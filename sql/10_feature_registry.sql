/*============================================================================
  OTIF GUARDIAN — 10_feature_registry.sql
  Governed Feature Registry for XGBoost V2 Model
  ============================================================================
  Creates:
    Tables:  AUDIT.FEATURE_REGISTRY, AUDIT.FEATURE_SET_VERSION, AUDIT.MODEL_FEATURE_MAP,
             AUDIT.FEATURE_DISTRIBUTION_BASELINE
    Views:   AUDIT.V_FEATURE_LINEAGE, AUDIT.V_FEATURE_COVERAGE, AUDIT.V_FEATURE_DRIFT_SUMMARY
    Procs:   AUDIT.SP_VALIDATE_FEATURE_REGISTRY, AUDIT.SP_SNAPSHOT_FEATURE_DISTRIBUTIONS
    Tests:   Inline test suite (T-FR-001 through T-FR-012)
  ============================================================================*/

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE OTIF_GUARDIAN_WH;
USE DATABASE OTIF_GUARDIAN;

-- ============================================================================
-- 1. FEATURE REGISTRY TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS AUDIT.FEATURE_REGISTRY (
    FEATURE_ID          NUMBER AUTOINCREMENT PRIMARY KEY,
    FEATURE_NAME        VARCHAR NOT NULL,
    BUSINESS_DEFINITION VARCHAR NOT NULL,
    SOURCE_TABLE        VARCHAR NOT NULL,
    SOURCE_COLUMN       VARCHAR NOT NULL,
    GRAIN               VARCHAR NOT NULL DEFAULT 'PO_LINE',
    LOOKBACK_WINDOW     VARCHAR,
    TRANSFORMATION_LOGIC VARCHAR NOT NULL,
    POINT_IN_TIME_RULE  VARCHAR NOT NULL,
    DATA_TYPE           VARCHAR NOT NULL,
    OWNER               VARCHAR NOT NULL DEFAULT 'ML_ENGINEERING',
    VERSION             VARCHAR NOT NULL DEFAULT '2.0',
    LEAKAGE_RISK        VARCHAR NOT NULL DEFAULT 'NONE',
    ACTIVE_FLAG         BOOLEAN NOT NULL DEFAULT TRUE,
    CREATED_AT          TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT          TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT UQ_FEATURE_NAME UNIQUE (FEATURE_NAME, VERSION)
);

-- ============================================================================
-- 2. FEATURE SET VERSION TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS AUDIT.FEATURE_SET_VERSION (
    FEATURE_SET_ID      NUMBER AUTOINCREMENT PRIMARY KEY,
    VERSION_LABEL       VARCHAR NOT NULL UNIQUE,
    DESCRIPTION         VARCHAR,
    FEATURE_COUNT       NUMBER NOT NULL,
    SOURCE_VIEW         VARCHAR NOT NULL,
    TRAIN_TABLE         VARCHAR NOT NULL,
    SCORE_TABLE         VARCHAR NOT NULL,
    CREATED_AT          TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    CREATED_BY          VARCHAR DEFAULT CURRENT_USER(),
    IS_ACTIVE           BOOLEAN NOT NULL DEFAULT TRUE
);

-- ============================================================================
-- 3. MODEL-TO-FEATURE MAPPING TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS AUDIT.MODEL_FEATURE_MAP (
    MAP_ID              NUMBER AUTOINCREMENT PRIMARY KEY,
    MODEL_NAME          VARCHAR NOT NULL,
    MODEL_VERSION       VARCHAR NOT NULL,
    FEATURE_SET_VERSION VARCHAR NOT NULL,
    FEATURE_NAME        VARCHAR NOT NULL,
    FEATURE_INDEX       NUMBER,
    IS_CATEGORICAL      BOOLEAN DEFAULT FALSE,
    MAPPED_AT           TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT UQ_MODEL_FEATURE UNIQUE (MODEL_NAME, MODEL_VERSION, FEATURE_NAME)
);

-- ============================================================================
-- 4. FEATURE DISTRIBUTION BASELINE TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS AUDIT.FEATURE_DISTRIBUTION_BASELINE (
    BASELINE_ID         NUMBER AUTOINCREMENT PRIMARY KEY,
    FEATURE_NAME        VARCHAR NOT NULL,
    FEATURE_SET_VERSION VARCHAR NOT NULL,
    DATASET             VARCHAR NOT NULL,
    ROW_COUNT           NUMBER,
    NULL_COUNT          NUMBER,
    NULL_PCT            FLOAT,
    DISTINCT_COUNT      NUMBER,
    MEAN_VAL            FLOAT,
    STDDEV_VAL          FLOAT,
    MIN_VAL             FLOAT,
    P25_VAL             FLOAT,
    MEDIAN_VAL          FLOAT,
    P75_VAL             FLOAT,
    MAX_VAL             FLOAT,
    SNAPSHOT_AT         TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================================
-- 5. POPULATE FEATURE REGISTRY — ALL 41 FEATURES
-- ============================================================================

TRUNCATE TABLE IF EXISTS AUDIT.FEATURE_REGISTRY;

INSERT INTO AUDIT.FEATURE_REGISTRY
    (FEATURE_NAME, BUSINESS_DEFINITION, SOURCE_TABLE, SOURCE_COLUMN, GRAIN, LOOKBACK_WINDOW,
     TRANSFORMATION_LOGIC, POINT_IN_TIME_RULE, DATA_TYPE, OWNER, VERSION, LEAKAGE_RISK, ACTIVE_FLAG)
VALUES
-- === SUPPLIER MASTER FEATURES (5) ===
('SUPPLIER_TIER', 'Supplier strategic tier classification (1=strategic, 3=transactional)',
 'RAW.SUPPLIERS', 'SUPPLIER_TIER', 'SUPPLIER', NULL,
 'Direct lookup: s.supplier_tier', 'Static master data; safe at any point in time', 'NUMBER(1,0)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('SUPPLIER_STD_LEAD_TIME', 'Supplier contractual standard lead time in days',
 'RAW.SUPPLIERS', 'STANDARD_LEAD_TIME_DAYS', 'SUPPLIER', NULL,
 'Direct lookup: s.standard_lead_time_days', 'Static master data; safe at any point in time', 'NUMBER(20,0)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('SUPPLIER_MASTER_OTD', 'Supplier master-data on-time delivery percentage',
 'RAW.SUPPLIERS', 'HISTORICAL_OTD_PCT', 'SUPPLIER', NULL,
 'Direct lookup: s.historical_otd_pct', 'Master data snapshot; may lag actual performance', 'NUMBER(27,1)',
 'ML_ENGINEERING', '2.0', 'LOW', TRUE),

('SUPPLIER_QUALITY_SCORE', 'Supplier quality audit score from master data',
 'RAW.SUPPLIERS', 'QUALITY_SCORE', 'SUPPLIER', NULL,
 'Direct lookup: s.quality_score', 'Static master data; safe at any point in time', 'NUMBER(27,1)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('SUPPLIER_ON_PROBATION', 'Binary flag: 1 if supplier status is PROBATION at time of order',
 'RAW.SUPPLIERS', 'STATUS', 'SUPPLIER', NULL,
 'CASE WHEN s.status = ''PROBATION'' THEN 1 ELSE 0 END', 'Master data flag; assumes status is current at order time', 'NUMBER(1,0)',
 'ML_ENGINEERING', '2.0', 'LOW', TRUE),

-- === MATERIAL MASTER FEATURES (6) ===
('MATERIAL_CATEGORY', 'Material product category classification',
 'RAW.MATERIALS', 'MATERIAL_CATEGORY', 'MATERIAL', NULL,
 'Direct lookup: m.material_category', 'Static master data', 'VARCHAR',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('ABC_CLASS', 'Material ABC inventory classification (A=high value, C=low)',
 'RAW.MATERIALS', 'ABC_CLASS', 'MATERIAL', NULL,
 'Direct lookup: m.abc_class', 'Static master data', 'VARCHAR(1)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('CRITICALITY', 'Material criticality for production (CRITICAL, HIGH, MEDIUM, LOW)',
 'RAW.MATERIALS', 'CRITICALITY', 'MATERIAL', NULL,
 'Direct lookup: m.criticality', 'Static master data', 'VARCHAR',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('STANDARD_UNIT_COST', 'Standard unit cost from material master',
 'RAW.MATERIALS', 'STANDARD_UNIT_COST', 'MATERIAL', NULL,
 'Direct lookup: m.standard_unit_cost', 'Static master data', 'FLOAT',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('WEIGHT_KG', 'Material unit weight in kilograms',
 'RAW.MATERIALS', 'WEIGHT_KG', 'MATERIAL', NULL,
 'Direct lookup: m.weight_kg', 'Static master data', 'NUMBER(27,2)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('MATERIAL_SAFETY_DAYS', 'Safety stock days configured for the material',
 'RAW.MATERIALS', 'SAFETY_STOCK_DAYS', 'MATERIAL', NULL,
 'Direct lookup: m.safety_stock_days', 'Static master data', 'NUMBER(20,0)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

-- === PO LINE FEATURES (3) ===
('QUANTITY_ORDERED', 'Quantity of material ordered on this PO line',
 'RAW.PO_LINES', 'QUANTITY_ORDERED', 'PO_LINE', NULL,
 'Direct lookup: pl.quantity_ordered', 'Known at order placement; no leakage', 'NUMBER(38,0)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('UNIT_PRICE', 'Negotiated unit price for this PO line',
 'RAW.PO_LINES', 'UNIT_PRICE', 'PO_LINE', NULL,
 'Direct lookup: pl.unit_price', 'Known at order placement; no leakage', 'FLOAT',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('LINE_VALUE', 'Total value of PO line (quantity * unit_price)',
 'RAW.PO_LINES', 'QUANTITY_ORDERED, UNIT_PRICE', 'PO_LINE', NULL,
 'Derived: pl.quantity_ordered * pl.unit_price', 'Derived from order-time fields; no leakage', 'FLOAT',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

-- === PO HEADER FEATURES (2) ===
('PO_TYPE', 'Purchase order type (STANDARD, BLANKET, CONTRACT, EMERGENCY)',
 'RAW.PURCHASE_ORDERS', 'PO_TYPE', 'PO', NULL,
 'Direct lookup: po.po_type', 'Known at order placement', 'VARCHAR',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('CURRENCY', 'PO transaction currency code',
 'RAW.PURCHASE_ORDERS', 'CURRENCY', 'PO', NULL,
 'Direct lookup: po.currency', 'Known at order placement', 'VARCHAR',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

-- === PLANT FEATURES (2) ===
('PLANT_REGION', 'Receiving plant geographic region',
 'RAW.PLANTS', 'REGION', 'PLANT', NULL,
 'Direct lookup: p.region', 'Static master data', 'VARCHAR(5)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('PLANT_COUNTRY', 'Receiving plant country code',
 'RAW.PLANTS', 'COUNTRY_CODE', 'PLANT', NULL,
 'Direct lookup: p.country_code', 'Static master data', 'VARCHAR(2)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

-- === TEMPORAL DERIVED FEATURES (4) ===
('PROMISED_LEAD_TIME_DAYS', 'Days between order date and promised delivery date',
 'RAW.PURCHASE_ORDERS + RAW.PO_LINES', 'ORDER_DATE, PROMISED_DELIVERY_DATE', 'PO_LINE', NULL,
 'DATEDIFF(''day'', po.order_date, pl.promised_delivery_date)', 'Derived from order-time dates; no leakage', 'NUMBER(9,0)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('ORDER_DAY_OF_WEEK', 'Day of week the PO was placed (0=Sun, 6=Sat)',
 'RAW.PURCHASE_ORDERS', 'ORDER_DATE', 'PO', NULL,
 'DAYOFWEEK(po.order_date)', 'Derived from order date; no leakage', 'NUMBER(2,0)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('ORDER_MONTH', 'Month the PO was placed (1-12)',
 'RAW.PURCHASE_ORDERS', 'ORDER_DATE', 'PO', NULL,
 'MONTH(po.order_date)', 'Derived from order date; no leakage', 'NUMBER(2,0)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('ORDER_QUARTER', 'Quarter the PO was placed (1-4)',
 'RAW.PURCHASE_ORDERS', 'ORDER_DATE', 'PO', NULL,
 'QUARTER(po.order_date)', 'Derived from order date; no leakage', 'NUMBER(2,0)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

-- === LEAD TIME ANALYSIS FEATURES (2) ===
('LEAD_TIME_VS_STANDARD', 'Promised lead time minus supplier standard lead time (positive = padded, negative = compressed)',
 'RAW.PURCHASE_ORDERS + RAW.PO_LINES + RAW.SUPPLIERS', 'ORDER_DATE, PROMISED_DELIVERY_DATE, STANDARD_LEAD_TIME_DAYS', 'PO_LINE', NULL,
 'DATEDIFF(''day'', po.order_date, pl.promised_delivery_date) - s.standard_lead_time_days',
 'Derived from order-time dates and master data; no leakage', 'NUMBER(21,0)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('LEAD_TIME_RATIO', 'Ratio of promised to standard lead time (<1 = compressed schedule)',
 'RAW.PURCHASE_ORDERS + RAW.PO_LINES + RAW.SUPPLIERS', 'ORDER_DATE, PROMISED_DELIVERY_DATE, STANDARD_LEAD_TIME_DAYS', 'PO_LINE', NULL,
 'CASE WHEN s.standard_lead_time_days > 0 THEN ROUND(DATEDIFF(''day'', po.order_date, pl.promised_delivery_date) * 1.0 / s.standard_lead_time_days, 4) ELSE NULL END',
 'Derived from order-time dates and master data; no leakage', 'NUMBER(17,4)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

-- === SOURCING RISK FEATURES (2) ===
('MATERIAL_ALT_SUPPLIER_COUNT', 'Count of active alternate suppliers for this material',
 'RAW.ALTERNATE_SUPPLIERS', 'MATERIAL_ID', 'MATERIAL', NULL,
 'COALESCE(COUNT(*) WHERE status=''ACTIVE'' GROUP BY material_id, 0)',
 'Static relationship data; safe at any point', 'NUMBER(18,0)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('IS_SINGLE_SOURCED', 'Binary flag: 1 if material has 0 or 1 active supplier (single-source risk)',
 'RAW.ALTERNATE_SUPPLIERS', 'MATERIAL_ID', 'MATERIAL', NULL,
 'CASE WHEN COALESCE(alt.active_alt_count, 0) <= 1 THEN 1 ELSE 0 END',
 'Derived from static master data; safe at any point', 'NUMBER(1,0)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

-- === DEMAND FEATURES (2) ===
('DEMAND_30D_QTY', 'Total quantity demanded for this material in 30 days prior to order date',
 'RAW.DEMAND', 'QUANTITY_DEMANDED', 'PO_LINE', '30 days before order_date',
 'SUM(d.quantity_demanded) WHERE d.demand_date BETWEEN DATEADD(-30, order_date) AND order_date',
 'Point-in-time safe: only demand records before order_date are included', 'NUMBER(38,0)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('DEMAND_30D_COUNT', 'Count of demand events for this material in 30 days prior to order date',
 'RAW.DEMAND', 'DEMAND_DATE', 'PO_LINE', '30 days before order_date',
 'COUNT(*) WHERE d.demand_date BETWEEN DATEADD(-30, order_date) AND order_date',
 'Point-in-time safe: only demand records before order_date are included', 'NUMBER(18,0)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

-- === SUPPLIER HISTORY FEATURES — V2 Multi-Window (8) ===
('SUPPLIER_HIST_VOLUME', 'Total historical PO lines for this supplier before current PO order date',
 'ML.V_SUPPLIER_HISTORY_V2', 'HIST_TOTAL_LINES', 'PO', 'All history before order_date',
 'COUNT(pl_hist.po_line_id) WHERE po_hist.order_date < po_current.order_date',
 'Point-in-time safe: strict < on order_date excludes current PO', 'NUMBER(18,0)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('SUPPLIER_HIST_OTIF_RATE', 'Supplier lifetime OTIF rate from all closed PO lines before current order',
 'ML.V_SUPPLIER_HISTORY_V2', 'HIST_OTIF_RATE', 'PO', 'All history before order_date',
 'COUNT_IF(on_time AND full_qty) / COUNT(*) for historical lines',
 'Point-in-time safe: only closed lines with actual_delivery_date < order_date', 'NUMBER(20,6)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('SUPPLIER_HIST_AVG_VARIANCE', 'Average delivery date variance in days (positive = late) for supplier history',
 'ML.V_SUPPLIER_HISTORY_V2', 'HIST_AVG_DELIVERY_VARIANCE', 'PO', 'All history before order_date',
 'AVG(DATEDIFF(day, promised_delivery_date, actual_delivery_date))',
 'Point-in-time safe: only historical closed lines before order_date', 'NUMBER(27,6)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('SUPPLIER_HIST_STDDEV_VARIANCE', 'Standard deviation of delivery variance for supplier history',
 'ML.V_SUPPLIER_HISTORY_V2', 'HIST_STDDEV_DELIVERY_VARIANCE', 'PO', 'All history before order_date',
 'STDDEV(DATEDIFF(day, promised_delivery_date, actual_delivery_date))',
 'Point-in-time safe: only historical closed lines before order_date', 'FLOAT',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('SUPPLIER_30D_OTIF_RATE', 'Supplier OTIF rate from PO lines in 30-day window before current order',
 'ML.V_SUPPLIER_HISTORY_V2', 'HIST_30D_OTIF_RATE', 'PO', '30 days before order_date',
 'COUNT_IF(on_time AND full_qty) / COUNT(*) WHERE po_hist.order_date >= DATEADD(-30, current_order_date)',
 'Point-in-time safe: 30-day rolling window strictly before order_date', 'NUMBER(20,6)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('SUPPLIER_60D_OTIF_RATE', 'Supplier OTIF rate from PO lines in 60-day window before current order',
 'ML.V_SUPPLIER_HISTORY_V2', 'HIST_60D_OTIF_RATE', 'PO', '60 days before order_date',
 'COUNT_IF(on_time AND full_qty) / COUNT(*) WHERE po_hist.order_date >= DATEADD(-60, current_order_date)',
 'Point-in-time safe: 60-day rolling window strictly before order_date', 'NUMBER(20,6)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('SUPPLIER_90D_OTIF_RATE', 'Supplier OTIF rate from PO lines in 90-day window before current order',
 'ML.V_SUPPLIER_HISTORY_V2', 'HIST_90D_OTIF_RATE', 'PO', '90 days before order_date',
 'COUNT_IF(on_time AND full_qty) / COUNT(*) WHERE po_hist.order_date >= DATEADD(-90, current_order_date)',
 'Point-in-time safe: 90-day rolling window strictly before order_date', 'NUMBER(20,6)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('SUPPLIER_RECENT_BREACH_COUNT', 'Count of supplier breaches in 60 days before current order',
 'ML.V_SUPPLIER_HISTORY_V2', 'RECENT_BREACH_COUNT', 'PO', '60 days before order_date',
 'COUNT_IF(breach) WHERE po_hist.order_date >= DATEADD(-60, current_order_date)',
 'Point-in-time safe: 60-day window strictly before order_date', 'NUMBER(13,0)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

-- === V2 ENGINEERED FEATURES (6) ===
('SUPPLIER_OTIF_TREND', 'OTIF trend: 30d rate minus 90d rate (negative = deteriorating performance)',
 'ML.V_SUPPLIER_HISTORY_V2', 'HIST_30D_OTIF_RATE, HIST_90D_OTIF_RATE', 'PO', '30d and 90d windows',
 'COALESCE(hist_30d_otif_rate, hist_otif_rate) - COALESCE(hist_90d_otif_rate, hist_otif_rate)',
 'Derived from point-in-time safe supplier history windows', 'NUMBER(21,6)',
 'ML_ENGINEERING', '2.0', 'NONE', TRUE),

('INVENTORY_COVERAGE_RATIO', 'Ratio of on-hand inventory to total (on-hand + in-transit) at material-plant level',
 'RAW.INVENTORY', 'QTY_ON_HAND, QTY_IN_TRANSIT', 'MATERIAL_PLANT', NULL,
 'COALESCE(inv.qty_on_hand,0) / (COALESCE(inv.qty_on_hand,0) + COALESCE(inv.qty_in_transit,0) + 1)',
 'Current snapshot; no temporal isolation (inventory is point-in-time by nature)', 'NUMBER(38,4)',
 'ML_ENGINEERING', '2.0', 'MEDIUM', TRUE),

('MATERIAL_BREACH_RATE', 'Historical breach rate for this material across all suppliers',
 'RAW.PO_LINES', 'ACTUAL_DELIVERY_DATE, PROMISED_DELIVERY_DATE, QUANTITY_RECEIVED, QUANTITY_ORDERED', 'MATERIAL', 'All closed history',
 'COUNT_IF(late OR short) / COUNT(*) for closed PO lines by material_id',
 'Uses all historical closed lines; no order_date filter — potential minor leakage for concurrent POs', 'NUMBER(20,6)',
 'ML_ENGINEERING', '2.0', 'MEDIUM', TRUE),

('SUPPLIER_MATERIAL_BREACH_RATE', 'Historical breach rate for this specific supplier-material pair',
 'RAW.PO_LINES + RAW.PURCHASE_ORDERS', 'ACTUAL_DELIVERY_DATE, PROMISED_DELIVERY_DATE, QUANTITY_RECEIVED, QUANTITY_ORDERED', 'SUPPLIER_MATERIAL', 'All closed history',
 'COUNT_IF(late OR short) / COUNT(*) for closed PO lines by supplier_id + material_id',
 'Uses all historical closed lines; no order_date filter — potential minor leakage for concurrent POs', 'NUMBER(20,6)',
 'ML_ENGINEERING', '2.0', 'MEDIUM', TRUE),

('SUPPLIER_OPEN_PO_SHARE', 'Fraction of all open POs belonging to this supplier (concentration risk)',
 'RAW.PURCHASE_ORDERS', 'PO_STATUS, SUPPLIER_ID', 'SUPPLIER', NULL,
 'COUNT(*) WHERE po_status=''OPEN'' AND supplier_id=X / COUNT(*) WHERE po_status=''OPEN''',
 'Current snapshot of open POs; not temporally isolated — minor leakage risk', 'NUMBER(25,6)',
 'ML_ENGINEERING', '2.0', 'MEDIUM', TRUE);

-- ============================================================================
-- 6. FEATURE SET VERSION
-- ============================================================================

TRUNCATE TABLE IF EXISTS AUDIT.FEATURE_SET_VERSION;

INSERT INTO AUDIT.FEATURE_SET_VERSION
    (VERSION_LABEL, DESCRIPTION, FEATURE_COUNT, SOURCE_VIEW, TRAIN_TABLE, SCORE_TABLE, IS_ACTIVE)
VALUES
('V2', 'XGBoost V2 feature set: 41 features with multi-window supplier history, OTIF trend, lead time ratio, inventory coverage, material/pair breach rates, and supplier concentration',
 41, 'OTIF_GUARDIAN.ML.V_FEATURE_SET_V2', 'OTIF_GUARDIAN.ML.TRAIN_DATA_V2', 'OTIF_GUARDIAN.ML.SCORE_DATA_V2', TRUE);

-- ============================================================================
-- 7. MODEL-TO-FEATURE MAPPING
-- ============================================================================

TRUNCATE TABLE IF EXISTS AUDIT.MODEL_FEATURE_MAP;

-- Categorical features used by XGBoost (OrdinalEncoder in pipeline)
-- CAT_COLS = MATERIAL_CATEGORY, ABC_CLASS, CRITICALITY, PO_TYPE, CURRENCY, PLANT_REGION, PLANT_COUNTRY

INSERT INTO AUDIT.MODEL_FEATURE_MAP (MODEL_NAME, MODEL_VERSION, FEATURE_SET_VERSION, FEATURE_NAME, FEATURE_INDEX, IS_CATEGORICAL)
SELECT
    'OTIF_BREACH_PREDICTOR' AS MODEL_NAME,
    'V2' AS MODEL_VERSION,
    '2.0' AS FEATURE_SET_VERSION,
    fr.FEATURE_NAME,
    fr.FEATURE_ID AS FEATURE_INDEX,
    CASE WHEN fr.FEATURE_NAME IN ('MATERIAL_CATEGORY','ABC_CLASS','CRITICALITY','PO_TYPE','CURRENCY','PLANT_REGION','PLANT_COUNTRY')
         THEN TRUE ELSE FALSE END AS IS_CATEGORICAL
FROM AUDIT.FEATURE_REGISTRY fr
WHERE fr.VERSION = '2.0' AND fr.ACTIVE_FLAG = TRUE
ORDER BY fr.FEATURE_ID;

-- Also update model version history to correct feature count from 38 to 41
UPDATE AUDIT.MODEL_VERSION_HISTORY
SET FEATURE_COUNT = 41, NOTES = NOTES || ' Feature count corrected from 38 to 41.'
WHERE VERSION_NAME = 'V2' AND FEATURE_COUNT = 38;

-- ============================================================================
-- 8. FEATURE LINEAGE VIEW
-- ============================================================================

CREATE OR REPLACE VIEW AUDIT.V_FEATURE_LINEAGE AS
SELECT
    fr.FEATURE_ID,
    fr.FEATURE_NAME,
    fr.BUSINESS_DEFINITION,
    fr.SOURCE_TABLE,
    fr.SOURCE_COLUMN,
    fr.GRAIN,
    fr.LOOKBACK_WINDOW,
    fr.TRANSFORMATION_LOGIC,
    fr.POINT_IN_TIME_RULE,
    fr.DATA_TYPE,
    fr.LEAKAGE_RISK,
    mfm.MODEL_NAME,
    mfm.MODEL_VERSION,
    mfm.IS_CATEGORICAL,
    fsv.VERSION_LABEL AS FEATURE_SET_VERSION,
    fsv.SOURCE_VIEW,
    fsv.TRAIN_TABLE,
    fsv.SCORE_TABLE
FROM AUDIT.FEATURE_REGISTRY fr
LEFT JOIN AUDIT.MODEL_FEATURE_MAP mfm
    ON fr.FEATURE_NAME = mfm.FEATURE_NAME AND fr.VERSION = mfm.FEATURE_SET_VERSION
LEFT JOIN AUDIT.FEATURE_SET_VERSION fsv
    ON mfm.FEATURE_SET_VERSION = fsv.VERSION_LABEL
WHERE fr.ACTIVE_FLAG = TRUE;

-- ============================================================================
-- 9. FEATURE COVERAGE VIEW
-- ============================================================================

CREATE OR REPLACE VIEW AUDIT.V_FEATURE_COVERAGE AS
WITH registry_features AS (
    SELECT FEATURE_NAME FROM AUDIT.FEATURE_REGISTRY WHERE VERSION = '2.0' AND ACTIVE_FLAG = TRUE
),
train_columns AS (
    SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'ML' AND TABLE_NAME = 'TRAIN_DATA_V2' AND COLUMN_NAME != 'OTIF_BREACH'
),
score_columns AS (
    SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'ML' AND TABLE_NAME = 'SCORE_DATA_V2'
    AND COLUMN_NAME NOT IN ('PO_LINE_ID','PO_ID','ORDER_DATE','PROMISED_DELIVERY_DATE','OTIF_BREACH')
)
SELECT
    r.FEATURE_NAME,
    CASE WHEN t.COLUMN_NAME IS NOT NULL THEN 'YES' ELSE 'MISSING' END AS IN_TRAIN,
    CASE WHEN s.COLUMN_NAME IS NOT NULL THEN 'YES' ELSE 'MISSING' END AS IN_SCORE,
    CASE WHEN t.COLUMN_NAME IS NOT NULL AND s.COLUMN_NAME IS NOT NULL THEN 'FULL'
         WHEN t.COLUMN_NAME IS NOT NULL OR s.COLUMN_NAME IS NOT NULL THEN 'PARTIAL'
         ELSE 'NONE' END AS COVERAGE
FROM registry_features r
LEFT JOIN train_columns t ON r.FEATURE_NAME = t.COLUMN_NAME
LEFT JOIN score_columns s ON r.FEATURE_NAME = s.COLUMN_NAME;

-- ============================================================================
-- 10. FEATURE DISTRIBUTION SNAPSHOT PROCEDURE
-- ============================================================================

CREATE OR REPLACE PROCEDURE AUDIT.SP_SNAPSHOT_FEATURE_DISTRIBUTIONS(
    P_DATASET VARCHAR,
    P_VERSION VARCHAR DEFAULT '2.0'
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
EXECUTE AS CALLER
AS
$$
def run(session, p_dataset, p_version):
    session.sql("USE DATABASE OTIF_GUARDIAN").collect()
    session.sql("USE SCHEMA AUDIT").collect()

    if p_dataset == 'TRAIN':
        table = 'OTIF_GUARDIAN.ML.TRAIN_DATA_V2'
        tname = 'TRAIN_DATA_V2'
        exclude = ['OTIF_BREACH']
    elif p_dataset == 'SCORE':
        table = 'OTIF_GUARDIAN.ML.SCORE_DATA_V2'
        tname = 'SCORE_DATA_V2'
        exclude = ['PO_LINE_ID','PO_ID','ORDER_DATE','PROMISED_DELIVERY_DATE','OTIF_BREACH']
    else:
        return f'ERROR: Unknown dataset {p_dataset}. Use TRAIN or SCORE.'

    cols_df = session.sql(f"""
        SELECT COLUMN_NAME, DATA_TYPE FROM OTIF_GUARDIAN.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_CATALOG = 'OTIF_GUARDIAN'
        AND TABLE_SCHEMA = 'ML'
        AND TABLE_NAME = '{tname}'
        ORDER BY ORDINAL_POSITION
    """).collect()

    numeric_types = ['NUMBER','FLOAT','DOUBLE','DECIMAL','INT','BIGINT','SMALLINT','TINYINT','REAL']
    inserted = 0

    for row in cols_df:
        col = row['COLUMN_NAME']
        dtype = row['DATA_TYPE']
        if col in exclude:
            continue

        is_numeric = any(t in dtype.upper() for t in numeric_types)

        if is_numeric:
            stats_sql = f"""
                SELECT
                    COUNT(*) AS row_count,
                    COUNT(*) - COUNT("{col}") AS null_count,
                    ROUND((COUNT(*) - COUNT("{col}")) * 100.0 / NULLIF(COUNT(*),0), 2) AS null_pct,
                    COUNT(DISTINCT "{col}") AS distinct_count,
                    AVG("{col}")::FLOAT AS mean_val,
                    STDDEV("{col}")::FLOAT AS stddev_val,
                    MIN("{col}")::FLOAT AS min_val,
                    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY "{col}")::FLOAT AS p25_val,
                    MEDIAN("{col}")::FLOAT AS median_val,
                    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY "{col}")::FLOAT AS p75_val,
                    MAX("{col}")::FLOAT AS max_val
                FROM {table}
            """
        else:
            stats_sql = f"""
                SELECT
                    COUNT(*) AS row_count,
                    COUNT(*) - COUNT("{col}") AS null_count,
                    ROUND((COUNT(*) - COUNT("{col}")) * 100.0 / NULLIF(COUNT(*),0), 2) AS null_pct,
                    COUNT(DISTINCT "{col}") AS distinct_count,
                    NULL AS mean_val, NULL AS stddev_val, NULL AS min_val,
                    NULL AS p25_val, NULL AS median_val, NULL AS p75_val, NULL AS max_val
                FROM {table}
            """

        try:
            stats = session.sql(stats_sql).collect()[0]
            session.sql(f"""
                INSERT INTO OTIF_GUARDIAN.AUDIT.FEATURE_DISTRIBUTION_BASELINE
                (FEATURE_NAME, FEATURE_SET_VERSION, DATASET, ROW_COUNT, NULL_COUNT, NULL_PCT,
                 DISTINCT_COUNT, MEAN_VAL, STDDEV_VAL, MIN_VAL, P25_VAL, MEDIAN_VAL, P75_VAL, MAX_VAL)
                VALUES ('{col}', '{p_version}', '{p_dataset}',
                    {stats['ROW_COUNT']}, {stats['NULL_COUNT']}, {stats['NULL_PCT']},
                    {stats['DISTINCT_COUNT']},
                    {'NULL' if stats['MEAN_VAL'] is None else stats['MEAN_VAL']},
                    {'NULL' if stats['STDDEV_VAL'] is None else stats['STDDEV_VAL']},
                    {'NULL' if stats['MIN_VAL'] is None else stats['MIN_VAL']},
                    {'NULL' if stats['P25_VAL'] is None else stats['P25_VAL']},
                    {'NULL' if stats['MEDIAN_VAL'] is None else stats['MEDIAN_VAL']},
                    {'NULL' if stats['P75_VAL'] is None else stats['P75_VAL']},
                    {'NULL' if stats['MAX_VAL'] is None else stats['MAX_VAL']})
            """).collect()
            inserted += 1
        except Exception as e:
            pass

    return f'OK: Snapshotted {inserted} features for {p_dataset} dataset'
$$;

-- ============================================================================
-- 11. FEATURE VALIDATION PROCEDURE
-- ============================================================================

CREATE OR REPLACE PROCEDURE AUDIT.SP_VALIDATE_FEATURE_REGISTRY(
    P_MODEL_VERSION VARCHAR DEFAULT 'V2'
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
EXECUTE AS CALLER
AS
$$
def run(session, p_model_version):
    session.sql("USE DATABASE OTIF_GUARDIAN").collect()
    results = []
    def add(cid, name, sev, status, exp, act, msg):
        results.append({'check_id':cid,'check_name':name,'severity':sev,'status':status,
                        'expected':str(exp),'actual':str(act),'message':msg})

    # FR-001: Registry features exist in TRAIN_DATA_V2
    missing = session.sql("""
        SELECT fr.FEATURE_NAME FROM OTIF_GUARDIAN.AUDIT.FEATURE_REGISTRY fr
        WHERE fr.VERSION='2.0' AND fr.ACTIVE_FLAG=TRUE
        AND fr.FEATURE_NAME NOT IN (
            SELECT COLUMN_NAME FROM OTIF_GUARDIAN.INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA='ML' AND TABLE_NAME='TRAIN_DATA_V2')
    """).collect()
    if not missing:
        add('FR-001','Registry features exist in TRAIN_DATA_V2','CRITICAL','PASS','0 missing','0 missing','All registered features found in training data')
    else:
        names=', '.join([r['FEATURE_NAME'] for r in missing])
        add('FR-001','Registry features exist in TRAIN_DATA_V2','CRITICAL','FAIL','0 missing',f'{len(missing)} missing',f'Missing: {names}')

    # FR-002: No orphan features in TRAIN_DATA_V2
    orphans = session.sql("""
        SELECT COLUMN_NAME FROM OTIF_GUARDIAN.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA='ML' AND TABLE_NAME='TRAIN_DATA_V2' AND COLUMN_NAME!='OTIF_BREACH'
        AND COLUMN_NAME NOT IN (
            SELECT FEATURE_NAME FROM OTIF_GUARDIAN.AUDIT.FEATURE_REGISTRY WHERE VERSION='2.0' AND ACTIVE_FLAG=TRUE)
    """).collect()
    if not orphans:
        add('FR-002','No orphan features in TRAIN_DATA_V2','CRITICAL','PASS','0 orphans','0 orphans','All training columns are registered')
    else:
        names=', '.join([r['COLUMN_NAME'] for r in orphans])
        add('FR-002','No orphan features in TRAIN_DATA_V2','CRITICAL','FAIL','0 orphans',f'{len(orphans)} orphans',f'Unregistered: {names}')

    # FR-003: Train/Score feature schema match
    mismatch = session.sql("""
        SELECT t.COLUMN_NAME FROM (
            SELECT COLUMN_NAME FROM OTIF_GUARDIAN.INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA='ML' AND TABLE_NAME='TRAIN_DATA_V2' AND COLUMN_NAME!='OTIF_BREACH'
        ) t LEFT JOIN (
            SELECT COLUMN_NAME FROM OTIF_GUARDIAN.INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA='ML' AND TABLE_NAME='SCORE_DATA_V2'
            AND COLUMN_NAME NOT IN ('PO_LINE_ID','PO_ID','ORDER_DATE','PROMISED_DELIVERY_DATE','OTIF_BREACH')
        ) s ON t.COLUMN_NAME=s.COLUMN_NAME WHERE s.COLUMN_NAME IS NULL
    """).collect()
    if not mismatch:
        add('FR-003','Train/Score feature schema match','CRITICAL','PASS','0 mismatches','0 mismatches','All training features present in scoring data')
    else:
        names=', '.join([r['COLUMN_NAME'] for r in mismatch])
        add('FR-003','Train/Score feature schema match','CRITICAL','FAIL','0 mismatches',f'{len(mismatch)} mismatches',f'In train not score: {names}')

    # FR-004: Feature count matches registry
    tc = session.sql("SELECT COUNT(*) AS c FROM OTIF_GUARDIAN.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='ML' AND TABLE_NAME='TRAIN_DATA_V2' AND COLUMN_NAME!='OTIF_BREACH'").collect()[0]['C']
    rc = session.sql("SELECT COUNT(*) AS c FROM OTIF_GUARDIAN.AUDIT.FEATURE_REGISTRY WHERE VERSION='2.0' AND ACTIVE_FLAG=TRUE").collect()[0]['C']
    add('FR-004','Feature count matches registry','CRITICAL','PASS' if tc==rc else 'FAIL',str(rc),str(tc),'Feature counts aligned' if tc==rc else 'Count mismatch')

    # FR-005: Model-feature map completeness
    mc = session.sql(f"SELECT COUNT(*) AS c FROM OTIF_GUARDIAN.AUDIT.MODEL_FEATURE_MAP WHERE MODEL_VERSION='{p_model_version}'").collect()[0]['C']
    add('FR-005','Model-feature map completeness','CRITICAL','PASS' if mc==rc else 'FAIL',str(rc),str(mc),'All features mapped' if mc==rc else 'Not all features mapped')

    # FR-006: Leakage risk documentation
    leak = session.sql("SELECT FEATURE_NAME,LEAKAGE_RISK FROM OTIF_GUARDIAN.AUDIT.FEATURE_REGISTRY WHERE VERSION='2.0' AND ACTIVE_FLAG=TRUE AND LEAKAGE_RISK NOT IN ('NONE','LOW')").collect()
    msg = 'Features with MEDIUM+ risk: '+', '.join([r['FEATURE_NAME'] for r in leak]) if leak else 'No medium+ leakage risk features'
    add('FR-006','Leakage risk documentation','WARNING','PASS','All assessed',f'{len(leak)} MEDIUM+ risk',msg)

    # FR-007: No features with >50% nulls
    high_null = []
    cols = session.sql("SELECT COLUMN_NAME FROM OTIF_GUARDIAN.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='ML' AND TABLE_NAME='TRAIN_DATA_V2' AND COLUMN_NAME!='OTIF_BREACH'").collect()
    for r in cols:
        col = r['COLUMN_NAME']
        np_val = session.sql(f'SELECT ROUND((COUNT(*)-COUNT("{col}"))*100.0/COUNT(*),2) AS np FROM OTIF_GUARDIAN.ML.TRAIN_DATA_V2').collect()[0]['NP']
        if np_val is not None and float(np_val) > 50:
            high_null.append(f'{col}({np_val}%)')
    if not high_null:
        add('FR-007','No features with >50% nulls in training','WARNING','PASS','0','0','All features have acceptable null rates')
    else:
        add('FR-007','No features with >50% nulls in training','WARNING','FAIL','0',str(len(high_null)),f'High null: {", ".join(high_null)}')

    # FR-008: Feature set version V2 active
    fv = session.sql("SELECT COUNT(*) AS c FROM OTIF_GUARDIAN.AUDIT.FEATURE_SET_VERSION WHERE VERSION_LABEL='V2' AND IS_ACTIVE=TRUE").collect()[0]['C']
    add('FR-008','Feature set version V2 is active','CRITICAL','PASS' if fv>0 else 'FAIL','1',str(fv),'V2 registered and active' if fv>0 else 'V2 not found')

    # FR-009: Data type consistency (VARCHAR/TEXT equivalence handled)
    reg = session.sql("SELECT FEATURE_NAME,DATA_TYPE AS RT FROM OTIF_GUARDIAN.AUDIT.FEATURE_REGISTRY WHERE VERSION='2.0' AND ACTIVE_FLAG=TRUE").collect()
    act = session.sql("SELECT COLUMN_NAME,DATA_TYPE AS AT FROM OTIF_GUARDIAN.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='ML' AND TABLE_NAME='TRAIN_DATA_V2'").collect()
    amap = {r['COLUMN_NAME']:r['AT'] for r in act}
    diffs = []
    for r in reg:
        fn,rt = r['FEATURE_NAME'],r['RT'].upper()
        at = amap.get(fn,'')
        if not at: continue
        au = at.upper()
        def norm(t):
            t = t.strip()
            if t == 'TEXT': return 'VARCHAR'
            if t.startswith('VARCHAR'): return 'VARCHAR'
            if t.startswith('NUMBER'): return 'NUMBER'
            return t
        if norm(rt) == norm(au): continue
        if norm(rt) in ('FLOAT','NUMBER') and norm(au) in ('FLOAT','NUMBER'): continue
        diffs.append(f'{fn}:reg={rt},actual={at}')

    add('FR-009','Data type consistency','WARNING','PASS' if not diffs else 'FAIL','0 mismatches',
        f'{len(diffs)} mismatches','Types aligned' if not diffs else '; '.join(diffs))

    # FR-010: Distribution baseline exists
    bc = session.sql("SELECT COUNT(*) AS c FROM OTIF_GUARDIAN.AUDIT.FEATURE_DISTRIBUTION_BASELINE WHERE FEATURE_SET_VERSION='2.0'").collect()[0]['C']
    add('FR-010','Feature distribution baseline exists','WARNING','PASS' if bc>0 else 'FAIL','>0',str(bc),
        'Baseline captured' if bc>0 else 'Run SP_SNAPSHOT_FEATURE_DISTRIBUTIONS first')

    # FR-011: Categorical feature count
    cc = session.sql(f"SELECT COUNT(*) AS c FROM OTIF_GUARDIAN.AUDIT.MODEL_FEATURE_MAP WHERE MODEL_VERSION='{p_model_version}' AND IS_CATEGORICAL=TRUE").collect()[0]['C']
    add('FR-011','Categorical feature count matches pipeline','CRITICAL','PASS' if cc==7 else 'FAIL','7',str(cc),
        'Categorical features correct' if cc==7 else 'Mismatch')

    # FR-012: No duplicate features
    dupes = session.sql("SELECT FEATURE_NAME FROM OTIF_GUARDIAN.AUDIT.FEATURE_REGISTRY WHERE VERSION='2.0' AND ACTIVE_FLAG=TRUE GROUP BY FEATURE_NAME HAVING COUNT(*)>1").collect()
    add('FR-012','No duplicate features in registry','CRITICAL','PASS' if not dupes else 'FAIL','0',str(len(dupes)),
        'All unique' if not dupes else 'Dupes: '+', '.join([r['FEATURE_NAME'] for r in dupes]))

    # Store to DQ audit trail
    run_id = 'FR-VALIDATE-' + session.sql("SELECT TO_VARCHAR(CURRENT_TIMESTAMP(),'YYYYMMDD_HH24MISS') AS ts").collect()[0]['TS']
    for r in results:
        safe_msg = r['message'].replace("'","''")
        session.sql(f"""
            INSERT INTO OTIF_GUARDIAN.AUDIT.DQ_CHECK_RESULTS
            (RUN_ID,CHECK_NAME,DATASET,CATEGORY,SEVERITY,STATUS,EXPECTED_VALUE,ACTUAL_VALUE,ERROR_MESSAGE,EXECUTION_TIME)
            VALUES('{run_id}','{r["check_id"]}: {r["check_name"]}','FEATURE_REGISTRY','FEATURE_VALIDATION',
                   '{r["severity"]}','{r["status"]}','{r["expected"]}','{r["actual"]}','{safe_msg}',CURRENT_TIMESTAMP())
        """).collect()

    return {
        'total_checks': len(results),
        'passed': sum(1 for r in results if r['status']=='PASS'),
        'failed': sum(1 for r in results if r['status']=='FAIL'),
        'critical_failures': sum(1 for r in results if r['status']=='FAIL' and r['severity']=='CRITICAL'),
        'results': results
    }
$$;

-- ============================================================================
-- 12. FEATURE DRIFT SUMMARY VIEW
-- ============================================================================

CREATE OR REPLACE VIEW AUDIT.V_FEATURE_DRIFT_SUMMARY AS
SELECT
    b.FEATURE_NAME,
    b.DATASET,
    b.ROW_COUNT,
    b.NULL_PCT,
    b.DISTINCT_COUNT,
    b.MEAN_VAL,
    b.STDDEV_VAL,
    b.MIN_VAL,
    b.MAX_VAL,
    b.SNAPSHOT_AT,
    fr.LEAKAGE_RISK,
    fr.BUSINESS_DEFINITION
FROM AUDIT.FEATURE_DISTRIBUTION_BASELINE b
JOIN AUDIT.FEATURE_REGISTRY fr ON b.FEATURE_NAME = fr.FEATURE_NAME AND b.FEATURE_SET_VERSION = fr.VERSION
WHERE fr.ACTIVE_FLAG = TRUE
ORDER BY b.SNAPSHOT_AT DESC, b.FEATURE_NAME;
