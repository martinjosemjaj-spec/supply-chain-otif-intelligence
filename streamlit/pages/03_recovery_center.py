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
    get_prediction_time, get_model_version, fmt_dollar, fmt_number
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
