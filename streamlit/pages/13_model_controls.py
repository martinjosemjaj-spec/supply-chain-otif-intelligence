"""
OTIF Guardian - Model & Controls
Real model metrics, governance controls, and provenance evidence.
Spec: SKILL.md S10
"""

import streamlit as st
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from lib.data import (
    get_model_version_str, get_model_metrics, get_confusion_matrix,
    get_feature_importance, get_data_freshness, get_prediction_time,
    get_scoring_time, run_query, is_demo_mode, fmt_number,
)
from lib.config import OBJECTS

# ── Header ───────────────────────────────────────────────────
st.markdown("### Model & Controls")
st.caption("Model performance, governance controls, and data provenance")

if is_demo_mode():
    st.warning("DEMO MODE — Metrics shown are from demo fixtures, not a production model.")

st.markdown("---")

# ── Model Version & Provenance ───────────────────────────────
st.markdown("#### Model Provenance")

c1, c2, c3 = st.columns(3)
with c1:
    st.metric("Model Version", get_model_version_str())
with c2:
    st.metric("Last Scoring", str(get_scoring_time()))
with c3:
    st.metric("Last Recovery Run", str(get_prediction_time()))

st.markdown("---")

# ── Performance Metrics ──────────────────────────────────────
st.markdown("#### Performance Metrics (Holdout Set)")

if not is_demo_mode():
    try:
        metrics = get_model_metrics()
        if not metrics.empty:
            m = metrics.iloc[0]
            c1, c2, c3, c4, c5 = st.columns(5)
            with c1:
                st.metric("ROC-AUC", f"{m.get('ROC_AUC', 'N/A'):.4f}"
                          if m.get('ROC_AUC') is not None else "N/A")
            with c2:
                st.metric("Accuracy", f"{m.get('ACCURACY', 'N/A'):.4f}"
                          if m.get('ACCURACY') is not None else "N/A")
            with c3:
                st.metric("Precision (Breach)", f"{m.get('PRECISION_BREACH', 'N/A'):.4f}"
                          if m.get('PRECISION_BREACH') is not None else "N/A")
            with c4:
                st.metric("Recall (Breach)", f"{m.get('RECALL_BREACH', 'N/A'):.4f}"
                          if m.get('RECALL_BREACH') is not None else "N/A")
            with c5:
                st.metric("F1 (Breach)", f"{m.get('F1_BREACH', 'N/A'):.4f}"
                          if m.get('F1_BREACH') is not None else "N/A")
        else:
            st.info("No model metrics available. Train the model first.")
    except Exception as e:
        st.error(f"Failed to load metrics: {e}")
else:
    st.info("Live model metrics not available in demo mode. "
            "Prototype reference values (not live): "
            "ROC-AUC 0.8304, Precision 0.4385, Recall 0.6950, F1 0.5377. "
            "These are prototype-demo values, not production results.")

st.markdown("---")

# ── Confusion Matrix ─────────────────────────────────────────
st.markdown("#### Confusion Matrix (Test Set)")

if not is_demo_mode():
    try:
        cm = get_confusion_matrix()
        if not cm.empty:
            formatted = cm.copy()
            formatted.columns = ["Actual", "Predicted", "Count"]
            formatted["Actual"] = formatted["Actual"].map({0: "No Breach", 1: "Breach"})
            formatted["Predicted"] = formatted["Predicted"].map({0: "No Breach", 1: "Breach"})
            formatted["Count"] = formatted["Count"].apply(lambda x: f"{int(x):,}")
            st.dataframe(formatted, use_container_width=True)
        else:
            st.info("No confusion matrix data. Train the model first.")
    except Exception as e:
        st.error(f"{e}")
else:
    st.info("Confusion matrix not available in demo mode.")

st.markdown("---")

# ── Feature Importance ───────────────────────────────────────
st.markdown("#### Feature Importance (Top 15)")

if not is_demo_mode():
    try:
        fi = get_feature_importance()
        if not fi.empty:
            st.bar_chart(fi.set_index("FEATURE")["SCORE"], use_container_width=True)
            st.dataframe(fi, use_container_width=True)
        else:
            st.info("No feature importance data.")
    except Exception as e:
        st.error(f"{e}")
else:
    st.info("Feature importance not available in demo mode.")

st.markdown("---")

# ── Governance Controls ──────────────────────────────────────
st.markdown("#### Governance Controls")

st.markdown("""
| Control | Status | Evidence |
|---------|--------|----------|
| Train/Test Split | Stratified 80/20 | `SP_TRAIN_IMPROVED_MODEL` procedure |
| Oversampling | SMOTE on train only | Applied before HPO, not on holdout |
| Threshold Tuning | Optimal F1 on holdout | `precision_recall_curve` in procedure |
| Calibration | Isotonic, 3-fold on train | `CalibratedClassifierCV` |
| Scoring Population | Open PO lines only | `OTIF_BREACH IS NULL` filter |
| Recovery Engine | Deterministic SQL | No LLM calculations |
| Agent Tools | Read-only SQL tools | `cortex_analyst_text_to_sql` |
| ERP Writes | None | Read-only decision support |
""")

st.caption(
    "The prototype references point-in-time splits, inventory safety floors, "
    "lane lead-time checks, and approved-source validation. "
    "Actual enforcement status should be verified against the deployed stored procedures."
)

st.markdown("---")

# ── Data Freshness ───────────────────────────────────────────
st.markdown("#### Data Freshness")

try:
    freshness = get_data_freshness()
    if not freshness.empty:
        for _, row in freshness.iterrows():
            c1, c2 = st.columns([1, 2])
            with c1:
                st.markdown(f"**{row['SOURCE_TABLE']}**")
            with c2:
                st.markdown(f"`{row['LAST_UPDATED']}`")
    else:
        st.info("Unable to determine data freshness.")
except Exception as e:
    st.error(f"{e}")

st.markdown("---")

# ── Object Inventory ─────────────────────────────────────────
st.markdown("#### Object Inventory")

if not is_demo_mode() and st.button("Refresh Object Counts"):
    try:
        inventory = run_query("""
            SELECT 'Tables (RAW)' AS object_type, COUNT(*) AS count
            FROM INFORMATION_SCHEMA.TABLES
            WHERE TABLE_SCHEMA = 'RAW' AND TABLE_CATALOG = 'OTIF_GUARDIAN'
            UNION ALL
            SELECT 'Views (ANALYTICS)', COUNT(*)
            FROM INFORMATION_SCHEMA.VIEWS
            WHERE TABLE_SCHEMA = 'ANALYTICS' AND TABLE_CATALOG = 'OTIF_GUARDIAN'
            UNION ALL
            SELECT 'Views (ML)', COUNT(*)
            FROM INFORMATION_SCHEMA.VIEWS
            WHERE TABLE_SCHEMA = 'ML' AND TABLE_CATALOG = 'OTIF_GUARDIAN'
            UNION ALL
            SELECT 'Tables (ML)', COUNT(*)
            FROM INFORMATION_SCHEMA.TABLES
            WHERE TABLE_SCHEMA = 'ML' AND TABLE_CATALOG = 'OTIF_GUARDIAN'
        """)
        for _, row in inventory.iterrows():
            c1, c2 = st.columns([2, 1])
            with c1:
                st.markdown(f"**{row['OBJECT_TYPE']}**")
            with c2:
                st.markdown(f"`{int(row['COUNT']):,}`")
    except Exception as e:
        st.error(f"{e}")

st.caption("Decision support only — no ERP writes.")
