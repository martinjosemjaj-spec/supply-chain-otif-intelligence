"""
OTIF Guardian - Governed Copilot (v2)
Agent-backed Q&A with suggested questions, evidence, and governance guardrails.
Spec: SKILL.md S8
"""

import streamlit as st
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from lib.data import run_agent_query, is_demo_mode, get_system_status

# ── Header ───────────────────────────────────────────────────
st.markdown("### Governed Copilot")
st.caption("Ask questions grounded in governed SQL tool results")

if is_demo_mode():
    st.warning("DEMO MODE — Responses are synthetic and clearly labelled.")

st.info(
    "🔒 **Governed mode active.** All answers are derived from approved read-only SQL tools. "
    "The language model routes and explains — it does not perform calculations or fabricate data. "
    "Decision support only — no ERP writes."
)

# ── Session State ────────────────────────────────────────────
if "copilot_history" not in st.session_state:
    st.session_state.copilot_history = []

# ── Clear History ────────────────────────────────────────────
if st.session_state.copilot_history:
    if st.button("Clear conversation", key="clear_copilot"):
        st.session_state.copilot_history = []
        st.rerun()

# ── Suggested Questions ──────────────────────────────────────
st.markdown("#### Suggested Questions")

selected_po = st.session_state.get("po_detail_selector")
plant = st.session_state.get("filter_plant", "All")

suggestions = [
    "Which inbound orders threaten customer OTIF?"
    + (f" at {plant}" if plant != "All" else ""),
    "Which suppliers have the most revenue at risk?",
]
if selected_po:
    suggestions.insert(1, f"Why is PO line {selected_po} high risk?")
    suggestions.append(f"What is the best feasible recovery action for PO line {selected_po}?")

cols = st.columns(min(len(suggestions), 4))
clicked_suggestion = None
for i, s in enumerate(suggestions[:4]):
    with cols[i]:
        if st.button(s, key=f"suggest_{i}", use_container_width=True):
            clicked_suggestion = s

st.markdown("---")

# ── Chat History ─────────────────────────────────────────────
for entry in st.session_state.copilot_history:
    role = entry["role"]
    content = entry["content"]
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
    if "trace" in entry and entry["trace"]:
        with st.expander("Evidence / Raw Response"):
            st.code(entry["trace"], language="json")

# ── Input ────────────────────────────────────────────────────
st.markdown("---")
c1, c2 = st.columns([5, 1])
with c1:
    user_input = st.text_input(
        "Your question",
        value=clicked_suggestion or "",
        placeholder="Ask about OTIF performance, risk, or recovery...",
        key="copilot_v2_input",
        label_visibility="collapsed",
    )
with c2:
    send_btn = st.button("Send ➤", use_container_width=True, key="copilot_v2_send")

if (send_btn or clicked_suggestion) and user_input and user_input.strip():
    question = user_input.strip()
    if len(question) > 2000:
        st.error("Question too long (max 2000 characters).")
    else:
        st.session_state.copilot_history.append({"role": "user", "content": question})

        with st.spinner("Querying OTIF Guardian Agent..."):
            try:
                answer, trace, raw = run_agent_query(question)
                entry = {"role": "assistant", "content": answer}
                if trace:
                    entry["trace"] = trace
                st.session_state.copilot_history.append(entry)

                st.markdown(
                    f'<div style="background:#f0f2f6; padding:0.75rem 1rem; border-radius:8px; '
                    f'margin-bottom:0.5rem;"><strong>Assistant:</strong><br>{answer}</div>',
                    unsafe_allow_html=True,
                )
                if trace:
                    with st.expander("Evidence / Raw Response"):
                        st.code(trace, language="json")

                # Evidence badges
                _s = get_system_status()
                st.markdown(
                    f'<div style="display:flex; gap:1rem; font-size:0.78rem; color:#666; '
                    f'margin-top:0.3rem;">'
                    f'<span>Source: governed SQL tools</span>'
                    f'<span>Model: {_s["model_version"]}</span>'
                    f'<span>Data as of: {_s["data_freshness"]}</span>'
                    f'<span>Calculation: deterministic</span>'
                    f'</div>',
                    unsafe_allow_html=True,
                )
            except Exception as e:
                error_msg = f"Agent call failed: {e}"
                st.error(error_msg)
                st.session_state.copilot_history.append({
                    "role": "assistant", "content": f"Error: {error_msg}"
                })

# ── Footer ───────────────────────────────────────────────────
st.markdown("---")
st.caption(
    "**Governance:** Responses generated by the OTIF Guardian Cortex Agent using "
    "approved read-only SQL tools against the semantic model. "
    "No autonomous actions. No ERP writes."
)
if is_demo_mode():
    st.caption("**Demo responses are deterministic and not from an LLM.**")
