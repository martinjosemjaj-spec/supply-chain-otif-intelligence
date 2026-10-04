"""
OTIF Guardian - XGBoost Classification Model Evaluation
Evaluates breach prediction using 80/20 stratified split + 5-fold CV.
"""
import sys
sys.path.insert(0, r"C:\Users\vinos\supply-chain-otif-intelligence")
from snowpark_session import create_snowpark_session
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split, StratifiedKFold, cross_validate
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import (
    accuracy_score, precision_score, recall_score, f1_score, roc_auc_score,
    classification_report, confusion_matrix
)
from xgboost import XGBClassifier
import warnings
warnings.filterwarnings("ignore")

print("=" * 70)
print("OTIF Guardian - XGBoost Breach Prediction Model Evaluation")
print("=" * 70)

# 1. Connect and load data
print("\n[1/6] Loading training data from OTIF_GUARDIAN.ML.TRAIN_DATA_V2...")
session = create_snowpark_session("FV67216")
session.sql("USE DATABASE OTIF_GUARDIAN").collect()
session.sql("USE WAREHOUSE OTIF_GUARDIAN_WH").collect()

df = session.table("OTIF_GUARDIAN.ML.TRAIN_DATA_V2").to_pandas()
print(f"  Dataset shape: {df.shape}")
print(f"  Target distribution:")
print(f"    No Breach (0): {(df['OTIF_BREACH'] == 0).sum()} ({(df['OTIF_BREACH'] == 0).mean():.1%})")
print(f"    Breach (1):    {(df['OTIF_BREACH'] == 1).sum()} ({(df['OTIF_BREACH'] == 1).mean():.1%})")

# 2. Prepare features
print("\n[2/6] Preparing features...")
target = "OTIF_BREACH"
y = df[target].astype(int)
X = df.drop(columns=[target])

cat_cols = X.select_dtypes(include=["object"]).columns.tolist()
label_encoders = {}
for col in cat_cols:
    le = LabelEncoder()
    X[col] = le.fit_transform(X[col].astype(str))
    label_encoders[col] = le

X = X.fillna(-999)
print(f"  Features: {X.shape[1]} ({len(cat_cols)} categorical encoded)")
print(f"  Categorical columns: {cat_cols}")

# 3. Stratified 80/20 split
print("\n[3/6] Splitting data (80% train / 20% holdout, stratified)...")
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.20, random_state=42, stratify=y
)
print(f"  Train set: {X_train.shape[0]} rows (breach rate: {y_train.mean():.4f})")
print(f"  Test set:  {X_test.shape[0]} rows (breach rate: {y_test.mean():.4f})")

# 4. Train XGBoost
print("\n[4/6] Training XGBoost classifier...")
scale_pos = (y_train == 0).sum() / max((y_train == 1).sum(), 1)
model = XGBClassifier(
    n_estimators=300,
    max_depth=5,
    learning_rate=0.05,
    subsample=0.8,
    colsample_bytree=0.8,
    scale_pos_weight=scale_pos,
    reg_alpha=1.0,
    reg_lambda=2.0,
    eval_metric="logloss",
    random_state=42,
    n_jobs=-1,
    verbosity=0,
)
model.fit(X_train, y_train)
print(f"  Model trained with {model.n_estimators} trees, max_depth={model.max_depth}")
print(f"  scale_pos_weight={scale_pos:.2f} (to handle class imbalance)")

# 5. Stratified 5-Fold Cross-Validation on training set
print("\n[5/6] Running Stratified 5-Fold Cross-Validation on 80% training data...")
cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
scoring = ["accuracy", "precision", "recall", "f1", "roc_auc"]
cv_results = cross_validate(model, X_train, y_train, cv=cv, scoring=scoring, return_train_score=True)

print("\n" + "=" * 70)
print("CROSS-VALIDATION RESULTS (5-Fold on 80% Training Data)")
print("=" * 70)
print(f"{'Metric':<20} {'Mean':>10} {'Std':>10} {'Train Mean':>12}")
print("-" * 55)
for metric in scoring:
    test_key = f"test_{metric}"
    train_key = f"train_{metric}"
    mean_val = cv_results[test_key].mean()
    std_val = cv_results[test_key].std()
    train_mean = cv_results[train_key].mean()
    print(f"  {metric:<18} {mean_val:>9.4f} {std_val:>9.4f} {train_mean:>11.4f}")

# 6. Holdout Test Set Evaluation
print("\n" + "=" * 70)
print("HOLDOUT TEST SET RESULTS (20% Stratified)")
print("=" * 70)

y_pred = model.predict(X_test)
y_prob = model.predict_proba(X_test)[:, 1]

acc = accuracy_score(y_test, y_pred)
prec = precision_score(y_test, y_pred, zero_division=0)
rec = recall_score(y_test, y_pred, zero_division=0)
f1 = f1_score(y_test, y_pred, zero_division=0)
roc = roc_auc_score(y_test, y_prob)

print(f"  {'Accuracy':<20} {acc:.4f}")
print(f"  {'Precision':<20} {prec:.4f}")
print(f"  {'Recall':<20} {rec:.4f}")
print(f"  {'F1-Score':<20} {f1:.4f}")
print(f"  {'ROC-AUC':<20} {roc:.4f}")

print("\n  Confusion Matrix:")
cm = confusion_matrix(y_test, y_pred)
print(f"                  Predicted 0  Predicted 1")
print(f"    Actual 0       {cm[0][0]:>7}      {cm[0][1]:>7}")
print(f"    Actual 1       {cm[1][0]:>7}      {cm[1][1]:>7}")

print("\n  Classification Report:")
print(classification_report(y_test, y_pred, target_names=["No Breach", "Breach"]))

# 7. Overfitting Analysis
print("=" * 70)
print("OVERFITTING ANALYSIS")
print("=" * 70)

y_train_pred = model.predict(X_train)
y_train_prob = model.predict_proba(X_train)[:, 1]
train_acc = accuracy_score(y_train, y_train_pred)
train_f1 = f1_score(y_train, y_train_pred, zero_division=0)
train_roc = roc_auc_score(y_train, y_train_prob)

print(f"\n  {'Metric':<20} {'Train':>10} {'CV Mean':>10} {'Test':>10} {'Train-Test Gap':>15}")
print("  " + "-" * 67)
cv_acc = cv_results["test_accuracy"].mean()
cv_f1 = cv_results["test_f1"].mean()
cv_roc = cv_results["test_roc_auc"].mean()
print(f"  {'Accuracy':<20} {train_acc:>9.4f} {cv_acc:>9.4f} {acc:>9.4f} {train_acc - acc:>14.4f}")
print(f"  {'F1-Score':<20} {train_f1:>9.4f} {cv_f1:>9.4f} {f1:>9.4f} {train_f1 - f1:>14.4f}")
print(f"  {'ROC-AUC':<20} {train_roc:>9.4f} {cv_roc:>9.4f} {roc:>9.4f} {train_roc - roc:>14.4f}")

gap_f1 = train_f1 - f1
gap_roc = train_roc - roc
if gap_f1 < 0.05 and gap_roc < 0.05:
    verdict = "MINIMAL overfitting - model generalizes well"
elif gap_f1 < 0.10 and gap_roc < 0.10:
    verdict = "MODERATE overfitting - consider regularization"
else:
    verdict = "SIGNIFICANT overfitting - needs stronger regularization or more data"
print(f"\n  Verdict: {verdict}")

# 8. Top Feature Importances
print("\n" + "=" * 70)
print("TOP 10 FEATURE IMPORTANCES (gain)")
print("=" * 70)
fi = pd.Series(model.feature_importances_, index=X.columns).sort_values(ascending=False)
for i, (feat, imp) in enumerate(fi.head(10).items()):
    bar = "#" * int(imp * 100)
    print(f"  {i+1:>2}. {feat:<40} {imp:.4f}  {bar}")

# 9. Summary
print("\n" + "=" * 70)
print("SUMMARY & RECOMMENDATIONS")
print("=" * 70)
print(f"""
  Model: XGBoost ({model.n_estimators} trees, max_depth={model.max_depth})
  Data:  {len(df)} samples, {X.shape[1]} features, {y.mean():.1%} breach rate

  Performance:
    - ROC-AUC:   {roc:.4f} (CV: {cv_roc:.4f} +/- {cv_results['test_roc_auc'].std():.4f})
    - F1-Score:  {f1:.4f} (CV: {cv_f1:.4f} +/- {cv_results['test_f1'].std():.4f})
    - Recall:    {rec:.4f} (catches {rec:.0%} of actual breaches)
    - Precision: {prec:.4f} ({prec:.0%} of breach alerts are correct)

  Overfitting: {verdict}

  Recommendations:
    1. {"Recall is strong (>{:.0%}) - good breach detection".format(rec) if rec > 0.7 else "Recall is low ({:.0%}) - consider SMOTE oversampling or threshold tuning to catch more breaches".format(rec)}
    2. {"Precision is acceptable" if prec > 0.5 else "Precision is low ({:.0%}) - many false alarms. Feature engineering or threshold optimization may help".format(prec)}
    3. {"ROC-AUC > 0.90 indicates excellent discriminative ability" if roc > 0.90 else "ROC-AUC of {:.4f} shows good but improvable discrimination - consider adding more features".format(roc)}
    4. Class imbalance ({y.mean():.1%} breach rate) - SMOTE, class weights, or threshold calibration recommended
    5. Consider isotonic probability calibration for more reliable risk tier assignments
""")

session.close()
print("Done.")
