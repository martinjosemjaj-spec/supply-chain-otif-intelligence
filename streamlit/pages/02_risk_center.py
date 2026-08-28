"""
OTIF Guardian - Risk Center
ML-predicted breach risk visibility with drill-down.
"""

import streamlit as st
import sys
sys.path.insert(0, "..")
from lib.data import (
    get_risk_summary, get_at_risk_lines, get_risk_by_supplier,
    get_risk_by_material, get_feature_importance, get_reason_codes_for_line,
    get_model_version, get_prediction_time
)

st.title("Risk Center")

# ── Status Bar ────────────────────────────────────────────────
with st.container():
    c1, c2, c3 = st.columns(3)
    with c1:
        try:
            mv = get_model_version()
            version = mv.get("DEFAULT_VERSION_NAME", mv.get("default_version_name", "N/A"))
        except Exception:
            version = "N/A"
        st.caption(f"Model: **{version}** | Trace: Deterministic XGBoost")
    with c2:
        st.caption(f"Last Scored: **{get_prediction_time()}**")
    with c3:
        st.caption("Explainability: **SHAP Reason Codes**")

st.divider()

# ── Risk Distribution ─────────────────────────────────────────
st.subheader("Risk Distribution")

try:
    risk_summary = get_risk_summary()
    if not risk_summary.empty:
        cols = st.columns(len(risk_summary))
        colors = {"CRITICAL": "🔴", "HIGH": "🟠", "MEDIUM": "🟡", "LOW": "🟢", "MINIMAL": "⚪"}
        for i, row in risk_summary.iterrows():
            tier = row["RISK_TIER"]
            with cols[i]:
                st.metric(
                    f"{colors.get(tier, '')} {tier}",
                    f"{row['LINE_COUNT']} lines",
                    f"Avg: {row['AVG_PROBABILITY']:.1%}"
                )
    else:
        st.info("No scored data available. Run inference pipeline first.")
except Exception as e:
    st.error(f"Failed to load risk summary: {e}")

st.divider()

# ── At-Risk Lines Table ───────────────────────────────────────
st.subheader("At-Risk PO Lines")

tier_filter = st.selectbox(
    "Filter by risk tier",
    ["CRITICAL", "HIGH", "MEDIUM", "LOW", "MINIMAL"],
    index=0
)

try:
    at_risk = get_at_risk_lines(tier_filter)
    if not at_risk.empty:
        st.dataframe(
            at_risk,
            use_container_width=True,
            hide_index=True,
            column_config={
                "BREACH_PROBABILITY": st.column_config.ProgressColumn(
                    "Breach Prob", min_value=0, max_value=1, format="%.2f"
                ),
                "DAYS_UNTIL_DUE": st.column_config.NumberColumn("Days Until Due"),
            }
        )
    else:
        st.info(f"No lines at {tier_filter} risk level.")
except Exception as e:
    st.error(f"Failed to load at-risk lines: {e}")

st.divider()

# ── Risk by Dimension ─────────────────────────────────────────
tab1, tab2, tab3 = st.tabs(["By Supplier", "By Material", "Feature Importance"])

with tab1:
    st.subheader("High-Risk Suppliers")
    try:
        sup_risk = get_risk_by_supplier()
        if not sup_risk.empty:
            st.dataframe(sup_risk, use_container_width=True, hide_index=True)
        else:
            st.info("No supplier risk data.")
    except Exception as e:
        st.error(f"{e}")

with tab2:
    st.subheader("High-Risk Materials")
    try:
        mat_risk = get_risk_by_material()
        if not mat_risk.empty:
            st.dataframe(mat_risk, use_container_width=True, hide_index=True)
        else:
            st.info("No material risk data.")
    except Exception as e:
        st.error(f"{e}")

with tab3:
    st.subheader("Global Feature Importance")
    try:
        fi = get_feature_importance()
        if not fi.empty:
            st.bar_chart(fi.set_index(fi.columns[0])[fi.columns[1]], use_container_width=True)
            st.dataframe(fi, use_container_width=True, hide_index=True)
        else:
            st.info("No feature importance data.")
    except Exception as e:
        st.error(f"{e}")

st.divider()

# ── Reason Code Drill-Down ────────────────────────────────────
st.subheader("Reason Code Drill-Down")
st.caption("Enter a PO Line ID to see why the model predicted a breach.")

po_line_input = st.number_input("PO Line ID", min_value=1, step=1, value=1)

if st.button("Get Reason Codes"):
    try:
        reasons = get_reason_codes_for_line(int(po_line_input))
        if not reasons.empty:
            st.dataframe(reasons, use_container_width=True, hide_index=True)
            st.caption("Decision Trace: SHAP contributions from XGBoost model. Positive = increases breach risk.")
        else:
            st.warning("No reason codes found for this PO line. It may not be in the high-risk set.")
    except Exception as e:
        st.error(f"{e}")
