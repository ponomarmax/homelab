from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pandas as pd

REQUIRED_COLUMNS = [
    "ts_utc",
    "hr",
    "received_at_collector",
    "uploaded_at_collector",
    "received_at_server",
    "session_id",
    "stream_id",
    "stream_type",
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


class PolarHrNormalizer:
    name = "PolarHrNormalizer"

    def handle(self, raw_path: Path) -> NormalizeHandlerOutput:
        rows: list[dict[str, Any]] = []
        warnings: list[str] = []
        skipped_samples_count = 0
        chunks_count = 0

        session_id: str | None = None
        stream_id: str | None = None
        stream_type = "hr"
        user_id: str | None = None

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

                chunk_stream_type = chunk.get("stream_type")
                payload_schema = ((chunk.get("transport") or {}).get("payload_schema"))
                if chunk_stream_type != "hr" or payload_schema != "polar.hr":
                    warnings.append(f"line {line_number}: unsupported stream/payload")
                    continue

                chunks_count += 1
                session_id = str(chunk.get("session_id") or session_id or "")
                stream_id = str(chunk.get("stream_id") or stream_id or "")
                user_id = str(chunk.get("user_id") or user_id or "")

                source = chunk.get("source") if isinstance(chunk.get("source"), dict) else {}
                collection = chunk.get("collection") if isinstance(chunk.get("collection"), dict) else {}
                time_info = chunk.get("time") if isinstance(chunk.get("time"), dict) else {}
                server = chunk.get("server") if isinstance(chunk.get("server"), dict) else {}
                payload = chunk.get("payload") if isinstance(chunk.get("payload"), dict) else {}
                samples = payload.get("samples") if isinstance(payload.get("samples"), list) else []

                if not samples:
                    warnings.append(f"line {line_number}: empty or malformed payload.samples")

                for sample_idx, sample in enumerate(samples, start=1):
                    if not isinstance(sample, dict):
                        skipped_samples_count += 1
                        warnings.append(f"line {line_number}: sample {sample_idx} malformed")
                        continue

                    sample_ts = sample.get("received_at_collector")
                    if not sample_ts:
                        skipped_samples_count += 1
                        warnings.append(f"line {line_number}: sample {sample_idx} missing received_at_collector")
                        continue

                    hr_value = sample.get("hr")
                    if hr_value is None:
                        skipped_samples_count += 1
                        warnings.append(f"line {line_number}: sample {sample_idx} missing hr")
                        continue

                    rows.append(
                        {
                            "ts_utc": sample_ts,
                            "hr": int(hr_value),
                            "received_at_collector": sample_ts,
                            "uploaded_at_collector": time_info.get("uploaded_at_collector"),
                            "received_at_server": server.get("received_at_server"),
                            "session_id": chunk.get("session_id"),
                            "stream_id": chunk.get("stream_id"),
                            "stream_type": chunk_stream_type,
                            "user_id": str(chunk.get("user_id") or ""),
                            "source_vendor": source.get("vendor"),
                            "source_device_model": source.get("device_model"),
                            "source_device_id": source.get("device_id"),
                            "collection_mode": collection.get("mode"),
                            "source_chunk_id": chunk.get("chunk_id"),
                            "source_sequence": chunk.get("sequence"),
                            "source_line_number": line_number,
                            "alignment_confidence": "medium",
                        }
                    )

        df = pd.DataFrame(rows, columns=REQUIRED_COLUMNS)
        if not df.empty:
            df["ts_utc"] = pd.to_datetime(df["ts_utc"], utc=True, errors="coerce")
            df = df.dropna(subset=["ts_utc"]).sort_values("ts_utc").reset_index(drop=True)

        report = {
            "session_id": session_id or "",
            "stream_id": stream_id or "",
            "stream_type": stream_type,
            "user_id": user_id or "",
            "alignment_basis": "payload.samples[].received_at_collector",
            "confidence": "medium",
            "samples_count": int(len(df.index)),
            "chunks_count": chunks_count,
            "skipped_samples_count": skipped_samples_count,
            "warnings": warnings,
        }
        return NormalizeHandlerOutput(dataframe=df, report=report, warnings=warnings)
