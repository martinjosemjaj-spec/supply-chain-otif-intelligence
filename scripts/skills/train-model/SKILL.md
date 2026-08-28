---
name: train-model
description: "Train or retrain the OTIF breach prediction model using Snowflake native ML Classification. Handles feature engineering, temporal splitting, model training, evaluation, registry, and reason code generation. Use when: training a new model version, retraining on fresh data, evaluating model performance, checking feature importance, generating SHAP explanations. Triggers: train model, retrain, new model version, model training, evaluate model, feature importance, reason codes, refresh model, update model."
---

# Train Model

## Purpose

Train (or retrain) the OTIF breach prediction model using Snowflake native ML Classification. This skill:
- Engineers leakage-free features from supply chain data
- Applies a temporal train/test split
- Trains a SNOWFLAKE.ML.CLASSIFICATION model (XGBoost)
- Evaluates on hold-out test set
- Registers the model version in Model Registry
- Generates feature importance and reason codes

## Inputs

| Input | Required | Description |
|-------|----------|-------------|
| Database | Yes | Target database (default: `OTIF_GUARDIAN`) |
| ML schema | Yes | Schema for model objects (default: `ML`) |
| Train cutoff date | Yes | Temporal split point (default: first day of current month minus 2 months) |
| Test end date | Yes | End of test window (default: first day of current month) |
| Warehouse | Yes | Compute warehouse (default: `OTIF_GUARDIAN_WH`) |
| Model version | No | Version label for registry (default: auto-incremented V1, V2, ...) |
| Config overrides | No | Optional XGBoost config (default: `{'ON_ERROR': 'SKIP'}`) |

## Outputs

| Output | Location | Description |
|--------|----------|-------------|
| Feature views | `OTIF_GUARDIAN.ML` | V_SUPPLIER_HISTORY, V_MATERIAL_DEMAND_FEATURES, V_FEATURE_SET |
| Training table | `OTIF_GUARDIAN.ML.TRAIN_DATA` | Temporal subset for training |
| Test table | `OTIF_GUARDIAN.ML.TEST_DATA` | Temporal subset for evaluation |
| Model object | `OTIF_GUARDIAN.ML.OTIF_BREACH_MODEL` | Trained classification model |
| Registry entry | `OTIF_GUARDIAN.ML.OTIF_BREACH_PREDICTOR` | Versioned model in registry |
| Metrics view | `OTIF_GUARDIAN.ML.V_MODEL_METRICS` | Accuracy, precision, recall, F1 |
| Confusion matrix | `OTIF_GUARDIAN.ML.V_CONFUSION_MATRIX` | TP/FP/TN/FN counts |
| Feature importance | `OTIF_GUARDIAN.ML.V_FEATURE_IMPORTANCE` | Ranked feature contributions |
| Reason codes | `OTIF_GUARDIAN.ML.REASON_CODES` | Per-prediction SHAP explanations |

## Execution Steps

### Step 1: Verify Prerequisites

```sql
-- Confirm source data exists and is populated
SELECT COUNT(*) AS po_lines FROM OTIF_GUARDIAN.RAW.PO_LINES WHERE actual_delivery_date IS NOT NULL;
-- Should be > 10000 for meaningful training

-- Confirm ML schema exists
CREATE SCHEMA IF NOT EXISTS OTIF_GUARDIAN.ML;
```

If closed PO lines < 5000, STOP and warn: "Insufficient training data. Need at least 5000 closed PO lines with delivery outcomes."

### Step 2: Create Feature Engineering Views

Execute the feature engineering section of `sql/04_ml_pipeline.sql`:
- `V_SUPPLIER_HISTORY` — temporal supplier performance
- `V_MATERIAL_DEMAND_FEATURES` — demand context
- `V_FEATURE_SET` — master feature table

### Step 3: Apply Temporal Split

```sql
-- Determine split dates
-- Train: order_date < [train_cutoff]
-- Test: order_date >= [train_cutoff] AND < [test_end]

CREATE OR REPLACE TABLE OTIF_GUARDIAN.ML.TRAIN_DATA AS
SELECT * EXCLUDE (po_id, po_line_id, order_date, promised_delivery_date)
FROM OTIF_GUARDIAN.ML.V_FEATURE_SET
WHERE OTIF_BREACH IS NOT NULL
  AND order_date < :train_cutoff_date;

CREATE OR REPLACE TABLE OTIF_GUARDIAN.ML.TEST_DATA AS
SELECT * EXCLUDE (po_id, po_line_id, order_date, promised_delivery_date)
FROM OTIF_GUARDIAN.ML.V_FEATURE_SET
WHERE OTIF_BREACH IS NOT NULL
  AND order_date >= :train_cutoff_date
  AND order_date < :test_end_date;
```

Report split sizes:
```
Train set: [N] rows ([X]% breach rate)
Test set:  [M] rows ([Y]% breach rate)
```

### Step 4: Train Model

```sql
CREATE OR REPLACE SNOWFLAKE.ML.CLASSIFICATION OTIF_GUARDIAN.ML.OTIF_BREACH_MODEL(
    INPUT_DATA => SYSTEM$REFERENCE('TABLE', 'OTIF_GUARDIAN.ML.TRAIN_DATA'),
    TARGET_COLNAME => 'OTIF_BREACH',
    CONFIG_OBJECT => {'ON_ERROR': 'SKIP'}
);
```

### Step 5: Evaluate on Test Set

```sql
-- Generate predictions
CREATE OR REPLACE TABLE OTIF_GUARDIAN.ML.TEST_PREDICTIONS AS
SELECT *, OTIF_GUARDIAN.ML.OTIF_BREACH_MODEL!PREDICT(INPUT_DATA => OBJECT_CONSTRUCT(*)) AS prediction_result
FROM OTIF_GUARDIAN.ML.TEST_DATA;

-- Create metrics views
-- [Execute V_TEST_RESULTS, V_CONFUSION_MATRIX, V_MODEL_METRICS from sql/04_ml_pipeline.sql]
```

### Step 6: Extract Feature Importance

```sql
CREATE OR REPLACE VIEW OTIF_GUARDIAN.ML.V_FEATURE_IMPORTANCE AS
SELECT * FROM TABLE(OTIF_GUARDIAN.ML.OTIF_BREACH_MODEL!FEATURE_IMPORTANCE());
```

### Step 7: Register Model Version

```sql
CREATE MODEL IF NOT EXISTS OTIF_GUARDIAN.ML.OTIF_BREACH_PREDICTOR
  COMMENT = 'OTIF breach prediction model';

ALTER MODEL OTIF_GUARDIAN.ML.OTIF_BREACH_PREDICTOR
  ADD VERSION :version_label
  FROM MODEL OTIF_GUARDIAN.ML.OTIF_BREACH_MODEL
  COMMENT = :version_comment;

ALTER MODEL OTIF_GUARDIAN.ML.OTIF_BREACH_PREDICTOR
  SET DEFAULT_VERSION = :version_label;
```

### Step 8: Report Results

Present:
```
Model Training Complete
───────────────────────
Version: V[N]
Train rows: [X] | Test rows: [Y]
Split date: [cutoff]

Performance (Test Set):
  Accuracy:  [X]
  Precision: [X] (breach class)
  Recall:    [X] (breach class)
  F1 Score:  [X]
  Breach rate (actual): [X]%

Top 5 Features:
  1. [feature] — [importance]
  2. [feature] — [importance]
  ...

Registry: OTIF_GUARDIAN.ML.OTIF_BREACH_PREDICTOR @ V[N]
```

## Validation

| Check | Criteria | Action if Failed |
|-------|----------|-----------------|
| Train size >= 5000 | Count rows | Abort with warning |
| Test size >= 500 | Count rows | Warn; proceed with caution |
| Class balance | Breach rate 20%-80% | Warn about imbalance |
| Accuracy > 0.60 | From metrics view | Warn: model may not be production-ready |
| Recall (breach) > 0.50 | From metrics view | Warn: model misses too many breaches |
| No data leakage | No future-dated features | Verify V_FEATURE_SET has no actual_delivery_date |
| Model trains without error | CLASSIFICATION completes | Report error, suggest config change |
| Registry version increments | SHOW MODEL versions | Confirm new version visible |

## Rollback

```sql
-- Remove model version from registry
ALTER MODEL OTIF_GUARDIAN.ML.OTIF_BREACH_PREDICTOR DROP VERSION :version_label;

-- Drop the trained model object
DROP SNOWFLAKE.ML.CLASSIFICATION IF EXISTS OTIF_GUARDIAN.ML.OTIF_BREACH_MODEL;

-- Drop training artifacts (optional — preserves for debugging)
DROP TABLE IF EXISTS OTIF_GUARDIAN.ML.TRAIN_DATA;
DROP TABLE IF EXISTS OTIF_GUARDIAN.ML.TEST_DATA;
DROP TABLE IF EXISTS OTIF_GUARDIAN.ML.TEST_PREDICTIONS;

-- Restore previous default version (if reverting)
-- ALTER MODEL OTIF_GUARDIAN.ML.OTIF_BREACH_PREDICTOR SET DEFAULT_VERSION = V[N-1];
```

## Examples

### Example 1: Standard retraining with new data

```
User: $train-model
Agent: [Uses default split dates based on current date, trains, evaluates,
        registers as next version, reports metrics]
```

### Example 2: Custom split date

```
User: Retrain the model with a split at 2026-05-01
Agent: [Sets train_cutoff = 2026-05-01, test_end = 2026-07-01,
        trains, evaluates, reports. Notes if performance changed vs prior version.]
```

### Example 3: Evaluate only (no retrain)

```
User: Just show me the current model metrics and feature importance
Agent: [Queries V_MODEL_METRICS and V_FEATURE_IMPORTANCE, presents results
        without retraining]
```
