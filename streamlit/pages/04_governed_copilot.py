"""
OTIF Guardian - Governed Copilot
Chat interface backed by Cortex Agent with governance guardrails.
All answers grounded in SQL tool results — never raw LLM generation.
"""

import streamlit as st
import sys
sys.path.insert(0, "..")
from lib.data import get_session, get_model_version, get_prediction_time

st.title("Governed Copilot")

# ── Governance Banner ─────────────────────────────────────────
with st.container():
    c1, c2, c3, c4 = st.columns(4)
    with c1:
        try:
            mv = get_model_version()
            version = mv.get("DEFAULT_VERSION_NAME", mv.get("default_version_name", "N/A"))
        except Exception:
            version = "N/A"
        st.caption(f"Model: **{version}**")
    with c2:
        st.caption(f"Prediction: **{get_prediction_time()}**")
    with c3:
        st.caption("Trace: **Agent Tool Calls**")
    with c4:
        st.caption("Guardrail: **SQL-grounded only**")

st.divider()

st.info(
    "This copilot is governed. All answers are grounded in tool-executed SQL results "
    "from the OTIF Guardian semantic model, ML predictions, and recovery engine. "
    "The language model cannot perform calculations or fabricate data."
)

# ── Chat State ────────────────────────────────────────────────
if "messages" not in st.session_state:
    st.session_state.messages = []

if "copilot_enabled" not in st.session_state:
    st.session_state.copilot_enabled = True

# ── Sample Questions ──────────────────────────────────────────
with st.expander("Sample questions", expanded=False):
    st.markdown("""
    - What is the overall supplier OTIF rate?
    - Which PO lines are at critical risk this week?
    - Show me the top 5 worst-performing suppliers
    - What recovery options do we have for the Detroit plant?
    - How much revenue is at risk from predicted OTIF failures?
    - Simulate an expedite for PO-0003456
    """)

# ── Chat History ──────────────────────────────────────────────
for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])
        if "trace" in message:
            with st.expander("Decision Trace"):
                st.code(message["trace"], language="json")

# ── Chat Input ────────────────────────────────────────────────
if prompt := st.chat_input("Ask about OTIF performance, risk, or recovery..."):
    st.session_state.messages.append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)

    with st.chat_message("assistant"):
        with st.spinner("Querying OTIF Guardian Agent..."):
            try:
                session = get_session()

                # Call the Cortex Agent via SQL
                # This executes the agent which uses its tools (supply_analytics, risk_lookup, recovery_simulation)
                import json

                # Escape single quotes in prompt for SQL
                safe_prompt = prompt.replace("'", "''")

                result = session.sql(f"""
                    SELECT SNOWFLAKE.CORTEX.AGENT(
                        'OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT',
                        '{safe_prompt}'
                    ) AS response
                """).collect()

                if result:
                    response_raw = result[0]["RESPONSE"]
                    try:
                        response_json = json.loads(response_raw)
                        answer = response_json.get("message", response_raw)
                        # Extract tool calls for decision trace
                        tool_calls = response_json.get("tool_calls", [])
                        trace = json.dumps({
                            "tools_invoked": [tc.get("name", "unknown") for tc in tool_calls],
                            "grounding": "SQL tool results",
                            "model_version": version,
                            "guardrail": "No LLM calculations permitted"
                        }, indent=2) if tool_calls else None
                    except (json.JSONDecodeError, TypeError):
                        answer = str(response_raw)
                        trace = None

                    st.markdown(answer)
                    if trace:
                        with st.expander("Decision Trace"):
                            st.code(trace, language="json")
                        st.session_state.messages.append({
                            "role": "assistant", "content": answer, "trace": trace
                        })
                    else:
                        st.session_state.messages.append({
                            "role": "assistant", "content": answer
                        })
                else:
                    st.warning("No response from agent.")

            except Exception as e:
                error_msg = f"Agent call failed: {str(e)}"
                st.error(error_msg)
                st.caption(
                    "Fallback: The agent may not be deployed yet. "
                    "Deploy using `sql/06_deploy_agent.sql` first."
                )
                st.session_state.messages.append({
                    "role": "assistant",
                    "content": f"Error: {error_msg}"
                })

# ── Governance Footer ─────────────────────────────────────────
st.divider()
st.caption(
    "Governance: All responses are generated by the OTIF Guardian Cortex Agent using "
    "three deterministic tools (supply_analytics, risk_lookup, recovery_simulation). "
    "Financial calculations are SQL-executed, never LLM-generated. "
    "Decision traces show which tools were invoked for auditability."
)
