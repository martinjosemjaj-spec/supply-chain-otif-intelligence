"""
OTIF Guardian - Settings
System status, model info, data freshness, and configuration.
"""

import streamlit as st
import sys
sys.path.insert(0, "..")
from lib.data import (
    get_session, get_model_version, get_prediction_time,
    get_data_freshness, get_model_metrics, get_confusion_matrix,
    run_query, fmt_number
)

# ── Page Header ──────────────────────────────────────────────
st.markdown("## ⚙️ Settings")
st.caption("System status, model performance, and configuration")

st.markdown("---")

# ── Connection Info ──────────────────────────────────────────
st.markdown("### Connection")

try:
    conn_info = run_query("""
        SELECT
            CURRENT_ACCOUNT() AS account,
            CURRENT_USER() AS user_name,
            CURRENT_ROLE() AS role_name,
            CURRENT_WAREHOUSE() AS warehouse,
            CURRENT_DATABASE() AS database_name,
            CURRENT_SCHEMA() AS schema_name
    """)
    if not conn_info.empty:
        row = conn_info.iloc[0]
        col1, col2, col3 = st.columns(3)
        with col1:
            st.markdown(f"**Account:** `{row['ACCOUNT']}`")
            st.markdown(f"**User:** `{row['USER_NAME']}`")
        with col2:
            st.markdown(f"**Role:** `{row['ROLE_NAME']}`")
            st.markdown(f"**Warehouse:** `{row['WAREHOUSE']}`")
        with col3:
            st.markdown(f"**Database:** `{row['DATABASE_NAME']}`")
            st.markdown(f"**Schema:** `{row['SCHEMA_NAME']}`")
except Exception as e:
    st.error(f"Failed to get connection info: {e}")

st.markdown("---")

# ── Model Version & Performance ──────────────────────────────
st.markdown("### Model Performance")

col1, col2 = st.columns(2)

with col1:
    try:
        mv = get_model_version()
        version = mv.get("DEFAULT_VERSION_NAME", mv.get("default_version_name", "N/A"))
        st.metric("Active Version", version)
    except Exception:
        st.metric("Active Version", "N/A")

    st.metric("Last Prediction Run", str(get_prediction_time()))

with col2:
    try:
        metrics = get_model_metrics()
        if not metrics.empty:
            m = metrics.iloc[0]
            m1, m2 = st.columns(2)
            with m1:
                st.metric("Accuracy", f"{m.get('ACCURACY', 0):.4f}")
                st.metric("F1 (Breach)", f"{m.get('F1_BREACH', 0):.4f}")
            with m2:
                st.metric("Recall (Breach)", f"{m.get('RECALL_BREACH', 0):.4f}")
                st.metric("Precision (Breach)", f"{m.get('PRECISION_BREACH', 0):.4f}")
    except Exception:
        st.info("Model metrics not available.")

st.markdown("---")

# ── Confusion Matrix ─────────────────────────────────────────
st.markdown("### Confusion Matrix (Test Set)")

try:
    cm = get_confusion_matrix()
    if not cm.empty:
        # Format as readable table
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

st.markdown("---")

# ── Data Freshness ───────────────────────────────────────────
st.markdown("### Data Freshness")

try:
    freshness = get_data_freshness()
    if not freshness.empty:
        for _, row in freshness.iterrows():
            col1, col2 = st.columns([1, 2])
            with col1:
                st.markdown(f"**{row['SOURCE_TABLE']}**")
            with col2:
                st.markdown(f"`{row['LAST_UPDATED']}`")
    else:
        st.info("Unable to determine data freshness.")
except Exception as e:
    st.error(f"{e}")

st.markdown("---")

# ── Decision Trace Configuration ─────────────────────────────
st.markdown("### Decision Trace")

st.markdown("""
| Component | Trace Method | Description |
|-----------|-------------|-------------|
| ML Predictions | SHAP Reason Codes | Per-prediction feature contributions |
| Recovery Actions | Deterministic SQL | All cost/benefit calculations in SQL views |
| Copilot Answers | Agent Tool Calls | Traces which tools were invoked per response |
| Data Pipeline | Temporal Split | Train/test split prevents future data leakage |
""")

st.caption(
    "All calculations in OTIF Guardian are deterministic and reproducible. "
    "No LLM-generated numbers are used in risk scoring, recovery evaluation, "
    "or financial impact calculations."
)

st.markdown("---")

# ── Object Inventory ─────────────────────────────────────────
st.markdown("### Object Inventory")

if st.button("Refresh Object Counts"):
    try:
        inventory = run_query("""
            SELECT 'Tables (RAW)' AS object_type,
                   COUNT(*) AS count
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
            col1, col2 = st.columns([2, 1])
            with col1:
                st.markdown(f"**{row['OBJECT_TYPE']}**")
            with col2:
                st.markdown(f"`{int(row['COUNT']):,}`")
    except Exception as e:
        st.error(f"{e}")

# ── Recovery Engine Log ──────────────────────────────────────
st.markdown("### Recovery Engine Execution Log")

try:
    log = run_query("""
        SELECT * FROM OTIF_GUARDIAN.ML.RECOVERY_ENGINE_LOG
        ORDER BY execution_timestamp DESC
        LIMIT 10
    """)
    if not log.empty:
        st.dataframe(log, use_container_width=True)
    else:
        st.info("No execution history. Run the recovery engine to populate.")
except Exception as e:
    st.caption("Recovery engine log not yet created.")
