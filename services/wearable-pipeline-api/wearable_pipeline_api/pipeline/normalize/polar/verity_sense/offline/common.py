from __future__ import annotations

from datetime import timezone
from pathlib import Path
from typing import Any

import pandas as pd

from ...common.base import BASE_COLUMNS, NormalizeHandlerOutput, finalize_rows
from ...common.chunking import iter_chunks_for_schema
from .alignment import (
    AlignmentDecision,
    StreamSpec,
    VeritySenseOfflineAlignmentResolver,
    as_float,
    degrade_confidence,
    parse_ts,
    ts_to_iso,
)
from .streams.policies import POLICY_BY_SCHEMA, VeritySenseOfflineStreamPolicy


class PolarVerityOfflineNormalizer:
    name = "PolarVerityOfflineNormalizer"

    def __init__(self, spec: StreamSpec, policy: VeritySenseOfflineStreamPolicy | None = None) -> None:
        self.spec = spec
        self.policy = policy or POLICY_BY_SCHEMA.get(spec.payload_schema) or VeritySenseOfflineStreamPolicy(
            spec=spec,
            payload_schema=spec.payload_schema,
            stream_type=spec.stream_type,
            report_confidence="low",
            report_alignment_basis="offline_policy_managed",
            row_columns=[],
            default_rate_hz=1.0,
            cadence_anchor="start",
            uses_invalid_zero_timestamp_repair=False,
            field_builder=lambda _sample: {},
            build_timestamp_candidates=lambda _samples, _time_field, _resolve: {},
            repair_missing_timestamp=lambda _idx, _sample, _candidates, _rate: None,
        )
        self.alignment = VeritySenseOfflineAlignmentResolver()

    def handle(self, raw_path: Path) -> NormalizeHandlerOutput:
        rows: list[dict[str, Any]] = []
        chunk_contexts, warnings = iter_chunks_for_schema(raw_path, self.spec.payload_schema)
        skipped_samples_count = 0
        chunks_count = 0

        session_id = ""
        stream_id = ""
        user_id = ""
        source_app_origin = "unknown"

        decision = AlignmentDecision(level="L4", basis="unresolved", details="not_evaluated", confidence="low", shift_ns=None)
        ppi_invalid_or_zero_timestamps = 0
        valid_timestamp_count = 0
        total_timestamp_fields = 0

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
            samples = context.samples
            source_app_origin = str(time_info.get("source_app_origin") or source_app_origin or "unknown")

            if not samples:
                warnings.append(f"line {line_number}: empty or malformed payload.samples")
                continue

            stream_rate_hz = as_float(payload.get("sample_rate_hz")) or self.policy.default_rate_hz
            sample_ts_values: list[int] = []
            if self.spec.time_field:
                for sample in samples:
                    if not isinstance(sample, dict):
                        continue
                    raw = sample.get(self.spec.time_field)
                    if not isinstance(raw, int):
                        continue
                    total_timestamp_fields += 1
                    if raw <= 0:
                        if self.policy.uses_invalid_zero_timestamp_repair:
                            ppi_invalid_or_zero_timestamps += 1
                        continue
                    sample_ts_values.append(raw)
                    valid_timestamp_count += 1

            if chunks_count == 1:
                decision, basis_warnings = self.alignment.resolve_basis(chunk, sample_ts_values, len(samples), stream_rate_hz)
                warnings.extend(basis_warnings)

            session_start = self.alignment.extract_l0_candidate(chunk, len(samples), stream_rate_hz).start if decision.level == "L0" else None
            if session_start is None and sample_ts_values:
                session_start = self.alignment.ts_from_ns(sample_ts_values[0], shift_ns=decision.shift_ns)
            if session_start is None:
                session_start = parse_ts(time_info.get("fetch_started_at_collector") or time_info.get("first_sample_received_at_collector"))

            ppi_ts_candidates = self.policy.build_timestamp_candidates(
                samples,
                self.spec.time_field,
                lambda raw_ns: self.alignment.ts_from_ns(raw_ns, shift_ns=decision.shift_ns),
            )

            for sample_idx, sample in enumerate(samples, start=1):
                if not isinstance(sample, dict):
                    skipped_samples_count += 1
                    warnings.append(f"line {line_number}: sample {sample_idx} malformed")
                    continue

                ts: pd.Timestamp | None = None
                raw_sample_ts = sample.get(self.spec.time_field) if self.spec.time_field else None
                if isinstance(raw_sample_ts, int) and (not self.policy.uses_invalid_zero_timestamp_repair or raw_sample_ts > 0):
                    ts = self.alignment.ts_from_ns(int(raw_sample_ts), shift_ns=decision.shift_ns)

                if ts is None and self.policy.uses_invalid_zero_timestamp_repair:
                    ts = self.policy.repair_missing_timestamp(sample_idx - 1, sample, ppi_ts_candidates, stream_rate_hz)

                if ts is None and session_start is not None and stream_rate_hz > 0:
                    index = int(sample.get("sample_index")) if isinstance(sample.get("sample_index"), int) else (sample_idx - 1)
                    if self.policy.cadence_anchor == "end":
                        reverse_offset = max(len(samples) - 1 - index, 0) / stream_rate_hz
                        ts = session_start - pd.to_timedelta(reverse_offset, unit="s")
                    else:
                        ts = session_start + pd.to_timedelta(index / stream_rate_hz, unit="s")

                if ts is None:
                    skipped_samples_count += 1
                    warnings.append(f"line {line_number}: sample {sample_idx} missing resolvable timestamp")
                    continue

                row = {
                    "ts_utc": ts_to_iso(ts),
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
                    "alignment_confidence": decision.confidence,
                    "sample_index": sample.get("sample_index") if isinstance(sample.get("sample_index"), int) else (sample_idx - 1),
                    "raw_sample_timestamp_ns": raw_sample_ts,
                }
                row.update(self.policy.field_builder(sample))
                rows.append(row)

        if rows:
            extra_columns = sorted({key for row in rows for key in row.keys()} - set(BASE_COLUMNS) - {"ts_utc"})
            columns = BASE_COLUMNS + extra_columns
        else:
            columns = BASE_COLUMNS + ["sample_index", "raw_sample_timestamp_ns"]

        df = finalize_rows(rows, columns=columns)
        start = df["ts_utc"].min() if not df.empty else None
        end = df["ts_utc"].max() if not df.empty else None

        duration = max(float((end - start).total_seconds()), 0.0) if start is not None and end is not None else 0.0
        expected = max(float(len(df.index) - 1), 0.0) / self.policy.default_rate_hz if not df.empty else 0.0
        duration_delta = abs(duration - expected)
        duration_warning = None
        if expected > 0 and duration_delta > max(3.0, expected * 0.35):
            duration_warning = "duration deviates from expected cadence"
            warnings.append(duration_warning)

        valid_ratio = (float(valid_timestamp_count) / float(total_timestamp_fields)) if total_timestamp_fields > 0 else 0.0
        confidence = decision.confidence
        if source_app_origin == "third_party" and decision.level != "L0":
            confidence = degrade_confidence(confidence)
            warnings.append("third_party_origin_without_l0_metadata")
        if 0.0 < valid_ratio < 0.8:
            confidence = degrade_confidence(confidence)
            warnings.append("mixed_valid_invalid_timestamps")
        if self.policy.uses_invalid_zero_timestamp_repair and ppi_invalid_or_zero_timestamps > 0:
            warnings.append("ppi invalid_or_zero_timestamps fallback used for timestamp reconstruction")
            confidence = degrade_confidence(confidence)

        start_iso = ts_to_iso(start.tz_convert(timezone.utc) if start is not None and start.tzinfo is not None else start)
        end_iso = ts_to_iso(end.tz_convert(timezone.utc) if end is not None and end.tzinfo is not None else end)

        basis_details = {
            "selected_source": decision.basis,
            "selected_reason": decision.details,
            "source_app_origin": source_app_origin,
        }
        hard_fail_reasons: list[str] = []
        if decision.level == "L4" and decision.basis == "unresolved":
            hard_fail_reasons.append("no_valid_time_basis")

        report = {
            "session_id": session_id,
            "stream_id": stream_id,
            "stream_type": self.spec.stream_type,
            "payload_schema": self.spec.payload_schema,
            "user_id": user_id,
            "alignment_basis_level": decision.level,
            "alignment_basis_details": basis_details,
            "confidence": confidence,
            "applied_shift_ns": decision.shift_ns,
            "session_window_start": start_iso,
            "session_window_end": end_iso,
            "per_stream_start": start_iso,
            "per_stream_end": end_iso,
            "warnings": warnings,
            "hard_fail_reasons": hard_fail_reasons,
            "alignment_basis": decision.basis,
            "epoch_offset_decision": decision.details,
            "samples_count": int(len(df.index)),
            "chunks_count": chunks_count,
            "skipped_samples_count": skipped_samples_count,
            "invalid_or_zero_sample_timestamps_count": ppi_invalid_or_zero_timestamps,
            "normalized_time_range": {"start_utc": start_iso, "end_utc": end_iso},
            "duration_sanity": {
                "duration_seconds": duration,
                "expected_seconds_from_default_rate": expected,
                "absolute_delta_seconds": duration_delta,
                "warning": duration_warning,
            },
        }
        return NormalizeHandlerOutput(dataframe=df, report=report, warnings=warnings)
