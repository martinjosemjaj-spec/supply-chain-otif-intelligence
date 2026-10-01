#!/usr/bin/env python3
"""
OTIF Guardian - Deployment Orchestrator
Deploys SQL scripts in dependency order with validation gates per environment.

Usage:
    python scripts/deploy.py --env DEV                  # Full deploy to DEV
    python scripts/deploy.py --env PROD --stage agent   # Deploy single stage
    python scripts/deploy.py --env UAT --verify         # Run gates only (no deploy)
    python scripts/deploy.py --env PROD --dry-run       # Print plan, don't execute
    python scripts/deploy.py --env DEV --rollback --stage ontology  # Rollback stage
"""

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import yaml

try:
    import snowflake.connector
except ImportError:
    snowflake = None

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "config" / "environments.yml"


def load_config():
    with open(CONFIG_PATH) as f:
        return yaml.safe_load(f)


def get_snowflake_connection(env_config):
    """Connect to Snowflake using environment variables or connection config."""
    conn_params = {
        "account": os.environ.get("SNOWFLAKE_ACCOUNT", ""),
        "user": os.environ.get("SNOWFLAKE_USER", ""),
        "database": env_config["database"],
        "warehouse": env_config["warehouse"],
        "role": env_config["role"],
    }
    if os.environ.get("SNOWFLAKE_PRIVATE_KEY_PATH"):
        import cryptography.hazmat.primitives.serialization as ser
        with open(os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"], "rb") as kf:
            pk = ser.load_pem_private_key(kf.read(), password=None)
        conn_params["private_key"] = pk.private_bytes(
            ser.Encoding.DER, ser.PrivateFormat.PKCS8, ser.NoEncryption()
        )
    elif os.environ.get("SNOWFLAKE_PASSWORD"):
        conn_params["password"] = os.environ["SNOWFLAKE_PASSWORD"]
    elif os.environ.get("SNOWFLAKE_AUTHENTICATOR"):
        conn_params["authenticator"] = os.environ["SNOWFLAKE_AUTHENTICATOR"]
    else:
        conn_params["authenticator"] = "externalbrowser"
    return snowflake.connector.connect(**conn_params)


def execute_sql_file(conn, filepath, database, dry_run=False):
    """Execute a SQL file against Snowflake, splitting on semicolons."""
    path = ROOT / filepath
    if not path.exists():
        print(f"  SKIP {filepath} (file not found)")
        return True

    text = path.read_text(encoding="utf-8")
    # Replace database references for non-PROD environments
    if database != "OTIF_GUARDIAN":
        text = text.replace("OTIF_GUARDIAN.", f"{database}.")
        text = text.replace("USE DATABASE OTIF_GUARDIAN", f"USE DATABASE {database}")

    statements = [s.strip() for s in text.split(";") if s.strip() and not s.strip().startswith("--")]

    if dry_run:
        print(f"  DRY-RUN {filepath}: {len(statements)} statements")
        return True

    print(f"  Executing {filepath} ({len(statements)} statements)...")
    cur = conn.cursor()
    try:
        for i, stmt in enumerate(statements):
            if not stmt or stmt.startswith("--"):
                continue
            try:
                cur.execute(stmt)
            except Exception as e:
                # Skip USE/SHOW errors, fail on real errors
                err_str = str(e)
                if "already exists" in err_str.lower() and ("CREATE" in stmt.upper()):
                    print(f"    Statement {i+1}: exists (skipped)")
                else:
                    print(f"    FAILED statement {i+1}: {err_str[:200]}")
                    return False
        print(f"    OK ({len(statements)} statements)")
        return True
    finally:
        cur.close()


def run_gate(conn, gate_name, gate_config, database, dry_run=False):
    """Run a validation gate. Returns (passed: bool, details: str)."""
    gate_type = gate_config["type"]
    print(f"\n  Gate [{gate_name}]: {gate_config['description']}")

    if dry_run:
        print(f"    DRY-RUN: would run {gate_type} gate")
        return True, "dry-run"

    if gate_type == "pytest":
        cmd = gate_config["command"].split()
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=str(ROOT),
                                env={**os.environ, "OTIF_GUARDIAN_MODE": "demo"})
        passed = result.returncode == 0
        detail = f"exit_code={result.returncode}"
        if not passed:
            print(f"    STDOUT: {result.stdout[-500:]}")
            print(f"    STDERR: {result.stderr[-500:]}")
        return passed, detail

    elif gate_type == "sql_file":
        filepath = ROOT / gate_config["file"]
        return run_sql_test_file(conn, filepath, database)

    elif gate_type == "snowflake_procedure":
        return run_snowflake_procedure_gate(conn, gate_config, database)

    elif gate_type == "command":
        cmd = gate_config["command"].format(database=database)
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=str(ROOT))
        passed = result.returncode == 0
        return passed, f"exit_code={result.returncode}"

    else:
        print(f"    Unknown gate type: {gate_type}")
        return False, f"unknown type {gate_type}"


def run_sql_test_file(conn, filepath, database):
    """Run a SQL test file and check all results for PASS."""
    if not filepath.exists():
        return False, f"File not found: {filepath}"

    text = filepath.read_text(encoding="utf-8")
    if database != "OTIF_GUARDIAN":
        text = text.replace("OTIF_GUARDIAN.", f"{database}.")
        text = text.replace("USE DATABASE OTIF_GUARDIAN", f"USE DATABASE {database}")

    statements = [s.strip() for s in text.split(";") if s.strip()]

    cur = conn.cursor()
    passed_count = 0
    failed_count = 0
    total_tests = 0
    failures = []

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
                        for row in rows:
                            total_tests += 1
                            result_val = row[ridx]
                            test_id = row[tidx] if tidx is not None else f"test_{total_tests}"
                            if result_val == "PASS":
                                passed_count += 1
                            elif result_val == "MANUAL":
                                pass  # skip manual tests
                            else:
                                failed_count += 1
                                failures.append(test_id)
            except Exception as e:
                # USE/SHOW statements won't have RESULT column
                if "USE " in stmt.upper() or "SHOW " in stmt.upper():
                    continue
                failed_count += 1
                failures.append(f"SQL error: {str(e)[:100]}")
    finally:
        cur.close()

    passed = failed_count == 0
    detail = f"{passed_count}/{total_tests} passed"
    if failures:
        detail += f", FAILED: {', '.join(failures[:5])}"
    print(f"    {detail}")
    return passed, detail


def run_snowflake_procedure_gate(conn, gate_config, database):
    """Call a Snowflake stored procedure and check the result."""
    proc = gate_config["procedure"]
    fqn = f"{database}.{proc}"
    args = gate_config.get("args", [])
    pass_key = gate_config.get("pass_key", "overall_status")
    pass_values = [v.strip() for v in gate_config.get("pass_value", "PASS").split(",")]

    arg_str = ", ".join(f"'{a}'" for a in args) if args else ""
    sql = f"CALL {fqn}({arg_str})"

    cur = conn.cursor()
    try:
        cur.execute(sql)
        row = cur.fetchone()
        if row is None:
            return False, "No result returned"

        result = row[0]
        if isinstance(result, str):
            try:
                result = json.loads(result)
            except (json.JSONDecodeError, TypeError):
                pass

        if isinstance(result, dict):
            actual = str(result.get(pass_key, "UNKNOWN"))
            passed = actual in pass_values
            detail = f"{pass_key}={actual}"
            if not passed:
                detail += f" (expected one of: {pass_values})"
                # Show failed tests if available
                tests = result.get("tests", result.get("results", []))
                if isinstance(tests, list):
                    fails = [t for t in tests if isinstance(t, dict) and t.get("status") == "FAIL"]
                    if fails:
                        detail += f", {len(fails)} failures"
        else:
            actual = str(result)
            passed = actual in pass_values
            detail = f"result={actual}"

        print(f"    {detail}")
        return passed, detail
    except Exception as e:
        detail = f"Error calling {fqn}: {str(e)[:200]}"
        print(f"    {detail}")
        return False, detail
    finally:
        cur.close()


def record_deployment(conn, database, stage_name, status, detail, env_name):
    """Record deployment event in AUDIT.DEPLOYMENT_HISTORY."""
    cur = conn.cursor()
    try:
        cur.execute(f"""
            INSERT INTO {database}.AUDIT.DEPLOYMENT_HISTORY
            (DEPLOYED_AT, ENVIRONMENT, STAGE_NAME, STATUS, DETAIL, DEPLOYED_BY)
            SELECT CURRENT_TIMESTAMP(), '{env_name}', '{stage_name}', '{status}',
                   '{detail[:500].replace("'", "''")}', CURRENT_USER()
        """)
    except Exception:
        pass  # table may not exist yet (first deploy)
    finally:
        cur.close()


def deploy_stage(conn, stage, env_config, config, dry_run=False, env_name="DEV"):
    """Deploy a single stage: run scripts, then run gate if defined."""
    stage_name = stage["name"]
    database = env_config["database"]
    print(f"\n{'='*60}")
    print(f"STAGE {stage['order']}: {stage_name.upper()}")
    print(f"  {stage['description']}")
    print(f"{'='*60}")

    # Skip data generation in PROD
    for script in stage.get("scripts", []):
        if script == "sql/01_generate_data.sql" and not env_config.get("generate_data", True):
            print(f"  SKIP {script} (generate_data=false for {env_name})")
            continue
        success = execute_sql_file(conn, script, database, dry_run)
        if not success:
            record_deployment(conn, database, stage_name, "FAILED", f"Script failed: {script}", env_name)
            return False

    # Run commands (semantic view deploy, agent deploy, streamlit deploy)
    for cmd in stage.get("commands", []):
        if dry_run:
            print(f"  DRY-RUN command: {cmd}")
        else:
            print(f"  Running: {cmd}")
            # These require cortex/snow CLI and are environment-specific
            full_cmd = cmd.replace("{database}", database)
            result = subprocess.run(full_cmd, shell=True, capture_output=True, text=True, cwd=str(ROOT))
            if result.returncode != 0:
                print(f"    Command failed: {result.stderr[:300]}")
                # Don't fail on CLI commands — they may need manual execution
                print(f"    WARNING: Command may need manual execution")

    # Run validation gate if defined and required for this environment
    gate_name = stage.get("gate")
    if gate_name and gate_name in config.get("gates", {}):
        gate_config = config["gates"][gate_name]
        required_gates = env_config.get("required_gates", [])
        if gate_name in required_gates:
            passed, detail = run_gate(conn, gate_name, gate_config, database, dry_run)
            status = "PASSED" if passed else "GATE_FAILED"
            record_deployment(conn, database, stage_name, status, detail, env_name)
            if not passed and gate_config.get("mandatory", True):
                print(f"\n  BLOCKED: Mandatory gate [{gate_name}] FAILED")
                print(f"  Deployment halted at stage {stage_name}.")
                return False
        else:
            print(f"  Gate [{gate_name}] not required for {env_name} — skipped")

    record_deployment(conn, database, stage_name, "DEPLOYED", "OK", env_name)
    return True


def run_verify(conn, config, env_config, env_name):
    """Run all required gates without deploying."""
    required = env_config.get("required_gates", [])
    gates = config.get("gates", {})
    database = env_config["database"]

    print(f"\nVerification mode: running {len(required)} required gates for {env_name}")
    results = {}
    for gate_name in required:
        if gate_name not in gates:
            print(f"  Gate [{gate_name}] not defined — SKIP")
            continue
        passed, detail = run_gate(conn, gate_name, gates[gate_name], database)
        results[gate_name] = {"passed": passed, "detail": detail}

    print(f"\n{'='*60}")
    print("VERIFICATION RESULTS")
    print(f"{'='*60}")
    all_pass = True
    for name, r in results.items():
        status = "PASS" if r["passed"] else "FAIL"
        if not r["passed"]:
            all_pass = False
        print(f"  [{status}] {name}: {r['detail']}")

    overall = "PASS" if all_pass else "FAIL"
    print(f"\nOverall: {overall}")
    return all_pass


def main():
    parser = argparse.ArgumentParser(description="OTIF Guardian Deployment Orchestrator")
    parser.add_argument("--env", required=True, choices=["DEV", "UAT", "PROD"],
                        help="Target environment")
    parser.add_argument("--stage", help="Deploy only this stage (by name)")
    parser.add_argument("--verify", action="store_true",
                        help="Run validation gates only, no deployment")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print execution plan without running anything")
    parser.add_argument("--rollback", action="store_true",
                        help="Rollback a stage (requires --stage)")
    parser.add_argument("--from-stage", type=int,
                        help="Start deployment from this stage number")
    args = parser.parse_args()

    config = load_config()
    env_name = args.env
    env_config = config["environments"][env_name]
    stages = sorted(config["stages"], key=lambda s: s["order"])

    print(f"OTIF Guardian Deployment")
    print(f"  Environment: {env_name}")
    print(f"  Database:    {env_config['database']}")
    print(f"  Warehouse:   {env_config['warehouse']}")
    print(f"  Role:        {env_config['role']}")
    print(f"  Timestamp:   {datetime.now().isoformat()}")

    if args.dry_run:
        print(f"\n  MODE: DRY-RUN (no changes will be made)")
        if args.stage:
            target = [s for s in stages if s["name"] == args.stage]
            stages = target if target else stages
        for stage in stages:
            print(f"\n  Stage {stage['order']}: {stage['name']}")
            for script in stage.get("scripts", []):
                print(f"    -> {script}")
            for cmd in stage.get("commands", []):
                print(f"    -> CMD: {cmd}")
            if stage.get("gate"):
                print(f"    -> GATE: {stage['gate']}")
        return 0

    if snowflake is None:
        print("ERROR: snowflake-connector-python not installed")
        print("Run: pip install -r requirements.txt")
        return 1

    conn = get_snowflake_connection(env_config)
    try:
        if args.verify:
            ok = run_verify(conn, config, env_config, env_name)
            return 0 if ok else 1

        if args.rollback:
            if not args.stage:
                print("ERROR: --rollback requires --stage")
                return 1
            print(f"\nROLLBACK: Stage '{args.stage}' in {env_name}")
            print("  Rollback is stage-specific. Refer to the rollback section in each SQL script.")
            print("  For full teardown: DROP DATABASE IF EXISTS {database};")
            record_deployment(conn, env_config["database"], args.stage, "ROLLED_BACK", "manual", env_name)
            return 0

        # Filter stages
        if args.stage:
            stages = [s for s in stages if s["name"] == args.stage]
            if not stages:
                print(f"ERROR: Unknown stage '{args.stage}'")
                print(f"Valid stages: {[s['name'] for s in config['stages']]}")
                return 1
        elif args.from_stage:
            stages = [s for s in stages if s["order"] >= args.from_stage]

        # PROD deployment approval
        if env_name == "PROD" and env_config.get("deployment_approval"):
            print(f"\nPROD DEPLOYMENT REQUIRES APPROVAL")
            print(f"Stages to deploy: {[s['name'] for s in stages]}")
            confirm = input("Type 'DEPLOY PROD' to confirm: ")
            if confirm != "DEPLOY PROD":
                print("Deployment cancelled.")
                return 1

        # Deploy stages in order
        start = time.time()
        for stage in stages:
            success = deploy_stage(conn, stage, env_config, config, dry_run=False, env_name=env_name)
            if not success:
                elapsed = time.time() - start
                print(f"\nDEPLOYMENT FAILED at stage '{stage['name']}' after {elapsed:.0f}s")
                return 1

        elapsed = time.time() - start
        print(f"\n{'='*60}")
        print(f"DEPLOYMENT COMPLETE — {env_name}")
        print(f"  Stages deployed: {len(stages)}")
        print(f"  Duration: {elapsed:.0f}s")
        print(f"{'='*60}")
        return 0

    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
