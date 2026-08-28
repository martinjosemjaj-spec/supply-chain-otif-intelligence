"""
OTIF Guardian - Executive Dashboard
KPIs, trends, and high-level performance overview.
"""

import streamlit as st
import sys
sys.path.insert(0, "..")
from lib.data import (
    get_executive_kpis, get_customer_otif_kpis, get_monthly_otif_trend,
    get_otif_by_supplier_tier, get_model_version, get_prediction_time,
    get_data_freshness
)

st.title("Executive Dashboard")

# ── System Status Bar ─────────────────────────────────────────
with st.container():
    c1, c2, c3, c4 = st.columns(4)
    with c1:
        try:
            mv = get_model_version()
            version = mv.get("DEFAULT_VERSION_NAME", mv.get("default_version_name", "N/A"))
        except Exception:
            version = "N/A"
        st.caption(f"Model Version: **{version}**")
    with c2:
        pred_time = get_prediction_time()
        st.caption(f"Last Prediction: **{pred_time}**")
    with c3:
        st.caption("Decision Trace: **Deterministic SQL**")
    with c4:
        try:
            freshness = get_data_freshness()
            if not freshness.empty:
                latest = freshness["LAST_UPDATED"].max()
                st.caption(f"Data Freshness: **{latest}**")
            else:
                st.caption("Data Freshness: **Unknown**")
        except Exception:
            st.caption("Data Freshness: **Unknown**")

st.divider()

# ── KPI Row ───────────────────────────────────────────────────
st.subheader("Inbound Supply Performance")

try:
    kpis = get_executive_kpis()
    col1, col2, col3 = st.columns(3)
    with col1:
        rate = kpis.iloc[0]["INBOUND_OTIF_RATE"] if not kpis.empty else 0
        st.metric("Inbound OTIF Rate", f"{rate}%", delta=None)
    with col2:
        delivered = kpis.iloc[0]["TOTAL_DELIVERED"] if not kpis.empty else 0
        st.metric("Lines Delivered", f"{delivered:,.0f}")
    with col3:
        open_lines = kpis.iloc[0]["OPEN_LINES"] if not kpis.empty else 0
        st.metric("Open PO Lines", f"{open_lines:,.0f}")
except Exception as e:
    st.error(f"Failed to load inbound KPIs: {e}")

st.subheader("Customer Fulfillment")

try:
    co_kpis = get_customer_otif_kpis()
    col1, col2, col3 = st.columns(3)
    with col1:
        rate = co_kpis.iloc[0]["CUSTOMER_OTIF_RATE"] if not co_kpis.empty else 0
        st.metric("Customer OTIF Rate", f"{rate}%")
    with col2:
        open_orders = co_kpis.iloc[0]["OPEN_ORDERS"] if not co_kpis.empty else 0
        st.metric("Open Orders", f"{open_orders:,.0f}")
    with col3:
        rev_risk = co_kpis.iloc[0]["REVENUE_AT_RISK"] if not co_kpis.empty else 0
        st.metric("Revenue at Risk", f"${rev_risk:,.0f}")
except Exception as e:
    st.error(f"Failed to load customer KPIs: {e}")

st.divider()

# ── Trend Chart ───────────────────────────────────────────────
st.subheader("12-Month OTIF Trend")

try:
    trend = get_monthly_otif_trend()
    if not trend.empty:
        st.line_chart(trend.set_index("MONTH")["OTIF_RATE"], use_container_width=True)
    else:
        st.info("No trend data available.")
except Exception as e:
    st.error(f"Failed to load trend: {e}")

# ── Supplier Tier Breakdown ───────────────────────────────────
st.subheader("OTIF by Supplier Tier")

try:
    tier_data = get_otif_by_supplier_tier()
    if not tier_data.empty:
        st.bar_chart(
            tier_data.set_index("SUPPLIER_TIER")["OTIF_RATE"],
            use_container_width=True
        )
        st.dataframe(tier_data, use_container_width=True, hide_index=True)
    else:
        st.info("No tier data available.")
except Exception as e:
    st.error(f"Failed to load tier data: {e}")
