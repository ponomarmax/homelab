from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np
import pandas as pd


TIMESTAMP_CANDIDATES = [
    "ts_utc",
    "timestamp_utc",
    "timestamp",
    "received_at_collector",
    "received_at_server",
    "window_start_utc",
    "window_start",
    "window_end_utc",
    "window_end",
]


@dataclass
class GapStats:
    row_count: int
    duplicate_timestamps: int
    non_monotonic_count: int
    median_delta_seconds: float | None
    p95_delta_seconds: float | None
    max_delta_seconds: float | None


def nested_get(payload: dict[str, Any], path: str, default: Any = None) -> Any:
    value: Any = payload
    for part in path.split("."):
        if not isinstance(value, dict) or part not in value:
            return default
        value = value[part]
    return value


def detect_timestamp_column(df: pd.DataFrame, candidates: list[str] | None = None) -> str | None:
    scan = candidates or TIMESTAMP_CANDIDATES
    for col in scan:
        if col in df.columns:
            return col
    for col in df.columns:
        lowered = str(col).lower()
        if "time" in lowered or lowered.endswith("_ts") or lowered == "ts":
            return str(col)
    return None


def ensure_datetime(df: pd.DataFrame, ts_col: str | None = None) -> tuple[pd.DataFrame, str | None]:
    if df is None or df.empty:
        return pd.DataFrame() if df is None else df.copy(), ts_col

    out = df.copy()
    ts_col = ts_col or detect_timestamp_column(out)
    if ts_col is None or ts_col not in out.columns:
        return out, None

    out[ts_col] = pd.to_datetime(out[ts_col], errors="coerce", utc=True)
    out = out.dropna(subset=[ts_col]).sort_values(ts_col)
    return out, ts_col


def compute_gap_stats(ts: pd.Series) -> GapStats:
    clean_ts = pd.to_datetime(ts, errors="coerce", utc=True).dropna().sort_values()
    row_count = int(clean_ts.shape[0])
    if row_count == 0:
        return GapStats(0, 0, 0, None, None, None)

    deltas = clean_ts.diff().dt.total_seconds().dropna()
    duplicate_timestamps = int((deltas == 0).sum()) if not deltas.empty else 0
    non_monotonic_count = int((deltas < 0).sum()) if not deltas.empty else 0
    positive = deltas[deltas > 0]
    if positive.empty:
        return GapStats(row_count, duplicate_timestamps, non_monotonic_count, None, None, None)

    return GapStats(
        row_count=row_count,
        duplicate_timestamps=duplicate_timestamps,
        non_monotonic_count=non_monotonic_count,
        median_delta_seconds=float(positive.median()),
        p95_delta_seconds=float(np.percentile(positive, 95)),
        max_delta_seconds=float(positive.max()),
    )


def downsample_df(df: pd.DataFrame, max_points: int, sort_col: str | None = None) -> pd.DataFrame:
    if df is None or df.empty:
        return pd.DataFrame() if df is None else df

    out = df
    if sort_col and sort_col in out.columns:
        out = out.sort_values(sort_col)

    if max_points <= 0 or len(out.index) <= max_points:
        return out

    step = max(int(np.ceil(len(out.index) / max_points)), 1)
    return out.iloc[::step].copy()


def pick_first_column(df: pd.DataFrame, candidates: list[str]) -> str | None:
    for col in candidates:
        if col in df.columns:
            return col
    lowered = {str(c).lower(): str(c) for c in df.columns}
    for col in candidates:
        key = col.lower()
        if key in lowered:
            return lowered[key]
    return None


def is_battery_stream(
    stream_type: str,
    frame: pd.DataFrame | None = None,
    raw_item: dict[str, Any] | None = None,
) -> bool:
    if str(stream_type).lower() == "device_battery":
        return True

    if frame is not None and not frame.empty:
        for col in ["payload_schema", "transport_payload_schema", "schema", "stream_schema"]:
            if col in frame.columns:
                values = frame[col].dropna().astype(str).str.lower()
                if values.str.contains("polar.device_battery", regex=False).any():
                    return True

    if isinstance(raw_item, dict):
        preview = raw_item.get("preview") if isinstance(raw_item.get("preview"), list) else []
        for row in preview[:10]:
            if not isinstance(row, dict):
                continue
            schema = (
                nested_get(row, "transport.payload_schema")
                or nested_get(row, "payload_schema")
                or nested_get(row, "payload.payload_schema")
                or nested_get(row, "payload.schema")
            )
            if isinstance(schema, str) and schema.lower() == "polar.device_battery":
                return True
    return False


def stream_display_name(
    stream_type: str,
    battery_stream_alias: str,
    frame: pd.DataFrame | None = None,
    raw_item: dict[str, Any] | None = None,
) -> str:
    normalized = str(stream_type).strip()
    if not normalized:
        return "unknown"
    if normalized.lower() == "unknown" and is_battery_stream(normalized, frame=frame, raw_item=raw_item):
        return battery_stream_alias
    return normalized


def merge_feature_streams_by_time(
    feature_frames: dict[str, pd.DataFrame],
    max_rows_per_stream: int = 5000,
) -> pd.DataFrame:
    merged: pd.DataFrame | None = None
    for stream_name, frame in sorted(feature_frames.items()):
        if frame is None or frame.empty:
            continue
        local, ts_col = ensure_datetime(frame)
        if ts_col is None:
            continue

        local = downsample_df(local, max_points=max_rows_per_stream, sort_col=ts_col)
        keep = [ts_col]
        numeric_cols = [c for c in local.columns if c != ts_col and pd.api.types.is_numeric_dtype(local[c])]
        keep.extend(numeric_cols[:12])

        slim = local[keep].copy()
        slim = slim.rename(columns={ts_col: "window_ts"})
        for col in list(slim.columns):
            if col == "window_ts":
                continue
            slim = slim.rename(columns={col: f"{stream_name}__{col}"})

        slim = slim.sort_values("window_ts")
        if merged is None:
            merged = slim
            continue

        merged = pd.merge_asof(
            merged.sort_values("window_ts"),
            slim.sort_values("window_ts"),
            on="window_ts",
            direction="nearest",
            tolerance=pd.Timedelta(minutes=5),
        )

    if merged is None:
        return pd.DataFrame()
    return merged
