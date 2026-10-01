#!/usr/bin/env python3
"""
OTIF Guardian - Snowflake Validation Runner
Calls Snowflake stored procedures and reports PASS/FAIL for CI gates.

Usage:
    python scripts/run_snowflake_validations.py --gate security_tests
    python scripts/run_snowflake_validations.py --gate xgboost_validation
    python scripts/run_snowflake_validations.py --all-required --env PROD
    python scripts/run_snowflake_validations.py --list
"""

import argparse
import json
import os
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "config" / "environments.yml"

try:
    import snowflake.connector
except ImportError:
    print("ERROR: snowflake-connector-python required. Run: pip install -r requirements.txt")
    sys.exit(1)


def load_config():
    with open(CONFIG_PATH) as f:
        return yaml.safe_load(f)


def get_connection(database="OTIF_GUARDIAN"):
    return snowflake.connector.connect(
        account=os.environ.get("SNOWFLAKE_ACCOUNT", ""),
        user=os.environ.get("SNOWFLAKE_USER", ""),
        password=os.environ.get("SNOWFLAKE_PASSWORD", ""),
        database=database,
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "OTIF_GUARDIAN_WH"),
        role=os.environ.get("SNOWFLAKE_ROLE", "OTIF_GUARDIAN_ADMIN"),
        authenticator=os.environ.get("SNOWFLAKE_AUTHENTICATOR", "externalbrowser"),
    )


def run_procedure_gate(conn, gate_name, gate_config, database):
    """Call a stored procedure and evaluate against pass criteria."""
    proc = gate_config["procedure"]
    fqn = f"{database}.{proc}"
    args = gate_config.get("args", [])
    pass_key = gate_config.get("pass_key", "overall_status")
    pass_values = [v.strip() for v in gate_config.get("pass_value", "PASS").split(",")]

    arg_str = ", ".join(f"'{a}'" for a in args) if args else ""
    sql = f"CALL {fqn}({arg_str})"

    print(f"\n  Calling: {sql}")
    cur = conn.cursor()
    try:
        cur.execute(sql)
        row = cur.fetchone()
        if row is None:
            return False, "No result returned", {}

        raw = row[0]
        if isinstance(raw, str):
            try:
                result = json.loads(raw)
            except (json.JSONDecodeError, TypeError):
                result = {"raw": raw}
        elif isinstance(raw, dict):
            result = raw
        else:
            result = {"raw": str(raw)}

        actual = str(result.get(pass_key, "UNKNOWN"))
        passed = actual in pass_values

        return passed, f"{pass_key}={actual}", result
    except Exception as e:
        return False, f"Error: {str(e)[:200]}", {}
    finally:
        cur.close()


def main():
    parser = argparse.ArgumentParser(description="OTIF Guardian Snowflake Validation Runner")
    parser.add_argument("--gate", help="Run a specific gate by name")
    parser.add_argument("--all-required", action="store_true",
                        help="Run all required gates for the environment")
    parser.add_argument("--env", default="PROD", choices=["DEV", "UAT", "PROD"],
                        help="Environment (determines required gates)")
    parser.add_argument("--list", action="store_true", help="List all defined gates")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    args = parser.parse_args()

    config = load_config()
    gates = config.get("gates", {})
    env_config = config["environments"].get(args.env, {})
    database = env_config.get("database", "OTIF_GUARDIAN")

    if args.list:
        print("Defined gates:")
        for name, g in gates.items():
            required = name in env_config.get("required_gates", [])
            req_tag = " [REQUIRED]" if required else ""
            print(f"  {name}{req_tag}: {g['description']}")
        return 0

    gate_names = []
    if args.gate:
        if args.gate not in gates:
            print(f"ERROR: Unknown gate '{args.gate}'. Use --list to see options.")
            return 1
        gate_names = [args.gate]
    elif args.all_required:
        gate_names = [g for g in env_config.get("required_gates", []) if g in gates]
    else:
        parser.error("Specify --gate or --all-required")

    # Filter to procedure-type gates only (this script handles Snowflake procedures)
    proc_gates = {n: gates[n] for n in gate_names if gates[n]["type"] == "snowflake_procedure"}
    skip_gates = {n: gates[n] for n in gate_names if gates[n]["type"] != "snowflake_procedure"}

    if skip_gates:
        for name, g in skip_gates.items():
            print(f"  SKIP [{name}] — type '{g['type']}' (use deploy.py or pytest directly)")

    if not proc_gates:
        print("No Snowflake procedure gates to run.")
        return 0

    conn = get_connection(database)
    results = {}
    all_pass = True

    try:
        for name, gate_config in proc_gates.items():
            print(f"\nGate [{name}]: {gate_config['description']}")
            passed, detail, raw = run_procedure_gate(conn, name, gate_config, database)
            results[name] = {"passed": passed, "detail": detail}
            if not passed:
                all_pass = False

            status = "PASS" if passed else "FAIL"
            print(f"  Result: [{status}] {detail}")

            if not passed and raw:
                tests = raw.get("tests", raw.get("results", []))
                if isinstance(tests, list):
                    fails = [t for t in tests if isinstance(t, dict) and t.get("status") == "FAIL"]
                    for f in fails[:5]:
                        print(f"    FAIL: {f.get('test', f.get('test_name', 'unknown'))}")
    finally:
        conn.close()

    print(f"\n{'='*50}")
    overall = "ALL PASS" if all_pass else "FAILURES DETECTED"
    print(f"OVERALL: {overall}")
    print(f"{'='*50}")

    if args.json:
        print(json.dumps(results, indent=2))

    return 0 if all_pass else 1


if __name__ == "__main__":
    sys.exit(main())
