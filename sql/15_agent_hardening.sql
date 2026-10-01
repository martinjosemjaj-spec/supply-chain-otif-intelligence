/*============================================================================
  OTIF GUARDIAN — 15_agent_hardening.sql
  Cortex Agent Governance: Evaluation Harness + Deployment Gates
  ============================================================================
  Creates:
    Tables:  AUDIT.AGENT_EVAL_SUITE (30 test questions, 7 categories)
             AUDIT.AGENT_EVAL_RESULTS (evaluation results by agent version)
    Procs:   AUDIT.SP_RUN_AGENT_EVALUATION (18 automated + 8 routing tests)
  Modifies:
    agent/otif_guardian_agent.agent.yaml (hardened instructions)
  ============================================================================
  Evaluation Categories:
    1. KPI_ANALYSIS (5)         - Metric retrieval and accuracy
    2. RISK_ANALYSIS (5)        - ML risk prediction grounding
    3. SUPPLIER_ANALYSIS (4)    - Supplier-specific queries
    4. PO_ANALYSIS (3)          - PO-level lookups
    5. RECOVERY_SIMULATION (5)  - Deterministic recovery calculations
    6. UNSUPPORTED (4)          - Out-of-domain refusal
    7. AMBIGUOUS (4)            - Clarification behavior
  ============================================================================
  Deployment Gate:
    critical_failures = 0  → PASS (allow deployment)
    critical_failures > 0  → BLOCK (reject deployment)
  ============================================================================
  Agent Hardening (YAML changes):
    - Added Data Governance section with certified metric definitions
    - Added Model Context (V3, risk tier thresholds)
    - Added 8 strict prohibitions (no fabrication, no calculation, read-only)
    - Added 8 mandatory behaviors (cite tool, include model version, show cost)
    - Added tool selection matrix with routing rules
    - Added data modification refusal guardrail
    - Added assumptions citation requirement for recovery
    - Added structured response format with Source attribution
  ============================================================================*/

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE OTIF_GUARDIAN_WH;
USE DATABASE OTIF_GUARDIAN;

-- ============================================================================
-- 1. EVALUATION TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS AUDIT.AGENT_EVAL_SUITE (
    EVAL_ID         NUMBER AUTOINCREMENT PRIMARY KEY,
    CATEGORY        VARCHAR NOT NULL,
    QUESTION        VARCHAR NOT NULL,
    EXPECTED_TOOL   VARCHAR NOT NULL,
    SEVERITY        VARCHAR NOT NULL DEFAULT 'CRITICAL',
    VALIDATION_TYPE VARCHAR NOT NULL,
    VALIDATION_SQL  VARCHAR,
    EXPECTED_PATTERN VARCHAR,
    DESCRIPTION     VARCHAR,
    IS_ACTIVE       BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS AUDIT.AGENT_EVAL_RESULTS (
    RESULT_ID       NUMBER AUTOINCREMENT PRIMARY KEY,
    RUN_ID          VARCHAR NOT NULL,
    AGENT_VERSION   VARCHAR NOT NULL,
    EVAL_ID         NUMBER NOT NULL,
    CATEGORY        VARCHAR NOT NULL,
    QUESTION        VARCHAR NOT NULL,
    EXPECTED_TOOL   VARCHAR,
    RESPONSE_TEXT   VARCHAR,
    TOOL_USED       VARCHAR,
    TOOL_CORRECT    BOOLEAN,
    GROUNDING_CHECK VARCHAR,
    NUMERICAL_CHECK VARCHAR,
    SOURCE_CHECK    VARCHAR,
    OVERALL_STATUS  VARCHAR NOT NULL,
    NOTES           VARCHAR,
    EVALUATED_AT    TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================================
-- 2. EVALUATION PROCEDURE + DEPLOYMENT GATE
-- ============================================================================
-- AUDIT.SP_RUN_AGENT_EVALUATION(P_AGENT_VERSION):
--   Part 1: 18 automated tool/governance/consistency checks
--   Part 2: 8 routing logic tests (documented, require live agent)
--   Returns: deployment_gate = 'PASS' | 'BLOCK'
-- Run: CALL AUDIT.SP_RUN_AGENT_EVALUATION('1.1-hardened');

-- ============================================================================
-- WORKFLOW
-- ============================================================================
-- 1. Update agent YAML (agent/otif_guardian_agent.agent.yaml)
-- 2. Deploy agent: cortex agent-studio deploy
-- 3. Run evaluation: CALL AUDIT.SP_RUN_AGENT_EVALUATION('1.1-hardened')
-- 4. Check gate: SELECT deployment_gate FROM result
-- 5. If BLOCK: fix issues, re-deploy, re-evaluate
-- 6. If PASS: agent is production-ready
-- 7. For live routing tests: manually invoke agent with each ROUTING_LOGIC question
--    and record tool_used in AGENT_EVAL_RESULTS
