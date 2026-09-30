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
    get_data_freshness, fmt_dollar, fmt_pct, fmt_number
)

# ── Page Header ──────────────────────────────────────────────
st.markdown("## 📊 Executive Dashboard")
st.caption("Real-time supply chain performance overview")

# ── System Status Bar ────────────────────────────────────────
with st.expander("System Status", expanded=False):
    s1, s2, s3, s4 = st.columns(4)
    with s1:
        try:
            mv = get_model_version()
            version = mv.get("DEFAULT_VERSION_NAME", mv.get("default_version_name", "N/A"))
        except Exception:
            version = "N/A"
        st.markdown(f"**Model:** `{version}`")
    with s2:
        st.markdown(f"**Last Prediction:** `{get_prediction_time()}`")
    with s3:
        st.markdown("**Decision Trace:** `Deterministic SQL`")
    with s4:
        try:
            freshness = get_data_freshness()
            if not freshness.empty:
                latest = freshness["LAST_UPDATED"].max()
                st.markdown(f"**Data Freshness:** `{latest}`")
            else:
                st.markdown("**Data Freshness:** `Unknown`")
        except Exception:
            st.markdown("**Data Freshness:** `Unknown`")

st.markdown("---")

# ── Inbound Supply Performance ───────────────────────────────
st.markdown("### Inbound Supply Performance")

try:
    kpis = get_executive_kpis()
    col1, col2, col3 = st.columns(3)
    if not kpis.empty:
        rate = kpis.iloc[0]["INBOUND_OTIF_RATE"]
        delivered = kpis.iloc[0]["TOTAL_DELIVERED"]
        open_lines = kpis.iloc[0]["OPEN_LINES"]

        with col1:
            st.metric("Inbound OTIF Rate", fmt_pct(rate))
        with col2:
            st.metric("Lines Delivered", fmt_number(delivered))
        with col3:
            st.metric("Open PO Lines", fmt_number(open_lines))
    else:
        st.info("No inbound KPI data available.")
except Exception as e:
    st.error(f"Failed to load inbound KPIs: {e}")

st.markdown("")

# ── Customer Fulfillment ─────────────────────────────────────
st.markdown("### Customer Fulfillment")

try:
    co_kpis = get_customer_otif_kpis()
    col1, col2, col3 = st.columns(3)
    if not co_kpis.empty:
        rate = co_kpis.iloc[0]["CUSTOMER_OTIF_RATE"]
        open_orders = co_kpis.iloc[0]["OPEN_ORDERS"]
        rev_risk = co_kpis.iloc[0]["REVENUE_AT_RISK"]

        with col1:
            st.metric("Customer OTIF Rate", fmt_pct(rate))
        with col2:
            st.metric("Open Orders", fmt_number(open_orders))
        with col3:
            st.metric("Revenue at Risk", fmt_dollar(rev_risk))
    else:
        st.info("No customer KPI data available.")
except Exception as e:
    st.error(f"Failed to load customer KPIs: {e}")

st.markdown("---")

# ── 12-Month OTIF Trend ─────────────────────────────────────
st.markdown("### 12-Month OTIF Trend")

try:
    trend = get_monthly_otif_trend()
    if not trend.empty:
        st.line_chart(trend.set_index("MONTH")["OTIF_RATE"], use_container_width=True)
    else:
        st.info("No trend data available.")
except Exception as e:
    st.error(f"Failed to load trend: {e}")

# ── OTIF by Supplier Tier ───────────────────────────────────
st.markdown("### OTIF by Supplier Tier")

try:
    tier_data = get_otif_by_supplier_tier()
    if not tier_data.empty:
        c1, c2 = st.columns([2, 3])
        with c1:
            st.bar_chart(
                tier_data.set_index("SUPPLIER_TIER")["OTIF_RATE"],
                use_container_width=True,
            )
        with c2:
            display_df = tier_data.copy()
            display_df["OTIF_RATE"] = display_df["OTIF_RATE"].apply(lambda x: f"{x:.1f}%")
            display_df["TOTAL_LINES"] = display_df["TOTAL_LINES"].apply(lambda x: f"{x:,}")
            display_df.columns = ["Tier", "Total Lines", "OTIF Rate"]
            st.dataframe(display_df, use_container_width=True)
    else:
        st.info("No tier data available.")
except Exception as e:
    st.error(f"Failed to load tier data: {e}")
