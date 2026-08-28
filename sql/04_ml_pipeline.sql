-- ============================================================
-- OTIF_Guardian: ML Pipeline - OTIF Breach Prediction
-- Target: Predict whether an inbound PO line will breach OTIF
-- Method: Snowflake Native ML Classification + Model Registry
-- Generated: 2026-08-28
-- ============================================================
--
-- ARCHITECTURE:
--   Feature Engineering (SQL Views)
--   → Temporal Train/Test Split (no leakage)
--   → SNOWFLAKE.ML.CLASSIFICATION (native XGBoost)
--   → Model Registry (versioned)
--   → Inference Pipeline (batch scoring)
--   → Explainability (feature importance + reason codes)
--
-- LEAKAGE PREVENTION:
--   1. No actual_delivery_date or quantity_received in features
--   2. Historical aggregates computed ONLY from data prior to the PO's order_date
--   3. Temporal split: train on older data, test on newer data
--   4. No shipment/receipt data used (these occur AFTER the prediction point)
--
-- ============================================================

USE DATABASE OTIF_GUARDIAN;
USE SCHEMA ML;
USE WAREHOUSE OTIF_GUARDIAN_WH;

-- ============================================================
-- PART 1: FEATURE ENGINEERING
-- ============================================================

-- 1.1 Historical supplier performance (computed at time of PO creation)
-- This CTE computes supplier metrics using ONLY data prior to each PO line's order date

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_SUPPLIER_HISTORY AS
SELECT
    po_current.po_id AS current_po_id,
    po_current.supplier_id,
    po_current.order_date AS current_order_date,
    -- Supplier historical OTD (from PO lines closed BEFORE this PO was created)
    COUNT(pl_hist.po_line_id) AS hist_total_lines,
    COUNT_IF(
        pl_hist.actual_delivery_date IS NOT NULL
        AND pl_hist.actual_delivery_date <= pl_hist.promised_delivery_date
    ) AS hist_on_time_lines,
    COUNT_IF(
        pl_hist.quantity_received >= pl_hist.quantity_ordered
        AND pl_hist.line_status = 'CLOSED'
    ) AS hist_in_full_lines,
    -- Historical OTIF rate for this supplier (prior to this PO)
    CASE WHEN COUNT(pl_hist.po_line_id) > 0
        THEN COUNT_IF(
            pl_hist.actual_delivery_date <= pl_hist.promised_delivery_date
            AND pl_hist.quantity_received >= pl_hist.quantity_ordered
        ) * 1.0 / COUNT(pl_hist.po_line_id)
        ELSE NULL
    END AS hist_otif_rate,
    -- Average delivery variance (days late/early)
    AVG(DATEDIFF('day', pl_hist.promised_delivery_date, pl_hist.actual_delivery_date)) AS hist_avg_delivery_variance,
    -- Stddev of delivery variance (consistency)
    STDDEV(DATEDIFF('day', pl_hist.promised_delivery_date, pl_hist.actual_delivery_date)) AS hist_stddev_delivery_variance,
    -- Recent performance (last 90 days before this PO)
    COUNT_IF(
        po_hist.order_date >= DATEADD('day', -90, po_current.order_date)
    ) AS hist_recent_90d_lines,
    CASE WHEN COUNT_IF(po_hist.order_date >= DATEADD('day', -90, po_current.order_date)) > 0
        THEN COUNT_IF(
            po_hist.order_date >= DATEADD('day', -90, po_current.order_date)
            AND pl_hist.actual_delivery_date <= pl_hist.promised_delivery_date
            AND pl_hist.quantity_received >= pl_hist.quantity_ordered
        ) * 1.0 / NULLIF(COUNT_IF(po_hist.order_date >= DATEADD('day', -90, po_current.order_date)), 0)
        ELSE NULL
    END AS hist_recent_90d_otif_rate
FROM OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po_current
LEFT JOIN OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po_hist
    ON po_current.supplier_id = po_hist.supplier_id
    AND po_hist.order_date < po_current.order_date  -- STRICT temporal: only prior orders
LEFT JOIN OTIF_GUARDIAN.RAW.PO_LINES pl_hist
    ON po_hist.po_id = pl_hist.po_id
    AND pl_hist.actual_delivery_date IS NOT NULL     -- Only completed lines
    AND pl_hist.actual_delivery_date < po_current.order_date  -- Delivered before this PO
GROUP BY po_current.po_id, po_current.supplier_id, po_current.order_date;


-- 1.2 Material demand volatility (computed prior to PO date)

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_MATERIAL_DEMAND_FEATURES AS
SELECT
    pl.po_line_id,
    pl.material_id,
    po.order_date,
    -- Demand in the 30 days prior to PO
    COALESCE(dem.demand_30d_qty, 0) AS demand_30d_qty,
    COALESCE(dem.demand_30d_count, 0) AS demand_30d_count
FROM OTIF_GUARDIAN.RAW.PO_LINES pl
JOIN OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po ON pl.po_id = po.po_id
LEFT JOIN (
    SELECT
        d.material_id,
        po_ref.po_line_id,
        SUM(d.quantity_demanded) AS demand_30d_qty,
        COUNT(*) AS demand_30d_count
    FROM OTIF_GUARDIAN.RAW.DEMAND d
    JOIN (
        SELECT pl2.po_line_id, pl2.material_id, po2.order_date
        FROM OTIF_GUARDIAN.RAW.PO_LINES pl2
        JOIN OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po2 ON pl2.po_id = po2.po_id
    ) po_ref ON d.material_id = po_ref.material_id
    WHERE d.demand_date BETWEEN DATEADD('day', -30, po_ref.order_date) AND po_ref.order_date
    GROUP BY d.material_id, po_ref.po_line_id
) dem ON pl.po_line_id = dem.po_line_id;


-- 1.3 Master feature table (leakage-free)

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_FEATURE_SET AS
SELECT
    pl.po_line_id,
    po.po_id,
    po.order_date,
    pl.promised_delivery_date,

    -- ========== TARGET (label) ==========
    -- Only compute for closed/delivered lines (NULL for open lines)
    CASE
        WHEN pl.actual_delivery_date IS NOT NULL
             AND pl.line_status IN ('CLOSED', 'SHORT_CLOSED')
        THEN CASE
            WHEN pl.actual_delivery_date > pl.promised_delivery_date
                 OR pl.quantity_received < pl.quantity_ordered
            THEN 1  -- BREACH
            ELSE 0  -- NO BREACH
        END
        ELSE NULL  -- Open lines (used for inference, not training)
    END AS OTIF_BREACH,

    -- ========== FEATURES (all available at PO creation time) ==========

    -- Supplier attributes (known at PO creation)
    s.supplier_tier,
    s.standard_lead_time_days AS supplier_std_lead_time,
    s.historical_otd_pct AS supplier_master_otd,
    s.quality_score AS supplier_quality_score,
    CASE WHEN s.status = 'PROBATION' THEN 1 ELSE 0 END AS supplier_on_probation,

    -- Material attributes (known at PO creation)
    m.material_category,
    m.abc_class,
    m.criticality,
    m.standard_unit_cost,
    m.weight_kg,
    m.safety_stock_days AS material_safety_days,

    -- PO line attributes (known at creation)
    pl.quantity_ordered,
    pl.unit_price,
    pl.quantity_ordered * pl.unit_price AS line_value,
    po.po_type,
    po.currency,

    -- Plant attributes
    p.region AS plant_region,
    p.country_code AS plant_country,

    -- Temporal features (derived from dates known at PO creation)
    DATEDIFF('day', po.order_date, pl.promised_delivery_date) AS promised_lead_time_days,
    DAYOFWEEK(po.order_date) AS order_day_of_week,
    MONTH(po.order_date) AS order_month,
    QUARTER(po.order_date) AS order_quarter,

    -- Lead time gap (promised vs supplier standard)
    DATEDIFF('day', po.order_date, pl.promised_delivery_date) - s.standard_lead_time_days
        AS lead_time_vs_standard,

    -- Historical supplier performance (temporal, no leakage)
    sh.hist_total_lines AS supplier_hist_volume,
    sh.hist_otif_rate AS supplier_hist_otif_rate,
    sh.hist_avg_delivery_variance AS supplier_hist_avg_variance,
    sh.hist_stddev_delivery_variance AS supplier_hist_stddev_variance,
    sh.hist_recent_90d_otif_rate AS supplier_recent_otif_rate,

    -- Material demand features
    mdf.demand_30d_qty,
    mdf.demand_30d_count,

    -- Sourcing risk
    COALESCE(alt.active_alt_count, 0) AS material_alt_supplier_count,
    CASE WHEN COALESCE(alt.active_alt_count, 0) <= 1 THEN 1 ELSE 0 END AS is_single_sourced

FROM OTIF_GUARDIAN.RAW.PO_LINES pl
JOIN OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po ON pl.po_id = po.po_id
JOIN OTIF_GUARDIAN.RAW.SUPPLIERS s ON po.supplier_id = s.supplier_id
JOIN OTIF_GUARDIAN.RAW.MATERIALS m ON pl.material_id = m.material_id
JOIN OTIF_GUARDIAN.RAW.PLANTS p ON po.plant_id = p.plant_id
LEFT JOIN OTIF_GUARDIAN.ML.V_SUPPLIER_HISTORY sh
    ON po.po_id = sh.current_po_id
LEFT JOIN OTIF_GUARDIAN.ML.V_MATERIAL_DEMAND_FEATURES mdf
    ON pl.po_line_id = mdf.po_line_id
LEFT JOIN (
    SELECT material_id, COUNT(*) AS active_alt_count
    FROM OTIF_GUARDIAN.RAW.ALTERNATE_SUPPLIERS
    WHERE status = 'ACTIVE'
    GROUP BY material_id
) alt ON m.material_id = alt.material_id;


-- ============================================================
-- PART 2: TEMPORAL TRAIN/TEST SPLIT
-- ============================================================
-- Split point: 2026-06-01
-- Train: All PO lines with order_date < 2026-06-01 (and label IS NOT NULL)
-- Test:  All PO lines with order_date >= 2026-06-01 AND < 2026-08-01 (and label IS NOT NULL)
-- Score: Open lines (label IS NULL) — used for inference

CREATE OR REPLACE TABLE OTIF_GUARDIAN.ML.TRAIN_DATA AS
SELECT * EXCLUDE (po_id, po_line_id, order_date, promised_delivery_date)
FROM OTIF_GUARDIAN.ML.V_FEATURE_SET
WHERE OTIF_BREACH IS NOT NULL
  AND order_date < '2026-06-01'::DATE;

CREATE OR REPLACE TABLE OTIF_GUARDIAN.ML.TEST_DATA AS
SELECT * EXCLUDE (po_id, po_line_id, order_date, promised_delivery_date)
FROM OTIF_GUARDIAN.ML.V_FEATURE_SET
WHERE OTIF_BREACH IS NOT NULL
  AND order_date >= '2026-06-01'::DATE
  AND order_date < '2026-08-01'::DATE;

CREATE OR REPLACE TABLE OTIF_GUARDIAN.ML.SCORE_DATA AS
SELECT *
FROM OTIF_GUARDIAN.ML.V_FEATURE_SET
WHERE OTIF_BREACH IS NULL;  -- Open lines for prediction


-- ============================================================
-- PART 3: MODEL TRAINING
-- ============================================================
-- Uses Snowflake native ML Classification (XGBoost-based)
-- Automatically handles categorical encoding, missing values, hyperparameter tuning

CREATE OR REPLACE SNOWFLAKE.ML.CLASSIFICATION OTIF_GUARDIAN.ML.OTIF_BREACH_MODEL(
    INPUT_DATA => SYSTEM$REFERENCE('TABLE', 'OTIF_GUARDIAN.ML.TRAIN_DATA'),
    TARGET_COLNAME => 'OTIF_BREACH',
    CONFIG_OBJECT => {
        'ON_ERROR': 'SKIP'
    }
);

-- ============================================================
-- PART 4: MODEL EVALUATION ON TEST SET
-- ============================================================

-- 4.1 Generate predictions on test data
CREATE OR REPLACE TABLE OTIF_GUARDIAN.ML.TEST_PREDICTIONS AS
SELECT
    *,
    OTIF_GUARDIAN.ML.OTIF_BREACH_MODEL!PREDICT(
        INPUT_DATA => OBJECT_CONSTRUCT(*)
    ) AS prediction_result
FROM OTIF_GUARDIAN.ML.TEST_DATA;

-- 4.2 Extract prediction components
CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_TEST_RESULTS AS
SELECT
    OTIF_BREACH AS actual_label,
    prediction_result:"class"::INT AS predicted_label,
    prediction_result:"probability":"1"::FLOAT AS breach_probability,
    prediction_result:"probability":"0"::FLOAT AS no_breach_probability,
    *
FROM OTIF_GUARDIAN.ML.TEST_PREDICTIONS;

-- 4.3 Confusion matrix
CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_CONFUSION_MATRIX AS
SELECT
    actual_label,
    predicted_label,
    COUNT(*) AS cnt
FROM OTIF_GUARDIAN.ML.V_TEST_RESULTS
GROUP BY actual_label, predicted_label
ORDER BY actual_label, predicted_label;

-- 4.4 Model metrics
CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_MODEL_METRICS AS
WITH confusion AS (
    SELECT
        COUNT_IF(actual_label = 1 AND predicted_label = 1) AS TP,
        COUNT_IF(actual_label = 0 AND predicted_label = 1) AS FP,
        COUNT_IF(actual_label = 1 AND predicted_label = 0) AS FN,
        COUNT_IF(actual_label = 0 AND predicted_label = 0) AS TN,
        COUNT(*) AS total
    FROM OTIF_GUARDIAN.ML.V_TEST_RESULTS
)
SELECT
    -- Accuracy
    ROUND((TP + TN) * 1.0 / total, 4) AS accuracy,
    -- Precision (of breach predictions, how many were actual breaches)
    ROUND(TP * 1.0 / NULLIF(TP + FP, 0), 4) AS precision_breach,
    -- Recall (of actual breaches, how many did we catch)
    ROUND(TP * 1.0 / NULLIF(TP + FN, 0), 4) AS recall_breach,
    -- F1 Score
    ROUND(2.0 * (TP * 1.0 / NULLIF(TP + FP, 0)) * (TP * 1.0 / NULLIF(TP + FN, 0))
        / NULLIF((TP * 1.0 / NULLIF(TP + FP, 0)) + (TP * 1.0 / NULLIF(TP + FN, 0)), 0), 4) AS f1_breach,
    -- Specificity
    ROUND(TN * 1.0 / NULLIF(TN + FP, 0), 4) AS specificity,
    -- Counts
    TP, FP, FN, TN, total,
    -- Class balance
    ROUND((TP + FN) * 1.0 / total, 4) AS breach_rate_actual
FROM confusion;


-- ============================================================
-- PART 5: FEATURE IMPORTANCE
-- ============================================================
-- Snowflake ML Classification exposes feature importance via model methods

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_FEATURE_IMPORTANCE AS
SELECT *
FROM TABLE(OTIF_GUARDIAN.ML.OTIF_BREACH_MODEL!FEATURE_IMPORTANCE());


-- ============================================================
-- PART 6: INFERENCE PIPELINE (batch scoring of open PO lines)
-- ============================================================

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
FROM OTIF_GUARDIAN.ML.SCORE_DATA sd;

-- 6.1 Inference results view with risk tiers
CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_SCORED_RESULTS AS
SELECT
    sp.po_line_id,
    sp.po_id,
    sp.order_date,
    sp.promised_delivery_date,
    sp.prediction_result:"class"::INT AS predicted_breach,
    sp.prediction_result:"probability":"1"::FLOAT AS breach_probability,
    sp.prediction_result:"probability":"0"::FLOAT AS no_breach_probability,
    -- Risk tier
    CASE
        WHEN sp.prediction_result:"probability":"1"::FLOAT >= 0.8 THEN 'CRITICAL'
        WHEN sp.prediction_result:"probability":"1"::FLOAT >= 0.6 THEN 'HIGH'
        WHEN sp.prediction_result:"probability":"1"::FLOAT >= 0.4 THEN 'MEDIUM'
        WHEN sp.prediction_result:"probability":"1"::FLOAT >= 0.2 THEN 'LOW'
        ELSE 'MINIMAL'
    END AS risk_tier,
    -- Enrich with context
    po.po_number,
    s.supplier_name,
    s.supplier_tier,
    m.material_code,
    m.material_name,
    p.plant_code,
    DATEDIFF('day', CURRENT_DATE(), sp.promised_delivery_date) AS days_until_due
FROM OTIF_GUARDIAN.ML.SCORED_PO_LINES sp
JOIN OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po ON sp.po_id = po.po_id
JOIN OTIF_GUARDIAN.RAW.SUPPLIERS s ON po.supplier_id = s.supplier_id
JOIN OTIF_GUARDIAN.RAW.PO_LINES pl ON sp.po_line_id = pl.po_line_id
JOIN OTIF_GUARDIAN.RAW.MATERIALS m ON pl.material_id = m.material_id
JOIN OTIF_GUARDIAN.RAW.PLANTS p ON po.plant_id = p.plant_id;


-- ============================================================
-- PART 7: REASON CODES (per-prediction explainability)
-- ============================================================
-- Snowflake ML Classification provides EXPLAIN method for local explanations

-- 7.1 Generate reason codes for high-risk predictions
CREATE OR REPLACE TABLE OTIF_GUARDIAN.ML.REASON_CODES AS
SELECT
    sd.po_line_id,
    sd.po_id,
    OTIF_GUARDIAN.ML.OTIF_BREACH_MODEL!EXPLAIN(
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
    ) AS explanation
FROM OTIF_GUARDIAN.ML.SCORE_DATA sd
-- Only explain high-risk lines (score first, then explain subset)
WHERE sd.po_line_id IN (
    SELECT po_line_id
    FROM OTIF_GUARDIAN.ML.SCORED_PO_LINES
    WHERE prediction_result:"probability":"1"::FLOAT >= 0.6
);

-- 7.2 Parsed reason codes view
CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_REASON_CODES AS
SELECT
    rc.po_line_id,
    rc.po_id,
    f.key AS feature_name,
    f.value::FLOAT AS shap_contribution,
    ABS(f.value::FLOAT) AS abs_contribution,
    CASE
        WHEN f.value::FLOAT > 0 THEN 'INCREASES_RISK'
        ELSE 'DECREASES_RISK'
    END AS direction,
    ROW_NUMBER() OVER (PARTITION BY rc.po_line_id ORDER BY ABS(f.value::FLOAT) DESC) AS importance_rank
FROM OTIF_GUARDIAN.ML.REASON_CODES rc,
    LATERAL FLATTEN(INPUT => rc.explanation) f
WHERE f.key != 'bias';

-- 7.3 Top reason codes per PO line (top 5 drivers)
CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_TOP_REASON_CODES AS
SELECT
    po_line_id,
    po_id,
    feature_name,
    shap_contribution,
    direction,
    importance_rank
FROM OTIF_GUARDIAN.ML.V_REASON_CODES
WHERE importance_rank <= 5;


-- ============================================================
-- PART 8: MODEL REGISTRY
-- ============================================================
-- Register the trained model in Snowflake Model Registry for versioning

-- 8.1 Create the model registry entry
CREATE MODEL IF NOT EXISTS OTIF_GUARDIAN.ML.OTIF_BREACH_PREDICTOR
  COMMENT = 'OTIF breach prediction model for inbound PO lines. XGBoost classification via Snowflake ML.';

-- 8.2 Log the model version with metadata
-- Note: The native SNOWFLAKE.ML.CLASSIFICATION object IS the model.
-- We create a reference version pointing to it.
ALTER MODEL OTIF_GUARDIAN.ML.OTIF_BREACH_PREDICTOR
  ADD VERSION V1
  FROM MODEL OTIF_GUARDIAN.ML.OTIF_BREACH_MODEL
  COMMENT = 'Initial training: temporal split at 2026-06-01. 30 features. No leakage.';

-- 8.3 Set default version
ALTER MODEL OTIF_GUARDIAN.ML.OTIF_BREACH_PREDICTOR
  SET DEFAULT_VERSION = V1;


-- ============================================================
-- PART 9: MONITORING VIEWS
-- ============================================================

-- 9.1 Prediction distribution (drift monitoring)
CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_PREDICTION_DISTRIBUTION AS
SELECT
    risk_tier,
    COUNT(*) AS po_line_count,
    ROUND(AVG(breach_probability), 4) AS avg_breach_prob,
    MIN(breach_probability) AS min_prob,
    MAX(breach_probability) AS max_prob
FROM OTIF_GUARDIAN.ML.V_SCORED_RESULTS
GROUP BY risk_tier
ORDER BY CASE risk_tier
    WHEN 'CRITICAL' THEN 1
    WHEN 'HIGH' THEN 2
    WHEN 'MEDIUM' THEN 3
    WHEN 'LOW' THEN 4
    WHEN 'MINIMAL' THEN 5
END;

-- 9.2 Risk summary by supplier
CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_RISK_BY_SUPPLIER AS
SELECT
    supplier_name,
    supplier_tier,
    COUNT(*) AS open_lines,
    COUNT_IF(risk_tier IN ('CRITICAL', 'HIGH')) AS high_risk_lines,
    ROUND(AVG(breach_probability), 4) AS avg_breach_prob
FROM OTIF_GUARDIAN.ML.V_SCORED_RESULTS
GROUP BY supplier_name, supplier_tier
HAVING COUNT_IF(risk_tier IN ('CRITICAL', 'HIGH')) > 0
ORDER BY high_risk_lines DESC;

-- 9.3 Risk summary by material
CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_RISK_BY_MATERIAL AS
SELECT
    material_code,
    material_name,
    COUNT(*) AS open_lines,
    COUNT_IF(risk_tier IN ('CRITICAL', 'HIGH')) AS high_risk_lines,
    ROUND(AVG(breach_probability), 4) AS avg_breach_prob
FROM OTIF_GUARDIAN.ML.V_SCORED_RESULTS
GROUP BY material_code, material_name
HAVING COUNT_IF(risk_tier IN ('CRITICAL', 'HIGH')) > 0
ORDER BY high_risk_lines DESC;


-- ============================================================
-- END OF ML PIPELINE
-- ============================================================
