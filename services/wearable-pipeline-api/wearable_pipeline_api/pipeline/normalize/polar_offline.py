from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import timezone
from pathlib import Path
from typing import Any

import pandas as pd

from .base import BASE_COLUMNS, NormalizeHandlerOutput, finalize_rows, parse_jsonl_chunks

POLAR_EPOCH_OFFSET_NS = 946_684_800_000_000_000
PLAUSIBLE_DELTA_SECONDS = 24 * 60 * 60

OFFLINE_DEFAULT_RATE_HZ = {
    "hr": 1.0,
    "ppi": 1.0,
    "acc": 52.0,
    "gyro": 52.0,
    "mag": 50.0,
    "ppg": 55.0,
}


def _as_float(value: Any) -> float | None:
    try:
        if value is None:
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def _ns_to_iso_utc(ns_value: int, *, with_polar_epoch: bool) -> str | None:
    epoch_ns = ns_value + POLAR_EPOCH_OFFSET_NS if with_polar_epoch else ns_value
    ts = pd.to_datetime(epoch_ns, unit="ns", utc=True, errors="coerce")
    if pd.isna(ts):
        return None
    return ts.isoformat().replace("+00:00", "Z")


def _parse_ts(value: Any) -> pd.Timestamp | None:
    ts = pd.to_datetime(value, utc=True, errors="coerce")
    return None if pd.isna(ts) else ts


@dataclass(frozen=True)
class StreamSpec:
    stream_type: str
    payload_schema: str
    time_field: str | None


class PolarVerityOfflineNormalizer:
    name = "PolarVerityOfflineNormalizer"

    def __init__(self, spec: StreamSpec) -> None:
        self.spec = spec

    def _alignment_choice(self, sample_timestamps: list[int], collector_hint: pd.Timestamp | None) -> tuple[str, str, str, int | None, list[str]]:
        warnings: list[str] = []
        if not sample_timestamps:
            return "reconstructed_from_collector_and_cadence", "no_sample_timestamp", "low", None, warnings

        first_ts = sample_timestamps[0]
        direct_iso = _ns_to_iso_utc(first_ts, with_polar_epoch=True)
        if direct_iso is None:
            return "reconstructed_from_collector_and_cadence", "invalid_sample_timestamp", "low", None, warnings

        direct = _parse_ts(direct_iso)
        if collector_hint is None or direct is None:
            return "payload.samples[].timeStamp", "polar_epoch_ns_direct", "high", 0, warnings

        delta_seconds = abs((collector_hint - direct).total_seconds())
        if delta_seconds <= PLAUSIBLE_DELTA_SECONDS:
            return "payload.samples[].timeStamp", "polar_epoch_ns_direct", "high", 0, warnings

        shift_ns = int((collector_hint - direct).total_seconds() * 1_000_000_000)
        warnings.append("applied timestamp shift from collector reference due to implausible direct mapping")
        return "payload.samples[].timeStamp", "polar_epoch_ns_shifted_to_collector", "medium", shift_ns, warnings

    def _ts_from_ns(self, ns_value: int, *, shift_ns: int | None) -> str | None:
        base_iso = _ns_to_iso_utc(ns_value, with_polar_epoch=True)
        if base_iso is None:
            return None
        base = _parse_ts(base_iso)
        if base is None:
            return None
        if shift_ns:
            try:
                base = base + pd.to_timedelta(shift_ns, unit="ns")
            except (OverflowError, ValueError):
                return None
        return base.isoformat().replace("+00:00", "Z")

    def _build_stream_fields(self, sample: dict[str, Any]) -> dict[str, Any]:
        stream = self.spec.stream_type
        if stream == "hr":
            return {
                "hr": sample.get("hr"),
                "corrected_hr": sample.get("corrected_hr"),
                "ppg_quality": sample.get("ppg_quality"),
                "rrs_ms": sample.get("rrs_ms") if isinstance(sample.get("rrs_ms"), list) else [],
                "rr_available": sample.get("rr_available"),
                "contact_status": sample.get("contact_status"),
                "contact_status_supported": sample.get("contact_status_supported"),
            }
        if stream == "ppi":
            return {
                "hr": sample.get("hr"),
                "pp_in_ms": sample.get("ppInMs"),
                "pp_error_estimate": sample.get("ppErrorEstimate"),
                "blocker_bit": sample.get("blockerBit"),
                "skin_contact_status": sample.get("skinContactStatus"),
                "skin_contact_supported": sample.get("skinContactSupported"),
            }
        if stream in {"acc", "gyro", "mag"}:
            x = _as_float(sample.get("x"))
            y = _as_float(sample.get("y"))
            z = _as_float(sample.get("z"))
            return {
                "x": x,
                "y": y,
                "z": z,
                "vector_magnitude": (math.sqrt((x * x) + (y * y) + (z * z)) if x is not None and y is not None and z is not None else None),
            }
        if stream == "ppg":
            values = sample.get("channelSamples") if isinstance(sample.get("channelSamples"), list) else []
            return {
                "ppg0": sample.get("ppg0"),
                "ppg1": sample.get("ppg1"),
                "ppg2": sample.get("ppg2"),
                "ambient": sample.get("ambient"),
                "channel_samples": values,
            }
        return {}

    def handle(self, raw_path: Path) -> NormalizeHandlerOutput:
        rows: list[dict[str, Any]] = []
        chunks, warnings = parse_jsonl_chunks(raw_path)
        skipped_samples_count = 0
        chunks_count = 0

        session_id = ""
        stream_id = ""
        user_id = ""
        alignment_basis = "reconstructed_from_collector_and_cadence"
        epoch_decision = "no_sample_timestamp"
        confidence = "low"
        shift_ns_used: int | None = None

        for chunk in chunks:
            line_number = int(chunk.get("__line_number") or 0)
            payload_schema = str(((chunk.get("transport") or {}).get("payload_schema") or "")).strip().lower()
            if payload_schema != self.spec.payload_schema:
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
                continue

            collector_hint = _parse_ts(time_info.get("first_sample_received_at_collector"))
            sample_ts_values: list[int] = []
            if self.spec.time_field:
                for sample in samples:
                    if isinstance(sample, dict) and isinstance(sample.get(self.spec.time_field), int):
                        sample_ts_values.append(int(sample.get(self.spec.time_field)))
            if chunks_count == 1:
                alignment_basis, epoch_decision, confidence, shift_ns_used, extra_warnings = self._alignment_choice(sample_ts_values, collector_hint)
                warnings.extend(extra_warnings)

            stream_rate_hz = _as_float(payload.get("sample_rate_hz")) or OFFLINE_DEFAULT_RATE_HZ.get(self.spec.stream_type, 1.0)
            start_ts = collector_hint or _parse_ts(time_info.get("uploaded_at_collector")) or _parse_ts(server.get("received_at_server"))

            for sample_idx, sample in enumerate(samples, start=1):
                if not isinstance(sample, dict):
                    skipped_samples_count += 1
                    warnings.append(f"line {line_number}: sample {sample_idx} malformed")
                    continue

                ts_value: str | None = None
                raw_sample_ts = sample.get(self.spec.time_field) if self.spec.time_field else None
                if isinstance(raw_sample_ts, int):
                    ts_value = self._ts_from_ns(int(raw_sample_ts), shift_ns=shift_ns_used)
                elif start_ts is not None and stream_rate_hz and stream_rate_hz > 0:
                    index = int(sample.get("sample_index")) if isinstance(sample.get("sample_index"), int) else (sample_idx - 1)
                    ts_value = (start_ts + pd.to_timedelta(index / stream_rate_hz, unit="s")).isoformat().replace("+00:00", "Z")

                if not ts_value:
                    skipped_samples_count += 1
                    warnings.append(f"line {line_number}: sample {sample_idx} missing resolvable timestamp")
                    continue

                row = {
                    "ts_utc": ts_value,
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
                    "alignment_confidence": confidence,
                    "sample_index": sample.get("sample_index") if isinstance(sample.get("sample_index"), int) else (sample_idx - 1),
                    "raw_sample_timestamp_ns": raw_sample_ts,
                }
                row.update(self._build_stream_fields(sample))
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
        expected = max(float(len(df.index) - 1), 0.0) / OFFLINE_DEFAULT_RATE_HZ.get(self.spec.stream_type, 1.0) if not df.empty else 0.0
        duration_delta = abs(duration - expected)
        duration_warning = None
        if expected > 0 and duration_delta > max(3.0, expected * 0.35):
            duration_warning = "duration deviates from expected cadence"
            warnings.append(duration_warning)

        if start is not None and end is not None and start.tzinfo is not None:
            start_iso = start.tz_convert(timezone.utc).isoformat().replace("+00:00", "Z")
            end_iso = end.tz_convert(timezone.utc).isoformat().replace("+00:00", "Z")
        else:
            start_iso = None
            end_iso = None

        report = {
            "session_id": session_id,
            "stream_id": stream_id,
            "stream_type": self.spec.stream_type,
            "payload_schema": self.spec.payload_schema,
            "user_id": user_id,
            "alignment_basis": alignment_basis,
            "epoch_offset_decision": epoch_decision,
            "confidence": confidence,
            "samples_count": int(len(df.index)),
            "chunks_count": chunks_count,
            "skipped_samples_count": skipped_samples_count,
            "normalized_time_range": {"start_utc": start_iso, "end_utc": end_iso},
            "duration_sanity": {
                "duration_seconds": duration,
                "expected_seconds_from_default_rate": expected,
                "absolute_delta_seconds": duration_delta,
                "warning": duration_warning,
            },
            "warnings": warnings,
        }
        return NormalizeHandlerOutput(dataframe=df, report=report, warnings=warnings)
