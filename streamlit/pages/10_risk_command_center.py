"""
OTIF Guardian - Risk Command Center
Prioritized inbound risk with revenue exposure by plant.
Spec: SKILL.md S6
"""

import streamlit as st
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from lib.data import (
    get_risk_command_center, get_risk_kpi_metrics, get_revenue_by_plant,
    fmt_dollar, fmt_prob, fmt_number, fmt_days, is_demo_mode, unavailable_msg,
)
from lib.config import COMMAND_CENTER_PAGE_SIZE

# ── Header ───────────────────────────────────────────────────
st.markdown("### Prioritized Inbound Risk")
if is_demo_mode():
    st.warning("DEMO MODE — Synthetic data. Not connected to Snowflake.")

# ── Read shared filters from session state ───────────────────
plant = st.session_state.get("filter_plant", "All")
bands = st.session_state.get("filter_bands", ["CRITICAL", "HIGH"])
min_rev = st.session_state.get("filter_min_revenue", 0)

if not bands:
    st.info("No risk bands selected. Select at least one band in the sidebar.")
    st.stop()

# ── KPI Cards ────────────────────────────────────────────────
try:
    kpis = get_risk_kpi_metrics(plant, bands, min_rev)
    if not kpis.empty:
        row = kpis.iloc[0]
        c1, c2, c3, c4 = st.columns(4)
        with c1:
            st.metric("Open PO Lines Scored", fmt_number(row.get("SCORED_LINES", 0)))
        with c2:
            st.metric("Critical Risk Lines", fmt_number(row.get("CRITICAL_LINES", 0)))
        with c3:
            st.metric("Revenue at Risk", fmt_dollar(row.get("TOTAL_REVENUE_AT_RISK", 0)))
        with c4:
            avg_p = row.get("AVG_BREACH_PROBABILITY")
            st.metric("Avg Breach Prob. (unweighted mean)",
                      fmt_prob(avg_p) if avg_p is not None else "N/A")
    else:
        st.info("No data matching current filters.")
except Exception as e:
    st.error(f"Failed to load KPIs: {e}")

st.markdown("---")

# ── Two-column layout (~1.45:1) ──────────────────────────────
left, right = st.columns([3, 2])

with left:
    st.markdown("#### Risk Table")
    try:
        df = get_risk_command_center(plant, bands, min_rev, limit=COMMAND_CENTER_PAGE_SIZE)
        if not df.empty:
            display = df.copy()
            display["BREACH_PROBABILITY"] = display["BREACH_PROBABILITY"].apply(fmt_prob)
            display["LINE_VALUE"] = display["LINE_VALUE"].apply(fmt_dollar)
            display["QUANTITY_ORDERED"] = display["QUANTITY_ORDERED"].apply(fmt_number)
            display["DAYS_UNTIL_DUE"] = display["DAYS_UNTIL_DUE"].apply(fmt_days)

            show_cols = [
                "PO_LINE_ID", "SUPPLIER_NAME", "MATERIAL_CODE", "PLANT_NAME",
                "RISK_TIER", "BREACH_PROBABILITY", "DAYS_UNTIL_DUE",
                "QUANTITY_ORDERED", "LINE_VALUE",
            ]
            available = [c for c in show_cols if c in display.columns]
            renames = {
                "PO_LINE_ID": "PO Line", "SUPPLIER_NAME": "Supplier",
                "MATERIAL_CODE": "Part (Material)", "PLANT_NAME": "Plant",
                "RISK_TIER": "Risk Band", "BREACH_PROBABILITY": "Breach Prob.",
                "DAYS_UNTIL_DUE": "Days to Due", "QUANTITY_ORDERED": "At-Risk Qty",
                "LINE_VALUE": "At-Risk Revenue",
            }
            st.dataframe(
                display[available].rename(columns=renames),
                use_container_width=True,
                height=500,
            )
            st.caption(f"Showing {len(display)} lines. Sorted by breach probability desc, "
                       f"revenue desc, PO Line ID.")

            # Store PO line IDs for selection in PO Detail page
            st.session_state["available_po_lines"] = df["PO_LINE_ID"].tolist()
        else:
            st.info("No PO lines match the current filters.")
    except Exception as e:
        st.error(f"Failed to load risk table: {e}")

with right:
    st.markdown("#### Revenue Exposure by Plant")
    try:
        plant_df = get_revenue_by_plant(plant, bands, min_rev)
        if not plant_df.empty:
            st.bar_chart(
                plant_df.set_index("PLANT_NAME")["REVENUE"],
                use_container_width=True,
            )
            st.caption("Scoped to current filters")

            avg_prob = plant_df["AVG_BREACH_PROB"].mean()
            st.markdown(f"**Avg breach probability (current scope):** {fmt_prob(avg_prob)}")

            for _, r in plant_df.iterrows():
                st.markdown(
                    f"- **{r['PLANT_NAME']}**: {fmt_dollar(r['REVENUE'])} "
                    f"(avg prob: {fmt_prob(r['AVG_BREACH_PROB'])})"
                )
        else:
            st.info("No plant exposure data for current filters.")
    except Exception as e:
        st.error(f"Failed to load plant exposure: {e}")

# ── Unavailable fields notice ────────────────────────────────
with st.expander("Unavailable prototype fields", expanded=False):
    st.caption("The following prototype fields require additional data sources:")
    for field in ["EXPOSURE_SCORE", "PROJECTED_CUSTOMER_OTIF_PCT",
                  "SUPPLIER_OTIF_90D", "INVENTORY_DOS"]:
        st.markdown(f"- **{field}**: {unavailable_msg(field)}")
