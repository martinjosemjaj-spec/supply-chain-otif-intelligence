-- ============================================================
-- 18_cicd_infrastructure.sql
-- CI/CD Infrastructure for OTIF Guardian
-- ============================================================
-- Prerequisites: 00_bootstrap.sql (AUDIT schema must exist)
-- Run as: ACCOUNTADMIN or OTIF_GUARDIAN_ADMIN
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE OTIF_GUARDIAN;
USE WAREHOUSE OTIF_GUARDIAN_WH;

-- ============================================================
-- 1. DEPLOYMENT HISTORY TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS AUDIT.DEPLOYMENT_HISTORY (
    DEPLOY_ID NUMBER AUTOINCREMENT,
    DEPLOYED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    ENVIRONMENT TEXT NOT NULL,
    STAGE_NAME TEXT NOT NULL,
    STATUS TEXT NOT NULL,
    DETAIL TEXT,
    DEPLOYED_BY TEXT DEFAULT CURRENT_USER()
);

-- ============================================================
-- 2. DEPLOYMENT HISTORY VIEW (latest per stage per env)
-- ============================================================

CREATE OR REPLACE VIEW AUDIT.V_DEPLOYMENT_STATUS AS
SELECT
    ENVIRONMENT,
    STAGE_NAME,
    STATUS,
    DETAIL,
    DEPLOYED_AT,
    DEPLOYED_BY,
    ROW_NUMBER() OVER (
        PARTITION BY ENVIRONMENT, STAGE_NAME
        ORDER BY DEPLOYED_AT DESC
    ) AS rn
FROM AUDIT.DEPLOYMENT_HISTORY
QUALIFY rn = 1
ORDER BY ENVIRONMENT, STAGE_NAME;

-- ============================================================
-- 3. GRANTS
-- ============================================================

GRANT SELECT ON TABLE AUDIT.DEPLOYMENT_HISTORY TO ROLE OTIF_GUARDIAN_ENGINEER;
GRANT INSERT ON TABLE AUDIT.DEPLOYMENT_HISTORY TO ROLE OTIF_GUARDIAN_ENGINEER;
GRANT SELECT ON TABLE AUDIT.DEPLOYMENT_HISTORY TO ROLE OTIF_GUARDIAN_ANALYST;
GRANT SELECT ON VIEW AUDIT.V_DEPLOYMENT_STATUS TO ROLE OTIF_GUARDIAN_ENGINEER;
GRANT SELECT ON VIEW AUDIT.V_DEPLOYMENT_STATUS TO ROLE OTIF_GUARDIAN_ANALYST;
