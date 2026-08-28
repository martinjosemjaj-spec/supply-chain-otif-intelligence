# Architecture

## System Overview

OTIF Guardian is a vertically-integrated supply chain intelligence platform running entirely within Snowflake. It spans six architectural layers from raw data ingestion through interactive AI-powered decision support.

## Layer Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 6: PRESENTATION                                        │
│ Streamlit (5 pages) + Cortex Agent (governed copilot)       │
├─────────────────────────────────────────────────────────────┤
│ Layer 5: INTELLIGENCE                                        │
│ Cortex Agent (3 tools) + Cortex Analyst (semantic NLQ)      │
├─────────────────────────────────────────────────────────────┤
│ Layer 4: DECISION                                            │
│ Recovery Engine (deterministic SQL) + Action Ranking         │
├─────────────────────────────────────────────────────────────┤
│ Layer 3: PREDICTION                                          │
│ ML Classification (XGBoost) + SHAP Explainability           │
├─────────────────────────────────────────────────────────────┤
│ Layer 2: ONTOLOGY                                            │
│ 11 Analytical Views + Semantic View (1232-line YAML)        │
├─────────────────────────────────────────────────────────────┤
│ Layer 1: DATA                                                │
│ 12 Raw Tables (deterministic, referentially-intact)          │
├─────────────────────────────────────────────────────────────┤
│ Layer 0: INFRASTRUCTURE                                      │
│ Database, Schemas, Roles, Warehouse, Stages, Formats        │
└─────────────────────────────────────────────────────────────┘
```

## Data Flow

```
Source Data (RAW)
     │
     ▼
Ontology Views (ANALYTICS)
     │
     ├──────────────────────────────┐
     ▼                              ▼
Feature Engineering (ML)     Semantic View (SEMANTIC)
     │                              │
     ▼                              ▼
Model Training               Cortex Analyst
     │                              │
     ▼                              │
Batch Inference (SCORE)             │
     │                              │
     ▼                              │
Recovery Engine                     │
     │                              │
     ├──────────────────────────────┤
     ▼                              ▼
Cortex Agent (3 tools) ◄────────────┘
     │
     ▼
Streamlit Application
```

## Schema Design

| Schema | Purpose | Object Types |
|--------|---------|-------------|
| `RAW` | Source data, immutable after generation | Tables (12) |
| `STAGING` | Transform workspace | Tables (future) |
| `ANALYTICS` | Business-ready views | Views (11) |
| `SEMANTIC` | Cortex Analyst semantic model | Semantic Views, Stages |
| `ML` | Machine learning artifacts | Tables, Views, Models, Procedures |
| `AGENTS` | Cortex Agent definitions | Agents |
| `STREAMLIT` | Application deployment | Streamlit objects |
| `AUDIT` | Operational logging | Tables |

## Security Architecture

```
ACCOUNTADMIN
    └── OTIF_GUARDIAN_ADMIN (full project access)
            └── OTIF_GUARDIAN_ENGINEER (build, transform, deploy)
                    ├── OTIF_GUARDIAN_ANALYST (read analytics/semantic)
                    └── OTIF_GUARDIAN_APP (runtime service account)
```

| Role | Permissions |
|------|-------------|
| ADMIN | ALL on all schemas, manage roles |
| ENGINEER | CRUD on RAW, STAGING, ANALYTICS, ML, AUDIT; USAGE on SEMANTIC, AGENTS |
| ANALYST | SELECT on ANALYTICS, SEMANTIC; USAGE on AGENTS |
| APP | SELECT on ANALYTICS, ML; EXECUTE on procedures; USAGE on AGENTS |

## ML Architecture

```
┌──────────────────────────────────────────────────────────────┐
│ Feature Engineering (leakage-free)                            │
│                                                              │
│ V_SUPPLIER_HISTORY ──┐                                       │
│ (temporal only)      ├──► V_FEATURE_SET (30 features)       │
│ V_MATERIAL_DEMAND ───┘         │                            │
│                                │                            │
│                    ┌───────────┼───────────┐                │
│                    ▼           ▼           ▼                │
│              TRAIN_DATA   TEST_DATA   SCORE_DATA            │
│              (< cutoff)  (cutoff-end)  (open POs)           │
│                    │           │           │                │
│                    ▼           │           │                │
│         SNOWFLAKE.ML.CLASSIFICATION       │                │
│              (XGBoost)         │           │                │
│                    │           ▼           ▼                │
│                    │      EVALUATE    PREDICT               │
│                    │           │           │                │
│                    │           ▼           ▼                │
│                    │      METRICS    SCORED_PO_LINES        │
│                    │                      │                │
│                    ▼                      ▼                │
│           MODEL REGISTRY         RECOVERY ENGINE            │
│           (versioned)            (deterministic)            │
└──────────────────────────────────────────────────────────────┘
```

## Recovery Engine Architecture

The recovery engine is purely deterministic SQL with no LLM involvement:

```
AT_RISK_LINES (ML-scored, CRITICAL/HIGH/MEDIUM)
       │
       ├─── REVENUE_EXPOSURE (downstream customer order value)
       │
       ├─── ACTION: EXPEDITE
       │    └── Cost: premium freight surcharge
       │    └── Benefit: time saved * success probability * exposed revenue
       │
       ├─── ACTION: INVENTORY_TRANSFER
       │    └── Cost: inter-plant shipping + handling
       │    └── Benefit: surplus availability * success probability * exposed revenue
       │
       └─── ACTION: ALTERNATE_SUPPLIER
            └── Cost: price premium + expedite freight (if tight)
            └── Benefit: alt OTD reliability * success probability * exposed revenue

All actions ranked by: NET_VALUE_PROTECTED = REVENUE_PROTECTED - INCREMENTAL_COST
```

## Agent Architecture

Single agent with three tools, each backed by a different execution method:

| Tool | Type | Backend | Guardrail |
|------|------|---------|-----------|
| supply_analytics | cortex_analyst_text_to_sql | Semantic View → SQL | SQL results only |
| risk_lookup | generic (procedure) | SP_GET_RECOVERY_FOR_PO_LINE | Structured output |
| recovery_simulation | generic (procedure) | SP_RUN_RECOVERY_ENGINE | Deterministic SQL |

## Technology Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| ML Framework | Snowflake Native Classification | Zero infrastructure, auto-tuned, built-in EXPLAIN |
| Feature Store | SQL Views | No additional service; temporal join ensures leakage-free |
| Recovery Logic | SQL Views (not LLM) | Deterministic, auditable, reproducible |
| Agent Framework | Cortex Agent | Native Snowflake, tool-grounded, governed |
| Semantic Layer | Cortex Analyst YAML | Natural language queries with verified SQL |
| Application | Streamlit in Snowflake | Zero-deployment, role-integrated |
| Explainability | SHAP (via EXPLAIN method) | Per-prediction feature contributions |

## Non-Functional Requirements

| Requirement | Implementation |
|-------------|----------------|
| Reproducibility | Deterministic seeds, temporal splits, fixed SQL logic |
| Auditability | SHAP reason codes, tool call traces, execution logs |
| Idempotency | All DDL uses CREATE OR REPLACE / IF NOT EXISTS |
| Scalability | Warehouse auto-scaling, Gen 2 compute |
| Security | RBAC, no PII in ML features, no credential exposure |
| Availability | Auto-resume warehouse, stateless views |
