/*============================================================================
  OTIF GUARDIAN — 13_decision_layer_hardening.sql
  Deterministic Decision Layer: Governed Calculations + Regression Tests
  ============================================================================
  Creates:
    Tables:  ML.DECISION_ASSUMPTIONS (34 configurable parameters)
    Views:   ML.V_DECISION_LAYER_COMPLETE  (11 calculations per at-risk line)
             ML.V_RECOVERY_SIMULATION_DETAIL (per-action before/after breakdown)
             ML.V_OTIF_PROJECTION (baseline vs projected OTIF)
    Procs:   AUDIT.SP_RUN_DECISION_REGRESSION_TESTS (20 test cases)
  ============================================================================
  Architecture:
    XGBoost Model (risk prediction ONLY)
           │
    V_SCORED_RESULTS (breach probability, risk tier)
           │
    V_AT_RISK_LINES (CRITICAL + HIGH + MEDIUM lines)
           │
    ┌──────┴──────────────────────────────────────┐
    │  DECISION_ASSUMPTIONS (governed params)      │
    └──────┬──────────────────────────────────────┘
           │
    V_DECISION_LAYER_COMPLETE ──── 11 deterministic metrics
           │
    V_RECOVERY_SIMULATION_DETAIL ─ per-action: baseline/projected/cost/benefit/ROI
           │
    V_OTIF_PROJECTION ──────────── portfolio-level OTIF before/after
           │
    Semantic Layer + Cortex Agent (read-only consumers)
  ============================================================================
  Deterministic Calculations (NO LLM generation):
    1. OTIF_PROBABILITY       = 1 - breach_probability
    2. STOCKOUT_RISK_SCORE    = f(inventory_position, qty_ordered, reorder_point)
    3. REVENUE_EXPOSURE       = line_value * breach_probability + downstream_prob_weighted
    4. CUSTOMER_IMPACT        = exposed_customer_orders count + revenue
    5. INVENTORY_IMPACT       = on_hand / qty_ordered (coverage equiv)
    6. BASELINE_EXPOSURE      = total_exposure before any action
    7. PROJECTED_EXPOSURE     = total_exposure * (1 - success_probability)
    8. RECOVERY_COST          = action-specific cost from governed formulas
    9. BENEFIT                = baseline_exposure - projected_exposure
   10. NET_VALUE              = revenue_protected - recovery_cost
   11. ROI                    = net_value / recovery_cost
  ============================================================================*/

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE OTIF_GUARDIAN_WH;
USE DATABASE OTIF_GUARDIAN;

-- ============================================================================
-- 1. GOVERNED ASSUMPTIONS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS ML.DECISION_ASSUMPTIONS (
    ASSUMPTION_ID    NUMBER AUTOINCREMENT PRIMARY KEY,
    CATEGORY         VARCHAR NOT NULL,
    PARAM_NAME       VARCHAR NOT NULL UNIQUE,
    PARAM_VALUE      FLOAT NOT NULL,
    UNIT             VARCHAR,
    DESCRIPTION      VARCHAR NOT NULL,
    LAST_REVIEWED    DATE DEFAULT CURRENT_DATE(),
    REVIEWED_BY      VARCHAR DEFAULT CURRENT_USER(),
    IS_ACTIVE        BOOLEAN DEFAULT TRUE
);

-- Seed assumptions (idempotent via MERGE)
MERGE INTO ML.DECISION_ASSUMPTIONS t
USING (
    SELECT * FROM (VALUES
        ('EXPEDITE','COST_PER_KG_OCEAN',3.00,'$/kg','Expedite surcharge ocean-to-air'),
        ('EXPEDITE','COST_PER_KG_RAIL',1.50,'$/kg','Expedite surcharge rail-to-truck'),
        ('EXPEDITE','COST_PER_KG_TRUCK',0.75,'$/kg','Expedite surcharge truck acceleration'),
        ('EXPEDITE','COST_PER_KG_DEFAULT',1.00,'$/kg','Default expedite cost'),
        ('EXPEDITE','SUCCESS_PROB_7PLUS_DAYS',0.90,'probability','7+ days remaining'),
        ('EXPEDITE','SUCCESS_PROB_4TO6_DAYS',0.75,'probability','4-6 days remaining'),
        ('EXPEDITE','SUCCESS_PROB_2TO3_DAYS',0.50,'probability','2-3 days remaining'),
        ('EXPEDITE','SUCCESS_PROB_UNDER2_DAYS',0.10,'probability','<2 days remaining'),
        ('EXPEDITE','DAYS_SAVED_OCEAN',5,'days','Days saved ocean expedite'),
        ('EXPEDITE','DAYS_SAVED_RAIL',3,'days','Days saved rail expedite'),
        ('EXPEDITE','DAYS_SAVED_TRUCK_PCT',0.40,'fraction','Fraction saved truck'),
        ('EXPEDITE','DAYS_SAVED_DEFAULT',2,'days','Default days saved'),
        ('TRANSFER','COST_PER_KG_SAME_COUNTRY',0.80,'$/kg','Same-country transfer rate'),
        ('TRANSFER','COST_PER_KG_SAME_REGION',1.50,'$/kg','Same-region transfer rate'),
        ('TRANSFER','COST_PER_KG_CROSS_REGION',3.00,'$/kg','Cross-region transfer rate'),
        ('TRANSFER','HANDLING_COST_PER_UNIT',2.00,'$/unit','Per-unit handling'),
        ('TRANSFER','TRANSIT_DAYS_SAME_COUNTRY',3,'days','Same-country transit'),
        ('TRANSFER','TRANSIT_DAYS_SAME_REGION',7,'days','Same-region transit'),
        ('TRANSFER','TRANSIT_DAYS_CROSS_REGION',12,'days','Cross-region transit'),
        ('TRANSFER','SUCCESS_PROB_FULL_COVER',0.95,'probability','Full qty + time'),
        ('TRANSFER','SUCCESS_PROB_PARTIAL',0.70,'probability','Partial coverage'),
        ('TRANSFER','SUCCESS_PROB_LOW',0.20,'probability','Constrained transfer'),
        ('ALT_SUPPLIER','SUCCESS_OTD_95_IN_TIME',0.90,'probability','OTD>=95% in time'),
        ('ALT_SUPPLIER','SUCCESS_OTD_85_IN_TIME',0.75,'probability','OTD>=85% in time'),
        ('ALT_SUPPLIER','SUCCESS_OTD_75',0.55,'probability','OTD>=75%'),
        ('ALT_SUPPLIER','SUCCESS_DEFAULT',0.35,'probability','Default alt success'),
        ('ALT_SUPPLIER','RUSH_FREIGHT_PER_KG',2.50,'$/kg','Rush freight surcharge'),
        ('ALT_SUPPLIER','RUSH_FREIGHT_DAYS_THRESHOLD',3,'days','Rush trigger margin'),
        ('REVENUE','DOWNSTREAM_WINDOW_DAYS',14,'days','Customer order exposure window'),
        ('STOCKOUT','SAFETY_STOCK_MULTIPLE',1.0,'multiple','Safety stock multiplier'),
        ('RISK_TIER','CRITICAL_THRESHOLD',0.80,'probability','CRITICAL risk cutoff'),
        ('RISK_TIER','HIGH_THRESHOLD',0.60,'probability','HIGH risk cutoff'),
        ('RISK_TIER','MEDIUM_THRESHOLD',0.40,'probability','MEDIUM risk cutoff'),
        ('RISK_TIER','LOW_THRESHOLD',0.20,'probability','LOW risk cutoff')
    ) AS v(CAT, PN, PV, U, D)
) s ON t.PARAM_NAME = s.PN
WHEN NOT MATCHED THEN INSERT (CATEGORY, PARAM_NAME, PARAM_VALUE, UNIT, DESCRIPTION)
    VALUES (s.CAT, s.PN, s.PV, s.U, s.D);

-- ============================================================================
-- 2-4. GOVERNED VIEWS
-- ============================================================================
-- V_DECISION_LAYER_COMPLETE: 11 deterministic metrics per at-risk PO line
-- V_RECOVERY_SIMULATION_DETAIL: per-action before/after/cost/benefit/ROI/assumptions
-- V_OTIF_PROJECTION: baseline vs projected OTIF rate with recovery

-- These views are deployed via SQL_EXECUTE in the hardening session.
-- Source SQL is in the Snowflake ML schema.

-- ============================================================================
-- 5. REGRESSION TEST PROCEDURE
-- ============================================================================
-- AUDIT.SP_RUN_DECISION_REGRESSION_TESTS: 20 deterministic test cases
-- Run: CALL AUDIT.SP_RUN_DECISION_REGRESSION_TESTS();

-- ============================================================================
-- USAGE
-- ============================================================================
-- Streamlit:  SELECT * FROM ML.V_DECISION_LAYER_COMPLETE
-- Agent:      Reads V_RECOVERY_SIMULATION_DETAIL (no calculation by LLM)
-- Analyst:    SELECT * FROM ML.V_OTIF_PROJECTION
-- Config:     UPDATE ML.DECISION_ASSUMPTIONS SET PARAM_VALUE = X WHERE PARAM_NAME = 'Y'
-- Validate:   CALL AUDIT.SP_RUN_DECISION_REGRESSION_TESTS()
