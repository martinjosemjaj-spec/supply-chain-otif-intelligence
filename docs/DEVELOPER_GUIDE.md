# Developer Guide

## Development Environment

**Required tools:**
- Snowflake account (Enterprise+) with ACCOUNTADMIN
- Cortex Code CLI (`cortex`)
- Git

**Optional:**
- Python 3.11+ (for local Snowpark testing)
- Streamlit (for local UI preview)

## Project Conventions

### Naming

| Object | Pattern | Example |
|--------|---------|---------|
| Database | UPPER_SNAKE | `OTIF_GUARDIAN` |
| Schema | UPPER_SNAKE | `RAW`, `ANALYTICS`, `ML` |
| Table | UPPER_SNAKE | `PO_LINES` |
| View | V_ prefix | `V_PO_DELIVERY_PERFORMANCE` |
| Procedure | SP_ prefix | `SP_RUN_RECOVERY_ENGINE` |
| Model | Descriptive | `OTIF_BREACH_MODEL` |
| Role | Project prefix | `OTIF_GUARDIAN_ANALYST` |
| Sequence | _SEQ suffix | `LOAD_BATCH_SEQ` |

### SQL Style

- All DDL is idempotent (`CREATE OR REPLACE` or `IF NOT EXISTS`)
- Each script has a header comment block with purpose and date
- Section separators use `-- ====` lines
- All scripts set explicit context (`USE DATABASE`, `USE SCHEMA`, `USE WAREHOUSE`)
- Parameters referenced with colon prefix in stored procedures (`:param_name`)

### File Organization

- SQL scripts numbered by execution order (`00_`, `01_`, `02_`, ...)
- One logical unit per file (bootstrap, data gen, ontology, etc.)
- Views are defined in the script that creates their schema
- Procedures that contain Python go in `python/` with `.sql` extension

### Branching

- `main` — production-ready, all tests pass
- `develop` — integration branch
- `feature/<name>` — feature work
- `hotfix/<name>` — urgent production fixes

## Adding a New Entity

1. Add table DDL to `sql/01_generate_data.sql`
2. Add ontology view to `sql/02_ontology_views.sql`
3. Add to semantic view YAML (`semantic/otif_guardian_supply_chain.sv.yaml`)
4. Add relationship in YAML `relationships:` section
5. Add test cases to `tests/test_sql.sql`
6. Update `docs/ONTOLOGY.md` with entity definition
7. Update `docs/BUSINESS_GLOSSARY.md` if new terms introduced
8. Re-deploy semantic view and ontology views

## Adding a New Feature to ML Model

1. Add feature computation to `V_FEATURE_SET` in `sql/04_ml_pipeline.sql`
2. Verify no leakage: feature must be knowable at PO creation time
3. Add leakage test to `tests/test_ml.sql`
4. Retrain model (creates new version in registry)
5. Evaluate on test set — compare metrics to prior version
6. Update `docs/MODEL_CARD.md` with new feature documentation

**Leakage checklist:**
- Does this feature use `actual_delivery_date`? REJECT
- Does this feature use `quantity_received`? REJECT
- Does this feature use any shipment or receipt data? REJECT
- Is this feature computed using data that exists AFTER the PO's order_date? REJECT

## Adding a New Recovery Action

1. Create evaluation view in `sql/05_recovery_engine.sql` following the pattern of existing actions:
   - Feasibility check
   - Success probability (deterministic rules)
   - Cost calculation
   - Revenue protected calculation
   - Net value = revenue - cost
2. Add the new action to the `V_RECOVERY_RECOMMENDATIONS` UNION ALL
3. Add test in `tests/test_ml.sql` verifying:
   - Cost >= 0
   - Probability in [0, 1]
   - Net value formula correct
4. Update agent tool description if the action should be surfaced

## Modifying the Agent

1. Edit `agent/otif_guardian_agent.agent.yaml`
2. Write to workspace: `cortex agent-studio agent-write ...`
3. Save draft: `cortex agent-studio agent-save ...`
4. Test: `cortex agents run <FQN> "<test question>"`
5. If passing, publish: `cortex agent-studio agent-publish ...`

## Testing

```sql
-- Run all tests
@tests/test_sql.sql
@tests/test_ml.sql
@tests/test_semantic_agent_governance.sql
```

**Convention:** Every test returns a row with columns: `test_id`, `test_name`, `result` (PASS/FAIL), `actual`, `expected`.

**Adding tests:** Append to the appropriate test file following the pattern `T-<CATEGORY>-<NUMBER>`.

## Reusable Skills

Three CoCo skills are available in `scripts/skills/`:

```bash
cortex skill add scripts/skills/build-ontology
cortex skill add scripts/skills/train-model
cortex skill add scripts/skills/deploy-project
```

Use: `$build-ontology`, `$train-model`, `$deploy-project` in CoCo sessions.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Model accuracy < 0.55 | Insufficient or imbalanced data | Check class balance; adjust split date |
| Semantic view deploy fails | YAML syntax error | Validate with `SYSTEM$WRITE_SEMANTIC_MODEL_YAML(..., TRUE)` |
| Agent returns empty response | Semantic view not deployed | Deploy semantic view first |
| Recovery engine shows 0 actions | No at-risk lines (model scores all as low risk) | Check SCORED_PO_LINES for probability distribution |
| Procedure fails with "not authorized" | Missing grants | Run `sql/06_deploy_agent.sql` grants section |
