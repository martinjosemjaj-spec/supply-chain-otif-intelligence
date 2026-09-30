# OTIF Guardian — Upgrade Documentation

## Overview

This document covers the Code 2 prototype upgrade implemented per `SKILL.md`.

## Mode Selection

| Mode | How to activate | Behavior |
|------|----------------|----------|
| **Live** | Default (no env var) | Connects to Snowflake, queries real data |
| **Demo** | `OTIF_GUARDIAN_MODE=demo` | Runs locally with synthetic CSV fixtures, no Snowflake needed |

Demo mode labels all pages and copilot responses as synthetic. Live connection failures are never silently converted to demo output.

## Navigation (9 pages)

### New prototype pages
| Page | Description |
|------|-------------|
| **Risk Command Center** | Prioritized inbound risk table + revenue exposure by plant bar chart |
| **PO Decision Detail** | Single PO drill-down: risk metrics, SHAP reasons, recovery comparison |
| **Governed Copilot (v2)** | Suggested questions, agent Q&A, evidence expander, governance guardrails |
| **Model & Controls** | Model provenance, holdout metrics, confusion matrix, governance controls |

### Preserved legacy pages
| Page | Description |
|------|-------------|
| Executive Dashboard | Inbound/customer OTIF KPIs, 12-month trend, supplier tier breakdown |
| Risk Center | Risk distribution, at-risk tables, feature importance, SHAP drill-down |
| Recovery Center | Portfolio summary, action type breakdown, top recommendations, PO simulation |
| Settings | Connection info, model metrics, data freshness, object inventory |

## Sidebar Filters (shared scope per SKILL.md S5)

- **Plant selector**: All plants or specific plant code
- **Risk-band multiselect**: CRITICAL, HIGH, MEDIUM, LOW (default: CRITICAL, HIGH)
- **Min at-risk revenue**: Nonnegative, step $10,000 (default: $0)

Filters apply consistently to Risk Command Center, PO Detail selector, and copilot context.

## Required Snowflake Objects

| Object | Purpose |
|--------|---------|
| `OTIF_GUARDIAN.ML.V_AT_RISK_LINES` | Risk command center, PO detail |
| `OTIF_GUARDIAN.ML.V_SCORED_RESULTS` | Risk summary, scored line data |
| `OTIF_GUARDIAN.ML.V_RECOVERY_RECOMMENDATIONS` | PO recovery options |
| `OTIF_GUARDIAN.ML.V_BEST_RECOVERY_ACTION` | Top recovery actions |
| `OTIF_GUARDIAN.ML.V_TOP_REASON_CODES` | SHAP reason codes per PO line |
| `OTIF_GUARDIAN.ML.V_MODEL_METRICS` | Model performance metrics |
| `OTIF_GUARDIAN.ML.V_CONFUSION_MATRIX` | Confusion matrix |
| `OTIF_GUARDIAN.ML.V_FEATURE_IMPORTANCE` | Feature importance scores |
| `OTIF_GUARDIAN.ML.V_RECOVERY_PORTFOLIO_SUMMARY` | Portfolio summary |
| `OTIF_GUARDIAN.ML.V_RECOVERY_BY_ACTION_TYPE` | Action type breakdown |
| `OTIF_GUARDIAN.RAW.PLANTS` | Plant names for display |
| `OTIF_GUARDIAN.RAW.PO_LINES` | Executive KPIs |
| `OTIF_GUARDIAN.RAW.CUSTOMER_ORDERS` | Customer OTIF KPIs |
| `OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT` | Cortex Agent for copilot |

## Field Mappings (prototype → existing)

Documented in `streamlit/lib/config.py` FIELD_MAP. Key mappings:

| Prototype Field | Mapped To | Notes |
|-----------------|-----------|-------|
| RISK_BAND | RISK_TIER | Same values |
| PREDICTED_BREACH_PROBABILITY | BREACH_PROBABILITY | 0-1 fraction |
| PART_ID | MATERIAL_CODE | Not assumed equivalent |
| PLANT_NAME | PLANT_CODE + join | Join to PLANTS for name |
| AT_RISK_UNITS | QUANTITY_ORDERED | From V_AT_RISK_LINES |
| AT_RISK_REVENUE | LINE_VALUE | From V_AT_RISK_LINES |
| FEASIBLE_FLAG | IS_FEASIBLE | Boolean |
| RANK_SCORE | ACTION_RANK | Integer |

## Unavailable Fields (external dependencies)

These prototype fields require data sources not present in the current deployment:

| Field | Dependency |
|-------|-----------|
| EXPOSURE_SCORE | Requires `V_GOVERNED_RISK_COMMAND_CENTER` view |
| PROJECTED_CUSTOMER_OTIF_PCT | Requires customer OTIF projection model |
| SUPPLIER_OTIF_90D | Requires rolling 90-day supplier OTIF in scored view |
| INVENTORY_DOS | Requires inventory days-of-supply join in scored view |
| CONFIRMED_DELIVERY_DATE | Requires ASN/confirmation data feed |
| PROJECTED_STOCKOUT_DATE | Requires inventory depletion model |
| REJECTION_REASON | Requires governed recovery view with rejection logic |
| ACTION_QTY / RECOVERED_UNITS | Requires governed recovery view |
| ARRIVAL_DATE | Requires governed recovery view |

These are shown as N/A in the UI with explanatory messages in the "Unavailable prototype fields" expander.

## Metric Definitions

- **Inbound OTIF Rate**: `(lines on-time AND in-full) / (total closed+short_closed lines with actual delivery)`. Numerator and denominator both filter on `LINE_STATUS IN ('CLOSED','SHORT_CLOSED')`.
- **Avg Breach Probability**: Unweighted arithmetic mean across filtered risk lines. Labelled as "unweighted mean" per SKILL.md S5.
- **Revenue at Risk**: Sum of `LINE_VALUE` for filtered at-risk lines. Distinct from customer order revenue at risk.

## Demo Limitations

- Demo data is deterministic synthetic (42 risk lines, 3 plants, 4 PO recovery options)
- Copilot returns hard-coded demo responses, not LLM output
- Model metrics, confusion matrix, feature importance not available in demo mode
- Demo responses are clearly labelled with **[DEMO]** prefix

## Tests

52 pytest tests in `tests/test_app.py` covering:
- Configuration validation (5 tests)
- Formatting helpers including None/NaN handling (15 tests)
- Demo mode data access (7 tests)
- Risk command center filters, limits, columns (10 tests)
- PO detail, reason codes, recovery options including infeasible cases (5 tests)
- Copilot empty/valid/unsupported questions (4 tests)
- Demo data generation validity (4 tests)
- Unavailable field documentation (2 tests)

Run: `OTIF_GUARDIAN_MODE=demo python -m pytest tests/test_app.py -v`

## Unverified Integrations

- **Live Cortex Agent calls** — Agent exists and was tested via SQL in a prior session. The Streamlit copilot integration with `DATA_AGENT_RUN` has not been re-verified after the upgrade.
- **Prototype views** (`V_GOVERNED_RISK_COMMAND_CENTER`, `V_GOVERNED_RECOVERY_OPTIONS`) — These do not exist in the current deployment. The app maps to existing ML views instead.
- **Planning horizon enforcement** — The 14-day horizon is not enforced in queries; it is a display-only claim from the prototype.
