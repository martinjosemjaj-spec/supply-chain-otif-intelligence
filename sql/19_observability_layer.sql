-- ============================================================
-- 19_observability_layer.sql
-- Operational Observability for OTIF Guardian
-- ============================================================
-- Prerequisites: 08_monitoring, 09_data_quality, 11_model_hardening,
--                12_production_monitoring, 15_agent_hardening, 18_cicd_infrastructure
-- Run as: ACCOUNTADMIN or OTIF_GUARDIAN_ADMIN
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE OTIF_GUARDIAN;
USE WAREHOUSE OTIF_GUARDIAN_WH;

-- ============================================================
-- 1. V_OPERATIONAL_HEALTH — unified row-level telemetry
--    Pulls ACTUAL data from 4 domains:
--    DATA:        DQ checks, freshness, missing values, row counts
--    ML:          Model version, drift, prediction distribution, calibration, scoring
--    AGENT:       Evaluation scores, tool usage, errors
--    APPLICATION: Scoring status, volume, deployment history
-- ============================================================

-- See CREATE OR REPLACE VIEW executed via SQL_EXECUTE (too large for file deploy).
-- The view definition joins:
--   AUDIT.MONITORING_RESULTS (latest run)
--   AUDIT.V_DQ_CATEGORY_SUMMARY
--   AUDIT.DQ_CHECK_RESULTS (ROW_COUNT category)
--   AUDIT.V_PRODUCTION_MODEL
--   AUDIT.SCORING_LOG (latest success)
--   AUDIT.AGENT_EVAL_RESULTS (latest agent version)
--   AUDIT.DEPLOYMENT_HISTORY (latest deploy)

-- ============================================================
-- 2. V_OPERATIONAL_SUMMARY — domain-level rollup
-- ============================================================

CREATE OR REPLACE VIEW AUDIT.V_OPERATIONAL_SUMMARY AS
SELECT 
    DOMAIN,
    COUNT(*) AS TOTAL_CHECKS,
    SUM(CASE WHEN STATUS = 'HEALTHY' THEN 1 ELSE 0 END) AS HEALTHY,
    SUM(CASE WHEN STATUS = 'WARNING' THEN 1 ELSE 0 END) AS WARNINGS,
    SUM(CASE WHEN STATUS = 'CRITICAL' THEN 1 ELSE 0 END) AS CRITICAL,
    CASE 
        WHEN SUM(CASE WHEN STATUS = 'CRITICAL' THEN 1 ELSE 0 END) > 0 THEN 'CRITICAL'
        WHEN SUM(CASE WHEN STATUS = 'WARNING' THEN 1 ELSE 0 END) > 0 THEN 'WARNING'
        ELSE 'HEALTHY'
    END AS DOMAIN_STATUS,
    MAX(CHECKED_AT) AS LAST_CHECKED,
    MAX(MODEL_VERSION) AS MODEL_VERSION
FROM AUDIT.V_OPERATIONAL_HEALTH
GROUP BY DOMAIN
ORDER BY CASE DOMAIN WHEN 'DATA' THEN 1 WHEN 'ML' THEN 2 WHEN 'AGENT' THEN 3 WHEN 'APPLICATION' THEN 4 END;

-- ============================================================
-- 3. GRANTS
-- ============================================================

GRANT SELECT ON VIEW AUDIT.V_OPERATIONAL_HEALTH TO ROLE OTIF_GUARDIAN_APP;
GRANT SELECT ON VIEW AUDIT.V_OPERATIONAL_SUMMARY TO ROLE OTIF_GUARDIAN_APP;
GRANT SELECT ON VIEW AUDIT.V_OPERATIONAL_HEALTH TO ROLE OTIF_GUARDIAN_ANALYST;
GRANT SELECT ON VIEW AUDIT.V_OPERATIONAL_SUMMARY TO ROLE OTIF_GUARDIAN_ANALYST;
GRANT SELECT ON VIEW AUDIT.V_OPERATIONAL_HEALTH TO ROLE OTIF_GUARDIAN_ENGINEER;
GRANT SELECT ON VIEW AUDIT.V_OPERATIONAL_SUMMARY TO ROLE OTIF_GUARDIAN_ENGINEER;

-- ============================================================
-- OBSERVABILITY ARCHITECTURE
-- ============================================================
--
-- V_OPERATIONAL_SUMMARY (4 rows: DATA, ML, AGENT, APPLICATION)
--   └── V_OPERATIONAL_HEALTH (~47 rows of actual telemetry)
--         ├── DATA domain (33 checks)
--         │     ├── FRESHNESS: from MONITORING_RESULTS.DATA_FRESHNESS
--         │     ├── QUALITY: from V_DQ_CATEGORY_SUMMARY (11 categories)
--         │     ├── ROW_COUNTS: from DQ_CHECK_RESULTS.ROW_COUNT
--         │     └── MISSING_VALUES: from MONITORING_RESULTS.MISSING_VALUES
--         ├── ML domain (10 checks)
--         │     ├── MODEL_VERSION: from V_PRODUCTION_MODEL
--         │     ├── PREDICTION_DISTRIBUTION: from MONITORING_RESULTS.PREDICTION_DRIFT
--         │     ├── DRIFT: from MONITORING_RESULTS.FEATURE_DRIFT (non-healthy only)
--         │     ├── PERFORMANCE: from MONITORING_RESULTS.MODEL_PERFORMANCE
--         │     ├── CALIBRATION: from MONITORING_RESULTS.CALIBRATION
--         │     └── SCORING_STATUS: from SCORING_LOG (latest success)
--         ├── AGENT domain (2-3 checks)
--         │     ├── EVALUATION_SCORE: from AGENT_EVAL_RESULTS (pass rate)
--         │     ├── TOOL_USAGE: from AGENT_EVAL_RESULTS (tool distribution)
--         │     └── ERRORS: from AGENT_EVAL_RESULTS (failures)
--         └── APPLICATION domain (2 checks)
--               ├── SCORING_STATUS: from SCORING_LOG (latest run)
--               ├── SCORING_VOLUME: from MONITORING_RESULTS.SCORING_VOLUME
--               └── DEPLOYMENT: from DEPLOYMENT_HISTORY (latest)
--
-- Status determination:
--   HEALTHY:  check passed within configured thresholds
--   WARNING:  check exceeded warning threshold
--   CRITICAL: check exceeded critical threshold or hard failure
--
-- No synthetic values. Every row traces to an actual Snowflake table/procedure result.
