# Problem Brief

## Business Problem

Global supply chains face persistent challenges in achieving consistent On-Time In-Full (OTIF) delivery performance. When inbound materials arrive late or in insufficient quantities, the downstream effects cascade: production schedules slip, customer orders are delayed, contractual penalties accumulate, and revenue is lost.

Organizations typically detect OTIF failures reactively — after the delivery window has passed. By that point, recovery options are limited and expensive. The gap between when a breach becomes predictable and when it becomes visible in traditional reporting represents a critical intervention window that is consistently missed.

## Problem Statement

How can a supply chain organization predict which inbound purchase order lines are likely to breach OTIF commitments, and what is the most cost-effective recovery action to prevent downstream revenue impact?

## Scope

| Dimension | Boundary |
|-----------|----------|
| Supply chain tier | Tier 1 inbound (direct suppliers to plants) |
| Geographic | 8 plants across 4 regions (AMER, EMEA, APAC, LATAM) |
| Supplier base | 60 suppliers across 12 countries |
| Material portfolio | 250 active materials |
| Time horizon | Predict breaches 2-60 days before promised delivery |
| Recovery actions | Expedite, inventory transfer, alternate supplier |

## Current State (Before)

- OTIF failures detected only after delivery window closes
- No predictive capability for inbound delivery risk
- Recovery actions decided ad-hoc without cost/benefit analysis
- No systematic link between inbound risk and downstream customer revenue exposure
- Supplier performance reviewed quarterly (too slow for operational response)
- Single-sourced critical materials create invisible concentration risk

## Desired State (After)

- OTIF breach risk predicted at PO creation time with explainable reason codes
- Proactive recovery actions evaluated with deterministic cost/benefit before breach occurs
- Revenue exposure quantified for each at-risk PO line
- Automated ranking of recovery options by net value protected
- Real-time visibility across risk, recovery, and performance via governed dashboard
- AI copilot providing instant answers grounded in verified SQL, not hallucination

## Success Criteria

| Metric | Target | Measurement |
|--------|--------|-------------|
| Prediction lead time | >= 7 days before breach | avg(promised_date - prediction_date) for true positives |
| Model recall (breach class) | >= 40% | Test set evaluation |
| Recovery actions with positive ROI | >= 80% of recommendations | net_value_protected > 0 |
| Revenue protected per quarter | > $0 baseline | SUM(net_value_protected) for executed actions |
| OTIF rate improvement | >= 2 pp lift | Before/after measurement |
| User query response time | < 10 seconds | Agent response latency |

## Constraints

- All financial calculations must be deterministic and auditable (no LLM-generated numbers)
- Model predictions must include explainable reason codes
- Recovery recommendations must show cost alongside benefit (never benefit alone)
- System must operate within existing Snowflake infrastructure (no external services)
- Role-based access must prevent unauthorized modification of ML artifacts
- Data must remain within Snowflake governance boundary

## Stakeholders

| Role | Interest |
|------|----------|
| VP Supply Chain | Portfolio-level OTIF improvement and revenue protection |
| Procurement Director | Supplier performance visibility and recovery cost control |
| Plant Manager | Inbound risk to production schedule |
| Supply Planner | Actionable daily risk report with recovery options |
| Finance | Cost transparency and ROI of recovery investments |
| IT/Data | System maintainability, security, governance compliance |
