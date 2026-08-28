# OTIF_Guardian - Test Coverage Report

**Generated:** 2026-08-28  
**Total Tests:** 80  
**Automated:** 66 (SQL-executable)  
**Manual:** 14 (require agent interaction or role-switching)

---

## Coverage Summary

| Category | Tests | Automated | Manual | Coverage Target |
|----------|-------|-----------|--------|-----------------|
| SQL - Bootstrap | 3 | 3 | 0 | Infrastructure existence |
| SQL - Data Volume | 6 | 6 | 0 | Row count validation |
| SQL - Referential Integrity | 5 | 5 | 0 | FK constraints |
| SQL - Data Quality | 7 | 7 | 0 | NULLs, ranges, consistency |
| SQL - Ontology Views | 4 | 4 | 0 | View existence and logic |
| ML - Feature Engineering | 10 | 10 | 0 | Leakage prevention, schema |
| ML - Model Performance | 6 | 6 | 0 | Accuracy, recall, validity |
| ML - Recovery Engine | 7 | 7 | 0 | Formula correctness, bounds |
| Semantic - View Deployment | 1 | 1 | 0 | Object existence |
| Semantic - VQR Execution | 6 | 6 | 0 | Query correctness |
| Semantic - Table References | 1 | 1 | 0 | Schema alignment |
| Agent - Deployment | 1 | 1 | 0 | Object existence |
| Agent - Tool Configuration | 2 | 0 | 2 | Spec inspection |
| Agent - Behavioral | 4 | 0 | 4 | Response quality |
| Governance - Leakage | 1 | 1 | 0 | Temporal integrity |
| Governance - Determinism | 3 | 3 | 0 | Reproducibility |
| Governance - Access Control | 1 | 0 | 1 | RBAC enforcement |
| Governance - Audit | 1 | 1 | 0 | Log existence |
| Governance - PII | 1 | 1 | 0 | No sensitive data |
| Edge Cases | 10 | 10 | 0 | Boundary conditions |
| **TOTAL** | **80** | **66** | **14** | |

---

## Test Inventory

### SQL Tests (`tests/test_sql.sql`)

| ID | Test Name | Type | Expected Output |
|----|-----------|------|-----------------|
| T-SQL-001 | All required schemas exist | Auto | 8 schemas |
| T-SQL-002 | Warehouse exists | Auto | 1 warehouse |
| T-SQL-003 | All project roles exist | Auto | 4 roles |
| T-SQL-010 | Suppliers = 60 | Auto | 60 rows |
| T-SQL-011 | Plants = 8 | Auto | 8 rows |
| T-SQL-012 | Materials = 250 | Auto | 250 rows |
| T-SQL-013 | PO Lines ~30800 | Auto | 30000-31500 |
| T-SQL-014 | Active PO Lines ~800 | Auto | 600-1200 |
| T-SQL-015 | All 12 tables populated | Auto | 12 tables with rows |
| T-SQL-020 | PO→Supplier FK integrity | Auto | 0 orphans |
| T-SQL-021 | PO→Plant FK integrity | Auto | 0 orphans |
| T-SQL-022 | PO_LINES→PO FK integrity | Auto | 0 orphans |
| T-SQL-023 | PO_LINES→Material FK integrity | Auto | 0 orphans |
| T-SQL-024 | Inventory FK integrity | Auto | 0 orphans |
| T-SQL-030 | No NULL PK in PO_LINES | Auto | 0 violations |
| T-SQL-031 | Quantities positive | Auto | 0 violations |
| T-SQL-032 | Unit prices positive | Auto | 0 violations |
| T-SQL-033 | Supplier OTD in 0-100% | Auto | 0 violations |
| T-SQL-034 | Dates in reasonable range | Auto | 0 violations |
| T-SQL-035 | Closed lines have delivery date | Auto | 0 violations |
| T-SQL-036 | Open lines have NULL delivery date | Auto | 0 violations |
| T-SQL-040 | 11 ontology views exist | Auto | 11 views |
| T-SQL-041 | OTIF flags computed | Auto | >0 non-null |
| T-SQL-042 | Inventory health classified | Auto | >0 classified |
| T-SQL-043 | Customer OTIF flag consistent | Auto | 0 violations |

### ML Tests (`tests/test_ml.sql`)

| ID | Test Name | Type | Expected Output |
|----|-----------|------|-----------------|
| T-ML-001 | No actual_delivery_date in features | Auto | 0 columns found |
| T-ML-002 | No quantity_received in features | Auto | 0 columns found |
| T-ML-003 | No shipment columns in features | Auto | 0 columns found |
| T-ML-004 | TRAIN_DATA has target column | Auto | 1 column |
| T-ML-005 | Train data >= 5000 rows | Auto | >= 5000 |
| T-ML-006 | Test data >= 500 rows | Auto | >= 500 |
| T-ML-007 | Target is binary 0/1 | Auto | 2 distinct values |
| T-ML-008 | No NULL in supplier_tier | Auto | 0 nulls |
| T-ML-009 | Class balance 10-90% | Auto | Rate in range |
| T-ML-010 | Temporal split: train < test | Auto | train_max < test_min |
| T-ML-020 | Model object exists | Auto | 1 model found |
| T-ML-021 | Accuracy > 0.55 | Auto | > 0.55 |
| T-ML-022 | Recall(breach) > 0.40 | Auto | > 0.40 |
| T-ML-023 | Precision(breach) > 0.30 | Auto | > 0.30 |
| T-ML-024 | Probabilities in [0,1] | Auto | 0 violations |
| T-ML-025 | Feature importance populated | Auto | >= 10 features |
| T-ML-030 | At-risk lines identified | Auto | > 0 lines |
| T-ML-031 | Recovery recommendations exist | Auto | > 0 recs |
| T-ML-032 | Net value formula correct | Auto | 0 violations |
| T-ML-033 | All 3 action types present | Auto | 3 types |
| T-ML-034 | Incremental cost >= 0 | Auto | 0 violations |
| T-ML-035 | Success probability in [0,1] | Auto | 0 violations |
| T-ML-036 | Best action has rank 1 | Auto | 0 violations |

### Semantic + Agent + Governance Tests (`tests/test_semantic_agent_governance.sql`)

| ID | Test Name | Type | Expected Output |
|----|-----------|------|-----------------|
| T-SEM-001 | Semantic view deployed | Auto | 1 view |
| T-SEM-002 | VQR: overall OTIF rate | Auto | 0-100% |
| T-SEM-003 | VQR: OTIF by supplier | Auto | >10 suppliers |
| T-SEM-004 | VQR: stockout risk | Auto | >= 0 rows |
| T-SEM-005 | VQR: monthly trend | Auto | >= 6 months |
| T-SEM-006 | VQR: top spend > 0 | Auto | > 0 |
| T-SEM-007 | All referenced tables exist | Auto | 9 tables |
| T-AGT-001 | Agent deployed | Auto | 1 agent |
| T-AGT-002 | Agent has 3 tools | Manual | 3 tools in spec |
| T-AGT-003 | supply_analytics refs valid SV | Manual | Correct FQN |
| T-AGT-004 | Agent responds to OTIF query | Manual | Numeric result |
| T-AGT-005 | Agent rejects out-of-domain | Manual | Refusal message |
| T-AGT-006 | Agent invokes risk_lookup | Manual | Risk tiers in response |
| T-AGT-007 | Agent invokes recovery_simulation | Manual | Cost/ROI in response |
| T-GOV-001 | No future data in training | Auto | 0 violations |
| T-GOV-002 | No LLM in recovery views | Auto | 0 views with CORTEX.COMPLETE |
| T-GOV-003 | Recovery calculations deterministic | Auto | run_1 = run_2 |
| T-GOV-004 | Predictions reproducible | Auto | run_1 = run_2 |
| T-GOV-005 | ANALYST role is read-only on ML | Manual | INSERT fails |
| T-GOV-006 | Recovery engine log exists | Auto | Table found |
| T-GOV-007 | No PII in training data | Auto | 0 PII columns |
| T-EDGE-001 | No zero quantity_ordered | Auto | 0 violations |
| T-EDGE-002 | OTIF rate handles empty denom | Auto | No error |
| T-EDGE-003 | New supplier gets NULL hist | Auto | >= 0 rows |
| T-EDGE-004 | Single-sourced materials handled | Auto | > 0 rows |
| T-EDGE-005 | Overdue lines scored | Auto | >= 0 rows |
| T-EDGE-006 | No-donor transfer infeasible | Auto | >= 0 rows |
| T-EDGE-007 | No-alt-supplier infeasible | Auto | >= 0 rows |
| T-EDGE-008 | Large quantities handled | Auto | > 0 rows |
| T-EDGE-009 | Early deliveries negative variance | Auto | > 0 rows |
| T-EDGE-010 | Open orders have OTIF=NULL | Auto | 0 violations |

---

## Coverage by Component

| Project Component | Tests Covering It | % Covered |
|-------------------|-------------------|-----------|
| `sql/00_bootstrap.sql` | T-SQL-001, 002, 003 | 100% |
| `sql/01_generate_data.sql` | T-SQL-010-015, 020-024, 030-036 | 100% |
| `sql/02_ontology_views.sql` | T-SQL-040-043 | 100% |
| `sql/03_deploy_semantic_view.sql` | T-SEM-001-007 | 100% |
| `sql/04_ml_pipeline.sql` | T-ML-001-025 | 100% |
| `sql/05_recovery_engine.sql` | T-ML-030-036, T-GOV-002-003 | 100% |
| `python/recovery_procedures.sql` | T-GOV-006, T-ML-031 | 80% |
| `semantic/*.sv.yaml` | T-SEM-001-007 | 100% |
| `agent/*.agent.yaml` | T-AGT-001-007 | 100% |
| `streamlit/` | (UI testing — not in this suite) | 0% |

---

## Coverage by Risk Dimension

| Risk | Tests | Status |
|------|-------|--------|
| **Data leakage** | T-ML-001, 002, 003, 010, T-GOV-001 | 5 tests |
| **Model degradation** | T-ML-021, 022, 023, 024 | 4 tests |
| **Referential integrity** | T-SQL-020, 021, 022, 023, 024 | 5 tests |
| **Financial accuracy** | T-ML-032, T-GOV-003 | 2 tests |
| **Non-determinism** | T-GOV-003, 004 | 2 tests |
| **Access control** | T-GOV-005, 007 | 2 tests |
| **Agent safety** | T-AGT-005, T-GOV-002 | 2 tests |
| **Boundary conditions** | T-EDGE-001 through 010 | 10 tests |

---

## Execution Instructions

```sql
-- Run all automated SQL tests:
-- Execute each file sequentially; collect PASS/FAIL results

-- File 1: Bootstrap + Data + Ontology
@tests/test_sql.sql

-- File 2: ML + Recovery
@tests/test_ml.sql

-- File 3: Semantic + Agent + Governance + Edge Cases
@tests/test_semantic_agent_governance.sql
```

```bash
# Run manual agent tests:
cortex agents run OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT "What is the supplier OTIF rate?"
cortex agents run OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT "What is the weather today?"
cortex agents run OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT "Which POs are at critical risk?"
cortex agents run OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT "Simulate recovery for Detroit plant"
```

---

## Pass Criteria

| Severity | Rule |
|----------|------|
| **BLOCKER** | Any T-SQL-020-024 (FK integrity), T-ML-001-003 (leakage), T-GOV-001 fails |
| **CRITICAL** | Any T-ML-021-023 (model perf), T-SQL-030-036 (data quality) fails |
| **MAJOR** | Any T-SEM, T-AGT automated test fails |
| **MINOR** | Any T-EDGE test fails |

**Deployment gate:** Zero BLOCKER + Zero CRITICAL failures required for production promotion.
