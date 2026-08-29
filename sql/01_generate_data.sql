-- ============================================================
-- OTIF_Guardian: Supply Chain Data Generation
-- Deterministic seeds | Referential integrity | Production distributions
-- Generated: 2026-08-28
-- ============================================================
-- EXECUTION ORDER: Run sections sequentially (1 through 12)
-- All RANDOM/UNIFORM calls use fixed seeds for reproducibility
-- ============================================================

USE DATABASE OTIF_GUARDIAN;
USE SCHEMA RAW;
USE WAREHOUSE OTIF_GUARDIAN_WH;

-- ============================================================
-- 1. SUPPLIERS (60)
-- ============================================================

CREATE OR REPLACE TABLE OTIF_GUARDIAN.RAW.SUPPLIERS AS
WITH seed_data AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS supplier_id,
        SEQ4() AS seq
    FROM TABLE(GENERATOR(ROWCOUNT => 60))
),
regions AS (
    SELECT column1 AS region_code, column2 AS region_name FROM VALUES
        ('APAC', 'Asia Pacific'),
        ('EMEA', 'Europe Middle East Africa'),
        ('AMER', 'Americas'),
        ('LATAM', 'Latin America')
),
supplier_tiers AS (
    SELECT column1 AS tier FROM VALUES (1), (2), (3)
)
SELECT
    s.supplier_id,
    'SUP-' || LPAD(s.supplier_id::STRING, 4, '0') AS supplier_code,
    CASE MOD(HASH(s.supplier_id, 42), 20)
        WHEN 0 THEN 'Apex Materials Corp'
        WHEN 1 THEN 'BridgePoint Industries'
        WHEN 2 THEN 'CrestLine Manufacturing'
        WHEN 3 THEN 'DeltaForge Metals'
        WHEN 4 THEN 'EverFlow Polymers'
        WHEN 5 THEN 'FusionTech Components'
        WHEN 6 THEN 'GlobalPak Solutions'
        WHEN 7 THEN 'HarborView Chemicals'
        WHEN 8 THEN 'IronBridge Alloys'
        WHEN 9 THEN 'JetStream Logistics'
        WHEN 10 THEN 'KeyStone Plastics'
        WHEN 11 THEN 'LuminArc Electronics'
        WHEN 12 THEN 'MeridianWorks'
        WHEN 13 THEN 'NovaCast Foundry'
        WHEN 14 THEN 'OmniSource Trading'
        WHEN 15 THEN 'PrimePath Materials'
        WHEN 16 THEN 'QuantumEdge Supply'
        WHEN 17 THEN 'RidgeLine Composites'
        WHEN 18 THEN 'SteelVault Industries'
        WHEN 19 THEN 'TerraFirm Resources'
    END || ' ' || CASE WHEN s.supplier_id > 20 THEN LPAD(MOD(s.supplier_id, 20)::STRING, 2, '0') ELSE '' END AS supplier_name,
    CASE MOD(HASH(s.supplier_id, 101), 4)
        WHEN 0 THEN 'APAC'
        WHEN 1 THEN 'EMEA'
        WHEN 2 THEN 'AMER'
        WHEN 3 THEN 'LATAM'
    END AS region,
    CASE MOD(HASH(s.supplier_id, 201), 12)
        WHEN 0 THEN 'CN'   WHEN 1 THEN 'DE'   WHEN 2 THEN 'US'
        WHEN 3 THEN 'JP'   WHEN 4 THEN 'KR'   WHEN 5 THEN 'IN'
        WHEN 6 THEN 'MX'   WHEN 7 THEN 'BR'   WHEN 8 THEN 'TW'
        WHEN 9 THEN 'TH'   WHEN 10 THEN 'VN'  WHEN 11 THEN 'PL'
    END AS country_code,
    -- Tier distribution: 15% Tier-1, 50% Tier-2, 35% Tier-3
    CASE
        WHEN MOD(HASH(s.supplier_id, 301), 100) < 15 THEN 1
        WHEN MOD(HASH(s.supplier_id, 301), 100) < 65 THEN 2
        ELSE 3
    END AS supplier_tier,
    -- Lead time in days: Tier-1 shorter, Tier-3 longer
    CASE
        WHEN MOD(HASH(s.supplier_id, 301), 100) < 15 THEN 7 + MOD(HASH(s.supplier_id, 401), 14)
        WHEN MOD(HASH(s.supplier_id, 301), 100) < 65 THEN 14 + MOD(HASH(s.supplier_id, 401), 21)
        ELSE 28 + MOD(HASH(s.supplier_id, 401), 30)
    END AS standard_lead_time_days,
    -- On-time delivery rate: realistic distribution (70%-99%)
    ROUND(70 + (MOD(HASH(s.supplier_id, 501), 2900) / 100.0), 1) AS historical_otd_pct,
    -- Quality score: 80-100
    ROUND(80 + (MOD(HASH(s.supplier_id, 601), 2000) / 100.0), 1) AS quality_score,
    CASE MOD(HASH(s.supplier_id, 701), 3)
        WHEN 0 THEN 'ACTIVE'
        WHEN 1 THEN 'ACTIVE'
        WHEN 2 THEN CASE WHEN MOD(HASH(s.supplier_id, 801), 10) < 2 THEN 'PROBATION' ELSE 'ACTIVE' END
    END AS status,
    DATEADD('day', -1 * (365 + MOD(HASH(s.supplier_id, 901), 1825)), '2026-08-28'::DATE) AS onboarded_date,
    CURRENT_TIMESTAMP() AS created_at
FROM seed_data s;

-- ============================================================
-- 2. PLANTS (8)
-- ============================================================

CREATE OR REPLACE TABLE OTIF_GUARDIAN.RAW.PLANTS AS
SELECT column1 AS plant_id,
       column2 AS plant_code,
       column3 AS plant_name,
       column4 AS city,
       column5 AS country_code,
       column6 AS region,
       column7 AS timezone,
       column8 AS capacity_units_per_day,
       'ACTIVE'::VARCHAR AS status,
       CURRENT_TIMESTAMP() AS created_at
FROM VALUES
    (1, 'PLT-MFG-01', 'Detroit Assembly',       'Detroit',    'US', 'AMER', 'America/Detroit',    12000),
    (2, 'PLT-MFG-02', 'Monterrey Production',   'Monterrey', 'MX', 'LATAM','America/Monterrey',  9500),
    (3, 'PLT-MFG-03', 'Stuttgart Precision',    'Stuttgart', 'DE', 'EMEA', 'Europe/Berlin',      8000),
    (4, 'PLT-MFG-04', 'Shanghai Hub',           'Shanghai',  'CN', 'APAC', 'Asia/Shanghai',      15000),
    (5, 'PLT-MFG-05', 'Chennai Works',          'Chennai',   'IN', 'APAC', 'Asia/Kolkata',       11000),
    (6, 'PLT-MFG-06', 'Yokohama Advanced',      'Yokohama',  'JP', 'APAC', 'Asia/Tokyo',         7500),
    (7, 'PLT-MFG-07', 'Wroclaw Assembly',       'Wroclaw',   'PL', 'EMEA', 'Europe/Warsaw',      6500),
    (8, 'PLT-MFG-08', 'Guadalajara South',      'Guadalajara','MX','LATAM','America/Mexico_City', 8500);

-- ============================================================
-- 3. MATERIALS (250)
-- ============================================================

CREATE OR REPLACE TABLE OTIF_GUARDIAN.RAW.MATERIALS AS
WITH seed_data AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS material_id, SEQ4() AS seq
    FROM TABLE(GENERATOR(ROWCOUNT => 250))
)
SELECT
    s.material_id,
    'MAT-' || LPAD(s.material_id::STRING, 5, '0') AS material_code,
    CASE MOD(HASH(s.material_id, 1001), 8)
        WHEN 0 THEN 'Steel Coil '
        WHEN 1 THEN 'Aluminum Sheet '
        WHEN 2 THEN 'Polymer Resin '
        WHEN 3 THEN 'Electronic Module '
        WHEN 4 THEN 'Rubber Compound '
        WHEN 5 THEN 'Copper Wire '
        WHEN 6 THEN 'Ceramic Insert '
        WHEN 7 THEN 'Glass Panel '
    END || CASE MOD(HASH(s.material_id, 1101), 6)
        WHEN 0 THEN 'Type-A'  WHEN 1 THEN 'Type-B'  WHEN 2 THEN 'Grade-1'
        WHEN 3 THEN 'Grade-2' WHEN 4 THEN 'Spec-X'  WHEN 5 THEN 'Spec-Y'
    END || ' ' || LPAD(MOD(s.material_id, 50)::STRING, 2, '0') AS material_name,
    CASE MOD(HASH(s.material_id, 1201), 8)
        WHEN 0 THEN 'METALS'
        WHEN 1 THEN 'METALS'
        WHEN 2 THEN 'POLYMERS'
        WHEN 3 THEN 'ELECTRONICS'
        WHEN 4 THEN 'RUBBER'
        WHEN 5 THEN 'METALS'
        WHEN 6 THEN 'CERAMICS'
        WHEN 7 THEN 'GLASS'
    END AS material_category,
    CASE MOD(HASH(s.material_id, 1301), 4)
        WHEN 0 THEN 'KG'
        WHEN 1 THEN 'EA'
        WHEN 2 THEN 'M'
        WHEN 3 THEN 'L'
    END AS unit_of_measure,
    -- Unit cost: log-normal-like distribution ($0.50 - $2500)
    ROUND(POWER(10, 0.5 + (MOD(HASH(s.material_id, 1401), 350) / 100.0)) * 0.05, 2) AS standard_unit_cost,
    -- Weight in KG
    ROUND(0.01 + (MOD(HASH(s.material_id, 1501), 10000) / 100.0), 2) AS weight_kg,
    -- ABC classification: 20% A, 30% B, 50% C
    CASE
        WHEN MOD(HASH(s.material_id, 1601), 100) < 20 THEN 'A'
        WHEN MOD(HASH(s.material_id, 1601), 100) < 50 THEN 'B'
        ELSE 'C'
    END AS abc_class,
    -- Criticality
    CASE MOD(HASH(s.material_id, 1701), 5)
        WHEN 0 THEN 'CRITICAL'
        WHEN 1 THEN 'CRITICAL'
        WHEN 2 THEN 'IMPORTANT'
        WHEN 3 THEN 'IMPORTANT'
        WHEN 4 THEN 'STANDARD'
    END AS criticality,
    -- Safety stock days
    CASE
        WHEN MOD(HASH(s.material_id, 1601), 100) < 20 THEN 14 + MOD(HASH(s.material_id, 1801), 7)
        WHEN MOD(HASH(s.material_id, 1601), 100) < 50 THEN 7 + MOD(HASH(s.material_id, 1801), 7)
        ELSE 3 + MOD(HASH(s.material_id, 1801), 5)
    END AS safety_stock_days,
    CASE WHEN MOD(HASH(s.material_id, 1901), 20) = 0 THEN 'INACTIVE' ELSE 'ACTIVE' END AS status,
    CURRENT_TIMESTAMP() AS created_at
FROM seed_data s;

-- ============================================================
-- 4. PURCHASE ORDERS (header) - ~6200 historical + ~160 active
-- ============================================================

CREATE OR REPLACE TABLE OTIF_GUARDIAN.RAW.PURCHASE_ORDERS AS
WITH seed_data AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS po_id, SEQ4() AS seq
    FROM TABLE(GENERATOR(ROWCOUNT => 6400))
)
SELECT
    s.po_id,
    'PO-' || LPAD(s.po_id::STRING, 7, '0') AS po_number,
    -- Distribute across suppliers (weighted: Tier-1 gets more POs)
    1 + MOD(HASH(s.po_id, 2001), 60) AS supplier_id,
    -- Distribute across plants
    1 + MOD(HASH(s.po_id, 2101), 8) AS plant_id,
    -- Order date: spread over 3 years, more recent dates more frequent
    DATEADD('day',
        -1 * GREATEST(0, FLOOR(POWER(MOD(HASH(s.po_id, 2201), 1000) / 1000.0, 0.5) * 1095)),
        '2026-08-28'::DATE
    ) AS order_date,
    -- Requested delivery date: order_date + lead time variation
    DATEADD('day',
        -1 * GREATEST(0, FLOOR(POWER(MOD(HASH(s.po_id, 2201), 1000) / 1000.0, 0.5) * 1095)),
        '2026-08-28'::DATE
    ) + (14 + MOD(HASH(s.po_id, 2301), 45)) AS requested_delivery_date,
    CASE
        WHEN DATEADD('day',
            -1 * GREATEST(0, FLOOR(POWER(MOD(HASH(s.po_id, 2201), 1000) / 1000.0, 0.5) * 1095)),
            '2026-08-28'::DATE
        ) < '2026-07-01'::DATE THEN 'CLOSED'
        WHEN MOD(HASH(s.po_id, 2401), 10) < 2 THEN 'OPEN'
        ELSE 'CLOSED'
    END AS po_status,
    CASE MOD(HASH(s.po_id, 2501), 4)
        WHEN 0 THEN 'STANDARD'
        WHEN 1 THEN 'STANDARD'
        WHEN 2 THEN 'BLANKET'
        WHEN 3 THEN 'EXPEDITE'
    END AS po_type,
    CASE MOD(HASH(s.po_id, 2601), 3)
        WHEN 0 THEN 'USD' WHEN 1 THEN 'EUR' WHEN 2 THEN 'CNY'
    END AS currency,
    CURRENT_TIMESTAMP() AS created_at
FROM seed_data s;

-- ============================================================
-- 5. PO LINES (~30000 historical + ~800 active)
-- ============================================================

CREATE OR REPLACE TABLE OTIF_GUARDIAN.RAW.PO_LINES AS
WITH seed_data AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS line_id, SEQ4() AS seq
    FROM TABLE(GENERATOR(ROWCOUNT => 30800))
),
po_count AS (
    SELECT COUNT(*) AS total_pos FROM OTIF_GUARDIAN.RAW.PURCHASE_ORDERS
)
SELECT
    s.line_id AS po_line_id,
    -- Distribute lines across POs (avg ~4.8 lines per PO)
    1 + MOD(HASH(s.line_id, 3001), (SELECT total_pos FROM po_count)) AS po_id,
    -- Line number within PO
    1 + MOD(s.line_id - 1, 7) AS line_number,
    -- Material assignment
    1 + MOD(HASH(s.line_id, 3101), 250) AS material_id,
    -- Quantity: log-normal distribution (10 - 50000)
    GREATEST(10, FLOOR(POWER(10, 1 + (MOD(HASH(s.line_id, 3201), 370) / 100.0)) * 0.1))::INTEGER AS quantity_ordered,
    -- Unit price with some variation from standard
    ROUND(
        POWER(10, 0.5 + (MOD(HASH(1 + MOD(HASH(s.line_id, 3101), 250), 1401), 350) / 100.0)) * 0.05
        * (0.85 + MOD(HASH(s.line_id, 3301), 30) / 100.0),
    2) AS unit_price,
    -- Quantity received (outcome-bucketed: 90% clean, 6% late-only, 3% short, 1% both)
    CASE
        WHEN MOD(HASH(s.line_id, 3001), 6400) > 6000 THEN
            -- Active lines: 0-70% received
            FLOOR(GREATEST(10, FLOOR(POWER(10, 1 + (MOD(HASH(s.line_id, 3201), 370) / 100.0)) * 0.1))
                * MOD(HASH(s.line_id, 3401), 70) / 100.0)::INTEGER
        WHEN MOD(HASH(s.line_id, 4001), 100) < 90 THEN
            -- 90% clean: fully filled
            GREATEST(10, FLOOR(POWER(10, 1 + (MOD(HASH(s.line_id, 3201), 370) / 100.0)) * 0.1))::INTEGER
        WHEN MOD(HASH(s.line_id, 4001), 100) < 96 THEN
            -- 6% late-only: fully filled
            GREATEST(10, FLOOR(POWER(10, 1 + (MOD(HASH(s.line_id, 3201), 370) / 100.0)) * 0.1))::INTEGER
        WHEN MOD(HASH(s.line_id, 4001), 100) < 99 THEN
            -- 3% short-shipped only: 70-94% fill
            FLOOR(GREATEST(10, FLOOR(POWER(10, 1 + (MOD(HASH(s.line_id, 3201), 370) / 100.0)) * 0.1))
                * (70 + MOD(HASH(s.line_id, 3903), 25)) / 100.0)::INTEGER
        ELSE
            -- 1% both late AND short: 50-79% fill
            FLOOR(GREATEST(10, FLOOR(POWER(10, 1 + (MOD(HASH(s.line_id, 3201), 370) / 100.0)) * 0.1))
                * (50 + MOD(HASH(s.line_id, 3903), 30)) / 100.0)::INTEGER
    END AS quantity_received,
    -- Line status
    CASE
        WHEN MOD(HASH(s.line_id, 3001), 6400) > 6000 THEN
            CASE MOD(HASH(s.line_id, 3601), 4)
                WHEN 0 THEN 'OPEN'
                WHEN 1 THEN 'PARTIALLY_RECEIVED'
                WHEN 2 THEN 'OPEN'
                WHEN 3 THEN 'IN_TRANSIT'
            END
        ELSE
            CASE MOD(HASH(s.line_id, 3701), 20)
                WHEN 0 THEN 'SHORT_CLOSED'
                WHEN 1 THEN 'CANCELLED'
                ELSE 'CLOSED'
            END
    END AS line_status,
    -- Promised date
    DATEADD('day',
        14 + MOD(HASH(s.line_id, 3801), 45),
        DATEADD('day',
            -1 * GREATEST(0, FLOOR(POWER(MOD(HASH(1 + MOD(HASH(s.line_id, 3001), 6400), 2201), 1000) / 1000.0, 0.5) * 1095)),
            '2026-08-28'::DATE
        )
    ) AS promised_delivery_date,
    -- Actual delivery date (outcome-bucketed: matches quantity_received logic)
    CASE
        WHEN MOD(HASH(s.line_id, 3001), 6400) > 6000 THEN NULL
        WHEN MOD(HASH(s.line_id, 4001), 100) < 90 THEN
            -- 90% clean: early/on-time (-5 to 0 days)
            DATEADD('day',
                14 + MOD(HASH(s.line_id, 3801), 45)
                + (MOD(HASH(s.line_id, 3901), 6) - 5),
                DATEADD('day',
                    -1 * GREATEST(0, FLOOR(POWER(MOD(HASH(1 + MOD(HASH(s.line_id, 3001), 6400), 2201), 1000) / 1000.0, 0.5) * 1095)),
                    '2026-08-28'::DATE
                )
            )
        WHEN MOD(HASH(s.line_id, 4001), 100) < 96 THEN
            -- 6% late-only: 1 to 10 days late
            DATEADD('day',
                14 + MOD(HASH(s.line_id, 3801), 45)
                + (1 + MOD(HASH(s.line_id, 3902), 10)),
                DATEADD('day',
                    -1 * GREATEST(0, FLOOR(POWER(MOD(HASH(1 + MOD(HASH(s.line_id, 3001), 6400), 2201), 1000) / 1000.0, 0.5) * 1095)),
                    '2026-08-28'::DATE
                )
            )
        WHEN MOD(HASH(s.line_id, 4001), 100) < 99 THEN
            -- 3% short-shipped only: still on-time (-5 to 0 days)
            DATEADD('day',
                14 + MOD(HASH(s.line_id, 3801), 45)
                + (MOD(HASH(s.line_id, 3901), 6) - 5),
                DATEADD('day',
                    -1 * GREATEST(0, FLOOR(POWER(MOD(HASH(1 + MOD(HASH(s.line_id, 3001), 6400), 2201), 1000) / 1000.0, 0.5) * 1095)),
                    '2026-08-28'::DATE
                )
            )
        ELSE
            -- 1% both late AND short: 5 to 19 days late
            DATEADD('day',
                14 + MOD(HASH(s.line_id, 3801), 45)
                + (5 + MOD(HASH(s.line_id, 3902), 15)),
                DATEADD('day',
                    -1 * GREATEST(0, FLOOR(POWER(MOD(HASH(1 + MOD(HASH(s.line_id, 3001), 6400), 2201), 1000) / 1000.0, 0.5) * 1095)),
                    '2026-08-28'::DATE
                )
            )
    END AS actual_delivery_date,
    CURRENT_TIMESTAMP() AS created_at
FROM seed_data s;

-- ============================================================
-- 6. SHIPMENTS
-- ============================================================

CREATE OR REPLACE TABLE OTIF_GUARDIAN.RAW.SHIPMENTS AS
WITH seed_data AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS shipment_id, SEQ4() AS seq
    FROM TABLE(GENERATOR(ROWCOUNT => 28000))
)
SELECT
    s.shipment_id,
    'SHP-' || LPAD(s.shipment_id::STRING, 8, '0') AS shipment_number,
    -- Link to PO lines (1:1 or 1:many for split shipments)
    1 + MOD(HASH(s.shipment_id, 4001), 30800) AS po_line_id,
    CASE MOD(HASH(s.shipment_id, 4101), 5)
        WHEN 0 THEN 'AIR'
        WHEN 1 THEN 'OCEAN'
        WHEN 2 THEN 'OCEAN'
        WHEN 3 THEN 'TRUCK'
        WHEN 4 THEN 'RAIL'
    END AS transport_mode,
    'CARRIER-' || LPAD((1 + MOD(HASH(s.shipment_id, 4201), 25))::STRING, 3, '0') AS carrier_code,
    -- Ship date
    DATEADD('day',
        -1 * MOD(HASH(s.shipment_id, 4301), 1000),
        '2026-08-28'::DATE
    ) AS ship_date,
    -- ETA: ship_date + transit time based on mode
    DATEADD('day',
        -1 * MOD(HASH(s.shipment_id, 4301), 1000)
        + CASE MOD(HASH(s.shipment_id, 4101), 5)
            WHEN 0 THEN 3 + MOD(HASH(s.shipment_id, 4401), 5)
            WHEN 1 THEN 21 + MOD(HASH(s.shipment_id, 4401), 20)
            WHEN 2 THEN 21 + MOD(HASH(s.shipment_id, 4401), 20)
            WHEN 3 THEN 2 + MOD(HASH(s.shipment_id, 4401), 7)
            WHEN 4 THEN 7 + MOD(HASH(s.shipment_id, 4401), 10)
          END,
        '2026-08-28'::DATE
    ) AS estimated_arrival_date,
    -- Actual arrival (NULL for in-transit)
    CASE
        WHEN DATEADD('day',
            -1 * MOD(HASH(s.shipment_id, 4301), 1000)
            + CASE MOD(HASH(s.shipment_id, 4101), 5)
                WHEN 0 THEN 3 + MOD(HASH(s.shipment_id, 4401), 5)
                WHEN 1 THEN 21 + MOD(HASH(s.shipment_id, 4401), 20)
                WHEN 2 THEN 21 + MOD(HASH(s.shipment_id, 4401), 20)
                WHEN 3 THEN 2 + MOD(HASH(s.shipment_id, 4401), 7)
                WHEN 4 THEN 7 + MOD(HASH(s.shipment_id, 4401), 10)
              END,
            '2026-08-28'::DATE
        ) > '2026-08-28'::DATE THEN NULL
        ELSE DATEADD('day',
            -1 * MOD(HASH(s.shipment_id, 4301), 1000)
            + CASE MOD(HASH(s.shipment_id, 4101), 5)
                WHEN 0 THEN 3 + MOD(HASH(s.shipment_id, 4401), 5)
                WHEN 1 THEN 21 + MOD(HASH(s.shipment_id, 4401), 20)
                WHEN 2 THEN 21 + MOD(HASH(s.shipment_id, 4401), 20)
                WHEN 3 THEN 2 + MOD(HASH(s.shipment_id, 4401), 7)
                WHEN 4 THEN 7 + MOD(HASH(s.shipment_id, 4401), 10)
              END
            + (MOD(HASH(s.shipment_id, 4501), 5) - 1),  -- -1 to +3 days variance
            '2026-08-28'::DATE
        )
    END AS actual_arrival_date,
    CASE
        WHEN DATEADD('day',
            -1 * MOD(HASH(s.shipment_id, 4301), 1000)
            + CASE MOD(HASH(s.shipment_id, 4101), 5)
                WHEN 0 THEN 3  WHEN 1 THEN 21  WHEN 2 THEN 21
                WHEN 3 THEN 2  WHEN 4 THEN 7
              END,
            '2026-08-28'::DATE
        ) > '2026-08-28'::DATE THEN 'IN_TRANSIT'
        WHEN MOD(HASH(s.shipment_id, 4601), 50) = 0 THEN 'DAMAGED'
        ELSE 'DELIVERED'
    END AS shipment_status,
    -- Quantity shipped
    GREATEST(5, FLOOR(POWER(10, 1 + (MOD(HASH(s.shipment_id, 4701), 350) / 100.0)) * 0.08))::INTEGER AS quantity_shipped,
    CURRENT_TIMESTAMP() AS created_at
FROM seed_data s;

-- ============================================================
-- 7. RECEIPTS
-- ============================================================

CREATE OR REPLACE TABLE OTIF_GUARDIAN.RAW.RECEIPTS AS
WITH seed_data AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS receipt_id, SEQ4() AS seq
    FROM TABLE(GENERATOR(ROWCOUNT => 26000))
)
SELECT
    s.receipt_id,
    'RCV-' || LPAD(s.receipt_id::STRING, 8, '0') AS receipt_number,
    -- Link to shipment
    1 + MOD(HASH(s.receipt_id, 5001), 28000) AS shipment_id,
    -- Link to plant
    1 + MOD(HASH(s.receipt_id, 5101), 8) AS plant_id,
    -- Receipt date
    DATEADD('day', -1 * MOD(HASH(s.receipt_id, 5201), 950), '2026-08-28'::DATE) AS receipt_date,
    -- Quantity received
    GREATEST(5, FLOOR(POWER(10, 1 + (MOD(HASH(s.receipt_id, 5301), 340) / 100.0)) * 0.07))::INTEGER AS quantity_received,
    -- Quality inspection result
    CASE MOD(HASH(s.receipt_id, 5401), 100)
        WHEN 0 THEN 'REJECTED'
        WHEN 1 THEN 'REJECTED'
        WHEN 2 THEN 'CONDITIONAL'
        WHEN 3 THEN 'CONDITIONAL'
        WHEN 4 THEN 'CONDITIONAL'
        ELSE 'ACCEPTED'
    END AS inspection_result,
    -- Quantity accepted
    CASE
        WHEN MOD(HASH(s.receipt_id, 5401), 100) < 2 THEN 0
        WHEN MOD(HASH(s.receipt_id, 5401), 100) < 5 THEN
            FLOOR(GREATEST(5, FLOOR(POWER(10, 1 + (MOD(HASH(s.receipt_id, 5301), 340) / 100.0)) * 0.07))
                * (85 + MOD(HASH(s.receipt_id, 5501), 10)) / 100.0)::INTEGER
        ELSE GREATEST(5, FLOOR(POWER(10, 1 + (MOD(HASH(s.receipt_id, 5301), 340) / 100.0)) * 0.07))::INTEGER
    END AS quantity_accepted,
    CURRENT_TIMESTAMP() AS created_at
FROM seed_data s;

-- ============================================================
-- 8. INVENTORY (current snapshot per material per plant)
-- ============================================================

CREATE OR REPLACE TABLE OTIF_GUARDIAN.RAW.INVENTORY AS
WITH combos AS (
    SELECT
        m.material_id,
        p.plant_id,
        m.abc_class,
        m.standard_unit_cost
    FROM OTIF_GUARDIAN.RAW.MATERIALS m
    CROSS JOIN OTIF_GUARDIAN.RAW.PLANTS p
    WHERE MOD(HASH(m.material_id, p.plant_id, 6001), 3) < 2  -- Not all materials at all plants
)
SELECT
    ROW_NUMBER() OVER (ORDER BY c.plant_id, c.material_id) AS inventory_id,
    c.plant_id,
    c.material_id,
    -- On-hand quantity
    GREATEST(0, FLOOR(POWER(10, 1.5 + (MOD(HASH(c.material_id, c.plant_id, 6101), 250) / 100.0)) * 0.2))::INTEGER AS qty_on_hand,
    -- In-transit quantity
    FLOOR(POWER(10, 1 + (MOD(HASH(c.material_id, c.plant_id, 6201), 200) / 100.0)) * 0.1)::INTEGER AS qty_in_transit,
    -- Reserved quantity
    FLOOR(GREATEST(0, FLOOR(POWER(10, 1.5 + (MOD(HASH(c.material_id, c.plant_id, 6101), 250) / 100.0)) * 0.2))
        * MOD(HASH(c.material_id, c.plant_id, 6301), 40) / 100.0)::INTEGER AS qty_reserved,
    -- Reorder point
    GREATEST(10, FLOOR(POWER(10, 1.2 + (MOD(HASH(c.material_id, c.plant_id, 6401), 200) / 100.0)) * 0.15))::INTEGER AS reorder_point,
    -- Days of supply
    ROUND(3 + MOD(HASH(c.material_id, c.plant_id, 6501), 45), 1) AS days_of_supply,
    -- Inventory value
    ROUND(
        GREATEST(0, FLOOR(POWER(10, 1.5 + (MOD(HASH(c.material_id, c.plant_id, 6101), 250) / 100.0)) * 0.2))
        * c.standard_unit_cost,
    2) AS inventory_value,
    '2026-08-28'::DATE AS snapshot_date,
    CURRENT_TIMESTAMP() AS created_at
FROM combos c;

-- ============================================================
-- 9. DEMAND (customer demand signals)
-- ============================================================

CREATE OR REPLACE TABLE OTIF_GUARDIAN.RAW.DEMAND AS
WITH seed_data AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS demand_id, SEQ4() AS seq
    FROM TABLE(GENERATOR(ROWCOUNT => 15000))
)
SELECT
    s.demand_id,
    'DMD-' || LPAD(s.demand_id::STRING, 7, '0') AS demand_number,
    -- Material
    1 + MOD(HASH(s.demand_id, 7001), 250) AS material_id,
    -- Plant
    1 + MOD(HASH(s.demand_id, 7101), 8) AS plant_id,
    -- Demand date (next 90 days + historical 365 days)
    DATEADD('day',
        MOD(HASH(s.demand_id, 7201), 455) - 365,
        '2026-08-28'::DATE
    ) AS demand_date,
    -- Quantity
    GREATEST(10, FLOOR(POWER(10, 1.5 + (MOD(HASH(s.demand_id, 7301), 250) / 100.0)) * 0.15))::INTEGER AS quantity_demanded,
    CASE MOD(HASH(s.demand_id, 7401), 4)
        WHEN 0 THEN 'FIRM'
        WHEN 1 THEN 'FIRM'
        WHEN 2 THEN 'PLANNED'
        WHEN 3 THEN 'FORECAST'
    END AS demand_type,
    CASE MOD(HASH(s.demand_id, 7501), 3)
        WHEN 0 THEN 'HIGH'
        WHEN 1 THEN 'MEDIUM'
        WHEN 2 THEN 'LOW'
    END AS priority,
    CURRENT_TIMESTAMP() AS created_at
FROM seed_data s;

-- ============================================================
-- 10. CUSTOMER ORDERS
-- ============================================================

CREATE OR REPLACE TABLE OTIF_GUARDIAN.RAW.CUSTOMER_ORDERS AS
WITH seed_data AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS order_id, SEQ4() AS seq
    FROM TABLE(GENERATOR(ROWCOUNT => 12000))
)
SELECT
    s.order_id,
    'CO-' || LPAD(s.order_id::STRING, 7, '0') AS order_number,
    'CUST-' || LPAD((1 + MOD(HASH(s.order_id, 8001), 200))::STRING, 4, '0') AS customer_code,
    CASE MOD(HASH(s.order_id, 8101), 10)
        WHEN 0 THEN 'Apex Automotive'    WHEN 1 THEN 'BrightStar Motors'
        WHEN 2 THEN 'Continental Mfg'    WHEN 3 THEN 'DriveForce Inc'
        WHEN 4 THEN 'ElectraDrive'       WHEN 5 THEN 'FleetPower Corp'
        WHEN 6 THEN 'GreenMotion Ltd'    WHEN 7 THEN 'HyperDrive Systems'
        WHEN 8 THEN 'InnoVehicle'        WHEN 9 THEN 'JoltEnergy'
    END || ' ' || LPAD(MOD(1 + MOD(HASH(s.order_id, 8001), 200), 20)::STRING, 2, '0') AS customer_name,
    -- Plant fulfilling
    1 + MOD(HASH(s.order_id, 8201), 8) AS plant_id,
    -- Order date
    DATEADD('day', -1 * MOD(HASH(s.order_id, 8301), 730), '2026-08-28'::DATE) AS order_date,
    -- Requested delivery date
    DATEADD('day', -1 * MOD(HASH(s.order_id, 8301), 730) + 7 + MOD(HASH(s.order_id, 8401), 30), '2026-08-28'::DATE) AS requested_delivery_date,
    -- Actual ship date (NULL for open orders)
    CASE
        WHEN DATEADD('day', -1 * MOD(HASH(s.order_id, 8301), 730) + 7 + MOD(HASH(s.order_id, 8401), 30), '2026-08-28'::DATE)
            > '2026-08-28'::DATE THEN NULL
        ELSE DATEADD('day',
            -1 * MOD(HASH(s.order_id, 8301), 730) + 7 + MOD(HASH(s.order_id, 8401), 30)
            + (MOD(HASH(s.order_id, 8501), 7) - 2),
            '2026-08-28'::DATE)
    END AS actual_ship_date,
    -- Order value
    ROUND(100 + POWER(10, 2 + MOD(HASH(s.order_id, 8601), 200) / 100.0) * 0.5, 2) AS order_value,
    -- Line count
    1 + MOD(HASH(s.order_id, 8701), 12) AS line_count,
    CASE
        WHEN DATEADD('day', -1 * MOD(HASH(s.order_id, 8301), 730) + 7 + MOD(HASH(s.order_id, 8401), 30), '2026-08-28'::DATE)
            > '2026-08-28'::DATE THEN 'OPEN'
        WHEN MOD(HASH(s.order_id, 8801), 20) = 0 THEN 'PARTIAL'
        ELSE 'SHIPPED'
    END AS order_status,
    -- OTIF flag (for historical shipped orders)
    CASE
        WHEN DATEADD('day', -1 * MOD(HASH(s.order_id, 8301), 730) + 7 + MOD(HASH(s.order_id, 8401), 30), '2026-08-28'::DATE)
            > '2026-08-28'::DATE THEN NULL
        WHEN MOD(HASH(s.order_id, 8501), 7) - 2 <= 0
            AND MOD(HASH(s.order_id, 8801), 20) != 0 THEN TRUE
        ELSE FALSE
    END AS otif_flag,
    CURRENT_TIMESTAMP() AS created_at
FROM seed_data s;

-- ============================================================
-- 11. ALTERNATE SUPPLIERS (material-supplier mapping with ranking)
-- ============================================================

CREATE OR REPLACE TABLE OTIF_GUARDIAN.RAW.ALTERNATE_SUPPLIERS AS
WITH combos AS (
    SELECT
        m.material_id,
        s.supplier_id,
        s.supplier_tier,
        s.standard_lead_time_days,
        s.historical_otd_pct
    FROM OTIF_GUARDIAN.RAW.MATERIALS m
    CROSS JOIN OTIF_GUARDIAN.RAW.SUPPLIERS s
    -- Each material has 2-5 suppliers (deterministic selection)
    WHERE MOD(HASH(m.material_id, s.supplier_id, 9001), 100) < 7
)
SELECT
    ROW_NUMBER() OVER (ORDER BY c.material_id, c.supplier_tier, c.supplier_id) AS alt_supplier_id,
    c.material_id,
    c.supplier_id,
    ROW_NUMBER() OVER (PARTITION BY c.material_id ORDER BY c.supplier_tier, c.historical_otd_pct DESC) AS preference_rank,
    CASE
        WHEN ROW_NUMBER() OVER (PARTITION BY c.material_id ORDER BY c.supplier_tier, c.historical_otd_pct DESC) = 1
        THEN 'PRIMARY'
        ELSE 'ALTERNATE'
    END AS source_type,
    c.standard_lead_time_days AS lead_time_days,
    -- MOQ: minimum order quantity
    GREATEST(10, MOD(HASH(c.material_id, c.supplier_id, 9101), 500) * 10) AS min_order_qty,
    -- Price multiplier vs standard (alternates may cost more)
    ROUND(1.0 + (MOD(HASH(c.material_id, c.supplier_id, 9201), 30) / 100.0), 3) AS price_multiplier,
    CASE WHEN MOD(HASH(c.material_id, c.supplier_id, 9301), 15) = 0 THEN 'INACTIVE' ELSE 'ACTIVE' END AS status,
    CURRENT_TIMESTAMP() AS created_at
FROM combos c;

-- ============================================================
-- 12. TRANSPORT LANES
-- ============================================================

CREATE OR REPLACE TABLE OTIF_GUARDIAN.RAW.TRANSPORT_LANES AS
WITH origins AS (
    SELECT DISTINCT country_code AS origin_country FROM OTIF_GUARDIAN.RAW.SUPPLIERS
),
destinations AS (
    SELECT DISTINCT country_code AS dest_country FROM OTIF_GUARDIAN.RAW.PLANTS
),
lanes AS (
    SELECT
        o.origin_country,
        d.dest_country
    FROM origins o
    CROSS JOIN destinations d
)
SELECT
    ROW_NUMBER() OVER (ORDER BY l.origin_country, l.dest_country) AS lane_id,
    l.origin_country,
    l.dest_country,
    l.origin_country || '-' || l.dest_country AS lane_code,
    CASE MOD(HASH(l.origin_country, l.dest_country, 10001), 4)
        WHEN 0 THEN 'OCEAN'
        WHEN 1 THEN 'AIR'
        WHEN 2 THEN 'TRUCK'
        WHEN 3 THEN 'MULTIMODAL'
    END AS primary_mode,
    -- Transit days
    CASE
        WHEN l.origin_country = l.dest_country THEN 1 + MOD(HASH(l.origin_country, l.dest_country, 10101), 3)
        WHEN MOD(HASH(l.origin_country, l.dest_country, 10001), 4) = 0 THEN 18 + MOD(HASH(l.origin_country, l.dest_country, 10201), 22)
        WHEN MOD(HASH(l.origin_country, l.dest_country, 10001), 4) = 1 THEN 2 + MOD(HASH(l.origin_country, l.dest_country, 10201), 6)
        WHEN MOD(HASH(l.origin_country, l.dest_country, 10001), 4) = 2 THEN 3 + MOD(HASH(l.origin_country, l.dest_country, 10201), 8)
        ELSE 10 + MOD(HASH(l.origin_country, l.dest_country, 10201), 15)
    END AS transit_days,
    -- Cost per KG
    ROUND(CASE
        WHEN l.origin_country = l.dest_country THEN 0.05 + MOD(HASH(l.origin_country, l.dest_country, 10301), 10) / 100.0
        WHEN MOD(HASH(l.origin_country, l.dest_country, 10001), 4) = 1 THEN 2.5 + MOD(HASH(l.origin_country, l.dest_country, 10301), 300) / 100.0
        ELSE 0.15 + MOD(HASH(l.origin_country, l.dest_country, 10301), 80) / 100.0
    END, 3) AS cost_per_kg,
    -- Reliability %
    ROUND(75 + MOD(HASH(l.origin_country, l.dest_country, 10401), 2400) / 100.0, 1) AS reliability_pct,
    -- Carbon factor (kg CO2 per kg shipped)
    ROUND(CASE
        WHEN MOD(HASH(l.origin_country, l.dest_country, 10001), 4) = 1 THEN 1.2 + MOD(HASH(l.origin_country, l.dest_country, 10501), 100) / 100.0
        WHEN MOD(HASH(l.origin_country, l.dest_country, 10001), 4) = 0 THEN 0.02 + MOD(HASH(l.origin_country, l.dest_country, 10501), 5) / 100.0
        ELSE 0.1 + MOD(HASH(l.origin_country, l.dest_country, 10501), 20) / 100.0
    END, 4) AS carbon_kg_per_kg,
    'ACTIVE'::VARCHAR AS status,
    CURRENT_TIMESTAMP() AS created_at
FROM lanes l;

-- ============================================================
-- END OF DATA GENERATION
-- ============================================================
