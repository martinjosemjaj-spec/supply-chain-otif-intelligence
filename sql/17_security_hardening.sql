-- ============================================================
-- 17_security_hardening.sql
-- Production Security Hardening for OTIF Guardian
-- ============================================================
-- Prerequisites: 00_bootstrap.sql through 16_evidence_framework.sql
-- Run as: ACCOUNTADMIN or OTIF_GUARDIAN_ADMIN
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE OTIF_GUARDIAN;
USE WAREHOUSE OTIF_GUARDIAN_WH;

-- ============================================================
-- 1. MASKING POLICIES (defense-in-depth for sensitive data)
-- ============================================================

-- Financial data: UNIT_PRICE visible only to ADMIN/ENGINEER
CREATE MASKING POLICY IF NOT EXISTS AUDIT.MASK_FINANCIAL_FLOAT
  AS (val FLOAT) RETURNS FLOAT ->
  CASE 
    WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'SYSADMIN', 'OTIF_GUARDIAN_ADMIN', 'OTIF_GUARDIAN_ENGINEER') THEN val
    ELSE -1.00
  END;

-- Customer text: CUSTOMER_NAME/CODE visible only to ADMIN/ENGINEER
CREATE MASKING POLICY IF NOT EXISTS AUDIT.MASK_CUSTOMER_TEXT
  AS (val TEXT) RETURNS TEXT ->
  CASE 
    WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'SYSADMIN', 'OTIF_GUARDIAN_ADMIN', 'OTIF_GUARDIAN_ENGINEER') THEN val
    ELSE '***MASKED***'
  END;

-- Apply masking policies
ALTER TABLE RAW.PO_LINES MODIFY COLUMN UNIT_PRICE
  SET MASKING POLICY AUDIT.MASK_FINANCIAL_FLOAT;

ALTER TABLE RAW.CUSTOMER_ORDERS MODIFY COLUMN CUSTOMER_NAME
  SET MASKING POLICY AUDIT.MASK_CUSTOMER_TEXT;

ALTER TABLE RAW.CUSTOMER_ORDERS MODIFY COLUMN CUSTOMER_CODE
  SET MASKING POLICY AUDIT.MASK_CUSTOMER_TEXT;

-- ============================================================
-- 2. ROW ACCESS POLICY (restrict RAW customer data)
-- ============================================================

CREATE ROW ACCESS POLICY IF NOT EXISTS AUDIT.RAP_RAW_DATA
  AS (row_id NUMBER) RETURNS BOOLEAN ->
  CURRENT_ROLE() IN ('ACCOUNTADMIN', 'SYSADMIN', 'OTIF_GUARDIAN_ADMIN', 'OTIF_GUARDIAN_ENGINEER');

ALTER TABLE RAW.CUSTOMER_ORDERS
  ADD ROW ACCESS POLICY AUDIT.RAP_RAW_DATA ON (PLANT_ID);

-- ============================================================
-- 3. REVOKE EXCESSIVE GRANTS (least-privilege enforcement)
-- ============================================================

-- APP role should NOT have direct RAW table access
-- (accesses data through governed ANALYTICS/ML/SEMANTIC views)
REVOKE SELECT ON ALL TABLES IN SCHEMA RAW FROM ROLE OTIF_GUARDIAN_APP;

-- ============================================================
-- 4. GRANT NEW HARDENING OBJECTS TO APPROPRIATE ROLES
-- ============================================================

-- APP role: governed views for Streamlit/Agent
GRANT USAGE ON SCHEMA ML TO ROLE OTIF_GUARDIAN_APP;
GRANT USAGE ON SCHEMA AUDIT TO ROLE OTIF_GUARDIAN_APP;
GRANT SELECT ON VIEW ML.V_EVIDENCE_PACKAGE TO ROLE OTIF_GUARDIAN_APP;
GRANT SELECT ON VIEW ML.V_EVIDENCE_RECOVERY TO ROLE OTIF_GUARDIAN_APP;
GRANT SELECT ON VIEW ML.V_DECISION_LAYER_COMPLETE TO ROLE OTIF_GUARDIAN_APP;
GRANT SELECT ON VIEW ML.V_RECOVERY_SIMULATION_DETAIL TO ROLE OTIF_GUARDIAN_APP;
GRANT SELECT ON VIEW ML.V_OTIF_PROJECTION TO ROLE OTIF_GUARDIAN_APP;
GRANT SELECT ON TABLE ML.DECISION_ASSUMPTIONS TO ROLE OTIF_GUARDIAN_APP;
GRANT SELECT ON VIEW AUDIT.V_MONITORING_OVERALL TO ROLE OTIF_GUARDIAN_APP;
GRANT SELECT ON VIEW AUDIT.V_MONITORING_DASHBOARD TO ROLE OTIF_GUARDIAN_APP;
GRANT SELECT ON VIEW AUDIT.V_MONITORING_LATEST TO ROLE OTIF_GUARDIAN_APP;
GRANT SELECT ON VIEW AUDIT.V_CERTIFIED_METRICS TO ROLE OTIF_GUARDIAN_APP;
GRANT SELECT ON VIEW AUDIT.V_METRIC_CATALOG TO ROLE OTIF_GUARDIAN_APP;

-- ANALYST role: read-only monitoring and evidence
GRANT SELECT ON VIEW ML.V_EVIDENCE_PACKAGE TO ROLE OTIF_GUARDIAN_ANALYST;
GRANT SELECT ON VIEW ML.V_DECISION_LAYER_COMPLETE TO ROLE OTIF_GUARDIAN_ANALYST;
GRANT SELECT ON VIEW ML.V_OTIF_PROJECTION TO ROLE OTIF_GUARDIAN_ANALYST;
GRANT SELECT ON VIEW AUDIT.V_MONITORING_OVERALL TO ROLE OTIF_GUARDIAN_ANALYST;
GRANT SELECT ON VIEW AUDIT.V_MONITORING_DASHBOARD TO ROLE OTIF_GUARDIAN_ANALYST;
GRANT SELECT ON VIEW AUDIT.V_CERTIFIED_METRICS TO ROLE OTIF_GUARDIAN_ANALYST;

-- ============================================================
-- 5. AUTOMATED SECURITY VALIDATION PROCEDURE
-- ============================================================
-- See SP_VALIDATE_SECURITY_POSTURE created via SQL_EXECUTE
-- (Python procedure - too large for file-based deployment)
-- Run: CALL AUDIT.SP_VALIDATE_SECURITY_POSTURE();
-- Expected: 12/12 PASS, overall_status = 'SECURE'

-- ============================================================
-- PRIVILEGE MATRIX
-- ============================================================
--
-- Role Hierarchy:
--   ACCOUNTADMIN -> SYSADMIN -> OTIF_GUARDIAN_ADMIN
--   OTIF_GUARDIAN_ADMIN -> OTIF_GUARDIAN_ENGINEER
--   OTIF_GUARDIAN_ENGINEER -> OTIF_GUARDIAN_ANALYST
--   OTIF_GUARDIAN_ENGINEER -> OTIF_GUARDIAN_APP
--
-- +---------------------+-----+------+------+------+------+------+------+------+------+
-- | Schema              | ADM | ENG  | ANA  | APP  | Mask | RAP  | Write| Notes|
-- +---------------------+-----+------+------+------+------+------+------+------+
-- | RAW                 | RW  | RW   | --   | --   | YES  | YES  | ADM+ |      |
-- | STAGING             | RW  | RW   | --   | --   | --   | --   | ENG+ |      |
-- | ANALYTICS           | RW  | R    | R    | R    | --   | --   | ENG+ | Views|
-- | SEMANTIC            | RW  | U    | U    | U    | --   | --   | ADM  | SV   |
-- | ML                  | RW  | RW   | R(3) | R(24)| --   | --   | ENG+ | Views|
-- | AGENTS              | RW  | --   | U    | U    | --   | --   | ADM  | Agent|
-- | STREAMLIT           | RW  | U    | --   | U    | --   | --   | ADM  | App  |
-- | AUDIT               | RW  | R    | R(15)| R(5) | --   | --   | ENG+ | Mon  |
-- +---------------------+-----+------+------+------+------+------+------+------+
-- 
-- Legend: RW=Read/Write, R=Read(SELECT), U=USAGE only, --=No access
-- R(N)=SELECT on N specific objects, ADM+=ADMIN and above, ENG+=ENGINEER and above
--
-- Masking Policies:
--   MASK_FINANCIAL_FLOAT -> RAW.PO_LINES.UNIT_PRICE (ADMIN/ENGINEER see values)
--   MASK_CUSTOMER_TEXT   -> RAW.CUSTOMER_ORDERS.CUSTOMER_NAME (ADMIN/ENGINEER see values)
--   MASK_CUSTOMER_TEXT   -> RAW.CUSTOMER_ORDERS.CUSTOMER_CODE (ADMIN/ENGINEER see values)
--
-- Row Access Policy:
--   RAP_RAW_DATA -> RAW.CUSTOMER_ORDERS (ADMIN/ENGINEER can read rows)
--
-- Security Findings Remediated:
--   1. OTIF_GUARDIAN_APP had SELECT on all 12 RAW tables -> REVOKED
--   2. No masking policies existed -> 2 created, applied to 3 columns
--   3. No row access policies existed -> 1 created, applied to CUSTOMER_ORDERS
--
-- Validation:
--   CALL AUDIT.SP_VALIDATE_SECURITY_POSTURE();
--   -> 12/12 PASS, overall_status = 'SECURE'
