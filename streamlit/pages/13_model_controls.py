"""
OTIF Guardian - Model & Controls
Real model metrics, governance controls, and provenance evidence.
Spec: SKILL.md S10
"""

import streamlit as st
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from lib.data import (
    get_model_version_str, get_model_metrics, get_confusion_matrix,
    get_feature_importance, get_data_freshness, get_prediction_time,
    get_scoring_time, run_query, is_demo_mode,
    get_operational_summary, get_operational_detail,
    get_dq_gate_status, get_dq_category_summary, get_dq_failures,
    get_observability_dashboard, get_monitoring_details,
)

# ── Header ───────────────────────────────────────────────────
st.markdown("### Model & Controls")
st.caption("Operational health, model performance, governance controls, and data provenance")

if is_demo_mode():
    st.warning("DEMO MODE — Metrics shown are from demo fixtures, not a production model.")

st.markdown("---")

# ── System Health (4 domains) ─────────────────────────────────
st.markdown("#### System Health")

try:
    with st.spinner("Loading operational health..."):
        ops = get_operational_summary()
    if not ops.empty:
        domain_cols = st.columns(4)
        status_colors = {"HEALTHY": "#36B37E", "WARNING": "#FFAB00", "CRITICAL": "#DE350B"}
        status_icons = {"HEALTHY": "HEALTHY", "WARNING": "WARNING", "CRITICAL": "CRITICAL"}

        for i, (_, row) in enumerate(ops.iterrows()):
            domain = row["DOMAIN"]
            status = row["DOMAIN_STATUS"]
            color = status_colors.get(status, "#888")
            with domain_cols[i]:
                st.markdown(
                    f'<div style="border:2px solid {color}; border-radius:8px; '
                    f'padding:0.8rem; text-align:center; min-height:140px;">'
                    f'<div style="font-size:0.85rem; color:#666; text-transform:uppercase; '
                    f'letter-spacing:0.05rem;">{domain}</div>'
                    f'<div style="font-size:1.4rem; font-weight:700; color:{color}; '
                    f'margin:0.3rem 0;">{status_icons.get(status, status)}</div>'
                    f'<div style="font-size:0.78rem; color:#888;">'
                    f'{int(row["HEALTHY"])}/{int(row["TOTAL_CHECKS"])} checks OK</div>'
                    f'<div style="font-size:0.72rem; color:#aaa; margin-top:0.2rem;">'
                    f'v{row["MODEL_VERSION"] or "?"} | {str(row["LAST_CHECKED"])[:16]}</div>'
                    f'</div>',
                    unsafe_allow_html=True,
                )
        st.markdown("")

        # Drilldown for non-HEALTHY domains
        problem_domains = ops[ops["DOMAIN_STATUS"] != "HEALTHY"]
        if not problem_domains.empty:
            st.markdown("##### Issues Requiring Attention")
            for _, row in problem_domains.iterrows():
                domain = row["DOMAIN"]
                status = row["DOMAIN_STATUS"]
                color = status_colors.get(status, "#888")
                w = int(row["WARNINGS"])
                c = int(row["CRITICAL"])
                st.markdown(
                    f'<div style="background:{color}15; border-left:3px solid {color}; '
                    f'padding:0.5rem 0.8rem; border-radius:4px; margin-bottom:0.4rem; '
                    f'font-size:0.85rem;">'
                    f'<b>{domain}</b>: {c} critical, {w} warnings out of '
                    f'{int(row["TOTAL_CHECKS"])} checks</div>',
                    unsafe_allow_html=True,
                )

            # Show detail rows for problem domains
            if not is_demo_mode():
                with st.expander("Detailed findings", expanded=False):
                    for _, row in problem_domains.iterrows():
                        detail = get_operational_detail(row["DOMAIN"])
                        if not detail.empty:
                            issues = detail[detail["STATUS"] != "HEALTHY"]
                            if not issues.empty:
                                st.markdown(f"**{row['DOMAIN']}**")
                                for _, d in issues.iterrows():
                                    st.markdown(
                                        f"- [{d['STATUS']}] {d['SUBDOMAIN']}: "
                                        f"{d['METRIC_LABEL'] or ''} — {d['DETAIL'] or ''}"
                                    )
        else:
            st.success("All systems operational.")
    else:
        st.info("No operational health data available.")
except Exception as e:
    st.error(f"Unable to load system health: {e}")

st.markdown("---")

# ── Model Version & Provenance ───────────────────────────────
st.markdown("#### Model Provenance")

c1, c2, c3 = st.columns(3)
with c1:
    st.metric("Model Version", get_model_version_str())
with c2:
    st.metric("Last Scoring", str(get_scoring_time()))
with c3:
    st.metric("Last Recovery Run", str(get_prediction_time()))

st.markdown("---")

# ── Performance Metrics ──────────────────────────────────────
st.markdown("#### Performance Metrics (Holdout Set)")

if not is_demo_mode():
    try:
        metrics = get_model_metrics()
        if not metrics.empty:
            m = metrics.iloc[0]
            c1, c2, c3, c4, c5 = st.columns(5)
            with c1:
                st.metric("ROC-AUC", f"{m.get('ROC_AUC', 'N/A'):.4f}"
                          if m.get('ROC_AUC') is not None else "N/A")
            with c2:
                st.metric("Accuracy", f"{m.get('ACCURACY', 'N/A'):.4f}"
                          if m.get('ACCURACY') is not None else "N/A")
            with c3:
                st.metric("Precision (Breach)", f"{m.get('PRECISION_BREACH', 'N/A'):.4f}"
                          if m.get('PRECISION_BREACH') is not None else "N/A")
            with c4:
                st.metric("Recall (Breach)", f"{m.get('RECALL_BREACH', 'N/A'):.4f}"
                          if m.get('RECALL_BREACH') is not None else "N/A")
            with c5:
                st.metric("F1 (Breach)", f"{m.get('F1_BREACH', 'N/A'):.4f}"
                          if m.get('F1_BREACH') is not None else "N/A")
        else:
            st.info("No model metrics available. Train the model first.")
    except Exception as e:
        st.error(f"Failed to load metrics: {e}")
else:
    st.info("Live model metrics not available in demo mode. "
            "Prototype reference values (not live): "
            "ROC-AUC 0.8304, Precision 0.4385, Recall 0.6950, F1 0.5377. "
            "These are prototype-demo values, not production results.")

st.markdown("---")

# ── Confusion Matrix ─────────────────────────────────────────
st.markdown("#### Confusion Matrix (Test Set)")

if not is_demo_mode():
    try:
        cm = get_confusion_matrix()
        if not cm.empty:
            formatted = cm.copy()
            formatted.columns = ["Actual", "Predicted", "Count"]
            formatted["Actual"] = formatted["Actual"].map({0: "No Breach", 1: "Breach"})
            formatted["Predicted"] = formatted["Predicted"].map({0: "No Breach", 1: "Breach"})
            formatted["Count"] = formatted["Count"].apply(lambda x: f"{int(x):,}")
            st.dataframe(formatted, use_container_width=True)
        else:
            st.info("No confusion matrix data. Train the model first.")
    except Exception as e:
        st.error(f"{e}")
else:
    st.info("Confusion matrix not available in demo mode.")

st.markdown("---")

# ── Feature Importance ───────────────────────────────────────
st.markdown("#### Feature Importance (Top 15)")

if not is_demo_mode():
    try:
        fi = get_feature_importance()
        if not fi.empty:
            st.bar_chart(fi.set_index("FEATURE")["SCORE"], use_container_width=True)
            st.dataframe(fi, use_container_width=True)
        else:
            st.info("No feature importance data.")
    except Exception as e:
        st.error(f"{e}")
else:
    st.info("Feature importance not available in demo mode.")

st.markdown("---")

# ── Governance Controls ──────────────────────────────────────
st.markdown("#### Governance Controls")

st.markdown("""
| Control | Status | Evidence |
|---------|--------|----------|
| Train/Test Split | Stratified 80/20 | `SP_TRAIN_IMPROVED_MODEL` procedure |
| Oversampling | SMOTE on train only | Applied before HPO, not on holdout |
| Threshold Tuning | Optimal F1 on holdout | `precision_recall_curve` in procedure |
| Calibration | Isotonic, 3-fold on train | `CalibratedClassifierCV` |
| Scoring Population | Open PO lines only | `OTIF_BREACH IS NULL` filter |
| Recovery Engine | Deterministic SQL | No LLM calculations |
| Agent Tools | Read-only SQL tools | `cortex_analyst_text_to_sql` |
| ERP Writes | None | Read-only decision support |
""")

st.caption(
    "The prototype references point-in-time splits, inventory safety floors, "
    "lane lead-time checks, and approved-source validation. "
    "Actual enforcement status should be verified against the deployed stored procedures."
)

st.markdown("---")

# ── Data Freshness ───────────────────────────────────────────
st.markdown("#### Data Freshness")

try:
    freshness = get_data_freshness()
    if not freshness.empty:
        for _, row in freshness.iterrows():
            c1, c2 = st.columns([1, 2])
            with c1:
                st.markdown(f"**{row['SOURCE_TABLE']}**")
            with c2:
                st.markdown(f"`{row['LAST_UPDATED']}`")
    else:
        st.info("Unable to determine data freshness.")
except Exception as e:
    st.error(f"{e}")

st.markdown("---")

# ── Data Quality Gate ────────────────────────────────────────
st.markdown("#### Data Quality Gate")

try:
    dq = get_dq_gate_status()
    gate = dq.get("gate_status", "UNKNOWN")
    gate_colors = {"PASS": "#36B37E", "BLOCKED": "#DE350B", "PENDING": "#FFAB00", "UNKNOWN": "#999"}
    gate_color = gate_colors.get(gate, "#999")

    g1, g2, g3, g4 = st.columns(4)
    with g1:
        st.markdown(f"**Gate Status:** <span style='color:{gate_color};font-weight:bold'>{gate}</span>", unsafe_allow_html=True)
    with g2:
        st.metric("Total Checks", dq.get("total_checks", 0))
    with g3:
        st.metric("Passed", dq.get("passed", 0))
    with g4:
        crit = dq.get("critical_failures", 0)
        st.metric("Critical Failures", crit, delta=f"-{crit}" if crit > 0 else None, delta_color="inverse" if crit > 0 else "off")

    if gate == "BLOCKED":
        st.error("SCORING BLOCKED: Critical data quality failures detected. Model scoring must not proceed until resolved.")

    cat_df = get_dq_category_summary()
    if not cat_df.empty:
        st.markdown("**Category Breakdown**")
        st.dataframe(cat_df, use_container_width=True, hide_index=True)

    fail_df = get_dq_failures()
    if not fail_df.empty:
        st.markdown("**Active Failures**")
        st.dataframe(fail_df, use_container_width=True, hide_index=True)

except Exception as e:
    st.warning(f"Unable to load DQ status: {e}")

st.markdown("---")

# ── 4-Layer Observability ────────────────────────────────────
st.markdown("#### Observability (4 Layers)")

try:
    obs = get_observability_dashboard()
    if not obs.empty:
        layer_cols = st.columns(4)
        status_colors = {"HEALTHY": "#36B37E", "WARNING": "#FFAB00", "CRITICAL": "#DE350B"}
        layer_icons = {"DATA": "DATA", "ML": "ML", "AGENT": "AGENT", "BUSINESS": "BUSINESS"}

        for i, (_, row) in enumerate(obs.iterrows()):
            domain = row["DOMAIN"]
            status = row["DOMAIN_STATUS"]
            color = status_colors.get(status, "#888")
            with layer_cols[i % 4]:
                st.markdown(
                    f'<div style="border:2px solid {color}; border-radius:8px; '
                    f'padding:0.8rem; text-align:center; min-height:120px;">'
                    f'<div style="font-size:0.85rem; color:#666; text-transform:uppercase;">{domain}</div>'
                    f'<div style="font-size:1.3rem; font-weight:700; color:{color}; margin:0.3rem 0;">{status}</div>'
                    f'<div style="font-size:0.78rem; color:#888;">'
                    f'{int(row["HEALTHY"])}/{int(row["TOTAL_CHECKS"])} healthy</div>'
                    f'<div style="font-size:0.72rem; color:#aaa;">v{row["MODEL_VERSION"] or "?"}</div>'
                    f'</div>',
                    unsafe_allow_html=True,
                )

        with st.expander("Layer Details"):
            for layer in ["DATA", "ML", "AGENT", "BUSINESS"]:
                details = get_monitoring_details(layer)
                if not details.empty:
                    st.markdown(f"**{layer}**")
                    st.dataframe(details[["CATEGORY", "CHECK_NAME", "STATUS", "CURRENT_VALUE", "THRESHOLD_WARNING", "THRESHOLD_CRITICAL", "MESSAGE"]],
                                 use_container_width=True, hide_index=True)
    else:
        st.info("No observability data. Run `CALL OTIF_GUARDIAN.AUDIT.SP_RUN_OBSERVABILITY()` to populate.")
except Exception as e:
    st.warning(f"Unable to load observability: {e}")

st.markdown("---")

# ── Object Inventory ─────────────────────────────────────────
st.markdown("#### Object Inventory")

if not is_demo_mode() and st.button("Refresh Object Counts"):
    try:
        inventory = run_query("""
            SELECT 'Tables (RAW)' AS object_type, COUNT(*) AS count
            FROM INFORMATION_SCHEMA.TABLES
            WHERE TABLE_SCHEMA = 'RAW' AND TABLE_CATALOG = 'OTIF_GUARDIAN'
            UNION ALL
            SELECT 'Views (ANALYTICS)', COUNT(*)
            FROM INFORMATION_SCHEMA.VIEWS
            WHERE TABLE_SCHEMA = 'ANALYTICS' AND TABLE_CATALOG = 'OTIF_GUARDIAN'
            UNION ALL
            SELECT 'Views (ML)', COUNT(*)
            FROM INFORMATION_SCHEMA.VIEWS
            WHERE TABLE_SCHEMA = 'ML' AND TABLE_CATALOG = 'OTIF_GUARDIAN'
            UNION ALL
            SELECT 'Tables (ML)', COUNT(*)
            FROM INFORMATION_SCHEMA.TABLES
            WHERE TABLE_SCHEMA = 'ML' AND TABLE_CATALOG = 'OTIF_GUARDIAN'
        """)
        for _, row in inventory.iterrows():
            c1, c2 = st.columns([2, 1])
            with c1:
                st.markdown(f"**{row['OBJECT_TYPE']}**")
            with c2:
                st.markdown(f"`{int(row['COUNT']):,}`")
    except Exception as e:
        st.error(f"{e}")

st.caption("Decision support only — no ERP writes.")
