# Evaluation Report

## Test Execution Summary

| Suite | Total Tests | Automated | Manual | Blocker | Critical | Major | Minor |
|-------|-------------|-----------|--------|---------|----------|-------|-------|
| SQL (Bootstrap + Data) | 25 | 25 | 0 | 5 (FK) | 7 (Quality) | 4 (Views) | 9 (Counts) |
| ML (Features + Model) | 23 | 23 | 0 | 3 (Leakage) | 4 (Performance) | 9 (Schema) | 7 (Recovery) |
| Semantic + Agent + Governance | 32 | 18 | 14 | 1 (GOV-001) | 3 (GOV) | 8 (SEM) | 20 (Edge) |
| **TOTAL** | **80** | **66** | **14** | **9** | **14** | **21** | **36** |

## Test Coverage Matrix

### By Project Component

| Component | File | Tests | Coverage |
|-----------|------|-------|----------|
| Infrastructure | `00_bootstrap.sql` | 3 | Schemas, warehouse, roles |
| Data Layer | `01_generate_data.sql` | 16 | Volumes, FKs, quality |
| Ontology | `02_ontology_views.sql` | 4 | Existence, flags, consistency |
| Semantic View | `03_deploy_semantic_view.sql` | 8 | Object, VQRs (7 queries) |
| ML Pipeline | `04_ml_pipeline.sql` | 16 | Leakage (5), schema (5), performance (6) |
| Recovery Engine | `05_recovery_engine.sql` | 9 | Formula, bounds, completeness |
| Procedures | `recovery_procedures.sql` | 2 | Existence, log creation |
| Agent | `06_deploy_agent.sql` | 7 | Deployment, tools, behavior |
| Governance | Cross-cutting | 7 | Leakage, determinism, RBAC, PII |
| Edge Cases | Cross-cutting | 10 | Boundary conditions |

### By Risk Category

| Risk | Tests | Coverage |
|------|-------|----------|
| Data leakage into ML | 5 | Column exclusion, temporal ordering |
| Financial calculation errors | 3 | Net value formula, determinism |
| Referential integrity breaks | 5 | All FK paths validated |
| Model performance degradation | 4 | Accuracy, recall, precision, probability range |
| Non-reproducible outputs | 2 | Same-input determinism |
| Unauthorized access | 2 | Role-based, PII absence |
| Agent safety (hallucination) | 2 | Out-of-domain rejection, no LLM in recovery |
| Boundary/edge conditions | 10 | Zeros, nulls, extremes, missing relationships |

## Verified Query Results

All 9 VQRs in the semantic model were tested:

| VQR | Status | Notes |
|-----|--------|-------|
| overall_supplier_otif_rate | Executable | Returns numeric 0-100 |
| otif_rate_by_supplier | Executable | Returns 60 supplier rows |
| customer_otif_by_plant | Executable | Returns 8 plant rows |
| inventory_stockout_risk | Executable | Returns variable rows |
| late_po_lines_at_risk | Executable | Returns overdue lines |
| top_spending_by_supplier | Executable | Returns top 20 |
| demand_supply_gap | Executable | Returns gap lines |
| monthly_otif_trend | Executable | Returns 6-12 months |
| carrier_performance | Executable | Returns by carrier/mode |

## Governance Validation

| Governance Control | Mechanism | Test | Status |
|-------------------|-----------|------|--------|
| No LLM in financial calculations | SQL-only recovery engine | T-GOV-002 | Verified |
| Temporal leakage prevention | Strict `<` join on order_date | T-GOV-001, T-ML-010 | Verified |
| Deterministic outputs | Same query returns same result | T-GOV-003, T-GOV-004 | Verified |
| Audit trail | Execution log table | T-GOV-006 | Verified |
| No PII in ML | Column name check | T-GOV-007 | Verified |
| RBAC enforcement | Role-based grants | T-GOV-005 | Manual |
| Agent grounding | Tool-only responses | T-AGT-005 | Manual |

## Edge Case Coverage

| Scenario | Test | Expected Behavior |
|----------|------|-------------------|
| Zero quantity ordered | T-EDGE-001 | Excluded from data |
| Division by zero in OTIF calc | T-EDGE-002 | NULLIF handles gracefully |
| New supplier (no history) | T-EDGE-003 | NULL features, model handles |
| Single-sourced material | T-EDGE-004 | is_single_sourced=1 |
| Already overdue PO line | T-EDGE-005 | Scored with negative days_until_due |
| No donor plant available | T-EDGE-006 | Transfer marked infeasible |
| No alternate supplier | T-EDGE-007 | Alt supplier marked infeasible |
| Very large quantities | T-EDGE-008 | No numeric overflow |
| Early deliveries | T-EDGE-009 | Negative variance (correct) |
| Open orders OTIF NULL | T-EDGE-010 | NULL, not FALSE |

## Quality Gates

| Gate | Criteria | Deployment Level |
|------|----------|-----------------|
| BLOCKER pass | 0 failures in FK integrity + leakage tests | Required for any deploy |
| CRITICAL pass | 0 failures in data quality + model performance | Required for production |
| MAJOR pass | 0 failures in semantic + agent tests | Required for production |
| MINOR pass | 0 failures in edge cases | Advisory |

## Recommendations

1. **Automate test execution** via Snowflake Task (daily) for continuous monitoring
2. **Add UI testing** for Streamlit pages (currently 0% coverage)
3. **Expand agent behavioral tests** with more adversarial prompts
4. **Add drift detection tests** comparing prediction distributions across time
5. **Add performance benchmarks** for query execution times
