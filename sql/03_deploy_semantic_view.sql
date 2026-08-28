-- ============================================================
-- OTIF_Guardian: Semantic View Deployment
-- Deploys the semantic view YAML to Snowflake
-- Generated: 2026-08-28
-- ============================================================
-- 
-- DEPLOYMENT OPTIONS:
-- 
-- Option A: Deploy via cortex agent-studio CLI (recommended)
--   cortex agent-studio sv-write \
--     --yaml-content "$(cat semantic/otif_guardian_supply_chain.sv.yaml)" \
--     --source-object OTIF_GUARDIAN.SEMANTIC.OTIF_GUARDIAN_SUPPLY_CHAIN
--
--   cortex agent-studio sv-deploy \
--     --file-path OTIF_GUARDIAN_SUPPLY_CHAIN.sv.yaml \
--     --fqn OTIF_GUARDIAN.SEMANTIC.OTIF_GUARDIAN_SUPPLY_CHAIN
--
-- Option B: Deploy via SQL (below)
-- ============================================================

-- Ensure schema exists
CREATE SCHEMA IF NOT EXISTS OTIF_GUARDIAN.SEMANTIC
  COMMENT = 'Semantic models and Cortex Analyst objects';

-- Grant analyst usage
GRANT USAGE ON DATABASE OTIF_GUARDIAN TO ROLE OTIF_GUARDIAN_ANALYST;
GRANT USAGE ON SCHEMA OTIF_GUARDIAN.SEMANTIC TO ROLE OTIF_GUARDIAN_ANALYST;

-- ============================================================
-- Deploy semantic view from stage
-- ============================================================

-- Step 1: Create a stage for the YAML file
CREATE STAGE IF NOT EXISTS OTIF_GUARDIAN.SEMANTIC.SV_STAGE
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Semantic view YAML definitions';

-- Step 2: Upload the YAML file to stage
-- Run from CLI:
--   snow stage copy semantic/otif_guardian_supply_chain.sv.yaml \
--     @OTIF_GUARDIAN.SEMANTIC.SV_STAGE/
--
-- Or via PUT:
-- PUT file://semantic/otif_guardian_supply_chain.sv.yaml
--   @OTIF_GUARDIAN.SEMANTIC.SV_STAGE/
--   AUTO_COMPRESS = FALSE
--   OVERWRITE = TRUE;

-- Step 3: Create the semantic view referencing the staged YAML
-- Using SYSTEM$WRITE_SEMANTIC_MODEL_YAML to validate before deploy:
--
-- SELECT SYSTEM$WRITE_SEMANTIC_MODEL_YAML(
--   @OTIF_GUARDIAN.SEMANTIC.SV_STAGE/otif_guardian_supply_chain.sv.yaml,
--   TRUE  -- validate_only = TRUE (dry run)
-- );

-- Step 4: Final deployment via cortex agent-studio (production method):
--
-- cortex agent-studio sv-deploy \
--   --file-path OTIF_GUARDIAN_SUPPLY_CHAIN.sv.yaml \
--   --fqn OTIF_GUARDIAN.SEMANTIC.OTIF_GUARDIAN_SUPPLY_CHAIN

-- ============================================================
-- Post-deployment grants
-- ============================================================

-- Grant SELECT on the semantic view to consuming roles
-- (Execute after deployment creates the view object)
--
-- GRANT SELECT ON SEMANTIC VIEW OTIF_GUARDIAN.SEMANTIC.OTIF_GUARDIAN_SUPPLY_CHAIN
--   TO ROLE OTIF_GUARDIAN_ANALYST;
--
-- GRANT SELECT ON SEMANTIC VIEW OTIF_GUARDIAN.SEMANTIC.OTIF_GUARDIAN_SUPPLY_CHAIN
--   TO ROLE OTIF_GUARDIAN_APP;

-- ============================================================
-- Validation queries (run post-deployment)
-- ============================================================

-- Verify the semantic view exists
-- SHOW SEMANTIC VIEWS IN SCHEMA OTIF_GUARDIAN.SEMANTIC;

-- Describe the deployed view
-- DESCRIBE SEMANTIC VIEW OTIF_GUARDIAN.SEMANTIC.OTIF_GUARDIAN_SUPPLY_CHAIN;

-- Test with Cortex Analyst
-- SELECT SNOWFLAKE.CORTEX.ANALYST(
--   'What is the overall supplier OTIF rate?',
--   PARSE_JSON('{"semantic_view": "OTIF_GUARDIAN.SEMANTIC.OTIF_GUARDIAN_SUPPLY_CHAIN"}')
-- );

-- ============================================================
-- Rollback (if needed)
-- ============================================================

-- DROP SEMANTIC VIEW IF EXISTS OTIF_GUARDIAN.SEMANTIC.OTIF_GUARDIAN_SUPPLY_CHAIN;

-- ============================================================
-- END
-- ============================================================
