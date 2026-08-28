-- ============================================================
-- OTIF_Guardian: Agent Deployment SQL
-- Single agent: OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT
-- Generated: 2026-08-28
-- ============================================================
-- 
-- DEPLOYMENT METHOD (recommended):
--
--   # Write spec to workspace
--   cortex agent-studio agent-write \
--     --yaml-content "$(cat agent/otif_guardian_agent.agent.yaml)" \
--     --source-object OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT
--
--   # Deploy to Snowflake (creates the AGENT object)
--   cortex agent-studio agent-deploy \
--     --file-path OTIF_GUARDIAN_AGENT.agent.yaml \
--     --fqn OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT
--
-- ALTERNATIVE: SQL deployment (below)
-- ============================================================

-- Prerequisites
CREATE SCHEMA IF NOT EXISTS OTIF_GUARDIAN.AGENTS
  COMMENT = 'Cortex Agent definitions and search services';

GRANT USAGE ON DATABASE OTIF_GUARDIAN TO ROLE OTIF_GUARDIAN_APP;
GRANT USAGE ON SCHEMA OTIF_GUARDIAN.AGENTS TO ROLE OTIF_GUARDIAN_APP;
GRANT USAGE ON WAREHOUSE OTIF_GUARDIAN_WH TO ROLE OTIF_GUARDIAN_APP;

-- Grant agent access to source data
GRANT SELECT ON ALL TABLES IN SCHEMA OTIF_GUARDIAN.RAW TO ROLE OTIF_GUARDIAN_APP;
GRANT SELECT ON ALL VIEWS IN SCHEMA OTIF_GUARDIAN.ML TO ROLE OTIF_GUARDIAN_APP;
GRANT SELECT ON ALL TABLES IN SCHEMA OTIF_GUARDIAN.ML TO ROLE OTIF_GUARDIAN_APP;
GRANT USAGE ON PROCEDURE OTIF_GUARDIAN.ML.SP_GET_RECOVERY_FOR_PO_LINE(INTEGER) TO ROLE OTIF_GUARDIAN_APP;
GRANT USAGE ON PROCEDURE OTIF_GUARDIAN.ML.SP_RUN_RECOVERY_ENGINE() TO ROLE OTIF_GUARDIAN_APP;
GRANT USAGE ON PROCEDURE OTIF_GUARDIAN.ML.SP_CALCULATE_OTIF_IMPACT() TO ROLE OTIF_GUARDIAN_APP;

-- Grant semantic view access
-- (Execute after semantic view is deployed)
-- GRANT SELECT ON SEMANTIC VIEW OTIF_GUARDIAN.SEMANTIC.OTIF_GUARDIAN_SUPPLY_CHAIN TO ROLE OTIF_GUARDIAN_APP;

-- ============================================================
-- Post-deployment verification
-- ============================================================

-- Verify agent exists
-- SHOW AGENTS IN SCHEMA OTIF_GUARDIAN.AGENTS;
-- DESCRIBE AGENT OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT;

-- Test the agent
-- cortex agents run OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT "What is the overall supplier OTIF rate?"

-- ============================================================
-- Grant user access to the agent
-- ============================================================

-- GRANT USAGE ON AGENT OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT TO ROLE OTIF_GUARDIAN_ANALYST;
-- GRANT USAGE ON AGENT OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT TO ROLE OTIF_GUARDIAN_ENGINEER;

-- ============================================================
-- Connect to Snowflake Intelligence (CoWork) — optional
-- ============================================================

-- After deployment, the agent is accessible via:
-- 1. cortex agents run (CLI)
-- 2. Snowflake Intelligence (CoWork) UI — auto-discoverable if access granted
-- 3. REST API: POST /api/v2/cortex/agent:run

-- ============================================================
-- Rollback
-- ============================================================

-- DROP AGENT IF EXISTS OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT;

-- ============================================================
-- END
-- ============================================================
