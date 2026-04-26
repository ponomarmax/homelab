from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

import pandas as pd
import pyarrow.parquet as pq

LOGGER = logging.getLogger(__name__)


def _read_parquet_limited(path: Path, max_rows: int | None = None) -> pd.DataFrame:
    if max_rows is None:
        return pd.read_parquet(path)

    parquet_file = pq.ParquetFile(path)
    remaining = max_rows
    frames: list[pd.DataFrame] = []
    for batch in parquet_file.iter_batches(batch_size=min(remaining, 5000)):
        batch_df = batch.to_pandas()
        if len(batch_df.index) > remaining:
            batch_df = batch_df.head(remaining)
        frames.append(batch_df)
        remaining -= len(batch_df.index)
        if remaining <= 0:
            break

    if not frames:
        return pd.DataFrame()
    return pd.concat(frames, ignore_index=True)


def load_clean(session_path: str | Path, max_rows_per_stream: int | None = 50000) -> dict[str, pd.DataFrame]:
    """Load clean time-series data grouped by stream type."""
    root = Path(session_path)
    streams: dict[str, pd.DataFrame] = {}
    for path in sorted(root.glob("**/processed/clean_timeseries/**/streams/*/data.parquet")):
        stream_type = path.parent.name
        streams[stream_type] = _read_parquet_limited(path, max_rows=max_rows_per_stream)
        LOGGER.info("clean_loaded", extra={"stream": stream_type, "rows": len(streams[stream_type])})

    if not streams:
        LOGGER.warning("clean_missing", extra={"session_path": str(root)})
    return streams


def load_window_features(session_path: str | Path, max_rows_per_stream: int | None = 50000) -> dict[str, pd.DataFrame]:
    """Load window features grouped by stream type."""
    root = Path(session_path)
    streams: dict[str, pd.DataFrame] = {}
    for path in sorted(root.glob("**/processed/window_features/**/streams/*/data.parquet")):
        stream_type = path.parent.name
        streams[stream_type] = _read_parquet_limited(path, max_rows=max_rows_per_stream)
        LOGGER.info("window_features_loaded", extra={"stream": stream_type, "rows": len(streams[stream_type])})

    if not streams:
        LOGGER.warning("window_features_missing", extra={"session_path": str(root)})
    return streams


def load_summary(session_path: str | Path) -> dict[str, Any]:
    """Load session_summary.json if available."""
    root = Path(session_path)
    summary_paths = sorted(root.glob("**/processed/window_features/**/session_summary.json"))
    if not summary_paths:
        LOGGER.warning("summary_missing", extra={"session_path": str(root)})
        return {}

    path = summary_paths[0]
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if isinstance(payload, dict):
        payload["_source_path"] = str(path)
    LOGGER.info("summary_loaded", extra={"path": str(path)})
    return payload if isinstance(payload, dict) else {"value": payload, "_source_path": str(path)}


def load_raw_chunks(
    session_path: str | Path,
    preview_rows_per_stream: int = 50,
    max_scan_lines_per_stream: int = 20000,
) -> dict[str, dict[str, Any]]:
    """Load raw chunks.jsonl metadata and a small preview per stream."""
    root = Path(session_path)
    out: dict[str, dict[str, Any]] = {}

    for path in sorted(root.glob("**/raw/**/streams/*/chunks.jsonl")):
        stream_type = path.parent.name
        preview: list[dict[str, Any]] = []
        scanned = 0
        total_seen = 0
        parse_errors = 0

        with path.open("r", encoding="utf-8") as handle:
            for line in handle:
                total_seen += 1
                if scanned >= max_scan_lines_per_stream:
                    break

                scanned += 1
                payload = line.strip()
                if not payload:
                    continue

                if len(preview) < preview_rows_per_stream:
                    try:
                        item = json.loads(payload)
                    except json.JSONDecodeError:
                        parse_errors += 1
                        continue
                    if isinstance(item, dict):
                        preview.append(item)

        first_ts, last_ts = _extract_timestamps(preview)
        out[stream_type] = {
            "path": str(path),
            "preview": preview,
            "preview_count": len(preview),
            "scanned_lines": scanned,
            "observed_lines": total_seen,
            "scan_truncated": scanned >= max_scan_lines_per_stream,
            "first_timestamp": first_ts,
            "last_timestamp": last_ts,
            "parse_errors": parse_errors,
        }
        LOGGER.info(
            "raw_loaded",
            extra={"stream": stream_type, "preview_count": len(preview), "scanned_lines": scanned},
        )

    if not out:
        LOGGER.warning("raw_missing", extra={"session_path": str(root)})
    return out


def _extract_timestamps(records: list[dict[str, Any]]) -> tuple[str | None, str | None]:
    values: list[str] = []
    for row in records:
        if not isinstance(row, dict):
            continue
        server = row.get("server") if isinstance(row.get("server"), dict) else {}
        timing = row.get("time") if isinstance(row.get("time"), dict) else {}
        for candidate in (
            server.get("received_at_server"),
            timing.get("uploaded_at_collector"),
            timing.get("first_sample_received_at_collector"),
        ):
            if isinstance(candidate, str) and candidate.strip():
                values.append(candidate)
                break

    if not values:
        return None, None
    return values[0], values[-1]
