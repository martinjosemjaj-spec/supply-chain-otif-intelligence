# Release Notes — OTIF Guardian RC1

**Version:** 1.0.0-rc1  
**Date:** 2026-08-28  
**Classification:** Release Candidate  
**Status:** Pending Approval

---

## Release Summary

OTIF Guardian 1.0.0-rc1 is the first release candidate of the enterprise supply chain OTIF performance monitoring platform. This release delivers the complete end-to-end solution from data layer through AI-powered decision support.

---

## Features Delivered

### Data Layer
- 12 deterministic raw tables covering suppliers, plants, materials, purchase orders, shipments, receipts, inventory, demand, customer orders, alternate suppliers, and transport lanes
- ~131,000 rows with full referential integrity
- Deterministic seeds (reproducible across environments)

### Ontology Layer
- 11 analytical views materializing entity relationships
- Enriched entity profiles (supplier, material, plant)
- Computed OTIF flags (is_on_time, is_in_full, is_otif)
- Inventory health classification (STOCKOUT/CRITICAL/LOW/ADEQUATE/EXCESS)
- Demand-supply balance with urgency bands

### Semantic Layer
- 1,232-line Cortex Analyst YAML semantic model
- 9 tables, 52 dimensions, 34 facts, 14 metrics
- 12 relationships with cardinality annotations
- 90+ natural-language synonyms
- 9 verified queries (VQRs)
- Duplicate aggregation prevention annotations

### ML Pipeline
- 30-feature XGBoost classification model (Snowflake native)
- Temporal train/test split (no data leakage)
- 5 explicit leakage prevention controls
- Model Registry integration (versioned)
- SHAP-based explainability (per-prediction reason codes)
- Risk tier classification (CRITICAL/HIGH/MEDIUM/LOW/MINIMAL)

### Recovery Engine
- 3 deterministic recovery action evaluators (EXPEDITE, INVENTORY_TRANSFER, ALTERNATE_SUPPLIER)
- Revenue Protected, OTIF Lift, Incremental Cost, Net Value Protected, ROI calculations
- All financial logic in SQL (zero LLM involvement)
- Portfolio-level summary and action-type breakdown
- Single-line drill-down capability

### Cortex Agent
- Single production agent with 3 governed tools
- supply_analytics (Cortex Analyst text-to-SQL)
- risk_lookup (ML prediction retrieval)
- recovery_simulation (deterministic cost/benefit)
- Guardrailed instructions (no LLM calculations, domain-restricted)
- Structured output format templates

### Streamlit Application
- 5-page multi-page application
- Executive Dashboard (KPIs, trends, tier breakdown)
- Risk Center (distribution, drill-down, feature importance, reason codes)
- Recovery Center (portfolio summary, ranked recommendations, simulation)
- Governed Copilot (agent-backed chat with decision traces)
- Settings (model version, metrics, data freshness, audit log)

### Infrastructure
- RBAC hierarchy (ADMIN, ENGINEER, ANALYST, APP)
- Resource monitor (100 credits/month, auto-suspend)
- Gen 2 warehouse with query acceleration
- 5 internal stages with directory listing
- 3 file formats (CSV, JSON, Parquet)

### Test Suite
- 80 tests (66 automated SQL, 14 manual)
- Coverage: SQL, ML, Semantic, Agent, Governance, Edge Cases
- Deployment gate: zero BLOCKER + zero CRITICAL failures

### Documentation
- 9 production documents (Architecture, Deployment, Developer, API, Model Card, Evaluation, Problem Brief, Impact Statement)
- Business Glossary (50+ terms)
- Metric Glossary (18 metrics with formulas)
- Ontology specification (9 entities, 12 relationships)
- Data Quality Report

### CoCo Skills
- 3 reusable skills (build-ontology, train-model, deploy-project)
- Standard SKILL.md format with YAML frontmatter

---

## Known Issues

| ID | Severity | Description | Mitigation |
|----|----------|-------------|------------|
| BC-001 | CRITICAL | `get_model_version()` dead initial query | Fails silently; fallback works |
| BC-002 | CRITICAL | `SCORED_PO_LINES` missing `created_at` column | Data freshness shows NULL for this source |
| SEC-001 | CRITICAL | SQL injection vector in governed copilot | Single-quote escaping present but insufficient |
| BC-003 | HIGH | V_SOURCING_MAP row explosion from unconstrained join | View returns extra rows; not used in critical path |
| PERF-001 | HIGH | O(n²) self-join in V_SUPPLIER_HISTORY | Acceptable at current data volumes |
| GOV-002 | HIGH | No user attribution in recovery engine log | Log captures timestamp but not who ran it |

See `docs/REMEDIATION_REPORT.md` for full details and remediation plan.

---

## Breaking Changes

None. This is the initial release.

---

## Dependencies

| Dependency | Version | Status |
|------------|---------|--------|
| Snowflake | Enterprise (Gen 2) | Required |
| Cortex Analyst | Enabled (account param) | Required |
| Cortex Agents | Available | Required |
| SNOWFLAKE.ML.CLASSIFICATION | Available | Required |
| Model Registry | Available | Required |
| Streamlit in Snowflake | Available | Optional |
| Snowpark Python | 3.11 runtime | Required for procedures |

---

## Deployment Artifacts

52 files, ~340 KB total. See ZIP_MANIFEST.md for complete inventory.
