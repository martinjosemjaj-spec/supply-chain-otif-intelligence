"""
OTIF Guardian - Production Streamlit Application
Main entry point with page routing.
"""

import streamlit as st

st.set_page_config(
    page_title="OTIF Guardian",
    page_icon="🛡️",
    layout="wide",
    initial_sidebar_state="expanded",
)

# Pages
executive_dashboard = st.Page("pages/01_executive_dashboard.py", title="Executive Dashboard", icon="📊", default=True)
risk_center = st.Page("pages/02_risk_center.py", title="Risk Center", icon="⚠️")
recovery_center = st.Page("pages/03_recovery_center.py", title="Recovery Center", icon="🔧")
governed_copilot = st.Page("pages/04_governed_copilot.py", title="Governed Copilot", icon="💬")
settings = st.Page("pages/05_settings.py", title="Settings", icon="⚙️")

pg = st.navigation([executive_dashboard, risk_center, recovery_center, governed_copilot, settings])
pg.run()
