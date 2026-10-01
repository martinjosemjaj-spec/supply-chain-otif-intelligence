-- ============================================================
-- OTIF_Guardian: Monitoring & Governance Infrastructure
-- Audit tables, model metrics history, drift detection,
-- scoring logs, and scheduled monitoring tasks.
-- Generated: 2026-10-01
-- ============================================================

USE DATABASE OTIF_GUARDIAN;
USE WAREHOUSE OTIF_GUARDIAN_WH;

-- ============================================================
-- 1. AUDIT TABLES
-- ============================================================

-- 1.1 Model version history — one row per training run
CREATE TABLE IF NOT EXISTS OTIF_GUARDIAN.AUDIT.MODEL_VERSION_HISTORY (
    VERSION_ID          NUMBER AUTOINCREMENT,
    MODEL_NAME          VARCHAR NOT NULL DEFAULT 'OTIF_BREACH_PREDICTOR',
    VERSION_NAME        VARCHAR NOT NULL,
    TRAINED_AT          TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    TRAINED_BY          VARCHAR DEFAULT CURRENT_USER(),
    FRAMEWORK           VARCHAR DEFAULT 'XGBoost',
    FEATURE_COUNT       NUMBER,
    TRAIN_ROWS          NUMBER,
    TEST_ROWS           NUMBER,
    BREACH_RATE         FLOAT,
    ACCURACY            FLOAT,
    PRECISION_BREACH    FLOAT,
    RECALL_BREACH       FLOAT,
    F1_BREACH           FLOAT,
    ROC_AUC             FLOAT,
    OPTIMAL_THRESHOLD   FLOAT,
    STAGE_ARTIFACT_PATH VARCHAR,
    REGISTRY_VERSION    VARCHAR,
    HYPERPARAMETERS     VARIANT,
    NOTES               VARCHAR,
    PRIMARY KEY (VERSION_ID)
);

-- 1.2 Scoring log — one row per batch scoring run
CREATE TABLE IF NOT EXISTS OTIF_GUARDIAN.AUDIT.SCORING_LOG (
    SCORING_ID          NUMBER AUTOINCREMENT,
    SCORED_AT           TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    SCORED_BY           VARCHAR DEFAULT CURRENT_USER(),
    MODEL_VERSION       VARCHAR NOT NULL,
    LINES_SCORED        NUMBER,
    LINES_AT_RISK       NUMBER,
    AVG_BREACH_PROB     FLOAT,
    MAX_BREACH_PROB     FLOAT,
    TOTAL_REVENUE_AT_RISK FLOAT,
    SCORING_DURATION_SEC  FLOAT,
    STATUS              VARCHAR DEFAULT 'SUCCESS',
    ERROR_MESSAGE       VARCHAR,
    PRIMARY KEY (SCORING_ID)
);

-- 1.3 Drift monitor — periodic comparison of production vs training distributions
CREATE TABLE IF NOT EXISTS OTIF_GUARDIAN.AUDIT.DRIFT_MONITOR (
    CHECK_ID            NUMBER AUTOINCREMENT,
    CHECKED_AT          TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    MODEL_VERSION       VARCHAR NOT NULL,
    METRIC_NAME         VARCHAR NOT NULL,
    TRAINING_VALUE      FLOAT NOT NULL,
    CURRENT_VALUE       FLOAT NOT NULL,
    DRIFT_ABS           FLOAT,
    DRIFT_PCT           FLOAT,
    THRESHOLD           FLOAT,
    IS_DRIFTED          BOOLEAN,
    PRIMARY KEY (CHECK_ID)
);


-- ============================================================
-- 2. TABLE-BACKED MODEL METRICS (replaces hardcoded view)
-- ============================================================

CREATE TABLE IF NOT EXISTS OTIF_GUARDIAN.AUDIT.MODEL_METRICS_HISTORY (
    METRIC_ID           NUMBER AUTOINCREMENT,
    MODEL_VERSION       VARCHAR NOT NULL,
    EVALUATED_AT        TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    ACCURACY            FLOAT,
    PRECISION_BREACH    FLOAT,
    RECALL_BREACH       FLOAT,
    F1_BREACH           FLOAT,
    ROC_AUC             FLOAT,
    TP                  NUMBER,
    FP                  NUMBER,
    FN                  NUMBER,
    TN                  NUMBER,
    TOTAL               NUMBER,
    BREACH_RATE_ACTUAL  FLOAT,
    PRIMARY KEY (METRIC_ID)
);


-- ============================================================
-- 3. SEED CURRENT V2 METRICS
-- ============================================================

-- Seed model version history with V1 and V2
INSERT INTO OTIF_GUARDIAN.AUDIT.MODEL_VERSION_HISTORY
    (MODEL_NAME, VERSION_NAME, TRAINED_AT, FRAMEWORK, FEATURE_COUNT,
     TRAIN_ROWS, TEST_ROWS, BREACH_RATE, ACCURACY, PRECISION_BREACH,
     RECALL_BREACH, F1_BREACH, ROC_AUC, OPTIMAL_THRESHOLD,
     STAGE_ARTIFACT_PATH, NOTES)
SELECT 'OTIF_BREACH_PREDICTOR', 'V1', '2026-09-30 05:14:00'::TIMESTAMP_NTZ,
       'XGBoost', 30, 27351, 123, 0.0976,
       NULL, NULL, NULL, NULL, 0.5320, 0.50,
       '@MODEL_STAGE/breach_model/model.joblib',
       'Initial training. scale_pos_weight only. Low recall.'
WHERE NOT EXISTS (
    SELECT 1 FROM OTIF_GUARDIAN.AUDIT.MODEL_VERSION_HISTORY WHERE VERSION_NAME = 'V1'
);

INSERT INTO OTIF_GUARDIAN.AUDIT.MODEL_VERSION_HISTORY
    (MODEL_NAME, VERSION_NAME, TRAINED_AT, FRAMEWORK, FEATURE_COUNT,
     TRAIN_ROWS, TEST_ROWS, BREACH_RATE, ACCURACY, PRECISION_BREACH,
     RECALL_BREACH, F1_BREACH, ROC_AUC, OPTIMAL_THRESHOLD,
     STAGE_ARTIFACT_PATH, NOTES)
SELECT 'OTIF_BREACH_PREDICTOR', 'V2', '2026-09-30 06:37:50'::TIMESTAMP_NTZ,
       'XGBoost', 38, 27351, 5471, 0.0976,
       0.8967, 0.4824, 0.7978, 0.6013, 0.9502, 0.33,
       '@MODEL_STAGE/breach_model_v2/improved_model.joblib',
       'SMOTE + RandomizedSearchCV HPO + isotonic calibration. Optimal threshold 0.33.'
WHERE NOT EXISTS (
    SELECT 1 FROM OTIF_GUARDIAN.AUDIT.MODEL_VERSION_HISTORY WHERE VERSION_NAME = 'V2'
);

-- Seed model metrics history
INSERT INTO OTIF_GUARDIAN.AUDIT.MODEL_METRICS_HISTORY
    (MODEL_VERSION, EVALUATED_AT, ACCURACY, PRECISION_BREACH, RECALL_BREACH,
     F1_BREACH, ROC_AUC, TP, FP, FN, TN, TOTAL, BREACH_RATE_ACTUAL)
SELECT 'V2', '2026-09-30 06:37:50'::TIMESTAMP_NTZ,
       0.8967, 0.4824, 0.7978, 0.6013, 0.9502,
       426, 457, 108, 4480, 5471, 0.0976
WHERE NOT EXISTS (
    SELECT 1 FROM OTIF_GUARDIAN.AUDIT.MODEL_METRICS_HISTORY WHERE MODEL_VERSION = 'V2'
);

-- Seed initial scoring log
INSERT INTO OTIF_GUARDIAN.AUDIT.SCORING_LOG
    (SCORED_AT, MODEL_VERSION, LINES_SCORED, LINES_AT_RISK,
     AVG_BREACH_PROB, MAX_BREACH_PROB, TOTAL_REVENUE_AT_RISK, STATUS)
SELECT '2026-09-30 06:42:00'::TIMESTAMP_NTZ, 'V2',
       3326, 219, 0.4270, 0.9978, 5545902.53, 'SUCCESS'
WHERE NOT EXISTS (
    SELECT 1 FROM OTIF_GUARDIAN.AUDIT.SCORING_LOG WHERE MODEL_VERSION = 'V2'
);


-- ============================================================
-- 4. REPLACE V_MODEL_METRICS WITH TABLE-BACKED VIEW
-- ============================================================

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_MODEL_METRICS AS
SELECT
    ACCURACY, PRECISION_BREACH, RECALL_BREACH, F1_BREACH, ROC_AUC,
    TP, FP, FN, TN, TOTAL, BREACH_RATE_ACTUAL
FROM OTIF_GUARDIAN.AUDIT.MODEL_METRICS_HISTORY
ORDER BY EVALUATED_AT DESC
LIMIT 1;


-- ============================================================
-- 5. MONITORING VIEWS
-- ============================================================

-- 5.1 Scoring freshness: how stale are the current predictions?
CREATE OR REPLACE VIEW OTIF_GUARDIAN.AUDIT.V_SCORING_FRESHNESS AS
SELECT
    SCORED_AT,
    MODEL_VERSION,
    LINES_SCORED,
    LINES_AT_RISK,
    TOTAL_REVENUE_AT_RISK,
    DATEDIFF('hour', SCORED_AT, CURRENT_TIMESTAMP()) AS HOURS_SINCE_SCORED,
    CASE
        WHEN DATEDIFF('hour', SCORED_AT, CURRENT_TIMESTAMP()) <= 24 THEN 'FRESH'
        WHEN DATEDIFF('hour', SCORED_AT, CURRENT_TIMESTAMP()) <= 48 THEN 'STALE'
        ELSE 'CRITICAL'
    END AS FRESHNESS_STATUS
FROM OTIF_GUARDIAN.AUDIT.SCORING_LOG
ORDER BY SCORED_AT DESC
LIMIT 1;

-- 5.2 Model version summary
CREATE OR REPLACE VIEW OTIF_GUARDIAN.AUDIT.V_MODEL_VERSION_SUMMARY AS
SELECT
    VERSION_NAME,
    TRAINED_AT,
    FEATURE_COUNT,
    TRAIN_ROWS,
    ACCURACY,
    PRECISION_BREACH,
    RECALL_BREACH,
    F1_BREACH,
    ROC_AUC,
    OPTIMAL_THRESHOLD,
    NOTES
FROM OTIF_GUARDIAN.AUDIT.MODEL_VERSION_HISTORY
ORDER BY TRAINED_AT DESC;

-- 5.3 Drift summary
CREATE OR REPLACE VIEW OTIF_GUARDIAN.AUDIT.V_DRIFT_SUMMARY AS
SELECT
    CHECKED_AT,
    MODEL_VERSION,
    METRIC_NAME,
    TRAINING_VALUE,
    CURRENT_VALUE,
    DRIFT_ABS,
    DRIFT_PCT,
    IS_DRIFTED
FROM OTIF_GUARDIAN.AUDIT.DRIFT_MONITOR
WHERE CHECKED_AT = (SELECT MAX(CHECKED_AT) FROM OTIF_GUARDIAN.AUDIT.DRIFT_MONITOR)
ORDER BY ABS(DRIFT_PCT) DESC;


-- ============================================================
-- 6. DRIFT DETECTION PROCEDURE
-- ============================================================

CREATE OR REPLACE PROCEDURE OTIF_GUARDIAN.AUDIT.SP_CHECK_DRIFT()
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
BEGIN
    -- Compare current scored distribution vs training baseline
    LET v_train_breach_rate FLOAT;
    LET v_current_breach_rate FLOAT;
    LET v_train_avg_prob FLOAT;
    LET v_current_avg_prob FLOAT;
    LET v_model_version VARCHAR;

    -- Get latest model version
    SELECT VERSION_NAME INTO :v_model_version
    FROM OTIF_GUARDIAN.AUDIT.MODEL_VERSION_HISTORY
    ORDER BY TRAINED_AT DESC LIMIT 1;

    -- Training baseline breach rate
    SELECT BREACH_RATE INTO :v_train_breach_rate
    FROM OTIF_GUARDIAN.AUDIT.MODEL_VERSION_HISTORY
    WHERE VERSION_NAME = :v_model_version;

    -- Current prediction distribution
    SELECT
        AVG(BREACH_PROBABILITY) INTO :v_current_avg_prob
    FROM OTIF_GUARDIAN.ML.V_AT_RISK_LINES;

    -- Compute actual breach rate from recently closed lines (last 30 days)
    SELECT
        COUNT_IF(ACTUAL_DELIVERY_DATE > PROMISED_DELIVERY_DATE
                 OR QUANTITY_RECEIVED < QUANTITY_ORDERED) * 1.0
        / NULLIF(COUNT(*), 0) INTO :v_current_breach_rate
    FROM OTIF_GUARDIAN.RAW.PO_LINES
    WHERE LINE_STATUS IN ('CLOSED', 'SHORT_CLOSED')
      AND ACTUAL_DELIVERY_DATE >= DATEADD('day', -30, CURRENT_DATE());

    -- Log breach rate drift
    INSERT INTO OTIF_GUARDIAN.AUDIT.DRIFT_MONITOR
        (MODEL_VERSION, METRIC_NAME, TRAINING_VALUE, CURRENT_VALUE,
         DRIFT_ABS, DRIFT_PCT, THRESHOLD, IS_DRIFTED)
    VALUES (
        :v_model_version,
        'BREACH_RATE',
        :v_train_breach_rate,
        :v_current_breach_rate,
        ABS(:v_current_breach_rate - :v_train_breach_rate),
        CASE WHEN :v_train_breach_rate > 0
             THEN ABS(:v_current_breach_rate - :v_train_breach_rate) / :v_train_breach_rate * 100
             ELSE NULL END,
        15.0,
        CASE WHEN :v_train_breach_rate > 0
             THEN ABS(:v_current_breach_rate - :v_train_breach_rate) / :v_train_breach_rate * 100 > 15.0
             ELSE FALSE END
    );

    RETURN OBJECT_CONSTRUCT(
        'status', 'success',
        'model_version', :v_model_version,
        'training_breach_rate', :v_train_breach_rate,
        'current_breach_rate', :v_current_breach_rate,
        'avg_predicted_prob', :v_current_avg_prob
    );
END;


-- ============================================================
-- 7. SCHEDULED MONITORING TASKS
-- ============================================================

-- 7.1 Daily scoring freshness check
CREATE OR REPLACE TASK OTIF_GUARDIAN.AUDIT.TASK_CHECK_SCORING_FRESHNESS
    WAREHOUSE = OTIF_GUARDIAN_WH
    SCHEDULE = 'USING CRON 0 8 * * * America/New_York'
    COMMENT = 'Daily check: are predictions stale (>48h old)?'
AS
    INSERT INTO OTIF_GUARDIAN.AUDIT.DRIFT_MONITOR
        (MODEL_VERSION, METRIC_NAME, TRAINING_VALUE, CURRENT_VALUE,
         DRIFT_ABS, DRIFT_PCT, THRESHOLD, IS_DRIFTED)
    SELECT
        sl.MODEL_VERSION,
        'SCORING_FRESHNESS_HOURS',
        24.0,
        DATEDIFF('hour', sl.SCORED_AT, CURRENT_TIMESTAMP()),
        DATEDIFF('hour', sl.SCORED_AT, CURRENT_TIMESTAMP()) - 24.0,
        (DATEDIFF('hour', sl.SCORED_AT, CURRENT_TIMESTAMP()) - 24.0) / 24.0 * 100,
        48.0,
        DATEDIFF('hour', sl.SCORED_AT, CURRENT_TIMESTAMP()) > 48
    FROM OTIF_GUARDIAN.AUDIT.SCORING_LOG sl
    ORDER BY sl.SCORED_AT DESC
    LIMIT 1;

-- 7.2 Weekly drift detection
CREATE OR REPLACE TASK OTIF_GUARDIAN.AUDIT.TASK_CHECK_DRIFT
    WAREHOUSE = OTIF_GUARDIAN_WH
    SCHEDULE = 'USING CRON 0 6 * * 1 America/New_York'
    COMMENT = 'Weekly drift check: breach rate vs training baseline'
AS
    CALL OTIF_GUARDIAN.AUDIT.SP_CHECK_DRIFT();

-- NOTE: Tasks are created in SUSPENDED state by default.
-- To activate, run:
--   ALTER TASK OTIF_GUARDIAN.AUDIT.TASK_CHECK_SCORING_FRESHNESS RESUME;
--   ALTER TASK OTIF_GUARDIAN.AUDIT.TASK_CHECK_DRIFT RESUME;


-- ============================================================
-- 8. GRANTS
-- ============================================================

-- Engineer can read/write audit
GRANT ALL PRIVILEGES ON SCHEMA OTIF_GUARDIAN.AUDIT TO ROLE OTIF_GUARDIAN_ENGINEER;
GRANT SELECT ON ALL TABLES IN SCHEMA OTIF_GUARDIAN.AUDIT TO ROLE OTIF_GUARDIAN_ANALYST;
GRANT SELECT ON ALL VIEWS IN SCHEMA OTIF_GUARDIAN.AUDIT TO ROLE OTIF_GUARDIAN_ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA OTIF_GUARDIAN.AUDIT TO ROLE OTIF_GUARDIAN_APP;
GRANT SELECT ON ALL VIEWS IN SCHEMA OTIF_GUARDIAN.AUDIT TO ROLE OTIF_GUARDIAN_APP;

-- ============================================================
-- END OF MONITORING SCRIPT
-- ============================================================
