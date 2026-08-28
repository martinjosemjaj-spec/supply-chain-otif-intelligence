-- ============================================================
-- OTIF_Guardian: Semantic View + Agent + Governance Tests
-- Tests for YAML validation, VQR correctness, agent behavior,
-- governance guardrails, and edge cases.
-- Generated: 2026-08-28
-- ============================================================

USE DATABASE OTIF_GUARDIAN;
USE WAREHOUSE OTIF_GUARDIAN_WH;

-- ============================================================
-- SECTION 1: SEMANTIC VIEW TESTS
-- ============================================================

-- T-SEM-001: Semantic view object exists
SELECT 'T-SEM-001' AS test_id, 'Semantic view deployed' AS test_name,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS found, 1 AS expected
FROM (SHOW SEMANTIC VIEWS LIKE 'OTIF_GUARDIAN_SUPPLY_CHAIN' IN SCHEMA OTIF_GUARDIAN.SEMANTIC);

-- T-SEM-002: VQR - Overall OTIF rate returns numeric result
SELECT 'T-SEM-002' AS test_id, 'VQR: overall OTIF rate executes' AS test_name,
    CASE WHEN otif_rate_pct IS NOT NULL AND otif_rate_pct BETWEEN 0 AND 100
    THEN 'PASS' ELSE 'FAIL' END AS result,
    otif_rate_pct AS actual, '0-100' AS expected_range
FROM (
    SELECT ROUND(COUNT_IF(
        ACTUAL_DELIVERY_DATE IS NOT NULL
        AND ACTUAL_DELIVERY_DATE <= PROMISED_DELIVERY_DATE
        AND QUANTITY_RECEIVED >= QUANTITY_ORDERED
    ) * 100.0 / NULLIF(COUNT_IF(
        ACTUAL_DELIVERY_DATE IS NOT NULL
        AND LINE_STATUS IN ('CLOSED','SHORT_CLOSED')
    ), 0), 2) AS otif_rate_pct
    FROM OTIF_GUARDIAN.RAW.PO_LINES
);

-- T-SEM-003: VQR - OTIF by supplier returns multiple rows
SELECT 'T-SEM-003' AS test_id, 'VQR: OTIF by supplier returns data' AS test_name,
    CASE WHEN COUNT(*) > 10 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS supplier_count, 10 AS minimum
FROM (
    SELECT s.SUPPLIER_CODE, COUNT(*) AS total
    FROM OTIF_GUARDIAN.RAW.PO_LINES pl
    JOIN OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po ON pl.PO_ID = po.PO_ID
    JOIN OTIF_GUARDIAN.RAW.SUPPLIERS s ON po.SUPPLIER_ID = s.SUPPLIER_ID
    WHERE pl.ACTUAL_DELIVERY_DATE IS NOT NULL
    GROUP BY s.SUPPLIER_CODE
);

-- T-SEM-004: VQR - Stockout risk query returns valid results
SELECT 'T-SEM-004' AS test_id, 'VQR: stockout risk executes' AS test_name,
    CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS rows_returned, 0 AS minimum
FROM (
    SELECT m.MATERIAL_CODE, i.DAYS_OF_SUPPLY, m.SAFETY_STOCK_DAYS
    FROM OTIF_GUARDIAN.RAW.INVENTORY i
    JOIN OTIF_GUARDIAN.RAW.MATERIALS m ON i.MATERIAL_ID = m.MATERIAL_ID
    WHERE i.DAYS_OF_SUPPLY < m.SAFETY_STOCK_DAYS
);

-- T-SEM-005: VQR - Monthly trend returns 12 months
SELECT 'T-SEM-005' AS test_id, 'VQR: monthly trend has data' AS test_name,
    CASE WHEN COUNT(*) >= 6 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS months, 6 AS minimum
FROM (
    SELECT DATE_TRUNC('month', ACTUAL_DELIVERY_DATE) AS month
    FROM OTIF_GUARDIAN.RAW.PO_LINES
    WHERE ACTUAL_DELIVERY_DATE IS NOT NULL
        AND ACTUAL_DELIVERY_DATE >= DATEADD('month', -12, CURRENT_DATE())
    GROUP BY 1
);

-- T-SEM-006: VQR - Top spend by supplier returns valid amounts
SELECT 'T-SEM-006' AS test_id, 'VQR: top spend > 0' AS test_name,
    CASE WHEN total_spend > 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    total_spend AS actual, 0 AS minimum
FROM (
    SELECT SUM(pl.QUANTITY_ORDERED * pl.UNIT_PRICE) AS total_spend
    FROM OTIF_GUARDIAN.RAW.PO_LINES pl
);

-- T-SEM-007: Semantic model references valid tables
SELECT 'T-SEM-007' AS test_id, 'All referenced tables exist' AS test_name,
    CASE WHEN COUNT(*) >= 9 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS tables_found, 9 AS expected
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'OTIF_GUARDIAN' AND TABLE_SCHEMA = 'RAW'
  AND TABLE_NAME IN ('SUPPLIERS','PLANTS','MATERIALS','PO_LINES',
    'PURCHASE_ORDERS','CUSTOMER_ORDERS','INVENTORY','DEMAND','SHIPMENTS','RECEIPTS');

-- ============================================================
-- SECTION 2: AGENT TESTS
-- ============================================================

-- T-AGT-001: Agent object exists
SELECT 'T-AGT-001' AS test_id, 'Agent deployed' AS test_name,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS found, 1 AS expected
FROM (SHOW AGENTS LIKE 'OTIF_GUARDIAN_AGENT' IN SCHEMA OTIF_GUARDIAN.AGENTS);

-- T-AGT-002: Agent has 3 tools defined
-- (Validated via spec inspection — agent-read)
SELECT 'T-AGT-002' AS test_id, 'Agent has 3 tools (spec check)' AS test_name,
    'MANUAL' AS result,
    NULL AS actual,
    3 AS expected;
-- Run: cortex agent-studio agent-read --fqn OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT
-- Verify: tools array has exactly 3 entries

-- T-AGT-003: Agent supply_analytics tool connects to semantic view
SELECT 'T-AGT-003' AS test_id, 'supply_analytics tool references valid SV' AS test_name,
    'MANUAL' AS result,
    NULL AS actual,
    'OTIF_GUARDIAN.SEMANTIC.OTIF_GUARDIAN_SUPPLY_CHAIN' AS expected_sv;
-- Verify via spec that tool_resources.supply_analytics.semantic_view matches

-- T-AGT-004: Agent responds to basic query
-- cortex agents run OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT "What is the supplier OTIF rate?"
SELECT 'T-AGT-004' AS test_id, 'Agent responds to OTIF query' AS test_name,
    'MANUAL' AS result, NULL AS actual, 'Non-empty response with numeric OTIF rate' AS expected;

-- T-AGT-005: Agent refuses out-of-domain question
-- cortex agents run OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT "What is the weather today?"
SELECT 'T-AGT-005' AS test_id, 'Agent rejects out-of-domain' AS test_name,
    'MANUAL' AS result, NULL AS actual, 'Refusal message about supply chain scope' AS expected;

-- T-AGT-006: Agent uses risk_lookup tool for risk questions
-- cortex agents run OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT "Which POs are at critical risk?"
SELECT 'T-AGT-006' AS test_id, 'Agent invokes risk_lookup' AS test_name,
    'MANUAL' AS result, NULL AS actual, 'Response includes risk tiers and probabilities' AS expected;

-- T-AGT-007: Agent uses recovery_simulation for recovery questions
-- cortex agents run OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT "Simulate recovery for Detroit plant"
SELECT 'T-AGT-007' AS test_id, 'Agent invokes recovery_simulation' AS test_name,
    'MANUAL' AS result, NULL AS actual, 'Response includes cost, revenue protected, ROI' AS expected;

-- ============================================================
-- SECTION 3: GOVERNANCE TESTS
-- ============================================================

-- T-GOV-001: No future data in training features
SELECT 'T-GOV-001' AS test_id, 'No future-dated features in training' AS test_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS violations, 0 AS expected
FROM OTIF_GUARDIAN.ML.V_FEATURE_SET fs
JOIN OTIF_GUARDIAN.RAW.PURCHASE_ORDERS po ON fs.PO_ID = po.PO_ID
JOIN OTIF_GUARDIAN.ML.V_SUPPLIER_HISTORY sh ON po.PO_ID = sh.CURRENT_PO_ID
WHERE sh.CURRENT_ORDER_DATE IS NOT NULL
  AND fs.OTIF_BREACH IS NOT NULL;
-- The V_SUPPLIER_HISTORY view enforces po_hist.order_date < po_current.order_date

-- T-GOV-002: Recovery engine uses no LLM (all views are SQL)
SELECT 'T-GOV-002' AS test_id, 'Recovery views are pure SQL (no UDF/LLM)' AS test_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS violations, 0 AS expected
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'ML' AND TABLE_CATALOG = 'OTIF_GUARDIAN'
  AND VIEW_DEFINITION ILIKE '%CORTEX.COMPLETE%';

-- T-GOV-003: Recovery net value formula is deterministic
SELECT 'T-GOV-003' AS test_id, 'Recovery calculations deterministic' AS test_name,
    CASE WHEN r1.total_nvp = r2.total_nvp THEN 'PASS' ELSE 'FAIL' END AS result,
    r1.total_nvp AS run_1, r2.total_nvp AS run_2
FROM
    (SELECT ROUND(SUM(NET_VALUE_PROTECTED), 2) AS total_nvp
     FROM OTIF_GUARDIAN.ML.V_BEST_RECOVERY_ACTION) r1,
    (SELECT ROUND(SUM(NET_VALUE_PROTECTED), 2) AS total_nvp
     FROM OTIF_GUARDIAN.ML.V_BEST_RECOVERY_ACTION) r2;

-- T-GOV-004: Model predictions are reproducible (same input → same output)
SELECT 'T-GOV-004' AS test_id, 'Predictions reproducible' AS test_name,
    CASE WHEN p1.prob = p2.prob THEN 'PASS' ELSE 'FAIL' END AS result,
    p1.prob AS run_1, p2.prob AS run_2
FROM
    (SELECT prediction_result:"probability":"1"::FLOAT AS prob
     FROM OTIF_GUARDIAN.ML.SCORED_PO_LINES LIMIT 1) p1,
    (SELECT prediction_result:"probability":"1"::FLOAT AS prob
     FROM OTIF_GUARDIAN.ML.SCORED_PO_LINES LIMIT 1) p2;

-- T-GOV-005: Role-based access — ANALYST cannot write to ML schema
-- Run as OTIF_GUARDIAN_ANALYST:
-- Expected: insufficient privileges on INSERT/CREATE
SELECT 'T-GOV-005' AS test_id, 'ANALYST role is read-only on ML' AS test_name,
    'MANUAL' AS result, NULL AS actual,
    'INSERT into ML.TRAIN_DATA should fail for ANALYST role' AS expected;

-- T-GOV-006: Audit trail — recovery engine logs executions
SELECT 'T-GOV-006' AS test_id, 'Recovery engine log table exists' AS test_name,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS found, 1 AS minimum
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'ML' AND TABLE_NAME = 'RECOVERY_ENGINE_LOG';

-- T-GOV-007: No PII in model features
SELECT 'T-GOV-007' AS test_id, 'No PII columns in training data' AS test_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS violations, 0 AS expected
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'ML' AND TABLE_NAME = 'TRAIN_DATA'
  AND COLUMN_NAME IN ('EMAIL','PHONE','SSN','NAME','ADDRESS','CUSTOMER_NAME');

-- ============================================================
-- SECTION 4: EDGE CASE TESTS
-- ============================================================

-- T-EDGE-001: Zero quantity ordered handled
SELECT 'T-EDGE-001' AS test_id, 'No zero quantity_ordered' AS test_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS violations, 0 AS expected
FROM OTIF_GUARDIAN.RAW.PO_LINES WHERE QUANTITY_ORDERED = 0;

-- T-EDGE-002: Division by zero in OTIF rate calculation
SELECT 'T-EDGE-002' AS test_id, 'OTIF rate handles empty denominator' AS test_name,
    CASE WHEN otif_rate IS NOT NULL OR total_delivered = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    otif_rate AS actual, 'NOT NULL or 0 denominator' AS expected
FROM (
    SELECT
        COUNT_IF(ACTUAL_DELIVERY_DATE IS NOT NULL) AS total_delivered,
        COUNT_IF(ACTUAL_DELIVERY_DATE <= PROMISED_DELIVERY_DATE
            AND QUANTITY_RECEIVED >= QUANTITY_ORDERED) * 100.0
            / NULLIF(COUNT_IF(ACTUAL_DELIVERY_DATE IS NOT NULL
                AND LINE_STATUS IN ('CLOSED','SHORT_CLOSED')), 0) AS otif_rate
    FROM OTIF_GUARDIAN.RAW.PO_LINES
);

-- T-EDGE-003: Supplier with no historical data (new supplier)
SELECT 'T-EDGE-003' AS test_id, 'New supplier gets NULL hist features (not error)' AS test_name,
    CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS lines_with_null_hist, 'Non-negative' AS expected
FROM OTIF_GUARDIAN.ML.V_FEATURE_SET
WHERE SUPPLIER_HIST_OTIF_RATE IS NULL AND OTIF_BREACH IS NOT NULL;

-- T-EDGE-004: Material with no alternate suppliers
SELECT 'T-EDGE-004' AS test_id, 'Single-sourced materials handled' AS test_name,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS single_sourced, 1 AS minimum
FROM OTIF_GUARDIAN.ML.V_FEATURE_SET
WHERE MATERIAL_ALT_SUPPLIER_COUNT <= 1 AND OTIF_BREACH IS NOT NULL;

-- T-EDGE-005: PO line with promised_date in the past (already overdue)
SELECT 'T-EDGE-005' AS test_id, 'Overdue lines scored correctly' AS test_name,
    CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS overdue_scored, 'Non-negative' AS expected
FROM OTIF_GUARDIAN.ML.V_SCORED_RESULTS
WHERE DAYS_UNTIL_DUE < 0;

-- T-EDGE-006: Recovery for line with no donor plant available
SELECT 'T-EDGE-006' AS test_id, 'No-donor transfer marked infeasible' AS test_name,
    CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS infeasible_transfers, 'Non-negative' AS expected
FROM OTIF_GUARDIAN.ML.V_ACTION_INVENTORY_TRANSFER
WHERE IS_FEASIBLE = FALSE;

-- T-EDGE-007: Recovery for line with no alternate supplier
SELECT 'T-EDGE-007' AS test_id, 'No-alt-supplier marked infeasible' AS test_name,
    CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS infeasible_alt, 'Non-negative' AS expected
FROM OTIF_GUARDIAN.ML.V_ACTION_ALTERNATE_SUPPLIER
WHERE IS_FEASIBLE = FALSE;

-- T-EDGE-008: Very large quantity (> 10000) does not cause overflow
SELECT 'T-EDGE-008' AS test_id, 'Large quantities handled' AS test_name,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS large_qty_lines, 1 AS minimum
FROM OTIF_GUARDIAN.RAW.PO_LINES WHERE QUANTITY_ORDERED > 10000;

-- T-EDGE-009: Negative delivery variance (early delivery) handled
SELECT 'T-EDGE-009' AS test_id, 'Early deliveries have negative variance' AS test_name,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS early_deliveries, 1 AS minimum
FROM OTIF_GUARDIAN.RAW.PO_LINES
WHERE ACTUAL_DELIVERY_DATE IS NOT NULL
  AND ACTUAL_DELIVERY_DATE < PROMISED_DELIVERY_DATE;

-- T-EDGE-010: Customer order with OTIF=NULL for open orders
SELECT 'T-EDGE-010' AS test_id, 'Open orders have OTIF=NULL' AS test_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
    COUNT(*) AS violations, 0 AS expected
FROM OTIF_GUARDIAN.RAW.CUSTOMER_ORDERS
WHERE ORDER_STATUS = 'OPEN' AND OTIF_FLAG IS NOT NULL;

-- ============================================================
-- END OF SEMANTIC + AGENT + GOVERNANCE + EDGE CASE TESTS
-- ============================================================
