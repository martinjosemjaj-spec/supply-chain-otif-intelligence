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

# ── Page Header ──────────────────────────────────────────────
st.markdown("## ⚠️ Risk Center")
st.caption("ML-predicted breach risk visibility and drill-down")

with st.expander("Model Info", expanded=False):
    c1, c2, c3 = st.columns(3)
    with c1:
        try:
            mv = get_model_version()
            version = mv.get("DEFAULT_VERSION_NAME", mv.get("default_version_name", "N/A"))
        except Exception:
            version = "N/A"
        st.markdown(f"**Model:** `{version}` | **Trace:** Deterministic XGBoost")
    with c2:
        st.markdown(f"**Last Scored:** `{get_prediction_time()}`")
    with c3:
        st.markdown("**Explainability:** SHAP Reason Codes")

st.markdown("---")

# ── Risk Distribution ────────────────────────────────────────
st.markdown("### Risk Distribution")

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
                    f"{int(row['LINE_COUNT']):,} lines",
                    f"Avg: {row['AVG_PROBABILITY']:.1%}",
                )
    else:
        st.info("No scored data available. Run inference pipeline first.")
except Exception as e:
    st.error(f"Failed to load risk summary: {e}")

st.markdown("---")

# ── At-Risk Lines Table ──────────────────────────────────────
st.markdown("### At-Risk PO Lines")

tier_filter = st.selectbox(
    "Filter by risk tier",
    ["CRITICAL", "HIGH", "MEDIUM", "LOW", "MINIMAL"],
    index=0,
)

try:
    at_risk = get_at_risk_lines(tier_filter)
    if not at_risk.empty:
        st.caption(f"Showing {len(at_risk)} lines at **{tier_filter}** risk level")
        display_df = at_risk.copy()
        display_df["BREACH_PROBABILITY"] = display_df["BREACH_PROBABILITY"].apply(
            lambda x: f"{x:.1%}" if x is not None else "N/A"
        )
        display_df.columns = [
            "PO Number", "Supplier", "Material Code", "Material",
            "Plant", "Days Until Due", "Breach Prob.", "Risk Tier",
        ]
        st.dataframe(display_df, use_container_width=True)
    else:
        st.info(f"No lines at {tier_filter} risk level.")
except Exception as e:
    st.error(f"Failed to load at-risk lines: {e}")

st.markdown("---")

# ── Risk by Dimension ────────────────────────────────────────
tab1, tab2, tab3 = st.tabs(["By Supplier", "By Material", "Feature Importance"])

with tab1:
    st.markdown("#### High-Risk Suppliers")
    try:
        sup_risk = get_risk_by_supplier()
        if not sup_risk.empty:
            st.dataframe(sup_risk, use_container_width=True)
        else:
            st.info("No supplier risk data.")
    except Exception as e:
        st.error(f"{e}")

with tab2:
    st.markdown("#### High-Risk Materials")
    try:
        mat_risk = get_risk_by_material()
        if not mat_risk.empty:
            st.dataframe(mat_risk, use_container_width=True)
        else:
            st.info("No material risk data.")
    except Exception as e:
        st.error(f"{e}")

with tab3:
    st.markdown("#### Global Feature Importance")
    try:
        fi = get_feature_importance()
        if not fi.empty:
            st.bar_chart(fi.set_index("FEATURE_NAME")["IMPORTANCE_SCORE"], use_container_width=True)
            st.dataframe(fi, use_container_width=True)
        else:
            st.info("No feature importance data.")
    except Exception as e:
        st.error(f"{e}")

st.markdown("---")

# ── Reason Code Drill-Down ───────────────────────────────────
st.markdown("### Reason Code Drill-Down")
st.caption("Enter a PO Line ID to see why the model predicted a breach.")

c1, c2 = st.columns([3, 1])
with c1:
    po_line_input = st.number_input("PO Line ID", min_value=1, step=1, value=1)
with c2:
    st.markdown("")
    st.markdown("")
    run_btn = st.button("Get Reason Codes")

if run_btn:
    try:
        reasons = get_reason_codes_for_line(int(po_line_input))
        if not reasons.empty:
            st.dataframe(reasons, use_container_width=True)
            st.caption(
                "**Decision Trace:** SHAP contributions from XGBoost model. "
                "Positive = increases breach risk."
            )
        else:
            st.warning("No reason codes found for this PO line. It may not be in the high-risk set.")
    except Exception as e:
        st.error(f"{e}")
