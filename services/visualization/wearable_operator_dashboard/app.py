from __future__ import annotations

from pathlib import Path
from urllib.parse import quote_plus

import json
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st

try:
    from wearable_operator_dashboard.data_access import (
        build_ppi_points_from_raw_artifact,
        classify_ppi_quality_tier,
        discover_normalized_files,
        fetch_session_details,
        fetch_sessions,
        infer_duration_seconds,
        load_config,
        load_stream_points,
        read_jsonl_page,
        read_table_page,
    )
except ModuleNotFoundError:
    from data_access import (  # type: ignore
        build_ppi_points_from_raw_artifact,
        classify_ppi_quality_tier,
        discover_normalized_files,
        fetch_session_details,
        fetch_sessions,
        infer_duration_seconds,
        load_config,
        load_stream_points,
        read_jsonl_page,
        read_table_page,
    )


st.set_page_config(page_title="Wearable Operator Dashboard", layout="wide")
config = load_config()

st.title("Wearable Operator Dashboard")
st.caption("Operational dashboard for raw-first collection and pipeline status")

pages = ["Session List", "Session Details"]
query_page = str(st.query_params.get("page", "Session List"))
default_index = pages.index(query_page) if query_page in pages else 0
page = st.sidebar.radio("Page", pages, index=default_index)
st.query_params["page"] = page


def _extract_anchor_start(raw_artifacts: list[str]) -> pd.Timestamp | None:
    for path_text in raw_artifacts:
        path = Path(path_text)
        if not path.is_file():
            continue
        try:
            with path.open("r", encoding="utf-8") as handle:
                for line in handle:
                    text = line.strip()
                    if not text:
                        continue
                    row = json.loads(text)
                    time_obj = row.get("time") or {}
                    candidate = (
                        time_obj.get("recording_start_utc")
                        or time_obj.get("fetch_started_at_collector")
                        or time_obj.get("first_sample_received_at_collector")
                    )
                    ts = pd.to_datetime(candidate, utc=True, errors="coerce")
                    if pd.notna(ts):
                        return ts
        except Exception:
            continue
    return None

if page == "Session List":
    st.subheader("Sessions")
    sessions = fetch_sessions(config)
    if not sessions:
        st.info("No sessions found")
    else:
        rows = []
        for session in sessions:
            rows.append(
                {
                    "session_id": session.get("session_id"),
                    "session_link": f"/?page=Session+Details&session_id={quote_plus(str(session.get('session_id') or ''))}",
                    "user_id": session.get("user_id", "unknown"),
                    "device": session.get("device"),
                    "device_id": session.get("device_id", "unknown"),
                    "collection_mode": session.get("collection_mode"),
                    "started_at": session.get("started_at"),
                    "ended_at": session.get("ended_at"),
                    "duration_seconds": session.get("duration")
                    or infer_duration_seconds(session.get("started_at"), session.get("ended_at")),
                    "streams_present": ",".join(session.get("streams_present", [])),
                    "raw_upload_status": session.get("raw_upload_status"),
                    "normalization_status": session.get("normalization_status"),
                    "feature_status": session.get("feature_status"),
                    "summary_status": session.get("summary_status"),
                    "created_at": session.get("created_at"),
                    "updated_at": session.get("updated_at"),
                }
            )
        frame = pd.DataFrame(rows)
        st.dataframe(
            frame,
            use_container_width=True,
            column_config={
                "session_link": st.column_config.LinkColumn(
                    "session_id",
                    display_text=r".*session_id=([a-zA-Z0-9\-]+)",
                ),
            },
            column_order=[
                "session_link",
                "user_id",
                "device",
                "device_id",
                "collection_mode",
                "started_at",
                "ended_at",
                "duration_seconds",
                "streams_present",
                "raw_upload_status",
                "normalization_status",
                "feature_status",
                "summary_status",
                "created_at",
                "updated_at",
            ],
        )

if page == "Session Details":
    st.subheader("Session Details")
    default_id = st.query_params.get("session_id", "")
    session_id = st.text_input("session_id", value=default_id)

    if session_id:
        details = fetch_session_details(config, session_id)
        streams_meta = details.get("streams", {}) or {}
        stream_names = sorted(streams_meta.keys())
        processed_artifacts = details.get("processed_artifacts", {}) or {}
        stream_window_feature_paths = processed_artifacts.get("stream_window_feature_paths", {}) or {}

        def resolve_normalized_files() -> dict[str, Path]:
            normalized_files = discover_normalized_files(config, session_id)
            if not normalized_files:
                for s, paths in stream_window_feature_paths.items():
                    if not paths:
                        continue
                    candidate = Path(paths[0])
                    if not candidate.is_file():
                        continue
                    try:
                        frame_head = pd.read_parquet(candidate, columns=["input_artifact_reference"]).head(1)
                        if not frame_head.empty:
                            ref = str(frame_head.iloc[0]["input_artifact_reference"])
                            ref_path = Path(ref)
                            if ref_path.is_file():
                                normalized_files[s] = ref_path
                    except Exception:
                        continue
            return normalized_files

        with st.expander("Technical Metadata", expanded=False):
            c1, c2 = st.columns(2)
            with c1:
                st.json(
                    {
                        "session_id": details.get("session_id"),
                        "pipeline_run_status": details.get("pipeline_run_status"),
                        "streams_count": len(streams_meta),
                    }
                )
            with c2:
                st.json(
                    {
                        "raw_artifacts": details.get("raw_artifacts", []),
                        "processed_artifacts": processed_artifacts,
                    }
                )
            st.json(details.get("stream_summaries", {}))

        section = st.radio(
            "Section",
            ["Overview", "Raw Data", "Normalized Data", "Window Features", "Charts"],
            horizontal=True,
            key="session_details_section",
        )

        if section == "Overview":
            normalized_files = resolve_normalized_files()
            plot_files = dict(normalized_files)
            for stream_name, paths in stream_window_feature_paths.items():
                if stream_name in plot_files:
                    continue
                if not paths:
                    continue
                first = next((item for item in paths if isinstance(item, str) and item.strip()), None)
                if not first:
                    continue
                plot_files[stream_name] = Path(first)
            rows = []
            for s in sorted(set(stream_names) | set(plot_files.keys()) | set(stream_window_feature_paths.keys())):
                raw_path = (streams_meta.get(s) or {}).get("raw_path")
                norm_path = plot_files.get(s)
                window_paths = stream_window_feature_paths.get(s, [])
                rows.append(
                    {
                        "stream": s,
                        "raw_path": raw_path,
                        "normalized_path": str(norm_path) if norm_path else "",
                        "window_paths": len(window_paths),
                    }
                )
            st.dataframe(pd.DataFrame(rows), use_container_width=True)

        elif section == "Raw Data":
            raw_streams = [s for s in stream_names if (streams_meta.get(s) or {}).get("raw_path")]
            if not raw_streams:
                st.info("No raw stream artifacts")
            else:
                raw_stream = st.selectbox("Raw stream", options=raw_streams, key="raw_stream_select")
                raw_path = Path((streams_meta.get(raw_stream) or {}).get("raw_path", ""))
                raw_page_size = st.selectbox("Rows per page", [25, 50, 100, 250], index=1, key="raw_page_size")
                raw_page = st.number_input("Page", min_value=1, value=1, step=1, key="raw_page_num")
                raw_rows, raw_total = read_jsonl_page(raw_path, page=int(raw_page), page_size=int(raw_page_size))
                st.caption(f"File: {raw_path} | total rows: {raw_total}")
                if raw_rows:
                    st.dataframe(
                        pd.DataFrame([{"line": idx + 1 + (int(raw_page)-1)*int(raw_page_size), **row} for idx, row in enumerate(raw_rows)]),
                        use_container_width=True,
                    )
                else:
                    st.info("No rows on this page")

        elif section == "Normalized Data":
            normalized_files = resolve_normalized_files()
            norm_streams = sorted(normalized_files.keys())
            if not norm_streams:
                st.info("No normalized files found")
            else:
                norm_stream = st.selectbox("Normalized stream", options=norm_streams, key="norm_stream_select")
                norm_path = normalized_files[norm_stream]
                norm_page_size = st.selectbox("Rows per page", [25, 50, 100, 250], index=1, key="norm_page_size")
                norm_page = st.number_input("Page", min_value=1, value=1, step=1, key="norm_page_num")
                norm_df, norm_total = read_table_page(norm_path, page=int(norm_page), page_size=int(norm_page_size))
                st.caption(f"File: {norm_path} | total rows: {norm_total}")
                st.dataframe(norm_df, use_container_width=True)

        elif section == "Window Features":
            window_streams = sorted([s for s, paths in stream_window_feature_paths.items() if paths])
            if not window_streams:
                st.info("No window feature files found")
            else:
                win_stream = st.selectbox("Window stream", options=window_streams, key="win_stream_select")
                win_paths = [Path(item) for item in stream_window_feature_paths.get(win_stream, []) if item]
                win_path = st.selectbox("Window artifact", options=win_paths, format_func=lambda p: str(p), key="win_path_select")
                win_page_size = st.selectbox("Rows per page", [25, 50, 100, 250], index=1, key="win_page_size")
                win_page = st.number_input("Page", min_value=1, value=1, step=1, key="win_page_num")
                win_df, win_total = read_table_page(win_path, page=int(win_page), page_size=int(win_page_size))
                st.caption(f"File: {win_path} | total rows: {win_total}")
                st.dataframe(win_df, use_container_width=True)

        elif section == "Charts":
            normalized_files = resolve_normalized_files()
            plot_files = dict(normalized_files)
            for stream_name, paths in stream_window_feature_paths.items():
                if stream_name in plot_files:
                    continue
                if not paths:
                    continue
                first = next((item for item in paths if isinstance(item, str) and item.strip()), None)
                if not first:
                    continue
                plot_files[stream_name] = Path(first)
            if not plot_files:
                st.info("No normalized/window feature files found for charting")
            else:
                stream_name = st.selectbox("Stream", options=sorted(plot_files.keys()))
                max_points = st.number_input("Max points", min_value=100, max_value=500000, value=20000, step=100)
                selected_path = plot_files[stream_name]
                points = load_stream_points(selected_path, limit=int(max_points))
                if stream_name.lower() == "ppi":
                    ppi_raw_path = ((details.get("streams") or {}).get("ppi") or {}).get("raw_path")
                    if ppi_raw_path:
                        raw_points = build_ppi_points_from_raw_artifact(Path(ppi_raw_path), max_points=int(max_points))
                        if raw_points:
                            points = raw_points

                if not points:
                    st.warning("Selected file contains no plottable points")
                else:
                    frame = pd.DataFrame(points)
                    frame["timestamp"] = pd.to_datetime(frame["timestamp"], errors="coerce", utc=True)
                    frame = frame.dropna(subset=["timestamp"]).copy()
                    frame["quality"] = frame["quality"].fillna("unknown")
                    frame["value"] = pd.to_numeric(frame["value"], errors="coerce")
                    frame = frame.dropna(subset=["value"]).copy()
                    frame["ppErrorEstimate"] = pd.to_numeric(frame.get("ppErrorEstimate"), errors="coerce")
                    frame["blockerBit"] = pd.to_numeric(frame.get("blockerBit"), errors="coerce")

                    if frame.empty:
                        st.warning("No valid timestamp points found")
                    else:
                        if stream_name.lower() == "ppi":
                            frame["quality_tier"] = [
                                classify_ppi_quality_tier(err, blk)
                                for err, blk in zip(frame["ppErrorEstimate"], frame["blockerBit"])
                            ]
                            color_col = "quality_tier"
                            color_map = {
                                "low": "#ef4444",
                                "medium": "#f59e0b",
                                "high": "#22c55e",
                                "unknown": "#64748b",
                            }
                        else:
                            color_col = "quality"
                            color_map = None

                        col_ctrl1, col_ctrl2 = st.columns(2)
                        with col_ctrl1:
                            show_line = st.checkbox("Show trend line", value=True)
                            show_anchors = st.checkbox("Show start/end anchors", value=True)
                        with col_ctrl2:
                            show_points = st.checkbox("Show points", value=True)

                        fig = px.scatter(
                            frame,
                            x="timestamp",
                            y="value",
                            color=color_col,
                            title=f"{stream_name.upper()} timeline",
                            opacity=0.75,
                            render_mode="webgl",
                            color_discrete_map=color_map,
                            hover_data=["ppErrorEstimate", "blockerBit", "skinContactStatus", "window_size"],
                        )
                        if not show_points:
                            for trace in fig.data:
                                trace.visible = "legendonly"
                        if stream_name.lower() == "ppi":
                            if show_line:
                                trend_df = (
                                    frame.sort_values("timestamp")
                                    .drop_duplicates(subset=["timestamp"], keep="last")
                                    .set_index("timestamp")["value"]
                                    .rolling("60s", min_periods=1)
                                    .median()
                                    .reset_index()
                                )
                                fig.add_trace(
                                    go.Scatter(
                                        x=trend_df["timestamp"],
                                        y=trend_df["value"],
                                        mode="lines",
                                        name="ppi_trend",
                                        line={"color": "#334155", "width": 1},
                                        opacity=0.55,
                                    )
                                )
                            if show_anchors:
                                anchor_start = _extract_anchor_start(details.get("raw_artifacts", []) or [])
                                if anchor_start is not None:
                                    fig.add_vline(x=anchor_start.to_pydatetime(), line_dash="dash", line_color="green")
                                recon_end = frame["timestamp"].max()
                                if pd.notna(recon_end):
                                    fig.add_vline(x=recon_end.to_pydatetime(), line_dash="dash", line_color="red")
                        fig.update_xaxes(rangeslider_visible=True)
                        fig.update_layout(height=420)
                        st.plotly_chart(fig, use_container_width=True)
                        st.caption(f"Plotted points: {len(frame)} from {selected_path}")
