"""
OTIF Guardian - Shared utilities and data access layer.
All SQL queries centralized here. No business logic in pages.
"""

import streamlit as st
from snowflake.snowpark.context import get_active_session
from datetime import datetime


@st.cache_resource
def get_session():
    return get_active_session()


def run_query(sql: str):
    session = get_session()
    return session.sql(sql).to_pandas()


# ── Metadata ──────────────────────────────────────────────────

def get_model_version():
    df = run_query("""
        SELECT default_version_name, comment
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
    """)
    # Fallback: direct query
    try:
        df = run_query("""
            SELECT default_version_name
            FROM TABLE(FLATTEN(
                INPUT => PARSE_JSON(SYSTEM$GET_ALL_MODEL_VERSIONS('OTIF_GUARDIAN.ML.OTIF_BREACH_PREDICTOR'))
            ))
        """)
    except Exception:
        df = run_query("""
            SHOW MODELS LIKE 'OTIF_BREACH_PREDICTOR' IN SCHEMA OTIF_GUARDIAN.ML
        """)
    if not df.empty:
        return df.iloc[0].to_dict()
    return {"default_version_name": "UNKNOWN"}


def get_data_freshness():
    return run_query("""
        SELECT
            'PO_LINES' AS source_table,
            MAX(created_at) AS last_updated
        FROM OTIF_GUARDIAN.RAW.PO_LINES
        UNION ALL
        SELECT 'INVENTORY', MAX(created_at)
        FROM OTIF_GUARDIAN.RAW.INVENTORY
        UNION ALL
        SELECT 'CUSTOMER_ORDERS', MAX(created_at)
        FROM OTIF_GUARDIAN.RAW.CUSTOMER_ORDERS
        UNION ALL
        SELECT 'SCORED_PO_LINES', MAX(created_at)
        FROM OTIF_GUARDIAN.ML.SCORED_PO_LINES
    """)


def get_prediction_time():
    try:
        df = run_query("""
            SELECT MAX(execution_timestamp) AS last_run
            FROM OTIF_GUARDIAN.ML.RECOVERY_ENGINE_LOG
        """)
        if not df.empty and df.iloc[0]["LAST_RUN"]:
            return df.iloc[0]["LAST_RUN"]
    except Exception:
        pass
    return "Never"


# ── Executive KPIs ────────────────────────────────────────────

def get_executive_kpis():
    return run_query("""
        SELECT
            -- Inbound OTIF
            ROUND(COUNT_IF(
                ACTUAL_DELIVERY_DATE IS NOT NULL
                AND ACTUAL_DELIVERY_DATE <= PROMISED_DELIVERY_DATE
                AND QUANTITY_RECEIVED >= QUANTITY_ORDERED
            ) * 100.0 / NULLIF(COUNT_IF(
                ACTUAL_DELIVERY_DATE IS NOT NULL
                AND LINE_STATUS IN ('CLOSED','SHORT_CLOSED')
            ), 0), 1) AS inbound_otif_rate,
            -- Lines delivered
            COUNT_IF(ACTUAL_DELIVERY_DATE IS NOT NULL AND LINE_STATUS IN ('CLOSED','SHORT_CLOSED')) AS total_delivered,
            -- Open lines
            COUNT_IF(LINE_STATUS IN ('OPEN','IN_TRANSIT','PARTIALLY_RECEIVED')) AS open_lines
        FROM OTIF_GUARDIAN.RAW.PO_LINES
    """)


def get_customer_otif_kpis():
    return run_query("""
        SELECT
            ROUND(COUNT_IF(OTIF_FLAG = TRUE) * 100.0
                / NULLIF(COUNT_IF(OTIF_FLAG IS NOT NULL), 0), 1) AS customer_otif_rate,
            COUNT_IF(ORDER_STATUS = 'OPEN') AS open_orders,
            SUM(CASE WHEN OTIF_FLAG = FALSE THEN ORDER_VALUE ELSE 0 END) AS revenue_at_risk
        FROM OTIF_GUARDIAN.RAW.CUSTOMER_ORDERS
    """)


def get_monthly_otif_trend():
    return run_query("""
        SELECT
            DATE_TRUNC('month', ACTUAL_DELIVERY_DATE)::DATE AS month,
            ROUND(COUNT_IF(
                ACTUAL_DELIVERY_DATE <= PROMISED_DELIVERY_DATE
                AND QUANTITY_RECEIVED >= QUANTITY_ORDERED
            ) * 100.0 / NULLIF(COUNT(*), 0), 1) AS otif_rate
        FROM OTIF_GUARDIAN.RAW.PO_LINES
        WHERE ACTUAL_DELIVERY_DATE IS NOT NULL
            AND ACTUAL_DELIVERY_DATE >= DATEADD('month', -12, CURRENT_DATE())
        GROUP BY 1
        ORDER BY 1
    """)


def get_otif_by_supplier_tier():
    return run_query("""
        SELECT
            s.SUPPLIER_TIER,
            COUNT(*) AS total_lines,
            ROUND(COUNT_IF(
                pl.ACTUAL_DELIVERY_DATE <= pl.PROMISED_DELIVERY_DATE
                AND pl.QUANTITY_RECEIVED >= pl.QUANTITY_ORDERED
            ) * 100.0 / NULLIF(COUNT(*), 0), 1) AS otif_rate
        FROM OTIF_GUARDIAN.RAW.PO_LINES pl
        JOIN OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po ON pl.PO_ID = po.PO_ID
        JOIN OTIF_GUARDIAN.RAW.SUPPLIERS s ON po.SUPPLIER_ID = s.SUPPLIER_ID
        WHERE pl.ACTUAL_DELIVERY_DATE IS NOT NULL
            AND pl.LINE_STATUS IN ('CLOSED','SHORT_CLOSED')
        GROUP BY s.SUPPLIER_TIER
        ORDER BY s.SUPPLIER_TIER
    """)


# ── Risk Center ───────────────────────────────────────────────

def get_risk_summary():
    return run_query("""
        SELECT
            risk_tier,
            COUNT(*) AS line_count,
            ROUND(AVG(breach_probability), 3) AS avg_probability
        FROM OTIF_GUARDIAN.ML.V_SCORED_RESULTS
        GROUP BY risk_tier
        ORDER BY CASE risk_tier
            WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2
            WHEN 'MEDIUM' THEN 3 WHEN 'LOW' THEN 4 ELSE 5 END
    """)


def get_at_risk_lines(risk_tier="CRITICAL", limit=50):
    return run_query(f"""
        SELECT
            po_number, supplier_name, material_code, material_name,
            plant_code, days_until_due, breach_probability, risk_tier
        FROM OTIF_GUARDIAN.ML.V_SCORED_RESULTS
        WHERE risk_tier = '{risk_tier}'
        ORDER BY breach_probability DESC
        LIMIT {limit}
    """)


def get_risk_by_supplier():
    return run_query("""
        SELECT * FROM OTIF_GUARDIAN.ML.V_RISK_BY_SUPPLIER
        ORDER BY high_risk_lines DESC
        LIMIT 20
    """)


def get_risk_by_material():
    return run_query("""
        SELECT * FROM OTIF_GUARDIAN.ML.V_RISK_BY_MATERIAL
        ORDER BY high_risk_lines DESC
        LIMIT 20
    """)


def get_feature_importance():
    return run_query("""
        SELECT * FROM OTIF_GUARDIAN.ML.V_FEATURE_IMPORTANCE
        ORDER BY 2 DESC
        LIMIT 15
    """)


def get_reason_codes_for_line(po_line_id: int):
    return run_query(f"""
        SELECT feature_name, shap_contribution, direction, importance_rank
        FROM OTIF_GUARDIAN.ML.V_TOP_REASON_CODES
        WHERE po_line_id = {po_line_id}
        ORDER BY importance_rank
    """)


# ── Recovery Center ───────────────────────────────────────────

def get_recovery_portfolio():
    return run_query("""
        SELECT * FROM OTIF_GUARDIAN.ML.V_RECOVERY_PORTFOLIO_SUMMARY
    """)


def get_recovery_by_action_type():
    return run_query("""
        SELECT * FROM OTIF_GUARDIAN.ML.V_RECOVERY_BY_ACTION_TYPE
    """)


def get_best_recovery_actions(limit=50):
    return run_query(f"""
        SELECT
            r.po_line_id, r.action_type, r.action_detail,
            r.success_probability, r.otif_lift,
            r.incremental_cost, r.revenue_protected, r.net_value_protected,
            r.roi_multiple, r.breach_probability, r.days_until_due
        FROM OTIF_GUARDIAN.ML.V_BEST_RECOVERY_ACTION r
        ORDER BY r.net_value_protected DESC
        LIMIT {limit}
    """)


def get_recovery_for_po(po_line_id: int):
    return run_query(f"""
        SELECT
            action_rank, action_type, action_detail,
            is_feasible, would_resolve_breach, success_probability,
            otif_lift, incremental_cost, revenue_protected,
            net_value_protected, roi_multiple
        FROM OTIF_GUARDIAN.ML.V_RECOVERY_RECOMMENDATIONS
        WHERE po_line_id = {po_line_id}
        ORDER BY action_rank
    """)


# ── Model Metrics ─────────────────────────────────────────────

def get_model_metrics():
    return run_query("""
        SELECT * FROM OTIF_GUARDIAN.ML.V_MODEL_METRICS
    """)


def get_confusion_matrix():
    return run_query("""
        SELECT * FROM OTIF_GUARDIAN.ML.V_CONFUSION_MATRIX
    """)
