from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pandas as pd

BASE_COLUMNS = [
    "ts_utc",
    "received_at_collector",
    "uploaded_at_collector",
    "received_at_server",
    "session_id",
    "stream_id",
    "stream_type",
    "payload_schema",
    "user_id",
    "source_vendor",
    "source_device_model",
    "source_device_id",
    "collection_mode",
    "source_chunk_id",
    "source_sequence",
    "source_line_number",
    "alignment_confidence",
]


@dataclass
class NormalizeHandlerOutput:
    dataframe: pd.DataFrame
    report: dict[str, Any]
    warnings: list[str]


def parse_jsonl_chunks(raw_path: Path) -> tuple[list[dict[str, Any]], list[str]]:
    chunks: list[dict[str, Any]] = []
    warnings: list[str] = []

    with raw_path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            clean_line = line.strip()
            if not clean_line:
                continue
            try:
                chunk = json.loads(clean_line)
            except json.JSONDecodeError:
                warnings.append(f"line {line_number}: malformed json line")
                continue

            if not isinstance(chunk, dict):
                warnings.append(f"line {line_number}: chunk must be object")
                continue

            chunk["__line_number"] = line_number
            chunks.append(chunk)

    return chunks, warnings


def finalize_rows(rows: list[dict[str, Any]], *, columns: list[str]) -> pd.DataFrame:
    df = pd.DataFrame(rows, columns=columns)
    if df.empty:
        return df

    df["ts_utc"] = pd.to_datetime(df["ts_utc"], utc=True, errors="coerce")
    df = df.dropna(subset=["ts_utc"]).sort_values("ts_utc").reset_index(drop=True)
    return df
