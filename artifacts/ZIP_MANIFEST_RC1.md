# ZIP Manifest — OTIF Guardian RC1

**Package:** `OTIF_Guardian_v1.0.0-rc1`  
**Date:** 2026-08-28  
**Total Files:** 52  
**Total Size:** ~340 KB (uncompressed)

---

## Directory Tree

```
OTIF_Guardian/
├── .gitignore                                           515 B
├── CORTEX.md                                          1,372 B
├── PROJECT_DECISIONS.md                               1,082 B
├── PROJECT_STATUS.md                                    670 B
├── README.md                                          8,319 B
│
├── agent/
│   └── otif_guardian_agent.agent.yaml                13,000 B
│
├── artifacts/
│   ├── DEPLOYMENT_CHECKLIST_RC1.md                    3,500 B
│   ├── RELEASE_NOTES_RC1.md                           5,800 B
│   ├── REPOSITORY_CHECKLIST_RC1.md                    5,200 B
│   ├── ROLLBACK_GUIDE_RC1.md                          7,500 B
│   └── ZIP_MANIFEST_RC1.md                            3,200 B
│
├── config/
│   (empty — reserved for environment configuration)
│
├── docs/
│   ├── API_GUIDE.md                                   6,499 B
│   ├── ARCHITECTURE.md                                9,806 B
│   ├── BUSINESS_GLOSSARY.md                           7,581 B
│   ├── DATA_QUALITY_REPORT.md                         9,489 B
│   ├── DEPLOYMENT_GUIDE.md                            4,880 B
│   ├── DEVELOPER_GUIDE.md                             4,930 B
│   ├── EVALUATION_REPORT.md                           5,085 B
│   ├── IMPACT_STATEMENT.md                            5,272 B
│   ├── METRIC_GLOSSARY.md                            10,858 B
│   ├── MODEL_CARD.md                                  5,795 B
│   ├── ONTOLOGY.md                                   13,700 B
│   └── PROBLEM_BRIEF.md                               3,898 B
│
├── python/
│   └── recovery_procedures.sql                       15,330 B
│
├── scripts/
│   └── skills/
│       ├── build-ontology/
│       │   └── SKILL.md                               6,153 B
│       ├── deploy-project/
│       │   └── SKILL.md                              10,263 B
│       └── train-model/
│           └── SKILL.md                               8,002 B
│
├── semantic/
│   └── otif_guardian_supply_chain.sv.yaml            43,556 B
│
├── sql/
│   ├── 00_bootstrap.sql                               9,162 B
│   ├── 01_generate_data.sql                          29,313 B
│   ├── 02_ontology_views.sql                         19,656 B
│   ├── 03_deploy_semantic_view.sql                    3,858 B
│   ├── 04_ml_pipeline.sql                            23,037 B
│   ├── 05_recovery_engine.sql                        25,930 B
│   └── 06_deploy_agent.sql                            3,490 B
│
├── streamlit/
│   ├── app.py                                           871 B
│   ├── environment.toml                                 289 B
│   ├── lib/
│   │   ├── __init__.py                                   24 B
│   │   └── data.py                                    8,587 B
│   └── pages/
│       ├── 01_executive_dashboard.py                  4,067 B
│       ├── 02_risk_center.py                          5,174 B
│       ├── 03_recovery_center.py                      6,376 B
│       ├── 04_governed_copilot.py                     6,356 B
│       └── 05_settings.py                             8,137 B
│
└── tests/
    ├── COVERAGE_REPORT.md                             9,612 B
    ├── test_ml.sql                                    8,714 B
    ├── test_semantic_agent_governance.sql             14,074 B
    └── test_sql.sql                                  10,963 B
```

---

## File Count by Category

| Category | Files | Total Size |
|----------|-------|------------|
| SQL (deployment scripts) | 7 | ~114 KB |
| Semantic (YAML model) | 1 | ~44 KB |
| Agent (spec) | 1 | ~13 KB |
| Python (procedures) | 1 | ~15 KB |
| Streamlit (application) | 7 | ~34 KB |
| Tests | 4 | ~43 KB |
| Documentation | 12 | ~88 KB |
| Release Artifacts | 5 | ~25 KB |
| Skills | 3 | ~24 KB |
| Project Root | 5 | ~12 KB |
| Config (reserved) | 0 | 0 |
| **TOTAL** | **52** (excl. .gitkeep) | **~340 KB** |

---

## Excluded from Package

| Item | Reason |
|------|--------|
| `.git/` | Version control metadata, not deployable |
| `.gitkeep` files (6) | Placeholder files superseded by content |
| `artifacts/` contents | Release-management docs, not deployed to Snowflake |
| `scripts/skills/` | CoCo skill files, registered separately |

---

## Deployment-Critical Files

These files are required for a successful deployment:

| # | File | Role |
|---|------|------|
| 1 | `sql/00_bootstrap.sql` | Creates all infrastructure |
| 2 | `sql/01_generate_data.sql` | Populates data (dev/staging only) |
| 3 | `sql/02_ontology_views.sql` | Creates analytical layer |
| 4 | `semantic/otif_guardian_supply_chain.sv.yaml` | Semantic model definition |
| 5 | `sql/04_ml_pipeline.sql` | ML training and inference |
| 6 | `sql/05_recovery_engine.sql` | Recovery evaluation |
| 7 | `python/recovery_procedures.sql` | Stored procedures |
| 8 | `agent/otif_guardian_agent.agent.yaml` | Agent specification |
| 9 | `sql/06_deploy_agent.sql` | Agent grants |

---

## Integrity Verification

To verify package integrity after transfer:

```powershell
# File count (expected: 52 content files)
(Get-ChildItem -Path OTIF_Guardian -Recurse -File | Where-Object { $_.Name -ne '.gitkeep' }).Count

# Total size check (expected: ~340 KB)
(Get-ChildItem -Path OTIF_Guardian -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1KB
```
