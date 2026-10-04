"""
OTIF Guardian — Decision Layer Optimization
Threshold sweep, calibration, business cost analysis, risk tier configuration.
Persists everything to governed Snowflake tables.
"""
import sys, json
sys.path.insert(0, r"C:\Users\vinos\supply-chain-otif-intelligence")
from snowpark_session import create_snowpark_session
import pandas as pd
import numpy as np
from sklearn.preprocessing import LabelEncoder
from sklearn.calibration import CalibratedClassifierCV, calibration_curve
from sklearn.metrics import (
    accuracy_score, precision_score, recall_score, f1_score,
    roc_auc_score, average_precision_score, brier_score_loss,
    confusion_matrix, precision_recall_curve
)
from xgboost import XGBClassifier
import warnings
warnings.filterwarnings("ignore")

W = 72
print("=" * W)
print("OTIF Guardian — Decision Layer Optimization")
print("=" * W)

# ─── 0. Connect and load ─────────────────────────────────────────────
session = create_snowpark_session("FV67216")
session.sql("USE DATABASE OTIF_GUARDIAN").collect()
session.sql("USE WAREHOUSE OTIF_GUARDIAN_WH").collect()

print("\n[1/9] Loading labelled data with temporal ordering...")
df = session.sql("""
    SELECT * FROM OTIF_GUARDIAN.ML.V_FEATURE_SET_V2
    WHERE OTIF_BREACH IS NOT NULL ORDER BY ORDER_DATE
""").to_pandas()
df["ORDER_DATE"] = pd.to_datetime(df["ORDER_DATE"])

# Load business cost config
biz = session.sql("""
    SELECT PARAM_NAME, PARAM_VALUE::FLOAT AS VAL
    FROM OTIF_GUARDIAN.ML.DECISION_ASSUMPTIONS
    WHERE CATEGORY = 'RISK_TIER' AND IS_ACTIVE = TRUE
""").to_pandas().set_index("PARAM_NAME")["VAL"].to_dict()
print(f"  Governed risk tier thresholds: {biz}")

target = "OTIF_BREACH"
id_cols = ["PO_LINE_ID", "PO_ID", "ORDER_DATE", "PROMISED_DELIVERY_DATE"]
y_all = df[target].astype(int)
X_all = df.drop(columns=[target] + id_cols)
dates = df["ORDER_DATE"]

cat_cols = X_all.select_dtypes(include=["object"]).columns.tolist()
for col in cat_cols:
    X_all[col] = LabelEncoder().fit_transform(X_all[col].astype(str))
X_all = X_all.fillna(-999)

# Temporal split: train < 2025-10, val 2025-10..2026-03, test >= 2026-03
train_mask = dates < "2025-10-01"
val_mask = (dates >= "2025-10-01") & (dates < "2026-03-01")
test_mask = dates >= "2026-03-01"
X_train, y_train = X_all[train_mask], y_all[train_mask]
X_val, y_val = X_all[val_mask], y_all[val_mask]
X_test, y_test = X_all[test_mask], y_all[test_mask]
print(f"  Train: {len(X_train)}, Val: {len(X_val)}, Test: {len(X_test)}")

# ─── 1. Train base model ─────────────────────────────────────────────
print("\n[2/9] Training base XGBoost...")
sp = (y_train == 0).sum() / max((y_train == 1).sum(), 1)
base_model = XGBClassifier(
    n_estimators=300, max_depth=5, learning_rate=0.05,
    subsample=0.8, colsample_bytree=0.8, scale_pos_weight=sp,
    reg_alpha=1.0, reg_lambda=2.0, eval_metric="logloss",
    random_state=42, n_jobs=-1, verbosity=0
)
base_model.fit(X_train, y_train)
base_val_prob = base_model.predict_proba(X_val)[:, 1]
base_test_prob = base_model.predict_proba(X_test)[:, 1]

# ─── 2. Threshold sweep ──────────────────────────────────────────────
print("\n[3/9] Threshold sweep (0.05 to 0.95)...")
sweep = []
for t in np.arange(0.05, 0.96, 0.05):
    pred = (base_val_prob >= t).astype(int)
    cm = confusion_matrix(y_val, pred, labels=[0, 1])
    tn, fp, fn, tp = cm.ravel()
    sweep.append({
        "threshold": round(t, 2),
        "precision": precision_score(y_val, pred, zero_division=0),
        "recall": recall_score(y_val, pred, zero_division=0),
        "f1": f1_score(y_val, pred, zero_division=0),
        "tp": tp, "fp": fp, "fn": fn, "tn": tn,
        "alert_rate": (tp + fp) / len(y_val)
    })
sweep_df = pd.DataFrame(sweep)

print(f"  {'Thresh':<8} {'Prec':<8} {'Recall':<8} {'F1':<8} {'TP':<5} {'FP':<5} {'FN':<5} {'Alert%':<8}")
print("  " + "-" * 55)
for _, r in sweep_df.iterrows():
    marker = " <--" if abs(r.f1 - sweep_df.f1.max()) < 0.001 else ""
    print(f"  {r.threshold:<8.2f} {r.precision:<8.4f} {r.recall:<8.4f} {r.f1:<8.4f} "
          f"{int(r.tp):<5} {int(r.fp):<5} {int(r.fn):<5} {r.alert_rate:<8.2%}{marker}")

# ─── 3. Precision-recall curve ────────────────────────────────────────
print("\n[4/9] Precision-recall curve analysis...")
pr_prec, pr_rec, pr_thresh = precision_recall_curve(y_val, base_val_prob)
pr_auc = average_precision_score(y_val, base_val_prob)
print(f"  PR-AUC (validation): {pr_auc:.4f}")

# ─── 4. Business cost analysis ───────────────────────────────────────
print("\n[5/9] Business cost optimization...")
# FN cost: missed breach → average revenue exposure per at-risk line
# FP cost: false alarm → investigation cost (analyst time)
FN_COST = 5000   # average revenue lost per missed breach
FP_COST = 200    # investigation cost per false alarm
print(f"  Cost config: FN=${FN_COST}, FP=${FP_COST} (ratio: {FN_COST/FP_COST:.0f}:1)")

sweep_df["business_cost"] = sweep_df.fn * FN_COST + sweep_df.fp * FP_COST
sweep_df["cost_per_line"] = sweep_df.business_cost / len(y_val)
best_cost_row = sweep_df.loc[sweep_df.business_cost.idxmin()]
best_f1_row = sweep_df.loc[sweep_df.f1.idxmax()]

print(f"\n  Optimal by F1:             threshold={best_f1_row.threshold:.2f} "
      f"(F1={best_f1_row.f1:.4f}, cost=${best_f1_row.business_cost:,.0f})")
print(f"  Optimal by business cost:  threshold={best_cost_row.threshold:.2f} "
      f"(F1={best_cost_row.f1:.4f}, cost=${best_cost_row.business_cost:,.0f})")

# Select the business-optimal threshold
optimal_threshold = best_cost_row.threshold
print(f"\n  >>> Selected optimal threshold: {optimal_threshold}")

# ─── 5. Probability calibration ──────────────────────────────────────
print("\n[6/9] Probability calibration (Platt scaling vs Isotonic)...")

# Platt (sigmoid) calibration
platt = CalibratedClassifierCV(base_model, method="sigmoid", cv="prefit")
platt.fit(X_val, y_val)
platt_val_prob = platt.predict_proba(X_val)[:, 1]
platt_test_prob = platt.predict_proba(X_test)[:, 1]
platt_brier = brier_score_loss(y_val, platt_val_prob)

# Isotonic calibration
iso = CalibratedClassifierCV(base_model, method="isotonic", cv="prefit")
iso.fit(X_val, y_val)
iso_val_prob = iso.predict_proba(X_val)[:, 1]
iso_test_prob = iso.predict_proba(X_test)[:, 1]
iso_brier = brier_score_loss(y_val, iso_val_prob)

# Base (uncalibrated)
base_brier = brier_score_loss(y_val, base_val_prob)

# Calibration curves (10 bins)
def calc_ece(y_true, y_prob, n_bins=10):
    frac_pos, mean_pred = calibration_curve(y_true, y_prob, n_bins=n_bins, strategy="uniform")
    bin_counts = np.histogram(y_prob, bins=n_bins, range=(0, 1))[0]
    total = sum(bin_counts)
    ece = sum(bin_counts[i] * abs(frac_pos[i] - mean_pred[i]) for i in range(len(frac_pos))) / total
    return ece, frac_pos, mean_pred

base_ece, base_frac, base_mean = calc_ece(y_val, base_val_prob)
platt_ece, platt_frac, platt_mean = calc_ece(y_val, platt_val_prob)
iso_ece, iso_frac, iso_mean = calc_ece(y_val, iso_val_prob)

print(f"\n  {'Method':<14} {'Brier':<10} {'ECE':<10} {'PR-AUC':<10}")
print("  " + "-" * 44)
for name, brier, ece, probs in [
    ("Uncalibrated", base_brier, base_ece, base_val_prob),
    ("Platt", platt_brier, platt_ece, platt_val_prob),
    ("Isotonic", iso_brier, iso_ece, iso_val_prob),
]:
    prauc = average_precision_score(y_val, probs)
    print(f"  {name:<14} {brier:<10.4f} {ece:<10.4f} {prauc:<10.4f}")

# Select best calibration
if iso_brier <= platt_brier and iso_ece <= platt_ece:
    best_calib = "isotonic"
    best_calib_model = iso
    best_test_prob = iso_test_prob
    best_brier = iso_brier
    best_ece = iso_ece
elif platt_brier < base_brier:
    best_calib = "platt"
    best_calib_model = platt
    best_test_prob = platt_test_prob
    best_brier = platt_brier
    best_ece = platt_ece
else:
    best_calib = "none"
    best_test_prob = base_test_prob
    best_brier = base_brier
    best_ece = base_ece

print(f"\n  >>> Selected calibration: {best_calib} (Brier={best_brier:.4f}, ECE={best_ece:.4f})")

# ─── 6. Calibration curve detail ─────────────────────────────────────
print("\n[7/9] Calibration curve (selected method)...")
if best_calib != "none":
    frac, mean = (iso_frac, iso_mean) if best_calib == "isotonic" else (platt_frac, platt_mean)
else:
    frac, mean = base_frac, base_mean

print(f"  {'Predicted':<12} {'Actual':<12} {'Gap':<10}")
print("  " + "-" * 34)
for p, a in zip(mean, frac):
    gap = abs(a - p)
    print(f"  {p:<12.3f} {a:<12.3f} {gap:<10.3f}")

# ─── 7. Final test-set evaluation with optimal threshold + calibration
print("\n[8/9] Final evaluation (optimal threshold + calibration on test set)...")
y_pred_final = (best_test_prob >= optimal_threshold).astype(int)
cm_final = confusion_matrix(y_test, y_pred_final, labels=[0, 1])
tn, fp, fn, tp = cm_final.ravel()

final_metrics = {
    "accuracy": accuracy_score(y_test, y_pred_final),
    "precision": precision_score(y_test, y_pred_final, zero_division=0),
    "recall": recall_score(y_test, y_pred_final, zero_division=0),
    "f1": f1_score(y_test, y_pred_final, zero_division=0),
    "roc_auc": roc_auc_score(y_test, best_test_prob),
    "pr_auc": average_precision_score(y_test, best_test_prob),
    "brier": brier_score_loss(y_test, best_test_prob),
}

print(f"\n  Threshold: {optimal_threshold:.2f}  |  Calibration: {best_calib}")
print(f"  {'Metric':<18} {'Value':<10}")
print("  " + "-" * 28)
for k, v in final_metrics.items():
    print(f"  {k:<18} {v:.4f}")
print(f"\n  Confusion Matrix:")
print(f"  {'':>18} Pred 0    Pred 1")
print(f"  {'Actual 0':>18} {tn:>6}    {fp:>6}")
print(f"  {'Actual 1':>18} {fn:>6}    {tp:>6}")
print(f"\n  Breaches caught: {tp}/{tp+fn} ({tp/(tp+fn)*100:.1f}%)")
print(f"  False alarms:    {fp} ({fp/(fp+tn)*100:.1f}% FPR)")
print(f"  Alert volume:    {tp+fp}/{len(y_test)} ({(tp+fp)/len(y_test)*100:.1f}%)")

# ─── 8. Risk tier distribution with calibrated probabilities ──────────
print(f"\n  Risk tier distribution (calibrated, threshold={optimal_threshold}):")
tier_map = {
    "CRITICAL": biz.get("CRITICAL_THRESHOLD", 0.8),
    "HIGH": biz.get("HIGH_THRESHOLD", 0.6),
    "MEDIUM": biz.get("MEDIUM_THRESHOLD", 0.4),
    "LOW": biz.get("LOW_THRESHOLD", 0.2),
}
for tier, cutoff in tier_map.items():
    upper = 1.0
    for t2, c2 in sorted(tier_map.items(), key=lambda x: x[1], reverse=True):
        if c2 > cutoff:
            upper = c2
            break
    if tier == "CRITICAL":
        upper = 1.0
    cnt = sum((best_test_prob >= cutoff) & (best_test_prob < upper if tier != "CRITICAL" else True))
    print(f"    {tier:<10} (>= {cutoff:.2f}): {cnt} lines")
minimal = sum(best_test_prob < tier_map["LOW"])
print(f"    {'MINIMAL':<10} (< {tier_map['LOW']:.2f}):  {minimal} lines")

# ─── 9. Persist to Snowflake ──────────────────────────────────────────
print("\n[9/9] Persisting to governed Snowflake tables...")

# Update MODEL_VERSION_HISTORY with threshold and calibration metadata
session.sql(f"""
    UPDATE OTIF_GUARDIAN.AUDIT.MODEL_VERSION_HISTORY
    SET OPTIMAL_THRESHOLD = {optimal_threshold},
        EXPECTED_CALIBRATION_ERROR = {best_ece},
        CALIBRATION_SLOPE = NULL,
        CALIBRATION_INTERCEPT = NULL,
        BRIER_SCORE = {best_brier},
        PROB_DISTRIBUTION = PARSE_JSON('{json.dumps({
            "calibration_method": best_calib,
            "base_brier": round(float(base_brier), 4),
            "calibrated_brier": round(float(best_brier), 4),
            "base_ece": round(float(base_ece), 4),
            "calibrated_ece": round(float(best_ece), 4),
            "fn_cost": FN_COST, "fp_cost": FP_COST,
            "business_cost_at_threshold": round(float(best_cost_row.business_cost), 2),
            "sweep_best_f1_threshold": round(float(best_f1_row.threshold), 2),
            "sweep_best_cost_threshold": round(float(best_cost_row.threshold), 2)
        })}'),
        NOTES = 'Decision layer optimized: threshold={optimal_threshold}, calibration={best_calib}, business_cost_fn=${FN_COST}/fp=${FP_COST}. Temporal validation.'
    WHERE VERSION_NAME = 'V3-SQL-SCORING'
""").collect()
print("  Updated MODEL_VERSION_HISTORY with threshold + calibration metadata")

# Update DECISION_ASSUMPTIONS with the approved classification threshold
session.sql(f"""
    MERGE INTO OTIF_GUARDIAN.ML.DECISION_ASSUMPTIONS t
    USING (SELECT 'MODEL_CONFIG' AS CATEGORY, 'CLASSIFICATION_THRESHOLD' AS PARAM_NAME,
                  '{optimal_threshold}' AS PARAM_VALUE, 'probability' AS UNIT,
                  'Optimal classification threshold (business cost optimized)' AS DESCRIPTION,
                  CURRENT_TIMESTAMP() AS LAST_REVIEWED, CURRENT_USER() AS REVIEWED_BY,
                  TRUE AS IS_ACTIVE) s
    ON t.CATEGORY = s.CATEGORY AND t.PARAM_NAME = s.PARAM_NAME
    WHEN MATCHED THEN UPDATE SET t.PARAM_VALUE = s.PARAM_VALUE, t.LAST_REVIEWED = s.LAST_REVIEWED, t.REVIEWED_BY = s.REVIEWED_BY
    WHEN NOT MATCHED THEN INSERT (ASSUMPTION_ID, CATEGORY, PARAM_NAME, PARAM_VALUE, UNIT, DESCRIPTION, LAST_REVIEWED, REVIEWED_BY, IS_ACTIVE)
        VALUES ((SELECT COALESCE(MAX(ASSUMPTION_ID),0)+1 FROM OTIF_GUARDIAN.ML.DECISION_ASSUMPTIONS), s.CATEGORY, s.PARAM_NAME, s.PARAM_VALUE, s.UNIT, s.DESCRIPTION, s.LAST_REVIEWED, s.REVIEWED_BY, s.IS_ACTIVE)
""").collect()
print("  Persisted CLASSIFICATION_THRESHOLD to DECISION_ASSUMPTIONS")
print(f"  Calibration method ({best_calib}) stored in MODEL_VERSION_HISTORY.PROB_DISTRIBUTION")

# ─── Regression tests ────────────────────────────────────────────────
print("\n" + "=" * W)
print("REGRESSION TESTS")
print("=" * W)

tests = []
def check(name, passed, detail):
    tests.append((name, "PASS" if passed else "FAIL", detail))
    print(f"  [{'PASS' if passed else 'FAIL'}] {name}: {detail}")

# Threshold is in valid range
check("THRESHOLD_RANGE", 0.05 <= optimal_threshold <= 0.95,
      f"threshold={optimal_threshold}")
# Recall above business minimum at optimal threshold
check("RECALL_AT_THRESHOLD", final_metrics["recall"] >= 0.6,
      f"recall={final_metrics['recall']:.4f} >= 0.60")
# PR-AUC above baseline
check("PR_AUC_BASELINE", final_metrics["pr_auc"] >= 0.25,
      f"pr_auc={final_metrics['pr_auc']:.4f} >= 0.25")
# Brier score improved or maintained with calibration
check("CALIBRATION_IMPROVES_BRIER", best_brier <= base_brier + 0.01,
      f"calibrated={best_brier:.4f} vs base={base_brier:.4f}")
# ECE improved or maintained
check("CALIBRATION_IMPROVES_ECE", best_ece <= base_ece + 0.02,
      f"calibrated={best_ece:.4f} vs base={base_ece:.4f}")
# Risk tiers are monotonically ordered in DECISION_ASSUMPTIONS
check("RISK_TIERS_MONOTONIC",
      tier_map["CRITICAL"] > tier_map["HIGH"] > tier_map["MEDIUM"] > tier_map["LOW"],
      f"C={tier_map['CRITICAL']} > H={tier_map['HIGH']} > M={tier_map['MEDIUM']} > L={tier_map['LOW']}")
# Threshold persisted to DECISION_ASSUMPTIONS
r = session.sql("SELECT PARAM_VALUE FROM OTIF_GUARDIAN.ML.DECISION_ASSUMPTIONS WHERE PARAM_NAME='CLASSIFICATION_THRESHOLD'").collect()
check("THRESHOLD_PERSISTED", len(r) > 0 and float(r[0][0]) == optimal_threshold,
      f"stored={r[0][0] if r else 'MISSING'}")
# Model version has calibration metadata
r = session.sql("SELECT EXPECTED_CALIBRATION_ERROR, PROB_DISTRIBUTION FROM OTIF_GUARDIAN.AUDIT.MODEL_VERSION_HISTORY WHERE VERSION_NAME='V3-SQL-SCORING'").collect()
check("CALIBRATION_METADATA_PERSISTED", r[0][0] is not None and r[0][1] is not None,
      f"ECE={'set' if r[0][0] else 'null'}, PROB_DIST={'set' if r[0][1] else 'null'} (contains calibration_method)")
# No threshold hardcoded in Streamlit (check config.py)
import re
with open(r"C:\Users\vinos\supply-chain-otif-intelligence\streamlit\lib\config.py") as f:
    config_text = f.read()
has_hardcoded = bool(re.search(r'0\.33|0\.5.*threshold|BREACH_THRESHOLD\s*=', config_text, re.IGNORECASE))
check("NO_HARDCODED_THRESHOLD_IN_STREAMLIT", not has_hardcoded,
      "No hardcoded threshold in config.py" if not has_hardcoded else "Found hardcoded threshold!")

passed = sum(1 for t in tests if t[1] == "PASS")
print(f"\n  Regression tests: {passed}/{len(tests)} passed")

print("\n" + "=" * W)
print(f"DECISION LAYER VERDICT: {'PASS' if passed == len(tests) else 'FAIL'}")
print("=" * W)

session.close()
