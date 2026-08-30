-- ============================================================
-- OTIF_Guardian: Ontology Views
-- Materialized ontology relationships and enriched entities
-- Schema: OTIF_GUARDIAN.ANALYTICS
-- Generated: 2026-08-28
-- ============================================================

USE DATABASE OTIF_GUARDIAN;
USE SCHEMA ANALYTICS;

-- ============================================================
-- 1. SUPPLIER PROFILE (enriched entity view)
-- ============================================================

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ANALYTICS.V_SUPPLIER_PROFILE AS
SELECT
    s.supplier_id,
    s.supplier_code,
    s.supplier_name,
    s.region,
    s.country_code,
    s.supplier_tier,
    s.standard_lead_time_days,
    s.historical_otd_pct,
    s.quality_score,
    s.status,
    s.onboarded_date,
    DATEDIFF('day', s.onboarded_date, CURRENT_DATE()) AS tenure_days,
    -- Aggregated relationships
    po_stats.total_pos,
    po_stats.total_po_value,
    po_stats.open_pos,
    mat_stats.materials_supplied,
    alt_stats.materials_as_primary,
    alt_stats.materials_as_alternate,
    -- Risk indicators
    -- NULL or unrecognized status is treated as UNKNOWN risk (defensive).
    -- PROBATION is always HIGH regardless of OTD metrics.
    CASE
        WHEN s.status IS NULL THEN 'UNKNOWN'
        WHEN s.status = 'PROBATION' THEN 'HIGH'
        WHEN s.historical_otd_pct < 80 THEN 'HIGH'
        WHEN s.historical_otd_pct < 88 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS risk_level
FROM OTIF_GUARDIAN.RAW.SUPPLIERS s
LEFT JOIN (
    -- All POs regardless of status (total_pos is a lifetime count)
    SELECT
        supplier_id,
        COUNT(*) AS total_pos,
        SUM(CASE WHEN po_status = 'OPEN' THEN 1 ELSE 0 END) AS open_pos,
        NULL AS total_po_value
    FROM OTIF_GUARDIAN.RAW.PURCHASE_ORDERS
    GROUP BY supplier_id
) po_stats ON s.supplier_id = po_stats.supplier_id
LEFT JOIN (
    -- All PO lines regardless of status (materials_supplied is a lifetime count)
    SELECT
        po.supplier_id,
        COUNT(DISTINCT pl.material_id) AS materials_supplied
    FROM OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po
    JOIN OTIF_GUARDIAN.RAW.PO_LINES pl ON po.po_id = pl.po_id
    GROUP BY po.supplier_id
) mat_stats ON s.supplier_id = mat_stats.supplier_id
LEFT JOIN (
    -- Only ACTIVE sourcing records (inactive/deprecated assignments are excluded
    -- because they don't represent current sourcing capability)
    SELECT
        supplier_id,
        COUNT(CASE WHEN source_type = 'PRIMARY' THEN 1 END) AS materials_as_primary,
        COUNT(CASE WHEN source_type = 'ALTERNATE' THEN 1 END) AS materials_as_alternate
    FROM OTIF_GUARDIAN.RAW.ALTERNATE_SUPPLIERS
    WHERE status = 'ACTIVE'
    GROUP BY supplier_id
) alt_stats ON s.supplier_id = alt_stats.supplier_id;

-- ============================================================
-- 2. MATERIAL PROFILE (enriched entity view)
-- ============================================================

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ANALYTICS.V_MATERIAL_PROFILE AS
SELECT
    m.material_id,
    m.material_code,
    m.material_name,
    m.material_category,
    m.unit_of_measure,
    m.standard_unit_cost,
    m.weight_kg,
    m.abc_class,
    m.criticality,
    m.safety_stock_days,
    m.status,
    -- Sourcing
    src.active_supplier_count,
    src.primary_supplier_id,
    CASE WHEN src.active_supplier_count = 1 THEN TRUE ELSE FALSE END AS is_single_sourced,
    -- Inventory
    inv.total_on_hand,
    inv.total_in_transit,
    inv.plants_stocked,
    -- Risk classification
    CASE
        WHEN m.abc_class = 'A' AND m.criticality = 'CRITICAL' AND src.active_supplier_count = 1 THEN 'CRITICAL_RISK'
        WHEN m.abc_class = 'A' AND src.active_supplier_count = 1 THEN 'HIGH_RISK'
        WHEN m.criticality = 'CRITICAL' AND src.active_supplier_count = 1 THEN 'HIGH_RISK'
        WHEN m.abc_class = 'A' THEN 'MEDIUM_RISK'
        ELSE 'LOW_RISK'
    END AS supply_risk_class
FROM OTIF_GUARDIAN.RAW.MATERIALS m
LEFT JOIN (
    SELECT
        material_id,
        COUNT(*) FILTER (WHERE status = 'ACTIVE') AS active_supplier_count,
        MIN(CASE WHEN preference_rank = 1 AND status = 'ACTIVE' THEN supplier_id END) AS primary_supplier_id
    FROM OTIF_GUARDIAN.RAW.ALTERNATE_SUPPLIERS
    GROUP BY material_id
) src ON m.material_id = src.material_id
LEFT JOIN (
    SELECT
        material_id,
        SUM(qty_on_hand) AS total_on_hand,
        SUM(qty_in_transit) AS total_in_transit,
        COUNT(DISTINCT plant_id) AS plants_stocked
    FROM OTIF_GUARDIAN.RAW.INVENTORY
    GROUP BY material_id
) inv ON m.material_id = inv.material_id;

-- ============================================================
-- 3. PLANT PROFILE (enriched entity view)
-- ============================================================

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ANALYTICS.V_PLANT_PROFILE AS
SELECT
    p.plant_id,
    p.plant_code,
    p.plant_name,
    p.city,
    p.country_code,
    p.region,
    p.timezone,
    p.capacity_units_per_day,
    p.status,
    -- Inventory position
    inv.distinct_materials,
    inv.total_inventory_value,
    -- Order volume
    co_stats.total_customer_orders,
    co_stats.open_customer_orders,
    -- Inbound supply
    po_stats.open_po_lines,
    po_stats.overdue_po_lines
FROM OTIF_GUARDIAN.RAW.PLANTS p
LEFT JOIN (
    SELECT
        plant_id,
        COUNT(DISTINCT material_id) AS distinct_materials,
        SUM(inventory_value) AS total_inventory_value
    FROM OTIF_GUARDIAN.RAW.INVENTORY
    GROUP BY plant_id
) inv ON p.plant_id = inv.plant_id
LEFT JOIN (
    SELECT
        plant_id,
        COUNT(*) AS total_customer_orders,
        COUNT(*) FILTER (WHERE order_status = 'OPEN') AS open_customer_orders
    FROM OTIF_GUARDIAN.RAW.CUSTOMER_ORDERS
    GROUP BY plant_id
) co_stats ON p.plant_id = co_stats.plant_id
LEFT JOIN (
    SELECT
        po.plant_id,
        COUNT(*) FILTER (WHERE pl.line_status IN ('OPEN','IN_TRANSIT','PARTIALLY_RECEIVED')) AS open_po_lines,
        COUNT(*) FILTER (WHERE pl.line_status IN ('OPEN','IN_TRANSIT','PARTIALLY_RECEIVED')
                         AND pl.promised_delivery_date < CURRENT_DATE()) AS overdue_po_lines
    FROM OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po
    JOIN OTIF_GUARDIAN.RAW.PO_LINES pl ON po.po_id = pl.po_id
    GROUP BY po.plant_id
) po_stats ON p.plant_id = po_stats.plant_id;

-- ============================================================
-- 4. INVENTORY POSITION (enriched with demand context)
-- ============================================================

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ANALYTICS.V_INVENTORY_POSITION AS
SELECT
    i.inventory_id,
    i.plant_id,
    p.plant_code,
    p.plant_name,
    i.material_id,
    m.material_code,
    m.material_name,
    m.material_category,
    m.abc_class,
    m.criticality,
    i.qty_on_hand,
    i.qty_in_transit,
    i.qty_reserved,
    i.qty_on_hand - i.qty_reserved AS qty_available,
    i.qty_on_hand + i.qty_in_transit - i.qty_reserved AS qty_projected,
    i.reorder_point,
    i.days_of_supply,
    m.safety_stock_days,
    i.inventory_value,
    i.snapshot_date,
    -- Health indicators
    CASE
        WHEN i.qty_on_hand = 0 THEN 'STOCKOUT'
        WHEN i.days_of_supply < m.safety_stock_days THEN 'BELOW_SAFETY'
        WHEN i.days_of_supply < m.safety_stock_days * 2 THEN 'ADEQUATE'
        ELSE 'EXCESS'
    END AS inventory_health,
    CASE
        WHEN i.qty_on_hand <= i.reorder_point THEN TRUE
        ELSE FALSE
    END AS below_reorder_point
FROM OTIF_GUARDIAN.RAW.INVENTORY i
JOIN OTIF_GUARDIAN.RAW.MATERIALS m ON i.material_id = m.material_id
JOIN OTIF_GUARDIAN.RAW.PLANTS p ON i.plant_id = p.plant_id;

-- ============================================================
-- 5. PO LINE DELIVERY PERFORMANCE (core OTIF analysis entity)
-- ============================================================

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ANALYTICS.V_PO_DELIVERY_PERFORMANCE AS
SELECT
    pl.po_line_id,
    pl.po_id,
    po.po_number,
    po.supplier_id,
    s.supplier_code,
    s.supplier_name,
    s.supplier_tier,
    po.plant_id,
    p.plant_code,
    pl.material_id,
    m.material_code,
    m.material_category,
    m.abc_class,
    po.order_date,
    po.po_type,
    pl.quantity_ordered,
    pl.quantity_received,
    pl.unit_price,
    pl.quantity_ordered * pl.unit_price AS line_value,
    pl.promised_delivery_date,
    pl.actual_delivery_date,
    pl.line_status,
    -- Delivery metrics
    CASE
        WHEN pl.actual_delivery_date IS NOT NULL
        THEN DATEDIFF('day', po.order_date, pl.actual_delivery_date)
    END AS actual_lead_time_days,
    CASE
        WHEN pl.actual_delivery_date IS NOT NULL
        THEN DATEDIFF('day', pl.promised_delivery_date, pl.actual_delivery_date)
    END AS delivery_variance_days,
    -- OTIF flags
    -- is_on_time: only evaluated for CLOSED/SHORT_CLOSED lines with delivery data
    CASE
        WHEN pl.line_status IN ('CLOSED', 'SHORT_CLOSED')
             AND pl.actual_delivery_date IS NOT NULL
             AND pl.actual_delivery_date <= pl.promised_delivery_date
        THEN TRUE
        WHEN pl.line_status IN ('CLOSED', 'SHORT_CLOSED')
             AND pl.actual_delivery_date IS NOT NULL
        THEN FALSE
        ELSE NULL
    END AS is_on_time,
    CASE
        WHEN pl.line_status = 'CLOSED'
             AND pl.quantity_received >= pl.quantity_ordered
        THEN TRUE
        WHEN pl.line_status IN ('CLOSED', 'SHORT_CLOSED')
        THEN FALSE
        ELSE NULL
    END AS is_in_full,
    -- is_otif: only CLOSED and SHORT_CLOSED lines are evaluated.
    -- CANCELLED lines are always excluded (NULL) even if they have delivery
    -- data, because a cancellation means the line was never actually fulfilled.
    -- OPEN, IN_TRANSIT, and PARTIALLY_RECEIVED are also excluded (not yet complete).
    CASE
        WHEN pl.line_status IN ('CLOSED', 'SHORT_CLOSED')
             AND pl.actual_delivery_date IS NOT NULL
             AND pl.actual_delivery_date <= pl.promised_delivery_date
             AND pl.quantity_received >= pl.quantity_ordered
        THEN TRUE
        WHEN pl.line_status IN ('CLOSED', 'SHORT_CLOSED')
             AND pl.actual_delivery_date IS NOT NULL
        THEN FALSE
        ELSE NULL
    END AS is_otif,
    -- Aging (for open lines)
    CASE
        WHEN pl.line_status IN ('OPEN', 'IN_TRANSIT', 'PARTIALLY_RECEIVED')
             AND pl.promised_delivery_date < CURRENT_DATE()
        THEN DATEDIFF('day', pl.promised_delivery_date, CURRENT_DATE())
        ELSE 0
    END AS days_overdue
FROM OTIF_GUARDIAN.RAW.PO_LINES pl
JOIN OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po ON pl.po_id = po.po_id
JOIN OTIF_GUARDIAN.RAW.SUPPLIERS s ON po.supplier_id = s.supplier_id
JOIN OTIF_GUARDIAN.RAW.PLANTS p ON po.plant_id = p.plant_id
JOIN OTIF_GUARDIAN.RAW.MATERIALS m ON pl.material_id = m.material_id;

-- ============================================================
-- 6. SHIPMENT TRACKING (logistics visibility)
-- ============================================================

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ANALYTICS.V_SHIPMENT_TRACKING AS
SELECT
    sh.shipment_id,
    sh.shipment_number,
    sh.po_line_id,
    pl.po_id,
    po.po_number,
    po.supplier_id,
    s.supplier_name,
    po.plant_id,
    p.plant_name,
    sh.transport_mode,
    sh.carrier_code,
    sh.ship_date,
    sh.estimated_arrival_date,
    sh.actual_arrival_date,
    sh.shipment_status,
    sh.quantity_shipped,
    -- Transit metrics
    DATEDIFF('day', sh.ship_date, COALESCE(sh.actual_arrival_date, CURRENT_DATE())) AS days_in_transit,
    CASE
        WHEN sh.actual_arrival_date IS NOT NULL
        THEN DATEDIFF('day', sh.estimated_arrival_date, sh.actual_arrival_date)
    END AS arrival_variance_days,
    CASE
        WHEN sh.shipment_status = 'IN_TRANSIT'
             AND sh.estimated_arrival_date < CURRENT_DATE()
        THEN TRUE
        ELSE FALSE
    END AS is_overdue,
    -- arrived_on_time: only evaluated for DELIVERED shipments.
    -- DAMAGED shipments are excluded (NULL) because a damaged delivery is not
    -- a successful on-time arrival regardless of timing. IN_TRANSIT shipments
    -- are excluded because they haven't arrived yet.
    CASE
        WHEN sh.shipment_status = 'DELIVERED'
             AND sh.actual_arrival_date IS NOT NULL
             AND sh.actual_arrival_date <= sh.estimated_arrival_date
        THEN TRUE
        WHEN sh.shipment_status = 'DELIVERED'
             AND sh.actual_arrival_date IS NOT NULL
        THEN FALSE
        ELSE NULL
    END AS arrived_on_time
FROM OTIF_GUARDIAN.RAW.SHIPMENTS sh
JOIN OTIF_GUARDIAN.RAW.PO_LINES pl ON sh.po_line_id = pl.po_line_id
JOIN OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po ON pl.po_id = po.po_id
JOIN OTIF_GUARDIAN.RAW.SUPPLIERS s ON po.supplier_id = s.supplier_id
JOIN OTIF_GUARDIAN.RAW.PLANTS p ON po.plant_id = p.plant_id;

-- ============================================================
-- 7. RECEIPT QUALITY (goods receipt + inspection)
-- ============================================================

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ANALYTICS.V_RECEIPT_QUALITY AS
SELECT
    r.receipt_id,
    r.receipt_number,
    r.shipment_id,
    sh.shipment_number,
    sh.po_line_id,
    r.plant_id,
    p.plant_name,
    r.receipt_date,
    r.quantity_received,
    r.inspection_result,
    r.quantity_accepted,
    r.quantity_received - r.quantity_accepted AS quantity_rejected,
    CASE
        WHEN r.quantity_received > 0
        THEN ROUND(r.quantity_accepted / r.quantity_received * 100, 2)
        ELSE NULL
    END AS acceptance_rate_pct,
    -- Supplier context (via shipment → PO)
    po.supplier_id,
    s.supplier_name,
    s.supplier_tier,
    pl.material_id,
    m.material_code,
    m.material_category
FROM OTIF_GUARDIAN.RAW.RECEIPTS r
JOIN OTIF_GUARDIAN.RAW.PLANTS p ON r.plant_id = p.plant_id
JOIN OTIF_GUARDIAN.RAW.SHIPMENTS sh ON r.shipment_id = sh.shipment_id
JOIN OTIF_GUARDIAN.RAW.PO_LINES pl ON sh.po_line_id = pl.po_line_id
JOIN OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po ON pl.po_id = po.po_id
JOIN OTIF_GUARDIAN.RAW.SUPPLIERS s ON po.supplier_id = s.supplier_id
JOIN OTIF_GUARDIAN.RAW.MATERIALS m ON pl.material_id = m.material_id;

-- ============================================================
-- 8. DEMAND SUPPLY BALANCE (material-plant supply/demand netting)
-- ============================================================

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ANALYTICS.V_DEMAND_SUPPLY_BALANCE AS
SELECT
    d.demand_id,
    d.demand_number,
    d.material_id,
    m.material_code,
    m.material_name,
    m.material_category,
    m.abc_class,
    m.criticality,
    d.plant_id,
    p.plant_code,
    d.demand_date,
    d.quantity_demanded,
    d.demand_type,
    d.priority,
    -- Current supply position
    i.qty_on_hand,
    i.qty_in_transit,
    i.qty_on_hand - i.qty_reserved AS qty_available,
    -- Coverage
    CASE
        WHEN i.qty_on_hand - i.qty_reserved >= d.quantity_demanded THEN 'COVERED'
        WHEN i.qty_on_hand + i.qty_in_transit - i.qty_reserved >= d.quantity_demanded THEN 'COVERED_WITH_TRANSIT'
        ELSE 'GAP'
    END AS coverage_status,
    GREATEST(0, d.quantity_demanded - COALESCE(i.qty_on_hand - i.qty_reserved, 0)) AS shortage_qty,
    -- Urgency
    DATEDIFF('day', CURRENT_DATE(), d.demand_date) AS days_until_need,
    CASE
        WHEN d.demand_date < CURRENT_DATE() THEN 'PAST_DUE'
        WHEN d.demand_date <= DATEADD('day', 3, CURRENT_DATE()) THEN 'URGENT'
        WHEN d.demand_date <= DATEADD('day', 7, CURRENT_DATE()) THEN 'NEAR_TERM'
        WHEN d.demand_date <= DATEADD('day', 30, CURRENT_DATE()) THEN 'PLANNING'
        ELSE 'HORIZON'
    END AS urgency_band
FROM OTIF_GUARDIAN.RAW.DEMAND d
JOIN OTIF_GUARDIAN.RAW.MATERIALS m ON d.material_id = m.material_id
JOIN OTIF_GUARDIAN.RAW.PLANTS p ON d.plant_id = p.plant_id
LEFT JOIN OTIF_GUARDIAN.RAW.INVENTORY i
    ON d.material_id = i.material_id AND d.plant_id = i.plant_id;

-- ============================================================
-- 9. CUSTOMER ORDER OTIF (outbound fulfillment performance)
-- ============================================================

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ANALYTICS.V_CUSTOMER_ORDER_OTIF AS
SELECT
    co.order_id,
    co.order_number,
    co.customer_code,
    co.customer_name,
    co.plant_id,
    p.plant_code,
    p.plant_name,
    p.region AS plant_region,
    co.order_date,
    co.requested_delivery_date,
    co.actual_ship_date,
    co.order_value,
    co.line_count,
    co.order_status,
    co.otif_flag,
    -- Derived timing
    CASE
        WHEN co.actual_ship_date IS NOT NULL
        THEN DATEDIFF('day', co.order_date, co.actual_ship_date)
    END AS order_to_ship_days,
    CASE
        WHEN co.actual_ship_date IS NOT NULL
        THEN DATEDIFF('day', co.requested_delivery_date, co.actual_ship_date)
    END AS ship_variance_days,
    CASE
        WHEN co.actual_ship_date IS NOT NULL
             AND co.actual_ship_date <= co.requested_delivery_date
        THEN TRUE
        WHEN co.actual_ship_date IS NOT NULL
        THEN FALSE
        ELSE NULL
    END AS is_on_time,
    -- is_in_full: proxy, not a true in-full check. CUSTOMER_ORDERS lacks line-level
    -- quantity_shipped vs quantity_ordered data, so order_status = 'SHIPPED' is used
    -- as a stand-in for "in full" and 'PARTIAL' for "not in full." This is a known
    -- limitation of the current data model, not a verified quantity match. If line-level
    -- quantity data becomes available, replace this with a real quantity comparison.
    CASE
        WHEN co.order_status = 'SHIPPED' THEN TRUE
        WHEN co.order_status = 'PARTIAL' THEN FALSE
        ELSE NULL
    END AS is_in_full,
    -- Revenue at risk (for non-OTIF)
    CASE
        WHEN co.otif_flag = FALSE THEN co.order_value
        ELSE 0
    END AS revenue_at_risk,
    -- Time bucket
    DATE_TRUNC('month', co.order_date) AS order_month,
    DATE_TRUNC('week', co.order_date) AS order_week
FROM OTIF_GUARDIAN.RAW.CUSTOMER_ORDERS co
JOIN OTIF_GUARDIAN.RAW.PLANTS p ON co.plant_id = p.plant_id;

-- ============================================================
-- 10. SUPPLIER-MATERIAL SOURCING MAP (relationship view)
-- ============================================================

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ANALYTICS.V_SOURCING_MAP AS
-- Transport context: pick the single best lane per supplier origin country
-- (highest reliability_pct). This avoids fan-out from the 1:many relationship
-- between supplier country and transport lanes to multiple plant countries.
WITH best_lane AS (
    SELECT *
    FROM (
        SELECT
            tl.*,
            ROW_NUMBER() OVER (PARTITION BY tl.origin_country ORDER BY tl.reliability_pct DESC, tl.cost_per_kg ASC) AS rn
        FROM OTIF_GUARDIAN.RAW.TRANSPORT_LANES tl
    )
    WHERE rn = 1
)
SELECT
    als.alt_supplier_id,
    als.material_id,
    m.material_code,
    m.material_name,
    m.material_category,
    m.abc_class,
    m.criticality,
    als.supplier_id,
    s.supplier_code,
    s.supplier_name,
    s.supplier_tier,
    s.region AS supplier_region,
    s.country_code AS supplier_country,
    s.historical_otd_pct,
    s.quality_score,
    als.preference_rank,
    als.source_type,
    als.lead_time_days,
    als.min_order_qty,
    als.price_multiplier,
    ROUND(m.standard_unit_cost * als.price_multiplier, 2) AS effective_unit_cost,
    als.status AS sourcing_status,
    -- Transport context (best lane from supplier's country by reliability)
    bl.lane_code,
    bl.primary_mode,
    bl.transit_days,
    bl.cost_per_kg,
    bl.reliability_pct,
    bl.carbon_kg_per_kg
FROM OTIF_GUARDIAN.RAW.ALTERNATE_SUPPLIERS als
JOIN OTIF_GUARDIAN.RAW.MATERIALS m ON als.material_id = m.material_id
JOIN OTIF_GUARDIAN.RAW.SUPPLIERS s ON als.supplier_id = s.supplier_id
LEFT JOIN best_lane bl ON s.country_code = bl.origin_country;

-- ============================================================
-- 11. TRANSPORT NETWORK (lane enrichment)
-- ============================================================

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ANALYTICS.V_TRANSPORT_NETWORK AS
SELECT
    tl.lane_id,
    tl.lane_code,
    tl.origin_country,
    tl.dest_country,
    tl.primary_mode,
    tl.transit_days,
    tl.cost_per_kg,
    tl.reliability_pct,
    tl.carbon_kg_per_kg,
    tl.status,
    -- Volume context (ACTIVE entities only — reflects current operational capacity,
    -- not historical. Inactive/probation suppliers and shuttered plants are excluded.)
    orig.active_supplier_count,
    dest.active_plant_count,
    -- Efficiency classification
    CASE
        WHEN tl.reliability_pct >= 95 AND tl.cost_per_kg < 1.0 THEN 'OPTIMAL'
        WHEN tl.reliability_pct >= 90 THEN 'GOOD'
        WHEN tl.reliability_pct >= 80 THEN 'ACCEPTABLE'
        ELSE 'AT_RISK'
    END AS lane_health
FROM OTIF_GUARDIAN.RAW.TRANSPORT_LANES tl
LEFT JOIN (
    SELECT country_code, COUNT(*) AS active_supplier_count
    FROM OTIF_GUARDIAN.RAW.SUPPLIERS
    WHERE status = 'ACTIVE'
    GROUP BY country_code
) orig ON tl.origin_country = orig.country_code
LEFT JOIN (
    SELECT country_code, COUNT(*) AS active_plant_count
    FROM OTIF_GUARDIAN.RAW.PLANTS
    WHERE status = 'ACTIVE'
    GROUP BY country_code
) dest ON tl.dest_country = dest.country_code;

-- ============================================================
-- END OF ONTOLOGY VIEWS
-- ============================================================
