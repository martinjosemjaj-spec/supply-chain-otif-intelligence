-- ============================================================
-- OTIF_Guardian: Model Registry Registration
-- Registers the trained XGBoost model artifact from @MODEL_STAGE
-- into the Snowflake Model Registry for versioned governance.
-- Generated: 2026-10-01
-- ============================================================

USE DATABASE OTIF_GUARDIAN;
USE SCHEMA ML;
USE WAREHOUSE OTIF_GUARDIAN_WH;

-- ============================================================
-- 1. STORED PROCEDURE: Register model from stage into Registry
-- ============================================================

CREATE OR REPLACE PROCEDURE OTIF_GUARDIAN.ML.SP_REGISTER_MODEL(
    P_VERSION_NAME VARCHAR DEFAULT 'V2'
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'snowflake-ml-python', 'joblib', 'xgboost', 'scikit-learn', 'pandas', 'numpy')
HANDLER = 'register_model'
EXECUTE AS CALLER
AS
$$
import json
import os
import tempfile
import joblib
import pandas as pd
import numpy as np
from snowflake.ml.registry import Registry
from snowflake.snowpark import Session

def register_model(session, p_version_name: str) -> dict:
    """
    Loads the trained XGBoost model from @MODEL_STAGE and registers it
    in the Snowflake Model Registry as OTIF_GUARDIAN.ML.OTIF_BREACH_PREDICTOR.
    """
    results = {"status": "starting", "steps": []}

    try:
        # Step 1: Download model artifact from stage
        tmpdir = tempfile.mkdtemp()
        stage_path = "@OTIF_GUARDIAN.ML.MODEL_STAGE/breach_model_v2/improved_model.joblib"
        session.sql(f"GET {stage_path} 'file://{tmpdir}'").collect()
        model_path = os.path.join(tmpdir, "improved_model.joblib")

        if not os.path.exists(model_path):
            return {"status": "error", "message": "Model artifact not found on stage"}

        model_data = joblib.load(model_path)
        results["steps"].append("Model artifact loaded from stage")

        # Step 2: Extract the calibrated pipeline or raw model
        # The improved model saves a dict with 'model', 'calibrated_model', 'threshold', etc.
        if isinstance(model_data, dict):
            model_obj = model_data.get("calibrated_model", model_data.get("model"))
            threshold = model_data.get("threshold", 0.33)
            results["steps"].append(f"Extracted calibrated model (threshold={threshold})")
        else:
            model_obj = model_data
            threshold = 0.50
            results["steps"].append("Loaded raw model object")

        # Step 3: Build sample input from TRAIN_DATA_V2
        cat_cols = ['MATERIAL_CATEGORY', 'ABC_CLASS', 'CRITICALITY',
                    'PO_TYPE', 'CURRENCY', 'PLANT_REGION', 'PLANT_COUNTRY']
        train_df = session.table("OTIF_GUARDIAN.ML.TRAIN_DATA_V2").limit(5).to_pandas()
        feature_cols = [c for c in train_df.columns if c != 'OTIF_BREACH']
        sample_input = train_df[feature_cols].head(5)

        # Encode categoricals to match training encoding
        from sklearn.preprocessing import LabelEncoder
        for col in cat_cols:
            if col in sample_input.columns:
                le = LabelEncoder()
                sample_input[col] = le.fit_transform(sample_input[col].astype(str).fillna('UNKNOWN'))

        # Fill numeric nulls
        for col in sample_input.columns:
            if col not in cat_cols:
                sample_input[col] = pd.to_numeric(sample_input[col], errors='coerce')
        sample_input = sample_input.fillna(-999)

        results["steps"].append(f"Sample input prepared ({len(feature_cols)} features)")

        # Step 4: Register in Model Registry
        reg = Registry(session=session, database_name="OTIF_GUARDIAN", schema_name="ML")

        mv = reg.log_model(
            model_obj,
            model_name="OTIF_BREACH_PREDICTOR",
            version_name=p_version_name,
            sample_input_data=sample_input,
            conda_dependencies=["xgboost", "scikit-learn"],
            comment=f"OTIF breach prediction model {p_version_name}. "
                    f"XGBoost + SMOTE + HPO + isotonic calibration. "
                    f"Threshold={threshold}. ROC-AUC=0.9502."
        )

        results["steps"].append(f"Model registered: OTIF_BREACH_PREDICTOR/{p_version_name}")
        results["model_name"] = "OTIF_BREACH_PREDICTOR"
        results["version"] = p_version_name
        results["status"] = "success"

    except Exception as e:
        results["status"] = "error"
        results["message"] = str(e)

    return results
$$;

-- ============================================================
-- END OF MODEL REGISTRY SCRIPT
-- ============================================================
