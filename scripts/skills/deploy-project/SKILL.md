---
name: deploy-project
description: "Deploy the OTIF Guardian project end-to-end to a Snowflake environment. Executes bootstrap, data generation, ontology, semantic view, ML pipeline, recovery engine, and agent in the correct dependency order with validation gates between stages. Use when: deploying to a new environment, promoting to production, full rebuild, environment setup, CI/CD pipeline. Triggers: deploy project, deploy all, full deployment, promote to production, set up environment, rebuild everything, fresh deploy, deploy OTIF Guardian."
---

# Deploy Project

## Purpose

Execute a full end-to-end deployment of the OTIF Guardian project to a Snowflake environment. Deploys all layers in dependency order with validation gates between each stage. Supports both fresh deployments and incremental updates.

This is the master orchestration skill — it calls the sub-components in sequence and halts on failure.

## Inputs

| Input | Required | Description |
|-------|----------|-------------|
| Target environment | Yes | Environment label: `dev`, `staging`, `production` |
| Database | Yes | Target database name (default: `OTIF_GUARDIAN`) |
| Warehouse | Yes | Compute warehouse (default: `OTIF_GUARDIAN_WH`) |
| Deploy mode | Yes | `full` (everything) or `incremental` (only changed layers) |
| Skip data generation | No | If `true`, assumes data already exists (default: `false` for dev, `true` for production) |
| Dry run | No | If `true`, validates SQL without executing (default: `false`) |

## Outputs

| Output | Description |
|--------|-------------|
| Deployment report | Stage-by-stage status with timings |
| Validation summary | All gate checks PASS/FAIL |
| Object inventory | List of all created objects |
| Rollback script | Generated SQL to undo the deployment |

## Execution Steps

### Stage 0: Pre-flight Checks

```sql
-- Verify connection and role
SELECT CURRENT_ACCOUNT(), CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE();

-- Verify warehouse exists and can be used
SHOW WAREHOUSES LIKE 'OTIF_GUARDIAN_WH';
```

**Gate:** Must have ACCOUNTADMIN or SYSADMIN role. Warehouse must exist.

### Stage 1: Bootstrap (sql/00_bootstrap.sql)

Creates: database, schemas, roles, warehouse, resource monitor, stages, file formats, sequences, grant hierarchy.

```
Execute: sql/00_bootstrap.sql
Validate: SHOW SCHEMAS IN DATABASE OTIF_GUARDIAN (expect 8+ schemas)
```

**Gate:** All 8 schemas exist. Warehouse created. Roles created.

### Stage 2: Data Generation (sql/01_generate_data.sql)

Creates: 12 tables with deterministic supply chain data.

```
Execute: sql/01_generate_data.sql (skip if skip_data_generation = true)
Validate: Row counts match expected (SUPPLIERS=60, PLANTS=8, MATERIALS=250, etc.)
```

**Gate:** All 12 tables have rows > 0. Key tables match target counts ± 5%.

### Stage 3: Ontology Views (sql/02_ontology_views.sql)

Creates: 11 analytical views in ANALYTICS schema.

```
Execute: sql/02_ontology_views.sql
Validate: All 11 views queryable with rows > 0
```

**Gate:** `SELECT COUNT(*) FROM V_PO_DELIVERY_PERFORMANCE` > 0.

### Stage 4: Semantic View (sql/03_deploy_semantic_view.sql)

Deploys: Cortex Analyst semantic view YAML.

```
Execute:
  1. Create stage OTIF_GUARDIAN.SEMANTIC.SV_STAGE
  2. Upload semantic/otif_guardian_supply_chain.sv.yaml to stage
  3. Deploy via cortex agent-studio sv-deploy
Validate: SHOW SEMANTIC VIEWS IN SCHEMA OTIF_GUARDIAN.SEMANTIC (expect 1)
```

**Gate:** Semantic view object exists and is queryable.

### Stage 5: ML Pipeline (sql/04_ml_pipeline.sql)

Creates: Feature views, train/test data, trained model, evaluation metrics, model registry.

```
Execute: sql/04_ml_pipeline.sql
Validate:
  - TRAIN_DATA rows > 5000
  - Model object exists
  - V_MODEL_METRICS returns results
  - Registry version exists
```

**Gate:** Model metrics accuracy > 0.55. Model registered in registry.

### Stage 6: Recovery Engine (sql/05_recovery_engine.sql)

Creates: Recovery evaluation views, recommendation ranking.

```
Execute: sql/05_recovery_engine.sql
Validate: V_RECOVERY_RECOMMENDATIONS returns rows (feasible actions exist)
```

**Gate:** At least 1 feasible recovery action generated.

### Stage 7: Python Procedures (python/recovery_procedures.sql)

Creates: 3 stored procedures for recovery orchestration.

```
Execute: python/recovery_procedures.sql
Validate: SHOW PROCEDURES IN SCHEMA OTIF_GUARDIAN.ML (expect 3 new procedures)
```

**Gate:** All 3 procedures created successfully.

### Stage 8: Agent (sql/06_deploy_agent.sql + agent deployment)

Creates: Cortex Agent object.

```
Execute:
  1. sql/06_deploy_agent.sql (grants and prerequisites)
  2. cortex agent-studio agent-write + agent-deploy
Validate: SHOW AGENTS IN SCHEMA OTIF_GUARDIAN.AGENTS (expect 1)
```

**Gate:** Agent object exists. Test query returns response.

### Stage 9: Post-Deployment Report

Generate and present:
```
OTIF Guardian Deployment Report
════════════════════════════════
Environment: [dev/staging/production]
Database: OTIF_GUARDIAN
Timestamp: [ISO 8601]
Duration: [total seconds]

Stage Results:
  ┌─────────────────────────┬────────┬──────────┐
  │ Stage                   │ Status │ Duration │
  ├─────────────────────────┼────────┼──────────┤
  │ 1. Bootstrap            │ PASS   │ 2.1s     │
  │ 2. Data Generation      │ PASS   │ 15.3s    │
  │ 3. Ontology Views       │ PASS   │ 1.8s     │
  │ 4. Semantic View        │ PASS   │ 3.2s     │
  │ 5. ML Pipeline          │ PASS   │ 45.7s    │
  │ 6. Recovery Engine      │ PASS   │ 2.4s     │
  │ 7. Python Procedures    │ PASS   │ 1.1s     │
  │ 8. Agent                │ PASS   │ 4.8s     │
  └─────────────────────────┴────────┴──────────┘

Objects Created: [count]
Model Metrics: Accuracy=[X], F1=[X]
Recovery Actions Available: [N]
Agent Status: ACTIVE
```

## Validation

| Stage | Gate Check | Failure Action |
|-------|-----------|----------------|
| 0 | Role = ACCOUNTADMIN or SYSADMIN | ABORT |
| 1 | 8 schemas exist | ABORT |
| 2 | 12 tables with rows > 0 | ABORT |
| 3 | 11 views queryable | ABORT |
| 4 | Semantic view object exists | WARN (continue without agent) |
| 5 | Model accuracy > 0.55 | WARN (deploy but flag for review) |
| 6 | >= 1 feasible recovery action | WARN |
| 7 | 3 procedures created | ABORT |
| 8 | Agent exists | WARN |

On any ABORT: execute rollback for that stage and all prior completed stages.
On any WARN: log warning, continue, include in final report.

## Rollback

Execute in reverse order. Each stage is independently rollback-able.

```sql
-- Stage 8: Agent
DROP AGENT IF EXISTS OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT;

-- Stage 7: Procedures
DROP PROCEDURE IF EXISTS OTIF_GUARDIAN.ML.SP_RUN_RECOVERY_ENGINE();
DROP PROCEDURE IF EXISTS OTIF_GUARDIAN.ML.SP_GET_RECOVERY_FOR_PO_LINE(INTEGER);
DROP PROCEDURE IF EXISTS OTIF_GUARDIAN.ML.SP_CALCULATE_OTIF_IMPACT();

-- Stage 6: Recovery Engine
DROP VIEW IF EXISTS OTIF_GUARDIAN.ML.V_RECOVERY_BY_ACTION_TYPE;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ML.V_RECOVERY_PORTFOLIO_SUMMARY;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ML.V_BEST_RECOVERY_ACTION;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ML.V_RECOVERY_RECOMMENDATIONS;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ML.V_ACTION_ALTERNATE_SUPPLIER;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ML.V_ACTION_INVENTORY_TRANSFER;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ML.V_ACTION_EXPEDITE;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ML.V_REVENUE_EXPOSURE;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ML.V_AT_RISK_LINES;

-- Stage 5: ML Pipeline
DROP MODEL IF EXISTS OTIF_GUARDIAN.ML.OTIF_BREACH_PREDICTOR;
DROP SNOWFLAKE.ML.CLASSIFICATION IF EXISTS OTIF_GUARDIAN.ML.OTIF_BREACH_MODEL;
DROP TABLE IF EXISTS OTIF_GUARDIAN.ML.REASON_CODES;
DROP TABLE IF EXISTS OTIF_GUARDIAN.ML.SCORED_PO_LINES;
DROP TABLE IF EXISTS OTIF_GUARDIAN.ML.TEST_PREDICTIONS;
DROP TABLE IF EXISTS OTIF_GUARDIAN.ML.TEST_DATA;
DROP TABLE IF EXISTS OTIF_GUARDIAN.ML.TRAIN_DATA;
DROP TABLE IF EXISTS OTIF_GUARDIAN.ML.SCORE_DATA;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ML.V_FEATURE_SET;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ML.V_MATERIAL_DEMAND_FEATURES;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ML.V_SUPPLIER_HISTORY;

-- Stage 4: Semantic View
DROP SEMANTIC VIEW IF EXISTS OTIF_GUARDIAN.SEMANTIC.OTIF_GUARDIAN_SUPPLY_CHAIN;

-- Stage 3: Ontology Views
-- [11 DROP VIEW statements as listed in build-ontology rollback]

-- Stage 2: Data (CAUTION: destroys data)
-- DROP TABLE IF EXISTS OTIF_GUARDIAN.RAW.SUPPLIERS; (repeat for all 12)

-- Stage 1: Full teardown (CAUTION: destroys everything)
-- DROP DATABASE IF EXISTS OTIF_GUARDIAN;
```

**Safety:** Stage 1 and 2 rollback destroys data. Require explicit confirmation before executing.

## Examples

### Example 1: Fresh development deployment

```
User: $deploy-project
Agent: [Asks: environment? → dev. Runs all 8 stages with data generation.
        Reports full success with metrics.]
```

### Example 2: Production promotion (data already exists)

```
User: Deploy to production. Data is already loaded.
Agent: [Sets skip_data_generation=true. Runs stages 1,3-8 (skips 2).
        Extra validation on model metrics. Reports deployment status.]
```

### Example 3: Dry run before production

```
User: Dry run a full deployment — don't execute anything
Agent: [Validates all SQL compiles. Checks prerequisites. Reports what
        WOULD be created without executing. Lists any missing prerequisites.]
```

### Example 4: Incremental update (only ML retrained)

```
User: Just redeploy stages 5-8 (ML through agent)
Agent: [Verifies stages 1-4 already exist via SHOW queries.
        Executes only stages 5-8. Reports delta changes.]
```
