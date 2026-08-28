# Deployment Checklist — OTIF Guardian RC1

**Version:** 1.0.0-rc1  
**Deployer:** ___________________  
**Date:** ___________________  
**Environment:** [ ] Dev  [ ] Staging  [ ] Production

---

## Pre-Deployment

| # | Check | Status | Notes |
|---|-------|--------|-------|
| 1 | Snowflake account confirmed Enterprise+ | [ ] | Account: KY70858 |
| 2 | Deployer has ACCOUNTADMIN role | [ ] | |
| 3 | Cortex Analyst enabled (`ENABLE_CORTEX_ANALYST = true`) | [ ] | |
| 4 | Cortex Agents available (`SHOW AGENTS` succeeds) | [ ] | |
| 5 | ML Classification available | [ ] | |
| 6 | Target database name confirmed | [ ] | Default: OTIF_GUARDIAN |
| 7 | No name conflict with existing database | [ ] | `SHOW DATABASES LIKE 'OTIF_GUARDIAN'` |
| 8 | Warehouse size agreed (XS minimum) | [ ] | Default: XS |
| 9 | Credit budget approved (resource monitor: 100/month) | [ ] | |
| 10 | Known issues reviewed and accepted | [ ] | See RELEASE_NOTES_RC1.md |
| 11 | Rollback plan reviewed | [ ] | See ROLLBACK_GUIDE_RC1.md |

---

## Deployment Execution

| Stage | Script | Command | Status | Validation | Pass |
|-------|--------|---------|--------|------------|------|
| 1 | Bootstrap | `@sql/00_bootstrap.sql` | [ ] | 8 schemas exist | [ ] |
| 2 | Data Gen | `@sql/01_generate_data.sql` | [ ] | 12 tables populated | [ ] |
| 3 | Ontology | `@sql/02_ontology_views.sql` | [ ] | 11 views queryable | [ ] |
| 4 | Semantic | `cortex agent-studio sv-deploy` | [ ] | 1 semantic view | [ ] |
| 5 | ML Pipeline | `@sql/04_ml_pipeline.sql` | [ ] | Accuracy > 0.55 | [ ] |
| 6 | Recovery | `@sql/05_recovery_engine.sql` | [ ] | Recommendations > 0 | [ ] |
| 7 | Procedures | `@python/recovery_procedures.sql` | [ ] | 3 procedures | [ ] |
| 8 | Agent | `cortex agent-studio agent-deploy` | [ ] | Agent responds | [ ] |

---

## Post-Deployment Validation

| # | Test | Command | Status |
|---|------|---------|--------|
| 1 | SQL test suite passes | `@tests/test_sql.sql` | [ ] |
| 2 | ML test suite passes | `@tests/test_ml.sql` | [ ] |
| 3 | Governance tests pass | `@tests/test_semantic_agent_governance.sql` | [ ] |
| 4 | Zero BLOCKER failures | Review results | [ ] |
| 5 | Zero CRITICAL failures | Review results | [ ] |
| 6 | Agent test: OTIF query | `cortex agents run <FQN> "What is the OTIF rate?"` | [ ] |
| 7 | Agent test: out-of-domain rejected | `cortex agents run <FQN> "What is the weather?"` | [ ] |
| 8 | Model metrics recorded | `SELECT * FROM V_MODEL_METRICS` | [ ] |
| 9 | Recovery portfolio non-empty | `SELECT * FROM V_RECOVERY_PORTFOLIO_SUMMARY` | [ ] |

---

## Access Grants

| # | Action | Status |
|---|--------|--------|
| 1 | OTIF_GUARDIAN_ANALYST role granted to analyst users | [ ] |
| 2 | OTIF_GUARDIAN_ENGINEER role granted to engineering users | [ ] |
| 3 | OTIF_GUARDIAN_APP role granted to service accounts | [ ] |
| 4 | Agent USAGE granted to ANALYST and ENGINEER roles | [ ] |
| 5 | Semantic view SELECT granted to ANALYST and APP roles | [ ] |

---

## Optional: Streamlit Deployment

| # | Action | Status |
|---|--------|--------|
| 1 | `snow streamlit deploy` executed | [ ] |
| 2 | Application accessible in Snowsight | [ ] |
| 3 | All 5 pages load without error | [ ] |
| 4 | Executive Dashboard shows KPI values | [ ] |

---

## Sign-Off

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Deployer | | | |
| Technical Lead | | | |
| Product Owner | | | |
| Security Review | | | |
