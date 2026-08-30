-- ============================================================
-- OTIF_Guardian: Deterministic Recovery Engine
-- Evaluates recovery actions for predicted OTIF breaches
-- ALL calculations are SQL — no LLM involved
-- Generated: 2026-08-28
-- ============================================================
--
-- RECOVERY ACTIONS EVALUATED:
--   1. EXPEDITE — Accelerate current PO via premium shipping
--   2. INVENTORY_TRANSFER — Move stock from another plant
--   3. ALTERNATE_SUPPLIER — Place emergency order with alternate source
--
-- VALUE CALCULATIONS:
--   - Revenue Protected = downstream customer order value saved
--   - OTIF Lift = expected OTIF improvement (probability delta)
--   - Incremental Cost = cost of recovery action above standard
--   - Net Value Protected = Revenue Protected - Incremental Cost
--
-- DECISION RULE: Deterministic ranking by Net Value Protected DESC
--   No LLM, no stochastic, no non-reproducible logic
--
-- ============================================================

USE DATABASE OTIF_GUARDIAN;
USE SCHEMA ML;
USE WAREHOUSE OTIF_GUARDIAN_WH;

-- ============================================================
-- 1. AT-RISK PO LINES (input to recovery engine)
-- ============================================================

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_AT_RISK_LINES AS
SELECT
    sr.po_line_id,
    sr.po_id,
    sr.po_number,
    sr.order_date,
    sr.promised_delivery_date,
    sr.days_until_due,
    sr.breach_probability,
    sr.risk_tier,
    sr.supplier_name,
    sr.supplier_tier,
    sr.material_code,
    sr.material_name,
    sr.plant_code,
    -- PO line details
    pl.quantity_ordered,
    pl.unit_price,
    pl.quantity_ordered * pl.unit_price AS line_value,
    pl.line_status,
    -- Supplier context
    s.supplier_id,
    s.standard_lead_time_days,
    s.country_code AS supplier_country,
    -- Material context
    m.material_id,
    m.material_category,
    m.abc_class,
    m.criticality,
    m.weight_kg,
    m.standard_unit_cost,
    -- Plant context
    po.plant_id,
    p.country_code AS plant_country,
    p.region AS plant_region
FROM OTIF_GUARDIAN.ML.V_SCORED_RESULTS sr
JOIN OTIF_GUARDIAN.RAW.PO_LINES pl ON sr.po_line_id = pl.po_line_id
JOIN OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po ON sr.po_id = po.po_id
JOIN OTIF_GUARDIAN.RAW.SUPPLIERS s ON po.supplier_id = s.supplier_id
JOIN OTIF_GUARDIAN.RAW.MATERIALS m ON pl.material_id = m.material_id
JOIN OTIF_GUARDIAN.RAW.PLANTS p ON po.plant_id = p.plant_id
WHERE sr.risk_tier IN ('CRITICAL', 'HIGH', 'MEDIUM');


-- ============================================================
-- 2. DOWNSTREAM REVENUE EXPOSURE
-- ============================================================
-- Estimate revenue at risk from customer orders that depend on
-- the at-risk material at the same plant within the delivery window

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_REVENUE_EXPOSURE AS
SELECT
    arl.po_line_id,
    arl.material_id,
    arl.plant_id,
    arl.promised_delivery_date,
    -- Count customer orders that need this material at this plant
    -- within 14 days of the promised delivery date
    COUNT(DISTINCT co.order_id) AS exposed_customer_orders,
    COALESCE(SUM(co.order_value), 0) AS total_exposed_revenue,
    -- Weighted by breach probability
    ROUND(COALESCE(SUM(co.order_value), 0) * arl.breach_probability, 2) AS probability_weighted_revenue
FROM OTIF_GUARDIAN.ML.V_AT_RISK_LINES arl
-- Join to demand that requires this material at this plant
JOIN OTIF_GUARDIAN.RAW.DEMAND d
    ON arl.material_id = d.material_id
    AND arl.plant_id = d.plant_id
    AND d.demand_type = 'FIRM'
    AND d.demand_date BETWEEN arl.promised_delivery_date
        AND DATEADD('day', 14, arl.promised_delivery_date)
-- Join to open customer orders at this plant in the same window
JOIN OTIF_GUARDIAN.RAW.CUSTOMER_ORDERS co
    ON co.plant_id = arl.plant_id
    AND co.order_status = 'OPEN'
    AND co.requested_delivery_date BETWEEN arl.promised_delivery_date
        AND DATEADD('day', 14, arl.promised_delivery_date)
GROUP BY arl.po_line_id, arl.material_id, arl.plant_id,
         arl.promised_delivery_date, arl.breach_probability;


-- ============================================================
-- 3. ACTION 1: EXPEDITE EVALUATION
-- ============================================================
-- Expedite = pay premium freight to accelerate current supplier shipment
-- Feasibility: days_until_due > 2 (minimum time for expedite to help)
-- Cost: premium shipping surcharge based on weight and distance

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_ACTION_EXPEDITE AS
SELECT
    arl.po_line_id,
    'EXPEDITE' AS action_type,

    -- Feasibility check
    CASE
        WHEN arl.days_until_due < 2 THEN FALSE  -- Too late to expedite
        WHEN arl.line_status = 'CANCELLED' THEN FALSE
        WHEN COALESCE(tl.primary_mode, 'UNKNOWN') = 'AIR' THEN FALSE  -- Already fastest mode
        ELSE TRUE
    END AS is_feasible,

    -- Time saved by expediting (switch ocean→air or truck→express)
    CASE
        WHEN tl.primary_mode = 'OCEAN' THEN GREATEST(0, tl.transit_days - 5)  -- Ocean→Air saves most
        WHEN tl.primary_mode = 'RAIL' THEN GREATEST(0, tl.transit_days - 3)
        WHEN tl.primary_mode = 'TRUCK' THEN GREATEST(0, FLOOR(tl.transit_days * 0.4))
        ELSE 2  -- Default 2 days saved
    END AS days_saved,

    -- New expected delivery vs promised
    CASE
        WHEN arl.days_until_due - CASE
            WHEN tl.primary_mode = 'OCEAN' THEN GREATEST(0, tl.transit_days - 5)
            WHEN tl.primary_mode = 'RAIL' THEN GREATEST(0, tl.transit_days - 3)
            WHEN tl.primary_mode = 'TRUCK' THEN GREATEST(0, FLOOR(tl.transit_days * 0.4))
            ELSE 2
        END <= 0 THEN TRUE  -- Would arrive on time after expedite
        ELSE FALSE
    END AS would_resolve_breach,

    -- Probability of success (deterministic based on mode and days)
    CASE
        WHEN arl.days_until_due >= 7 THEN 0.90
        WHEN arl.days_until_due >= 4 THEN 0.75
        WHEN arl.days_until_due >= 2 THEN 0.50
        ELSE 0.10
    END AS success_probability,

    -- OTIF lift: breach_probability * success_probability
    ROUND(arl.breach_probability *
        CASE
            WHEN arl.days_until_due >= 7 THEN 0.90
            WHEN arl.days_until_due >= 4 THEN 0.75
            WHEN arl.days_until_due >= 2 THEN 0.50
            ELSE 0.10
        END, 4) AS otif_lift,

    -- Incremental cost = qty * weight * surcharge per kg for mode upgrade
    -- Surcharge is always positive: the extra cost to jump to a faster mode
    ROUND(
        arl.quantity_ordered * ABS(arl.weight_kg) *
        CASE
            WHEN tl.primary_mode = 'OCEAN' THEN 3.00  -- Ocean→Air surcharge
            WHEN tl.primary_mode = 'RAIL'  THEN 1.50  -- Rail→Truck/Air surcharge
            WHEN tl.primary_mode = 'TRUCK' THEN 0.75  -- Truck→Express surcharge
            ELSE 1.00
        END
    , 2) AS incremental_cost,

    -- Revenue protected
    ROUND(
        COALESCE(re.probability_weighted_revenue, arl.line_value) *
        CASE
            WHEN arl.days_until_due >= 7 THEN 0.90
            WHEN arl.days_until_due >= 4 THEN 0.75
            WHEN arl.days_until_due >= 2 THEN 0.50
            ELSE 0.10
        END
    , 2) AS revenue_protected,

    -- Net value protected = revenue_protected - incremental_cost
    ROUND(
        COALESCE(re.probability_weighted_revenue, arl.line_value) *
        CASE
            WHEN arl.days_until_due >= 7 THEN 0.90
            WHEN arl.days_until_due >= 4 THEN 0.75
            WHEN arl.days_until_due >= 2 THEN 0.50
            ELSE 0.10
        END
        - arl.quantity_ordered * ABS(arl.weight_kg) *
        CASE
            WHEN tl.primary_mode = 'OCEAN' THEN 3.00
            WHEN tl.primary_mode = 'RAIL'  THEN 1.50
            WHEN tl.primary_mode = 'TRUCK' THEN 0.75
            ELSE 1.00
        END
    , 2) AS net_value_protected,

    -- Context
    arl.breach_probability,
    arl.days_until_due,
    COALESCE(tl.primary_mode, 'UNKNOWN') AS current_transport_mode,
    COALESCE(tl.transit_days, 14) AS current_transit_days,
    arl.line_value,
    COALESCE(re.total_exposed_revenue, 0) AS downstream_revenue_exposed

FROM OTIF_GUARDIAN.ML.V_AT_RISK_LINES arl
LEFT JOIN OTIF_GUARDIAN.RAW.TRANSPORT_LANES tl
    ON arl.supplier_country = tl.origin_country
    AND arl.plant_country = tl.dest_country
LEFT JOIN OTIF_GUARDIAN.ML.V_REVENUE_EXPOSURE re
    ON arl.po_line_id = re.po_line_id;


-- ============================================================
-- 4. ACTION 2: INVENTORY TRANSFER EVALUATION
-- ============================================================
-- Transfer = move existing stock from another plant that has surplus
-- Feasibility: another plant has available stock > reorder point

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_ACTION_INVENTORY_TRANSFER AS
SELECT
    arl.po_line_id,
    'INVENTORY_TRANSFER' AS action_type,

    -- Best donor plant (most surplus, closest)
    donor.plant_id AS donor_plant_id,
    donor.plant_code AS donor_plant_code,
    donor.qty_available AS donor_available_qty,
    donor.surplus_qty,

    -- Feasibility: donor has surplus AND can fulfill needed qty
    CASE
        WHEN donor.surplus_qty >= arl.quantity_ordered THEN TRUE
        WHEN donor.surplus_qty > 0 THEN TRUE  -- Partial transfer possible
        ELSE FALSE
    END AS is_feasible,

    -- Quantity transferable
    LEAST(arl.quantity_ordered, COALESCE(donor.surplus_qty, 0)) AS transferable_qty,

    -- Fill rate of transfer
    ROUND(LEAST(arl.quantity_ordered, COALESCE(donor.surplus_qty, 0)) * 1.0
        / NULLIF(arl.quantity_ordered, 0), 4) AS transfer_fill_rate,

    -- Transfer transit time (inter-plant, typically 2-5 days domestic, 7-14 international)
    CASE
        WHEN arl.plant_country = donor.plant_country THEN 3
        WHEN arl.plant_region = donor.plant_region THEN 7
        ELSE 12
    END AS transfer_transit_days,

    -- Would it arrive on time?
    CASE
        WHEN arl.days_until_due >= CASE
            WHEN arl.plant_country = donor.plant_country THEN 3
            WHEN arl.plant_region = donor.plant_region THEN 7
            ELSE 12
        END THEN TRUE
        ELSE FALSE
    END AS would_resolve_breach,

    -- Success probability
    CASE
        WHEN donor.surplus_qty >= arl.quantity_ordered
             AND arl.days_until_due >= CASE
                WHEN arl.plant_country = donor.plant_country THEN 3
                WHEN arl.plant_region = donor.plant_region THEN 7
                ELSE 12
             END THEN 0.95
        WHEN donor.surplus_qty > 0
             AND arl.days_until_due >= 3 THEN 0.70
        ELSE 0.20
    END AS success_probability,

    -- OTIF lift
    ROUND(arl.breach_probability *
        CASE
            WHEN donor.surplus_qty >= arl.quantity_ordered
                 AND arl.days_until_due >= CASE
                    WHEN arl.plant_country = donor.plant_country THEN 3
                    WHEN arl.plant_region = donor.plant_region THEN 7
                    ELSE 12
                 END THEN 0.95
            WHEN donor.surplus_qty > 0
                 AND arl.days_until_due >= 3 THEN 0.70
            ELSE 0.20
        END
    , 4) AS otif_lift,

    -- Incremental cost = transfer shipping + handling
    -- Shipping: weight * qty * inter-plant rate
    -- Handling: fixed $2/unit for pick-pack-ship at donor
    ROUND(
        LEAST(arl.quantity_ordered, COALESCE(donor.surplus_qty, 0)) *
        (arl.weight_kg * CASE
            WHEN arl.plant_country = donor.plant_country THEN 0.80  -- Domestic truck rate
            WHEN arl.plant_region = donor.plant_region THEN 1.50    -- Regional
            ELSE 3.00                                                -- International
        END + 2.00)  -- $2/unit handling
    , 2) AS incremental_cost,

    -- Revenue protected
    ROUND(
        COALESCE(re.probability_weighted_revenue, arl.line_value) *
        CASE
            WHEN donor.surplus_qty >= arl.quantity_ordered
                 AND arl.days_until_due >= CASE
                    WHEN arl.plant_country = donor.plant_country THEN 3
                    WHEN arl.plant_region = donor.plant_region THEN 7
                    ELSE 12
                 END THEN 0.95
            WHEN donor.surplus_qty > 0
                 AND arl.days_until_due >= 3 THEN 0.70
            ELSE 0.20
        END
    , 2) AS revenue_protected,

    -- Net value protected
    ROUND(
        COALESCE(re.probability_weighted_revenue, arl.line_value) *
        CASE
            WHEN donor.surplus_qty >= arl.quantity_ordered
                 AND arl.days_until_due >= CASE
                    WHEN arl.plant_country = donor.plant_country THEN 3
                    WHEN arl.plant_region = donor.plant_region THEN 7
                    ELSE 12
                 END THEN 0.95
            WHEN donor.surplus_qty > 0
                 AND arl.days_until_due >= 3 THEN 0.70
            ELSE 0.20
        END
        - LEAST(arl.quantity_ordered, COALESCE(donor.surplus_qty, 0)) *
          (arl.weight_kg * CASE
              WHEN arl.plant_country = donor.plant_country THEN 0.80
              WHEN arl.plant_region = donor.plant_region THEN 1.50
              ELSE 3.00
          END + 2.00)
    , 2) AS net_value_protected,

    -- Context
    arl.breach_probability,
    arl.days_until_due,
    arl.quantity_ordered,
    arl.line_value,
    COALESCE(re.total_exposed_revenue, 0) AS downstream_revenue_exposed

FROM OTIF_GUARDIAN.ML.V_AT_RISK_LINES arl
-- Find best donor plant (most surplus for this material, excluding the needing plant)
LEFT JOIN LATERAL (
    SELECT
        inv.plant_id,
        plt.plant_code,
        plt.country_code AS plant_country,
        plt.region AS plant_region,
        inv.qty_on_hand - inv.qty_reserved AS qty_available,
        (inv.qty_on_hand - inv.qty_reserved) - inv.reorder_point AS surplus_qty
    FROM OTIF_GUARDIAN.RAW.INVENTORY inv
    JOIN OTIF_GUARDIAN.RAW.PLANTS plt ON inv.plant_id = plt.plant_id
    WHERE inv.material_id = arl.material_id
      AND inv.plant_id != arl.plant_id
      AND (inv.qty_on_hand - inv.qty_reserved) > inv.reorder_point  -- Only surplus plants
    ORDER BY (inv.qty_on_hand - inv.qty_reserved) - inv.reorder_point DESC
    LIMIT 1
) donor ON TRUE
LEFT JOIN OTIF_GUARDIAN.ML.V_REVENUE_EXPOSURE re
    ON arl.po_line_id = re.po_line_id;


-- ============================================================
-- 5. ACTION 3: ALTERNATE SUPPLIER EVALUATION
-- ============================================================
-- Alt supplier = place emergency PO with a different qualified supplier
-- Feasibility: active alternate supplier exists with acceptable lead time

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_ACTION_ALTERNATE_SUPPLIER AS
SELECT
    arl.po_line_id,
    'ALTERNATE_SUPPLIER' AS action_type,

    -- Best alternate supplier
    alt_sup.alt_supplier_id,
    alt_sup.supplier_code AS alt_supplier_code,
    alt_sup.supplier_name AS alt_supplier_name,
    alt_sup.preference_rank AS alt_rank,
    alt_sup.lead_time_days AS alt_lead_time,
    alt_sup.effective_unit_cost AS alt_unit_cost,
    alt_sup.historical_otd_pct AS alt_otd_pct,

    -- Feasibility: alternate exists, lead time fits, MOQ met
    CASE
        WHEN alt_sup.alt_supplier_id IS NULL THEN FALSE
        WHEN alt_sup.lead_time_days > arl.days_until_due + 3 THEN FALSE  -- Won't arrive in time (3-day buffer)
        WHEN alt_sup.min_order_qty > arl.quantity_ordered * 2 THEN FALSE  -- MOQ too high
        ELSE TRUE
    END AS is_feasible,

    -- Would it arrive on time?
    CASE
        WHEN alt_sup.lead_time_days <= arl.days_until_due THEN TRUE
        ELSE FALSE
    END AS would_resolve_breach,

    -- Success probability (based on alternate's historical performance)
    CASE
        WHEN alt_sup.historical_otd_pct >= 95 AND alt_sup.lead_time_days <= arl.days_until_due THEN 0.90
        WHEN alt_sup.historical_otd_pct >= 85 AND alt_sup.lead_time_days <= arl.days_until_due THEN 0.75
        WHEN alt_sup.historical_otd_pct >= 75 THEN 0.55
        WHEN alt_sup.alt_supplier_id IS NOT NULL THEN 0.35
        ELSE 0.00
    END AS success_probability,

    -- OTIF lift
    ROUND(arl.breach_probability *
        CASE
            WHEN alt_sup.historical_otd_pct >= 95 AND alt_sup.lead_time_days <= arl.days_until_due THEN 0.90
            WHEN alt_sup.historical_otd_pct >= 85 AND alt_sup.lead_time_days <= arl.days_until_due THEN 0.75
            WHEN alt_sup.historical_otd_pct >= 75 THEN 0.55
            WHEN alt_sup.alt_supplier_id IS NOT NULL THEN 0.35
            ELSE 0.00
        END
    , 4) AS otif_lift,

    -- Incremental cost = (alt_unit_cost - standard_cost) * qty + expedite shipping if needed
    ROUND(
        CASE WHEN alt_sup.alt_supplier_id IS NOT NULL THEN
            -- Price premium
            (COALESCE(alt_sup.effective_unit_cost, arl.standard_unit_cost) - arl.standard_unit_cost)
                * arl.quantity_ordered
            -- Plus expedite freight if tight timeline
            + CASE
                WHEN arl.days_until_due - COALESCE(alt_sup.lead_time_days, 99) < 3
                THEN arl.quantity_ordered * arl.weight_kg * 2.50  -- Air freight premium
                ELSE 0
              END
        ELSE 0
        END
    , 2) AS incremental_cost,

    -- Revenue protected
    ROUND(
        COALESCE(re.probability_weighted_revenue, arl.line_value) *
        CASE
            WHEN alt_sup.historical_otd_pct >= 95 AND alt_sup.lead_time_days <= arl.days_until_due THEN 0.90
            WHEN alt_sup.historical_otd_pct >= 85 AND alt_sup.lead_time_days <= arl.days_until_due THEN 0.75
            WHEN alt_sup.historical_otd_pct >= 75 THEN 0.55
            WHEN alt_sup.alt_supplier_id IS NOT NULL THEN 0.35
            ELSE 0.00
        END
    , 2) AS revenue_protected,

    -- Net value protected
    ROUND(
        COALESCE(re.probability_weighted_revenue, arl.line_value) *
        CASE
            WHEN alt_sup.historical_otd_pct >= 95 AND alt_sup.lead_time_days <= arl.days_until_due THEN 0.90
            WHEN alt_sup.historical_otd_pct >= 85 AND alt_sup.lead_time_days <= arl.days_until_due THEN 0.75
            WHEN alt_sup.historical_otd_pct >= 75 THEN 0.55
            WHEN alt_sup.alt_supplier_id IS NOT NULL THEN 0.35
            ELSE 0.00
        END
        - CASE WHEN alt_sup.alt_supplier_id IS NOT NULL THEN
            (COALESCE(alt_sup.effective_unit_cost, arl.standard_unit_cost) - arl.standard_unit_cost)
                * arl.quantity_ordered
            + CASE
                WHEN arl.days_until_due - COALESCE(alt_sup.lead_time_days, 99) < 3
                THEN arl.quantity_ordered * arl.weight_kg * 2.50
                ELSE 0
              END
          ELSE 0
          END
    , 2) AS net_value_protected,

    -- Context
    arl.breach_probability,
    arl.days_until_due,
    arl.quantity_ordered,
    arl.line_value,
    arl.standard_unit_cost,
    COALESCE(re.total_exposed_revenue, 0) AS downstream_revenue_exposed

FROM OTIF_GUARDIAN.ML.V_AT_RISK_LINES arl
-- Find best alternate supplier
LEFT JOIN LATERAL (
    SELECT
        als.alt_supplier_id,
        s2.supplier_code,
        s2.supplier_name,
        als.preference_rank,
        als.lead_time_days,
        als.min_order_qty,
        ROUND(arl.standard_unit_cost * als.price_multiplier, 2) AS effective_unit_cost,
        s2.historical_otd_pct
    FROM OTIF_GUARDIAN.RAW.ALTERNATE_SUPPLIERS als
    JOIN OTIF_GUARDIAN.RAW.SUPPLIERS s2 ON als.supplier_id = s2.supplier_id
    WHERE als.material_id = arl.material_id
      AND als.supplier_id != arl.supplier_id  -- Not the current failing supplier
      AND als.status = 'ACTIVE'
      AND s2.status = 'ACTIVE'
    ORDER BY
        -- Prefer: fits timeline, high OTD, low rank number
        CASE WHEN als.lead_time_days <= arl.days_until_due THEN 0 ELSE 1 END,
        s2.historical_otd_pct DESC,
        als.preference_rank ASC
    LIMIT 1
) alt_sup ON TRUE
LEFT JOIN OTIF_GUARDIAN.ML.V_REVENUE_EXPOSURE re
    ON arl.po_line_id = re.po_line_id;


-- ============================================================
-- 6. UNIFIED RECOVERY RECOMMENDATIONS (ranked)
-- ============================================================

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_RECOVERY_RECOMMENDATIONS AS
WITH all_actions AS (
    -- Expedite
    SELECT
        po_line_id, action_type, is_feasible, would_resolve_breach,
        success_probability, otif_lift, incremental_cost,
        revenue_protected, net_value_protected,
        breach_probability, days_until_due, line_value,
        downstream_revenue_exposed,
        NULL AS donor_plant_code,
        NULL AS alt_supplier_name,
        current_transport_mode AS action_detail
    FROM OTIF_GUARDIAN.ML.V_ACTION_EXPEDITE

    UNION ALL

    -- Inventory Transfer
    SELECT
        po_line_id, action_type, is_feasible, would_resolve_breach,
        success_probability, otif_lift, incremental_cost,
        revenue_protected, net_value_protected,
        breach_probability, days_until_due, line_value,
        downstream_revenue_exposed,
        donor_plant_code,
        NULL AS alt_supplier_name,
        'Transfer from ' || COALESCE(donor_plant_code, 'N/A') AS action_detail
    FROM OTIF_GUARDIAN.ML.V_ACTION_INVENTORY_TRANSFER

    UNION ALL

    -- Alternate Supplier
    SELECT
        po_line_id, action_type, is_feasible, would_resolve_breach,
        success_probability, otif_lift, incremental_cost,
        revenue_protected, net_value_protected,
        breach_probability, days_until_due, line_value,
        downstream_revenue_exposed,
        NULL AS donor_plant_code,
        alt_supplier_name,
        'Order from ' || COALESCE(alt_supplier_name, 'N/A') AS action_detail
    FROM OTIF_GUARDIAN.ML.V_ACTION_ALTERNATE_SUPPLIER
),
-- Rank only cost-positive feasible actions
ranked AS (
    SELECT
        aa.*,
        ROW_NUMBER() OVER (
            PARTITION BY aa.po_line_id
            ORDER BY
                aa.net_value_protected DESC,
                aa.success_probability DESC
        ) AS action_rank,
        CASE
            WHEN aa.incremental_cost > 0
            THEN ROUND(aa.net_value_protected / aa.incremental_cost, 2)
            ELSE NULL
        END AS roi_multiple
    FROM all_actions aa
    WHERE aa.is_feasible = TRUE
      AND aa.net_value_protected > 0
),
-- Lines that have risk but no cost-positive action get NO_ACTION
at_risk_lines AS (
    SELECT DISTINCT po_line_id, breach_probability, days_until_due, line_value,
           downstream_revenue_exposed
    FROM all_actions
),
no_action_lines AS (
    SELECT
        arl.po_line_id,
        'NO_ACTION' AS action_type,
        TRUE AS is_feasible,
        FALSE AS would_resolve_breach,
        0 AS success_probability,
        0 AS otif_lift,
        0 AS incremental_cost,
        0 AS revenue_protected,
        0 AS net_value_protected,
        arl.breach_probability,
        arl.days_until_due,
        arl.line_value,
        arl.downstream_revenue_exposed,
        NULL AS donor_plant_code,
        NULL AS alt_supplier_name,
        'No cost-effective recovery action available' AS action_detail,
        1 AS action_rank,
        NULL AS roi_multiple
    FROM at_risk_lines arl
    WHERE NOT EXISTS (SELECT 1 FROM ranked r WHERE r.po_line_id = arl.po_line_id)
)
SELECT * FROM ranked
UNION ALL
SELECT * FROM no_action_lines;


-- ============================================================
-- 7. TOP RECOMMENDATION PER PO LINE
-- ============================================================

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_BEST_RECOVERY_ACTION AS
SELECT *
FROM OTIF_GUARDIAN.ML.V_RECOVERY_RECOMMENDATIONS
WHERE action_rank = 1;


-- ============================================================
-- 8. PORTFOLIO SUMMARY (aggregate impact of all recommended actions)
-- ============================================================

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_RECOVERY_PORTFOLIO_SUMMARY AS
SELECT
    -- Overall
    COUNT(DISTINCT po_line_id) AS at_risk_lines_addressable,
    COUNT(*) AS total_feasible_actions,

    -- Revenue metrics
    ROUND(SUM(CASE WHEN action_rank = 1 THEN revenue_protected ELSE 0 END), 2) AS total_revenue_protected,
    ROUND(SUM(CASE WHEN action_rank = 1 THEN incremental_cost ELSE 0 END), 2) AS total_incremental_cost,
    ROUND(SUM(CASE WHEN action_rank = 1 THEN net_value_protected ELSE 0 END), 2) AS total_net_value_protected,

    -- OTIF impact
    ROUND(AVG(CASE WHEN action_rank = 1 THEN otif_lift END), 4) AS avg_otif_lift,
    ROUND(SUM(CASE WHEN action_rank = 1 THEN otif_lift END), 2) AS cumulative_otif_lift_points,

    -- Action mix
    COUNT_IF(action_rank = 1 AND action_type = 'EXPEDITE') AS recommended_expedites,
    COUNT_IF(action_rank = 1 AND action_type = 'INVENTORY_TRANSFER') AS recommended_transfers,
    COUNT_IF(action_rank = 1 AND action_type = 'ALTERNATE_SUPPLIER') AS recommended_alt_suppliers,
    COUNT_IF(action_rank = 1 AND action_type = 'NO_ACTION') AS no_cost_effective_action,

    -- ROI
    ROUND(
        SUM(CASE WHEN action_rank = 1 THEN net_value_protected ELSE 0 END) /
        NULLIF(SUM(CASE WHEN action_rank = 1 THEN incremental_cost ELSE 0 END), 0)
    , 2) AS portfolio_roi_multiple

FROM OTIF_GUARDIAN.ML.V_RECOVERY_RECOMMENDATIONS;


-- ============================================================
-- 9. SUMMARY BY ACTION TYPE
-- ============================================================

CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_RECOVERY_BY_ACTION_TYPE AS
SELECT
    action_type,
    COUNT(*) AS feasible_count,
    COUNT_IF(action_rank = 1) AS recommended_count,
    ROUND(SUM(CASE WHEN action_rank = 1 THEN revenue_protected ELSE 0 END), 2) AS revenue_protected,
    ROUND(SUM(CASE WHEN action_rank = 1 THEN incremental_cost ELSE 0 END), 2) AS incremental_cost,
    ROUND(SUM(CASE WHEN action_rank = 1 THEN net_value_protected ELSE 0 END), 2) AS net_value_protected,
    ROUND(AVG(CASE WHEN action_rank = 1 THEN success_probability END), 4) AS avg_success_prob,
    ROUND(AVG(CASE WHEN action_rank = 1 THEN otif_lift END), 4) AS avg_otif_lift
FROM OTIF_GUARDIAN.ML.V_RECOVERY_RECOMMENDATIONS
GROUP BY action_type
ORDER BY net_value_protected DESC;


-- ============================================================
-- END OF RECOVERY ENGINE
-- ============================================================
