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
    get_prediction_time, get_model_version
)

st.title("Recovery Center")

# ── Status Bar ────────────────────────────────────────────────
with st.container():
    c1, c2, c3 = st.columns(3)
    with c1:
        try:
            mv = get_model_version()
            version = mv.get("DEFAULT_VERSION_NAME", mv.get("default_version_name", "N/A"))
        except Exception:
            version = "N/A"
        st.caption(f"Model: **{version}**")
    with c2:
        st.caption(f"Last Run: **{get_prediction_time()}**")
    with c3:
        st.caption("Decision Trace: **Deterministic SQL Engine (no LLM)**")

st.divider()

# ── Portfolio Summary ─────────────────────────────────────────
st.subheader("Recovery Portfolio Summary")

try:
    portfolio = get_recovery_portfolio()
    if not portfolio.empty:
        row = portfolio.iloc[0]
        col1, col2, col3, col4 = st.columns(4)
        with col1:
            st.metric("Addressable Lines", f"{row.get('AT_RISK_LINES_ADDRESSABLE', 0):,.0f}")
        with col2:
            st.metric("Revenue Protected", f"${row.get('TOTAL_REVENUE_PROTECTED', 0):,.0f}")
        with col3:
            st.metric("Incremental Cost", f"${row.get('TOTAL_INCREMENTAL_COST', 0):,.0f}")
        with col4:
            st.metric("Net Value Protected", f"${row.get('TOTAL_NET_VALUE_PROTECTED', 0):,.0f}")

        col5, col6, col7, col8 = st.columns(4)
        with col5:
            st.metric("Portfolio ROI", f"{row.get('PORTFOLIO_ROI_MULTIPLE', 0):.1f}x")
        with col6:
            st.metric("Expedites", f"{row.get('RECOMMENDED_EXPEDITES', 0):,.0f}")
        with col7:
            st.metric("Transfers", f"{row.get('RECOMMENDED_TRANSFERS', 0):,.0f}")
        with col8:
            st.metric("Alt Suppliers", f"{row.get('RECOMMENDED_ALT_SUPPLIERS', 0):,.0f}")
    else:
        st.info("No recovery data. Run the recovery engine first.")
except Exception as e:
    st.error(f"Failed to load portfolio: {e}")

st.divider()

# ── Action Type Breakdown ─────────────────────────────────────
st.subheader("Recovery by Action Type")

try:
    action_types = get_recovery_by_action_type()
    if not action_types.empty:
        st.dataframe(
            action_types,
            use_container_width=True,
            hide_index=True,
            column_config={
                "NET_VALUE_PROTECTED": st.column_config.NumberColumn("Net Value Protected", format="$%.2f"),
                "INCREMENTAL_COST": st.column_config.NumberColumn("Incremental Cost", format="$%.2f"),
                "REVENUE_PROTECTED": st.column_config.NumberColumn("Revenue Protected", format="$%.2f"),
                "AVG_SUCCESS_PROB": st.column_config.ProgressColumn("Avg Success", min_value=0, max_value=1, format="%.2f"),
            }
        )
    else:
        st.info("No action type data.")
except Exception as e:
    st.error(f"{e}")

st.divider()

# ── Top Recommended Actions ───────────────────────────────────
st.subheader("Top Recovery Recommendations")
st.caption("Ranked by Net Value Protected (highest first). All values from deterministic SQL calculations.")

limit = st.slider("Show top N actions", 10, 100, 25)

try:
    actions = get_best_recovery_actions(limit)
    if not actions.empty:
        st.dataframe(
            actions,
            use_container_width=True,
            hide_index=True,
            column_config={
                "NET_VALUE_PROTECTED": st.column_config.NumberColumn("Net Value", format="$%.2f"),
                "INCREMENTAL_COST": st.column_config.NumberColumn("Cost", format="$%.2f"),
                "REVENUE_PROTECTED": st.column_config.NumberColumn("Revenue Saved", format="$%.2f"),
                "SUCCESS_PROBABILITY": st.column_config.ProgressColumn("Success", min_value=0, max_value=1),
                "BREACH_PROBABILITY": st.column_config.ProgressColumn("Risk", min_value=0, max_value=1),
                "ROI_MULTIPLE": st.column_config.NumberColumn("ROI", format="%.1fx"),
            }
        )
    else:
        st.info("No recommendations available.")
except Exception as e:
    st.error(f"{e}")

st.divider()

# ── Single PO Line Simulation ─────────────────────────────────
st.subheader("Simulate Recovery for PO Line")
st.caption("Enter a PO Line ID to see all feasible recovery options with costs.")

po_line_id = st.number_input("PO Line ID", min_value=1, step=1, value=1, key="recovery_po")

if st.button("Simulate Recovery"):
    try:
        options = get_recovery_for_po(int(po_line_id))
        if not options.empty:
            st.success(f"Found {len(options)} feasible action(s) for PO Line {po_line_id}")
            st.dataframe(
                options,
                use_container_width=True,
                hide_index=True,
                column_config={
                    "NET_VALUE_PROTECTED": st.column_config.NumberColumn("Net Value", format="$%.2f"),
                    "INCREMENTAL_COST": st.column_config.NumberColumn("Cost", format="$%.2f"),
                    "REVENUE_PROTECTED": st.column_config.NumberColumn("Revenue Saved", format="$%.2f"),
                    "SUCCESS_PROBABILITY": st.column_config.ProgressColumn("Success", min_value=0, max_value=1),
                    "ROI_MULTIPLE": st.column_config.NumberColumn("ROI", format="%.1fx"),
                }
            )
            st.caption("All values computed by deterministic SQL engine. No LLM estimates.")
        else:
            st.warning("No feasible recovery actions for this PO line.")
    except Exception as e:
        st.error(f"{e}")
