# OTIF_Guardian - CoCo Project Instructions

## Project Context

This is the OTIF_Guardian project: a production Snowflake AI solution for On-Time In-Full delivery performance monitoring.

**Account:** KY70858 (AWS_AP_SOUTHEAST_7)  
**User:** SNOWRUBAN  
**Role:** ACCOUNTADMIN  
**Warehouse:** COMPUTE_WH  

## Architecture

- `sql/` - Snowflake DDL and DML (tables, views, stored procedures, tasks)
- `semantic/` - Cortex Analyst semantic model YAML definitions
- `python/` - Snowpark Python modules and UDFs
- `streamlit/` - Streamlit in Snowflake application code
- `agent/` - Cortex Agent specifications and tool definitions
- `tests/` - Unit and integration tests
- `config/` - Environment configuration
- `scripts/` - Deployment and maintenance scripts

## Conventions

- All SQL objects use the naming pattern: `OTIF_GUARDIAN.<schema>.<object>`
- Semantic models follow Cortex Analyst YAML specification
- Python code targets Snowpark Python runtime
- Tests use pytest with Snowpark testing utilities

## Key Files

- `PROJECT_STATUS.md` - Current status and progress
- `PROJECT_DECISIONS.md` - Architectural Decision Records (ADRs)

## Session Rules

- Do not modify production objects without explicit confirmation
- Always validate SQL before execution
- Reference PROJECT_DECISIONS.md before making architectural changes
