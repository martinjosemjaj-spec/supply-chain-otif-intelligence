"""
OTIF Guardian - Application Configuration
Centralizes database object references, display settings, and mode selection.
"""

import os

# ── Mode Selection ───────────────────────────────────────────
# Set OTIF_GUARDIAN_MODE=demo to run without Snowflake
APP_MODE = os.environ.get("OTIF_GUARDIAN_MODE", "live")

# ── Database Object References ───────────────────────────────
DB = "OTIF_GUARDIAN"

OBJECTS = {
    "risk_lines": f"{DB}.ML.V_AT_RISK_LINES",
    "scored_results": f"{DB}.ML.V_SCORED_RESULTS",
    "recovery_recs": f"{DB}.ML.V_RECOVERY_RECOMMENDATIONS",
    "best_recovery": f"{DB}.ML.V_BEST_RECOVERY_ACTION",
    "recovery_portfolio": f"{DB}.ML.V_RECOVERY_PORTFOLIO_SUMMARY",
    "recovery_by_action": f"{DB}.ML.V_RECOVERY_BY_ACTION_TYPE",
    "reason_codes": f"{DB}.ML.V_TOP_REASON_CODES",
    "feature_importance": f"{DB}.ML.V_FEATURE_IMPORTANCE",
    "model_metrics": f"{DB}.ML.V_MODEL_METRICS",
    "confusion_matrix": f"{DB}.ML.V_CONFUSION_MATRIX",
    "risk_by_supplier": f"{DB}.ML.V_RISK_BY_SUPPLIER",
    "risk_by_material": f"{DB}.ML.V_RISK_BY_MATERIAL",
    "revenue_exposure": f"{DB}.ML.V_REVENUE_EXPOSURE",
    "plants": f"{DB}.RAW.PLANTS",
    "po_lines": f"{DB}.RAW.PO_LINES",
    "customer_orders": f"{DB}.RAW.CUSTOMER_ORDERS",
    "recovery_log": f"{DB}.ML.RECOVERY_ENGINE_LOG",
    "agent": f"{DB}.AGENTS.OTIF_GUARDIAN_AGENT",
    "agent_semantic_view": f"{DB}.SEMANTIC.OTIF_GUARDIAN_SUPPLY_CHAIN",
    "monitoring_overall": f"{DB}.AUDIT.V_MONITORING_OVERALL",
    "monitoring_dashboard": f"{DB}.AUDIT.V_MONITORING_DASHBOARD",
    "evidence_package": f"{DB}.ML.V_EVIDENCE_PACKAGE",
    "evidence_recovery": f"{DB}.ML.V_EVIDENCE_RECOVERY",
    "decision_layer": f"{DB}.ML.V_DECISION_LAYER_COMPLETE",
    "otif_projection": f"{DB}.ML.V_OTIF_PROJECTION",
    "production_model": f"{DB}.AUDIT.V_PRODUCTION_MODEL",
    "decision_assumptions": f"{DB}.ML.DECISION_ASSUMPTIONS",
    "purchase_orders": f"{DB}.RAW.PURCHASE_ORDERS",
    "suppliers": f"{DB}.RAW.SUPPLIERS",
    "inventory": f"{DB}.RAW.INVENTORY",
    "operational_summary": f"{DB}.AUDIT.V_OPERATIONAL_SUMMARY",
    "operational_health": f"{DB}.AUDIT.V_OPERATIONAL_HEALTH",
    "dq_latest_run": f"{DB}.AUDIT.V_DQ_LATEST_RUN",
    "dq_failures": f"{DB}.AUDIT.V_DQ_FAILURES",
    "dq_category_summary": f"{DB}.AUDIT.V_DQ_CATEGORY_SUMMARY",
    "dq_run_summary": f"{DB}.AUDIT.DQ_RUN_SUMMARY",
    "observability_dashboard": f"{DB}.AUDIT.V_OBSERVABILITY_DASHBOARD",
    "monitoring_results": f"{DB}.AUDIT.MONITORING_RESULTS",
}

# ── Field Mapping Documentation ──────────────────────────────
# Prototype field -> Existing field (or None if unavailable)
# Per SKILL.md: "Document mappings rather than assuming equivalence"
FIELD_MAP = {
    # Risk fields
    "PO_LINE_ID": "PO_LINE_ID",           # Numeric in existing; prototype uses string
    "SUPPLIER_NAME": "SUPPLIER_NAME",
    "PART_ID": "MATERIAL_CODE",            # NOT assumed equal; documented mapping
    "PLANT_NAME": "PLANT_CODE",            # Join to PLANTS.PLANT_NAME for display
    "RISK_BAND": "RISK_TIER",             # Same values: CRITICAL/HIGH/MEDIUM/LOW
    "PREDICTED_BREACH_PROBABILITY": "BREACH_PROBABILITY",  # 0-1 fraction
    "SUPPLIER_OTIF_90D": None,             # Not available in scored views
    "INVENTORY_DOS": None,                 # Not available in scored views
    "AT_RISK_UNITS": "QUANTITY_ORDERED",   # From V_AT_RISK_LINES
    "AT_RISK_REVENUE": "LINE_VALUE",       # From V_AT_RISK_LINES
    "PROJECTED_CUSTOMER_OTIF_PCT": None,   # Cannot invent formula per spec
    "EXPOSURE_SCORE": None,                # Cannot invent formula per spec
    "CONFIRMED_DELIVERY_DATE": None,       # Not available
    "PROJECTED_RECEIPT_DATE": "PROMISED_DELIVERY_DATE",
    "PROJECTED_STOCKOUT_DATE": None,       # Not available
    "REASON_CODES": "V_TOP_REASON_CODES",  # SHAP-based, join by PO_LINE_ID
    "MODEL_VERSION": None,                 # Static: V2-XGBoost
    "SCORED_AT": None,                     # From recovery log timestamp
    "METRIC_AS_OF_DATE": None,             # Not tracked per line
    # Recovery fields
    "ACTION_NAME": "ACTION_TYPE",          # + ACTION_DETAIL
    "FEASIBLE_FLAG": "IS_FEASIBLE",
    "REJECTION_REASON": None,              # Not available
    "ACTION_QTY": None,                    # Not available as separate field
    "RECOVERED_UNITS": None,               # Not available
    "ARRIVAL_DATE": None,                  # Not available
    "INCREMENTAL_COST": "INCREMENTAL_COST",
    "REVENUE_PROTECTED": "REVENUE_PROTECTED",
    "OTIF_LIFT_PP": "OTIF_LIFT",           # Units may differ; document
    "NET_VALUE_PROTECTED": "NET_VALUE_PROTECTED",
    "RECOMMENDED_FLAG": None,              # Derive from ACTION_RANK = 1
    "RANK_SCORE": "ACTION_RANK",
}

# ── Display Settings ─────────────────────────────────────────
PLANNING_HORIZON_DAYS = 14
RISK_BANDS = ["CRITICAL", "HIGH", "MEDIUM", "LOW"]
DEFAULT_RISK_BANDS = ["CRITICAL", "HIGH"]
DEFAULT_MIN_REVENUE = 0
REVENUE_STEP = 10_000
COMMAND_CENTER_PAGE_SIZE = 100
CACHE_TTL_SECONDS = 120
SYSTEM_STATUS_CACHE_TTL = 300  # 5 min for metadata (model version, health)
QUERY_CACHE_TTL = 120          # 2 min for data queries

# ── Unavailable Fields ───────────────────────────────────────
# Per SKILL.md S2: "isolate the affected live feature with a clear
# availability message, document the exact dependency"
UNAVAILABLE_FIELDS = {
    "EXPOSURE_SCORE": "Requires governed view OTIF_GUARDIAN.APP.V_GOVERNED_RISK_COMMAND_CENTER",
    "PROJECTED_CUSTOMER_OTIF_PCT": "Requires governed view with customer OTIF projection model",
    "SUPPLIER_OTIF_90D": "Requires rolling 90-day supplier OTIF calculation in scored view",
    "INVENTORY_DOS": "Requires inventory days-of-supply join in scored view",
    "CONFIRMED_DELIVERY_DATE": "Requires ASN/confirmation data feed",
    "PROJECTED_STOCKOUT_DATE": "Requires inventory depletion model",
    "REJECTION_REASON": "Requires governed recovery view with rejection logic",
    "ACTION_QTY": "Requires governed recovery view with action quantities",
    "RECOVERED_UNITS": "Requires governed recovery view with recovered unit tracking",
    "ARRIVAL_DATE": "Requires governed recovery view with estimated arrival dates",
}
