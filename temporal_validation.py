"""
OTIF Guardian — Production Temporal Validation
Replaces stratified random splits with time-based train/val/test and rolling-window CV.
Persists all results to Snowflake audit tables.
"""
import sys, json
sys.path.insert(0, r"C:\Users\vinos\supply-chain-otif-intelligence")
from snowpark_session import create_snowpark_session
import pandas as pd
import numpy as np
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import (
    accuracy_score, precision_score, recall_score, f1_score,
    roc_auc_score, average_precision_score, brier_score_loss,
    confusion_matrix, precision_recall_curve
)
from xgboost import XGBClassifier
from datetime import datetime
import warnings
warnings.filterwarnings("ignore")

print("=" * 72)
print("OTIF Guardian — Production Temporal Validation")
print("=" * 72)

# ─── 0. Connect ───────────────────────────────────────────────────────
session = create_snowpark_session("FV67216")
session.sql("USE DATABASE OTIF_GUARDIAN").collect()
session.sql("USE WAREHOUSE OTIF_GUARDIAN_WH").collect()

# ─── 1. Load data with temporal columns ───────────────────────────────
print("\n[1/8] Loading labelled data from V_FEATURE_SET_V2...")
df = session.sql("""
    SELECT * FROM OTIF_GUARDIAN.ML.V_FEATURE_SET_V2
    WHERE OTIF_BREACH IS NOT NULL
    ORDER BY ORDER_DATE
""").to_pandas()
df["ORDER_DATE"] = pd.to_datetime(df["ORDER_DATE"])
print(f"  Rows: {len(df)}, Date range: {df.ORDER_DATE.min().date()} to {df.ORDER_DATE.max().date()}")
print(f"  Breach rate: {df.OTIF_BREACH.mean():.4f} ({df.OTIF_BREACH.sum()} / {len(df)})")

# ─── 2. Load existing acceptance thresholds ───────────────────────────
print("\n[2/8] Loading acceptance thresholds from MODEL_VALIDATION_THRESHOLDS...")
thresholds_df = session.sql("SELECT * FROM OTIF_GUARDIAN.AUDIT.MODEL_VALIDATION_THRESHOLDS WHERE IS_ACTIVE = TRUE").to_pandas()
thresholds = {}
for _, row in thresholds_df.iterrows():
    thresholds[row.METRIC_NAME] = {"op": row.OPERATOR, "val": float(row.THRESHOLD_VALUE)}
    print(f"  {row.METRIC_NAME} {row.OPERATOR} {row.THRESHOLD_VALUE}")

# ─── 3. Feature preparation ──────────────────────────────────────────
print("\n[3/8] Preparing features...")
target = "OTIF_BREACH"
id_cols = ["PO_LINE_ID", "PO_ID", "ORDER_DATE", "PROMISED_DELIVERY_DATE"]
y_all = df[target].astype(int)
X_all = df.drop(columns=[target] + id_cols)
dates = df["ORDER_DATE"]

cat_cols = X_all.select_dtypes(include=["object"]).columns.tolist()
label_encoders = {}
for col in cat_cols:
    le = LabelEncoder()
    X_all[col] = le.fit_transform(X_all[col].astype(str))
    label_encoders[col] = le
X_all = X_all.fillna(-999)
print(f"  Features: {X_all.shape[1]}, Categorical encoded: {len(cat_cols)}")

# ─── 4. Time-based train / validation / test split ───────────────────
print("\n[4/8] Temporal split (train < 2025-10 | val 2025-10..2026-03 | test >= 2026-03)...")
train_mask = dates < "2025-10-01"
val_mask = (dates >= "2025-10-01") & (dates < "2026-03-01")
test_mask = dates >= "2026-03-01"

X_train, y_train = X_all[train_mask], y_all[train_mask]
X_val, y_val = X_all[val_mask], y_all[val_mask]
X_test, y_test = X_all[test_mask], y_all[test_mask]

print(f"  Train: {len(X_train)} rows ({y_train.mean():.4f} breach rate)")
print(f"  Val:   {len(X_val)} rows ({y_val.mean():.4f} breach rate)")
print(f"  Test:  {len(X_test)} rows ({y_test.mean():.4f} breach rate)")

# ─── 5. Train model on temporal train set ─────────────────────────────
print("\n[5/8] Training XGBoost on temporal train set...")
scale_pos = (y_train == 0).sum() / max((y_train == 1).sum(), 1)
model = XGBClassifier(
    n_estimators=300, max_depth=5, learning_rate=0.05,
    subsample=0.8, colsample_bytree=0.8,
    scale_pos_weight=scale_pos, reg_alpha=1.0, reg_lambda=2.0,
    eval_metric="logloss", random_state=42, n_jobs=-1, verbosity=0
)
model.fit(X_train, y_train)

# Also score train set for overfitting check
y_train_prob = model.predict_proba(X_train)[:, 1]
train_roc = roc_auc_score(y_train, y_train_prob)

# ─── 6. Rolling-window temporal CV (expanding window, 3 folds) ───────
print("\n[6/8] Rolling expanding-window temporal CV (3 folds)...")
# Fold 1: train on <2025-01, test on 2025-01..2025-04
# Fold 2: train on <2025-04, test on 2025-04..2025-07
# Fold 3: train on <2025-07, test on 2025-07..2025-10
fold_boundaries = [
    ("2025-01-01", "2025-04-01"),
    ("2025-04-01", "2025-07-01"),
    ("2025-07-01", "2025-10-01"),
]
cv_results = []
print(f"  {'Fold':<6} {'Train':<8} {'Test':<7} {'ROC-AUC':<9} {'PR-AUC':<9} {'Recall':<8} {'F1':<8}")
print("  " + "-" * 55)
for i, (fold_start, fold_end) in enumerate(fold_boundaries):
    cv_train_mask = dates < fold_start
    cv_test_mask = (dates >= fold_start) & (dates < fold_end)
    if cv_train_mask.sum() < 100 or cv_test_mask.sum() < 30:
        continue
    Xtr, ytr = X_all[cv_train_mask], y_all[cv_train_mask]
    Xte, yte = X_all[cv_test_mask], y_all[cv_test_mask]
    sp = (ytr == 0).sum() / max((ytr == 1).sum(), 1)
    m = XGBClassifier(n_estimators=300, max_depth=5, learning_rate=0.05,
        subsample=0.8, colsample_bytree=0.8, scale_pos_weight=sp,
        reg_alpha=1.0, reg_lambda=2.0, eval_metric="logloss",
        random_state=42, n_jobs=-1, verbosity=0)
    m.fit(Xtr, ytr)
    p = m.predict_proba(Xte)[:, 1]
    pred = m.predict(Xte)
    roc = roc_auc_score(yte, p)
    pr = average_precision_score(yte, p)
    rec = recall_score(yte, pred)
    f1 = f1_score(yte, pred)
    cv_results.append({"fold": i+1, "train_n": len(Xtr), "test_n": len(Xte),
        "roc_auc": roc, "pr_auc": pr, "recall": rec, "f1": f1})
    print(f"  {i+1:<6} {len(Xtr):<8} {len(Xte):<7} {roc:<9.4f} {pr:<9.4f} {rec:<8.4f} {f1:<8.4f}")

cv_mean = {k: np.mean([f[k] for f in cv_results]) for k in ["roc_auc", "pr_auc", "recall", "f1"]}
cv_std = {k: np.std([f[k] for f in cv_results]) for k in ["roc_auc", "pr_auc", "recall", "f1"]}
print(f"  {'Mean':<6} {'':8} {'':7} {cv_mean['roc_auc']:<9.4f} {cv_mean['pr_auc']:<9.4f} {cv_mean['recall']:<8.4f} {cv_mean['f1']:<8.4f}")
print(f"  {'Std':<6} {'':8} {'':7} {cv_std['roc_auc']:<9.4f} {cv_std['pr_auc']:<9.4f} {cv_std['recall']:<8.4f} {cv_std['f1']:<8.4f}")

# ─── 7. Full evaluation on temporal test set ──────────────────────────
print("\n[7/8] Evaluating on temporal test set (>= 2026-03-01)...")

# Combine train+val for final model evaluation on test
X_trainval = pd.concat([X_train, X_val])
y_trainval = pd.concat([y_train, y_val])
sp_final = (y_trainval == 0).sum() / max((y_trainval == 1).sum(), 1)
model_final = XGBClassifier(n_estimators=300, max_depth=5, learning_rate=0.05,
    subsample=0.8, colsample_bytree=0.8, scale_pos_weight=sp_final,
    reg_alpha=1.0, reg_lambda=2.0, eval_metric="logloss",
    random_state=42, n_jobs=-1, verbosity=0)
model_final.fit(X_trainval, y_trainval)

y_pred = model_final.predict(X_test)
y_prob = model_final.predict_proba(X_test)[:, 1]

# Metrics
acc = accuracy_score(y_test, y_pred)
prec = precision_score(y_test, y_pred, zero_division=0)
rec = recall_score(y_test, y_pred, zero_division=0)
f1 = f1_score(y_test, y_pred, zero_division=0)
roc = roc_auc_score(y_test, y_prob)
pr_auc = average_precision_score(y_test, y_prob)
brier = brier_score_loss(y_test, y_prob)
cm = confusion_matrix(y_test, y_pred)
TP, FP, FN, TN = cm[1][1], cm[0][1], cm[1][0], cm[0][0]

# Overfit check
y_trainval_prob = model_final.predict_proba(X_trainval)[:, 1]
trainval_roc = roc_auc_score(y_trainval, y_trainval_prob)
overfit_gap = trainval_roc - roc

print("\n" + "=" * 72)
print("TEMPORAL TEST SET RESULTS (>= 2026-03-01)")
print("=" * 72)
print(f"  {'Accuracy':<22} {acc:.4f}")
print(f"  {'Precision':<22} {prec:.4f}")
print(f"  {'Recall':<22} {rec:.4f}")
print(f"  {'F1-Score':<22} {f1:.4f}")
print(f"  {'ROC-AUC':<22} {roc:.4f}")
print(f"  {'PR-AUC':<22} {pr_auc:.4f}")
print(f"  {'Brier Score':<22} {brier:.4f}")
print(f"  {'Overfit Gap (ROC)':<22} {overfit_gap:.4f}")
print(f"\n  Confusion Matrix:")
print(f"  {'':>20} Predicted 0  Predicted 1")
print(f"  {'Actual 0':>20} {TN:>7}      {FP:>7}")
print(f"  {'Actual 1':>20} {FN:>7}      {TP:>7}")

# ─── 8. Business impact metrics ──────────────────────────────────────
print("\n" + "=" * 72)
print("BUSINESS IMPACT METRICS")
print("=" * 72)
breach_rate = y_test.mean()
total_test = len(y_test)
breaches_caught = TP
breaches_missed = FN
false_alarms = FP
print(f"  Total test PO lines:     {total_test}")
print(f"  Actual breaches:         {TP + FN}")
print(f"  Breaches caught (TP):    {TP} ({TP/(TP+FN)*100:.1f}%)")
print(f"  Breaches missed (FN):    {FN} ({FN/(TP+FN)*100:.1f}%)")
print(f"  False alarms (FP):       {FP} ({FP/(FP+TN)*100:.1f}% false positive rate)")
print(f"  Alert volume:            {TP+FP} alerts for {total_test} lines ({(TP+FP)/total_test*100:.1f}% alert rate)")

# ─── Compare with existing stratified results ────────────────────────
print("\n" + "=" * 72)
print("COMPARISON: TEMPORAL vs STRATIFIED RANDOM")
print("=" * 72)
print(f"  {'Metric':<18} {'Stratified':>12} {'Temporal':>12} {'Delta':>10}")
print("  " + "-" * 54)
# Existing stratified results from evaluate_model.py
strat = {"Accuracy": 0.8671, "Precision": 0.4192, "Recall": 0.9382,
         "F1": 0.5795, "ROC-AUC": 0.9464}
temp = {"Accuracy": acc, "Precision": prec, "Recall": rec, "F1": f1, "ROC-AUC": roc}
for metric in strat:
    s, t = strat[metric], temp[metric]
    print(f"  {metric:<18} {s:>11.4f} {t:>11.4f} {t-s:>+10.4f}")
print(f"  {'PR-AUC':<18} {'N/A':>12} {pr_auc:>11.4f} {'—':>10}")
print(f"  {'Brier Score':<18} {'N/A':>12} {brier:>11.4f} {'—':>10}")

# ─── Gate checks ─────────────────────────────────────────────────────
print("\n" + "=" * 72)
print("PRODUCTION GATE CHECKS")
print("=" * 72)
gate_results = {}
metric_map = {
    "ROC_AUC": roc, "RECALL_BREACH": rec, "F1_BREACH": f1,
    "PR_AUC": pr_auc, "BRIER_SCORE": brier, "OVERFIT_GAP": overfit_gap
}
all_pass = True
for metric_name, cfg in thresholds.items():
    if metric_name in metric_map:
        actual = metric_map[metric_name]
        op, val = cfg["op"], cfg["val"]
        if op == ">=":
            passed = actual >= val
        elif op == "<=":
            passed = actual <= val
        else:
            passed = actual == val
        status = "PASS" if passed else "FAIL"
        if not passed:
            all_pass = False
        gate_results[metric_name] = {"status": status, "actual": actual, "threshold": val}
        print(f"  [{status}] {metric_name:<18} actual={actual:.4f}  threshold {op} {val}")

# Feature parity gate
fp_result = session.sql("""
    SELECT GATE_STATUS FROM OTIF_GUARDIAN.AUDIT.DQ_RUN_SUMMARY 
    WHERE RUN_ID LIKE 'FP_%' ORDER BY STARTED_AT DESC LIMIT 1
""").collect()
fp_status = fp_result[0][0] if fp_result else 'UNKNOWN'
gate_results["FEATURE_PARITY"] = {"status": fp_status, "actual": fp_status, "threshold": "PASS"}
print(f"  [{'PASS' if fp_status == 'PASS' else 'FAIL'}] {'FEATURE_PARITY':<18} status={fp_status}")
if fp_status != "PASS":
    all_pass = False

# DQ gate
dq_result = session.sql("""
    SELECT GATE_STATUS FROM OTIF_GUARDIAN.AUDIT.DQ_RUN_SUMMARY 
    WHERE RUN_ID LIKE 'DQ_%' ORDER BY STARTED_AT DESC LIMIT 1
""").collect()
dq_status = dq_result[0][0] if dq_result else 'UNKNOWN'
gate_results["DATA_QUALITY"] = {"status": dq_status, "actual": dq_status, "threshold": "PASS"}
print(f"  [{'PASS' if dq_status == 'PASS' else 'FAIL'}] {'DATA_QUALITY':<18} status={dq_status}")
if dq_status != "PASS":
    all_pass = False

# ─── Persist to Snowflake ────────────────────────────────────────────
print("\n[8/8] Persisting results to Snowflake audit tables...")

session.sql(f"""
    INSERT INTO OTIF_GUARDIAN.AUDIT.MODEL_METRICS_HISTORY
    (METRIC_ID, MODEL_VERSION, EVALUATED_AT, ACCURACY, PRECISION_BREACH, RECALL_BREACH,
     F1_BREACH, ROC_AUC, TP, FP, FN, TN, TOTAL, BREACH_RATE_ACTUAL)
    SELECT
        (SELECT COALESCE(MAX(METRIC_ID),0)+1 FROM OTIF_GUARDIAN.AUDIT.MODEL_METRICS_HISTORY),
        'V3-TEMPORAL', CURRENT_TIMESTAMP(),
        {acc}, {prec}, {rec}, {f1}, {roc}, {TP}, {FP}, {FN}, {TN}, {len(y_test)}, {breach_rate}
""").collect()
print("  Persisted temporal metrics to MODEL_METRICS_HISTORY (V3-TEMPORAL)")

# ─── Final verdict ───────────────────────────────────────────────────
print("\n" + "=" * 72)
verdict = "PASS — Model approved for production" if all_pass else "FAIL — Model does not meet all production gates"
print(f"PRODUCTION VALIDATION VERDICT: {verdict}")
print("=" * 72)
print(f"""
  Model:                XGBoost V3 (300 trees, max_depth=5)
  Validation method:    Temporal split + expanding-window CV
  Train period:         2023-08 to 2026-02
  Test period:          2026-03 to 2026-08 (most recent data)
  
  Gate summary:
    Metric gates:       {sum(1 for g in gate_results.values() if g['status']=='PASS')}/{len(gate_results)} passed
    Feature parity:     {fp_status}
    Data quality:       {dq_status}
  
  Temporal CV (3-fold expanding window):
    ROC-AUC:  {cv_mean['roc_auc']:.4f} +/- {cv_std['roc_auc']:.4f}
    PR-AUC:   {cv_mean['pr_auc']:.4f} +/- {cv_std['pr_auc']:.4f}
    Recall:   {cv_mean['recall']:.4f} +/- {cv_std['recall']:.4f}
    F1:       {cv_mean['f1']:.4f} +/- {cv_std['f1']:.4f}
  
  Temporal test set:
    ROC-AUC:  {roc:.4f}    PR-AUC: {pr_auc:.4f}
    Recall:   {rec:.4f}    Prec:   {prec:.4f}
    F1:       {f1:.4f}    Brier:  {brier:.4f}
    Overfit:  {overfit_gap:.4f}
""")

session.close()
