# OTIF_Guardian - Supply Chain Ontology

**Version:** 1.0  
**Date:** 2026-08-28  
**Domain:** Supply Chain — Procurement, Logistics, Fulfillment

---

## Ontology Overview

This ontology defines the conceptual model for the OTIF Guardian system. It formalizes entities, attributes, relationships, cardinalities, and lifecycle states within the supply chain domain.

---

## Entity Definitions

---

### 1. SUPPLIER

A legal entity that provides materials to plants under contractual terms.

| Attribute | Type | Semantics |
|-----------|------|-----------|
| supplier_id | PK | Internal surrogate |
| supplier_code | BK | Business identifier (SUP-XXXX) |
| supplier_name | | Legal trading name |
| region | ENUM | Geographic region (APAC, EMEA, AMER, LATAM) |
| country_code | ISO-3166 | Country of primary operations |
| supplier_tier | ENUM | Strategic classification (1=Strategic, 2=Preferred, 3=Approved) |
| standard_lead_time_days | Measure | Average fulfillment cycle in calendar days |
| historical_otd_pct | Measure | Historical on-time delivery percentage |
| quality_score | Measure | Composite quality rating (0-100) |
| status | Lifecycle | ACTIVE, PROBATION, INACTIVE, BLOCKED |
| onboarded_date | Temporal | Date supplier was qualified and onboarded |

**Lifecycle:** PROSPECTIVE → ACTIVE → PROBATION → INACTIVE → BLOCKED

**Grain:** One row per supplier entity.

---

### 2. MATERIAL

A stockable item procured from suppliers and consumed in production.

| Attribute | Type | Semantics |
|-----------|------|-----------|
| material_id | PK | Internal surrogate |
| material_code | BK | Business identifier (MAT-XXXXX) |
| material_name | | Descriptive name with specification |
| material_category | ENUM | METALS, POLYMERS, ELECTRONICS, RUBBER, CERAMICS, GLASS |
| unit_of_measure | ENUM | Base UOM (KG, EA, M, L) |
| standard_unit_cost | Measure | Current standard cost per UOM |
| weight_kg | Measure | Unit weight for logistics calculations |
| abc_class | ENUM | Pareto classification (A=high value, B=medium, C=low) |
| criticality | ENUM | Supply risk classification (CRITICAL, IMPORTANT, STANDARD) |
| safety_stock_days | Measure | Target buffer expressed in days of average demand |
| status | Lifecycle | ACTIVE, INACTIVE, OBSOLETE |

**Grain:** One row per material master record.

**Classification Matrix:**

| ABC \ Criticality | CRITICAL | IMPORTANT | STANDARD |
|-------------------|----------|-----------|----------|
| A | Dual-source, safety stock, frequent review | Safety stock, quarterly review | Standard replenishment |
| B | Safety stock, monitor lead time | Periodic review | Min-max |
| C | Monitor only | Reorder point | Kanban |

---

### 3. PLANT

A physical manufacturing or distribution site that receives materials and fulfills customer orders.

| Attribute | Type | Semantics |
|-----------|------|-----------|
| plant_id | PK | Internal surrogate |
| plant_code | BK | Business identifier (PLT-MFG-XX) |
| plant_name | | Descriptive name |
| city | | City of location |
| country_code | ISO-3166 | Country |
| region | ENUM | Geographic region |
| timezone | IANA | Operational timezone |
| capacity_units_per_day | Measure | Theoretical daily throughput |
| status | Lifecycle | ACTIVE, MAINTENANCE, INACTIVE |

**Grain:** One row per physical site.

---

### 4. INVENTORY

A point-in-time snapshot of material stock position at a specific plant.

| Attribute | Type | Semantics |
|-----------|------|-----------|
| inventory_id | PK | Internal surrogate |
| plant_id | FK | Location holding stock |
| material_id | FK | Material being tracked |
| qty_on_hand | Measure | Physical quantity available |
| qty_in_transit | Measure | Quantity shipped but not yet received |
| qty_reserved | Measure | Quantity allocated to demand/orders |
| reorder_point | Measure | Threshold triggering replenishment |
| days_of_supply | Measure | Projected runway at current consumption |
| inventory_value | Measure | On-hand * standard cost (functional currency) |
| snapshot_date | Temporal | Date of position record |

**Grain:** One row per material per plant per snapshot date.

**Derived Positions:**

- **Available = qty_on_hand - qty_reserved**
- **Projected = qty_on_hand + qty_in_transit - qty_reserved**
- **Below Safety = (days_of_supply < safety_stock_days)**

---

### 5. PURCHASE ORDER

A contractual commitment to procure materials from a supplier for delivery to a plant.

| Attribute | Type | Semantics |
|-----------|------|-----------|
| po_id | PK | Internal surrogate |
| po_number | BK | Business identifier (PO-XXXXXXX) |
| supplier_id | FK | Supplying entity |
| plant_id | FK | Receiving location |
| order_date | Temporal | Date PO was issued |
| requested_delivery_date | Temporal | Buyer-requested arrival |
| po_status | Lifecycle | OPEN, CLOSED, CANCELLED |
| po_type | ENUM | STANDARD, BLANKET, EXPEDITE |
| currency | ISO-4217 | Transaction currency |

**Lifecycle:** DRAFT → OPEN → PARTIALLY_RECEIVED → CLOSED | CANCELLED

**Grain:** One row per purchase order header.

**Child Entity: PO LINE**

| Attribute | Type | Semantics |
|-----------|------|-----------|
| po_line_id | PK | Internal surrogate |
| po_id | FK | Parent purchase order |
| line_number | | Sequence within PO |
| material_id | FK | Material being ordered |
| quantity_ordered | Measure | Committed quantity |
| unit_price | Measure | Agreed price per UOM |
| quantity_received | Measure | Cumulative received quantity |
| line_status | Lifecycle | OPEN, IN_TRANSIT, PARTIALLY_RECEIVED, CLOSED, SHORT_CLOSED, CANCELLED |
| promised_delivery_date | Temporal | Supplier-confirmed date |
| actual_delivery_date | Temporal | Actual goods receipt date (NULL if open) |

**Grain:** One row per material line within a purchase order.

---

### 6. SHIPMENT

A physical movement of goods from supplier to plant via a transport carrier.

| Attribute | Type | Semantics |
|-----------|------|-----------|
| shipment_id | PK | Internal surrogate |
| shipment_number | BK | Business identifier (SHP-XXXXXXXX) |
| po_line_id | FK | Purchase order line being fulfilled |
| transport_mode | ENUM | AIR, OCEAN, TRUCK, RAIL |
| carrier_code | | Logistics provider identifier |
| ship_date | Temporal | Date goods left origin |
| estimated_arrival_date | Temporal | Predicted arrival at destination |
| actual_arrival_date | Temporal | Confirmed arrival (NULL if in transit) |
| shipment_status | Lifecycle | BOOKED, IN_TRANSIT, DELIVERED, DAMAGED, LOST |
| quantity_shipped | Measure | Quantity dispatched |

**Grain:** One row per shipment event (a PO line may have multiple shipments).

---

### 7. RECEIPT

A goods receipt event confirming arrival and quality inspection at a plant.

| Attribute | Type | Semantics |
|-----------|------|-----------|
| receipt_id | PK | Internal surrogate |
| receipt_number | BK | Business identifier (RCV-XXXXXXXX) |
| shipment_id | FK | Inbound shipment |
| plant_id | FK | Receiving plant |
| receipt_date | Temporal | Date of physical receipt |
| quantity_received | Measure | Physical count received |
| inspection_result | ENUM | ACCEPTED, CONDITIONAL, REJECTED |
| quantity_accepted | Measure | Quantity passing quality gate |

**Grain:** One row per receipt transaction.

**Quality Gate Rules:**

- ACCEPTED: Full quantity passes to available inventory
- CONDITIONAL: Partial acceptance; remainder quarantined
- REJECTED: Full quantity returned or scrapped; triggers supplier NCR

---

### 8. DEMAND

A requirement signal for material at a plant, representing consumption needs.

| Attribute | Type | Semantics |
|-----------|------|-----------|
| demand_id | PK | Internal surrogate |
| demand_number | BK | Business identifier (DMD-XXXXXXX) |
| material_id | FK | Required material |
| plant_id | FK | Consuming location |
| demand_date | Temporal | Date material is needed |
| quantity_demanded | Measure | Required quantity |
| demand_type | ENUM | FIRM (committed), PLANNED (scheduled), FORECAST (projected) |
| priority | ENUM | HIGH, MEDIUM, LOW |

**Grain:** One row per demand signal.

**Type Hierarchy (certainty descending):** FIRM > PLANNED > FORECAST

---

### 9. CUSTOMER ORDER

A customer's request for finished goods shipped from a plant.

| Attribute | Type | Semantics |
|-----------|------|-----------|
| order_id | PK | Internal surrogate |
| order_number | BK | Business identifier (CO-XXXXXXX) |
| customer_code | FK | Ordering customer |
| customer_name | | Customer legal name |
| plant_id | FK | Fulfilling plant |
| order_date | Temporal | Date order was placed |
| requested_delivery_date | Temporal | Customer-requested delivery |
| actual_ship_date | Temporal | Actual dispatch date (NULL if open) |
| order_value | Measure | Total order monetary value |
| line_count | Measure | Number of line items |
| order_status | Lifecycle | OPEN, PARTIAL, SHIPPED, CANCELLED |
| otif_flag | Boolean | On-Time AND In-Full delivery achieved |

**Grain:** One row per customer order header.

**OTIF Definition:**
- **On-Time:** actual_ship_date <= requested_delivery_date
- **In-Full:** order_status = 'SHIPPED' (not PARTIAL)
- **OTIF:** On-Time AND In-Full

---

## Relationship Model

```
┌─────────────┐         ┌─────────────────┐         ┌─────────────┐
│  SUPPLIER   │ 1───M   │ PURCHASE_ORDER  │ M───1   │    PLANT    │
└─────────────┘         └─────────────────┘         └─────────────┘
       │                        │                          │
       │ M                      │ 1                        │ 1
       │                        │                          │
       ▼                        ▼                          ▼
┌─────────────────┐     ┌─────────────┐            ┌─────────────┐
│ ALT_SUPPLIERS   │     │  PO_LINES   │            │  INVENTORY  │
└─────────────────┘     └─────────────┘            └─────────────┘
       │                        │                          ▲
       │ M                      │ 1                        │ M
       │                        │                          │
       ▼                        ▼                          │
┌─────────────┐         ┌─────────────┐            ┌─────────────┐
│  MATERIAL   │◄────────│  SHIPMENT   │            │   DEMAND    │
└─────────────┘         └─────────────┘            └─────────────┘
                                │
                                │ 1
                                │
                                ▼
                        ┌─────────────┐
                        │   RECEIPT   │────────────► PLANT
                        └─────────────┘

┌─────────────────┐
│ CUSTOMER_ORDER  │ M───1  PLANT
└─────────────────┘

┌─────────────────┐
│ TRANSPORT_LANE  │  (origin_country → SUPPLIER.country, dest_country → PLANT.country)
└─────────────────┘
```

---

## Relationship Definitions

| Relationship | From | To | Cardinality | Description |
|-------------|------|-----|-------------|-------------|
| SUPPLIES | Supplier | Purchase Order | 1:M | A supplier fulfills many POs |
| RECEIVES_AT | Plant | Purchase Order | 1:M | A plant receives many POs |
| CONTAINS | Purchase Order | PO Line | 1:M | A PO has one or more lines |
| ORDERS | PO Line | Material | M:1 | Many lines can order the same material |
| SHIPS | PO Line | Shipment | 1:M | A line may ship in splits |
| ARRIVES | Shipment | Receipt | 1:M | A shipment may be received in parts |
| RECEIVED_AT | Receipt | Plant | M:1 | Receipts occur at a specific plant |
| STOCKED_AT | Material + Plant | Inventory | 1:1 | One inventory position per material-plant |
| DEMANDED_AT | Material + Plant | Demand | 1:M | Multiple demand signals per material-plant |
| FULFILLED_BY | Customer Order | Plant | M:1 | Orders fulfilled from a specific plant |
| SOURCED_FROM | Material | Alternate Supplier | 1:M | Materials have ranked supplier options |
| CONNECTS | Transport Lane | Supplier Country → Plant Country | M:M | Logistics network topology |

---

## Cardinality Summary

| Entity | Min Children | Max Children | Typical |
|--------|-------------|-------------|---------|
| Supplier → POs | 0 | Unbounded | ~100/year |
| PO → Lines | 1 | 20 | 4-5 |
| PO Line → Shipments | 0 | 5 | 1 |
| Shipment → Receipts | 0 | 3 | 1 |
| Material → Alt Suppliers | 1 | 8 | 3-4 |
| Plant → Inventory Records | 0 | 250 | ~170 |
| Material → Demand Signals | 0 | Unbounded | ~60/year |
| Plant → Customer Orders | 0 | Unbounded | ~1500/year |
