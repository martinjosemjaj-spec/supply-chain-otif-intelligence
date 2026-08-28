# Model Card: OTIF Breach Predictor

## Model Overview

| Field | Value |
|-------|-------|
| **Name** | OTIF_BREACH_PREDICTOR |
| **Location** | OTIF_GUARDIAN.ML |
| **Type** | Binary Classification |
| **Framework** | Snowflake Native ML Classification (XGBoost) |
| **Target** | Predict whether an inbound PO line will breach OTIF |
| **Output** | Probability [0,1] + binary class (0=no breach, 1=breach) |
| **Explainability** | SHAP values via EXPLAIN() method |

## Intended Use

**Primary use case:** Identify inbound PO lines at risk of OTIF breach before the delivery date, enabling proactive recovery actions (expedite, transfer, alternate sourcing).

**Users:** Supply chain planners, procurement managers, logistics coordinators.

**Not intended for:** Credit decisions, supplier contractual penalties, customer-facing communications, or any use outside supply chain operations.

## Training Data

| Property | Value |
|----------|-------|
| Source | OTIF_GUARDIAN.RAW.PO_LINES + enrichments |
| Temporal split | Train: order_date < 2026-06-01 |
| Test holdout | order_date >= 2026-06-01 AND < 2026-08-01 |
| Training rows | ~25,000-28,000 |
| Test rows | ~2,000-3,000 |
| Positive class (breach) | ~40-60% of training data |
| Feature count | 30 |

## Features (30)

### Supplier Attributes (known at PO creation)
- supplier_tier (1/2/3)
- supplier_std_lead_time (days)
- supplier_master_otd (%)
- supplier_quality_score (0-100)
- supplier_on_probation (0/1)

### Supplier Historical Performance (temporal, no leakage)
- supplier_hist_volume (prior PO line count)
- supplier_hist_otif_rate (prior OTIF %)
- supplier_hist_avg_variance (avg days late)
- supplier_hist_stddev_variance (delivery consistency)
- supplier_recent_otif_rate (last 90 days)

### Material Attributes
- material_category (categorical)
- abc_class (A/B/C)
- criticality (CRITICAL/IMPORTANT/STANDARD)
- standard_unit_cost ($)
- weight_kg
- material_safety_days

### PO Line Attributes
- quantity_ordered
- unit_price
- line_value (qty * price)
- po_type (STANDARD/BLANKET/EXPEDITE)
- currency (USD/EUR/CNY)

### Plant & Geography
- plant_region (APAC/EMEA/AMER/LATAM)
- plant_country

### Temporal Features
- promised_lead_time_days (days from order to promised)
- order_day_of_week
- order_month
- order_quarter
- lead_time_vs_standard (gap from supplier norm)

### Demand & Sourcing Risk
- demand_30d_qty (recent demand volume)
- demand_30d_count (recent demand signals)
- material_alt_supplier_count
- is_single_sourced (0/1)

## Leakage Prevention

The following data is explicitly EXCLUDED from features:
- `actual_delivery_date` — this IS the outcome
- `quantity_received` — post-delivery information
- All shipment data — occurs after PO creation
- All receipt data — occurs after delivery

Historical supplier metrics use STRICT temporal filtering: only data from PO lines closed BEFORE the current PO's order_date.

## Performance Metrics

| Metric | Threshold | Description |
|--------|-----------|-------------|
| Accuracy | > 0.55 | Overall correctness |
| Precision (breach) | > 0.30 | Of predicted breaches, how many were actual |
| Recall (breach) | > 0.40 | Of actual breaches, how many did we catch |
| F1 (breach) | Derived | Harmonic mean of precision/recall |
| AUC-ROC | Not natively reported | — |

**Note:** Thresholds are intentionally set to reflect a complex multi-factor prediction problem. The model's primary value is in ranking (risk tiers), not binary classification.

## Risk Tier Mapping

| Tier | Probability Range | Action Level |
|------|-------------------|--------------|
| CRITICAL | >= 0.80 | Immediate intervention required |
| HIGH | 0.60 - 0.79 | Recovery action recommended |
| MEDIUM | 0.40 - 0.59 | Monitor closely |
| LOW | 0.20 - 0.39 | Standard monitoring |
| MINIMAL | < 0.20 | No action needed |

## Limitations

1. **Cold-start suppliers:** New suppliers with no historical data receive NULL for temporal features. The model handles this via XGBoost's native NULL handling but predictions may be less reliable.

2. **External disruptions:** The model cannot predict force majeure events (natural disasters, geopolitical disruptions, pandemics) that are not reflected in historical patterns.

3. **Concept drift:** As supply chain conditions change, model performance will degrade. Recommended retraining frequency: monthly.

4. **Feature availability:** If a supplier's historical data is sparse (< 10 prior PO lines), temporal features may have high variance.

5. **Class balance sensitivity:** If production breach rates shift significantly from training distribution, recalibration is needed.

## Ethical Considerations

- The model does not use any personally identifiable information (PII)
- Supplier scores are based on objective delivery performance, not demographics
- Predictions include SHAP explanations for transparency and auditability
- The model recommends actions; final decisions remain with human operators
- No automated penalties are triggered by model predictions alone

## Monitoring

| Signal | Threshold | Action |
|--------|-----------|--------|
| Accuracy drops below 0.50 | Monthly check | Retrain |
| Breach rate shifts > 15pp from training | Monthly check | Retrain with new split |
| Feature distribution shift | Quarterly | Investigate and potentially re-engineer |
| Recovery engine ROI < 1.0x | Continuous | Review cost assumptions |

## Versioning

| Version | Date | Split | Notes |
|---------|------|-------|-------|
| V1 | 2026-08-28 | 2026-06-01 | Initial training, 30 features |

Managed via: `OTIF_GUARDIAN.ML.OTIF_BREACH_PREDICTOR` (Snowflake Model Registry)
