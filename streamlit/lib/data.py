"""
OTIF Guardian - Data access layer.
Centralizes all SQL queries. Supports live (Snowflake) and demo (CSV) modes.
"""

import pandas as pd
import os

try:
    import streamlit as st
    _HAS_ST = hasattr(st, "cache_resource")
except ImportError:
    _HAS_ST = False

from lib.config import APP_MODE, OBJECTS, CACHE_TTL_SECONDS, UNAVAILABLE_FIELDS

_DEMO_DIR = None


def _find_demo_dir():
    global _DEMO_DIR
    if _DEMO_DIR is not None:
        return _DEMO_DIR
    candidates = [
        os.path.join(os.path.dirname(os.path.dirname(__file__)), "demo_data"),
        os.path.join(os.path.dirname(os.path.dirname(__file__)), "artifacts"),
    ]
    for d in candidates:
        if os.path.isdir(d):
            _DEMO_DIR = d
            return d
    _DEMO_DIR = candidates[0]
    return _DEMO_DIR


def is_demo_mode():
    return APP_MODE == "demo"


# ── Session / Query ──────────────────────────────────────────

if _HAS_ST:
    @st.cache_resource
    def get_session():
        if is_demo_mode():
            return None
        from snowflake.snowpark.context import get_active_session
        return get_active_session()
else:
    def get_session():
        if is_demo_mode():
            return None
        from snowflake.snowpark.context import get_active_session
        return get_active_session()


def run_query(sql: str):
    if is_demo_mode():
        return pd.DataFrame()
    session = get_session()
    return session.sql(sql).to_pandas()


# ── Formatting Helpers ───────────────────────────────────────

def fmt_dollar(val):
    if val is None or (isinstance(val, float) and pd.isna(val)):
        return "N/A"
    try:
        v = float(val)
        if abs(v) >= 1_000_000:
            return f"${v/1_000_000:,.1f}M"
        elif abs(v) >= 1_000:
            return f"${v:,.0f}"
        return f"${v:,.2f}"
    except (TypeError, ValueError):
        return "N/A"


def fmt_pct(val, decimals=1):
    if val is None or (isinstance(val, float) and pd.isna(val)):
        return "N/A"
    try:
        return f"{float(val):.{decimals}f}%"
    except (TypeError, ValueError):
        return "N/A"


def fmt_prob(val):
    if val is None or (isinstance(val, float) and pd.isna(val)):
        return "N/A"
    try:
        return f"{float(val):.1%}"
    except (TypeError, ValueError):
        return "N/A"


def fmt_number(val):
    if val is None or (isinstance(val, float) and pd.isna(val)):
        return "N/A"
    try:
        return f"{int(float(val)):,}"
    except (TypeError, ValueError):
        return "N/A"


def fmt_days(val):
    if val is None or (isinstance(val, float) and pd.isna(val)):
        return "N/A"
    try:
        d = int(float(val))
        return f"{d:,}d"
    except (TypeError, ValueError):
        return "N/A"


def unavailable_msg(field_name):
    return UNAVAILABLE_FIELDS.get(field_name, "Data source not available")


# ── Metadata ─────────────────────────────────────────────────

def get_model_version():
    if is_demo_mode():
        return {"DEFAULT_VERSION_NAME": "V2-XGBoost (demo)"}
    try:
        df = run_query("SHOW MODELS LIKE 'OTIF_BREACH_PREDICTOR' IN SCHEMA OTIF_GUARDIAN.ML")
        if not df.empty:
            return df.iloc[0].to_dict()
    except Exception:
        pass
    return {"DEFAULT_VERSION_NAME": "V2-XGBoost"}


def get_model_version_str():
    mv = get_model_version()
    return mv.get("DEFAULT_VERSION_NAME", mv.get("default_version_name", "N/A"))


def get_data_freshness():
    if is_demo_mode():
        return pd.DataFrame({"SOURCE_TABLE": ["PO_LINES", "INVENTORY", "CUSTOMER_ORDERS"],
                             "LAST_UPDATED": ["(demo)", "(demo)", "(demo)"]})
    return run_query(f"""
        SELECT 'PO_LINES' AS source_table, MAX(created_at) AS last_updated
        FROM {OBJECTS['po_lines']}
        UNION ALL
        SELECT 'INVENTORY', MAX(created_at) FROM {OBJECTS['plants'].replace('PLANTS','INVENTORY')}
        UNION ALL
        SELECT 'CUSTOMER_ORDERS', MAX(created_at) FROM {OBJECTS['customer_orders']}
    """)


def get_prediction_time():
    if is_demo_mode():
        return "(demo mode)"
    try:
        df = run_query(f"SELECT MAX(execution_timestamp) AS last_run FROM {OBJECTS['recovery_log']}")
        if not df.empty and df.iloc[0]["LAST_RUN"] is not None:
            return df.iloc[0]["LAST_RUN"]
    except Exception:
        return "Metadata retrieval failed"
    return "No execution history"


def get_scoring_time():
    """Distinct from recovery engine execution time per SKILL.md S11."""
    if is_demo_mode():
        return "(demo mode)"
    try:
        df = run_query(f"""
            SELECT MAX(ORDER_DATE) AS last_scored
            FROM {OBJECTS['scored_results']}
            WHERE PREDICTED_BREACH IS NOT NULL
        """)
        if not df.empty and df.iloc[0]["LAST_SCORED"] is not None:
            return df.iloc[0]["LAST_SCORED"]
    except Exception:
        return "Metadata retrieval failed"
    return "No scoring history"


# ── Plants ───────────────────────────────────────────────────

def get_plants():
    if is_demo_mode():
        return pd.DataFrame({
            "PLANT_CODE": ["PLT-MFG-01", "PLT-MFG-02", "PLT-MFG-03"],
            "PLANT_NAME": ["Detroit Assembly", "Monterrey Production", "Stuttgart Precision"],
        })
    return run_query(f"SELECT PLANT_CODE, PLANT_NAME FROM {OBJECTS['plants']} ORDER BY PLANT_CODE")


# ── Executive KPIs (preserved from existing) ─────────────────

def get_executive_kpis():
    return run_query(f"""
        SELECT
            ROUND(COUNT_IF(
                ACTUAL_DELIVERY_DATE IS NOT NULL
                AND LINE_STATUS IN ('CLOSED','SHORT_CLOSED')
                AND ACTUAL_DELIVERY_DATE <= PROMISED_DELIVERY_DATE
                AND QUANTITY_RECEIVED >= QUANTITY_ORDERED
            ) * 100.0 / NULLIF(COUNT_IF(
                ACTUAL_DELIVERY_DATE IS NOT NULL
                AND LINE_STATUS IN ('CLOSED','SHORT_CLOSED')
            ), 0), 1) AS inbound_otif_rate,
            COUNT_IF(ACTUAL_DELIVERY_DATE IS NOT NULL
                AND LINE_STATUS IN ('CLOSED','SHORT_CLOSED')) AS total_delivered,
            COUNT_IF(LINE_STATUS IN ('OPEN','IN_TRANSIT','PARTIALLY_RECEIVED')) AS open_lines
        FROM {OBJECTS['po_lines']}
    """)


def get_customer_otif_kpis():
    return run_query(f"""
        SELECT
            ROUND(COUNT_IF(OTIF_FLAG = TRUE) * 100.0
                / NULLIF(COUNT_IF(OTIF_FLAG IS NOT NULL), 0), 1) AS customer_otif_rate,
            COUNT_IF(ORDER_STATUS = 'OPEN') AS open_orders,
            SUM(CASE WHEN OTIF_FLAG = FALSE THEN ORDER_VALUE ELSE 0 END) AS revenue_at_risk
        FROM {OBJECTS['customer_orders']}
    """)


def get_monthly_otif_trend():
    return run_query(f"""
        SELECT DATE_TRUNC('month', ACTUAL_DELIVERY_DATE)::DATE AS month,
            ROUND(COUNT_IF(ACTUAL_DELIVERY_DATE <= PROMISED_DELIVERY_DATE
                AND QUANTITY_RECEIVED >= QUANTITY_ORDERED
            ) * 100.0 / NULLIF(COUNT(*), 0), 1) AS otif_rate
        FROM {OBJECTS['po_lines']}
        WHERE ACTUAL_DELIVERY_DATE IS NOT NULL
            AND LINE_STATUS IN ('CLOSED','SHORT_CLOSED')
            AND ACTUAL_DELIVERY_DATE >= DATEADD('month', -12, CURRENT_DATE())
        GROUP BY 1 ORDER BY 1
    """)


def get_otif_by_supplier_tier():
    return run_query(f"""
        SELECT s.SUPPLIER_TIER, COUNT(*) AS total_lines,
            ROUND(COUNT_IF(pl.ACTUAL_DELIVERY_DATE <= pl.PROMISED_DELIVERY_DATE
                AND pl.QUANTITY_RECEIVED >= pl.QUANTITY_ORDERED
            ) * 100.0 / NULLIF(COUNT(*), 0), 1) AS otif_rate
        FROM {OBJECTS['po_lines']} pl
        JOIN OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po ON pl.PO_ID = po.PO_ID
        JOIN OTIF_GUARDIAN.RAW.SUPPLIERS s ON po.SUPPLIER_ID = s.SUPPLIER_ID
        WHERE pl.ACTUAL_DELIVERY_DATE IS NOT NULL
            AND pl.LINE_STATUS IN ('CLOSED','SHORT_CLOSED')
        GROUP BY s.SUPPLIER_TIER ORDER BY s.SUPPLIER_TIER
    """)


# ── Risk Command Center ─────────────────────────────────────

def get_risk_command_center(plant_filter=None, risk_bands=None, min_revenue=0,
                            limit=100, offset=0):
    """Filtered, paginated risk data pushed to Snowflake."""
    if is_demo_mode():
        return _demo_risk_data(plant_filter, risk_bands, min_revenue, limit)
    wheres = ["r.RISK_TIER IN ('CRITICAL','HIGH','MEDIUM','LOW')"]
    if plant_filter and plant_filter != "All":
        wheres.append(f"r.PLANT_CODE = '{plant_filter}'")
    if risk_bands:
        bands_str = ",".join(f"'{b}'" for b in risk_bands)
        wheres.append(f"r.RISK_TIER IN ({bands_str})")
    if min_revenue and min_revenue > 0:
        wheres.append(f"r.LINE_VALUE >= {float(min_revenue)}")
    where_clause = " AND ".join(wheres)
    return run_query(f"""
        SELECT r.PO_LINE_ID, r.PO_NUMBER, r.SUPPLIER_NAME, r.MATERIAL_CODE,
            r.PLANT_CODE, p.PLANT_NAME,
            r.RISK_TIER, r.BREACH_PROBABILITY, r.DAYS_UNTIL_DUE,
            r.QUANTITY_ORDERED, r.LINE_VALUE, r.PROMISED_DELIVERY_DATE,
            r.SUPPLIER_TIER, r.MATERIAL_CATEGORY, r.ABC_CLASS, r.CRITICALITY
        FROM {OBJECTS['risk_lines']} r
        LEFT JOIN {OBJECTS['plants']} p ON r.PLANT_CODE = p.PLANT_CODE
        WHERE {where_clause}
        ORDER BY r.BREACH_PROBABILITY DESC, r.LINE_VALUE DESC, r.PO_LINE_ID
        LIMIT {int(limit)} OFFSET {int(offset)}
    """)


def get_risk_kpi_metrics(plant_filter=None, risk_bands=None, min_revenue=0):
    """Aggregate KPIs for the command center, pushed to Snowflake."""
    if is_demo_mode():
        return _demo_risk_kpis()
    wheres = ["RISK_TIER IN ('CRITICAL','HIGH','MEDIUM','LOW')"]
    if plant_filter and plant_filter != "All":
        wheres.append(f"PLANT_CODE = '{plant_filter}'")
    if risk_bands:
        bands_str = ",".join(f"'{b}'" for b in risk_bands)
        wheres.append(f"RISK_TIER IN ({bands_str})")
    if min_revenue and min_revenue > 0:
        wheres.append(f"LINE_VALUE >= {float(min_revenue)}")
    where_clause = " AND ".join(wheres)
    return run_query(f"""
        SELECT
            COUNT(DISTINCT PO_LINE_ID) AS scored_lines,
            COUNT_IF(RISK_TIER = 'CRITICAL') AS critical_lines,
            COALESCE(SUM(LINE_VALUE), 0) AS total_revenue_at_risk,
            ROUND(AVG(BREACH_PROBABILITY), 4) AS avg_breach_probability
        FROM {OBJECTS['risk_lines']}
        WHERE {where_clause}
    """)


def get_revenue_by_plant(plant_filter=None, risk_bands=None, min_revenue=0):
    """Revenue exposure aggregated by plant for the bar chart."""
    if is_demo_mode():
        return pd.DataFrame({"PLANT_NAME": ["Detroit", "Monterrey", "Stuttgart"],
                             "REVENUE": [50000, 30000, 20000],
                             "AVG_BREACH_PROB": [0.7, 0.5, 0.3]})
    wheres = ["r.RISK_TIER IN ('CRITICAL','HIGH','MEDIUM','LOW')"]
    if plant_filter and plant_filter != "All":
        wheres.append(f"r.PLANT_CODE = '{plant_filter}'")
    if risk_bands:
        bands_str = ",".join(f"'{b}'" for b in risk_bands)
        wheres.append(f"r.RISK_TIER IN ({bands_str})")
    if min_revenue and min_revenue > 0:
        wheres.append(f"r.LINE_VALUE >= {float(min_revenue)}")
    where_clause = " AND ".join(wheres)
    return run_query(f"""
        SELECT COALESCE(p.PLANT_NAME, r.PLANT_CODE) AS PLANT_NAME,
            SUM(r.LINE_VALUE) AS REVENUE,
            ROUND(AVG(r.BREACH_PROBABILITY), 4) AS AVG_BREACH_PROB
        FROM {OBJECTS['risk_lines']} r
        LEFT JOIN {OBJECTS['plants']} p ON r.PLANT_CODE = p.PLANT_CODE
        WHERE {where_clause}
        GROUP BY COALESCE(p.PLANT_NAME, r.PLANT_CODE)
        ORDER BY REVENUE DESC
    """)


# ── PO Decision Detail ──────────────────────────────────────

def get_po_detail(po_line_id):
    """Single PO line detail for the decision view."""
    if is_demo_mode():
        return _demo_po_detail(po_line_id)
    return run_query(f"""
        SELECT r.*, p.PLANT_NAME
        FROM {OBJECTS['risk_lines']} r
        LEFT JOIN {OBJECTS['plants']} p ON r.PLANT_CODE = p.PLANT_CODE
        WHERE r.PO_LINE_ID = {int(po_line_id)}
    """)


def get_po_reason_codes(po_line_id):
    """SHAP reason codes for a PO line."""
    if is_demo_mode():
        return pd.DataFrame({
            "FEATURE_NAME": ["SUPPLIER_HIST_OTIF_RATE", "LEAD_TIME_RATIO"],
            "SHAP_CONTRIBUTION": [0.35, 0.22],
            "DIRECTION": ["INCREASES RISK", "INCREASES RISK"],
            "IMPORTANCE_RANK": [1, 2],
        })
    return run_query(f"""
        SELECT FEATURE_NAME, SHAP_CONTRIBUTION, DIRECTION, IMPORTANCE_RANK
        FROM {OBJECTS['reason_codes']}
        WHERE PO_LINE_ID = {int(po_line_id)}
        ORDER BY IMPORTANCE_RANK
    """)


def get_po_recovery_options(po_line_id):
    """Recovery options for a specific PO line."""
    if is_demo_mode():
        return _demo_recovery_options(po_line_id)
    return run_query(f"""
        SELECT ACTION_TYPE, ACTION_DETAIL, IS_FEASIBLE, WOULD_RESOLVE_BREACH,
            SUCCESS_PROBABILITY, OTIF_LIFT, INCREMENTAL_COST, REVENUE_PROTECTED,
            NET_VALUE_PROTECTED, ROI_MULTIPLE, ACTION_RANK
        FROM {OBJECTS['recovery_recs']}
        WHERE PO_LINE_ID = {int(po_line_id)}
        ORDER BY
            CASE WHEN ACTION_RANK = 1 THEN 0 ELSE 1 END,
            ACTION_RANK, NET_VALUE_PROTECTED DESC, PO_LINE_ID
    """)


# ── Preserved existing functions ─────────────────────────────

def get_risk_summary():
    return run_query(f"""
        SELECT risk_tier, COUNT(*) AS line_count,
            ROUND(AVG(breach_probability), 3) AS avg_probability
        FROM {OBJECTS['scored_results']}
        GROUP BY risk_tier
        ORDER BY CASE risk_tier
            WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2
            WHEN 'MEDIUM' THEN 3 WHEN 'LOW' THEN 4 ELSE 5 END
    """)


def get_at_risk_lines(risk_tier="CRITICAL", limit=50):
    return run_query(f"""
        SELECT po_number, supplier_name, material_code, material_name,
            plant_code, days_until_due, breach_probability, risk_tier
        FROM {OBJECTS['scored_results']}
        WHERE risk_tier = '{risk_tier}'
        ORDER BY breach_probability DESC
        LIMIT {int(limit)}
    """)


def get_risk_by_supplier():
    return run_query(f"SELECT * FROM {OBJECTS['risk_by_supplier']} ORDER BY high_risk_lines DESC LIMIT 20")


def get_risk_by_material():
    return run_query(f"SELECT * FROM {OBJECTS['risk_by_material']} ORDER BY high_risk_lines DESC LIMIT 20")


def get_feature_importance():
    return run_query(f"SELECT * FROM {OBJECTS['feature_importance']} ORDER BY SCORE DESC LIMIT 15")


def get_reason_codes_for_line(po_line_id):
    return run_query(f"""
        SELECT feature_name, shap_contribution, direction, importance_rank
        FROM {OBJECTS['reason_codes']}
        WHERE po_line_id = {int(po_line_id)}
        ORDER BY importance_rank
    """)


def get_recovery_portfolio():
    return run_query(f"SELECT * FROM {OBJECTS['recovery_portfolio']}")


def get_recovery_by_action_type():
    return run_query(f"SELECT * FROM {OBJECTS['recovery_by_action']}")


def get_best_recovery_actions(limit=50):
    return run_query(f"""
        SELECT r.po_line_id, r.action_type, r.action_detail,
            r.success_probability, r.otif_lift,
            r.incremental_cost, r.revenue_protected, r.net_value_protected,
            r.roi_multiple, r.breach_probability, r.days_until_due
        FROM {OBJECTS['best_recovery']} r
        ORDER BY r.net_value_protected DESC
        LIMIT {int(limit)}
    """)


def get_recovery_for_po(po_line_id):
    return run_query(f"""
        SELECT action_rank, action_type, action_detail,
            is_feasible, would_resolve_breach, success_probability,
            otif_lift, incremental_cost, revenue_protected,
            net_value_protected, roi_multiple
        FROM {OBJECTS['recovery_recs']}
        WHERE po_line_id = {int(po_line_id)}
        ORDER BY action_rank
    """)


def get_model_metrics():
    return run_query(f"SELECT * FROM {OBJECTS['model_metrics']}")


def get_confusion_matrix():
    return run_query(f"SELECT * FROM {OBJECTS['confusion_matrix']}")


# ── Agent / Copilot ──────────────────────────────────────────

def run_agent_query(question):
    """Call the Cortex Agent. Returns (answer_text, trace_json, raw_response)."""
    if not question or not question.strip():
        return ("Please enter a question.", None, None)
    if is_demo_mode():
        return _demo_agent_response(question)
    import json
    session = get_session()
    request_body = json.dumps({
        "messages": [{"role": "user", "content": [{"type": "text", "text": question}]}]
    })
    safe_body = request_body.replace("'", "''")
    result = session.sql(f"""
        SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
            '{OBJECTS['agent']}', '{safe_body}'
        ) AS response
    """).collect()
    if not result:
        return ("No response from agent.", None, None)
    raw = result[0]["RESPONSE"]
    try:
        parsed = json.loads(raw) if isinstance(raw, str) else raw
        parts = parsed.get("content", [])
        texts = [p.get("text", "") for p in parts if p.get("type") == "text"]
        tools = [p.get("tool_use", {}).get("name", "unknown")
                 for p in parts if p.get("type") == "tool_use"]
        answer = "\n".join(texts) if texts else str(raw)
        trace = json.dumps({"tools_invoked": tools, "grounding": "SQL tool results",
                            "guardrail": "No LLM calculations"}, indent=2) if tools else None
    except (json.JSONDecodeError, TypeError):
        answer = str(raw)
        trace = None
    return (answer, trace, raw)


# ── Demo Helpers ─────────────────────────────────────────────

def _demo_risk_data(plant_filter, risk_bands, min_revenue, limit):
    if risk_bands is not None and len(risk_bands) == 0:
        return pd.DataFrame()
    demo_dir = _find_demo_dir()
    path = os.path.join(demo_dir, "demo_risk_exposure.csv")
    if os.path.exists(path):
        df = pd.read_csv(path)
    else:
        df = _generate_demo_risk()
    if plant_filter and plant_filter != "All":
        df = df[df["PLANT_CODE"] == plant_filter]
    if risk_bands:
        df = df[df["RISK_TIER"].isin(risk_bands)]
    if min_revenue and min_revenue > 0:
        df = df[df["LINE_VALUE"] >= min_revenue]
    return df.head(limit)


def _demo_risk_kpis():
    return pd.DataFrame({
        "SCORED_LINES": [42], "CRITICAL_LINES": [8],
        "TOTAL_REVENUE_AT_RISK": [185000.0], "AVG_BREACH_PROBABILITY": [0.62],
    })


def _demo_po_detail(po_line_id):
    return pd.DataFrame({
        "PO_LINE_ID": [po_line_id], "PO_NUMBER": [f"PO-{po_line_id:07d}"],
        "SUPPLIER_NAME": ["Demo Supplier"], "MATERIAL_CODE": ["MAT-00001"],
        "PLANT_CODE": ["PLT-MFG-01"], "PLANT_NAME": ["Detroit Assembly"],
        "RISK_TIER": ["HIGH"], "BREACH_PROBABILITY": [0.78],
        "DAYS_UNTIL_DUE": [5], "QUANTITY_ORDERED": [100],
        "LINE_VALUE": [5000.0], "PROMISED_DELIVERY_DATE": ["2026-10-05"],
        "SUPPLIER_TIER": [2],
    })


def _demo_recovery_options(po_line_id):
    return pd.DataFrame({
        "ACTION_TYPE": ["EXPEDITE", "ALTERNATE_SUPPLIER", "INVENTORY_TRANSFER"],
        "ACTION_DETAIL": ["Premium freight", "Order from Alt-Supplier", "Transfer from PLT-MFG-02"],
        "IS_FEASIBLE": [True, True, False],
        "WOULD_RESOLVE_BREACH": [True, True, False],
        "SUCCESS_PROBABILITY": [0.90, 0.75, 0.0],
        "OTIF_LIFT": [0.85, 0.70, 0.0],
        "INCREMENTAL_COST": [1200.0, 0.0, 0.0],
        "REVENUE_PROTECTED": [5000.0, 5000.0, 0.0],
        "NET_VALUE_PROTECTED": [3800.0, 5000.0, 0.0],
        "ROI_MULTIPLE": [3.17, None, None],
        "ACTION_RANK": [1, 2, 3],
    })


def _demo_agent_response(question):
    q = question.lower()
    if "otif" in q and ("rate" in q or "overall" in q):
        return ("**[DEMO]** The overall inbound OTIF rate is approximately 90.3% "
                "across all closed/short-closed PO lines.", None, None)
    if "risk" in q or "critical" in q:
        return ("**[DEMO]** There are 8 critical-risk PO lines with a combined "
                "revenue exposure of ~$185K.", None, None)
    if "recovery" in q or "action" in q:
        return ("**[DEMO]** The top recovery action is EXPEDITE with a net value "
                "protected of ~$3,800 and an ROI of 3.17x.", None, None)
    if "supplier" in q:
        return ("**[DEMO]** Supplier risk is distributed across tiers. "
                "Tier 1 suppliers have ~10% breach rate.", None, None)
    return ("**[DEMO]** This is a demo response. In live mode, the OTIF Guardian "
            "agent answers from governed SQL tool results. Supported topics: "
            "OTIF rates, risk analysis, recovery actions, supplier performance.", None, None)


def _generate_demo_risk():
    import random
    random.seed(42)
    rows = []
    tiers = ["CRITICAL"] * 8 + ["HIGH"] * 12 + ["MEDIUM"] * 15 + ["LOW"] * 7
    for i, tier in enumerate(tiers):
        prob = {"CRITICAL": 0.85, "HIGH": 0.65, "MEDIUM": 0.45, "LOW": 0.25}[tier]
        rows.append({
            "PO_LINE_ID": 30000 + i, "PO_NUMBER": f"PO-{6000+i:07d}",
            "SUPPLIER_NAME": f"Supplier-{i%10}", "MATERIAL_CODE": f"MAT-{i%20:05d}",
            "PLANT_CODE": f"PLT-MFG-{(i%3)+1:02d}",
            "PLANT_NAME": ["Detroit Assembly", "Monterrey Production", "Stuttgart Precision"][i % 3],
            "RISK_TIER": tier, "BREACH_PROBABILITY": round(prob + random.uniform(-0.1, 0.1), 4),
            "DAYS_UNTIL_DUE": random.randint(-5, 30),
            "QUANTITY_ORDERED": random.randint(10, 500),
            "LINE_VALUE": round(random.uniform(500, 50000), 2),
            "PROMISED_DELIVERY_DATE": "2026-10-15",
            "SUPPLIER_TIER": random.choice([1, 2, 3]),
        })
    return pd.DataFrame(rows)
