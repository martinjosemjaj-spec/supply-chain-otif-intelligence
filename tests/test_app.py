"""
OTIF Guardian - Unit tests for data layer and configuration.
Run: python -m pytest tests/test_app.py -v
Requires: OTIF_GUARDIAN_MODE=demo (no Snowflake connection needed)
"""

import os
import sys
import pandas as pd

# Force demo mode for all tests
os.environ["OTIF_GUARDIAN_MODE"] = "demo"

# Add streamlit dir to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "streamlit"))

from lib.config import (
    APP_MODE, OBJECTS, FIELD_MAP, RISK_BANDS, DEFAULT_RISK_BANDS,
    UNAVAILABLE_FIELDS,
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
        assert not df["IS_FEASIBLE"].all()

    def test_recovery_has_feasible(self):
        df = get_po_recovery_options(30001)
        assert df["IS_FEASIBLE"].any()


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


# ── System Status Smoke Tests ─────────────────────────────────

class TestSystemStatus:
    def test_system_status_returns_dict(self):
        from lib.data import get_system_status
        status = get_system_status()
        assert isinstance(status, dict)
        required_keys = ["model_version", "model_health", "data_freshness", "agent_status"]
        for key in required_keys:
            assert key in status, f"Missing key: {key}"

    def test_system_status_demo_values(self):
        from lib.data import get_system_status
        status = get_system_status()
        assert "demo" in status["model_version"].lower()
        assert status["model_health"] == "HEALTHY"
        assert status["agent_status"] == "DEMO"

    def test_model_version_v3_in_demo(self):
        mv = get_model_version()
        assert "V3" in mv.get("DEFAULT_VERSION_NAME", "")


# ── Caching Smoke Tests ───────────────────────────────────────

class TestCaching:
    def test_cached_query_returns_dataframe_in_demo(self):
        from lib.data import cached_query
        result = cached_query("SELECT 1")
        assert isinstance(result, pd.DataFrame)
        assert result.empty  # demo mode returns empty


# ── Evidence Package Smoke Tests ──────────────────────────────

class TestEvidencePackage:
    def test_evidence_returns_expected_columns(self):
        from lib.data import get_evidence_package
        df = get_evidence_package(30001)
        assert not df.empty
        for col in ["MODEL_VERSION", "FEATURE_SET_VERSION", "CALCULATION_TYPE"]:
            assert col in df.columns, f"Missing column: {col}"

    def test_evidence_recovery_returns_dataframe(self):
        from lib.data import get_evidence_recovery
        df = get_evidence_recovery(30001)
        assert isinstance(df, pd.DataFrame)


# ── Monitoring Smoke Tests ────────────────────────────────────

class TestMonitoring:
    def test_monitoring_overall_demo(self):
        from lib.data import get_monitoring_overall
        df = get_monitoring_overall()
        assert not df.empty
        assert "OVERALL_STATUS" in df.columns
        assert df.iloc[0]["OVERALL_STATUS"] == "HEALTHY"

    def test_monitoring_dashboard_demo(self):
        from lib.data import get_monitoring_dashboard
        df = get_monitoring_dashboard()
        assert isinstance(df, pd.DataFrame)


# ── Filter Consistency Smoke Tests ────────────────────────────

class TestFilterConsistency:
    def test_risk_kpis_accept_all_filter_params(self):
        df = get_risk_kpi_metrics(
            plant_filter="PLT-MFG-01",
            risk_bands=["CRITICAL"], min_revenue=1000)
        assert isinstance(df, pd.DataFrame)

    def test_revenue_by_plant_accepts_filters(self):
        df = get_revenue_by_plant(
            plant_filter="All",
            risk_bands=["CRITICAL", "HIGH"], min_revenue=0)
        assert isinstance(df, pd.DataFrame)

    def test_risk_command_center_empty_bands(self):
        df = get_risk_command_center(risk_bands=[])
        assert df.empty

    def test_risk_command_center_with_all_filters(self):
        df = get_risk_command_center(
            plant_filter="PLT-MFG-02",
            risk_bands=["HIGH", "MEDIUM"],
            min_revenue=500, limit=5)
        assert len(df) <= 5


# ── Empty State Smoke Tests ───────────────────────────────────

class TestEmptyStates:
    def test_functions_return_dataframes_not_none(self):
        for fn in [get_risk_kpi_metrics, get_revenue_by_plant]:
            result = fn()
            assert isinstance(result, pd.DataFrame), f"{fn.__name__} returned {type(result)}"

    def test_po_detail_returns_dataframe(self):
        df = get_po_detail(99999)
        assert isinstance(df, pd.DataFrame)

    def test_agent_error_returns_tuple(self):
        answer, trace, raw = run_agent_query("")
        assert isinstance(answer, str)


# ── Config Hardening Smoke Tests ──────────────────────────────

class TestConfigHardening:
    def test_new_objects_in_config(self):
        new_keys = ["monitoring_overall", "monitoring_dashboard",
                    "evidence_package", "evidence_recovery",
                    "production_model", "otif_projection"]
        for key in new_keys:
            assert key in OBJECTS, f"Missing OBJECTS key: {key}"

    def test_cache_ttl_constants(self):
        from lib.config import QUERY_CACHE_TTL, SYSTEM_STATUS_CACHE_TTL
        assert QUERY_CACHE_TTL > 0
        assert SYSTEM_STATUS_CACHE_TTL >= QUERY_CACHE_TTL


# ── Observability Smoke Tests ─────────────────────────────────

class TestObservability:
    def test_operational_summary_returns_4_domains(self):
        from lib.data import get_operational_summary
        df = get_operational_summary()
        assert not df.empty
        assert set(df["DOMAIN"]) == {"DATA", "ML", "AGENT", "APPLICATION"}

    def test_operational_summary_has_required_columns(self):
        from lib.data import get_operational_summary
        df = get_operational_summary()
        for col in ["DOMAIN", "TOTAL_CHECKS", "HEALTHY", "WARNINGS",
                    "CRITICAL", "DOMAIN_STATUS", "LAST_CHECKED", "MODEL_VERSION"]:
            assert col in df.columns, f"Missing column: {col}"

    def test_operational_summary_status_values(self):
        from lib.data import get_operational_summary
        df = get_operational_summary()
        valid = {"HEALTHY", "WARNING", "CRITICAL"}
        for status in df["DOMAIN_STATUS"]:
            assert status in valid, f"Invalid status: {status}"

    def test_operational_summary_counts_consistent(self):
        from lib.data import get_operational_summary
        df = get_operational_summary()
        for _, row in df.iterrows():
            total = int(row["HEALTHY"]) + int(row["WARNINGS"]) + int(row["CRITICAL"])
            assert total == int(row["TOTAL_CHECKS"]), \
                f"{row['DOMAIN']}: {total} != {int(row['TOTAL_CHECKS'])}"

    def test_operational_detail_returns_empty_in_demo(self):
        from lib.data import get_operational_detail
        df = get_operational_detail()
        assert isinstance(df, pd.DataFrame)

    def test_operational_detail_accepts_domain_filter(self):
        from lib.data import get_operational_detail
        df = get_operational_detail(domain="ML")
        assert isinstance(df, pd.DataFrame)
