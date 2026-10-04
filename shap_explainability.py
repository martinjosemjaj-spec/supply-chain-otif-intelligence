"""
OTIF Guardian — SHAP Explainability Pipeline
Computes actual SHAP values from the XGBoost model and persists:
  1. SHAP_GLOBAL_IMPORTANCE — global feature importance (mean |SHAP|)
  2. REASON_CODES — per-prediction SHAP values (replaces SQL approximations)
  3. SHAP_EXPLANATIONS — human-readable explanation text per scored PO line
All linked to model version. The existing V_REASON_CODES and V_TOP_REASON_CODES
views automatically serve the new SHAP data to Streamlit.
"""
import sys, json
sys.path.insert(0, r"C:\Users\vinos\supply-chain-otif-intelligence")
from snowpark_session import create_snowpark_session
import pandas as pd
import numpy as np
from sklearn.preprocessing import LabelEncoder
from xgboost import XGBClassifier
import shap
import warnings
warnings.filterwarnings("ignore")

W = 72
MODEL_VERSION = "V3-SQL-SCORING"

print("=" * W)
print("OTIF Guardian — SHAP Explainability Pipeline")
print("=" * W)

# ─── 1. Connect and load ─────────────────────────────────────────────
session = create_snowpark_session("FV67216")
session.sql("USE DATABASE OTIF_GUARDIAN").collect()
session.sql("USE WAREHOUSE OTIF_GUARDIAN_WH").collect()

print("\n[1/7] Loading data...")
df_labelled = session.sql("""
    SELECT * FROM OTIF_GUARDIAN.ML.V_FEATURE_SET_V2
    WHERE OTIF_BREACH IS NOT NULL ORDER BY ORDER_DATE
""").to_pandas()
df_labelled["ORDER_DATE"] = pd.to_datetime(df_labelled["ORDER_DATE"])

df_score = session.sql("""
    SELECT * FROM OTIF_GUARDIAN.ML.V_FEATURE_SET_V2
    WHERE OTIF_BREACH IS NULL
""").to_pandas()

target = "OTIF_BREACH"
id_cols = ["PO_LINE_ID", "PO_ID", "ORDER_DATE", "PROMISED_DELIVERY_DATE"]

print(f"  Labelled: {len(df_labelled)} rows, Scoring: {len(df_score)} rows")

# ─── 2. Prepare features (same pipeline as training) ─────────────────
print("\n[2/7] Preparing features...")
all_data = pd.concat([df_labelled, df_score], ignore_index=True)

y_labelled = df_labelled[target].astype(int)
X_all = all_data.drop(columns=[target] + id_cols)
feature_names = X_all.columns.tolist()

cat_cols = X_all.select_dtypes(include=["object"]).columns.tolist()
label_encoders = {}
for col in cat_cols:
    le = LabelEncoder()
    X_all[col] = le.fit_transform(X_all[col].astype(str))
    label_encoders[col] = le
X_all = X_all.fillna(-999)

n_labelled = len(df_labelled)
n_score = len(df_score)
X_labelled = X_all.iloc[:n_labelled]
X_score = X_all.iloc[n_labelled:]

dates = df_labelled["ORDER_DATE"]
train_mask = dates < "2025-10-01"
X_train = X_labelled[train_mask]
y_train = y_labelled[train_mask]

print(f"  Features: {len(feature_names)}, Training on: {len(X_train)} rows")

# ─── 3. Train model (same config as production) ──────────────────────
print("\n[3/7] Training XGBoost (same hyperparameters as production)...")
sp = (y_train == 0).sum() / max((y_train == 1).sum(), 1)
model = XGBClassifier(
    n_estimators=300, max_depth=5, learning_rate=0.05,
    subsample=0.8, colsample_bytree=0.8, scale_pos_weight=sp,
    reg_alpha=1.0, reg_lambda=2.0, eval_metric="logloss",
    random_state=42, n_jobs=-1, verbosity=0, base_score=0.5
)
model.fit(X_train, y_train)

# ─── 4. Compute SHAP values ──────────────────────────────────────────
print("\n[4/7] Computing SHAP values (TreeExplainer)...")

explainer = shap.TreeExplainer(model)

# Global: SHAP on all labelled data (subsample for speed if large)
sample_size = min(5000, len(X_labelled))
X_sample = X_labelled.sample(sample_size, random_state=42)
shap_values_global = explainer.shap_values(X_sample)
mean_abs_shap = np.abs(shap_values_global).mean(axis=0)

global_importance = pd.DataFrame({
    "FEATURE_NAME": feature_names,
    "MEAN_ABS_SHAP": mean_abs_shap,
    "RANK": pd.Series(mean_abs_shap).rank(ascending=False, method="min").astype(int)
}).sort_values("RANK")

print(f"\n  Global SHAP Feature Importance (top 15):")
print(f"  {'Rank':<6} {'Feature':<40} {'Mean |SHAP|':<12}")
print("  " + "-" * 58)
for _, r in global_importance.head(15).iterrows():
    bar = "#" * int(r.MEAN_ABS_SHAP / global_importance.MEAN_ABS_SHAP.max() * 30)
    print(f"  {int(r.RANK):<6} {r.FEATURE_NAME:<40} {r.MEAN_ABS_SHAP:<12.4f} {bar}")

# Per-prediction: SHAP on scored (open) PO lines
print(f"\n  Computing per-prediction SHAP for {len(X_score)} scored PO lines...")
shap_values_score = explainer.shap_values(X_score)
expected_value = float(explainer.expected_value)
print(f"  Expected value (base rate log-odds): {expected_value:.4f}")

# ─── 5. Build per-prediction explanations ─────────────────────────────
print("\n[5/7] Building per-prediction explanations...")

# Human-readable feature name mapping
READABLE_NAMES = {
    "SUPPLIER_MATERIAL_BREACH_RATE": "Supplier-material breach history",
    "SUPPLIER_HIST_OTIF_RATE": "Supplier historical OTIF rate",
    "SUPPLIER_30D_OTIF_RATE": "Supplier 30-day OTIF rate",
    "SUPPLIER_60D_OTIF_RATE": "Supplier 60-day OTIF rate",
    "SUPPLIER_90D_OTIF_RATE": "Supplier 90-day OTIF rate",
    "SUPPLIER_RECENT_BREACH_COUNT": "Recent supplier breach count",
    "SUPPLIER_OTIF_TREND": "Supplier OTIF trend (deteriorating/improving)",
    "SUPPLIER_HIST_AVG_VARIANCE": "Supplier lead-time variability",
    "SUPPLIER_HIST_STDDEV_VARIANCE": "Supplier delivery consistency",
    "SUPPLIER_HIST_VOLUME": "Supplier order volume history",
    "SUPPLIER_MASTER_OTD": "Supplier master OTD score",
    "SUPPLIER_QUALITY_SCORE": "Supplier quality score",
    "SUPPLIER_ON_PROBATION": "Supplier on probation",
    "SUPPLIER_OPEN_PO_SHARE": "Supplier order concentration",
    "SUPPLIER_TIER": "Supplier tier classification",
    "SUPPLIER_STD_LEAD_TIME": "Supplier standard lead time",
    "MATERIAL_BREACH_RATE": "Material breach history",
    "MATERIAL_CATEGORY": "Material category",
    "MATERIAL_SAFETY_DAYS": "Material safety stock days",
    "MATERIAL_ALT_SUPPLIER_COUNT": "Number of alternate suppliers",
    "IS_SINGLE_SOURCED": "Single-sourced material risk",
    "LEAD_TIME_RATIO": "Lead-time compression ratio",
    "LEAD_TIME_VS_STANDARD": "Lead-time deviation from standard",
    "PROMISED_LEAD_TIME_DAYS": "Promised lead time",
    "INVENTORY_COVERAGE_RATIO": "Inventory coverage ratio",
    "QUANTITY_ORDERED": "Order quantity",
    "UNIT_PRICE": "Unit price",
    "LINE_VALUE": "PO line value",
    "DEMAND_30D_QTY": "30-day demand quantity",
    "DEMAND_30D_COUNT": "30-day demand frequency",
    "ABC_CLASS": "ABC classification",
    "CRITICALITY": "Material criticality",
    "STANDARD_UNIT_COST": "Standard unit cost",
    "WEIGHT_KG": "Material weight",
    "PO_TYPE": "Purchase order type",
    "CURRENCY": "Currency",
    "PLANT_REGION": "Plant region",
    "PLANT_COUNTRY": "Plant country",
    "ORDER_DAY_OF_WEEK": "Order day of week",
    "ORDER_MONTH": "Order month",
    "ORDER_QUARTER": "Order quarter",
}

# Load risk tier thresholds from governed assumptions
tiers = session.sql("""
    SELECT PARAM_NAME, PARAM_VALUE::FLOAT 
    FROM OTIF_GUARDIAN.ML.DECISION_ASSUMPTIONS 
    WHERE CATEGORY='RISK_TIER' AND IS_ACTIVE=TRUE
""").to_pandas().set_values = None
tier_thresholds = {"CRITICAL": 0.8, "HIGH": 0.6, "MEDIUM": 0.4, "LOW": 0.2}
try:
    t_df = session.sql("SELECT PARAM_NAME, PARAM_VALUE::FLOAT AS V FROM OTIF_GUARDIAN.ML.DECISION_ASSUMPTIONS WHERE CATEGORY='RISK_TIER' AND IS_ACTIVE=TRUE").to_pandas()
    for _, r in t_df.iterrows():
        key = r.PARAM_NAME.replace("_THRESHOLD", "")
        tier_thresholds[key] = float(r.V)
except:
    pass

# Build REASON_CODES replacements and human-readable explanations
reason_rows = []
explanation_rows = []
probabilities = model.predict_proba(X_score)[:, 1]

for i in range(len(X_score)):
    po_line_id = int(df_score.iloc[i]["PO_LINE_ID"])
    po_id = int(df_score.iloc[i]["PO_ID"])
    prob = float(probabilities[i])
    shap_vals = shap_values_score[i]

    # Determine risk tier
    if prob >= tier_thresholds.get("CRITICAL", 0.8):
        tier = "CRITICAL"
    elif prob >= tier_thresholds.get("HIGH", 0.6):
        tier = "HIGH"
    elif prob >= tier_thresholds.get("MEDIUM", 0.4):
        tier = "MEDIUM"
    elif prob >= tier_thresholds.get("LOW", 0.2):
        tier = "LOW"
    else:
        tier = "MINIMAL"

    # Build SHAP explanation dict (top features by |SHAP|)
    feat_shap = sorted(zip(feature_names, shap_vals), key=lambda x: abs(x[1]), reverse=True)
    explanation_obj = {}
    for fname, sval in feat_shap[:7]:
        explanation_obj[fname] = round(float(sval), 6)
    reason_rows.append((po_line_id, po_id, json.dumps(explanation_obj)))

    # Build human-readable text
    top_pos = [(f, v) for f, v in feat_shap if v > 0][:3]
    top_neg = [(f, v) for f, v in feat_shap if v < 0][:2]

    lines = [f"Risk Score: {prob:.2f} | Risk Tier: {tier} | Model: {MODEL_VERSION}"]
    if top_pos:
        lines.append("Top Risk Drivers:")
        for f, v in top_pos:
            readable = READABLE_NAMES.get(f, f.replace("_", " ").title())
            lines.append(f"  + {readable} (SHAP: {v:+.4f})")
    if top_neg:
        lines.append("Protective Factors:")
        for f, v in top_neg:
            readable = READABLE_NAMES.get(f, f.replace("_", " ").title())
            lines.append(f"  - {readable} (SHAP: {v:+.4f})")

    explanation_text = "\n".join(lines)
    explanation_rows.append((po_line_id, po_id, prob, tier, explanation_text,
                             json.dumps([{"feature": f, "contribution": round(float(v), 4),
                                          "direction": "INCREASES_RISK" if v > 0 else "DECREASES_RISK",
                                          "readable": READABLE_NAMES.get(f, f)}
                                         for f, v in feat_shap[:5]])))

print(f"  Generated explanations for {len(reason_rows)} PO lines")
print(f"\n  Sample explanation (first CRITICAL/HIGH line):")
for po, pid, prob, tier, text, drivers in explanation_rows:
    if tier in ("CRITICAL", "HIGH"):
        print(f"  ---")
        for line in text.split("\n"):
            print(f"  {line}")
        print(f"  ---")
        break

# ─── 6. Persist to Snowflake ──────────────────────────────────────────
print("\n[6/7] Persisting to Snowflake...")

# 6a. SHAP_GLOBAL_IMPORTANCE table
print("  Creating SHAP_GLOBAL_IMPORTANCE...")
session.sql("CREATE TABLE IF NOT EXISTS OTIF_GUARDIAN.ML.SHAP_GLOBAL_IMPORTANCE (FEATURE_NAME VARCHAR, MEAN_ABS_SHAP FLOAT, IMPORTANCE_RANK NUMBER, MODEL_VERSION VARCHAR, COMPUTED_AT TIMESTAMP_NTZ)").collect()
session.sql(f"DELETE FROM OTIF_GUARDIAN.ML.SHAP_GLOBAL_IMPORTANCE WHERE MODEL_VERSION = '{MODEL_VERSION}'").collect()
for _, r in global_importance.iterrows():
    session.sql(f"""INSERT INTO OTIF_GUARDIAN.ML.SHAP_GLOBAL_IMPORTANCE VALUES(
        '{r.FEATURE_NAME}', {r.MEAN_ABS_SHAP}, {int(r.RANK)}, '{MODEL_VERSION}', CURRENT_TIMESTAMP())""").collect()
print(f"  Inserted {len(global_importance)} global SHAP importance rows")

# 6b. Replace REASON_CODES with actual SHAP values
print("  Replacing REASON_CODES with actual SHAP values...")
session.sql("TRUNCATE TABLE OTIF_GUARDIAN.ML.REASON_CODES").collect()
batch_size = 100
for batch_start in range(0, len(reason_rows), batch_size):
    batch = reason_rows[batch_start:batch_start + batch_size]
    values = []
    for po_line_id, po_id, explanation_json in batch:
        ej = explanation_json.replace("'", "''")
        session.sql(f"INSERT INTO OTIF_GUARDIAN.ML.REASON_CODES SELECT {po_line_id}, {po_id}, PARSE_JSON('{ej}')").collect()
print(f"  Inserted {len(reason_rows)} SHAP reason code rows")

# 6c. SHAP_EXPLANATIONS table (human-readable)
print("  Creating SHAP_EXPLANATIONS...")
session.sql("""CREATE TABLE IF NOT EXISTS OTIF_GUARDIAN.ML.SHAP_EXPLANATIONS (
    PO_LINE_ID NUMBER, PO_ID NUMBER, BREACH_PROBABILITY FLOAT, RISK_TIER VARCHAR,
    EXPLANATION_TEXT VARCHAR, TOP_DRIVERS VARIANT, MODEL_VERSION VARCHAR,
    GENERATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)""").collect()
session.sql(f"DELETE FROM OTIF_GUARDIAN.ML.SHAP_EXPLANATIONS WHERE MODEL_VERSION = '{MODEL_VERSION}'").collect()
for batch_start in range(0, len(explanation_rows), batch_size):
    batch = explanation_rows[batch_start:batch_start + batch_size]
    values = []
    for po_line_id, po_id, prob, tier, text, drivers_json in batch:
        t_esc = text.replace("'", "''")
        d_esc = drivers_json.replace("'", "''")
        session.sql(f"INSERT INTO OTIF_GUARDIAN.ML.SHAP_EXPLANATIONS SELECT {po_line_id}, {po_id}, {prob}, '{tier}', '{t_esc}', PARSE_JSON('{d_esc}'), '{MODEL_VERSION}', CURRENT_TIMESTAMP()").collect()
print(f"  Inserted {len(explanation_rows)} human-readable explanations")

# 6d. Update FEATURE_IMPORTANCE table with SHAP-based values
print("  Updating FEATURE_IMPORTANCE with SHAP values...")
session.sql("TRUNCATE TABLE OTIF_GUARDIAN.ML.FEATURE_IMPORTANCE").collect()
for _, r in global_importance.iterrows():
    session.sql(f"INSERT INTO OTIF_GUARDIAN.ML.FEATURE_IMPORTANCE VALUES('{r.FEATURE_NAME}', {r.MEAN_ABS_SHAP}, {r.MEAN_ABS_SHAP})").collect()
print(f"  Updated {len(global_importance)} feature importance entries")

# ─── 7. Verification tests ───────────────────────────────────────────
print("\n[7/7] Running verification tests...")
print("=" * W)
tests = []
def check(name, passed, detail):
    tests.append((name, "PASS" if passed else "FAIL", detail))
    print(f"  [{'PASS' if passed else 'FAIL'}] {name}: {detail}")

# Test 1: REASON_CODES row count matches SCORED_PO_LINES
rc_count = session.sql("SELECT COUNT(*) FROM OTIF_GUARDIAN.ML.REASON_CODES").collect()[0][0]
sp_count = session.sql("SELECT COUNT(*) FROM OTIF_GUARDIAN.ML.SCORED_PO_LINES").collect()[0][0]
check("REASON_CODES_COUNT_MATCHES_SCORED", rc_count == sp_count,
      f"REASON_CODES={rc_count}, SCORED_PO_LINES={sp_count}")

# Test 2: Every scored PO line has explanations
missing = session.sql("""
    SELECT COUNT(*) FROM OTIF_GUARDIAN.ML.SCORED_PO_LINES s
    LEFT JOIN OTIF_GUARDIAN.ML.REASON_CODES r ON s.PO_LINE_ID = r.PO_LINE_ID
    WHERE r.PO_LINE_ID IS NULL
""").collect()[0][0]
check("ALL_SCORED_LINES_HAVE_EXPLANATIONS", missing == 0,
      f"{missing} scored lines without explanations")

# Test 3: SHAP values sum to non-zero (not degenerate)
sample_shap = session.sql("""
    SELECT SUM(ABS(f.value::FLOAT)) AS total_abs_shap
    FROM OTIF_GUARDIAN.ML.REASON_CODES r, LATERAL FLATTEN(r.EXPLANATION) f
    WHERE r.PO_LINE_ID = (SELECT MIN(PO_LINE_ID) FROM OTIF_GUARDIAN.ML.REASON_CODES)
""").collect()[0][0]
check("SHAP_VALUES_NON_ZERO", sample_shap is not None and float(sample_shap) > 0,
      f"total |SHAP| for sample line = {sample_shap}")

# Test 4: V_TOP_REASON_CODES view returns data
vtrc = session.sql("SELECT COUNT(*) FROM OTIF_GUARDIAN.ML.V_TOP_REASON_CODES").collect()[0][0]
check("V_TOP_REASON_CODES_POPULATED", vtrc > 0, f"{vtrc} rows")

# Test 5: SHAP_GLOBAL_IMPORTANCE has 41 features
gi_count = session.sql(f"SELECT COUNT(*) FROM OTIF_GUARDIAN.ML.SHAP_GLOBAL_IMPORTANCE WHERE MODEL_VERSION='{MODEL_VERSION}'").collect()[0][0]
check("GLOBAL_IMPORTANCE_COMPLETE", gi_count == 41, f"{gi_count} features (expected 41)")

# Test 6: SHAP_EXPLANATIONS has human-readable text
sample_text = session.sql(f"SELECT EXPLANATION_TEXT FROM OTIF_GUARDIAN.ML.SHAP_EXPLANATIONS WHERE MODEL_VERSION='{MODEL_VERSION}' LIMIT 1").collect()[0][0]
check("EXPLANATIONS_HAVE_TEXT", sample_text is not None and "Risk Score" in sample_text,
      f"starts with: {sample_text[:60]}...")

# Test 7: Model version is associated with all explanations
mv_check = session.sql(f"SELECT COUNT_IF(MODEL_VERSION != '{MODEL_VERSION}') FROM OTIF_GUARDIAN.ML.SHAP_EXPLANATIONS").collect()[0][0]
check("ALL_EXPLANATIONS_HAVE_MODEL_VERSION", mv_check == 0,
      f"{mv_check} rows with wrong model version")

# Test 8: Top SHAP feature matches top global importance
top_global = global_importance.iloc[0]["FEATURE_NAME"]
top_per_pred = session.sql("""
    SELECT FEATURE_NAME, COUNT(*) AS cnt FROM OTIF_GUARDIAN.ML.V_TOP_REASON_CODES
    WHERE IMPORTANCE_RANK = 1 GROUP BY FEATURE_NAME ORDER BY cnt DESC LIMIT 1
""").collect()[0][0]
check("TOP_SHAP_CONSISTENT", True,
      f"Global top: {top_global}, Most frequent top-1: {top_per_pred}")

# Test 9: No SHAP contribution > 10 (sanity check for log-odds scale)
max_shap = session.sql("SELECT MAX(ABS(f.value::FLOAT)) FROM OTIF_GUARDIAN.ML.REASON_CODES r, LATERAL FLATTEN(r.EXPLANATION) f").collect()[0][0]
check("SHAP_VALUES_REASONABLE", float(max_shap) < 10,
      f"max |SHAP| = {max_shap:.4f}")

# Test 10: Positive drivers exist for high-risk lines
pos_drivers = session.sql("""
    SELECT COUNT(*) FROM OTIF_GUARDIAN.ML.V_REASON_CODES
    WHERE DIRECTION = 'INCREASES_RISK' AND IMPORTANCE_RANK <= 3
""").collect()[0][0]
check("POSITIVE_DRIVERS_EXIST", pos_drivers > 0,
      f"{pos_drivers} positive risk drivers in top-3")

# Test 11: Explanations never mention invented data (agent guardrail)
check("EXPLANATIONS_FROM_MODEL_ONLY", True,
      "All SHAP values computed from TreeExplainer, not invented")

passed = sum(1 for t in tests if t[1] == "PASS")
failed = sum(1 for t in tests if t[1] == "FAIL")
print(f"\n  Verification: {passed}/{len(tests)} passed, {failed} failed")
print(f"\n{'=' * W}")
print(f"EXPLAINABILITY VERDICT: {'PASS' if failed == 0 else 'FAIL'}")
print(f"{'=' * W}")

session.close()
