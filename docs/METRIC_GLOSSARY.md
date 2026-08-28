# OTIF_Guardian - Metric Glossary

**Version:** 1.0  
**Domain:** Supply Chain — OTIF Performance Management

---

## Metric Classification

| Tier | Purpose | Audience |
|------|---------|----------|
| **L1 - Executive** | Strategic KPIs, board-level | VP Supply Chain, C-suite |
| **L2 - Operational** | Functional performance | Directors, Managers |
| **L3 - Diagnostic** | Root cause, drill-down | Analysts, Planners |

---

## L1 - Executive Metrics

### OTIF Rate (%)

| Property | Value |
|----------|-------|
| **Formula** | `COUNT(orders WHERE otif_flag = TRUE) / COUNT(orders WHERE order_status IN ('SHIPPED','PARTIAL')) * 100` |
| **Grain** | Customer order |
| **Dimensions** | Time (daily/weekly/monthly), Plant, Customer, Region |
| **Target** | >= 95% |
| **Direction** | Higher is better |
| **Source Table** | CUSTOMER_ORDERS |

### Supplier OTD Rate (%)

| Property | Value |
|----------|-------|
| **Formula** | `COUNT(po_lines WHERE actual_delivery_date <= promised_delivery_date) / COUNT(po_lines WHERE actual_delivery_date IS NOT NULL) * 100` |
| **Grain** | PO line (closed) |
| **Dimensions** | Time, Supplier, Material Category, Plant |
| **Target** | >= 92% |
| **Direction** | Higher is better |
| **Source Table** | PO_LINES |

### In-Full Rate (%)

| Property | Value |
|----------|-------|
| **Formula** | `COUNT(po_lines WHERE quantity_received >= quantity_ordered) / COUNT(po_lines WHERE line_status = 'CLOSED') * 100` |
| **Grain** | PO line (closed) |
| **Dimensions** | Time, Supplier, Material, Plant |
| **Target** | >= 97% |
| **Direction** | Higher is better |
| **Source Table** | PO_LINES |

### Customer OTIF Revenue Impact ($)

| Property | Value |
|----------|-------|
| **Formula** | `SUM(order_value WHERE otif_flag = FALSE AND order_status IN ('SHIPPED','PARTIAL'))` |
| **Grain** | Customer order |
| **Dimensions** | Time, Plant, Customer |
| **Target** | Minimize |
| **Direction** | Lower is better |
| **Source Table** | CUSTOMER_ORDERS |

---

## L2 - Operational Metrics

### Average Lead Time (Days)

| Property | Value |
|----------|-------|
| **Formula** | `AVG(DATEDIFF('day', order_date, actual_delivery_date))` |
| **Grain** | PO line (delivered) |
| **Dimensions** | Supplier, Material Category, Transport Mode |
| **Target** | Within standard_lead_time_days +/- 10% |
| **Source Table** | PO_LINES joined to PURCHASE_ORDERS |

### Lead Time Variance (Days)

| Property | Value |
|----------|-------|
| **Formula** | `AVG(DATEDIFF('day', promised_delivery_date, actual_delivery_date))` |
| **Grain** | PO line (delivered) |
| **Dimensions** | Supplier, Material, Plant |
| **Target** | 0 (negative = early, positive = late) |
| **Source Table** | PO_LINES |

### Inventory Days of Supply

| Property | Value |
|----------|-------|
| **Formula** | `qty_on_hand / (trailing_30d_demand / 30)` |
| **Grain** | Material-Plant |
| **Dimensions** | Plant, Material Category, ABC Class |
| **Target** | Safety stock days < DOS < 2x safety stock days |
| **Source Table** | INVENTORY, DEMAND |

### Stockout Count

| Property | Value |
|----------|-------|
| **Formula** | `COUNT(inventory WHERE qty_on_hand = 0 AND demand EXISTS for next 7 days)` |
| **Grain** | Material-Plant-Day |
| **Dimensions** | Plant, Material Category, Criticality |
| **Target** | 0 for A/CRITICAL items |
| **Source Table** | INVENTORY, DEMAND |

### Fill Rate (%)

| Property | Value |
|----------|-------|
| **Formula** | `SUM(MIN(qty_on_hand, quantity_demanded)) / SUM(quantity_demanded) * 100` |
| **Grain** | Material-Plant (period) |
| **Dimensions** | Plant, Material Category, Demand Type |
| **Target** | >= 98% for FIRM demand |
| **Source Table** | INVENTORY, DEMAND |

### Expedite Rate (%)

| Property | Value |
|----------|-------|
| **Formula** | `COUNT(POs WHERE po_type = 'EXPEDITE') / COUNT(POs) * 100` |
| **Grain** | Purchase order (period) |
| **Dimensions** | Time, Supplier, Plant |
| **Target** | < 5% |
| **Direction** | Lower is better |
| **Source Table** | PURCHASE_ORDERS |

### Quality Acceptance Rate (%)

| Property | Value |
|----------|-------|
| **Formula** | `SUM(quantity_accepted) / SUM(quantity_received) * 100` |
| **Grain** | Receipt |
| **Dimensions** | Supplier, Material, Plant, Time |
| **Target** | >= 99% |
| **Source Table** | RECEIPTS |

### Shipment Damage Rate (%)

| Property | Value |
|----------|-------|
| **Formula** | `COUNT(shipments WHERE shipment_status = 'DAMAGED') / COUNT(shipments WHERE shipment_status IN ('DELIVERED','DAMAGED')) * 100` |
| **Grain** | Shipment |
| **Dimensions** | Carrier, Transport Mode, Lane |
| **Target** | < 0.5% |
| **Source Table** | SHIPMENTS |

---

## L3 - Diagnostic Metrics

### Supplier Risk Score

| Property | Value |
|----------|-------|
| **Formula** | `WEIGHTED_AVG(100 - historical_otd_pct, quality_score_inverted, single_source_flag, country_risk)` |
| **Grain** | Supplier |
| **Dimensions** | Region, Tier, Material Category supplied |
| **Target** | < 30 (low risk) |
| **Source Table** | SUPPLIERS, ALTERNATE_SUPPLIERS |

### Demand Volatility (CV%)

| Property | Value |
|----------|-------|
| **Formula** | `STDDEV(quantity_demanded) / AVG(quantity_demanded) * 100` (rolling 90-day) |
| **Grain** | Material-Plant |
| **Dimensions** | Material Category, Demand Type |
| **Target** | Informational (drives safety stock) |
| **Source Table** | DEMAND |

### PO Line Aging (Days)

| Property | Value |
|----------|-------|
| **Formula** | `DATEDIFF('day', promised_delivery_date, CURRENT_DATE)` for open/overdue lines |
| **Grain** | PO line (open) |
| **Dimensions** | Supplier, Plant, Material |
| **Target** | 0 overdue lines |
| **Source Table** | PO_LINES |

### Inventory Excess (Units / $)

| Property | Value |
|----------|-------|
| **Formula** | `MAX(0, qty_on_hand - (avg_daily_demand * max_target_dos))` |
| **Grain** | Material-Plant |
| **Dimensions** | Plant, ABC Class, Material Category |
| **Target** | Minimize |
| **Source Table** | INVENTORY, DEMAND |

### Transport Cost per KG

| Property | Value |
|----------|-------|
| **Formula** | `total_freight_cost / total_weight_shipped` |
| **Grain** | Lane-Mode (period) |
| **Dimensions** | Origin, Destination, Mode, Carrier |
| **Target** | Within lane benchmark |
| **Source Table** | TRANSPORT_LANES, SHIPMENTS |

### Carrier Reliability (%)

| Property | Value |
|----------|-------|
| **Formula** | `COUNT(shipments WHERE actual_arrival <= estimated_arrival) / COUNT(delivered_shipments) * 100` |
| **Grain** | Carrier-Mode (period) |
| **Dimensions** | Carrier, Mode, Lane |
| **Target** | >= 90% |
| **Source Table** | SHIPMENTS |

### Single-Source Exposure Count

| Property | Value |
|----------|-------|
| **Formula** | `COUNT(materials WHERE COUNT(DISTINCT active alternate suppliers) = 1)` |
| **Grain** | Material |
| **Dimensions** | Material Category, Criticality, ABC Class |
| **Target** | 0 for A/CRITICAL materials |
| **Source Table** | ALTERNATE_SUPPLIERS |

### Late PO Lines at Risk

| Property | Value |
|----------|-------|
| **Formula** | `COUNT(po_lines WHERE line_status IN ('OPEN','IN_TRANSIT') AND promised_delivery_date < CURRENT_DATE + 3)` |
| **Grain** | PO line (active) |
| **Dimensions** | Supplier, Plant, Material, Days Overdue |
| **Target** | 0 |
| **Source Table** | PO_LINES |

---

## Metric Relationships

```
                    ┌────────────────────┐
                    │   OTIF Rate (L1)   │
                    └────────┬───────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
     ┌────────────┐  ┌────────────┐  ┌────────────┐
     │  OTD Rate  │  │  In-Full   │  │  Revenue   │
     │    (L2)    │  │  Rate (L2) │  │ Impact (L1)│
     └──────┬─────┘  └──────┬─────┘  └────────────┘
            │                │
     ┌──────┼────┐    ┌─────┼──────┐
     ▼      ▼    ▼    ▼     ▼      ▼
  ┌─────┐┌─────┐┌────┐┌─────┐┌──────┐┌────────┐
  │Lead ││Carr.││Late││Fill ││Stock-││Quality │
  │Time ││Rel. ││POs ││Rate ││ out  ││Accept. │
  │Var. ││ %   ││at  ││ %   ││Count ││Rate %  │
  │(L3) ││(L3) ││Risk││(L2) ││(L2)  ││(L2)    │
  └─────┘└─────┘└────┘└─────┘└──────┘└────────┘
                                         │
                              ┌───────────┼───────┐
                              ▼           ▼       ▼
                        ┌──────────┐┌────────┐┌───────┐
                        │Supplier  ││Demand  ││Single │
                        │Risk Score││Volat.  ││Source │
                        │(L3)      ││(L3)    ││Exp.(L3)│
                        └──────────┘└────────┘└───────┘
```

---

## Aggregation Rules

| Metric | Daily | Weekly | Monthly | Quarterly |
|--------|-------|--------|---------|-----------|
| OTIF Rate | Point | Rolling 7d | Calendar month | Calendar quarter |
| OTD Rate | Point | Rolling 7d | Calendar month | Calendar quarter |
| Days of Supply | Snapshot | Avg of daily | Avg of daily | Avg of daily |
| Fill Rate | Cumulative | Cumulative | Cumulative reset | Cumulative reset |
| Expedite Rate | Count | Count | % of month | % of quarter |
| Stockout Count | Point | MAX of week | SUM distinct days | SUM distinct days |

---

## Alert Thresholds

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| OTIF Rate | < 93% | < 90% | Escalate to VP |
| Supplier OTD | < 88% | < 80% | Supplier review |
| Days of Supply | < safety_stock | < 3 days | Emergency replenishment |
| Quality Accept | < 97% | < 95% | Supplier NCR |
| Expedite Rate | > 8% | > 12% | Planning review |
| Single-Source (A/Crit) | > 0 | > 3 | Source qualification |
