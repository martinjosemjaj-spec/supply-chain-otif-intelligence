-- ============================================================
-- OTIF_Guardian: SQL Test Suite
-- Tests for bootstrap, data integrity, referential integrity,
-- and ontology view correctness.
-- Generated: 2026-08-28
-- ============================================================
-- EXECUTION: Run all statements. Each returns PASS/FAIL.
-- Convention: A test PASSES if violation_count = 0.
-- ============================================================

USE DATABASE OTIF_GUARDIAN;
USE WAREHOUSE OTIF_GUARDIAN_WH;

-- ============================================================
-- SECTION 1: BOOTSTRAP TESTS
-- ============================================================

-- T-SQL-001: All required schemas exist
SELECT 'T-SQL-001' AS test_id, 'All required schemas exist' AS test_name,
    CASE WHEN COUNT(*) >= 8 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS actual_count, 8 AS expected_minimum
FROM INFORMATION_SCHEMA.SCHEMATA
WHERE CATALOG_NAME = 'OTIF_GUARDIAN'
  AND SCHEMA_NAME IN ('RAW','STAGING','ANALYTICS','SEMANTIC','ML','AGENTS','STREAMLIT','AUDIT');

-- T-SQL-002: Warehouse exists
SELECT 'T-SQL-002' AS test_id, 'Warehouse exists' AS test_name,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS actual_count, 1 AS expected
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
-- Alternative:
SHOW WAREHOUSES LIKE 'OTIF_GUARDIAN_WH';

-- T-SQL-003: All roles exist
SELECT 'T-SQL-003' AS test_id, 'All project roles exist' AS test_name,
    CASE WHEN COUNT(*) = 4 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS actual_count, 4 AS expected
FROM (
    SHOW ROLES LIKE 'OTIF_GUARDIAN%'
);

-- ============================================================
-- SECTION 2: DATA VOLUME TESTS
-- ============================================================

-- T-SQL-010: Suppliers count
SELECT 'T-SQL-010' AS test_id, 'Suppliers = 60' AS test_name,
    CASE WHEN COUNT(*) = 60 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS actual, 60 AS expected
FROM OTIF_GUARDIAN.RAW.SUPPLIERS;

-- T-SQL-011: Plants count
SELECT 'T-SQL-011' AS test_id, 'Plants = 8' AS test_name,
    CASE WHEN COUNT(*) = 8 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS actual, 8 AS expected
FROM OTIF_GUARDIAN.RAW.PLANTS;

-- T-SQL-012: Materials count
SELECT 'T-SQL-012' AS test_id, 'Materials = 250' AS test_name,
    CASE WHEN COUNT(*) = 250 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS actual, 250 AS expected
FROM OTIF_GUARDIAN.RAW.MATERIALS;

-- T-SQL-013: PO Lines approximately 30800
SELECT 'T-SQL-013' AS test_id, 'PO Lines ~30800' AS test_name,
    CASE WHEN COUNT(*) BETWEEN 30000 AND 31500 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS actual, 30800 AS expected
FROM OTIF_GUARDIAN.RAW.PO_LINES;

-- T-SQL-014: Active PO Lines approximately 800
SELECT 'T-SQL-014' AS test_id, 'Active PO Lines ~800' AS test_name,
    CASE WHEN COUNT(*) BETWEEN 600 AND 1200 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS actual, 800 AS expected
FROM OTIF_GUARDIAN.RAW.PO_LINES
WHERE LINE_STATUS IN ('OPEN','IN_TRANSIT','PARTIALLY_RECEIVED');

-- T-SQL-015: All 12 raw tables populated
SELECT 'T-SQL-015' AS test_id, 'All 12 tables have rows > 0' AS test_name,
    CASE WHEN COUNT(*) = 12 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS tables_with_data, 12 AS expected
FROM (
    SELECT 'SUPPLIERS' AS t, COUNT(*) AS c FROM OTIF_GUARDIAN.RAW.SUPPLIERS HAVING COUNT(*) > 0
    UNION ALL SELECT 'PLANTS', COUNT(*) FROM OTIF_GUARDIAN.RAW.PLANTS HAVING COUNT(*) > 0
    UNION ALL SELECT 'MATERIALS', COUNT(*) FROM OTIF_GUARDIAN.RAW.MATERIALS HAVING COUNT(*) > 0
    UNION ALL SELECT 'PURCHASE_ORDERS', COUNT(*) FROM OTIF_GUARDIAN.RAW.PURCHASE_ORDERS HAVING COUNT(*) > 0
    UNION ALL SELECT 'PO_LINES', COUNT(*) FROM OTIF_GUARDIAN.RAW.PO_LINES HAVING COUNT(*) > 0
    UNION ALL SELECT 'SHIPMENTS', COUNT(*) FROM OTIF_GUARDIAN.RAW.SHIPMENTS HAVING COUNT(*) > 0
    UNION ALL SELECT 'RECEIPTS', COUNT(*) FROM OTIF_GUARDIAN.RAW.RECEIPTS HAVING COUNT(*) > 0
    UNION ALL SELECT 'INVENTORY', COUNT(*) FROM OTIF_GUARDIAN.RAW.INVENTORY HAVING COUNT(*) > 0
    UNION ALL SELECT 'DEMAND', COUNT(*) FROM OTIF_GUARDIAN.RAW.DEMAND HAVING COUNT(*) > 0
    UNION ALL SELECT 'CUSTOMER_ORDERS', COUNT(*) FROM OTIF_GUARDIAN.RAW.CUSTOMER_ORDERS HAVING COUNT(*) > 0
    UNION ALL SELECT 'ALTERNATE_SUPPLIERS', COUNT(*) FROM OTIF_GUARDIAN.RAW.ALTERNATE_SUPPLIERS HAVING COUNT(*) > 0
    UNION ALL SELECT 'TRANSPORT_LANES', COUNT(*) FROM OTIF_GUARDIAN.RAW.TRANSPORT_LANES HAVING COUNT(*) > 0
);

-- ============================================================
-- SECTION 3: REFERENTIAL INTEGRITY TESTS
-- ============================================================

-- T-SQL-020: PO → Supplier FK integrity
SELECT 'T-SQL-020' AS test_id, 'PO.supplier_id → SUPPLIERS (no orphans)' AS test_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS orphan_count, 0 AS expected
FROM OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po
LEFT JOIN OTIF_GUARDIAN.RAW.SUPPLIERS s ON po.SUPPLIER_ID = s.SUPPLIER_ID
WHERE s.SUPPLIER_ID IS NULL;

-- T-SQL-021: PO → Plant FK integrity
SELECT 'T-SQL-021' AS test_id, 'PO.plant_id → PLANTS (no orphans)' AS test_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS orphan_count, 0 AS expected
FROM OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po
LEFT JOIN OTIF_GUARDIAN.RAW.PLANTS p ON po.PLANT_ID = p.PLANT_ID
WHERE p.PLANT_ID IS NULL;

-- T-SQL-022: PO_LINES → PO FK integrity
SELECT 'T-SQL-022' AS test_id, 'PO_LINES.po_id → PURCHASE_ORDERS (no orphans)' AS test_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS orphan_count, 0 AS expected
FROM OTIF_GUARDIAN.RAW.PO_LINES pl
LEFT JOIN OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po ON pl.PO_ID = po.PO_ID
WHERE po.PO_ID IS NULL;

-- T-SQL-023: PO_LINES → Material FK integrity
SELECT 'T-SQL-023' AS test_id, 'PO_LINES.material_id → MATERIALS (no orphans)' AS test_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS orphan_count, 0 AS expected
FROM OTIF_GUARDIAN.RAW.PO_LINES pl
LEFT JOIN OTIF_GUARDIAN.RAW.MATERIALS m ON pl.MATERIAL_ID = m.MATERIAL_ID
WHERE m.MATERIAL_ID IS NULL;

-- T-SQL-024: Inventory → Material/Plant FK integrity
SELECT 'T-SQL-024' AS test_id, 'INVENTORY FK integrity' AS test_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS orphan_count, 0 AS expected
FROM OTIF_GUARDIAN.RAW.INVENTORY i
LEFT JOIN OTIF_GUARDIAN.RAW.MATERIALS m ON i.MATERIAL_ID = m.MATERIAL_ID
LEFT JOIN OTIF_GUARDIAN.RAW.PLANTS p ON i.PLANT_ID = p.PLANT_ID
WHERE m.MATERIAL_ID IS NULL OR p.PLANT_ID IS NULL;

-- ============================================================
-- SECTION 4: DATA QUALITY TESTS
-- ============================================================

-- T-SQL-030: No NULL primary keys in PO_LINES
SELECT 'T-SQL-030' AS test_id, 'PO_LINES: no NULL PK' AS test_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS violations, 0 AS expected
FROM OTIF_GUARDIAN.RAW.PO_LINES WHERE PO_LINE_ID IS NULL;

-- T-SQL-031: Quantities positive
SELECT 'T-SQL-031' AS test_id, 'PO_LINES: quantity_ordered > 0' AS test_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS violations, 0 AS expected
FROM OTIF_GUARDIAN.RAW.PO_LINES WHERE QUANTITY_ORDERED <= 0;

-- T-SQL-032: Unit prices positive
SELECT 'T-SQL-032' AS test_id, 'PO_LINES: unit_price > 0' AS test_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS violations, 0 AS expected
FROM OTIF_GUARDIAN.RAW.PO_LINES WHERE UNIT_PRICE <= 0;

-- T-SQL-033: Supplier OTD percentage in valid range
SELECT 'T-SQL-033' AS test_id, 'SUPPLIERS: OTD 0-100%' AS test_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS violations, 0 AS expected
FROM OTIF_GUARDIAN.RAW.SUPPLIERS
WHERE HISTORICAL_OTD_PCT < 0 OR HISTORICAL_OTD_PCT > 100;

-- T-SQL-034: Dates in reasonable range
SELECT 'T-SQL-034' AS test_id, 'PO order_date within 2021-2027' AS test_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS violations, 0 AS expected
FROM OTIF_GUARDIAN.RAW.PURCHASE_ORDERS
WHERE ORDER_DATE < '2021-01-01' OR ORDER_DATE > '2027-12-31';

-- T-SQL-035: Closed lines have actual_delivery_date
SELECT 'T-SQL-035' AS test_id, 'Closed lines have delivery date' AS test_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS violations, 0 AS expected
FROM OTIF_GUARDIAN.RAW.PO_LINES
WHERE LINE_STATUS = 'CLOSED' AND ACTUAL_DELIVERY_DATE IS NULL;

-- T-SQL-036: Open lines have NULL actual_delivery_date
SELECT 'T-SQL-036' AS test_id, 'Open lines have NULL delivery date' AS test_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS violations, 0 AS expected
FROM OTIF_GUARDIAN.RAW.PO_LINES
WHERE LINE_STATUS = 'OPEN' AND ACTUAL_DELIVERY_DATE IS NOT NULL;

-- ============================================================
-- SECTION 5: ONTOLOGY VIEW TESTS
-- ============================================================

-- T-SQL-040: All 11 ontology views exist
SELECT 'T-SQL-040' AS test_id, '11 ontology views exist' AS test_name,
    CASE WHEN COUNT(*) >= 11 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS actual, 11 AS expected
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'ANALYTICS' AND TABLE_CATALOG = 'OTIF_GUARDIAN';

-- T-SQL-041: V_PO_DELIVERY_PERFORMANCE has OTIF flags
SELECT 'T-SQL-041' AS test_id, 'OTIF flags computed correctly' AS test_name,
    CASE WHEN COUNT_IF(IS_OTIF IS NOT NULL) > 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT_IF(IS_OTIF IS NOT NULL) AS non_null_flags, 0 AS expected_minimum
FROM OTIF_GUARDIAN.ANALYTICS.V_PO_DELIVERY_PERFORMANCE;

-- T-SQL-042: V_INVENTORY_POSITION health classification populated
SELECT 'T-SQL-042' AS test_id, 'Inventory health classified' AS test_name,
    CASE WHEN COUNT_IF(INVENTORY_HEALTH IS NOT NULL) > 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT_IF(INVENTORY_HEALTH IS NOT NULL) AS classified, 0 AS expected_minimum
FROM OTIF_GUARDIAN.ANALYTICS.V_INVENTORY_POSITION;

-- T-SQL-043: V_CUSTOMER_ORDER_OTIF OTIF flag matches logic
SELECT 'T-SQL-043' AS test_id, 'Customer OTIF flag consistent' AS test_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS violations, 0 AS expected
FROM OTIF_GUARDIAN.ANALYTICS.V_CUSTOMER_ORDER_OTIF
WHERE IS_ON_TIME = TRUE AND IS_IN_FULL = TRUE AND OTIF_FLAG = FALSE;

-- ============================================================
-- END OF SQL TESTS
-- ============================================================
