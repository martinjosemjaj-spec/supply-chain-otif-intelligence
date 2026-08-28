# API Guide

## Cortex Agent API

### Endpoint

The OTIF Guardian Agent is accessible via three methods:

| Method | Access |
|--------|--------|
| CLI | `cortex agents run OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT "<question>"` |
| SQL | `SELECT SNOWFLAKE.CORTEX.AGENT('OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT', '<question>')` |
| REST | `POST /api/v2/cortex/agent:run` |

### Tools Exposed

#### 1. supply_analytics

**Purpose:** Natural-language queries against supply chain data.

**Backed by:** Cortex Analyst text-to-SQL over the OTIF_GUARDIAN_SUPPLY_CHAIN semantic view.

**Example questions:**
- "What is the overall supplier OTIF rate?"
- "Show monthly OTIF trend for the last 12 months"
- "Which suppliers have the worst on-time delivery?"
- "What is our total procurement spend by material category?"

**Returns:** Structured data with column names and values from SQL execution.

#### 2. risk_lookup

**Purpose:** Retrieve ML-predicted breach risk for PO lines.

**Input schema:**

| Parameter | Type | Required | Values |
|-----------|------|----------|--------|
| lookup_type | string | Yes | `po_number`, `supplier`, `material`, `plant`, `top_risks` |
| identifier | string | No | PO number, supplier code, material code, plant code, or limit |
| risk_threshold | string | No | `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `MINIMAL` (default: MEDIUM) |

**Returns:** Array of at-risk PO lines with breach_probability, risk_tier, supplier/material context.

#### 3. recovery_simulation

**Purpose:** Evaluate recovery actions with deterministic cost/benefit.

**Input schema:**

| Parameter | Type | Required | Values |
|-----------|------|----------|--------|
| simulation_type | string | Yes | `single_line`, `supplier`, `plant`, `portfolio` |
| identifier | string | No | PO line ID, supplier code, plant code |
| action_filter | string | No | `EXPEDITE`, `INVENTORY_TRANSFER`, `ALTERNATE_SUPPLIER` |

**Returns:** Ranked list of feasible actions with revenue_protected, incremental_cost, net_value_protected, roi_multiple, success_probability, otif_lift.

---

## Stored Procedures

### SP_RUN_RECOVERY_ENGINE()

**Schema:** `OTIF_GUARDIAN.ML`  
**Returns:** VARIANT (JSON)

Executes the full recovery pipeline: re-scores open PO lines, evaluates all recovery actions, produces portfolio summary, and logs execution.

**Response structure:**
```json
{
  "execution_id": "20260828_143022",
  "status": "SUCCESS",
  "execution_duration_sec": 12.4,
  "steps": [...],
  "portfolio_summary": {
    "at_risk_lines_addressable": 142,
    "total_revenue_protected": 1250000.00,
    "total_incremental_cost": 185000.00,
    "total_net_value_protected": 1065000.00,
    "portfolio_roi_multiple": 5.76,
    "recommended_expedites": 45,
    "recommended_transfers": 38,
    "recommended_alt_suppliers": 59
  },
  "action_breakdown": [...]
}
```

### SP_GET_RECOVERY_FOR_PO_LINE(P_PO_LINE_ID INTEGER)

**Schema:** `OTIF_GUARDIAN.ML`  
**Returns:** VARIANT (JSON)

Returns all feasible recovery actions for a specific PO line, ranked by net value protected.

**Response structure:**
```json
{
  "po_line_id": 12345,
  "context": {
    "breach_probability": 0.82,
    "days_until_due": 5,
    "line_value": 45000.00,
    "downstream_revenue_exposed": 230000.00
  },
  "recommended_action": {
    "rank": 1,
    "action_type": "EXPEDITE",
    "detail": "Air freight from current supplier",
    "success_probability": 0.75,
    "revenue_protected": 172500.00,
    "incremental_cost": 12300.00,
    "net_value_protected": 160200.00,
    "roi_multiple": 13.02
  },
  "actions": [...]
}
```

### SP_CALCULATE_OTIF_IMPACT()

**Schema:** `OTIF_GUARDIAN.ML`  
**Returns:** VARIANT (JSON)

Calculates expected OTIF rate improvement if all top recommendations are executed.

**Response structure:**
```json
{
  "baseline": {
    "total_open_lines": 800,
    "predicted_breaches": 320,
    "predicted_otif_rate_pct": 60.0
  },
  "recovery_potential": {
    "addressable_breaches": 142,
    "fully_recoverable": 95,
    "expected_lines_recovered": 71
  },
  "projected": {
    "post_recovery_otif_rate_pct": 68.9,
    "otif_lift_pct_points": 8.9
  }
}
```

---

## SQL Views (Query Interface)

All views are in `OTIF_GUARDIAN.ML` or `OTIF_GUARDIAN.ANALYTICS` schemas and can be queried directly.

### Key ML Views

| View | Purpose | Key Columns |
|------|---------|-------------|
| `V_SCORED_RESULTS` | All scored PO lines with context | po_line_id, breach_probability, risk_tier, supplier_name, material_code |
| `V_MODEL_METRICS` | Model performance summary | accuracy, precision_breach, recall_breach, f1_breach |
| `V_FEATURE_IMPORTANCE` | Global feature ranking | feature_name, importance_score |
| `V_TOP_REASON_CODES` | Per-line SHAP explanations | po_line_id, feature_name, shap_contribution, direction |
| `V_BEST_RECOVERY_ACTION` | Top-1 action per PO line | po_line_id, action_type, net_value_protected, roi_multiple |
| `V_RECOVERY_PORTFOLIO_SUMMARY` | Aggregate portfolio impact | total_revenue_protected, total_cost, roi |
| `V_RISK_BY_SUPPLIER` | Supplier risk aggregation | supplier_name, high_risk_lines, avg_breach_prob |

### Key Analytics Views

| View | Purpose |
|------|---------|
| `V_PO_DELIVERY_PERFORMANCE` | Core OTIF analysis: is_on_time, is_in_full, is_otif per PO line |
| `V_CUSTOMER_ORDER_OTIF` | Customer fulfillment with revenue_at_risk |
| `V_INVENTORY_POSITION` | Stock health: STOCKOUT/CRITICAL/LOW/ADEQUATE/EXCESS |
| `V_DEMAND_SUPPLY_BALANCE` | Gap analysis with urgency bands |
| `V_SOURCING_MAP` | Material-supplier-lane relationships |

---

## Semantic View (Natural Language)

The semantic view `OTIF_GUARDIAN.SEMANTIC.OTIF_GUARDIAN_SUPPLY_CHAIN` supports natural-language queries via Cortex Analyst.

**Supported question types:**
- Aggregations: "total spend", "average lead time", "count of PO lines"
- Filtering: "for supplier X", "in the last 3 months", "at Detroit plant"
- Comparisons: "by supplier tier", "by material category", "by plant"
- Metrics: 14 pre-defined metrics (OTIF rate, fill rate, stockout count, etc.)
- Trends: "monthly", "weekly", "quarterly"

**Access via SQL:**
```sql
SELECT SNOWFLAKE.CORTEX.ANALYST(
    'What is the OTIF rate by supplier tier?',
    PARSE_JSON('{"semantic_view": "OTIF_GUARDIAN.SEMANTIC.OTIF_GUARDIAN_SUPPLY_CHAIN"}')
);
```
