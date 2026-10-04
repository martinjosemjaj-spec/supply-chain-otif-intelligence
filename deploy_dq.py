"""Deploy DQ framework procedures."""
import sys
sys.path.insert(0, r"C:\Users\vinos\supply-chain-otif-intelligence")
from snowpark_session import create_snowpark_session

session = create_snowpark_session("FV67216")
session.sql("USE DATABASE OTIF_GUARDIAN").collect()
session.sql("USE WAREHOUSE OTIF_GUARDIAN_WH").collect()

# Read the procedure SQL from file
with open(r"C:\Users\vinos\supply-chain-otif-intelligence\dq_procedure.sql", "r", encoding="utf-8") as f:
    proc_sql = f.read()

print("Creating SP_RUN_DQ_CHECKS...")
session.sql(proc_sql).collect()
print("SP_RUN_DQ_CHECKS created.")

# Create SP_DQ_GATE
gate_sql = """CREATE OR REPLACE PROCEDURE OTIF_GUARDIAN.AUDIT.SP_DQ_GATE()
RETURNS VARIANT LANGUAGE SQL
COMMENT = 'Returns latest DQ gate status. BLOCKED = critical failures, scoring must not proceed.'
EXECUTE AS CALLER
AS
BEGIN
    LET v_gate VARCHAR;
    LET v_critical INT;
    LET v_run_id VARCHAR;
    SELECT RUN_ID, GATE_STATUS, CRITICAL_FAILURES 
    INTO :v_run_id, :v_gate, :v_critical
    FROM OTIF_GUARDIAN.AUDIT.DQ_RUN_SUMMARY ORDER BY STARTED_AT DESC LIMIT 1;
    RETURN OBJECT_CONSTRUCT('run_id', :v_run_id, 'gate_status', :v_gate, 'critical_failures', :v_critical, 'scoring_allowed', :v_gate = 'PASS');
END"""
print("Creating SP_DQ_GATE...")
session.sql(gate_sql).collect()
print("SP_DQ_GATE created.")

session.close()
print("Done.")
