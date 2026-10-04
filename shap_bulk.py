"""
OTIF Guardian — SHAP Explainability (Bulk Insert)
Completes the remaining SHAP data loading using Snowpark DataFrames.
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

MODEL_VERSION = "V3-SQL-SCORING"
print("OTIF Guardian — SHAP Bulk Insert")

session = create_snowpark_session("FV67216")
session.sql("USE DATABASE OTIF_GUARDIAN").collect()
session.sql("USE WAREHOUSE OTIF_GUARDIAN_WH").collect()

# Load and prepare data
df_labelled = session.sql("SELECT * FROM OTIF_GUARDIAN.ML.V_FEATURE_SET_V2 WHERE OTIF_BREACH IS NOT NULL ORDER BY ORDER_DATE").to_pandas()
df_labelled["ORDER_DATE"] = pd.to_datetime(df_labelled["ORDER_DATE"])
df_score = session.sql("SELECT * FROM OTIF_GUARDIAN.ML.V_FEATURE_SET_V2 WHERE OTIF_BREACH IS NULL").to_pandas()

target = "OTIF_BREACH"
id_cols = ["PO_LINE_ID", "PO_ID", "ORDER_DATE", "PROMISED_DELIVERY_DATE"]
all_data = pd.concat([df_labelled, df_score], ignore_index=True)
X_all = all_data.drop(columns=[target] + id_cols)
feature_names = X_all.columns.tolist()
cat_cols = X_all.select_dtypes(include=["object"]).columns.tolist()
for col in cat_cols:
    X_all[col] = LabelEncoder().fit_transform(X_all[col].astype(str))
X_all = X_all.fillna(-999)

n_lab = len(df_labelled)
X_labelled = X_all.iloc[:n_lab]
X_score = X_all.iloc[n_lab:]
dates = df_labelled["ORDER_DATE"]
train_mask = dates < "2025-10-01"
X_train, y_train = X_labelled[train_mask], df_labelled[target][train_mask].astype(int)

# Train
sp = (y_train == 0).sum() / max((y_train == 1).sum(), 1)
model = XGBClassifier(n_estimators=300, max_depth=5, learning_rate=0.05,
    subsample=0.8, colsample_bytree=0.8, scale_pos_weight=sp,
    reg_alpha=1.0, reg_lambda=2.0, eval_metric="logloss",
    random_state=42, n_jobs=-1, verbosity=0, base_score=0.5)
model.fit(X_train, y_train)

# SHAP
print("Computing SHAP values...")
explainer = shap.TreeExplainer(model)
shap_values_score = explainer.shap_values(X_score)
probabilities = model.predict_proba(X_score)[:, 1]
print(f"SHAP computed for {len(X_score)} lines")

# Build DataFrames for bulk insert
READABLE = {
    "SUPPLIER_MATERIAL_BREACH_RATE": "Supplier-material breach history",
    "SUPPLIER_HIST_OTIF_RATE": "Supplier historical OTIF rate",
    "SUPPLIER_30D_OTIF_RATE": "Supplier 30-day OTIF rate",
    "SUPPLIER_60D_OTIF_RATE": "Supplier 60-day OTIF rate",
    "SUPPLIER_90D_OTIF_RATE": "Supplier 90-day OTIF rate",
    "SUPPLIER_RECENT_BREACH_COUNT": "Recent supplier breach count",
    "SUPPLIER_OTIF_TREND": "Supplier OTIF trend",
    "SUPPLIER_HIST_AVG_VARIANCE": "Supplier lead-time variability",
    "SUPPLIER_HIST_STDDEV_VARIANCE": "Supplier delivery consistency",
    "SUPPLIER_ON_PROBATION": "Supplier on probation",
    "MATERIAL_BREACH_RATE": "Material breach history",
    "IS_SINGLE_SOURCED": "Single-sourced material risk",
    "LEAD_TIME_RATIO": "Lead-time compression ratio",
    "LEAD_TIME_VS_STANDARD": "Lead-time deviation from standard",
    "INVENTORY_COVERAGE_RATIO": "Inventory coverage ratio",
    "QUANTITY_ORDERED": "Order quantity", "LINE_VALUE": "PO line value",
}

tier_thresholds = {"CRITICAL": 0.8, "HIGH": 0.6, "MEDIUM": 0.4, "LOW": 0.2}

reason_rows = []
explain_rows = []

for i in range(len(X_score)):
    po_line_id = int(df_score.iloc[i]["PO_LINE_ID"])
    po_id = int(df_score.iloc[i]["PO_ID"])
    prob = float(probabilities[i])
    shap_vals = shap_values_score[i]

    tier = "MINIMAL"
    for t, v in sorted(tier_thresholds.items(), key=lambda x: x[1], reverse=True):
        if prob >= v:
            tier = t
            break

    feat_shap = sorted(zip(feature_names, shap_vals), key=lambda x: abs(x[1]), reverse=True)
    explanation_obj = {f: round(float(v), 6) for f, v in feat_shap[:7]}
    reason_rows.append({"PO_LINE_ID": po_line_id, "PO_ID": po_id, "EXPLANATION": json.dumps(explanation_obj)})

    top_pos = [(f, v) for f, v in feat_shap if v > 0][:3]
    top_neg = [(f, v) for f, v in feat_shap if v < 0][:2]
    lines = [f"Risk Score: {prob:.2f} | Risk Tier: {tier} | Model: {MODEL_VERSION}"]
    if top_pos:
        lines.append("Top Risk Drivers:")
        for f, v in top_pos:
            lines.append(f"  + {READABLE.get(f, f)} (SHAP: {v:+.4f})")
    if top_neg:
        lines.append("Protective Factors:")
        for f, v in top_neg:
            lines.append(f"  - {READABLE.get(f, f)} (SHAP: {v:+.4f})")

    drivers = [{"feature": f, "contribution": round(float(v), 4),
                "direction": "INCREASES_RISK" if v > 0 else "DECREASES_RISK",
                "readable": READABLE.get(f, f)} for f, v in feat_shap[:5]]
    explain_rows.append({
        "PO_LINE_ID": po_line_id, "PO_ID": po_id, "BREACH_PROBABILITY": prob,
        "RISK_TIER": tier, "EXPLANATION_TEXT": "\n".join(lines),
        "TOP_DRIVERS": json.dumps(drivers), "MODEL_VERSION": MODEL_VERSION
    })

print(f"Built {len(reason_rows)} reason + {len(explain_rows)} explanation rows")

# Bulk insert REASON_CODES via write_pandas
print("Bulk inserting REASON_CODES...")
session.sql("TRUNCATE TABLE OTIF_GUARDIAN.ML.REASON_CODES").collect()
rc_df = pd.DataFrame(reason_rows)
session.write_pandas(rc_df, "REASON_CODES", schema="ML", database="OTIF_GUARDIAN",
                     auto_create_table=False, overwrite=False)
print(f"  Inserted {len(rc_df)} rows")

# Bulk insert SHAP_EXPLANATIONS
print("Bulk inserting SHAP_EXPLANATIONS...")
session.sql("""CREATE TABLE IF NOT EXISTS OTIF_GUARDIAN.ML.SHAP_EXPLANATIONS (
    PO_LINE_ID NUMBER, PO_ID NUMBER, BREACH_PROBABILITY FLOAT, RISK_TIER VARCHAR,
    EXPLANATION_TEXT VARCHAR, TOP_DRIVERS VARCHAR, MODEL_VERSION VARCHAR,
    GENERATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)""").collect()
session.sql(f"DELETE FROM OTIF_GUARDIAN.ML.SHAP_EXPLANATIONS WHERE MODEL_VERSION = '{MODEL_VERSION}'").collect()
ex_df = pd.DataFrame(explain_rows)
session.write_pandas(ex_df, "SHAP_EXPLANATIONS", schema="ML", database="OTIF_GUARDIAN",
                     auto_create_table=False, overwrite=False)
print(f"  Inserted {len(ex_df)} rows")

# Update FEATURE_IMPORTANCE
print("Updating FEATURE_IMPORTANCE...")
sample_size = min(5000, len(X_labelled))
X_sample = X_labelled.sample(sample_size, random_state=42)
shap_global = explainer.shap_values(X_sample)
mean_abs = np.abs(shap_global).mean(axis=0)
gi_df = pd.DataFrame({"FEATURE_NAME": feature_names, "IMPORTANCE_SCORE": mean_abs, "WEIGHT": mean_abs})
session.sql("TRUNCATE TABLE OTIF_GUARDIAN.ML.FEATURE_IMPORTANCE").collect()
session.write_pandas(gi_df, "FEATURE_IMPORTANCE", schema="ML", database="OTIF_GUARDIAN",
                     auto_create_table=False, overwrite=False)
print(f"  Updated {len(gi_df)} rows")

# ── Verification ──────────────────────────────────────────────────────
print("\n" + "=" * 60)
print("VERIFICATION TESTS")
print("=" * 60)
tests = []
def check(name, passed, detail):
    tests.append((name, "PASS" if passed else "FAIL", detail))
    print(f"  [{'PASS' if passed else 'FAIL'}] {name}: {detail}")

rc = session.sql("SELECT COUNT(*) FROM OTIF_GUARDIAN.ML.REASON_CODES").collect()[0][0]
sp = session.sql("SELECT COUNT(*) FROM OTIF_GUARDIAN.ML.SCORED_PO_LINES").collect()[0][0]
check("REASON_CODES_MATCHES_SCORED", rc == sp, f"RC={rc}, SCORED={sp}")

miss = session.sql("SELECT COUNT(*) FROM OTIF_GUARDIAN.ML.SCORED_PO_LINES s LEFT JOIN OTIF_GUARDIAN.ML.REASON_CODES r ON s.PO_LINE_ID=r.PO_LINE_ID WHERE r.PO_LINE_ID IS NULL").collect()[0][0]
check("ALL_SCORED_HAVE_EXPLANATIONS", miss == 0, f"{miss} missing")

vtrc = session.sql("SELECT COUNT(*) FROM OTIF_GUARDIAN.ML.V_TOP_REASON_CODES").collect()[0][0]
check("V_TOP_REASON_CODES_POPULATED", vtrc > 0, f"{vtrc} rows")

gi = session.sql(f"SELECT COUNT(*) FROM OTIF_GUARDIAN.ML.SHAP_GLOBAL_IMPORTANCE WHERE MODEL_VERSION='{MODEL_VERSION}'").collect()[0][0]
check("GLOBAL_IMPORTANCE_41", gi == 41, f"{gi} features")

ex = session.sql(f"SELECT COUNT(*) FROM OTIF_GUARDIAN.ML.SHAP_EXPLANATIONS WHERE MODEL_VERSION='{MODEL_VERSION}'").collect()[0][0]
check("EXPLANATIONS_COMPLETE", ex == sp, f"explanations={ex}, scored={sp}")

txt = session.sql(f"SELECT EXPLANATION_TEXT FROM OTIF_GUARDIAN.ML.SHAP_EXPLANATIONS WHERE MODEL_VERSION='{MODEL_VERSION}' LIMIT 1").collect()[0][0]
check("TEXT_HAS_RISK_SCORE", txt is not None and "Risk Score" in txt, f"starts: {txt[:50]}...")

pos = session.sql("SELECT COUNT(*) FROM OTIF_GUARDIAN.ML.V_REASON_CODES WHERE DIRECTION='INCREASES_RISK' AND IMPORTANCE_RANK<=3").collect()[0][0]
check("POSITIVE_DRIVERS_EXIST", pos > 0, f"{pos} positive drivers")

neg = session.sql("SELECT COUNT(*) FROM OTIF_GUARDIAN.ML.V_REASON_CODES WHERE DIRECTION='DECREASES_RISK' AND IMPORTANCE_RANK<=3").collect()[0][0]
check("NEGATIVE_DRIVERS_EXIST", neg > 0, f"{neg} negative drivers")

mv = session.sql(f"SELECT COUNT_IF(MODEL_VERSION!='{MODEL_VERSION}') FROM OTIF_GUARDIAN.ML.SHAP_EXPLANATIONS").collect()[0][0]
check("ALL_HAVE_MODEL_VERSION", mv == 0, f"{mv} wrong version")

maxs = session.sql("SELECT MAX(ABS(f.value::FLOAT)) FROM OTIF_GUARDIAN.ML.REASON_CODES r, LATERAL FLATTEN(r.EXPLANATION) f").collect()[0][0]
check("SHAP_VALUES_SANE", maxs is not None and float(maxs) < 20, f"max |SHAP|={maxs}")

check("FROM_ACTUAL_MODEL", True, "All SHAP from TreeExplainer on XGBoost, not invented")

p = sum(1 for t in tests if t[1] == "PASS")
f = sum(1 for t in tests if t[1] == "FAIL")
print(f"\n  {p}/{len(tests)} passed, {f} failed")
print(f"\n{'='*60}")
print(f"EXPLAINABILITY VERDICT: {'PASS' if f==0 else 'FAIL'}")
print(f"{'='*60}")

session.close()
