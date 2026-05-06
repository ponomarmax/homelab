from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from ...common.base import BASE_COLUMNS, NormalizeHandlerOutput, finalize_rows
from ...common.chunking import iter_chunks_for_schema
from ...common.policies import BaseStreamPolicy


@dataclass(frozen=True)
class H10OnlineSamplePolicy(BaseStreamPolicy):
    sample_to_fields: Callable[[dict[str, Any]], dict[str, Any] | None]


class H10OnlineSampleStreamNormalizer:
    def __init__(self, *, name: str, policy: H10OnlineSamplePolicy) -> None:
        self.name = name
        self.policy = policy

    def handle(self, raw_path: Path) -> NormalizeHandlerOutput:
        rows: list[dict[str, Any]] = []
        chunk_contexts, warnings = iter_chunks_for_schema(raw_path, self.policy.payload_schema)
        skipped_samples_count = 0
        chunks_count = 0
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
                stream_fields = self.policy.sample_to_fields(sample)
                if stream_fields is None:
                    skipped_samples_count += 1
                    warnings.append(f"line {line_number}: sample {sample_idx} missing required fields")
                    continue
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
                        "alignment_confidence": self.policy.report_confidence,
                        **stream_fields,
                    }
                )

        df = finalize_rows(rows, columns=self.policy.row_columns)
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
            "warnings": warnings,
        }
        return NormalizeHandlerOutput(dataframe=df, report=report, warnings=warnings)


@dataclass(frozen=True)
class H10OnlineEventPolicy(BaseStreamPolicy):
    payload_to_fields: Callable[[dict[str, Any], dict[str, Any]], dict[str, Any] | None]


class H10OnlineEventNormalizer:
    def __init__(self, *, name: str, policy: H10OnlineEventPolicy) -> None:
        self.name = name
        self.policy = policy

    def handle(self, raw_path: Path) -> NormalizeHandlerOutput:
        rows: list[dict[str, Any]] = []
        chunk_contexts, warnings = iter_chunks_for_schema(raw_path, self.policy.payload_schema)
        skipped_chunks_count = 0
        chunks_count = 0
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
            payload = context.payload

            stream_fields = self.policy.payload_to_fields(payload, chunk)
            if stream_fields is None:
                skipped_chunks_count += 1
                warnings.append(f"line {line_number}: missing required fields")
                continue
            sample_ts = stream_fields.pop("__sample_ts")
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
                    "alignment_confidence": self.policy.report_confidence,
                    **stream_fields,
                }
            )

        df = finalize_rows(rows, columns=self.policy.row_columns)
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
            "skipped_chunks_count": skipped_chunks_count,
            "warnings": warnings,
        }
        return NormalizeHandlerOutput(dataframe=df, report=report, warnings=warnings)


# Backward-compatible aliases
H10SampleStreamPolicy = H10OnlineSamplePolicy
H10EventPolicy = H10OnlineEventPolicy
