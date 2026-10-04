"""
OTIF Guardian - Recovery Center
Deterministic recovery action evaluation and simulation.
"""

import streamlit as st
import sys
sys.path.insert(0, "..")
from lib.data import (
    get_recovery_portfolio, get_recovery_by_action_type,
    get_best_recovery_actions, get_recovery_for_po,
    get_prediction_time, get_model_version, fmt_dollar, fmt_number,
    get_executive_kpis, get_recovery_impact_summary,
    get_decision_assumptions, get_model_version_str,
)

# ── Page Header ──────────────────────────────────────────────
st.markdown("## 🔧 Recovery Center")
st.caption("Deterministic recovery action evaluation and simulation")

with st.expander("Engine Info", expanded=False):
    c1, c2, c3 = st.columns(3)
    with c1:
        try:
            mv = get_model_version()
            version = mv.get("DEFAULT_VERSION_NAME", mv.get("default_version_name", "N/A"))
        except Exception:
            version = "N/A"
        st.markdown(f"**Model:** `{version}`")
    with c2:
        st.markdown(f"**Last Run:** `{get_prediction_time()}`")
    with c3:
        st.markdown("**Decision Trace:** Deterministic SQL Engine (no LLM)")

st.markdown("---")

# ── Portfolio Summary ────────────────────────────────────────
st.markdown("### Recovery Portfolio Summary")

try:
    portfolio = get_recovery_portfolio()
    if not portfolio.empty:
        row = portfolio.iloc[0]

        # Top-line metrics
        col1, col2, col3, col4 = st.columns(4)
        with col1:
            st.metric("Addressable Lines", fmt_number(row.get("AT_RISK_LINES_ADDRESSABLE", 0)))
        with col2:
            st.metric("Revenue Protected", fmt_dollar(row.get("TOTAL_REVENUE_PROTECTED", 0)))
        with col3:
            st.metric("Incremental Cost", fmt_dollar(row.get("TOTAL_INCREMENTAL_COST", 0)))
        with col4:
            st.metric("Net Value Protected", fmt_dollar(row.get("TOTAL_NET_VALUE_PROTECTED", 0)))

        # Second row
        col5, col6, col7, col8 = st.columns(4)
        with col5:
            roi = row.get("PORTFOLIO_ROI_MULTIPLE", 0)
            st.metric("Portfolio ROI", f"{roi:.1f}x")
        with col6:
            st.metric("Expedites", fmt_number(row.get("RECOMMENDED_EXPEDITES", 0)))
        with col7:
            st.metric("Transfers", fmt_number(row.get("RECOMMENDED_TRANSFERS", 0)))
        with col8:
            st.metric("Alt Suppliers", fmt_number(row.get("RECOMMENDED_ALT_SUPPLIERS", 0)))
    else:
        st.info("No recovery data. Run the recovery engine first.")
except Exception as e:
    st.error(f"Failed to load portfolio: {e}")

# ── Before / After OTIF Projection ──────────────────────────
st.markdown("#### Projected Impact: Before vs After Recovery")

try:
    kpis = get_executive_kpis()
    rec = get_recovery_impact_summary()
    if not kpis.empty and rec["addressable"] > 0:
        current_otif = float(kpis.iloc[0]["INBOUND_OTIF_RATE"])
        otif_lift = rec["otif_lift"]

        b1, b2, b3 = st.columns(3)
        with b1:
            st.markdown(
                f'<div style="text-align:center; padding:0.8rem; border:2px solid #FF5630; border-radius:8px;">'
                f'<div style="font-size:0.8rem; color:#666;">CURRENT STATE</div>'
                f'<div style="font-size:1.5rem; font-weight:700; color:#FF5630;">{current_otif:.1f}%</div>'
                f'<div style="font-size:0.75rem; color:#888;">Inbound OTIF Rate</div>'
                f'</div>', unsafe_allow_html=True)
        with b2:
            st.markdown(
                f'<div style="text-align:center; padding:0.8rem;">'
                f'<div style="font-size:2rem; color:#666;">→</div>'
                f'<div style="font-size:0.85rem; font-weight:600; color:#36B37E;">+{otif_lift:.1f} pp lift</div>'
                f'<div style="font-size:0.75rem; color:#888;">{rec["feasible_actions"]} actions</div>'
                f'</div>', unsafe_allow_html=True)
        with b3:
            projected = min(current_otif + otif_lift, 100)
            st.markdown(
                f'<div style="text-align:center; padding:0.8rem; border:2px solid #36B37E; border-radius:8px;">'
                f'<div style="font-size:0.8rem; color:#666;">PROJECTED STATE</div>'
                f'<div style="font-size:1.5rem; font-weight:700; color:#36B37E;">{projected:.1f}%</div>'
                f'<div style="font-size:0.75rem; color:#888;">After all feasible actions</div>'
                f'</div>', unsafe_allow_html=True)

        st.markdown(
            f'<div style="background:#f0f8f0; padding:0.4rem 0.8rem; border-radius:4px; '
            f'font-size:0.78rem; color:#555; margin-top:0.5rem;">'
            f'Revenue protected: <b>{fmt_dollar(rec["revenue_protected"])}</b> &nbsp;|&nbsp; '
            f'Net value created: <b>{fmt_dollar(rec["net_value"])}</b> &nbsp;|&nbsp; '
            f'Portfolio ROI: <b>{abs(rec["portfolio_roi"]):.1f}x</b> &nbsp;|&nbsp; '
            f'Model: <b>{get_model_version_str()}</b> &nbsp;|&nbsp; '
            f'Timestamp: <b>{get_prediction_time()}</b>'
            f'</div>', unsafe_allow_html=True)
except Exception as e:
    st.warning(f"Before/after projection unavailable: {e}")

st.markdown("---")

# ── Action Type Breakdown ────────────────────────────────────
st.markdown("### Recovery by Action Type")

try:
    action_types = get_recovery_by_action_type()
    if not action_types.empty:
        st.dataframe(action_types, use_container_width=True)
    else:
        st.info("No action type data.")
except Exception as e:
    st.error(f"{e}")

st.markdown("---")

# ── Top Recommended Actions ──────────────────────────────────
st.markdown("### Top Recovery Recommendations")
st.caption("Ranked by Net Value Protected (highest first). All values from deterministic SQL calculations.")

limit = st.slider("Show top N actions", 10, 100, 25)

try:
    actions = get_best_recovery_actions(limit)
    if not actions.empty:
        display_df = actions.copy()
        for col in ["INCREMENTAL_COST", "REVENUE_PROTECTED", "NET_VALUE_PROTECTED"]:
            if col in display_df.columns:
                display_df[col] = display_df[col].apply(lambda x: fmt_dollar(x) if x is not None else "N/A")
        for col in ["SUCCESS_PROBABILITY", "BREACH_PROBABILITY"]:
            if col in display_df.columns:
                display_df[col] = display_df[col].apply(
                    lambda x: f"{x:.1%}" if x is not None else "N/A"
                )
        if "ROI_MULTIPLE" in display_df.columns:
            display_df["ROI_MULTIPLE"] = display_df["ROI_MULTIPLE"].apply(
                lambda x: f"{x:.1f}x" if x is not None else "N/A"
            )
        st.dataframe(display_df, use_container_width=True)
    else:
        st.info("No recommendations available.")
except Exception as e:
    st.error(f"{e}")

st.markdown("---")

# ── Single PO Line Simulation ────────────────────────────────
st.markdown("### Simulate Recovery for PO Line")
st.caption("Enter a PO Line ID to see all feasible recovery options with costs.")

c1, c2 = st.columns([3, 1])
with c1:
    po_line_id = st.number_input("PO Line ID", min_value=1, step=1, value=1, key="recovery_po")
with c2:
    st.markdown("")
    st.markdown("")
    sim_btn = st.button("Simulate Recovery")

if sim_btn:
    try:
        options = get_recovery_for_po(int(po_line_id))
        if not options.empty:
            st.success(f"Found {len(options)} feasible action(s) for PO Line {po_line_id}")

            display_df = options.copy()
            for col in ["INCREMENTAL_COST", "REVENUE_PROTECTED", "NET_VALUE_PROTECTED"]:
                if col in display_df.columns:
                    display_df[col] = display_df[col].apply(lambda x: fmt_dollar(x) if x is not None else "N/A")
            for col in ["SUCCESS_PROBABILITY"]:
                if col in display_df.columns:
                    display_df[col] = display_df[col].apply(
                        lambda x: f"{x:.1%}" if x is not None else "N/A"
                    )
            if "ROI_MULTIPLE" in display_df.columns:
                display_df["ROI_MULTIPLE"] = display_df["ROI_MULTIPLE"].apply(
                    lambda x: f"{x:.1f}x" if x is not None else "N/A"
                )
            st.dataframe(display_df, use_container_width=True)
            st.caption("All values computed by deterministic SQL engine. No LLM estimates.")
        else:
            st.warning("No feasible recovery actions for this PO line.")
    except Exception as e:
        st.error(f"{e}")

st.markdown("---")

# ── Decision Assumptions ────────────────────────────────────
with st.expander("Decision Assumptions (configurable)", expanded=False):
    st.caption("These parameters govern all recovery cost, success probability, and OTIF lift calculations. "
               "They are stored in OTIF_GUARDIAN.ML.DECISION_ASSUMPTIONS and can be updated without code changes.")
    try:
        assumptions = get_decision_assumptions()
        if not assumptions.empty:
            st.dataframe(assumptions, use_container_width=True, hide_index=True)
        else:
            st.info("No decision assumptions configured.")
    except Exception as e:
        st.warning(f"Unable to load assumptions: {e}")
