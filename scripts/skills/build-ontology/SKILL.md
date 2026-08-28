---
name: build-ontology
description: "Build or rebuild the OTIF Guardian supply chain ontology. Creates entity definitions, relationship views, business glossary alignment, and metric calculations in Snowflake. Use when: creating ontology from scratch, adding new entities, rebuilding after schema changes, validating ontology consistency. Triggers: build ontology, create ontology, rebuild ontology, add entity, ontology refresh, create views, update ontology."
---

# Build Ontology

## Purpose

Construct or rebuild the OTIF Guardian supply chain ontology layer in Snowflake. This creates:
- Analytical views that materialize entity relationships
- Enriched entity profiles (supplier, material, plant)
- Performance calculation views (OTIF, delivery variance, inventory health)
- Demand-supply netting views

The ontology layer sits between raw data and the semantic model, providing clean, joined, business-enriched views.

## Inputs

| Input | Required | Description |
|-------|----------|-------------|
| Database | Yes | Target database (default: `OTIF_GUARDIAN`) |
| Schema | Yes | Target schema for views (default: `ANALYTICS`) |
| Source schema | Yes | Where raw tables live (default: `RAW`) |
| Entity list | No | Specific entities to rebuild (default: all) |
| Warehouse | Yes | Compute warehouse (default: `OTIF_GUARDIAN_WH`) |

## Outputs

| Output | Location | Description |
|--------|----------|-------------|
| 11 analytical views | `OTIF_GUARDIAN.ANALYTICS` | V_SUPPLIER_PROFILE, V_MATERIAL_PROFILE, V_PLANT_PROFILE, V_INVENTORY_POSITION, V_PO_DELIVERY_PERFORMANCE, V_SHIPMENT_TRACKING, V_RECEIPT_QUALITY, V_DEMAND_SUPPLY_BALANCE, V_CUSTOMER_ORDER_OTIF, V_SOURCING_MAP, V_TRANSPORT_NETWORK |
| Validation results | Console | Row counts, FK integrity, NULL checks |

## Execution Steps

### Step 1: Verify Prerequisites

```sql
-- Confirm database and schemas exist
SHOW DATABASES LIKE 'OTIF_GUARDIAN';
SHOW SCHEMAS IN DATABASE OTIF_GUARDIAN;

-- Confirm raw tables are populated
SELECT 'SUPPLIERS' AS tbl, COUNT(*) AS rows FROM OTIF_GUARDIAN.RAW.SUPPLIERS
UNION ALL SELECT 'PLANTS', COUNT(*) FROM OTIF_GUARDIAN.RAW.PLANTS
UNION ALL SELECT 'MATERIALS', COUNT(*) FROM OTIF_GUARDIAN.RAW.MATERIALS
UNION ALL SELECT 'PURCHASE_ORDERS', COUNT(*) FROM OTIF_GUARDIAN.RAW.PURCHASE_ORDERS
UNION ALL SELECT 'PO_LINES', COUNT(*) FROM OTIF_GUARDIAN.RAW.PO_LINES;
```

If any table has 0 rows, STOP and inform the user to run data generation first (`sql/01_generate_data.sql`).

### Step 2: Set Context

```sql
USE DATABASE OTIF_GUARDIAN;
USE SCHEMA ANALYTICS;
USE WAREHOUSE OTIF_GUARDIAN_WH;
```

### Step 3: Execute Ontology Views

Execute `sql/02_ontology_views.sql` from the project. This creates all 11 views as `CREATE OR REPLACE VIEW` statements (idempotent).

### Step 4: Validate

Run validation queries:

```sql
-- Confirm all views exist
SHOW VIEWS IN SCHEMA OTIF_GUARDIAN.ANALYTICS;

-- Check row counts (should be > 0 for all)
SELECT 'V_SUPPLIER_PROFILE' AS view_name, COUNT(*) AS rows FROM OTIF_GUARDIAN.ANALYTICS.V_SUPPLIER_PROFILE
UNION ALL SELECT 'V_MATERIAL_PROFILE', COUNT(*) FROM OTIF_GUARDIAN.ANALYTICS.V_MATERIAL_PROFILE
UNION ALL SELECT 'V_PLANT_PROFILE', COUNT(*) FROM OTIF_GUARDIAN.ANALYTICS.V_PLANT_PROFILE
UNION ALL SELECT 'V_INVENTORY_POSITION', COUNT(*) FROM OTIF_GUARDIAN.ANALYTICS.V_INVENTORY_POSITION
UNION ALL SELECT 'V_PO_DELIVERY_PERFORMANCE', COUNT(*) FROM OTIF_GUARDIAN.ANALYTICS.V_PO_DELIVERY_PERFORMANCE
UNION ALL SELECT 'V_CUSTOMER_ORDER_OTIF', COUNT(*) FROM OTIF_GUARDIAN.ANALYTICS.V_CUSTOMER_ORDER_OTIF;

-- Check for NULL primary keys (should return 0 for all)
SELECT 'SUPPLIER_NULL_ID' AS check_name, COUNT_IF(supplier_id IS NULL) AS violations
FROM OTIF_GUARDIAN.ANALYTICS.V_SUPPLIER_PROFILE;
```

### Step 5: Report

Present results as:
```
Ontology Build Complete
─────────────────────────
Views created: 11
All validations: PASS / FAIL
Total rows materialized: [sum]
Duration: [seconds]
```

## Validation

| Check | Query | Expected |
|-------|-------|----------|
| All 11 views exist | `SHOW VIEWS IN SCHEMA ANALYTICS` | 11 rows |
| No empty views | Count per view | All > 0 |
| FK integrity: PO→Supplier | LEFT JOIN where supplier IS NULL | 0 violations |
| FK integrity: PO_LINE→Material | LEFT JOIN where material IS NULL | 0 violations |
| OTIF flags computed | COUNT_IF(is_otif IS NOT NULL) | > 0 |
| Inventory health populated | COUNT_IF(inventory_health IS NOT NULL) | > 0 |

## Rollback

```sql
-- Drop all ontology views (safe — views have no data)
DROP VIEW IF EXISTS OTIF_GUARDIAN.ANALYTICS.V_SUPPLIER_PROFILE;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ANALYTICS.V_MATERIAL_PROFILE;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ANALYTICS.V_PLANT_PROFILE;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ANALYTICS.V_INVENTORY_POSITION;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ANALYTICS.V_PO_DELIVERY_PERFORMANCE;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ANALYTICS.V_SHIPMENT_TRACKING;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ANALYTICS.V_RECEIPT_QUALITY;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ANALYTICS.V_DEMAND_SUPPLY_BALANCE;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ANALYTICS.V_CUSTOMER_ORDER_OTIF;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ANALYTICS.V_SOURCING_MAP;
DROP VIEW IF EXISTS OTIF_GUARDIAN.ANALYTICS.V_TRANSPORT_NETWORK;
```

No data is lost — views are computed from RAW tables.

## Examples

### Example 1: Full ontology build from scratch

```
User: $build-ontology
Agent: [Runs Steps 1-5, creates all 11 views, reports success]
```

### Example 2: Rebuild after adding a new raw table

```
User: I added a new CARRIER_PERFORMANCE table to RAW. Rebuild the ontology.
Agent: [Runs Steps 1-5. Notes: existing views recreated. User should add
        a new view for the CARRIER_PERFORMANCE entity if needed.]
```

### Example 3: Selective rebuild

```
User: Just rebuild the supplier and material views.
Agent: [Runs only CREATE OR REPLACE for V_SUPPLIER_PROFILE and V_MATERIAL_PROFILE,
        then validates those two views only.]
```
