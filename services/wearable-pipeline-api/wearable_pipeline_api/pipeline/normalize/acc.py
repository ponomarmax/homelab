from __future__ import annotations

import math
from pathlib import Path
from typing import Any

from .base import BASE_COLUMNS, NormalizeHandlerOutput, finalize_rows, parse_jsonl_chunks

ACC_COLUMNS = BASE_COLUMNS + [
    "device_time_ns",
    "x_mg",
    "y_mg",
    "z_mg",
    "vector_magnitude_mg",
]


class PolarAccNormalizer:
    name = "PolarAccNormalizer"
    payload_schema = "polar.acc"

    def handle(self, raw_path: Path) -> NormalizeHandlerOutput:
        rows: list[dict[str, Any]] = []
        chunks, warnings = parse_jsonl_chunks(raw_path)
        skipped_samples_count = 0
        chunks_count = 0

        session_id = ""
        stream_id = ""
        user_id = ""

        for chunk in chunks:
            line_number = int(chunk.get("__line_number") or 0)
            payload_schema = str(((chunk.get("transport") or {}).get("payload_schema") or "")).strip().lower()
            if payload_schema != self.payload_schema:
                continue

            chunks_count += 1
            session_id = str(chunk.get("session_id") or session_id)
            stream_id = str(chunk.get("stream_id") or stream_id)
            user_id = str(chunk.get("user_id") or user_id)

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
                x_mg = sample.get("x_mg")
                y_mg = sample.get("y_mg")
                z_mg = sample.get("z_mg")
                if not sample_ts or x_mg is None or y_mg is None or z_mg is None:
                    skipped_samples_count += 1
                    warnings.append(f"line {line_number}: sample {sample_idx} missing required acc fields")
                    continue

                x = float(x_mg)
                y = float(y_mg)
                z = float(z_mg)
                rows.append(
                    {
                        "ts_utc": sample_ts,
                        "received_at_collector": sample_ts,
                        "uploaded_at_collector": time_info.get("uploaded_at_collector"),
                        "received_at_server": server.get("received_at_server"),
                        "session_id": chunk.get("session_id"),
                        "stream_id": chunk.get("stream_id"),
                        "stream_type": chunk.get("stream_type"),
                        "payload_schema": payload_schema,
                        "user_id": str(chunk.get("user_id") or ""),
                        "source_vendor": source.get("vendor"),
                        "source_device_model": source.get("device_model"),
                        "source_device_id": source.get("device_id"),
                        "collection_mode": collection.get("mode"),
                        "source_chunk_id": chunk.get("chunk_id"),
                        "source_sequence": chunk.get("sequence"),
                        "source_line_number": line_number,
                        "alignment_confidence": "medium",
                        "device_time_ns": sample.get("device_time_ns"),
                        "x_mg": x,
                        "y_mg": y,
                        "z_mg": z,
                        "vector_magnitude_mg": math.sqrt((x * x) + (y * y) + (z * z)),
                    }
                )

        df = finalize_rows(rows, columns=ACC_COLUMNS)
        report = {
            "session_id": session_id,
            "stream_id": stream_id,
            "stream_type": "acc",
            "payload_schema": self.payload_schema,
            "user_id": user_id,
            "alignment_basis": "payload.samples[].received_at_collector",
            "confidence": "medium",
            "samples_count": int(len(df.index)),
            "chunks_count": chunks_count,
            "skipped_samples_count": skipped_samples_count,
            "warnings": warnings,
        }
        return NormalizeHandlerOutput(dataframe=df, report=report, warnings=warnings)
