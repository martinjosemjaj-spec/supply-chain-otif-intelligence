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
    get_data_freshness, fmt_dollar, fmt_pct, fmt_number,
    get_risk_tier_distribution, get_recovery_impact_summary,
    get_dq_gate_status, get_model_version_str,
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

# ── Risk Tier Distribution (What is at risk?) ───────────────
st.markdown("### Risk Exposure by Tier")

try:
    tiers = get_risk_tier_distribution()
    if not tiers.empty:
        tier_cols = st.columns(len(tiers))
        tier_colors = {"CRITICAL": "#DE350B", "HIGH": "#FF5630", "MEDIUM": "#FFAB00", "LOW": "#36B37E"}
        for i, (_, row) in enumerate(tiers.iterrows()):
            tier = row["RISK_TIER"]
            color = tier_colors.get(tier, "#888")
            with tier_cols[i]:
                st.markdown(
                    f'<div style="border-left:4px solid {color}; padding:0.5rem 0.8rem; '
                    f'background:{color}10; border-radius:4px;">'
                    f'<div style="font-size:0.8rem; color:#666;">{tier}</div>'
                    f'<div style="font-size:1.2rem; font-weight:700;">{int(row["LINE_COUNT"])} lines</div>'
                    f'<div style="font-size:0.85rem; color:#444;">{fmt_dollar(row["TOTAL_VALUE"])} exposed</div>'
                    f'</div>', unsafe_allow_html=True)
    else:
        st.info("No risk tier data available.")
except Exception as e:
    st.warning(f"Risk tier data unavailable: {e}")

st.markdown("")

# ── Recovery Impact Summary (What to do? What happens?) ─────
st.markdown("### Recovery Impact")
st.caption("Projected impact if all feasible recovery actions are executed")

try:
    rec = get_recovery_impact_summary()
    r1, r2, r3, r4 = st.columns(4)
    with r1:
        st.metric("Addressable Lines", fmt_number(rec["addressable"]))
    with r2:
        st.metric("Revenue Protected", fmt_dollar(rec["revenue_protected"]))
    with r3:
        st.metric("Net Value Created", fmt_dollar(rec["net_value"]))
    with r4:
        st.metric("OTIF Lift (pp)", f"+{rec['otif_lift']:.1f}")
except Exception as e:
    st.warning(f"Recovery impact unavailable: {e}")

st.markdown("---")

# ── Trust Badge ─────────────────────────────────────────────
try:
    dq = get_dq_gate_status()
    gate = dq.get("gate_status", "UNKNOWN")
    gate_color = {"PASS": "#36B37E", "BLOCKED": "#DE350B"}.get(gate, "#FFAB00")
    mv_str = get_model_version_str()
    st.markdown(
        f'<div style="background:#f5f5f5; padding:0.5rem 1rem; border-radius:6px; '
        f'font-size:0.78rem; color:#666; display:flex; gap:2rem; align-items:center;">'
        f'<span>Model: <b>{mv_str}</b></span>'
        f'<span>DQ Gate: <b style="color:{gate_color}">{gate}</b> ({dq.get("passed",0)}/{dq.get("total_checks",0)})</span>'
        f'<span>Decision: <b>Deterministic SQL</b></span>'
        f'<span>Source: <b>Governed Semantic View</b></span>'
        f'</div>', unsafe_allow_html=True)
except Exception:
    pass

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
