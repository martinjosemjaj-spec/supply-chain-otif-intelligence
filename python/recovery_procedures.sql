-- ============================================================
-- OTIF_Guardian: Recovery Engine - Python Orchestration
-- Snowpark stored procedure for batch recovery evaluation
-- Deterministic — NO LLM calls
-- Generated: 2026-08-28
-- ============================================================

USE DATABASE OTIF_GUARDIAN;
USE SCHEMA ML;

-- ============================================================
-- Stored Procedure: Execute recovery evaluation pipeline
-- ============================================================

CREATE OR REPLACE PROCEDURE OTIF_GUARDIAN.ML.SP_RUN_RECOVERY_ENGINE()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run_recovery_engine'
COMMENT = 'Deterministic recovery engine: scores at-risk PO lines and recommends actions'
AS
$$
import json
from datetime import datetime
from snowflake.snowpark import Session
from snowflake.snowpark.functions import col, lit, count, sum as sum_, avg, when, round as round_

def run_recovery_engine(session: Session) -> dict:
    """
    Execute the full recovery evaluation pipeline.
    All calculations are deterministic SQL/Python — no LLM involved.

    Steps:
    1. Refresh ML scoring (batch inference on open PO lines)
    2. Evaluate three recovery actions per at-risk line
    3. Rank and select best action per line
    4. Produce portfolio summary

    Returns:
        dict with execution metadata and portfolio summary
    """

    execution_start = datetime.now()
    results = {
        "execution_id": execution_start.strftime("%Y%m%d_%H%M%S"),
        "status": "RUNNING",
        "steps": []
    }

    try:
        # ----------------------------------------------------------
        # Step 1: Refresh scored PO lines (re-run inference)
        # ----------------------------------------------------------
        session.sql("""
            CREATE OR REPLACE TABLE OTIF_GUARDIAN.ML.SCORED_PO_LINES AS
            SELECT
                sd.po_line_id,
                sd.po_id,
                sd.order_date,
                sd.promised_delivery_date,
                OTIF_GUARDIAN.ML.OTIF_BREACH_MODEL!PREDICT(
                    INPUT_DATA => OBJECT_CONSTRUCT(
                        'SUPPLIER_TIER', sd.supplier_tier,
                        'SUPPLIER_STD_LEAD_TIME', sd.supplier_std_lead_time,
                        'SUPPLIER_MASTER_OTD', sd.supplier_master_otd,
                        'SUPPLIER_QUALITY_SCORE', sd.supplier_quality_score,
                        'SUPPLIER_ON_PROBATION', sd.supplier_on_probation,
                        'MATERIAL_CATEGORY', sd.material_category,
                        'ABC_CLASS', sd.abc_class,
                        'CRITICALITY', sd.criticality,
                        'STANDARD_UNIT_COST', sd.standard_unit_cost,
                        'WEIGHT_KG', sd.weight_kg,
                        'MATERIAL_SAFETY_DAYS', sd.material_safety_days,
                        'QUANTITY_ORDERED', sd.quantity_ordered,
                        'UNIT_PRICE', sd.unit_price,
                        'LINE_VALUE', sd.line_value,
                        'PO_TYPE', sd.po_type,
                        'CURRENCY', sd.currency,
                        'PLANT_REGION', sd.plant_region,
                        'PLANT_COUNTRY', sd.plant_country,
                        'PROMISED_LEAD_TIME_DAYS', sd.promised_lead_time_days,
                        'ORDER_DAY_OF_WEEK', sd.order_day_of_week,
                        'ORDER_MONTH', sd.order_month,
                        'ORDER_QUARTER', sd.order_quarter,
                        'LEAD_TIME_VS_STANDARD', sd.lead_time_vs_standard,
                        'SUPPLIER_HIST_VOLUME', sd.supplier_hist_volume,
                        'SUPPLIER_HIST_OTIF_RATE', sd.supplier_hist_otif_rate,
                        'SUPPLIER_HIST_AVG_VARIANCE', sd.supplier_hist_avg_variance,
                        'SUPPLIER_HIST_STDDEV_VARIANCE', sd.supplier_hist_stddev_variance,
                        'SUPPLIER_RECENT_OTIF_RATE', sd.supplier_recent_otif_rate,
                        'DEMAND_30D_QTY', sd.demand_30d_qty,
                        'DEMAND_30D_COUNT', sd.demand_30d_count,
                        'MATERIAL_ALT_SUPPLIER_COUNT', sd.material_alt_supplier_count,
                        'IS_SINGLE_SOURCED', sd.is_single_sourced
                    )
                ) AS prediction_result
            FROM OTIF_GUARDIAN.ML.SCORE_DATA sd
        """).collect()

        scored_count = session.sql(
            "SELECT COUNT(*) AS cnt FROM OTIF_GUARDIAN.ML.SCORED_PO_LINES"
        ).collect()[0]["CNT"]

        results["steps"].append({
            "step": "inference",
            "status": "COMPLETE",
            "scored_lines": scored_count
        })

        # ----------------------------------------------------------
        # Step 2: Count at-risk lines
        # ----------------------------------------------------------
        at_risk_count = session.sql("""
            SELECT COUNT(*) AS cnt
            FROM OTIF_GUARDIAN.ML.V_AT_RISK_LINES
        """).collect()[0]["CNT"]

        results["steps"].append({
            "step": "risk_identification",
            "status": "COMPLETE",
            "at_risk_lines": at_risk_count
        })

        # ----------------------------------------------------------
        # Step 3: Get portfolio summary (all SQL views already defined)
        # ----------------------------------------------------------
        portfolio = session.sql("""
            SELECT *
            FROM OTIF_GUARDIAN.ML.V_RECOVERY_PORTFOLIO_SUMMARY
        """).collect()

        if portfolio:
            row = portfolio[0]
            results["portfolio_summary"] = {
                "at_risk_lines_addressable": row["AT_RISK_LINES_ADDRESSABLE"],
                "total_feasible_actions": row["TOTAL_FEASIBLE_ACTIONS"],
                "total_revenue_protected": float(row["TOTAL_REVENUE_PROTECTED"] or 0),
                "total_incremental_cost": float(row["TOTAL_INCREMENTAL_COST"] or 0),
                "total_net_value_protected": float(row["TOTAL_NET_VALUE_PROTECTED"] or 0),
                "avg_otif_lift": float(row["AVG_OTIF_LIFT"] or 0),
                "recommended_expedites": row["RECOMMENDED_EXPEDITES"],
                "recommended_transfers": row["RECOMMENDED_TRANSFERS"],
                "recommended_alt_suppliers": row["RECOMMENDED_ALT_SUPPLIERS"],
                "portfolio_roi_multiple": float(row["PORTFOLIO_ROI_MULTIPLE"] or 0)
            }
        else:
            results["portfolio_summary"] = {
                "at_risk_lines_addressable": 0,
                "total_net_value_protected": 0,
                "message": "No at-risk lines found or no feasible actions available"
            }

        # ----------------------------------------------------------
        # Step 4: Get action type breakdown
        # ----------------------------------------------------------
        action_breakdown = session.sql("""
            SELECT * FROM OTIF_GUARDIAN.ML.V_RECOVERY_BY_ACTION_TYPE
        """).collect()

        results["action_breakdown"] = []
        for row in action_breakdown:
            results["action_breakdown"].append({
                "action_type": row["ACTION_TYPE"],
                "recommended_count": row["RECOMMENDED_COUNT"],
                "net_value_protected": float(row["NET_VALUE_PROTECTED"] or 0),
                "avg_success_prob": float(row["AVG_SUCCESS_PROB"] or 0),
                "avg_otif_lift": float(row["AVG_OTIF_LIFT"] or 0)
            })

        # ----------------------------------------------------------
        # Step 5: Persist execution log
        # ----------------------------------------------------------
        session.sql(f"""
            CREATE TABLE IF NOT EXISTS OTIF_GUARDIAN.ML.RECOVERY_ENGINE_LOG (
                execution_id VARCHAR,
                execution_timestamp TIMESTAMP_NTZ,
                scored_lines INTEGER,
                at_risk_lines INTEGER,
                feasible_actions INTEGER,
                net_value_protected FLOAT,
                portfolio_roi FLOAT,
                execution_duration_sec FLOAT
            )
        """).collect()

        execution_end = datetime.now()
        duration = (execution_end - execution_start).total_seconds()

        net_val = results.get("portfolio_summary", {}).get("total_net_value_protected", 0)
        roi = results.get("portfolio_summary", {}).get("portfolio_roi_multiple", 0)
        feasible = results.get("portfolio_summary", {}).get("total_feasible_actions", 0)

        session.sql(f"""
            INSERT INTO OTIF_GUARDIAN.ML.RECOVERY_ENGINE_LOG VALUES (
                '{results["execution_id"]}',
                CURRENT_TIMESTAMP(),
                {scored_count},
                {at_risk_count},
                {feasible},
                {net_val},
                {roi},
                {duration}
            )
        """).collect()

        results["status"] = "SUCCESS"
        results["execution_duration_sec"] = duration

    except Exception as e:
        results["status"] = "FAILED"
        results["error"] = str(e)

    return results
$$;


-- ============================================================
-- Stored Procedure: Get recovery recommendation for a single PO line
-- ============================================================

CREATE OR REPLACE PROCEDURE OTIF_GUARDIAN.ML.SP_GET_RECOVERY_FOR_PO_LINE(
    P_PO_LINE_ID INTEGER
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'get_recovery_for_po_line'
COMMENT = 'Returns all feasible recovery actions for a specific PO line, ranked by net value'
AS
$$
def get_recovery_for_po_line(session, p_po_line_id: int) -> dict:
    """
    Retrieve ranked recovery actions for a single PO line.
    Pure SQL query — no LLM computation.
    """
    results = {"po_line_id": p_po_line_id, "actions": []}

    # Get all recommendations for this line
    rows = session.sql(f"""
        SELECT
            action_rank,
            action_type,
            action_detail,
            is_feasible,
            would_resolve_breach,
            success_probability,
            otif_lift,
            incremental_cost,
            revenue_protected,
            net_value_protected,
            roi_multiple,
            breach_probability,
            days_until_due,
            line_value,
            downstream_revenue_exposed
        FROM OTIF_GUARDIAN.ML.V_RECOVERY_RECOMMENDATIONS
        WHERE po_line_id = {p_po_line_id}
        ORDER BY action_rank
    """).collect()

    for row in rows:
        results["actions"].append({
            "rank": row["ACTION_RANK"],
            "action_type": row["ACTION_TYPE"],
            "detail": row["ACTION_DETAIL"],
            "would_resolve": row["WOULD_RESOLVE_BREACH"],
            "success_probability": float(row["SUCCESS_PROBABILITY"] or 0),
            "otif_lift": float(row["OTIF_LIFT"] or 0),
            "incremental_cost": float(row["INCREMENTAL_COST"] or 0),
            "revenue_protected": float(row["REVENUE_PROTECTED"] or 0),
            "net_value_protected": float(row["NET_VALUE_PROTECTED"] or 0),
            "roi_multiple": float(row["ROI_MULTIPLE"]) if row["ROI_MULTIPLE"] else None
        })

    # Context
    if rows:
        results["context"] = {
            "breach_probability": float(rows[0]["BREACH_PROBABILITY"] or 0),
            "days_until_due": rows[0]["DAYS_UNTIL_DUE"],
            "line_value": float(rows[0]["LINE_VALUE"] or 0),
            "downstream_revenue_exposed": float(rows[0]["DOWNSTREAM_REVENUE_EXPOSED"] or 0)
        }
        results["recommended_action"] = results["actions"][0] if results["actions"] else None
    else:
        results["message"] = "No feasible recovery actions found for this PO line"

    return results
$$;


-- ============================================================
-- Stored Procedure: Calculate net OTIF improvement from executing all recommendations
-- ============================================================

CREATE OR REPLACE PROCEDURE OTIF_GUARDIAN.ML.SP_CALCULATE_OTIF_IMPACT()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'calculate_otif_impact'
COMMENT = 'Calculates expected OTIF rate improvement if all top recommendations are executed'
AS
$$
def calculate_otif_impact(session) -> dict:
    """
    Deterministic calculation of expected OTIF improvement.
    Compares current predicted OTIF vs post-recovery projected OTIF.
    """

    # Current baseline: predicted breach rate on open lines
    baseline = session.sql("""
        SELECT
            COUNT(*) AS total_open_lines,
            COUNT_IF(prediction_result:"class"::INT = 1) AS predicted_breaches,
            COUNT_IF(prediction_result:"class"::INT = 0) AS predicted_ok,
            ROUND(COUNT_IF(prediction_result:"class"::INT = 0) * 100.0
                / NULLIF(COUNT(*), 0), 2) AS predicted_otif_rate
        FROM OTIF_GUARDIAN.ML.SCORED_PO_LINES
    """).collect()[0]

    # Recovery impact: how many predicted breaches can be recovered
    recovery = session.sql("""
        SELECT
            COUNT(*) AS addressable_breaches,
            SUM(otif_lift) AS total_otif_lift_points,
            SUM(CASE WHEN would_resolve_breach THEN 1 ELSE 0 END) AS fully_recoverable,
            AVG(success_probability) AS avg_success_rate
        FROM OTIF_GUARDIAN.ML.V_BEST_RECOVERY_ACTION
    """).collect()[0]

    total_lines = baseline["TOTAL_OPEN_LINES"]
    predicted_ok = baseline["PREDICTED_OK"]
    fully_recoverable = recovery["FULLY_RECOVERABLE"] or 0
    avg_success = float(recovery["AVG_SUCCESS_RATE"] or 0)

    # Expected recovered lines = fully_recoverable * avg_success_rate
    expected_recovered = round(fully_recoverable * avg_success, 0)

    # Post-recovery OTIF rate
    post_recovery_ok = predicted_ok + expected_recovered
    post_recovery_otif = round(post_recovery_ok * 100.0 / max(total_lines, 1), 2)

    return {
        "baseline": {
            "total_open_lines": total_lines,
            "predicted_breaches": baseline["PREDICTED_BREACHES"],
            "predicted_otif_rate_pct": float(baseline["PREDICTED_OTIF_RATE"] or 0)
        },
        "recovery_potential": {
            "addressable_breaches": recovery["ADDRESSABLE_BREACHES"] or 0,
            "fully_recoverable": fully_recoverable,
            "avg_success_rate": avg_success,
            "expected_lines_recovered": int(expected_recovered)
        },
        "projected": {
            "post_recovery_otif_rate_pct": post_recovery_otif,
            "otif_lift_pct_points": round(post_recovery_otif - float(baseline["PREDICTED_OTIF_RATE"] or 0), 2)
        }
    }
$$;


-- ============================================================
-- END
-- ============================================================
