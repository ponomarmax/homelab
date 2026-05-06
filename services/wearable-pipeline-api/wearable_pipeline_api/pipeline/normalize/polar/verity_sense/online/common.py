from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

import pandas as pd

from ...common.base import NormalizeHandlerOutput, finalize_rows
from ...common.chunking import iter_chunks_for_schema
from ...common.policies import BaseStreamPolicy
from ..common import compute_gap_metrics, resolve_base_ts_utc


@dataclass(frozen=True)
class VeritySenseOnlineOffsetStreamPolicy(BaseStreamPolicy):
    sample_to_fields: Callable[[dict[str, Any], int], dict[str, Any] | None]
    resolve_offset_ns: Callable[[dict[str, Any]], int | None]
    next_offset_ns: Callable[[dict[str, Any], int], int]


class VeritySenseOnlineOffsetNormalizer:
    def __init__(self, *, name: str, policy: VeritySenseOnlineOffsetStreamPolicy) -> None:
        self.name = name
        self.policy = policy

    def handle(self, raw_path: Path) -> NormalizeHandlerOutput:
        rows: list[dict[str, Any]] = []
        chunk_contexts, warnings = iter_chunks_for_schema(raw_path, self.policy.payload_schema)
        skipped_samples_count = 0
        chunks_count = 0
        invalid_offset_count = 0
        session_id = ""
        stream_id = ""
        user_id = ""

        for context in chunk_contexts:
            chunk = context.chunk
            line_number = context.line_number
            payload_schema = context.payload_schema
            chunks_count += 1
            session_id = str(chunk.get("session_id") or session_id)
            stream_id = str(chunk.get("stream_id") or stream_id)
            user_id = str(chunk.get("user_id") or user_id)
            source = context.source
            collection = context.collection
            time_info = context.time_info
            server = context.server
            samples = context.samples

            if not samples:
                warnings.append(f"line {line_number}: empty or malformed payload.samples")
                continue

            base_ts_utc = resolve_base_ts_utc(time_info, server)
            if base_ts_utc is None:
                warnings.append(f"line {line_number}: missing base collector/server timestamp")
                skipped_samples_count += len(samples)
                continue

            running_offset_ns = 0
            for sample_idx, sample in enumerate(samples, start=1):
                if not isinstance(sample, dict):
                    skipped_samples_count += 1
                    warnings.append(f"line {line_number}: sample {sample_idx} malformed")
                    continue

                stream_fields = self.policy.sample_to_fields(sample, sample_idx - 1)
                if stream_fields is None:
                    skipped_samples_count += 1
                    warnings.append(f"line {line_number}: sample {sample_idx} missing required fields")
                    continue

                resolved_offset = self.policy.resolve_offset_ns(sample)
                if resolved_offset is None:
                    invalid_offset_count += 1
                    resolved_offset = running_offset_ns

                ts = base_ts_utc + pd.to_timedelta(resolved_offset, unit="ns")
                rows.append(
                    {
                        "ts_utc": ts.isoformat().replace("+00:00", "Z"),
                        "received_at_collector": time_info.get("first_sample_received_at_collector"),
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
                        "alignment_confidence": self.policy.report_confidence,
                        **stream_fields,
                    }
                )
                running_offset_ns = self.policy.next_offset_ns(sample, resolved_offset)

        df = finalize_rows(rows, columns=self.policy.row_columns)
        ts_series = pd.to_datetime(df["ts_utc"], utc=True, errors="coerce") if not df.empty else pd.Series(dtype="datetime64[ns, UTC]")
        gap_count, max_gap_ms = compute_gap_metrics(ts_series)
        invalid_ratio = float(invalid_offset_count) / float(len(df.index)) if len(df.index) > 0 else 0.0
        if invalid_offset_count > 0:
            warnings.append("missing_or_invalid_offset_ns_fallback_used")

        start = ts_series.min() if not df.empty else None
        end = ts_series.max() if not df.empty else None
        start_iso = start.isoformat().replace("+00:00", "Z") if start is not None and not pd.isna(start) else None
        end_iso = end.isoformat().replace("+00:00", "Z") if end is not None and not pd.isna(end) else None

        report = {
            "session_id": session_id,
            "stream_id": stream_id,
            "stream_type": self.policy.stream_type,
            "payload_schema": self.policy.payload_schema,
            "user_id": user_id,
            "alignment_basis": self.policy.report_alignment_basis,
            "confidence": self.policy.report_confidence,
            "samples_count": int(len(df.index)),
            "chunks_count": chunks_count,
            "skipped_samples_count": skipped_samples_count,
            "invalid_or_missing_offset_count": invalid_offset_count,
            "invalid_ratio": invalid_ratio,
            "gap_count_gt_2s": gap_count,
            "max_gap_ms": max_gap_ms,
            "normalized_time_range": {"start_utc": start_iso, "end_utc": end_iso},
            "warnings": warnings,
        }
        return NormalizeHandlerOutput(dataframe=df, report=report, warnings=warnings)


# Backward-compatible alias
OnlineOffsetStreamPolicy = VeritySenseOnlineOffsetStreamPolicy
