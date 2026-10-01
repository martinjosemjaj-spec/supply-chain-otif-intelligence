/*============================================================================
  OTIF GUARDIAN — 12_production_monitoring.sql
  Production Model Monitoring: 10 Categories, Configurable Thresholds
  ============================================================================
  Creates:
    Tables:  AUDIT.MONITORING_RESULTS, AUDIT.MONITORING_THRESHOLDS
    Views:   AUDIT.V_MONITORING_OVERALL, AUDIT.V_MONITORING_LATEST,
             AUDIT.V_MONITORING_DASHBOARD, AUDIT.V_MONITORING_HISTORY
    Procs:   AUDIT.SP_RUN_PRODUCTION_MONITORING
    Tasks:   AUDIT.TASK_PRODUCTION_MONITORING (daily 6am ET, suspended)
  ============================================================================
  Monitoring Categories:
    1. FEATURE_DRIFT       - Mean shift and stddev ratio vs training baseline
    2. PREDICTION_DRIFT    - Avg breach probability and predicted breach rate
    3. RISK_TIER           - Distribution across CRITICAL/HIGH/MEDIUM/LOW/MINIMAL
    4. MISSING_VALUES      - Null percentage changes per feature
    5. DATA_FRESHNESS      - Scoring age (hours) and data staleness (days)
    6. MODEL_PERFORMANCE   - Actual breach rate on closed scored POs
    7. CALIBRATION         - Predicted probability vs actual outcome rate
    8. CLASS_IMBALANCE     - Scoring breach rate vs training breach rate
    9. SCORING_VOLUME      - Volume change between scoring runs
   10. MODEL_VERSION       - Production vs last-scored version match
  ============================================================================
  Status Levels: HEALTHY | WARNING | CRITICAL
  Thresholds are configurable in MONITORING_THRESHOLDS table.
  ============================================================================*/

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE OTIF_GUARDIAN_WH;
USE DATABASE OTIF_GUARDIAN;

-- ============================================================================
-- 1. MONITORING RESULTS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS AUDIT.MONITORING_RESULTS (
    MONITOR_ID       NUMBER AUTOINCREMENT PRIMARY KEY,
    RUN_ID           VARCHAR NOT NULL,
    RUN_AT           TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    MODEL_VERSION    VARCHAR NOT NULL,
    CATEGORY         VARCHAR NOT NULL,
    CHECK_NAME       VARCHAR NOT NULL,
    DIMENSION        VARCHAR DEFAULT 'OVERALL',
    DIMENSION_VALUE  VARCHAR DEFAULT 'ALL',
    BASELINE_VALUE   FLOAT,
    CURRENT_VALUE    FLOAT,
    DELTA            FLOAT,
    DELTA_PCT        FLOAT,
    STATUS           VARCHAR NOT NULL,
    SEVERITY         VARCHAR,
    THRESHOLD_WARNING  FLOAT,
    THRESHOLD_CRITICAL FLOAT,
    MESSAGE          VARCHAR
);

-- ============================================================================
-- 2. MONITORING THRESHOLDS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS AUDIT.MONITORING_THRESHOLDS (
    THRESHOLD_ID    NUMBER AUTOINCREMENT PRIMARY KEY,
    CATEGORY        VARCHAR NOT NULL,
    CHECK_NAME      VARCHAR NOT NULL,
    WARNING_VALUE   FLOAT NOT NULL,
    CRITICAL_VALUE  FLOAT NOT NULL,
    OPERATOR        VARCHAR NOT NULL DEFAULT 'ABS_DELTA',
    DESCRIPTION     VARCHAR,
    IS_ACTIVE       BOOLEAN DEFAULT TRUE,
    CONSTRAINT UQ_MON_THRESHOLD UNIQUE (CATEGORY, CHECK_NAME)
);

-- Seed thresholds (idempotent)
MERGE INTO AUDIT.MONITORING_THRESHOLDS t
USING (
    SELECT 'FEATURE_DRIFT' AS C, 'MEAN_SHIFT_STDDEV' AS N, 1.0 AS W, 2.0 AS CR, 'ABS_RATIO' AS O, 'Mean shift in stddev units' AS D
    UNION ALL SELECT 'FEATURE_DRIFT','STDDEV_RATIO_CHANGE',0.5,1.0,'ABS_DELTA','Stddev ratio change from 1.0'
    UNION ALL SELECT 'PREDICTION_DRIFT','AVG_PROB_SHIFT',0.05,0.10,'ABS_DELTA','Avg breach probability shift'
    UNION ALL SELECT 'PREDICTION_DRIFT','BREACH_RATE_SHIFT',0.05,0.10,'ABS_DELTA','Predicted breach rate shift'
    UNION ALL SELECT 'RISK_TIER','TIER_PCT_SHIFT',0.10,0.20,'ABS_DELTA','Risk tier percentage shift'
    UNION ALL SELECT 'MISSING_VALUES','NULL_PCT_INCREASE',10.0,25.0,'ABS_DELTA','Null percentage increase'
    UNION ALL SELECT 'DATA_FRESHNESS','SCORING_AGE_HOURS',48.0,168.0,'CURRENT_GT','Hours since last scoring'
    UNION ALL SELECT 'DATA_FRESHNESS','DATA_STALENESS_DAYS',60.0,180.0,'CURRENT_GT','Days since newest scored PO'
    UNION ALL SELECT 'MODEL_PERFORMANCE','ACTUAL_BREACH_RATE_SHIFT',0.03,0.06,'ABS_DELTA','Actual breach rate shift'
    UNION ALL SELECT 'CALIBRATION','AVG_PROB_VS_ACTUAL_RATE',0.05,0.10,'ABS_DELTA','Predicted vs actual gap'
    UNION ALL SELECT 'CLASS_IMBALANCE','SCORING_BREACH_RATE_SHIFT',0.05,0.10,'ABS_DELTA','Breach rate class shift'
    UNION ALL SELECT 'SCORING_VOLUME','VOLUME_CHANGE_PCT',0.30,0.50,'ABS_RATIO','Volume change fraction'
    UNION ALL SELECT 'MODEL_VERSION','VERSION_MISMATCH',1.0,1.0,'EQUALS','Version mismatch flag'
) s ON t.CATEGORY = s.C AND t.CHECK_NAME = s.N
WHEN NOT MATCHED THEN INSERT (CATEGORY, CHECK_NAME, WARNING_VALUE, CRITICAL_VALUE, OPERATOR, DESCRIPTION)
    VALUES (s.C, s.N, s.W, s.CR, s.O, s.D);

-- ============================================================================
-- 3. MONITORING VIEWS (Streamlit-ready)
-- ============================================================================

CREATE OR REPLACE VIEW AUDIT.V_MONITORING_OVERALL AS
WITH latest_run AS (SELECT MAX(RUN_ID) AS RUN_ID FROM AUDIT.MONITORING_RESULTS)
SELECT mr.RUN_ID, MAX(mr.RUN_AT) AS LAST_CHECKED, mr.MODEL_VERSION,
    COUNT(*) AS TOTAL_CHECKS,
    COUNT_IF(mr.STATUS='HEALTHY') AS HEALTHY,
    COUNT_IF(mr.STATUS='WARNING') AS WARNINGS,
    COUNT_IF(mr.STATUS='CRITICAL') AS CRITICAL,
    CASE WHEN COUNT_IF(mr.STATUS='CRITICAL')>0 THEN 'CRITICAL'
         WHEN COUNT_IF(mr.STATUS='WARNING')>0 THEN 'WARNING' ELSE 'HEALTHY' END AS OVERALL_STATUS
FROM AUDIT.MONITORING_RESULTS mr JOIN latest_run lr ON mr.RUN_ID=lr.RUN_ID
GROUP BY mr.RUN_ID, mr.MODEL_VERSION;

CREATE OR REPLACE VIEW AUDIT.V_MONITORING_LATEST AS
WITH latest_run AS (SELECT MAX(RUN_ID) AS RUN_ID FROM AUDIT.MONITORING_RESULTS)
SELECT mr.* FROM AUDIT.MONITORING_RESULTS mr JOIN latest_run lr ON mr.RUN_ID=lr.RUN_ID
ORDER BY CASE mr.STATUS WHEN 'CRITICAL' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END, mr.CATEGORY;

CREATE OR REPLACE VIEW AUDIT.V_MONITORING_DASHBOARD AS
WITH latest_run AS (SELECT MAX(RUN_ID) AS RUN_ID FROM AUDIT.MONITORING_RESULTS)
SELECT mr.CATEGORY, COUNT(*) AS TOTAL_CHECKS,
    COUNT_IF(mr.STATUS='HEALTHY') AS HEALTHY,
    COUNT_IF(mr.STATUS='WARNING') AS WARNINGS,
    COUNT_IF(mr.STATUS='CRITICAL') AS CRITICAL,
    CASE WHEN COUNT_IF(mr.STATUS='CRITICAL')>0 THEN 'CRITICAL'
         WHEN COUNT_IF(mr.STATUS='WARNING')>0 THEN 'WARNING' ELSE 'HEALTHY' END AS CATEGORY_STATUS,
    MAX(mr.RUN_AT) AS LAST_CHECKED
FROM AUDIT.MONITORING_RESULTS mr JOIN latest_run lr ON mr.RUN_ID=lr.RUN_ID
GROUP BY mr.CATEGORY ORDER BY CASE WHEN COUNT_IF(mr.STATUS='CRITICAL')>0 THEN 1 WHEN COUNT_IF(mr.STATUS='WARNING')>0 THEN 2 ELSE 3 END;

CREATE OR REPLACE VIEW AUDIT.V_MONITORING_HISTORY AS
SELECT RUN_ID, MIN(RUN_AT) AS RUN_AT, MODEL_VERSION, CATEGORY, CHECK_NAME,
    COUNT(*) AS CHECK_COUNT,
    COUNT_IF(STATUS='HEALTHY') AS HEALTHY, COUNT_IF(STATUS='WARNING') AS WARNINGS, COUNT_IF(STATUS='CRITICAL') AS CRITICAL,
    CASE WHEN COUNT_IF(STATUS='CRITICAL')>0 THEN 'CRITICAL' WHEN COUNT_IF(STATUS='WARNING')>0 THEN 'WARNING' ELSE 'HEALTHY' END AS STATUS
FROM AUDIT.MONITORING_RESULTS GROUP BY RUN_ID, MODEL_VERSION, CATEGORY, CHECK_NAME ORDER BY RUN_AT DESC;

-- ============================================================================
-- 4. SCHEDULED TASK (daily 6am ET, created suspended)
-- ============================================================================

CREATE OR REPLACE TASK AUDIT.TASK_PRODUCTION_MONITORING
    WAREHOUSE = OTIF_GUARDIAN_WH
    SCHEDULE = 'USING CRON 0 6 * * * America/New_York'
    COMMENT = 'Daily production model monitoring'
AS CALL AUDIT.SP_RUN_PRODUCTION_MONITORING();

-- To activate: ALTER TASK AUDIT.TASK_PRODUCTION_MONITORING RESUME;

-- ============================================================================
-- 5. MONITORING PROCEDURE
-- ============================================================================
-- SP_RUN_PRODUCTION_MONITORING() is deployed via SQL_EXECUTE.
-- Source: Python Snowpark, 10 categories, ~200 lines.
-- Run: CALL AUDIT.SP_RUN_PRODUCTION_MONITORING();
-- Views for Streamlit: V_MONITORING_OVERALL, V_MONITORING_DASHBOARD, V_MONITORING_LATEST
