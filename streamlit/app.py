"""
OTIF Guardian - Production Streamlit Application
Main entry point with hero branding, sidebar filters, and page navigation.
Spec: SKILL.md S4, S5
"""

import streamlit as st
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from lib.data import is_demo_mode, get_plants, get_system_status
from lib.config import (
    RISK_BANDS, DEFAULT_RISK_BANDS, DEFAULT_MIN_REVENUE,
    REVENUE_STEP,
)

st.set_page_config(
    page_title="OTIF Guardian",
    page_icon="🛡️",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ── Hero Header ──────────────────────────────────────────────
st.markdown(
    """
    <div style="background: linear-gradient(135deg, #061B31 0%, #0B365B 50%, #075985 100%);
                padding: 1.5rem 2rem; border-radius: 10px; margin-bottom: 1rem;">
        <h1 style="color: #ffffff; margin: 0; font-size: 2rem;">🛡️ OTIF Guardian</h1>
        <p style="color: #93c5fd; margin: 0.3rem 0 0.8rem 0; font-size: 0.95rem;">
            Predict inbound supply failure. Trace customer exposure.
            Compare feasible recovery actions.
        </p>
        <div style="display: flex; gap: 0.5rem; flex-wrap: wrap;">
            <span style="background: rgba(255,255,255,0.15); color: #e0e7ff;
                         padding: 0.2rem 0.7rem; border-radius: 12px; font-size: 0.75rem;">
                Decision support — no ERP writes</span>
            <span style="background: rgba(255,255,255,0.15); color: #e0e7ff;
                         padding: 0.2rem 0.7rem; border-radius: 12px; font-size: 0.75rem;">
                Deterministic SQL engine</span>
            <span style="background: rgba(255,255,255,0.15); color: #e0e7ff;
                         padding: 0.2rem 0.7rem; border-radius: 12px; font-size: 0.75rem;">
                XGBoost + SHAP</span>
        </div>
    </div>
    """,
    unsafe_allow_html=True,
)

if is_demo_mode():
    st.warning("🔶 DEMO MODE — Running with synthetic data. Not connected to Snowflake.")

# ── System Status Bar ────────────────────────────────────────
try:
    _status = get_system_status()
    _health_color = {"HEALTHY": "#36B37E", "WARNING": "#FFAB00", "CRITICAL": "#DE350B"}.get(
        _status["model_health"], "#888")
    st.markdown(
        f'<div style="display:flex; gap:1.5rem; padding:0.4rem 1rem; '
        f'background:#f8fafc; border-radius:6px; margin-bottom:0.5rem; font-size:0.82rem;">'
        f'<span><b>Data Freshness:</b> {_status["data_freshness"]}</span>'
        f'<span><b>Model:</b> {_status["model_version"]}</span>'
        f'<span><b>Health:</b> <span style="color:{_health_color}; font-weight:600;">'
        f'{_status["model_health"]}</span></span>'
        f'<span><b>Agent:</b> {_status["agent_status"]}</span>'
        f'</div>',
        unsafe_allow_html=True,
    )
except Exception:
    pass

# ── Sidebar: Scope & Filters (SKILL.md S5) ──────────────────
st.sidebar.markdown(
    """
    <div style="text-align:center; padding: 0.3rem 0 0.8rem 0;">
        <span style="font-size:1.8rem;">🛡️</span>
        <h3 style="margin:0; font-size:1.1rem;">OTIF Guardian</h3>
    </div>
    """,
    unsafe_allow_html=True,
)
st.sidebar.divider()

# Plant selector
try:
    plants_df = get_plants()
    plant_options = ["All"] + plants_df["PLANT_CODE"].tolist()
    plant_names = {"All": "All Plants"}
    for _, r in plants_df.iterrows():
        plant_names[r["PLANT_CODE"]] = f"{r['PLANT_CODE']} — {r['PLANT_NAME']}"
except Exception:
    plant_options = ["All"]
    plant_names = {"All": "All Plants"}

selected_plant = st.sidebar.selectbox(
    "Plant",
    plant_options,
    format_func=lambda x: plant_names.get(x, x),
    key="filter_plant",
)

# Risk-band multiselect
selected_bands = st.sidebar.multiselect(
    "Risk Bands",
    RISK_BANDS,
    default=DEFAULT_RISK_BANDS,
    key="filter_bands",
)

# Minimum revenue
min_revenue = st.sidebar.number_input(
    "Min At-Risk Revenue ($)",
    min_value=0,
    value=DEFAULT_MIN_REVENUE,
    step=REVENUE_STEP,
    key="filter_min_revenue",
)

st.sidebar.divider()

# Navigation
page = st.sidebar.radio(
    "Navigation",
    [
        "📊  Risk Command Center",
        "🔍  PO Decision Detail",
        "💬  Governed Copilot",
        "⚙️  Model & Controls",
        "───────────────",
        "📈  Executive Dashboard",
        "⚠️  Risk Center (legacy)",
        "🔧  Recovery Center (legacy)",
        "📋  Settings (legacy)",
    ],
    label_visibility="collapsed",
)

st.sidebar.divider()
st.sidebar.caption(
    "**Governance:** All financial calculations are deterministic SQL. "
    "ML predictions use XGBoost with SHAP explainability. "
    "No ERP writes."
)
st.sidebar.caption(f"v3.0 | {'Demo' if is_demo_mode() else 'Live'} mode")

# ── Page Router ──────────────────────────────────────────────
if "Risk Command Center" in page:
    exec(open("pages/10_risk_command_center.py").read())
elif "PO Decision Detail" in page:
    exec(open("pages/11_po_decision_detail.py").read())
elif "Governed Copilot" in page:
    exec(open("pages/12_governed_copilot.py").read())
elif "Model & Controls" in page:
    exec(open("pages/13_model_controls.py").read())
elif "Executive Dashboard" in page:
    exec(open("pages/01_executive_dashboard.py").read())
elif "Risk Center" in page:
    exec(open("pages/02_risk_center.py").read())
elif "Recovery Center" in page:
    exec(open("pages/03_recovery_center.py").read())
elif "Settings" in page:
    exec(open("pages/05_settings.py").read())
elif "───" in page:
    st.info("Select a page from the navigation above.")
