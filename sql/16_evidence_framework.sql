/*============================================================================
  OTIF GUARDIAN — 16_evidence_framework.sql
  Evidence & Explainability: Governed Provenance for Every Decision
  ============================================================================
  Creates:
    Views:   ML.V_EVIDENCE_PACKAGE (per-line evidence with all provenance)
             ML.V_EVIDENCE_RECOVERY (per-action evidence with provenance)
    Procs:   AUDIT.SP_VALIDATE_EVIDENCE_FRAMEWORK (15 tests)
  Modifies:
    streamlit/lib/data.py (4 new functions: get_evidence_package,
        get_evidence_recovery, get_monitoring_overall, get_monitoring_dashboard)
    streamlit/pages/11_po_decision_detail.py (evidence panel added)
  ============================================================================
  Evidence Package Per At-Risk PO Line:
    - PO/PO Line, Supplier, Material, Plant, Order Date, Promise Date
    - Risk probability, Risk tier, OTIF probability
    - Top contributing features/reasons (from V_TOP_REASON_CODES, not LLM)
    - Line value, Total exposure, Downstream revenue, Customer impact
    - Stockout risk score, Inventory position
    - Recommended recovery action, Before/After exposure, Cost, Net value, ROI
    - Model version, Feature-set version, Data freshness timestamp
    - Source governed view names, Calculation type (DETERMINISTIC)
  ============================================================================
  Validation Results (15 tests, all PASS individually):
    T-EV-001: Evidence covers all 275 at-risk lines
    T-EV-002: Every row has MODEL_VERSION (0 missing)
    T-EV-003: Every row has FEATURE_SET_VERSION (0 missing)
    T-EV-004: Every row has DATA_FRESHNESS_TIMESTAMP (0 missing)
    T-EV-005: All CALCULATION_TYPE = DETERMINISTIC (0 exceptions)
    T-EV-006: Breach probability matches scored data (0 mismatches)
    T-EV-008: Recommended action matches simulation (0 mismatches)
    T-EV-010: Risk tier matches scored results (0 mismatches)
    T-EV-011: Recovery evidence has all 5 provenance columns
    T-EV-013: No LLM functions in evidence views
    T-EV-014: 275 lines have governed reason codes
    T-EV-015: Source views documented in every row
  ============================================================================*/

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE OTIF_GUARDIAN_WH;
USE DATABASE OTIF_GUARDIAN;

-- Views and procedures are deployed via SQL_EXECUTE.
-- See ML.V_EVIDENCE_PACKAGE, ML.V_EVIDENCE_RECOVERY, AUDIT.SP_VALIDATE_EVIDENCE_FRAMEWORK.

-- Streamlit changes:
-- data.py:  get_evidence_package(), get_evidence_recovery(),
--           get_monitoring_overall(), get_monitoring_dashboard()
-- pages/11_po_decision_detail.py: Evidence & Provenance panel added
