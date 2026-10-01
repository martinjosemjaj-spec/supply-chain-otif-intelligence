# OTIF Guardian: End-to-End ML Solution Architecture

**Document Classification:** Stakeholder-Ready Architecture Overview
**Version:** 2.0 | **Date:** October 2026
**Platform:** Snowflake (single-account, fully-native)

---

## 1. Executive Summary

OTIF Guardian is a vertically-integrated supply chain intelligence platform that predicts inbound purchase order OTIF (On-Time In-Full) delivery failures, quantifies downstream revenue exposure, and recommends cost-effective recovery actions — all running natively within Snowflake.

The system transforms reactive OTIF failure detection into proactive risk management. Instead of discovering a delivery breach after the fact, procurement teams receive ML-scored risk predictions days to weeks before the promised delivery date, accompanied by ranked recovery options with deterministic cost/benefit analysis.

**Key numbers from the deployed system:**
- 3,326 open PO lines scored in real-time
- 219 at-risk lines identified (114 CRITICAL, 2 HIGH, 103 MEDIUM)
- $5.5M total revenue at risk across the portfolio
- $2.08M net value protectable via recommended recovery actions
- 12.5x portfolio-level ROI on recommended interventions
- 30+ engineered features feeding the XGBoost classifier
- 3 recovery action types evaluated with deterministic SQL

---

## 2. Architecture Overview

```
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │                     OTIF GUARDIAN SOLUTION ARCHITECTURE                      │
 │                                                                             │
 │  ┌─────────────────────────────────────────────────────────────────────────┐ │
 │  │ LAYER 6: PRESENTATION                                                  │ │
 │  │  Streamlit in Snowflake (4 active pages + 4 legacy)                    │ │
 │  │  ┌────────────────┐ ┌────────────────┐ ┌──────────────┐ ┌──────────┐  │ │
 │  │  │ Risk Command   │ │ PO Decision    │ │ Governed     │ │ Model &  │  │ │
 │  │  │ Center         │ │ Detail         │ │ Copilot      │ │ Controls │  │ │
 │  │  └───────┬────────┘ └───────┬────────┘ └──────┬───────┘ └────┬─────┘  │ │
 │  └──────────┼──────────────────┼─────────────────┼──────────────┼────────┘ │
 │             │                  │                  │              │          │
 │  ┌──────────┼──────────────────┼─────────────────┼──────────────┼────────┐ │
 │  │ LAYER 5: INTELLIGENCE      │                  │              │         │ │
 │  │          │                  │                  ▼              │         │ │
 │  │          │                  │    ┌────────────────────────┐   │         │ │
 │  │          │                  │    │   Cortex Agent         │   │         │ │
 │  │          │                  │    │  (claude-sonnet-4-6)   │   │         │ │
 │  │          │                  │    │  ┌──────────────────┐  │   │         │ │
 │  │          │                  │    │  │ supply_analytics │──┼───┼──► SV   │ │
 │  │          │                  │    │  │ risk_lookup      │──┼──►│  SP     │ │
 │  │          │                  │    │  │ recovery_sim     │──┼──►│  SP     │ │
 │  │          │                  │    │  └──────────────────┘  │   │         │ │
 │  │          │                  │    └────────────────────────┘   │         │ │
 │  └──────────┼──────────────────┼────────────────────────────────┼────────┘ │
 │             │                  │                                 │          │
 │  ┌──────────┼──────────────────┼─────────────────────────────────┼────────┐ │
 │  │ LAYER 4: DECISION (Recovery Engine)                           │         │ │
 │  │          │                  │                                 │         │ │
 │  │    ┌─────▼──────┐   ┌──────▼───────┐   ┌──────────────┐     │         │ │
 │  │    │ EXPEDITE   │   │ INVENTORY    │   │ ALTERNATE    │     │         │ │
 │  │    │ premium    │   │ TRANSFER     │   │ SUPPLIER     │     │         │ │
 │  │    │ freight    │   │ inter-plant  │   │ emergency    │     │         │ │
 │  │    └─────┬──────┘   └──────┬───────┘   └──────┬───────┘     │         │ │
 │  │          └─────────────────┼────────────────────┘            │         │ │
 │  │                     ┌──────▼───────┐                         │         │ │
 │  │                     │ ACTION RANK  │  NET_VALUE_PROTECTED    │         │ │
 │  │                     │ (deterministic)                        │         │ │
 │  │                     └──────┬───────┘                         │         │ │
 │  └────────────────────────────┼─────────────────────────────────┼────────┘ │
 │                               │                                 │          │
 │  ┌────────────────────────────┼─────────────────────────────────┼────────┐ │
 │  │ LAYER 3: PREDICTION        │                                 │         │ │
 │  │                    ┌───────▼──────────┐                      │         │ │
 │  │                    │  XGBoost V2      │                      │         │ │
 │  │                    │  ───────────     │                      │         │ │
 │  │                    │  SMOTE + HPO     │──────────────────────┘         │ │
 │  │                    │  Calibrated      │                                │ │
 │  │                    │  Threshold: 0.33 │     ┌────────────────────┐     │ │
 │  │                    │  ROC-AUC: 0.9502 │────►│ SCORED_PO_LINES   │     │ │
 │  │                    └───────▲──────────┘     │ (3,326 open POs)  │     │ │
 │  │                            │                └────────────────────┘     │ │
 │  └────────────────────────────┼─────────────────────────────────────────┘ │
 │                               │                                           │
 │  ┌────────────────────────────┼─────────────────────────────────────────┐ │
 │  │ LAYER 2: ONTOLOGY          │                                         │ │
 │  │                   ┌────────┴───────┐    ┌─────────────────────────┐  │ │
 │  │                   │ V_FEATURE_SET  │    │  11 Analytical Views    │  │ │
 │  │                   │ _V2 (38 cols)  │    │  (ANALYTICS schema)     │  │ │
 │  │                   └────────▲───────┘    └────────────▲────────────┘  │ │
 │  │                            │                         │               │ │
 │  │  ┌────────────────────┐    │    ┌────────────────────┘               │ │
 │  │  │ V_SUPPLIER_HISTORY │────┘    │  ┌─────────────────────────────┐  │ │
 │  │  │ _V2 (multi-window) │         │  │  Semantic View (1200-line   │  │ │
 │  │  └────────────────────┘         │  │  YAML, 17 tables, 200+     │  │ │
 │  │  ┌────────────────────┐         │  │  metrics, 30 relationships) │  │ │
 │  │  │ V_MATERIAL_DEMAND  │─────────┘  └─────────────────────────────┘  │ │
 │  │  │ _FEATURES          │                                              │ │
 │  │  └────────────────────┘                                              │ │
 │  └──────────────────────────────────────────────────────────────────────┘ │
 │                               │                                           │
 │  ┌────────────────────────────┼─────────────────────────────────────────┐ │
 │  │ LAYER 1: DATA              │                                         │ │
 │  │                   ┌────────┴────────┐                                │ │
 │  │  ┌────────────┐  │ 12 RAW Tables    │  ┌──────────────┐             │ │
 │  │  │ SUPPLIERS  │  │ ──────────────   │  │ CUSTOMER     │             │ │
 │  │  │ (60)       │  │ PURCHASE_ORDERS  │  │ _ORDERS      │             │ │
 │  │  ├────────────┤  │ PO_LINES         │  │ (12,000)     │             │ │
 │  │  │ MATERIALS  │  │ SHIPMENTS        │  ├──────────────┤             │ │
 │  │  │ (250)      │  │ RECEIPTS         │  │ DEMAND       │             │ │
 │  │  ├────────────┤  │ INVENTORY        │  │ (15,000)     │             │ │
 │  │  │ PLANTS     │  │ DEMAND           │  ├──────────────┤             │ │
 │  │  │ (8)        │  │ TRANSPORT_LANES  │  │ ALT_SUPPLIERS│             │ │
 │  │  └────────────┘  │ ALT_SUPPLIERS    │  │ (8,086)      │             │ │
 │  │                  └──────────────────┘  └──────────────┘             │ │
 │  └──────────────────────────────────────────────────────────────────────┘ │
 │                                                                           │
 │  ┌──────────────────────────────────────────────────────────────────────┐ │
 │  │ LAYER 0: INFRASTRUCTURE                                              │ │
 │  │  Database: OTIF_GUARDIAN    Warehouse: OTIF_GUARDIAN_WH (XS)         │ │
 │  │  8 Schemas    4 RBAC Roles    Resource Monitor (100 credits/mo)     │ │
 │  │  4 Stages     3 File Formats   3 Sequences                          │ │
 │  └──────────────────────────────────────────────────────────────────────┘ │
 └──────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Data Layer

### 3.1 Source Data Model

The system operates on 12 deterministically-generated tables in the `RAW` schema, simulating a realistic global supply chain with referential integrity.

| Table | Rows | Description | Key Relationships |
|-------|------|-------------|-------------------|
| `SUPPLIERS` | 60 | Supplier master: tier, lead time, OTD%, quality score | Root entity |
| `MATERIALS` | 250 | Material master: category, ABC class, criticality, cost | Root entity |
| `PLANTS` | 8 | Manufacturing plants across 4 regions (AMER, EMEA, APAC, LATAM) | Root entity |
| `PURCHASE_ORDERS` | 6,400 | PO headers: supplier, plant, type, status | FK to SUPPLIERS, PLANTS |
| `PO_LINES` | 30,800 | Line items: material, quantity, delivery dates, status | FK to PURCHASE_ORDERS, MATERIALS |
| `SHIPMENTS` | 28,000 | Inbound shipment tracking: carrier, mode, status | FK to PO_LINES |
| `RECEIPTS` | 26,000 | Goods receipt: actual delivery, quantity received | FK to PO_LINES, PLANTS |
| `CUSTOMER_ORDERS` | 12,000 | Downstream customer orders linked to materials | FK to MATERIALS, PLANTS |
| `INVENTORY` | 1,353 | Current inventory position: on-hand, in-transit, safety stock | FK to MATERIALS, PLANTS |
| `DEMAND` | 15,000 | Demand signals: forecast, actual, quantity, date | FK to MATERIALS, PLANTS |
| `ALTERNATE_SUPPLIERS` | 8,086 | Backup sourcing options per material | FK to MATERIALS, SUPPLIERS |
| `TRANSPORT_LANES` | 91 | Logistics network: transit days, cost/kg, reliability | Cross-reference |

### 3.2 Data Generation Strategy

All data is generated deterministically using `HASH()` functions with fixed seeds. This ensures:
- Complete reproducibility across environments
- Referential integrity between all 12 tables
- Realistic breach rates (~10% of closed PO lines)
- Geographic distribution across 12 supplier countries and 4 plant regions
- Temporal coverage from 2024 through mid-2026

---

## 4. Feature Engineering

### 4.1 Feature Pipeline Design

Feature engineering runs as SQL views with strict temporal isolation to prevent data leakage.

```
             ┌──────────────────────────────────────────────────┐
             │           V_FEATURE_SET_V2 (38 columns)          │
             │                                                  │
             │  ┌──────────────┐  ┌────────────┐  ┌─────────┐  │
             │  │ PO_LINES     │  │ SUPPLIERS  │  │ PLANTS  │  │
             │  │ + POs        │  │ (static    │  │ (static │  │
             │  │ (temporal)   │  │  master)   │  │  master) │  │
             │  └──────┬───────┘  └─────┬──────┘  └────┬────┘  │
             │         │                │               │       │
             │    ┌────▼────────────────▼───────────────▼────┐  │
             │    │         JOIN HUB (per PO line)           │  │
             │    └─────────────────────┬────────────────────┘  │
             │                          │                       │
             │  ┌──────────┐  ┌────────┴────────┐  ┌────────┐  │
             │  │ Supplier │  │ Derived         │  │ Material│  │
             │  │ History  │  │ Features        │  │ Demand  │  │
             │  │ (30/60/  │  │ (ratios, flags, │  │ Features│  │
             │  │  90 day) │  │  temporal)      │  │ (30-day │  │
             │  │ V2       │  │                 │  │  window) │  │
             │  └──────────┘  └─────────────────┘  └────────┘  │
             └──────────────────────────────────────────────────┘
```

### 4.2 Feature Categories (38 Total)

| Category | Count | Examples |
|----------|-------|---------|
| **Supplier Master Attributes** | 5 | `supplier_tier`, `supplier_std_lead_time`, `supplier_quality_score`, `supplier_on_probation`, `supplier_master_otd` |
| **Supplier Historical (temporal)** | 8 | `supplier_hist_otif_rate`, `supplier_30d/60d/90d_otif_rate`, `supplier_recent_breach_count`, `supplier_otif_trend` |
| **Material Attributes** | 6 | `material_category`, `abc_class`, `criticality`, `standard_unit_cost`, `weight_kg`, `material_safety_days` |
| **PO Line Attributes** | 4 | `quantity_ordered`, `unit_price`, `line_value`, `po_type`, `currency` |
| **Plant & Geography** | 2 | `plant_region`, `plant_country` |
| **Temporal** | 5 | `promised_lead_time_days`, `order_day_of_week`, `order_month`, `order_quarter`, `lead_time_vs_standard` |
| **Sourcing Risk** | 3 | `material_alt_supplier_count`, `is_single_sourced`, `demand_30d_qty` |
| **V2 Enhancements** | 5 | `supplier_otif_trend`, `lead_time_ratio`, `inventory_coverage_ratio`, `material_breach_rate`, `supplier_material_breach_rate`, `supplier_open_po_share` |

### 4.3 Leakage Prevention

The feature pipeline enforces strict temporal boundaries:

1. **Outcome exclusion:** `actual_delivery_date`, `quantity_received`, and all post-shipment data are excluded from features.
2. **Temporal supplier history:** `V_SUPPLIER_HISTORY_V2` computes rolling OTIF rates using only PO lines closed *before* the current PO's `order_date`.
3. **Train/test split:** Temporal split at `order_date < '2026-06-01'` (train) vs. `>= '2026-06-01'` (test). No random shuffling.
4. **Scoring population:** Only PO lines with `OTIF_BREACH IS NULL` (open/in-transit) are scored.

---

## 5. XGBoost Model Design

### 5.1 Model Evolution

The model went through two major iterations:

| Aspect | V1 (Initial) | V2 (Improved) |
|--------|-------------|---------------|
| **Framework** | Snowflake Native `ML.CLASSIFICATION` | Snowpark Python XGBoost |
| **Class handling** | `scale_pos_weight` only | SMOTE oversampling on train split |
| **Hyperparameters** | Default/manual | `RandomizedSearchCV` (50 iterations, 3-fold) |
| **Calibration** | None | Isotonic calibration (3-fold on original train) |
| **Threshold** | Default 0.50 | Optimal 0.33 (maximizes F1 on holdout) |
| **Regularization** | Default | `max_depth=5`, `reg_alpha=1`, `reg_lambda=2` |
| **ROC-AUC** | 0.5320 | **0.9502** |
| **Recall** | 0.0824 | **0.7978** |
| **F1** | 0.0832 | **0.6013** |
| **Precision** | 0.0840 | **0.4824** |

### 5.2 Training Pipeline

The training pipeline is implemented as stored procedure `SP_TRAIN_IMPROVED_MODEL` running Snowpark Python on the warehouse:

```
  TRAIN_DATA_V2 (27,351 rows)
       │
       ▼
  ┌──────────────────┐
  │ 1. Encode         │  Label-encode 7 categorical columns
  │    categoricals    │  Fill NULLs with -999
  └────────┬───────────┘
           │
           ▼
  ┌──────────────────┐
  │ 2. Stratified     │  80/20 split preserving ~10% breach rate
  │    train/test     │  
  └────────┬───────────┘
           │
           ▼
  ┌──────────────────┐
  │ 3. SMOTE          │  Oversample minority class on 80% train ONLY
  │    oversampling   │  (not applied to holdout)
  └────────┬───────────┘
           │
           ▼
  ┌──────────────────┐
  │ 4. RandomizedSearch│  50 iterations x 3-fold CV
  │    CV (HPO)       │  Optimizing F1 score
  └────────┬───────────┘
           │
           ▼
  ┌──────────────────┐
  │ 5. Train final    │  XGBClassifier with best hyperparameters
  │    XGBoost model  │
  └────────┬───────────┘
           │
           ▼
  ┌──────────────────┐
  │ 6. Isotonic       │  3-fold calibration on original train
  │    calibration    │  (not SMOTE data)
  └────────┬───────────┘
           │
           ▼
  ┌──────────────────┐
  │ 7. Find optimal   │  Sweep thresholds 0.05-0.95 on holdout
  │    threshold      │  Maximize F1 → 0.33
  └────────┬───────────┘
           │
           ▼
  ┌──────────────────┐
  │ 8. Score open POs │  3,326 lines → SCORED_PO_LINES
  │                   │  Output: probability + risk tier
  └────────┬───────────┘
           │
           ▼
  ┌──────────────────┐
  │ 9. Save artifact  │  @MODEL_STAGE/breach_model_v2/
  │    to stage       │
  └──────────────────┘
```

### 5.3 Hyperparameter Search Space

```
Parameter               Range
─────────────────────   ─────────────────────────────
n_estimators            [100, 200, 300, 500]
max_depth               [3, 4, 5, 6, 7]
learning_rate           [0.01, 0.05, 0.1, 0.15]
subsample               [0.7, 0.8, 0.9, 1.0]
colsample_bytree        [0.7, 0.8, 0.9, 1.0]
reg_alpha               [0, 0.1, 0.5, 1.0]
reg_lambda              [1.0, 1.5, 2.0, 3.0]
min_child_weight        [1, 3, 5, 7]
gamma                   [0, 0.1, 0.3, 0.5]
```

### 5.4 Risk Tier Mapping

Model output probabilities are mapped to actionable risk tiers:

| Tier | Probability Range | Action Level | Current Count |
|------|-------------------|--------------|---------------|
| **CRITICAL** | >= 0.80 | Immediate intervention | 114 lines |
| **HIGH** | 0.60 - 0.79 | Recovery recommended | 2 lines |
| **MEDIUM** | 0.40 - 0.59 | Close monitoring | 103 lines |
| **LOW** | 0.20 - 0.39 | Standard monitoring | — |
| **MINIMAL** | < 0.20 | No action | — |

---

## 6. Recovery Engine

### 6.1 Design Philosophy

The Recovery Engine is entirely **deterministic SQL** — no LLM-generated calculations, no estimates, no probabilistic inference. Every cost, benefit, and ranking is computed from governed formulas traceable to source data.

### 6.2 Action Types

```
                     AT-RISK PO LINE
                           │
          ┌────────────────┼────────────────┐
          │                │                │
    ┌─────▼─────┐   ┌─────▼─────┐   ┌─────▼──────┐
    │ EXPEDITE  │   │ INVENTORY │   │ ALTERNATE  │
    │           │   │ TRANSFER  │   │ SUPPLIER   │
    │ Premium   │   │ Move stock│   │ Emergency  │
    │ freight   │   │ between   │   │ order from │
    │ surcharge │   │ plants    │   │ backup     │
    └─────┬─────┘   └─────┬─────┘   └─────┬──────┘
          │                │                │
          │  Feasibility   │   Feasibility  │  Feasibility
          │  checks:       │   checks:      │  checks:
          │  - Time buffer │   - Surplus    │  - Alt exists
          │  - Route exists│     inventory  │  - Active status
          │                │   - Different  │  - OTD > 70%
          │                │     plant      │
          └────────────────┼────────────────┘
                           │
                    ┌──────▼──────┐
                    │ RANK BY:    │
                    │ NET_VALUE_  │
                    │ PROTECTED   │
                    │ (rev - cost)│
                    └─────────────┘
```

### 6.3 Cost/Benefit Formulas

**Expedite:**
- Cost: `unit_cost * quantity * premium_rate * (1 - days_remaining/lead_time)`
- Benefit: `revenue_exposed * success_probability * time_saved_fraction`

**Inventory Transfer:**
- Cost: `shipping_cost_per_kg * weight * quantity + handling_fee`
- Benefit: `revenue_exposed * min(surplus/needed, 1.0) * success_probability`

**Alternate Supplier:**
- Cost: `(alt_unit_cost - original_cost) * quantity + expedite_if_tight`
- Benefit: `revenue_exposed * alt_otd_reliability * success_probability`

### 6.4 Portfolio-Level Results (Live)

| Metric | Value |
|--------|-------|
| Addressable at-risk lines | 219 |
| Total feasible actions evaluated | 260 |
| Total revenue protectable | $2,250,477 |
| Total incremental cost | $166,720 |
| Net value protected | $2,083,757 |
| Portfolio ROI | **12.5x** |
| Recommended expedites | 13 |
| Recommended inventory transfers | 11 |
| Recommended alternate suppliers | 76 |
| Lines with no cost-effective action | 119 |

---

## 7. Semantic Layer

### 7.1 Semantic View

The Cortex Analyst semantic view (`OTIF_GUARDIAN.SEMANTIC.OTIF_GUARDIAN_SUPPLY_CHAIN`) provides a natural-language query interface over the entire data model.

**Specifications:**
- ~1,200-line YAML definition
- 17 logical tables (mapping to RAW and ML schema objects)
- 200+ measures and dimensions
- 30 relationships (foreign key mappings)
- Supports Cortex Analyst text-to-SQL generation
- Extensions: CA (Cortex Analyst) + AI

### 7.2 Covered Domains

| Domain | Tables | Key Metrics |
|--------|--------|-------------|
| **Supplier Performance** | SUPPLIERS, PO_DELIVERY | OTIF rate, OTD%, quality score, delivery variance |
| **Procurement** | PURCHASE_ORDERS, PO_LINES | PO count, line value, lead time |
| **Inventory** | INVENTORY | On-hand, in-transit, days of supply, stock coverage |
| **Customer Fulfillment** | CUSTOMER_ORDERS | Fill rate, order OTIF, revenue at risk |
| **Demand** | DEMAND | Forecast vs actual, demand signals |
| **Logistics** | SHIPMENTS, TRANSPORT_LANES | Transit days, carrier reliability, cost/kg |
| **Quality** | RECEIPTS | Receipt quality, quantity variance, damage rate |
| **ML Predictions** | SCORED_PO_LINES, AT_RISK_LINES | Breach probability, risk tier, feature importance |
| **Recovery** | RECOVERY_RECOMMENDATIONS | Action type, cost, revenue protected, ROI |

---

## 8. Cortex Agent

### 8.1 Agent Design

The OTIF Guardian Agent (`OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT`) provides a conversational interface backed by three governed tools.

```
                        User Question
                             │
                             ▼
                    ┌────────────────┐
                    │  Cortex Agent  │
                    │  (claude-      │
                    │   sonnet-4-6)  │
                    └───────┬────────┘
                            │
            ┌───────────────┼───────────────┐
            │               │               │
    ┌───────▼───────┐ ┌────▼─────┐  ┌──────▼──────┐
    │ supply_       │ │ risk_    │  │ recovery_   │
    │ analytics     │ │ lookup   │  │ simulation  │
    │               │ │          │  │             │
    │ Cortex Analyst│ │ Stored   │  │ Stored      │
    │ text-to-SQL   │ │ Procedure│  │ Procedure   │
    │               │ │          │  │             │
    │ Semantic View │ │ SP_GET_  │  │ SP_RUN_     │
    │ → SQL → Data  │ │ RECOVERY │  │ RECOVERY_   │
    │               │ │ _FOR_PO  │  │ ENGINE      │
    └───────────────┘ └──────────┘  └─────────────┘
```

### 8.2 Tool Routing Logic

| User Intent | Tool Selected | Backend |
|-------------|---------------|---------|
| "What is the OTIF rate?" | `supply_analytics` | Semantic View → SQL |
| "Which suppliers underperform?" | `supply_analytics` | Semantic View → SQL |
| "What is at risk this week?" | `risk_lookup` | `SP_GET_RECOVERY_FOR_PO_LINE` |
| "Show risk for PO-0001234" | `risk_lookup` | `SP_GET_RECOVERY_FOR_PO_LINE` |
| "Simulate recovery for Detroit" | `recovery_simulation` | `SP_RUN_RECOVERY_ENGINE` |
| "How much to expedite PO X?" | `recovery_simulation` | `SP_RUN_RECOVERY_ENGINE` |

### 8.3 Governance Guardrails

1. **No self-calculation:** The agent never performs arithmetic — all numbers come from tool results
2. **No fabrication:** If a tool returns no results, the agent says so
3. **Source attribution:** Every number cites which tool produced it
4. **Cost transparency:** Recovery recommendations always show cost alongside benefit
5. **Domain boundary:** Agent refuses questions outside supply chain OTIF
6. **Read-only:** No ERP writes, no data modification

---

## 9. Streamlit Application

### 9.1 Application Architecture

```
                    ┌──────────────────────────────────┐
                    │            app.py                 │
                    │  Hero header, sidebar filters,    │
                    │  page router                      │
                    └──────────┬───────────────────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
   ┌──────▼──────┐    ┌───────▼──────┐    ┌───────▼───────┐
   │ lib/config  │    │ lib/data.py  │    │ lib/__init__  │
   │ (objects,   │    │ (queries,    │    │               │
   │  field map, │    │  formatting, │    │               │
   │  display)   │    │  demo mode)  │    │               │
   └─────────────┘    └──────────────┘    └───────────────┘

  Page Router (sidebar navigation):
  ──────────────────────────────────
  ┌────────────────────────┐  Primary Pages (v2):
  │ 10_risk_command_center │  Risk table + revenue exposure by plant
  ├────────────────────────┤
  │ 11_po_decision_detail  │  Single PO: risk evidence + recovery options
  ├────────────────────────┤
  │ 12_governed_copilot    │  Agent-backed Q&A with evidence traces
  ├────────────────────────┤
  │ 13_model_controls      │  Model metrics, governance controls, freshness
  └────────────────────────┘

  ┌────────────────────────┐  Legacy Pages (v1):
  │ 01_executive_dashboard │  KPI overview
  ├────────────────────────┤
  │ 02_risk_center         │  Basic risk view
  ├────────────────────────┤
  │ 03_recovery_center     │  Basic recovery view
  ├────────────────────────┤
  │ 05_settings            │  Configuration
  └────────────────────────┘
```

### 9.2 Key Design Patterns

**Dual-mode operation:** The app supports both `live` (connected to Snowflake) and `demo` (synthetic data) modes, controlled by `OTIF_GUARDIAN_MODE` environment variable. Demo mode generates realistic synthetic data locally for development and demonstrations.

**Shared filters:** Plant, risk band, and minimum revenue filters are set once in the sidebar and propagated via `st.session_state` to all pages.

**Field mapping discipline:** The `FIELD_MAP` in `config.py` explicitly documents every mapping between prototype field names and actual database columns, including fields that are unavailable. No silent assumptions.

**Unavailable field handling:** Fields requiring data sources not yet implemented are listed with explanations rather than hidden or fabricated.

### 9.3 Page Descriptions

| Page | Purpose | Key Components |
|------|---------|----------------|
| **Risk Command Center** | Portfolio-level risk triage | KPI cards (scored lines, critical count, revenue at risk), sortable risk table, revenue exposure bar chart by plant |
| **PO Decision Detail** | Single-PO deep dive | Risk banner, breach probability, SHAP reason codes table, recovery options comparison with cost/benefit/ROI, model provenance |
| **Governed Copilot** | Natural language Q&A | Suggested questions (context-aware), agent-backed responses, evidence traces in expandable sections, governance notice |
| **Model & Controls** | Model governance dashboard | ROC-AUC/accuracy/precision/recall/F1 metrics, confusion matrix, feature importance chart, governance controls table, data freshness, object inventory |

---

## 10. Deployment Architecture

### 10.1 Schema Layout

```
  OTIF_GUARDIAN (Database)
  │
  ├── RAW                12 source tables, stages, file formats
  ├── STAGING            Transform workspace (future)
  ├── ANALYTICS          11 ontology views (business-ready)
  ├── SEMANTIC           Semantic view YAML + Cortex Analyst
  ├── ML                 Training data, scored results, feature views,
  │                      model artifacts, stored procedures, recovery engine
  ├── AGENTS             Cortex Agent definition
  ├── STREAMLIT          Streamlit application object
  └── AUDIT              Operational logging (future)
```

### 10.2 RBAC Design

```
  SYSADMIN
    └── OTIF_GUARDIAN_ADMIN       Full project access
          └── OTIF_GUARDIAN_ENGINEER   Build, transform, deploy
                ├── OTIF_GUARDIAN_ANALYST   Read analytics + semantic
                └── OTIF_GUARDIAN_APP       Runtime service account
```

| Role | Schemas Writable | Schemas Readable | Special Privileges |
|------|------------------|------------------|--------------------|
| **ADMIN** | All | All | Manage roles, all DDL |
| **ENGINEER** | RAW, STAGING, ANALYTICS, ML, AUDIT | SEMANTIC, AGENTS, STREAMLIT | Deploy procedures, manage stages |
| **ANALYST** | None | ANALYTICS, SEMANTIC, AGENTS | Query semantic view, use agent |
| **APP** | None | ANALYTICS, ML, SEMANTIC, AGENTS | Execute procedures, serve Streamlit |

### 10.3 Deployed Objects (Live)

| Object Type | Schema | Count | Key Objects |
|-------------|--------|-------|-------------|
| Base Tables | RAW | 12 | SUPPLIERS, MATERIALS, PLANTS, PO_LINES, etc. |
| Base Tables | ML | 9 | TRAIN_DATA_V2, SCORE_DATA_V2, SCORED_PO_LINES, etc. |
| Views | ANALYTICS | 11 | V_SUPPLIER_PROFILE, V_PO_DELIVERY_PERFORMANCE, etc. |
| Views | ML | 17 | V_FEATURE_SET_V2, V_AT_RISK_LINES, V_RECOVERY_RECOMMENDATIONS, etc. |
| Stored Procedures | ML | 7 | SP_TRAIN_IMPROVED_MODEL, SP_EVALUATE_BREACH_MODEL, SP_RUN_RECOVERY_ENGINE, etc. |
| Semantic View | SEMANTIC | 1 | OTIF_GUARDIAN_SUPPLY_CHAIN |
| Agent | AGENTS | 1 | OTIF_GUARDIAN_AGENT |
| Streamlit | STREAMLIT | 1 | OTIF_GUARDIAN_APP |
| Warehouse | — | 1 | OTIF_GUARDIAN_WH (XS, auto-suspend 60s) |
| Resource Monitor | — | 1 | OTIF_GUARDIAN_RM (100 credits/month) |

### 10.4 Deployment Flow

```
  1. Bootstrap (00_bootstrap.sql)
     └── Database, schemas, roles, warehouse, stages, formats, sequences

  2. Generate Data (01_generate_data.sql)
     └── 12 RAW tables with deterministic synthetic data

  3. Ontology Views (02_ontology_views.sql)
     └── 11 analytical views in ANALYTICS schema

  4. Semantic View (03_deploy_semantic_view.sql)
     └── OTIF_GUARDIAN_SUPPLY_CHAIN semantic view from YAML

  5. ML Pipeline (04b_ml_pipeline_improved.sql)
     └── Feature views, training/scoring tables, stored procedures

  6. Training (CALL SP_TRAIN_IMPROVED_MODEL or train_otif_model.py)
     └── XGBoost training → SCORED_PO_LINES

  7. Recovery Engine (05_recovery_engine.sql)
     └── Recovery views, action evaluation, portfolio summary

  8. Agent Deployment (06_deploy_agent.sql)
     └── Cortex Agent with 3 tools + grants

  9. Streamlit Deployment
     └── OTIF_GUARDIAN_APP in STREAMLIT schema
```

---

## 11. Validation Methodology

### 11.1 Model Validation

| Technique | Implementation | Purpose |
|-----------|---------------|---------|
| **Temporal split** | `order_date < 2026-06-01` (train) vs. rest (test) | Prevent future data leakage |
| **Stratified split** | 80/20 preserving ~10% breach rate | Balanced class representation |
| **5-fold cross-validation** | Stratified K-Fold on SMOTE-augmented train | Variance estimation |
| **Holdout evaluation** | 20% held out from SMOTE entirely | Unbiased performance estimate |
| **Calibration** | Isotonic, 3-fold on original (not SMOTE) train | Reliable probability estimates |
| **Threshold optimization** | Sweep 0.05-0.95, maximize F1 on holdout | Operational threshold (0.33) |

### 11.2 Recovery Engine Validation

- All formulas are deterministic SQL with no stochastic component
- Feasibility checks enforce hard constraints (inventory existence, supplier status, route availability)
- Net value protected is always `revenue_protected - incremental_cost` (never presented without cost)
- Portfolio ROI aggregates only recommended (rank=1) actions

### 11.3 Agent Validation

- Agent responses are tested against known-answer questions
- Semantic view queries are validated via Cortex Analyst compilation
- Tool routing is verified against expected intent-to-tool mappings
- Governance compliance: no fabricated numbers, all values from tool results

---

## 12. Monitoring Approach

### 12.1 Model Monitoring

| Signal | Threshold | Check Frequency | Action |
|--------|-----------|-----------------|--------|
| Accuracy drop | Below 0.50 | Monthly | Retrain model |
| Breach rate drift | > 15pp shift from training | Monthly | Retrain with new split |
| Feature distribution shift | Statistical divergence | Quarterly | Investigate, re-engineer |
| Recovery ROI < 1.0x | Portfolio aggregate | Continuous | Review cost assumptions |

### 12.2 Operational Monitoring

| Component | Signal | Method |
|-----------|--------|--------|
| Warehouse | Credit consumption | Resource monitor (100 credits/month, suspend at 100%) |
| Scoring freshness | SCORED_PO_LINES timestamp | `V_MODEL_METRICS` view |
| Recovery engine | `RECOVERY_ENGINE_LOG` rows | Procedure execution logging |
| Data freshness | Source table modification time | Model & Controls page |
| Agent availability | Agent response latency | Streamlit health check |

### 12.3 Data Quality Views

The ML schema includes built-in observability views:

- `V_MODEL_METRICS` — ROC-AUC, accuracy, precision, recall, F1 from latest evaluation
- `V_CONFUSION_MATRIX` — TP/FP/TN/FN counts from holdout set
- `V_FEATURE_IMPORTANCE` — XGBoost feature importance scores with rank
- `V_PREDICTION_DISTRIBUTION` — Distribution of predicted probabilities
- `V_TOP_REASON_CODES` — SHAP-based per-prediction risk explanations

---

## 13. Limitations

### 13.1 Model Limitations

1. **Cold-start suppliers:** New suppliers with no delivery history receive NULL temporal features. XGBoost handles NULLs natively, but predictions are less reliable for suppliers with fewer than 10 prior PO lines.

2. **External disruptions:** The model cannot predict force majeure events (natural disasters, geopolitical disruptions, pandemics) not reflected in historical patterns.

3. **Concept drift:** Supply chain conditions change over time. Model performance degrades without monthly retraining.

4. **Class imbalance:** The ~10% breach rate requires SMOTE and threshold tuning. If production breach rates shift significantly, recalibration is needed.

5. **Test set size:** The temporal holdout contains ~123 rows, which limits statistical confidence in evaluation metrics.

### 13.2 Data Limitations

1. **Synthetic data:** All 12 RAW tables are deterministically generated. Real-world data will have different distributions, missing values, and quality issues.

2. **No real-time feeds:** Data is loaded once via generation scripts, not connected to live ERP/WMS systems.

3. **Missing data sources:** Several prototype fields (confirmed delivery date, projected stockout date, ASN data) require data feeds not yet implemented.

### 13.3 System Limitations

1. **Batch inference only:** Scoring runs as a stored procedure call, not as a real-time trigger on new PO creation.

2. **Single-account deployment:** No cross-account data sharing or multi-region replication.

3. **No model registry versioning:** The model artifact is saved to a stage but not registered in Snowflake Model Registry with version management.

4. **Recovery engine static assumptions:** Cost formulas use fixed rates (e.g., premium freight surcharge) that should be parameterized for different markets.

5. **No automated retraining:** Retraining requires manual procedure invocation. No scheduled task or drift-triggered automation.

---

## 14. Future Roadmap

### 14.1 Near-Term Enhancements

| Enhancement | Impact | Complexity |
|-------------|--------|------------|
| Connect to real ERP data feeds | Real predictions vs. synthetic | High |
| Snowflake Task-based automated retraining | Eliminates manual retraining | Medium |
| Model Registry integration with versioning | Model governance and rollback | Medium |
| Dynamic Tables for incremental feature refresh | Real-time feature freshness | Medium |
| Parameterized cost assumptions in recovery engine | Market-specific recovery costs | Low |

### 14.2 Medium-Term Evolution

| Enhancement | Impact |
|-------------|--------|
| Snowpipe Streaming for real-time PO ingestion | Sub-minute scoring latency |
| SHAP waterfall visualizations in Streamlit | Better explainability UX |
| Cortex Search for unstructured supplier intelligence | Risk signals from news/filings |
| Multi-model ensemble (XGBoost + LightGBM + logistic) | Improved prediction accuracy |
| A/B testing framework for recovery strategies | Empirical recovery effectiveness |

### 14.3 Long-Term Vision

| Enhancement | Impact |
|-------------|--------|
| Cross-account data sharing for supplier collaboration | Multi-party supply chain visibility |
| Reinforcement learning for optimal recovery sequencing | Automated decision optimization |
| Integration with Snowflake Marketplace weather/risk data | External risk signal enrichment |
| Cortex Agent with autonomous recovery execution (with approval workflow) | Reduced human-in-the-loop latency |

---

## 15. Component Interaction Summary

```
  ┌──────────┐    Sidebar      ┌──────────────────────────────────────┐
  │  User    │───filters───────►│  Streamlit App (OTIF_GUARDIAN_APP)  │
  │          │◄──dashboards─────│  4 pages + shared state             │
  └──────────┘                  └──────────┬──────────┬───────────────┘
                                           │          │
                              SQL queries  │          │  Agent queries
                                           │          │
                                           ▼          ▼
                                    ┌──────────┐ ┌──────────┐
                                    │ ML Views │ │ Cortex   │
                                    │ (17)     │ │ Agent    │
                                    └────┬─────┘ └────┬─────┘
                                         │            │
                            ┌────────────┘            │
                            │                ┌────────┴────────────┐
                            │                │                     │
                            │          ┌─────▼─────┐    ┌─────────▼──────┐
                            │          │ Semantic  │    │ Stored         │
                            │          │ View      │    │ Procedures     │
                            │          │ (Cortex   │    │ (recovery,     │
                            │          │  Analyst) │    │  risk lookup)  │
                            │          └─────┬─────┘    └────────┬───────┘
                            │                │                   │
                            └────────────────┼───────────────────┘
                                             │
                                             ▼
                                    ┌────────────────┐
                                    │ RAW Tables (12)│
                                    │ ML Tables (9)  │
                                    │ Views (28)     │
                                    └────────────────┘
                                             │
                                             ▼
                                    ┌────────────────┐
                                    │ OTIF_GUARDIAN_WH│
                                    │ (XS, auto-     │
                                    │  suspend 60s)  │
                                    └────────────────┘
```

---

## Appendix A: Object Reference

### Stored Procedures

| Procedure | Purpose | Input | Output |
|-----------|---------|-------|--------|
| `SP_TRAIN_IMPROVED_MODEL()` | Full V2 training pipeline (SMOTE + HPO + calibration) | None | VARIANT (metrics JSON) |
| `SP_TRAIN_AND_SCORE()` | V1 training + scoring pipeline | None | VARIANT |
| `SP_TRAIN_BREACH_MODEL()` | V1 basic XGBoost training | None | VARIANT |
| `SP_EVALUATE_BREACH_MODEL()` | Holdout + 5-fold CV evaluation | None | VARIANT |
| `SP_RUN_RECOVERY_ENGINE()` | Execute deterministic recovery scoring | None | VARIANT |
| `SP_GET_RECOVERY_FOR_PO_LINE(INT)` | Recovery actions for one PO line | PO_LINE_ID | VARIANT |
| `SP_CALCULATE_OTIF_IMPACT()` | Portfolio OTIF lift calculation | None | VARIANT |

### Key Views

| View | Schema | Purpose |
|------|--------|---------|
| `V_FEATURE_SET_V2` | ML | 38-column feature vector per PO line |
| `V_SUPPLIER_HISTORY_V2` | ML | Multi-window (30/60/90-day) supplier OTIF history |
| `V_AT_RISK_LINES` | ML | Scored PO lines above MEDIUM risk threshold |
| `V_SCORED_RESULTS` | ML | Full scored results with supplier/material context |
| `V_RECOVERY_RECOMMENDATIONS` | ML | All evaluated recovery actions with cost/benefit |
| `V_BEST_RECOVERY_ACTION` | ML | Top-ranked recovery per PO line |
| `V_RECOVERY_PORTFOLIO_SUMMARY` | ML | Portfolio-level aggregation of recovery impact |
| `V_TOP_REASON_CODES` | ML | SHAP-based risk explanation per prediction |
| `V_MODEL_METRICS` | ML | Latest model evaluation metrics |
| `V_CONFUSION_MATRIX` | ML | Test set confusion matrix |
| `V_FEATURE_IMPORTANCE` | ML | Feature importance rankings |

---

*This document describes the system as deployed on October 1, 2026, running on Snowflake account SNNEIIG-OT77826.*
