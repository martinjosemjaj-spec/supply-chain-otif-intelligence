"""Deploy semantic view from YAML file."""
import sys
sys.path.insert(0, r"C:\Users\vinos\supply-chain-otif-intelligence")
from snowpark_session import create_snowpark_session

session = create_snowpark_session("FV67216")
session.sql("USE DATABASE OTIF_GUARDIAN").collect()
session.sql("USE WAREHOUSE OTIF_GUARDIAN_WH").collect()

yaml_path = r"C:\Users\vinos\supply-chain-otif-intelligence\semantic\otif_guardian_supply_chain.sv.yaml"
with open(yaml_path, "r", encoding="utf-8") as f:
    yaml_content = f.read()

sql = f"CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML('OTIF_GUARDIAN.SEMANTIC', $${yaml_content}$$)"
result = session.sql(sql).collect()
print("Result:", result)
session.close()
