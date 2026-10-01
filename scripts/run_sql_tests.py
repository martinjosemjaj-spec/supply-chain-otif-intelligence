#!/usr/bin/env python3
"""
OTIF Guardian - SQL Test Runner
Executes SQL test files against Snowflake and reports PASS/FAIL results.

Usage:
    python scripts/run_sql_tests.py --file tests/test_sql.sql
    python scripts/run_sql_tests.py --file tests/test_ml.sql --filter T-ML-001,T-ML-010
    python scripts/run_sql_tests.py --all
"""

import argparse
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

try:
    import snowflake.connector
except ImportError:
    print("ERROR: snowflake-connector-python required. Run: pip install -r requirements.txt")
    sys.exit(1)


def get_connection():
    return snowflake.connector.connect(
        account=os.environ.get("SNOWFLAKE_ACCOUNT", ""),
        user=os.environ.get("SNOWFLAKE_USER", ""),
        password=os.environ.get("SNOWFLAKE_PASSWORD", ""),
        database=os.environ.get("SNOWFLAKE_DATABASE", "OTIF_GUARDIAN"),
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "OTIF_GUARDIAN_WH"),
        role=os.environ.get("SNOWFLAKE_ROLE", "OTIF_GUARDIAN_ADMIN"),
        authenticator=os.environ.get("SNOWFLAKE_AUTHENTICATOR", "externalbrowser"),
    )


def run_sql_tests(conn, filepath, filter_ids=None):
    """Run SQL test file, return list of test results."""
    text = filepath.read_text(encoding="utf-8")
    database = os.environ.get("SNOWFLAKE_DATABASE", "OTIF_GUARDIAN")
    if database != "OTIF_GUARDIAN":
        text = text.replace("OTIF_GUARDIAN.", f"{database}.")
        text = text.replace("USE DATABASE OTIF_GUARDIAN", f"USE DATABASE {database}")

    statements = [s.strip() for s in text.split(";") if s.strip()]
    cur = conn.cursor()
    results = []

    try:
        for stmt in statements:
            if not stmt or stmt.startswith("--"):
                continue
            try:
                cur.execute(stmt)
                if stmt.upper().startswith("SELECT"):
                    rows = cur.fetchall()
                    cols = [d[0] for d in cur.description] if cur.description else []
                    if "RESULT" in cols:
                        ridx = cols.index("RESULT")
                        tidx = cols.index("TEST_ID") if "TEST_ID" in cols else None
                        nidx = cols.index("TEST_NAME") if "TEST_NAME" in cols else None
                        for row in rows:
                            test_id = row[tidx] if tidx is not None else "unknown"
                            test_name = row[nidx] if nidx is not None else ""
                            result = row[ridx]
                            if filter_ids and test_id not in filter_ids:
                                continue
                            results.append({
                                "test_id": test_id,
                                "test_name": test_name,
                                "result": result,
                            })
            except Exception as e:
                if "USE " in stmt.upper() or "SHOW " in stmt.upper():
                    continue
                results.append({
                    "test_id": "SQL_ERROR",
                    "test_name": str(e)[:100],
                    "result": "FAIL",
                })
    finally:
        cur.close()

    return results


def main():
    parser = argparse.ArgumentParser(description="OTIF Guardian SQL Test Runner")
    parser.add_argument("--file", help="SQL test file to run")
    parser.add_argument("--all", action="store_true", help="Run all SQL test files")
    parser.add_argument("--filter", help="Comma-separated test IDs to include")
    parser.add_argument("--json", action="store_true", help="Output results as JSON")
    args = parser.parse_args()

    test_files = []
    if args.all:
        test_dir = ROOT / "tests"
        test_files = sorted(test_dir.glob("*.sql"))
    elif args.file:
        test_files = [ROOT / args.file]
    else:
        parser.error("Specify --file or --all")

    filter_ids = set(args.filter.split(",")) if args.filter else None

    conn = get_connection()
    all_results = []

    try:
        for tf in test_files:
            if not tf.exists():
                print(f"File not found: {tf}")
                continue
            print(f"\nRunning: {tf.name}")
            print("-" * 50)
            results = run_sql_tests(conn, tf, filter_ids)
            all_results.extend(results)

            for r in results:
                status = r["result"]
                icon = "PASS" if status == "PASS" else ("SKIP" if status == "MANUAL" else "FAIL")
                print(f"  [{icon}] {r['test_id']}: {r['test_name']}")
    finally:
        conn.close()

    # Summary
    passed = sum(1 for r in all_results if r["result"] == "PASS")
    failed = sum(1 for r in all_results if r["result"] == "FAIL")
    manual = sum(1 for r in all_results if r["result"] == "MANUAL")
    total = len(all_results)

    print(f"\n{'='*50}")
    print(f"TOTAL: {total} | PASS: {passed} | FAIL: {failed} | MANUAL: {manual}")
    print(f"{'='*50}")

    if args.json:
        print(json.dumps({"tests": all_results, "passed": passed, "failed": failed}, indent=2))

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
