# OTIF Guardian

Enterprise supply chain intelligence platform for On-Time In-Full delivery performance monitoring, predictive risk management, and automated recovery orchestration.

## Overview

OTIF Guardian provides end-to-end visibility into inbound and outbound delivery performance across a multi-plant, multi-supplier supply chain network. It combines structured analytics, machine learning prediction, and deterministic recovery evaluation to reduce OTIF breaches and protect downstream revenue.

**Core capabilities:**

- Real-time OTIF performance monitoring across 8 plants, 60 suppliers, and 250 materials
- ML-powered breach prediction (XGBoost classification) with per-prediction explainability
- Deterministic recovery engine evaluating expedite, inventory transfer, and alternate supplier actions
- Governed AI copilot backed by Cortex Agent with SQL-grounded responses
- Cortex Analyst semantic layer for natural-language supply chain queries

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     OTIF Guardian Platform                        │
├──────────┬──────────┬──────────┬──────────┬─────────────────────┤
│Executive │  Risk    │ Recovery │ Governed │     Settings        │
│Dashboard │  Center  │  Center  │ Copilot  │                     │
├──────────┴──────────┴──────────┴──────────┴─────────────────────┤
│                    Streamlit Application                          │
├─────────────────────────────────────────────────────────────────┤
│                      Cortex Agent                                │
│  ┌─────────────────┬───────────────┬────────────────────────┐   │
│  │supply_analytics │  risk_lookup  │ recovery_simulation    │   │
│  │(Cortex Analyst) │  (ML Predict) │ (Deterministic SQL)    │   │
│  └─────────────────┴───────────────┴────────────────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│  Semantic View (YAML)  │  ML Pipeline  │  Recovery Engine       │
├─────────────────────────────────────────────────────────────────┤
│                    Ontology Views (ANALYTICS)                     │
├─────────────────────────────────────────────────────────────────┤
│                     Raw Data (12 tables)                          │
└─────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
OTIF_Guardian/
├── README.md                  This file
├── CORTEX.md                  CoCo project instructions
├── PROJECT_STATUS.md          Status tracker
├── PROJECT_DECISIONS.md       Architectural decision records
├── docs/
│   ├── ARCHITECTURE.md        System architecture
│   ├── DEPLOYMENT_GUIDE.md    Deployment procedures
│   ├── DEVELOPER_GUIDE.md     Development conventions
│   ├── API_GUIDE.md           Agent and procedure API reference
│   ├── MODEL_CARD.md          ML model documentation
│   ├── EVALUATION_REPORT.md   Test results and coverage
│   ├── PROBLEM_BRIEF.md       Business problem definition
│   ├── IMPACT_STATEMENT.md    Business impact analysis
│   ├── ONTOLOGY.md            Entity relationship model
│   ├── BUSINESS_GLOSSARY.md   Term definitions
│   ├── METRIC_GLOSSARY.md     KPI specifications
│   └── DATA_QUALITY_REPORT.md Data generation report
├── sql/
│   ├── 00_bootstrap.sql       Database, schemas, roles, grants
│   ├── 01_generate_data.sql   Deterministic data generation
│   ├── 02_ontology_views.sql  11 analytical views
│   ├── 03_deploy_semantic_view.sql  Semantic view deployment
│   ├── 04_ml_pipeline.sql     Feature engineering + model training
│   ├── 05_recovery_engine.sql Deterministic recovery evaluation
│   └── 06_deploy_agent.sql    Agent deployment and grants
├── semantic/
│   └── otif_guardian_supply_chain.sv.yaml  Cortex Analyst model
├── python/
│   └── recovery_procedures.sql  Snowpark stored procedures
├── streamlit/
│   ├── app.py                  Multi-page application
│   ├── environment.toml        SiS deployment config
│   ├── lib/data.py             Data access layer
│   └── pages/                  5 application pages
├── agent/
│   └── otif_guardian_agent.agent.yaml  Cortex Agent spec
├── tests/
│   ├── test_sql.sql            SQL correctness tests (25)
│   ├── test_ml.sql             ML pipeline tests (23)
│   ├── test_semantic_agent_governance.sql  Integration tests (32)
│   └── COVERAGE_REPORT.md     Test coverage documentation
├── scripts/
│   └── skills/                 CoCo reusable skills (3)
├── config/
└── artifacts/
```

## Quick Start

```sql
-- 1. Bootstrap infrastructure
@sql/00_bootstrap.sql

-- 2. Generate data
@sql/01_generate_data.sql

-- 3. Build ontology
@sql/02_ontology_views.sql

-- 4. Deploy semantic view
-- See docs/DEPLOYMENT_GUIDE.md

-- 5. Train ML model
@sql/04_ml_pipeline.sql

-- 6. Deploy recovery engine
@sql/05_recovery_engine.sql
@python/recovery_procedures.sql

-- 7. Deploy agent
@sql/06_deploy_agent.sql

-- 8. Run tests
@tests/test_sql.sql
@tests/test_ml.sql
@tests/test_semantic_agent_governance.sql
```

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Platform | Snowflake Enterprise (AWS AP-Southeast-7) |
| ML | Snowflake Native ML Classification (XGBoost) |
| Model Registry | Snowflake Model Registry |
| Semantic | Cortex Analyst Semantic Views (YAML) |
| Agent | Cortex Agent (3 tools) |
| Application | Streamlit in Snowflake |
| Compute | Gen 2 Warehouses |
| Explainability | SHAP via EXPLAIN() method |
| Orchestration | Snowpark Python Stored Procedures |

## Key Metrics

| Metric | Target | Description |
|--------|--------|-------------|
| Inbound OTIF Rate | >= 95% | PO lines delivered on-time and in-full |
| Customer OTIF Rate | >= 95% | Customer orders shipped on-time and in-full |
| Model Accuracy | > 0.55 | Breach prediction correctness |
| Recovery ROI | > 2.0x | Net value protected / cost |

## Governance

- All financial calculations are deterministic SQL — no LLM-generated numbers
- ML predictions include SHAP-based reason codes for auditability
- Recovery recommendations ranked by net value with full cost transparency
- Agent responses grounded in tool-executed SQL results
- Temporal train/test split prevents data leakage
- Role-based access control (ADMIN, ENGINEER, ANALYST, APP)

## Documentation

See `docs/` directory for complete documentation including architecture, deployment, developer guide, API reference, model card, and evaluation report.
