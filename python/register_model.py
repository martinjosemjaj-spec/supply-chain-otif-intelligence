"""
OTIF Guardian - Register Model in Snowflake Model Registry
Run from CLI: python python/register_model.py
Requires: pip install snowflake-ml-python snowflake-connector-python xgboost scikit-learn
"""
import os, sys, tempfile, json
import joblib
import pandas as pd
import numpy as np

def main():
    from snowflake.snowpark import Session
    from snowflake.ml.registry import Registry
    from sklearn.preprocessing import LabelEncoder

    print("Connecting to Snowflake...")
    session = Session.builder.configs({
        "account": "SNNEIIG-OT77826",
        "user": "SNOWRUBAN",
        "authenticator": "externalbrowser",
        "database": "OTIF_GUARDIAN",
        "schema": "ML",
        "warehouse": "OTIF_GUARDIAN_WH"
    }).create()
    print("Connected.")

    # Download model from stage
    tmpdir = tempfile.mkdtemp()
    print(f"Downloading model artifact to {tmpdir}...")
    session.sql(f"GET @OTIF_GUARDIAN.ML.MODEL_STAGE/breach_model_v2/improved_model.joblib 'file://{tmpdir}'").collect()

    model_path = os.path.join(tmpdir, "improved_model.joblib")
    if not os.path.exists(model_path):
        print("ERROR: Model artifact not found")
        sys.exit(1)

    model_data = joblib.load(model_path)
    print(f"Model artifact loaded ({type(model_data)})")

    # Extract model object
    if isinstance(model_data, dict):
        model_obj = model_data.get("calibrated_model", model_data.get("model"))
        threshold = model_data.get("threshold", 0.33)
        print(f"Extracted calibrated model (threshold={threshold})")
    else:
        model_obj = model_data
        threshold = 0.50
        print("Using raw model object")

    # Build sample input
    cat_cols = ['MATERIAL_CATEGORY','ABC_CLASS','CRITICALITY','PO_TYPE','CURRENCY','PLANT_REGION','PLANT_COUNTRY']
    train_df = session.table("OTIF_GUARDIAN.ML.TRAIN_DATA_V2").limit(5).to_pandas()
    feature_cols = [c for c in train_df.columns if c != 'OTIF_BREACH']
    sample_input = train_df[feature_cols].head(5).copy()
    for col in cat_cols:
        if col in sample_input.columns:
            le = LabelEncoder()
            sample_input[col] = le.fit_transform(sample_input[col].astype(str).fillna('UNKNOWN'))
    for col in sample_input.columns:
        if col not in cat_cols:
            sample_input[col] = pd.to_numeric(sample_input[col], errors='coerce')
    sample_input = sample_input.fillna(-999)
    print(f"Sample input: {sample_input.shape[0]} rows x {sample_input.shape[1]} features")

    # Register in Model Registry
    print("Registering model in Snowflake Model Registry...")
    reg = Registry(session=session, database_name="OTIF_GUARDIAN", schema_name="ML")
    mv = reg.log_model(
        model_obj,
        model_name="OTIF_BREACH_PREDICTOR",
        version_name="V2",
        sample_input_data=sample_input,
        conda_dependencies=["xgboost", "scikit-learn"],
        comment=f"OTIF breach prediction V2. XGBoost + SMOTE + HPO + isotonic calibration. Threshold={threshold}. ROC-AUC=0.9502."
    )
    print(f"SUCCESS: Registered OTIF_BREACH_PREDICTOR/V2")
    print(f"Functions: {mv.show_functions()}")
    session.close()

if __name__ == "__main__":
    main()
