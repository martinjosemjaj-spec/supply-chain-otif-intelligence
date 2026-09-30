"""
OTIF Guardian - Governed Copilot
Chat interface backed by Cortex Agent with governance guardrails.
All answers grounded in SQL tool results — never raw LLM generation.
"""

import streamlit as st
import sys
sys.path.insert(0, "..")
from lib.data import get_session, get_model_version, get_prediction_time

# ── Page Header ──────────────────────────────────────────────
st.markdown("## 💬 Governed Copilot")
st.caption("Ask questions about OTIF performance, risk, and recovery")

# ── Governance Banner ────────────────────────────────────────
with st.expander("Governance Info", expanded=False):
    c1, c2, c3, c4 = st.columns(4)
    with c1:
        try:
            mv = get_model_version()
            version = mv.get("DEFAULT_VERSION_NAME", mv.get("default_version_name", "N/A"))
        except Exception:
            version = "N/A"
        st.markdown(f"**Model:** `{version}`")
    with c2:
        st.markdown(f"**Prediction:** `{get_prediction_time()}`")
    with c3:
        st.markdown("**Trace:** Agent Tool Calls")
    with c4:
        st.markdown("**Guardrail:** SQL-grounded only")

st.info(
    "🔒 **Governed mode active.** All answers are grounded in SQL tool results "
    "from the OTIF Guardian semantic model. The language model cannot fabricate data."
)

# ── Chat State ───────────────────────────────────────────────
if "messages" not in st.session_state:
    st.session_state.messages = []

# ── Sample Questions ─────────────────────────────────────────
with st.expander("💡 Sample questions", expanded=False):
    st.markdown("""
- What is the overall supplier OTIF rate?
- Which PO lines are at critical risk this week?
- Show me the top 5 worst-performing suppliers
- What recovery options do we have for the Detroit plant?
- How much revenue is at risk from predicted OTIF failures?
""")

st.markdown("---")

# ── Chat History ─────────────────────────────────────────────
for message in st.session_state.messages:
    role = message["role"]
    content = message["content"]
    if role == "user":
        st.markdown(
            f'<div style="background:#e8f4f8; padding:0.75rem 1rem; border-radius:8px; '
            f'margin-bottom:0.5rem;"><strong>You:</strong> {content}</div>',
            unsafe_allow_html=True,
        )
    else:
        st.markdown(
            f'<div style="background:#f0f2f6; padding:0.75rem 1rem; border-radius:8px; '
            f'margin-bottom:0.5rem;"><strong>Assistant:</strong><br>{content}</div>',
            unsafe_allow_html=True,
        )
    if "trace" in message:
        with st.expander("🔍 Decision Trace"):
            st.code(message["trace"], language="json")

# ── Chat Input ───────────────────────────────────────────────
st.markdown("---")

c1, c2 = st.columns([5, 1])
with c1:
    prompt = st.text_input(
        "Your question",
        placeholder="Ask about OTIF performance, risk, or recovery...",
        key="copilot_input",
        label_visibility="collapsed",
    )
with c2:
    send_btn = st.button("Send ➤", use_container_width=True)

if send_btn and prompt:
    st.session_state.messages.append({"role": "user", "content": prompt})

    with st.spinner("Querying OTIF Guardian Agent..."):
        try:
            session = get_session()
            import json

            request_body = json.dumps({
                "messages": [
                    {
                        "role": "user",
                        "content": [{"type": "text", "text": prompt}]
                    }
                ]
            })
            safe_body = request_body.replace("'", "''")

            result = session.sql(f"""
                SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
                    'OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT',
                    '{safe_body}'
                ) AS response
            """).collect()

            if result:
                response_raw = result[0]["RESPONSE"]
                try:
                    response_json = json.loads(response_raw) if isinstance(response_raw, str) else response_raw
                    content_parts = response_json.get("content", [])
                    answer_parts = []
                    tool_names = []
                    for part in content_parts:
                        if part.get("type") == "text":
                            answer_parts.append(part.get("text", ""))
                        elif part.get("type") == "tool_use":
                            tool_names.append(part.get("tool_use", {}).get("name", "unknown"))
                    answer = "\n".join(answer_parts) if answer_parts else str(response_raw)
                    trace = json.dumps({
                        "tools_invoked": tool_names,
                        "grounding": "SQL tool results",
                        "guardrail": "No LLM calculations permitted"
                    }, indent=2) if tool_names else None
                except (json.JSONDecodeError, TypeError):
                    answer = str(response_raw)
                    trace = None

                msg = {"role": "assistant", "content": answer}
                if trace:
                    msg["trace"] = trace
                st.session_state.messages.append(msg)

                st.markdown(
                    f'<div style="background:#f0f2f6; padding:0.75rem 1rem; border-radius:8px; '
                    f'margin-bottom:0.5rem;"><strong>Assistant:</strong><br>{answer}</div>',
                    unsafe_allow_html=True,
                )
                if trace:
                    with st.expander("🔍 Decision Trace"):
                        st.code(trace, language="json")
            else:
                st.warning("No response from agent.")

        except Exception as e:
            error_msg = f"Agent call failed: {str(e)}"
            st.error(error_msg)
            st.caption(
                "The agent may not be deployed yet. "
                "Deploy using `sql/06_deploy_agent.sql` first."
            )
            st.session_state.messages.append({
                "role": "assistant",
                "content": f"Error: {error_msg}"
            })

# ── Governance Footer ────────────────────────────────────────
st.markdown("---")
st.caption(
    "**Governance:** All responses are generated by the OTIF Guardian Cortex Agent using "
    "three deterministic tools (supply_analytics, risk_lookup, recovery_simulation). "
    "Financial calculations are SQL-executed, never LLM-generated."
)
