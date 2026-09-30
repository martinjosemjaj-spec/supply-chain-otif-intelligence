"""
OTIF Guardian - Unit tests for data layer and configuration.
Run: python -m pytest tests/test_app.py -v
Requires: OTIF_GUARDIAN_MODE=demo (no Snowflake connection needed)
"""

import os
import sys
import pytest

# Force demo mode for all tests
os.environ["OTIF_GUARDIAN_MODE"] = "demo"

# Add streamlit dir to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "streamlit"))

from lib.config import (
    APP_MODE, OBJECTS, FIELD_MAP, RISK_BANDS, DEFAULT_RISK_BANDS,
    UNAVAILABLE_FIELDS, COMMAND_CENTER_PAGE_SIZE,
)
from lib.data import (
    is_demo_mode, fmt_dollar, fmt_pct, fmt_prob, fmt_number, fmt_days,
    unavailable_msg, get_model_version, get_model_version_str,
    get_data_freshness, get_plants, get_prediction_time, get_scoring_time,
    get_risk_command_center, get_risk_kpi_metrics, get_revenue_by_plant,
    get_po_detail, get_po_reason_codes, get_po_recovery_options,
    run_agent_query,
    _generate_demo_risk,
)


# ── Config Tests ─────────────────────────────────────────────

class TestConfig:
    def test_demo_mode_active(self):
        assert APP_MODE == "demo"

    def test_objects_has_required_keys(self):
        required = ["risk_lines", "scored_results", "recovery_recs",
                     "best_recovery", "reason_codes", "agent", "plants"]
        for key in required:
            assert key in OBJECTS, f"Missing object key: {key}"

    def test_field_map_documents_unavailable(self):
        unavailable = [k for k, v in FIELD_MAP.items() if v is None]
        assert len(unavailable) > 0, "Should document unavailable fields"
        for field in unavailable:
            assert field in UNAVAILABLE_FIELDS or field in [
                "MODEL_VERSION", "SCORED_AT", "METRIC_AS_OF_DATE",
                "ACTION_QTY", "RECOVERED_UNITS", "ARRIVAL_DATE",
                "RECOMMENDED_FLAG",
            ]

    def test_risk_bands_are_valid(self):
        assert set(RISK_BANDS) == {"CRITICAL", "HIGH", "MEDIUM", "LOW"}

    def test_defaults_subset_of_bands(self):
        assert set(DEFAULT_RISK_BANDS).issubset(set(RISK_BANDS))


# ── Formatting Tests ─────────────────────────────────────────

class TestFormatting:
    def test_fmt_dollar_millions(self):
        assert "$1.5M" == fmt_dollar(1_500_000)

    def test_fmt_dollar_thousands(self):
        assert "$5,000" == fmt_dollar(5000)

    def test_fmt_dollar_small(self):
        assert "$12.50" == fmt_dollar(12.5)

    def test_fmt_dollar_none(self):
        assert fmt_dollar(None) == "N/A"

    def test_fmt_dollar_nan(self):
        import math
        assert fmt_dollar(float("nan")) == "N/A"

    def test_fmt_pct(self):
        assert fmt_pct(90.3) == "90.3%"

    def test_fmt_pct_none(self):
        assert fmt_pct(None) == "N/A"

    def test_fmt_prob(self):
        assert fmt_prob(0.85) == "85.0%"

    def test_fmt_prob_zero(self):
        assert fmt_prob(0) == "0.0%"

    def test_fmt_prob_none(self):
        assert fmt_prob(None) == "N/A"

    def test_fmt_number(self):
        assert fmt_number(1234) == "1,234"

    def test_fmt_number_none(self):
        assert fmt_number(None) == "N/A"

    def test_fmt_days(self):
        assert fmt_days(5) == "5d"

    def test_fmt_days_negative(self):
        assert fmt_days(-3) == "-3d"

    def test_fmt_days_none(self):
        assert fmt_days(None) == "N/A"


# ── Demo Mode Data Tests ────────────────────────────────────

class TestDemoMode:
    def test_is_demo_mode(self):
        assert is_demo_mode() is True

    def test_model_version_demo(self):
        mv = get_model_version()
        assert "demo" in mv.get("DEFAULT_VERSION_NAME", "").lower()

    def test_model_version_str(self):
        s = get_model_version_str()
        assert isinstance(s, str) and len(s) > 0

    def test_data_freshness_demo(self):
        df = get_data_freshness()
        assert not df.empty
        assert "SOURCE_TABLE" in df.columns

    def test_plants_demo(self):
        df = get_plants()
        assert not df.empty
        assert "PLANT_CODE" in df.columns
        assert "PLANT_NAME" in df.columns

    def test_prediction_time_demo(self):
        t = get_prediction_time()
        assert "demo" in t.lower()

    def test_scoring_time_demo(self):
        t = get_scoring_time()
        assert "demo" in t.lower()


# ── Risk Command Center Demo Tests ───────────────────────────

class TestRiskCommandCenter:
    def test_returns_dataframe(self):
        df = get_risk_command_center()
        assert not df.empty

    def test_has_required_columns(self):
        df = get_risk_command_center()
        required = ["PO_LINE_ID", "RISK_TIER", "BREACH_PROBABILITY", "LINE_VALUE"]
        for col in required:
            assert col in df.columns, f"Missing column: {col}"

    def test_plant_filter(self):
        df = get_risk_command_center(plant_filter="PLT-MFG-01")
        if not df.empty:
            assert all(df["PLANT_CODE"] == "PLT-MFG-01")

    def test_band_filter(self):
        df = get_risk_command_center(risk_bands=["CRITICAL"])
        if not df.empty:
            assert all(df["RISK_TIER"] == "CRITICAL")

    def test_revenue_filter(self):
        df = get_risk_command_center(min_revenue=10000)
        if not df.empty:
            assert all(df["LINE_VALUE"] >= 10000)

    def test_limit(self):
        df = get_risk_command_center(limit=3)
        assert len(df) <= 3

    def test_empty_bands_returns_empty(self):
        df = get_risk_command_center(risk_bands=[])
        assert df.empty

    def test_probabilities_in_range(self):
        df = get_risk_command_center()
        if not df.empty:
            assert all(0 <= p <= 1 for p in df["BREACH_PROBABILITY"])

    def test_kpi_metrics(self):
        df = get_risk_kpi_metrics()
        assert not df.empty
        row = df.iloc[0]
        assert row["SCORED_LINES"] > 0

    def test_revenue_by_plant(self):
        df = get_revenue_by_plant()
        assert not df.empty
        assert "PLANT_NAME" in df.columns
        assert "REVENUE" in df.columns


# ── PO Detail Demo Tests ────────────────────────────────────

class TestPODetail:
    def test_returns_detail(self):
        df = get_po_detail(30001)
        assert not df.empty

    def test_reason_codes(self):
        df = get_po_reason_codes(30001)
        assert not df.empty
        assert "FEATURE_NAME" in df.columns
        assert "SHAP_CONTRIBUTION" in df.columns

    def test_recovery_options(self):
        df = get_po_recovery_options(30001)
        assert not df.empty
        required = ["ACTION_TYPE", "IS_FEASIBLE", "NET_VALUE_PROTECTED"]
        for col in required:
            assert col in df.columns

    def test_recovery_has_infeasible(self):
        """Per SKILL.md: include normal and infeasible-action cases."""
        df = get_po_recovery_options(30001)
        assert any(df["IS_FEASIBLE"] == False)

    def test_recovery_has_feasible(self):
        df = get_po_recovery_options(30001)
        assert any(df["IS_FEASIBLE"] == True)


# ── Copilot Demo Tests ──────────────────────────────────────

class TestCopilot:
    def test_empty_question(self):
        answer, trace, raw = run_agent_query("")
        assert "enter a question" in answer.lower()

    def test_otif_question(self):
        answer, trace, raw = run_agent_query("What is the overall OTIF rate?")
        assert "DEMO" in answer
        assert "90" in answer

    def test_risk_question(self):
        answer, trace, raw = run_agent_query("How many critical risk lines?")
        assert "DEMO" in answer

    def test_unsupported_question(self):
        answer, trace, raw = run_agent_query("What is the weather today?")
        assert "DEMO" in answer
        assert "Supported topics" in answer or "demo response" in answer.lower()


# ── Demo Data Generation Tests ───────────────────────────────

class TestDemoDataGeneration:
    def test_generate_demo_risk(self):
        df = _generate_demo_risk()
        assert not df.empty
        assert len(df) > 0
        assert "PO_LINE_ID" in df.columns
        assert "RISK_TIER" in df.columns

    def test_demo_risk_has_all_tiers(self):
        df = _generate_demo_risk()
        tiers = set(df["RISK_TIER"].unique())
        assert tiers == {"CRITICAL", "HIGH", "MEDIUM", "LOW"}

    def test_demo_risk_probabilities_valid(self):
        df = _generate_demo_risk()
        assert all(0 <= p <= 1 for p in df["BREACH_PROBABILITY"])

    def test_demo_risk_no_duplicates(self):
        df = _generate_demo_risk()
        assert df["PO_LINE_ID"].is_unique


# ── Unavailable Field Documentation ─────────────────────────

class TestUnavailableFields:
    def test_all_unavailable_documented(self):
        for field, source in FIELD_MAP.items():
            if source is None and field not in [
                "MODEL_VERSION", "SCORED_AT", "METRIC_AS_OF_DATE",
                "ACTION_QTY", "RECOVERED_UNITS", "ARRIVAL_DATE",
                "RECOMMENDED_FLAG",
            ]:
                assert field in UNAVAILABLE_FIELDS, \
                    f"Unavailable field {field} not documented"

    def test_unavailable_msg(self):
        msg = unavailable_msg("EXPOSURE_SCORE")
        assert isinstance(msg, str) and len(msg) > 0
