# Impact Statement

## Executive Summary

OTIF Guardian transforms supply chain OTIF management from reactive failure detection to predictive risk mitigation. By predicting delivery breaches before they occur and recommending cost-optimized recovery actions, the platform protects downstream revenue while minimizing intervention costs.

## Quantified Impact

### Revenue Protection

| Metric | Value | Methodology |
|--------|-------|-------------|
| At-risk PO lines identified | ~140-200 per scoring cycle | ML model scoring open PO lines at CRITICAL/HIGH/MEDIUM |
| Revenue exposed to breach | Varies by cycle | Downstream customer order value linked to at-risk materials |
| Net value protected (portfolio) | Calculated per run | SUM(revenue_protected - incremental_cost) across all top actions |
| Portfolio ROI | Target > 2.0x | Net value / total recovery cost |

### Operational Efficiency

| Before | After | Improvement |
|--------|-------|-------------|
| Breach detected after delivery | Predicted 7-60 days in advance | Intervention window created |
| Recovery actions decided ad-hoc | Actions ranked by net value with deterministic cost | Optimal allocation |
| Quarterly supplier reviews | Real-time risk scoring with reason codes | Response time reduced |
| Manual analysis per incident | Automated evaluation of 3 recovery strategies | Analyst time saved |
| Siloed visibility (plant-level) | Cross-network portfolio view | Global optimization |

### Decision Quality

| Dimension | Impact |
|-----------|--------|
| **Explainability** | Every prediction has top-5 SHAP reason codes — analysts know WHY a line is at risk |
| **Cost transparency** | Every recommendation shows incremental cost alongside revenue protected — no hidden costs |
| **Determinism** | Same input always produces same recommendation — auditable, reproducible |
| **Governance** | No LLM-generated financial figures — all numbers from SQL execution |
| **Prioritization** | Net Value Protected ranking ensures highest-impact actions are addressed first |

## Risk Reduction

### Single-Source Exposure

The system identifies materials with only one active supplier and flags them when that supplier shows risk signals. This enables proactive qualification of alternate sources before a crisis.

### Concentration Risk

Portfolio-level views reveal when multiple at-risk PO lines converge on the same supplier, material, or plant — enabling cross-functional response before cascading failures occur.

### Demand-Supply Gaps

Forward-looking demand-supply netting identifies gaps before they become stockouts, connecting ML-predicted inbound risk to downstream demand urgency.

## Capability Maturity

| Level | Capability | Status |
|-------|-----------|--------|
| 1 | Descriptive analytics (what happened) | Delivered — Ontology views + Semantic model |
| 2 | Diagnostic analytics (why it happened) | Delivered — SHAP reason codes + drill-down |
| 3 | Predictive analytics (what will happen) | Delivered — ML breach prediction |
| 4 | Prescriptive analytics (what to do) | Delivered — Recovery engine with cost/benefit |
| 5 | Autonomous action (do it automatically) | Future — Human-in-the-loop currently required |

## Value Chain

```
ML Prediction → Risk Identification → Recovery Evaluation → Action Recommendation
                                                                      │
                Revenue Protected ────── Cost Avoided ────── OTIF Lift │
                                                                      ▼
                                                            Business Outcome:
                                                            - Fewer customer delays
                                                            - Lower penalty exposure
                                                            - Reduced expedite waste
                                                            - Improved supplier mgmt
```

## Stakeholder Value

| Stakeholder | Primary Value |
|-------------|---------------|
| **VP Supply Chain** | Portfolio-level OTIF improvement measured in revenue protected and pp lift |
| **Procurement** | Data-driven supplier conversations with explainable risk scores |
| **Plant Operations** | Advance warning of inbound delays with recovery time estimates |
| **Finance** | Cost-justified recovery spend with positive ROI demonstration |
| **Supply Planners** | Daily actionable risk report replacing manual exception monitoring |
| **IT/Data** | Fully governed, auditable, zero-external-dependency architecture |

## Long-Term Strategic Value

1. **Data asset creation** — Historical breach patterns and recovery outcomes build institutional knowledge
2. **Continuous improvement** — Monthly retraining incorporates latest patterns
3. **Supplier development** — Objective, explainable performance data drives improvement programs
4. **Network optimization** — Recovery pattern analysis reveals structural supply chain weaknesses
5. **Platform extensibility** — Architecture supports additional prediction targets (quality, cost overrun, demand volatility)
