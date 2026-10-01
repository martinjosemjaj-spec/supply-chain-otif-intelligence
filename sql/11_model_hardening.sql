/*============================================================================
  OTIF GUARDIAN — 11_model_hardening.sql
  Production Model Hardening: Temporal Splits, Promotion Gates, Rollback
  ============================================================================
  Creates/Alters:
    Tables:  AUDIT.MODEL_VALIDATION_THRESHOLDS, AUDIT.PRODUCTION_MODEL_HISTORY
    Alters:  AUDIT.MODEL_VERSION_HISTORY (adds temporal split, approval, metrics cols)
    Views:   AUDIT.V_PRODUCTION_MODEL
    Procs:   ML.SP_TRAIN_HARDENED_MODEL, ML.SP_PROMOTE_MODEL,
             ML.SP_ROLLBACK_MODEL, ML.SP_VALIDATE_MODEL_INDEPENDENTLY
  ============================================================================
  Audit Findings Fixed:
    1. Random train/test split → Temporal 60/20/20 by order_date
    2. Threshold tuned on test set → Tuned on validation set
    3. No promotion gates → Configurable metric thresholds
    4. No rollback → SP_ROLLBACK_MODEL with re-scoring
    5. No independent validation → SP_VALIDATE_MODEL_INDEPENDENTLY
    6. Missing metrics → PR-AUC, Brier, calibration, confusion, probability dist, business impact
  Known Accepted Risks (documented in FEATURE_REGISTRY, not modified):
    - INVENTORY_COVERAGE_RATIO: current snapshot (MEDIUM leakage)
    - MATERIAL_BREACH_RATE: all-time without date filter (MEDIUM leakage)
    - SUPPLIER_MATERIAL_BREACH_RATE: all-time without date filter (MEDIUM leakage)
    - SUPPLIER_OPEN_PO_SHARE: current snapshot (MEDIUM leakage)
  ============================================================================*/

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE OTIF_GUARDIAN_WH;
USE DATABASE OTIF_GUARDIAN;

-- ============================================================================
-- 1. SCHEMA CHANGES TO MODEL_VERSION_HISTORY
-- ============================================================================

ALTER TABLE AUDIT.MODEL_VERSION_HISTORY ADD COLUMN IF NOT EXISTS
    TRAINING_PERIOD_START DATE,
    TRAINING_PERIOD_END DATE,
    VALIDATION_PERIOD_START DATE,
    VALIDATION_PERIOD_END DATE,
    TEST_PERIOD_START DATE,
    TEST_PERIOD_END DATE,
    VALIDATION_ROWS NUMBER,
    PR_AUC FLOAT,
    BRIER_SCORE FLOAT,
    EXPECTED_CALIBRATION_ERROR FLOAT,
    CALIBRATION_SLOPE FLOAT,
    CALIBRATION_INTERCEPT FLOAT,
    CONFUSION_MATRIX VARIANT,
    PROB_DISTRIBUTION VARIANT,
    BUSINESS_IMPACT VARIANT,
    FEATURE_SET_VERSION_LABEL VARCHAR,
    APPROVAL_STATUS VARCHAR DEFAULT 'APPROVED',
    APPROVED_BY VARCHAR,
    APPROVED_AT TIMESTAMP,
    IS_PRODUCTION BOOLEAN DEFAULT FALSE,
    PREVIOUS_PRODUCTION_VERSION VARCHAR;

-- ============================================================================
-- 2. VALIDATION THRESHOLDS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS AUDIT.MODEL_VALIDATION_THRESHOLDS (
    THRESHOLD_ID    NUMBER AUTOINCREMENT PRIMARY KEY,
    METRIC_NAME     VARCHAR NOT NULL UNIQUE,
    OPERATOR        VARCHAR NOT NULL,
    THRESHOLD_VALUE FLOAT NOT NULL,
    IS_ACTIVE       BOOLEAN DEFAULT TRUE,
    DESCRIPTION     VARCHAR,
    CREATED_AT      TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Seed thresholds (idempotent via MERGE)
MERGE INTO AUDIT.MODEL_VALIDATION_THRESHOLDS t
USING (
    SELECT 'ROC_AUC' AS MN, '>=' AS OP, 0.85 AS TV, 'Minimum ROC-AUC on test set' AS D
    UNION ALL SELECT 'RECALL_BREACH', '>=', 0.60, 'Minimum recall for breach class'
    UNION ALL SELECT 'F1_BREACH', '>=', 0.40, 'Minimum F1 for breach class'
    UNION ALL SELECT 'PR_AUC', '>=', 0.25, 'Minimum precision-recall AUC'
    UNION ALL SELECT 'BRIER_SCORE', '<=', 0.15, 'Maximum Brier score'
    UNION ALL SELECT 'OVERFIT_GAP', '<=', 0.10, 'Maximum train-test ROC-AUC gap'
) s ON t.METRIC_NAME = s.MN
WHEN NOT MATCHED THEN INSERT (METRIC_NAME, OPERATOR, THRESHOLD_VALUE, DESCRIPTION)
    VALUES (s.MN, s.OP, s.TV, s.D);

-- ============================================================================
-- 3. PRODUCTION MODEL HISTORY TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS AUDIT.PRODUCTION_MODEL_HISTORY (
    PROMOTION_ID    NUMBER AUTOINCREMENT PRIMARY KEY,
    MODEL_NAME      VARCHAR NOT NULL,
    VERSION_NAME    VARCHAR NOT NULL,
    PROMOTED_AT     TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    PROMOTED_BY     VARCHAR DEFAULT CURRENT_USER(),
    DEMOTED_AT      TIMESTAMP,
    DEMOTED_BY      VARCHAR,
    ACTION          VARCHAR NOT NULL DEFAULT 'PROMOTE',
    ROLLBACK_FROM   VARCHAR,
    NOTES           VARCHAR
);

-- ============================================================================
-- 4. V_PRODUCTION_MODEL VIEW
-- ============================================================================

CREATE OR REPLACE VIEW AUDIT.V_PRODUCTION_MODEL AS
SELECT
    mvh.VERSION_NAME, mvh.TRAINED_AT, mvh.TRAINED_BY,
    mvh.FEATURE_COUNT, mvh.TRAIN_ROWS, mvh.VALIDATION_ROWS, mvh.TEST_ROWS,
    mvh.ACCURACY, mvh.PRECISION_BREACH, mvh.RECALL_BREACH, mvh.F1_BREACH,
    mvh.ROC_AUC, mvh.PR_AUC, mvh.BRIER_SCORE, mvh.OPTIMAL_THRESHOLD,
    mvh.TRAINING_PERIOD_START, mvh.TRAINING_PERIOD_END,
    mvh.VALIDATION_PERIOD_START, mvh.VALIDATION_PERIOD_END,
    mvh.TEST_PERIOD_START, mvh.TEST_PERIOD_END,
    mvh.APPROVAL_STATUS, mvh.APPROVED_BY, mvh.APPROVED_AT,
    mvh.STAGE_ARTIFACT_PATH, mvh.CONFUSION_MATRIX,
    mvh.BUSINESS_IMPACT, mvh.PREVIOUS_PRODUCTION_VERSION,
    mvh.FEATURE_SET_VERSION_LABEL, mvh.HYPERPARAMETERS, mvh.NOTES
FROM AUDIT.MODEL_VERSION_HISTORY mvh
WHERE mvh.IS_PRODUCTION = TRUE AND mvh.MODEL_NAME = 'OTIF_BREACH_PREDICTOR';

-- ============================================================================
-- 5-8. STORED PROCEDURES
-- ============================================================================
-- Procedures are deployed in ML schema (not AUDIT) because they need
-- stage access via EXECUTE AS OWNER, and MODEL_STAGE is in ML schema.
--
-- SP_TRAIN_HARDENED_MODEL(P_VERSION_NAME):  Train with temporal splits
-- SP_PROMOTE_MODEL(P_VERSION_NAME):         Validate gates + promote + re-score
-- SP_ROLLBACK_MODEL():                      Revert to previous production version
-- SP_VALIDATE_MODEL_INDEPENDENTLY(P_VER):   Independent metric verification
--
-- These procedures are deployed via SQL_EXECUTE in the hardening session.
-- See the procedure source in the Snowflake ML schema.
-- Workflow:
--   1. CALL ML.SP_TRAIN_HARDENED_MODEL('V3');        -- trains, saves PENDING
--   2. CALL ML.SP_PROMOTE_MODEL('V3');               -- validates gates, promotes, re-scores
--   3. CALL ML.SP_VALIDATE_MODEL_INDEPENDENTLY('V3'); -- independent verification
--   4. CALL ML.SP_ROLLBACK_MODEL();                  -- rollback if needed
