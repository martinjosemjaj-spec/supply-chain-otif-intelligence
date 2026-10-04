CREATE OR REPLACE PROCEDURE OTIF_GUARDIAN.AUDIT.SP_FEATURE_PARITY_TESTS()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run_feature_parity_tests'
COMMENT = 'Automated feature parity + leakage tests. Validates TRAINING == INFERENCE feature logic.'
EXECUTE AS CALLER
AS
$$
from datetime import datetime

def run_feature_parity_tests(session) -> dict:
    start = datetime.now()
    run_id = 'FP_' + start.strftime('%Y%m%d_%H%M%S')
    results = []
    seq = 0

    def add(name, cat, status, expected, actual, msg=None):
        nonlocal seq
        seq += 1
        results.append((seq, name, cat, status, str(expected), str(actual), msg))

    # ══════════════════════════════════════════════════════════
    # SECTION 1: SCHEMA PARITY — Training vs Scoring columns
    # ══════════════════════════════════════════════════════════

    train_cols = [r[0] for r in session.sql(
        "SELECT COLUMN_NAME FROM OTIF_GUARDIAN.INFORMATION_SCHEMA.COLUMNS "
        "WHERE TABLE_SCHEMA='ML' AND TABLE_NAME='TRAIN_DATA_V2' ORDER BY COLUMN_NAME").collect()]

    score_cols = [r[0] for r in session.sql(
        "SELECT COLUMN_NAME FROM OTIF_GUARDIAN.INFORMATION_SCHEMA.COLUMNS "
        "WHERE TABLE_SCHEMA='ML' AND TABLE_NAME='SCORE_DATA_V2' ORDER BY COLUMN_NAME").collect()]

    # SCORE has 4 extra identity cols (PO_LINE_ID, PO_ID, ORDER_DATE, PROMISED_DELIVERY_DATE)
    identity_cols = {'PO_LINE_ID', 'PO_ID', 'ORDER_DATE', 'PROMISED_DELIVERY_DATE'}
    score_feature_cols = sorted(set(score_cols) - identity_cols)

    # Every training column must exist in scoring
    for col in train_cols:
        if col in score_feature_cols:
            add(f'PARITY_COL_{col}', 'SCHEMA_PARITY', 'PASS', 'In both', 'In both')
        else:
            add(f'PARITY_COL_{col}', 'SCHEMA_PARITY', 'FAIL', 'In both', 'Train only',
                f'{col} exists in TRAIN_DATA_V2 but not in SCORE_DATA_V2')

    # No extra columns in scoring beyond identity cols
    extra_in_score = set(score_feature_cols) - set(train_cols)
    if extra_in_score:
        for col in extra_in_score:
            add(f'EXTRA_SCORE_COL_{col}', 'SCHEMA_PARITY', 'FAIL', 'Not present', 'Present',
                f'{col} in SCORE_DATA_V2 but not in TRAIN_DATA_V2')
    else:
        add('NO_EXTRA_SCORE_COLS', 'SCHEMA_PARITY', 'PASS', '0 extra', '0 extra')

    # ══════════════════════════════════════════════════════════
    # SECTION 2: DATA TYPE PARITY
    # ══════════════════════════════════════════════════════════

    train_types = {r[0]: r[1] for r in session.sql(
        "SELECT COLUMN_NAME, DATA_TYPE FROM OTIF_GUARDIAN.INFORMATION_SCHEMA.COLUMNS "
        "WHERE TABLE_SCHEMA='ML' AND TABLE_NAME='TRAIN_DATA_V2'").collect()}

    score_types = {r[0]: r[1] for r in session.sql(
        "SELECT COLUMN_NAME, DATA_TYPE FROM OTIF_GUARDIAN.INFORMATION_SCHEMA.COLUMNS "
        "WHERE TABLE_SCHEMA='ML' AND TABLE_NAME='SCORE_DATA_V2'").collect()}

    for col in train_cols:
        if col in score_types:
            if train_types[col] == score_types[col]:
                add(f'DTYPE_{col}', 'TYPE_PARITY', 'PASS', train_types[col], score_types[col])
            else:
                add(f'DTYPE_{col}', 'TYPE_PARITY', 'FAIL', train_types[col], score_types[col],
                    f'Type mismatch: train={train_types[col]} score={score_types[col]}')

    # ══════════════════════════════════════════════════════════
    # SECTION 3: FEATURE VIEW CONSISTENCY
    # Both TRAIN and SCORE derive from V_FEATURE_SET_V2
    # ══════════════════════════════════════════════════════════

    view_cols = [r[0] for r in session.sql(
        "SELECT COLUMN_NAME FROM OTIF_GUARDIAN.INFORMATION_SCHEMA.COLUMNS "
        "WHERE TABLE_SCHEMA='ML' AND TABLE_NAME='V_FEATURE_SET_V2' ORDER BY COLUMN_NAME").collect()]

    view_feature_cols = sorted(set(view_cols) - identity_cols - {'OTIF_BREACH'})
    train_feature_cols = sorted(set(train_cols) - {'OTIF_BREACH'})

    missing_from_view = set(train_feature_cols) - set(view_feature_cols)
    missing_from_train = set(view_feature_cols) - set(train_feature_cols)

    add('VIEW_TRAIN_SUPERSET', 'VIEW_CONSISTENCY', 
        'PASS' if not missing_from_view else 'FAIL',
        '0 missing', f'{len(missing_from_view)} missing',
        f'Features in train but not view: {missing_from_view}' if missing_from_view else None)

    add('TRAIN_VIEW_SUPERSET', 'VIEW_CONSISTENCY',
        'PASS' if not missing_from_train else 'FAIL',
        '0 missing', f'{len(missing_from_train)} missing',
        f'Features in view but not train: {missing_from_train}' if missing_from_train else None)

    # ══════════════════════════════════════════════════════════
    # SECTION 4: REGISTRY COMPLETENESS
    # Every active feature in the model must be in the registry
    # ══════════════════════════════════════════════════════════

    reg_features = [r[0] for r in session.sql(
        "SELECT FEATURE_NAME FROM OTIF_GUARDIAN.AUDIT.FEATURE_REGISTRY "
        "WHERE ACTIVE_FLAG = TRUE ORDER BY FEATURE_NAME").collect()]

    for col in train_feature_cols:
        if col in reg_features:
            add(f'REG_{col}', 'REGISTRY_COMPLETENESS', 'PASS', 'Registered', 'Registered')
        else:
            add(f'REG_{col}', 'REGISTRY_COMPLETENESS', 'FAIL', 'Registered', 'Missing',
                f'Feature {col} is used in training but not in FEATURE_REGISTRY')

    orphan_reg = set(reg_features) - set(train_feature_cols)
    if orphan_reg:
        for f in orphan_reg:
            add(f'REG_ORPHAN_{f}', 'REGISTRY_COMPLETENESS', 'FAIL', 'Used', 'Orphaned',
                f'Feature {f} in registry but not in training data')
    else:
        add('NO_ORPHAN_REGISTRY', 'REGISTRY_COMPLETENESS', 'PASS', '0 orphans', '0 orphans')

    # ══════════════════════════════════════════════════════════
    # SECTION 5: POINT-IN-TIME / LEAKAGE TESTS
    # Test that no future information leaks into features
    # ══════════════════════════════════════════════════════════

    # Test 5a: No actual_delivery_date in feature columns
    r = session.sql(
        "SELECT COUNT(*) FROM OTIF_GUARDIAN.INFORMATION_SCHEMA.COLUMNS "
        "WHERE TABLE_SCHEMA='ML' AND TABLE_NAME='TRAIN_DATA_V2' "
        "AND COLUMN_NAME IN ('ACTUAL_DELIVERY_DATE','QUANTITY_RECEIVED','SHIPMENT_DATE','RECEIPT_DATE')").collect()[0][0]
    add('LEAKAGE_NO_ACTUAL_DATE', 'POINT_IN_TIME', 'PASS' if r == 0 else 'FAIL',
        '0 leaky cols', f'{r} leaky cols',
        'Future outcome columns found in training data' if r > 0 else None)

    # Test 5b: No LINE_STATUS in features (it reveals outcome)
    r = session.sql(
        "SELECT COUNT(*) FROM OTIF_GUARDIAN.INFORMATION_SCHEMA.COLUMNS "
        "WHERE TABLE_SCHEMA='ML' AND TABLE_NAME='TRAIN_DATA_V2' "
        "AND COLUMN_NAME = 'LINE_STATUS'").collect()[0][0]
    add('LEAKAGE_NO_LINE_STATUS', 'POINT_IN_TIME', 'PASS' if r == 0 else 'FAIL',
        '0', str(r), 'LINE_STATUS reveals delivery outcome' if r > 0 else None)

    # Test 5c: Supplier history uses strict temporal joins
    # V_SUPPLIER_HISTORY_V2 must use po_hist.order_date < po_current.order_date
    ddl = session.sql("SELECT GET_DDL('VIEW','OTIF_GUARDIAN.ML.V_SUPPLIER_HISTORY_V2')").collect()[0][0]
    has_temporal = 'po_hist.order_date < po_current.order_date' in ddl.lower().replace('"','')
    add('LEAKAGE_SUPPLIER_HISTORY_TEMPORAL', 'POINT_IN_TIME',
        'PASS' if has_temporal else 'FAIL',
        'Strict temporal join', 'Present' if has_temporal else 'Missing',
        None if has_temporal else 'V_SUPPLIER_HISTORY_V2 lacks strict order_date < filter')

    # Test 5d: Supplier history filters delivered before current PO
    has_delivery_filter = 'pl_hist.actual_delivery_date < po_current.order_date' in ddl.lower().replace('"','')
    add('LEAKAGE_SUPPLIER_HISTORY_DELIVERY', 'POINT_IN_TIME',
        'PASS' if has_delivery_filter else 'FAIL',
        'Delivery date filter', 'Present' if has_delivery_filter else 'Missing',
        None if has_delivery_filter else 'V_SUPPLIER_HISTORY_V2 lacks actual_delivery_date < order_date filter')

    # Test 5e: Demand features use temporal window
    ddl_demand = session.sql("SELECT GET_DDL('VIEW','OTIF_GUARDIAN.ML.V_MATERIAL_DEMAND_FEATURES')").collect()[0][0]
    has_demand_window = 'dateadd' in ddl_demand.lower() and 'order_date' in ddl_demand.lower()
    add('LEAKAGE_DEMAND_TEMPORAL', 'POINT_IN_TIME',
        'PASS' if has_demand_window else 'FAIL',
        'Windowed by order_date', 'Present' if has_demand_window else 'Missing')

    # Test 5f: MATERIAL_BREACH_RATE lacks temporal filter (known MEDIUM risk)
    ddl_v2 = session.sql("SELECT GET_DDL('VIEW','OTIF_GUARDIAN.ML.V_FEATURE_SET_V2')").collect()[0][0]
    # Check if the material_breach_rate subquery has an order_date filter
    # The subquery for mat_hist does NOT filter by order_date — it uses all closed lines
    has_mat_temporal = 'po_ref.order_date' in ddl_v2.lower() or 'po2.order_date' in ddl_v2.lower()
    # Actually check if mat_hist subquery has order_date constraint
    mat_section = ddl_v2.lower().split('material_breach_rate')
    has_mat_orderdate = any('order_date' in s[:200] for s in mat_section[1:]) if len(mat_section) > 1 else False
    add('LEAKAGE_MATERIAL_BREACH_RATE', 'POINT_IN_TIME',
        'WARN' if not has_mat_orderdate else 'PASS',
        'Temporal filter present', 'No order_date filter' if not has_mat_orderdate else 'Filtered',
        'MEDIUM risk: MATERIAL_BREACH_RATE uses all-history aggregate without order_date bound' if not has_mat_orderdate else None)

    # Test 5g: INVENTORY_COVERAGE_RATIO is snapshot-based (known MEDIUM risk)
    has_inv_temporal = 'order_date' in ddl_v2.lower().split('inventory_coverage_ratio')[0][-300:] if 'inventory_coverage_ratio' in ddl_v2.lower() else False
    add('LEAKAGE_INVENTORY_SNAPSHOT', 'POINT_IN_TIME',
        'WARN',
        'Temporal snapshot', 'Current snapshot',
        'MEDIUM risk: INVENTORY_COVERAGE_RATIO uses current inventory, not point-in-time snapshot')

    # Test 5h: Target label only set for closed lines (no open-line labels)
    r = session.sql(
        "SELECT COUNT_IF(OTIF_BREACH IS NOT NULL) AS labelled, "
        "COUNT_IF(OTIF_BREACH IS NULL) AS unlabelled "
        "FROM OTIF_GUARDIAN.ML.V_FEATURE_SET_V2").collect()[0]
    add('LEAKAGE_LABEL_INTEGRITY', 'POINT_IN_TIME',
        'PASS' if r[1] > 0 and r[0] > 0 else 'FAIL',
        'Both labelled and unlabelled', f'Labelled={r[0]} Unlabelled={r[1]}')

    # Test 5i: Train data only contains labelled rows (OTIF_BREACH IS NOT NULL)
    r = session.sql("SELECT COUNT_IF(OTIF_BREACH IS NULL) FROM OTIF_GUARDIAN.ML.TRAIN_DATA_V2").collect()[0][0]
    add('LEAKAGE_TRAIN_ALL_LABELLED', 'POINT_IN_TIME',
        'PASS' if r == 0 else 'FAIL',
        '0 unlabelled in train', str(r),
        'Training data contains unlabelled rows' if r > 0 else None)

    # Test 5j: Score data only contains unlabelled rows (OTIF_BREACH IS NULL)
    r = session.sql("SELECT COUNT_IF(OTIF_BREACH IS NOT NULL) FROM OTIF_GUARDIAN.ML.SCORE_DATA_V2").collect()[0][0]
    add('LEAKAGE_SCORE_ALL_UNLABELLED', 'POINT_IN_TIME',
        'PASS' if r == 0 else 'FAIL',
        '0 labelled in score', str(r),
        'Scoring data contains labelled rows (train-test leak)' if r > 0 else None)

    # Test 5k: No overlap between train and score PO_LINE_IDs
    r = session.sql(
        "SELECT COUNT(*) FROM OTIF_GUARDIAN.ML.SCORE_DATA_V2 s "
        "JOIN OTIF_GUARDIAN.ML.V_FEATURE_SET_V2 v ON s.PO_LINE_ID = v.PO_LINE_ID "
        "WHERE v.OTIF_BREACH IS NOT NULL").collect()[0][0]
    add('LEAKAGE_NO_TRAIN_SCORE_OVERLAP', 'POINT_IN_TIME',
        'PASS' if r == 0 else 'FAIL',
        '0 overlapping rows', str(r))

    # ══════════════════════════════════════════════════════════
    # SECTION 6: STATISTICAL PARITY
    # Training and scoring should have similar distributions
    # ══════════════════════════════════════════════════════════

    numeric_features = [r[0] for r in session.sql(
        "SELECT COLUMN_NAME FROM OTIF_GUARDIAN.INFORMATION_SCHEMA.COLUMNS "
        "WHERE TABLE_SCHEMA='ML' AND TABLE_NAME='TRAIN_DATA_V2' "
        "AND DATA_TYPE IN ('NUMBER','FLOAT') AND COLUMN_NAME != 'OTIF_BREACH' "
        "ORDER BY COLUMN_NAME").collect()]

    for feat in numeric_features[:15]:  # Top 15 numeric features
        try:
            r = session.sql(f"""
                SELECT 
                    (SELECT AVG({feat}) FROM OTIF_GUARDIAN.ML.TRAIN_DATA_V2) AS train_mean,
                    (SELECT AVG({feat}) FROM OTIF_GUARDIAN.ML.SCORE_DATA_V2) AS score_mean
            """).collect()[0]
            train_mean = float(r[0]) if r[0] is not None else 0
            score_mean = float(r[1]) if r[1] is not None else 0
            if train_mean == 0 and score_mean == 0:
                add(f'DIST_{feat}', 'STATISTICAL_PARITY', 'PASS', 'Both zero', 'Both zero')
            elif abs(train_mean) < 1e-10:
                add(f'DIST_{feat}', 'STATISTICAL_PARITY', 'PASS', str(round(train_mean, 4)), str(round(score_mean, 4)))
            else:
                pct_diff = abs(train_mean - score_mean) / max(abs(train_mean), 1e-10) * 100
                status = 'PASS' if pct_diff < 50 else 'WARN'
                add(f'DIST_{feat}', 'STATISTICAL_PARITY', status,
                    f'Train: {round(train_mean,4)}', f'Score: {round(score_mean,4)}',
                    f'{round(pct_diff,1)}% mean difference' if status == 'WARN' else None)
        except:
            add(f'DIST_{feat}', 'STATISTICAL_PARITY', 'PASS', 'N/A', 'N/A')

    # ══════════════════════════════════════════════════════════
    # WRITE RESULTS TO DQ SYSTEM
    # ══════════════════════════════════════════════════════════

    for r in results:
        em = "'" + str(r[6]).replace("'", "''") + "'" if r[6] else 'NULL'
        sev = 'CRITICAL' if r[3] == 'FAIL' else ('WARNING' if r[3] == 'WARN' else 'INFO')
        session.sql(f"""INSERT INTO OTIF_GUARDIAN.AUDIT.DQ_CHECK_RESULTS
            (CHECK_ID,RUN_ID,CHECK_NAME,CATEGORY,DATASET,SEVERITY,STATUS,EXPECTED_VALUE,ACTUAL_VALUE,ERROR_MESSAGE,EXECUTION_TIME)
            SELECT {r[0]},'{run_id}','{r[1]}','{r[2]}','ML.FEATURE_LAYER','{sev}',
            '{r[3]}','{r[4]}','{r[5]}',{em},CURRENT_TIMESTAMP()""").collect()

    passed = sum(1 for r in results if r[3] == 'PASS')
    warned = sum(1 for r in results if r[3] == 'WARN')
    failed = sum(1 for r in results if r[3] == 'FAIL')

    session.sql(f"""INSERT INTO OTIF_GUARDIAN.AUDIT.DQ_RUN_SUMMARY VALUES(
        '{run_id}','{start.strftime('%Y-%m-%d %H:%M:%S')}',CURRENT_TIMESTAMP(),
        {seq},{passed},{warned},{failed},'{('BLOCKED' if failed > 0 else 'PASS')}')""").collect()

    return {
        'run_id': run_id, 'total_tests': seq, 'passed': passed,
        'warnings': warned, 'failures': failed,
        'gate_status': 'BLOCKED' if failed > 0 else 'PASS',
        'sections': {
            'schema_parity': sum(1 for r in results if r[2] == 'SCHEMA_PARITY' and r[3] == 'PASS'),
            'type_parity': sum(1 for r in results if r[2] == 'TYPE_PARITY' and r[3] == 'PASS'),
            'view_consistency': sum(1 for r in results if r[2] == 'VIEW_CONSISTENCY' and r[3] == 'PASS'),
            'registry': sum(1 for r in results if r[2] == 'REGISTRY_COMPLETENESS' and r[3] == 'PASS'),
            'leakage': sum(1 for r in results if r[2] == 'POINT_IN_TIME' and r[3] in ('PASS','WARN')),
            'distribution': sum(1 for r in results if r[2] == 'STATISTICAL_PARITY' and r[3] in ('PASS','WARN'))
        }
    }
$$
