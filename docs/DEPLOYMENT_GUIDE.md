# Deployment Guide

## Prerequisites

| Requirement | Minimum |
|-------------|---------|
| Snowflake Edition | Enterprise |
| Role | ACCOUNTADMIN (initial deploy); SYSADMIN (subsequent) |
| Warehouse | XS or larger |
| Region | Any AWS/Azure/GCP region with Cortex AI |
| Cortex Analyst | Enabled (account parameter) |
| Cortex Agents | Available |
| ML Classification | Available |

## Deployment Order

Execute scripts in strict sequence. Each stage has a validation gate.

| Stage | Script | Duration | Gate |
|-------|--------|----------|------|
| 1 | `sql/00_bootstrap.sql` | ~5s | 8 schemas exist |
| 2 | `sql/01_generate_data.sql` | ~30s | 12 tables populated |
| 3 | `sql/02_ontology_views.sql` | ~5s | 11 views queryable |
| 4 | `sql/03_deploy_semantic_view.sql` | ~10s | Semantic view object exists |
| 5 | `sql/04_ml_pipeline.sql` | ~60s | Model registered, accuracy > 0.55 |
| 6 | `sql/05_recovery_engine.sql` | ~5s | Recommendations generated |
| 7 | `python/recovery_procedures.sql` | ~5s | 3 procedures created |
| 8 | `sql/06_deploy_agent.sql` | ~10s | Agent responds to test query |

**Total estimated deployment time: 2-3 minutes.**

## Stage 1: Bootstrap

```sql
-- Execute as ACCOUNTADMIN
USE ROLE ACCOUNTADMIN;
-- Run the entire bootstrap script
-- Creates: database, 8 schemas, 4 roles, warehouse, resource monitor,
-- stages, file formats, sequences, and complete grant hierarchy
```

**Validation:**
```sql
SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA
WHERE CATALOG_NAME = 'OTIF_GUARDIAN'; -- Expected: >= 8
```

## Stage 2: Data Generation

```sql
USE ROLE ACCOUNTADMIN;
USE DATABASE OTIF_GUARDIAN;
USE SCHEMA RAW;
USE WAREHOUSE OTIF_GUARDIAN_WH;
-- Execute sql/01_generate_data.sql
```

**Validation:**
```sql
SELECT COUNT(*) FROM OTIF_GUARDIAN.RAW.PO_LINES; -- Expected: 30800
```

## Stage 3: Ontology Views

```sql
USE SCHEMA ANALYTICS;
-- Execute sql/02_ontology_views.sql
```

**Validation:**
```sql
SELECT COUNT(*) FROM OTIF_GUARDIAN.ANALYTICS.V_PO_DELIVERY_PERFORMANCE; -- > 0
```

## Stage 4: Semantic View

```bash
# Upload YAML to workspace
cortex agent-studio sv-write \
  --yaml-content "$(cat semantic/otif_guardian_supply_chain.sv.yaml)" \
  --source-object OTIF_GUARDIAN.SEMANTIC.OTIF_GUARDIAN_SUPPLY_CHAIN

# Deploy to Snowflake
cortex agent-studio sv-deploy \
  --file-path OTIF_GUARDIAN_SUPPLY_CHAIN.sv.yaml \
  --fqn OTIF_GUARDIAN.SEMANTIC.OTIF_GUARDIAN_SUPPLY_CHAIN
```

**Validation:**
```sql
SHOW SEMANTIC VIEWS IN SCHEMA OTIF_GUARDIAN.SEMANTIC; -- 1 row
```

## Stage 5: ML Pipeline

```sql
USE SCHEMA ML;
-- Execute sql/04_ml_pipeline.sql
-- This takes longest (~60s) due to model training
```

**Validation:**
```sql
SELECT * FROM OTIF_GUARDIAN.ML.V_MODEL_METRICS; -- accuracy > 0.55
```

## Stage 6: Recovery Engine

```sql
-- Execute sql/05_recovery_engine.sql
```

**Validation:**
```sql
SELECT COUNT(*) FROM OTIF_GUARDIAN.ML.V_RECOVERY_RECOMMENDATIONS; -- > 0
```

## Stage 7: Python Procedures

```sql
-- Execute python/recovery_procedures.sql
```

**Validation:**
```sql
SHOW PROCEDURES IN SCHEMA OTIF_GUARDIAN.ML; -- 3 procedures
```

## Stage 8: Agent

```bash
# Write agent spec
cortex agent-studio agent-write \
  --yaml-content "$(cat agent/otif_guardian_agent.agent.yaml)" \
  --source-object OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT

# Deploy
cortex agent-studio agent-deploy \
  --file-path OTIF_GUARDIAN_AGENT.agent.yaml \
  --fqn OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT

# Grant access
GRANT USAGE ON AGENT OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT TO ROLE OTIF_GUARDIAN_ANALYST;
```

**Validation:**
```bash
cortex agents run OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT "What is the OTIF rate?"
```

## Post-Deployment Tests

```sql
-- Run complete test suite
@tests/test_sql.sql
@tests/test_ml.sql
@tests/test_semantic_agent_governance.sql
```

All tests should return PASS. See `tests/COVERAGE_REPORT.md` for pass criteria.

## Streamlit Deployment (Optional)

```bash
snow streamlit deploy \
  --database OTIF_GUARDIAN \
  --schema STREAMLIT \
  --query-warehouse OTIF_GUARDIAN_WH
```

## Rollback

Each stage can be rolled back independently in reverse order. See the ROLLBACK section at the end of each SQL script, or use the `$deploy-project` skill with rollback instructions.

**Full teardown (destroys all data):**
```sql
DROP DATABASE IF EXISTS OTIF_GUARDIAN;
```

## Environment Promotion

| From | To | Method |
|------|----|--------|
| Dev → Staging | Re-run stages 1-8 against staging database | Change database name |
| Staging → Production | Re-run stages 1,3-8 (skip data gen) | Set `skip_data_generation=true` |

For production, replace `sql/01_generate_data.sql` with actual data ingestion pipelines.
