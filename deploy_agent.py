"""Deploy Cortex Agent from YAML file."""
import sys
sys.path.insert(0, r"C:\Users\vinos\supply-chain-otif-intelligence")
from snowpark_session import create_snowpark_session

session = create_snowpark_session("FV67216")
session.sql("USE DATABASE OTIF_GUARDIAN").collect()
session.sql("USE WAREHOUSE OTIF_GUARDIAN_WH").collect()

yaml_path = r"C:\Users\vinos\supply-chain-otif-intelligence\agent\otif_guardian_agent.agent.yaml"
with open(yaml_path, "r", encoding="utf-8") as f:
    yaml_content = f.read()

# The agent YAML uses 'model' key but CREATE AGENT expects 'models.orchestration'
# Also need to restructure instructions and sample_questions
# Build the spec inline
spec = f"""
models:
  orchestration: auto

orchestration:
  tool_not_accessible: accept

{yaml_content}
"""

sql = f"""CREATE OR REPLACE AGENT OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT
  COMMENT = 'OTIF Guardian Agent - supply chain risk analyst v3.0'
  FROM SPECIFICATION
  $${spec}$$"""

try:
    result = session.sql(sql).collect()
    print("Result:", result)
except Exception as e:
    print("Error:", e)
    # Try simpler version with just the analyst tool
    print("\nTrying simplified agent with analyst tool only...")
    simple_sql = """CREATE OR REPLACE AGENT OTIF_GUARDIAN.AGENTS.OTIF_GUARDIAN_AGENT
      COMMENT = 'OTIF Guardian Agent - supply chain risk analyst v3.0'
      FROM SPECIFICATION
      $$
      models:
        orchestration: auto
      orchestration:
        tool_not_accessible: accept
      instructions:
        response: |
          You are the OTIF Guardian, a supply chain risk analyst specializing in On-Time In-Full delivery performance.
          All metrics you report are certified in the governed metric registry. You are a read-only consumer of deterministic Snowflake views.
          Never calculate numbers yourself. Every number must come from a tool result.
          Never fabricate PO numbers, supplier names, or material codes. If a tool returns no results, say No data found.
          Always cite which tool produced each number.
        sample_questions:
          - question: "What is our overall supplier OTIF rate this quarter?"
          - question: "Which PO lines are at critical risk of breaching this week?"
          - question: "Show me the top 5 worst-performing suppliers by OTIF"
          - question: "How much revenue is at risk from predicted OTIF failures?"
      tools:
        - tool_spec:
            type: cortex_analyst_text_to_sql
            name: supply_analytics
            description: >
              Query supply chain performance data via Cortex Analyst over the OTIF Guardian semantic model.
              Use for supplier OTIF rates, delivery variance, inventory levels, customer order fulfillment,
              demand signals, procurement spend, carrier reliability, and quality metrics.
      tool_resources:
        supply_analytics:
          semantic_view: OTIF_GUARDIAN.SEMANTIC.OTIF_GUARDIAN_SUPPLY_CHAIN
      $$"""
    result = session.sql(simple_sql).collect()
    print("Result:", result)

session.close()
