from __future__ import annotations

import json
import math
import os
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import pandas as pd


DEFAULT_MAX_POINTS = 20000


@dataclass(frozen=True)
class DashboardConfig:
    pipeline_api_base_url: str
    raw_root: Path
    processed_root: Path


def load_config() -> DashboardConfig:
    return DashboardConfig(
        pipeline_api_base_url=os.getenv("PIPELINE_API_BASE_URL", "http://wearable-pipeline-api:8091").rstrip("/"),
        raw_root=Path(os.getenv("RAW_ROOT", "/data/wearable/raw")),
        processed_root=Path(os.getenv("PROCESSED_ROOT", "/data/wearable/processed")),
    )


def _get_json(url: str, timeout_seconds: float) -> dict[str, Any]:
    request = Request(url=url, method="GET")
    try:
        with urlopen(request, timeout=timeout_seconds) as response:
            return json.loads(response.read().decode("utf-8"))
    except (HTTPError, URLError) as exc:
        raise RuntimeError(f"Failed GET {url}: {exc}") from exc


def fetch_sessions(config: DashboardConfig, timeout_seconds: float = 10.0) -> list[dict[str, Any]]:
    payload = _get_json(f"{config.pipeline_api_base_url}/api/v1/operator/sessions", timeout_seconds=timeout_seconds)
    return payload.get("sessions", [])


def fetch_session_details(config: DashboardConfig, session_id: str, timeout_seconds: float = 10.0) -> dict[str, Any]:
    return _get_json(
        f"{config.pipeline_api_base_url}/api/v1/operator/sessions/{session_id}",
        timeout_seconds=timeout_seconds,
    )


def discover_normalized_files(config: DashboardConfig, session_id: str) -> dict[str, Path]:
    files: dict[str, Path] = {}
    for path in config.processed_root.glob(f"**/session_id={session_id}/**/*.jsonl"):
        if not path.is_file():
            continue
        low = str(path).lower()
        if "normalize" not in low and "normalized" not in low:
            continue
        stream = path.stem
        for marker in ("ppi", "acc", "hr", "ppg", "gyro", "mag"):
            if marker in low:
                stream = marker
                break
        files.setdefault(stream, path)
    return files


def _pick_first(item: dict[str, Any], keys: list[str]) -> Any:
    for key in keys:
        if key in item and item[key] is not None:
            return item[key]
    return None


def _downsample_quality_aware(frame: pd.DataFrame, max_points: int) -> pd.DataFrame:
    if len(frame.index) <= max_points:
        return frame

    severe = frame[frame["quality_tier"] == "low"]
    rest = frame[frame["quality_tier"] != "low"]
    budget = max(1, max_points - len(severe.index))
    if len(rest.index) > budget:
        step = max(1, math.ceil(len(rest.index) / budget))
        rest = rest.iloc[::step].copy()
    merged = pd.concat([severe, rest], axis=0).sort_values("timestamp").drop_duplicates(subset=["timestamp", "value"])
    if len(merged.index) > max_points:
        step = max(1, math.ceil(len(merged.index) / max_points))
        merged = merged.iloc[::step].copy()
    return merged


def classify_ppi_quality_tier(pp_error_estimate: Any, blocker_bit: Any) -> str:
    blocker = pd.to_numeric(pd.Series([blocker_bit]), errors="coerce").iloc[0]
    if pd.notna(blocker) and int(blocker) == 1:
        return "low"
    err = pd.to_numeric(pd.Series([pp_error_estimate]), errors="coerce").iloc[0]
    if pd.isna(err):
        return "unknown"
    if float(err) < 7.0:
        return "high"
    return "medium"


def build_ppi_points_from_raw_artifact(raw_chunks_path: Path, max_points: int = DEFAULT_MAX_POINTS) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    anchor_start: pd.Timestamp | None = None
    cumulative_seconds = 0.0

    if not raw_chunks_path.is_file():
        return rows

    with raw_chunks_path.open("r", encoding="utf-8") as handle:
        for line in handle:
            text = line.strip()
            if not text:
                continue
            try:
                chunk = json.loads(text)
            except json.JSONDecodeError:
                continue

            time_obj = chunk.get("time") or {}
            candidate = (
                time_obj.get("recording_start_utc")
                or time_obj.get("fetch_started_at_collector")
                or time_obj.get("first_sample_received_at_collector")
            )
            if anchor_start is None:
                ts = pd.to_datetime(candidate, utc=True, errors="coerce")
                if pd.notna(ts):
                    anchor_start = ts

            payload = chunk.get("payload") or {}
            samples = payload.get("samples") or []
            for sample in samples:
                ppi_ms = pd.to_numeric(pd.Series([sample.get("ppInMs")]), errors="coerce").iloc[0]
                if pd.isna(ppi_ms):
                    continue
                ppi_value = float(ppi_ms)
                if ppi_value <= 0:
                    continue

                blocker = sample.get("blockerBit")
                pp_err = sample.get("ppErrorEstimate")
                skin_contact = sample.get("skinContactStatus")
                quality_tier = classify_ppi_quality_tier(pp_err, blocker)

                raw_ts = pd.to_numeric(pd.Series([sample.get("timeStamp")]), errors="coerce").iloc[0]
                abs_time: pd.Timestamp | None = None
                if pd.notna(raw_ts) and float(raw_ts) > 0:
                    # Polar offline raw timestamp is ns-like epoch in practice.
                    abs_time = pd.to_datetime(int(raw_ts), unit="ns", utc=True, errors="coerce")
                if abs_time is None or pd.isna(abs_time):
                    if anchor_start is None:
                        continue
                    abs_time = anchor_start + pd.to_timedelta(cumulative_seconds, unit="s")

                rows.append(
                    {
                        "timestamp": abs_time,
                        "value": ppi_value,
                        "quality": quality_tier,
                        "quality_tier": quality_tier,
                        "ppErrorEstimate": pp_err,
                        "blockerBit": blocker,
                        "skinContactStatus": skin_contact,
                        "window_size": None,
                    }
                )
                cumulative_seconds += ppi_value / 1000.0

    if not rows:
        return rows
    frame = pd.DataFrame(rows).sort_values("timestamp").drop_duplicates(subset=["timestamp", "value"], keep="last")
    frame = _downsample_quality_aware(frame, max_points=max_points)
    return frame.to_dict(orient="records")


def load_stream_points(file_path: Path, limit: int | None = None) -> list[dict[str, Any]]:
    suffix = file_path.suffix.lower()
    if suffix in {".parquet", ".csv"}:
        return load_stream_points_from_table(file_path, limit=limit)

    points: list[dict[str, Any]] = []
    with file_path.open("r", encoding="utf-8") as handle:
        for line in handle:
            text = line.strip()
            if not text:
                continue
            row = json.loads(text)
            timestamp = _pick_first(
                row,
                [
                    "timestamp_utc",
                    "timestamp",
                    "sample_time_utc",
                    "time",
                    "recorded_at",
                ],
            )
            value = _pick_first(
                row,
                [
                    "ppi_ms",
                    "ppInMs",
                    "ppi",
                    "hr_bpm",
                    "hr",
                    "x",
                    "magnitude",
                    "acc_magnitude",
                ],
            )
            quality = _pick_first(row, ["quality", "quality_label", "signal_quality", "sample_quality"])
            if quality is None:
                quality = _pick_first(row, ["quality_tier"])
            points.append({"timestamp": timestamp, "value": value, "quality": quality})
            if limit is not None and len(points) >= limit:
                break
    return points


def load_stream_points_from_table(file_path: Path, limit: int | None = None) -> list[dict[str, Any]]:
    frame = pd.read_parquet(file_path) if file_path.suffix.lower() == ".parquet" else pd.read_csv(file_path)

    # If this is an aggregated window-features artifact, switch to underlying clean timeseries
    # to preserve per-sample PPI quality signals.
    if "input_artifact_reference" in frame.columns and "ppInMs" not in frame.columns and "ppi_ms" not in frame.columns:
        refs = frame["input_artifact_reference"].dropna().astype(str).unique().tolist()
        if refs:
            ref_path = Path(refs[0])
            if ref_path.is_file() and ref_path != file_path:
                return load_stream_points(ref_path, limit=limit)

    timestamp_candidates = [
        "timestamp_utc",
        "timestamp",
        "sample_time_utc",
        "time",
        "recorded_at",
        "window_start_utc",
        "window_end_utc",
        "ts_utc",
        "t_abs_utc",
    ]
    value_candidates = [
        "ppi_ms",
        "ppInMs",
        "ppi",
        "hr_mean",
        "hr_median",
        "hr_first",
        "hr_last",
        "hr_bpm",
        "hr",
        "x",
        "magnitude",
        "acc_magnitude",
        "mean",
    ]
    quality_candidates = ["quality", "quality_label", "signal_quality", "sample_quality", "quality_tier"]

    timestamp_col = next((col for col in timestamp_candidates if col in frame.columns), None)
    value_col = next((col for col in value_candidates if col in frame.columns), None)
    quality_col = next((col for col in quality_candidates if col in frame.columns), None)

    if timestamp_col is None or value_col is None:
        return []

    selected_cols = [timestamp_col, value_col] + ([quality_col] if quality_col else [])
    for optional_col in ("ppErrorEstimate", "blockerBit", "skinContactStatus", "quality_tier", "window_size"):
        if optional_col in frame.columns and optional_col not in selected_cols:
            selected_cols.append(optional_col)
    trimmed = frame[selected_cols].copy()
    if limit is not None:
        trimmed = trimmed.head(limit)

    points: list[dict[str, Any]] = []
    for _, row in trimmed.iterrows():
        points.append(
            {
                "timestamp": row.get(timestamp_col),
                "value": row.get(value_col),
                "quality": row.get(quality_col) if quality_col else None,
                "ppErrorEstimate": row.get("ppErrorEstimate"),
                "blockerBit": row.get("blockerBit"),
                "skinContactStatus": row.get("skinContactStatus"),
                "window_size": row.get("window_size"),
            }
        )
    return points


def infer_duration_seconds(started_at: str | None, ended_at: str | None) -> float | None:
    if not started_at or not ended_at:
        return None
    try:
        start_dt = datetime.fromisoformat(started_at.replace("Z", "+00:00"))
        end_dt = datetime.fromisoformat(ended_at.replace("Z", "+00:00"))
    except ValueError:
        return None
    return max(0.0, (end_dt - start_dt).total_seconds())


def read_jsonl_page(path: Path, page: int, page_size: int) -> tuple[list[dict[str, Any]], int]:
    if not path.is_file():
        return [], 0
    if page < 1:
        page = 1
    if page_size < 1:
        page_size = 50
    start = (page - 1) * page_size
    end = start + page_size
    rows: list[dict[str, Any]] = []
    total = 0
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            text = line.strip()
            if not text:
                continue
            total += 1
            if total <= start:
                continue
            if total > end:
                continue
            try:
                rows.append(json.loads(text))
            except json.JSONDecodeError:
                rows.append({"_parse_error": True, "_raw_line": text})
    return rows, total


def read_table_page(path: Path, page: int, page_size: int) -> tuple[pd.DataFrame, int]:
    if not path.is_file():
        return pd.DataFrame(), 0
    if page < 1:
        page = 1
    if page_size < 1:
        page_size = 50
    if path.suffix.lower() == ".parquet":
        frame = pd.read_parquet(path)
    elif path.suffix.lower() == ".csv":
        frame = pd.read_csv(path)
    elif path.suffix.lower() == ".jsonl":
        rows: list[dict[str, Any]] = []
        with path.open("r", encoding="utf-8") as handle:
            for line in handle:
                text = line.strip()
                if not text:
                    continue
                try:
                    rows.append(json.loads(text))
                except json.JSONDecodeError:
                    continue
        frame = pd.DataFrame(rows)
    else:
        return pd.DataFrame(), 0
    total = len(frame.index)
    start = (page - 1) * page_size
    end = start + page_size
    return frame.iloc[start:end].copy(), total
