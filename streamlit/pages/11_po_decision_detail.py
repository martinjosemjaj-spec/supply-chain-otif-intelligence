"""
OTIF Guardian - PO Decision Detail
Detailed view for a single PO line with risk evidence and recovery options.
Spec: SKILL.md S7
"""

import streamlit as st
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from lib.data import (
    get_po_detail, get_po_reason_codes, get_po_recovery_options,
    get_risk_command_center, get_model_version_str, get_prediction_time,
    get_scoring_time,
    fmt_dollar, fmt_prob, fmt_number, fmt_days, is_demo_mode, unavailable_msg,
)

# ── Header ───────────────────────────────────────────────────
st.markdown("### PO Decision Detail")
if is_demo_mode():
    st.warning("DEMO MODE — Synthetic data. Not connected to Snowflake.")

# ── PO Line Selector ────────────────────────────────────────
plant = st.session_state.get("filter_plant", "All")
bands = st.session_state.get("filter_bands", ["CRITICAL", "HIGH"])
min_rev = st.session_state.get("filter_min_revenue", 0)

available_lines = st.session_state.get("available_po_lines", [])
if not available_lines:
    try:
        df = get_risk_command_center(plant, bands, min_rev, limit=200)
        if not df.empty:
            available_lines = df["PO_LINE_ID"].tolist()
            st.session_state["available_po_lines"] = available_lines
    except Exception:
        pass

if not available_lines:
    st.info("No PO lines available in the current filter scope. "
            "Adjust filters in the sidebar or visit the Risk Command Center first.")
    st.stop()

selected_id = st.selectbox(
    "Select PO Line",
    options=available_lines,
    format_func=lambda x: f"PO Line {x}",
    key="po_detail_selector",
)

if selected_id is None:
    st.stop()

# ── Load Detail ──────────────────────────────────────────────
try:
    detail_df = get_po_detail(selected_id)
except Exception as e:
    st.error(f"Failed to load PO detail: {e}")
    st.stop()

if detail_df.empty:
    st.warning(f"No data found for PO Line {selected_id}.")
    st.stop()

row = detail_df.iloc[0]

# ── Risk Banner ──────────────────────────────────────────────
tier = row.get("RISK_TIER", "UNKNOWN")
tier_colors = {"CRITICAL": "#DE350B", "HIGH": "#FF8B00", "MEDIUM": "#FFAB00", "LOW": "#36B37E"}
color = tier_colors.get(tier, "#666")

st.markdown(
    f'<div style="background:{color}20; border-left:4px solid {color}; '
    f'padding:0.75rem 1rem; border-radius:4px; margin-bottom:1rem;">'
    f'<strong>PO Line {selected_id}</strong> — '
    f'<span style="color:{color}; font-weight:600;">{tier} RISK</span>'
    f'</div>',
    unsafe_allow_html=True,
)

# ── Model Provenance ─────────────────────────────────────────
with st.expander("Model & Scoring Provenance", expanded=False):
    p1, p2, p3 = st.columns(3)
    with p1:
        st.markdown(f"**Model Version:** `{get_model_version_str()}`")
    with p2:
        st.markdown(f"**Scoring Time:** `{get_scoring_time()}`")
    with p3:
        st.markdown(f"**Recovery Run:** `{get_prediction_time()}`")

# ── Key Metrics ──────────────────────────────────────────────
st.markdown("#### Risk Metrics")
c1, c2, c3, c4, c5 = st.columns(5)
with c1:
    st.metric("Breach Probability", fmt_prob(row.get("BREACH_PROBABILITY")))
with c2:
    st.metric("Days to Due", fmt_days(row.get("DAYS_UNTIL_DUE")))
with c3:
    st.metric("At-Risk Quantity", fmt_number(row.get("QUANTITY_ORDERED")))
with c4:
    st.metric("At-Risk Revenue", fmt_dollar(row.get("LINE_VALUE")))
with c5:
    st.metric("Supplier Tier", str(row.get("SUPPLIER_TIER", "N/A")))

# ── Dimensions ───────────────────────────────────────────────
st.markdown("#### Details")
d1, d2, d3 = st.columns(3)
with d1:
    st.markdown(f"**Supplier:** {row.get('SUPPLIER_NAME', 'N/A')}")
    st.markdown(f"**PO Number:** {row.get('PO_NUMBER', 'N/A')}")
with d2:
    st.markdown(f"**Part (Material):** {row.get('MATERIAL_CODE', 'N/A')}")
    st.markdown(f"**Category:** {row.get('MATERIAL_CATEGORY', 'N/A')}")
with d3:
    st.markdown(f"**Plant:** {row.get('PLANT_NAME', row.get('PLANT_CODE', 'N/A'))}")
    st.markdown(f"**Projected Receipt:** {row.get('PROMISED_DELIVERY_DATE', 'N/A')}")

# Unavailable fields
st.markdown("")
for field in ["CONFIRMED_DELIVERY_DATE", "PROJECTED_STOCKOUT_DATE",
              "SUPPLIER_OTIF_90D", "INVENTORY_DOS"]:
    pass  # Silently omit — listed in expander below

st.markdown("---")

# ── SHAP Reason Codes ────────────────────────────────────────
st.markdown("#### Risk Reason Codes (SHAP)")
st.caption("Per-prediction feature contributions from XGBoost model. "
           "Positive = increases breach risk.")

try:
    reasons = get_po_reason_codes(selected_id)
    if not reasons.empty:
        display_r = reasons.copy()
        display_r["SHAP_CONTRIBUTION"] = display_r["SHAP_CONTRIBUTION"].apply(
            lambda x: f"{x:+.4f}" if x is not None else "N/A"
        )
        display_r.columns = ["Feature", "SHAP Contribution", "Direction", "Rank"]
        st.dataframe(display_r, use_container_width=True)
    else:
        st.info("No SHAP reason codes available for this PO line.")
except Exception as e:
    st.error(f"Failed to load reason codes: {e}")

st.markdown("---")

# ── Recovery Comparison ──────────────────────────────────────
st.markdown("#### Recovery Options")
st.caption("Feasible recovery actions ranked by action rank, then net value protected. "
           "Read-only — human approval required before execution.")

try:
    recovery = get_po_recovery_options(selected_id)
    if not recovery.empty:
        display_rec = recovery.copy()
        # Format columns
        for col in ["INCREMENTAL_COST", "REVENUE_PROTECTED", "NET_VALUE_PROTECTED"]:
            if col in display_rec.columns:
                display_rec[col] = display_rec[col].apply(
                    lambda x: fmt_dollar(x) if x is not None else "N/A"
                )
        if "SUCCESS_PROBABILITY" in display_rec.columns:
            display_rec["SUCCESS_PROBABILITY"] = display_rec["SUCCESS_PROBABILITY"].apply(fmt_prob)
        if "OTIF_LIFT" in display_rec.columns:
            display_rec["OTIF_LIFT"] = display_rec["OTIF_LIFT"].apply(
                lambda x: f"{x:.2f} pp" if x is not None else "N/A"
            )
        if "ROI_MULTIPLE" in display_rec.columns:
            display_rec["ROI_MULTIPLE"] = display_rec["ROI_MULTIPLE"].apply(
                lambda x: f"{x:.1f}x" if x is not None else "N/A"
            )
        if "IS_FEASIBLE" in display_rec.columns:
            display_rec["IS_FEASIBLE"] = display_rec["IS_FEASIBLE"].apply(
                lambda x: "Yes" if x else "No"
            )
        if "WOULD_RESOLVE_BREACH" in display_rec.columns:
            display_rec["WOULD_RESOLVE_BREACH"] = display_rec["WOULD_RESOLVE_BREACH"].apply(
                lambda x: "Yes" if x else "No"
            )

        # Flag infeasible recommended actions
        if "ACTION_RANK" in display_rec.columns and "IS_FEASIBLE" in display_rec.columns:
            for idx, r in display_rec.iterrows():
                if r.get("ACTION_RANK") == 1 and r.get("IS_FEASIBLE") == "No":
                    st.warning(f"Top-ranked action '{r.get('ACTION_TYPE', '')}' is marked infeasible.")

        rename_map = {
            "ACTION_TYPE": "Action", "ACTION_DETAIL": "Detail",
            "IS_FEASIBLE": "Feasible", "WOULD_RESOLVE_BREACH": "Resolves Breach",
            "SUCCESS_PROBABILITY": "Success Prob.", "OTIF_LIFT": "OTIF Lift (pp)",
            "INCREMENTAL_COST": "Cost", "REVENUE_PROTECTED": "Revenue Protected",
            "NET_VALUE_PROTECTED": "Net Value", "ROI_MULTIPLE": "ROI",
            "ACTION_RANK": "Rank",
        }
        st.dataframe(
            display_rec.rename(columns=rename_map),
            use_container_width=True,
        )
    else:
        st.info("No recovery options available for this PO line.")
except Exception as e:
    st.error(f"Failed to load recovery options: {e}")

# ── Unavailable fields ───────────────────────────────────────
with st.expander("Unavailable prototype fields", expanded=False):
    for field in ["CONFIRMED_DELIVERY_DATE", "PROJECTED_STOCKOUT_DATE",
                  "SUPPLIER_OTIF_90D", "INVENTORY_DOS",
                  "REJECTION_REASON", "ACTION_QTY", "RECOVERED_UNITS", "ARRIVAL_DATE"]:
        st.markdown(f"- **{field}**: {unavailable_msg(field)}")

st.markdown("---")
st.caption("Decision support only — no ERP writes. All values from deterministic SQL engine.")
