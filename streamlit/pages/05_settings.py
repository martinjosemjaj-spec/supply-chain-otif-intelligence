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
    run_query
)

st.title("Settings")

# ══════════════════════════════════════════════════════════════
# Section 1: Connection Info
# ══════════════════════════════════════════════════════════════
st.subheader("Connection")

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
            st.text_input("Account", value=row["ACCOUNT"], disabled=True)
            st.text_input("User", value=row["USER_NAME"], disabled=True)
        with col2:
            st.text_input("Role", value=row["ROLE_NAME"], disabled=True)
            st.text_input("Warehouse", value=row["WAREHOUSE"], disabled=True)
        with col3:
            st.text_input("Database", value=str(row["DATABASE_NAME"]), disabled=True)
            st.text_input("Schema", value=str(row["SCHEMA_NAME"]), disabled=True)
except Exception as e:
    st.error(f"Failed to get connection info: {e}")

st.divider()

# ══════════════════════════════════════════════════════════════
# Section 2: Model Version & Performance
# ══════════════════════════════════════════════════════════════
st.subheader("Model Version")

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
            st.metric("Accuracy", f"{m.get('ACCURACY', 0):.4f}")
            st.metric("F1 (Breach)", f"{m.get('F1_BREACH', 0):.4f}")
            st.metric("Recall (Breach)", f"{m.get('RECALL_BREACH', 0):.4f}")
            st.metric("Precision (Breach)", f"{m.get('PRECISION_BREACH', 0):.4f}")
    except Exception:
        st.info("Model metrics not available.")

st.divider()

# ══════════════════════════════════════════════════════════════
# Section 3: Confusion Matrix
# ══════════════════════════════════════════════════════════════
st.subheader("Confusion Matrix (Test Set)")

try:
    cm = get_confusion_matrix()
    if not cm.empty:
        st.dataframe(cm, use_container_width=True, hide_index=True)
    else:
        st.info("No confusion matrix data. Train the model first.")
except Exception as e:
    st.error(f"{e}")

st.divider()

# ══════════════════════════════════════════════════════════════
# Section 4: Data Freshness
# ══════════════════════════════════════════════════════════════
st.subheader("Data Freshness")

try:
    freshness = get_data_freshness()
    if not freshness.empty:
        st.dataframe(freshness, use_container_width=True, hide_index=True)
    else:
        st.info("Unable to determine data freshness.")
except Exception as e:
    st.error(f"{e}")

st.divider()

# ══════════════════════════════════════════════════════════════
# Section 5: Decision Trace Configuration
# ══════════════════════════════════════════════════════════════
st.subheader("Decision Trace")

st.markdown("""
| Component | Trace Method | Description |
|-----------|-------------|-------------|
| ML Predictions | SHAP Reason Codes | Per-prediction feature contributions via `EXPLAIN()` |
| Recovery Actions | Deterministic SQL | All cost/benefit calculations in SQL views |
| Copilot Answers | Agent Tool Calls | Traces which tools were invoked per response |
| Data Pipeline | Temporal Split | Train/test split prevents future data leakage |
""")

st.caption(
    "All calculations in OTIF Guardian are deterministic and reproducible. "
    "No LLM-generated numbers are used in risk scoring, recovery evaluation, "
    "or financial impact calculations."
)

st.divider()

# ══════════════════════════════════════════════════════════════
# Section 6: Object Inventory
# ══════════════════════════════════════════════════════════════
st.subheader("Object Inventory")

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
        st.dataframe(inventory, use_container_width=True, hide_index=True)
    except Exception as e:
        st.error(f"{e}")

# ══════════════════════════════════════════════════════════════
# Section 7: Recovery Engine Log
# ══════════════════════════════════════════════════════════════
st.subheader("Recovery Engine Execution Log")

try:
    log = run_query("""
        SELECT * FROM OTIF_GUARDIAN.ML.RECOVERY_ENGINE_LOG
        ORDER BY execution_timestamp DESC
        LIMIT 10
    """)
    if not log.empty:
        st.dataframe(log, use_container_width=True, hide_index=True)
    else:
        st.info("No execution history. Run the recovery engine to populate.")
except Exception as e:
    st.caption("Recovery engine log not yet created.")
