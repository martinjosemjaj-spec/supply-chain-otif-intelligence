# CI/CD Guide

## Architecture

```
Push/PR → ci.yml (lint + pytest)
                    ↓
Manual trigger → deploy.yml → G1: Python Tests
                              → G2: SQL Tests
                              → Deploy stages 1-11 (dependency-ordered)
                              → Post-deploy validation (UAT/PROD)
```

## Environments

| Setting | DEV | UAT | PROD |
|---------|-----|-----|------|
| Database | `OTIF_GUARDIAN_DEV` | `OTIF_GUARDIAN_UAT` | `OTIF_GUARDIAN` |
| Warehouse | `OTIF_GUARDIAN_WH` | `OTIF_GUARDIAN_WH` | `OTIF_GUARDIAN_WH` |
| Role | `OTIF_GUARDIAN_ADMIN` | `OTIF_GUARDIAN_ADMIN` | `OTIF_GUARDIAN_ADMIN` |
| Data generation | Yes | Yes | No (real data) |
| Auto-deploy | Push to `dev` branch | Manual dispatch | Manual dispatch |
| Required gates | G1, G2 | G1-G7 | G1-G9 (all) |
| GitHub Environment | `DEV` | `UAT` | `PROD` (with reviewers) |

## Deployment Stages

Stages execute in strict dependency order:

| # | Stage | Scripts | Gate |
|---|-------|---------|------|
| 1 | data_foundation | 00_bootstrap, 01_generate_data | — |
| 2 | ontology | 02_ontology_views | G2: sql_tests |
| 3 | semantic_layer | 03_deploy_semantic_view + YAML | — |
| 4 | ml_pipeline | 04_ml_pipeline, 04b_ml_pipeline_improved | G4: feature_validation |
| 5 | model_hardening | 07_model_registry, 10_feature_registry, 11_model_hardening | G5: xgboost_validation |
| 6 | recovery_engine | 05_recovery_engine, recovery_procedures.sql | — |
| 7 | decision_layer | 13_decision_layer_hardening | G3: data_quality |
| 8 | monitoring | 08_monitoring, 09_data_quality, 12_production_monitoring | — |
| 9 | governance | 14_semantic_governance, 16_evidence_framework, 17_security_hardening | G8: security_tests |
| 10 | agent | 06_deploy_agent, 15_agent_hardening + YAML | G7: agent_evaluation |
| 11 | streamlit | snow streamlit deploy | G9: streamlit_smoke |

## Validation Gates

| Gate | Source | Pass Criteria | Mandatory |
|------|--------|---------------|-----------|
| G1: python_tests | `pytest tests/test_app.py` | All 45 tests pass | Yes |
| G2: sql_tests | `tests/test_sql.sql` | All 25 tests PASS | Yes |
| G3: data_quality | `AUDIT.SP_RUN_PRODUCTION_MONITORING()` | overall_status != CRITICAL | Yes |
| G4: feature_validation | `tests/test_ml.sql` (T-ML-001..010) | All 10 tests PASS | Yes |
| G5: xgboost_validation | `ML.SP_VALIDATE_MODEL_INDEPENDENTLY('V3')` | overall_status=PASS | Yes |
| G6: semantic_validation | `AUDIT.SP_VALIDATE_SEMANTIC_LAYER()` | overall_status=PASS | Yes |
| G7: agent_evaluation | `AUDIT.SP_RUN_AGENT_EVALUATION('PROD')` | deployment_gate=PASS | Yes |
| G8: security_tests | `AUDIT.SP_VALIDATE_SECURITY_POSTURE()` | overall_status=SECURE | Yes |
| G9: streamlit_smoke | `snow streamlit get-url` | HTTP accessible | No |

## Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `SNOWFLAKE_ACCOUNT` | Snowflake account identifier (e.g., `SNNEIIG-OT77826`) |
| `SNOWFLAKE_USER` | Service account username |
| `SNOWFLAKE_PRIVATE_KEY` | RSA private key (PEM format) for key-pair auth |

## Required GitHub Environments

Create these in Settings → Environments:

- **DEV** — no protection rules
- **UAT** — optional: require reviewer
- **PROD** — required: at least 1 reviewer, restrict to `master` branch

## Required Snowflake Roles

| Role | Purpose | Used By |
|------|---------|---------|
| `OTIF_GUARDIAN_ADMIN` | Deploy DDL, run procedures, manage grants | CI/CD service account |
| `OTIF_GUARDIAN_ENGINEER` | Create/modify ML objects, run training | Data engineers |
| `OTIF_GUARDIAN_ANALYST` | Read-only on ANALYTICS, AUDIT, select ML views | Business analysts |
| `OTIF_GUARDIAN_APP` | Read-only governed views, run Streamlit | Streamlit app runtime |

## Local Development Commands

```bash
# Install dependencies
pip install -r requirements.txt

# Run Python tests (no Snowflake needed)
OTIF_GUARDIAN_MODE=demo python -m pytest tests/test_app.py -v

# Dry-run deployment plan
python scripts/deploy.py --env DEV --dry-run

# Deploy to DEV
python scripts/deploy.py --env DEV

# Deploy single stage
python scripts/deploy.py --env DEV --stage ontology

# Resume from a specific stage
python scripts/deploy.py --env DEV --from-stage 4

# Run verification gates only
python scripts/deploy.py --env PROD --verify

# Run SQL tests against Snowflake
python scripts/run_sql_tests.py --all

# Run specific SQL test file
python scripts/run_sql_tests.py --file tests/test_ml.sql

# Run Snowflake validation procedures
python scripts/run_snowflake_validations.py --gate security_tests
python scripts/run_snowflake_validations.py --all-required --env PROD

# List all gates
python scripts/run_snowflake_validations.py --list
```

## Environment Variables (Local)

```bash
export SNOWFLAKE_ACCOUNT="SNNEIIG-OT77826"
export SNOWFLAKE_USER="SNOWRUBAN"
export SNOWFLAKE_DATABASE="OTIF_GUARDIAN"        # or OTIF_GUARDIAN_DEV
export SNOWFLAKE_WAREHOUSE="OTIF_GUARDIAN_WH"
export SNOWFLAKE_ROLE="OTIF_GUARDIAN_ADMIN"
export SNOWFLAKE_AUTHENTICATOR="externalbrowser"  # or set SNOWFLAKE_PASSWORD
```

## Rollback

Each stage can be rolled back independently:

```bash
# Record a rollback
python scripts/deploy.py --env PROD --rollback --stage agent

# Full teardown (DESTROYS ALL DATA)
# DROP DATABASE IF EXISTS OTIF_GUARDIAN;
```

For model rollback specifically:
```sql
CALL OTIF_GUARDIAN.ML.SP_ROLLBACK_MODEL();
```

## Deployment History

All deployments are tracked in `AUDIT.DEPLOYMENT_HISTORY`:

```sql
SELECT * FROM OTIF_GUARDIAN.AUDIT.DEPLOYMENT_HISTORY
ORDER BY DEPLOYED_AT DESC
LIMIT 20;
```
