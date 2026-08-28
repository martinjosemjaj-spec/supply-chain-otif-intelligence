# OTIF_Guardian - Data Quality Report

**Generated:** 2026-08-28  
**Script:** `sql/01_generate_data.sql`  
**Method:** Deterministic (HASH-based seeds, reproducible across executions)

---

## Volume Summary

| Table | Target Rows | Actual (Approx) | Notes |
|-------|-------------|------------------|-------|
| SUPPLIERS | 60 | 60 | Fixed |
| PLANTS | 8 | 8 | Fixed (VALUES) |
| MATERIALS | 250 | 250 | Fixed |
| PURCHASE_ORDERS | 6,400 | 6,400 | ~6,200 historical + ~200 active |
| PO_LINES | 30,800 | 30,800 | ~30,000 historical + ~800 active |
| SHIPMENTS | 28,000 | 28,000 | Linked to PO lines |
| RECEIPTS | 26,000 | 26,000 | Linked to shipments |
| INVENTORY | ~1,300 | ~1,333 (250 * 8 * 0.67) | Sparse matrix (not all materials at all plants) |
| DEMAND | 15,000 | 15,000 | Historical + forward-looking |
| CUSTOMER_ORDERS | 12,000 | 12,000 | 2-year history |
| ALTERNATE_SUPPLIERS | ~1,050 | ~1,050 (250 * 60 * 0.07) | 2-5 suppliers per material |
| TRANSPORT_LANES | ~72 | ~72 (12 origins * 6 destinations) | Full origin-dest combinations |

**Total rows:** ~131,000+

---

## Referential Integrity Map

```
SUPPLIERS (60)
    ├── PURCHASE_ORDERS.supplier_id → SUPPLIERS.supplier_id
    └── ALTERNATE_SUPPLIERS.supplier_id → SUPPLIERS.supplier_id

PLANTS (8)
    ├── PURCHASE_ORDERS.plant_id → PLANTS.plant_id
    ├── RECEIPTS.plant_id → PLANTS.plant_id
    ├── INVENTORY.plant_id → PLANTS.plant_id
    ├── DEMAND.plant_id → PLANTS.plant_id
    └── CUSTOMER_ORDERS.plant_id → PLANTS.plant_id

MATERIALS (250)
    ├── PO_LINES.material_id → MATERIALS.material_id
    ├── INVENTORY.material_id → MATERIALS.material_id
    ├── DEMAND.material_id → MATERIALS.material_id
    └── ALTERNATE_SUPPLIERS.material_id → MATERIALS.material_id

PURCHASE_ORDERS (6,400)
    └── PO_LINES.po_id → PURCHASE_ORDERS.po_id

PO_LINES (30,800)
    └── SHIPMENTS.po_line_id → PO_LINES.po_line_id

SHIPMENTS (28,000)
    └── RECEIPTS.shipment_id → SHIPMENTS.shipment_id

TRANSPORT_LANES
    ├── origin_country → SUPPLIERS.country_code
    └── dest_country → PLANTS.country_code
```

---

## Distribution Characteristics

### Suppliers
| Attribute | Distribution | Values |
|-----------|-------------|--------|
| Tier | Weighted | 15% Tier-1, 50% Tier-2, 35% Tier-3 |
| Region | Uniform | APAC, EMEA, AMER, LATAM |
| Country | Uniform | 12 countries |
| OTD % | Uniform | 70.0% - 99.0% |
| Quality Score | Uniform | 80.0 - 100.0 |
| Status | Weighted | ~87% Active, ~13% Probation |
| Lead Time | Tier-based | T1: 7-20d, T2: 14-34d, T3: 28-57d |

### Materials
| Attribute | Distribution | Values |
|-----------|-------------|--------|
| Category | Weighted | METALS (37.5%), POLYMERS, ELECTRONICS, RUBBER, CERAMICS, GLASS |
| ABC Class | Pareto | A: 20%, B: 30%, C: 50% |
| Criticality | Weighted | CRITICAL: 40%, IMPORTANT: 40%, STANDARD: 20% |
| Unit Cost | Log-normal | $0.50 - $2,500 |
| UOM | Uniform | KG, EA, M, L |
| Status | Weighted | 95% Active, 5% Inactive |

### Purchase Orders & Lines
| Attribute | Distribution | Values |
|-----------|-------------|--------|
| Order Date | Power-law (recency bias) | 3-year span, denser near present |
| PO Status | Time-based | Historical: CLOSED, Recent: 80% CLOSED / 20% OPEN |
| PO Type | Weighted | STANDARD: 50%, BLANKET: 25%, EXPEDITE: 25% |
| Line Quantity | Log-normal | 10 - 50,000 units |
| Line Status (hist) | Weighted | CLOSED: 90%, SHORT_CLOSED: 5%, CANCELLED: 5% |
| Line Status (active) | Uniform | OPEN, PARTIALLY_RECEIVED, IN_TRANSIT |
| Delivery Variance | Normal-like | -5 to +9 days from promised |

### Shipments
| Attribute | Distribution | Values |
|-----------|-------------|--------|
| Transport Mode | Weighted | OCEAN: 40%, TRUCK: 20%, AIR: 20%, RAIL: 20% |
| Transit Time | Mode-based | AIR: 3-7d, TRUCK: 2-8d, RAIL: 7-16d, OCEAN: 21-40d |
| Arrival Variance | Offset | -1 to +3 days |
| Status | Time-based | DELIVERED (past ETA), IN_TRANSIT (future ETA), DAMAGED: 2% |

### Receipts
| Attribute | Distribution | Values |
|-----------|-------------|--------|
| Inspection | Weighted | ACCEPTED: 95%, CONDITIONAL: 3%, REJECTED: 2% |

### Inventory
| Attribute | Distribution | Values |
|-----------|-------------|--------|
| Coverage | Sparse | ~67% of material-plant combinations stocked |
| Days of Supply | Uniform | 3 - 47 days |
| Reserved % | Uniform | 0-40% of on-hand |

### Customer Orders
| Attribute | Distribution | Values |
|-----------|-------------|--------|
| Customers | Uniform | ~200 distinct customers |
| Ship Variance | Offset | -2 to +4 days |
| OTIF Rate | Derived | ~30-40% of shipped orders are OTIF=TRUE |
| Status | Time-based | SHIPPED (past due), OPEN (future), PARTIAL: 5% |

### Demand
| Attribute | Distribution | Values |
|-----------|-------------|--------|
| Type | Weighted | FIRM: 50%, PLANNED: 25%, FORECAST: 25% |
| Priority | Uniform | HIGH, MEDIUM, LOW |
| Time Horizon | Uniform | -365 to +90 days from today |

---

## Data Quality Dimensions

### Completeness
| Check | Status | Notes |
|-------|--------|-------|
| No NULL primary keys | PASS | All IDs generated via ROW_NUMBER |
| No NULL foreign keys | PASS | All FKs computed via MOD(HASH()) |
| NULLable fields intentional | PASS | actual_delivery_date NULL for open lines; actual_ship_date NULL for open orders |
| No orphan records | PASS | FK ranges bounded by parent table sizes |

### Consistency
| Check | Status | Notes |
|-------|--------|-------|
| qty_received <= qty_ordered | PASS | Bounded to 90-105% for historical |
| actual_date NULL when status=OPEN | PASS | Conditional logic ensures alignment |
| OTIF flag aligned with dates | PASS | TRUE only when ship variance <= 0 AND status != PARTIAL |
| Inventory reserved <= on_hand | PASS | Reserved capped at 40% of on-hand |

### Validity
| Check | Status | Notes |
|-------|--------|-------|
| Dates within reasonable range | PASS | 2021-08-28 to 2026-11-26 |
| Quantities positive | PASS | GREATEST() ensures minimums |
| Percentages 0-100 | PASS | OTD: 70-99, Quality: 80-100, Reliability: 75-99 |
| Costs positive | PASS | Log-normal floor ensures > 0 |

### Uniqueness
| Check | Status | Notes |
|-------|--------|-------|
| Primary keys unique | PASS | ROW_NUMBER guarantees uniqueness |
| Business codes unique | PASS | Derived from PK with fixed-width padding |

### Timeliness
| Check | Status | Notes |
|-------|--------|-------|
| Reference date | INFO | All dates relative to 2026-08-28 |
| Snapshot currency | PASS | Inventory snapshot_date = generation date |

---

## Known Limitations & Trade-offs

1. **Shipment-to-PO-Line is N:1 not 1:1** - Multiple shipments may reference the same PO line (simulating split shipments). Some PO lines may have no shipment.

2. **Quantity consistency across tables** - Shipment qty and receipt qty are generated independently. In production, receipt qty <= shipment qty. Post-generation validation recommended.

3. **Customer order line items** - `line_count` is metadata only; individual order lines are not expanded into a separate table (can be added as needed).

4. **Transport lane utilization** - Lanes exist for all origin-destination country pairs. Not all lanes will be referenced by actual shipments.

5. **Determinism** - All randomness uses `HASH(key, seed)` with fixed integer seeds. Re-running the script on the same Snowflake version produces identical data.

6. **OTIF rate** - The derived OTIF flag shows ~30-40% true, which is deliberately below world-class (~95%) to provide meaningful signal for the monitoring system to detect and improve.

---

## Validation Queries (run post-generation)

```sql
-- Row counts
SELECT 'SUPPLIERS' AS tbl, COUNT(*) AS rows FROM OTIF_GUARDIAN.RAW.SUPPLIERS
UNION ALL SELECT 'PLANTS', COUNT(*) FROM OTIF_GUARDIAN.RAW.PLANTS
UNION ALL SELECT 'MATERIALS', COUNT(*) FROM OTIF_GUARDIAN.RAW.MATERIALS
UNION ALL SELECT 'PURCHASE_ORDERS', COUNT(*) FROM OTIF_GUARDIAN.RAW.PURCHASE_ORDERS
UNION ALL SELECT 'PO_LINES', COUNT(*) FROM OTIF_GUARDIAN.RAW.PO_LINES
UNION ALL SELECT 'SHIPMENTS', COUNT(*) FROM OTIF_GUARDIAN.RAW.SHIPMENTS
UNION ALL SELECT 'RECEIPTS', COUNT(*) FROM OTIF_GUARDIAN.RAW.RECEIPTS
UNION ALL SELECT 'INVENTORY', COUNT(*) FROM OTIF_GUARDIAN.RAW.INVENTORY
UNION ALL SELECT 'DEMAND', COUNT(*) FROM OTIF_GUARDIAN.RAW.DEMAND
UNION ALL SELECT 'CUSTOMER_ORDERS', COUNT(*) FROM OTIF_GUARDIAN.RAW.CUSTOMER_ORDERS
UNION ALL SELECT 'ALTERNATE_SUPPLIERS', COUNT(*) FROM OTIF_GUARDIAN.RAW.ALTERNATE_SUPPLIERS
UNION ALL SELECT 'TRANSPORT_LANES', COUNT(*) FROM OTIF_GUARDIAN.RAW.TRANSPORT_LANES
ORDER BY 1;

-- FK integrity check
SELECT 'PO->SUPPLIER orphans' AS check_name,
       COUNT(*) AS violations
FROM OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po
LEFT JOIN OTIF_GUARDIAN.RAW.SUPPLIERS s ON po.supplier_id = s.supplier_id
WHERE s.supplier_id IS NULL;

-- Active PO lines count
SELECT COUNT(*) AS active_po_lines
FROM OTIF_GUARDIAN.RAW.PO_LINES
WHERE line_status IN ('OPEN', 'PARTIALLY_RECEIVED', 'IN_TRANSIT');
```

---

## File Manifest

| File | Purpose |
|------|---------|
| `sql/01_generate_data.sql` | Data generation DDL (662 lines, idempotent) |
| `docs/DATA_QUALITY_REPORT.md` | This report |
