from __future__ import annotations

import pandas as pd


def resolve_base_ts_utc(time_info: dict, server: dict) -> pd.Timestamp | None:
    base_ts = (
        time_info.get("first_sample_received_at_collector")
        or time_info.get("uploaded_at_collector")
        or server.get("received_at_server")
    )
    if not base_ts:
        return None
    ts = pd.to_datetime(base_ts, utc=True, errors="coerce")
    return None if pd.isna(ts) else ts


def compute_gap_metrics(ts_series: pd.Series) -> tuple[int, int]:
    if ts_series.empty:
        return 0, 0
    deltas = ts_series.diff().dropna()
    if deltas.empty:
        return 0, 0
    gap_threshold = pd.Timedelta(milliseconds=2000)
    gap_count = int((deltas > gap_threshold).sum())
    max_gap_ms = int(deltas.max().total_seconds() * 1000)
    return gap_count, max_gap_ms
