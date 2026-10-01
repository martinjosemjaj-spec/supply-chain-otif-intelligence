-- ============================================================
-- OTIF_Guardian: Data Quality Framework
-- Production-grade DQ checks with governed result tables,
-- severity classification, and scoring gate.
-- Generated: 2026-10-01
-- ============================================================
--
-- USAGE:
--   CALL OTIF_GUARDIAN.AUDIT.SP_RUN_DQ_CHECKS();    -- Run all 86 checks
--   CALL OTIF_GUARDIAN.AUDIT.SP_DQ_GATE();           -- Check if scoring is allowed
--   SELECT * FROM OTIF_GUARDIAN.AUDIT.V_DQ_CATEGORY_SUMMARY;  -- Category breakdown
--   SELECT * FROM OTIF_GUARDIAN.AUDIT.V_DQ_FAILURES;          -- Current failures only
--
-- GATE LOGIC:
--   CRITICAL failure → GATE_STATUS = 'BLOCKED' → scoring must not proceed
--   WARNING only     → GATE_STATUS = 'PASS'    → scoring allowed
--
-- ============================================================

USE DATABASE OTIF_GUARDIAN;
USE WAREHOUSE OTIF_GUARDIAN_WH;

-- ============================================================
-- 1. RESULT TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS OTIF_GUARDIAN.AUDIT.DQ_CHECK_RESULTS (
    CHECK_ID            NUMBER AUTOINCREMENT,
    RUN_ID              VARCHAR NOT NULL,
    CHECK_NAME          VARCHAR NOT NULL,
    CATEGORY            VARCHAR NOT NULL,
    DATASET             VARCHAR NOT NULL,
    SEVERITY            VARCHAR NOT NULL,
    STATUS              VARCHAR NOT NULL,
    EXPECTED_VALUE      VARCHAR,
    ACTUAL_VALUE        VARCHAR,
    ERROR_MESSAGE       VARCHAR,
    EXECUTION_TIME      TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (CHECK_ID)
);

CREATE TABLE IF NOT EXISTS OTIF_GUARDIAN.AUDIT.DQ_RUN_SUMMARY (
    RUN_ID              VARCHAR NOT NULL,
    STARTED_AT          TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    COMPLETED_AT        TIMESTAMP_NTZ,
    TOTAL_CHECKS        NUMBER DEFAULT 0,
    PASSED              NUMBER DEFAULT 0,
    WARNINGS            NUMBER DEFAULT 0,
    CRITICAL_FAILURES   NUMBER DEFAULT 0,
    GATE_STATUS         VARCHAR DEFAULT 'PENDING',
    PRIMARY KEY (RUN_ID)
);

-- ============================================================
-- 2. MONITORING VIEWS
-- ============================================================

CREATE OR REPLACE VIEW OTIF_GUARDIAN.AUDIT.V_DQ_FAILURES AS
SELECT CHECK_NAME, CATEGORY, DATASET, SEVERITY, ACTUAL_VALUE, ERROR_MESSAGE, EXECUTION_TIME
FROM OTIF_GUARDIAN.AUDIT.DQ_CHECK_RESULTS
WHERE RUN_ID = (SELECT RUN_ID FROM OTIF_GUARDIAN.AUDIT.DQ_RUN_SUMMARY ORDER BY STARTED_AT DESC LIMIT 1)
  AND STATUS = 'FAIL'
ORDER BY CASE SEVERITY WHEN 'CRITICAL' THEN 0 ELSE 1 END, CATEGORY, CHECK_NAME;

CREATE OR REPLACE VIEW OTIF_GUARDIAN.AUDIT.V_DQ_CATEGORY_SUMMARY AS
SELECT
    CATEGORY,
    COUNT(*) AS TOTAL_CHECKS,
    COUNT_IF(STATUS = 'PASS') AS PASSED,
    COUNT_IF(STATUS = 'FAIL' AND SEVERITY = 'WARNING') AS WARNINGS,
    COUNT_IF(STATUS = 'FAIL' AND SEVERITY = 'CRITICAL') AS CRITICAL_FAILS
FROM OTIF_GUARDIAN.AUDIT.DQ_CHECK_RESULTS
WHERE RUN_ID = (SELECT RUN_ID FROM OTIF_GUARDIAN.AUDIT.DQ_RUN_SUMMARY ORDER BY STARTED_AT DESC LIMIT 1)
GROUP BY CATEGORY
ORDER BY CRITICAL_FAILS DESC, WARNINGS DESC;

CREATE OR REPLACE VIEW OTIF_GUARDIAN.AUDIT.V_DQ_LATEST_RUN AS
SELECT r.*, s.GATE_STATUS, s.TOTAL_CHECKS, s.PASSED, s.WARNINGS, s.CRITICAL_FAILURES
FROM OTIF_GUARDIAN.AUDIT.DQ_CHECK_RESULTS r
JOIN OTIF_GUARDIAN.AUDIT.DQ_RUN_SUMMARY s ON r.RUN_ID = s.RUN_ID
WHERE s.RUN_ID = (SELECT RUN_ID FROM OTIF_GUARDIAN.AUDIT.DQ_RUN_SUMMARY ORDER BY STARTED_AT DESC LIMIT 1)
ORDER BY CASE r.STATUS WHEN 'FAIL' THEN 0 ELSE 1 END,
         CASE r.SEVERITY WHEN 'CRITICAL' THEN 0 ELSE 1 END,
         r.CATEGORY, r.CHECK_NAME;

-- ============================================================
-- 3. MAIN DQ PROCEDURE: SP_RUN_DQ_CHECKS
--    (see CREATE OR REPLACE PROCEDURE above — deployed separately)
-- ============================================================
-- CALL OTIF_GUARDIAN.AUDIT.SP_RUN_DQ_CHECKS();

-- ============================================================
-- 4. GATE PROCEDURE: SP_DQ_GATE
--    (see CREATE OR REPLACE PROCEDURE above — deployed separately)
-- ============================================================
-- CALL OTIF_GUARDIAN.AUDIT.SP_DQ_GATE();

-- ============================================================
-- 5. GRANTS
-- ============================================================

GRANT SELECT ON ALL TABLES IN SCHEMA OTIF_GUARDIAN.AUDIT TO ROLE OTIF_GUARDIAN_ANALYST;
GRANT SELECT ON ALL VIEWS IN SCHEMA OTIF_GUARDIAN.AUDIT TO ROLE OTIF_GUARDIAN_ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA OTIF_GUARDIAN.AUDIT TO ROLE OTIF_GUARDIAN_APP;
GRANT SELECT ON ALL VIEWS IN SCHEMA OTIF_GUARDIAN.AUDIT TO ROLE OTIF_GUARDIAN_APP;

-- ============================================================
-- END OF DATA QUALITY FRAMEWORK
-- ============================================================
