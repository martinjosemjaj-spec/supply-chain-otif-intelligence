"""Deploy and run feature parity tests."""
import sys
sys.path.insert(0, r"C:\Users\vinos\supply-chain-otif-intelligence")
from snowpark_session import create_snowpark_session

session = create_snowpark_session("FV67216")
session.sql("USE DATABASE OTIF_GUARDIAN").collect()
session.sql("USE WAREHOUSE OTIF_GUARDIAN_WH").collect()

with open(r"C:\Users\vinos\supply-chain-otif-intelligence\feature_parity_procedure.sql", "r", encoding="utf-8") as f:
    proc_sql = f.read()

print("Creating SP_FEATURE_PARITY_TESTS...")
session.sql(proc_sql).collect()
print("Created. Running tests...")
result = session.sql("CALL OTIF_GUARDIAN.AUDIT.SP_FEATURE_PARITY_TESTS()").collect()
print("Result:", result[0][0])
session.close()
