from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import UTC, datetime, timezone
from pathlib import Path
from typing import Any

import pandas as pd

from .base import BASE_COLUMNS, NormalizeHandlerOutput, finalize_rows, parse_jsonl_chunks

POLAR_EPOCH_OFFSET_NS = 946_684_800_000_000_000
CURRENT_YEAR = datetime.now(UTC).year
MIN_PLAUSIBLE_YEAR = 2018
MAX_PLAUSIBLE_YEAR = CURRENT_YEAR + 1

OFFLINE_DEFAULT_RATE_HZ = {
    "hr": 1.0,
    "ppi": 1.0,
    "acc": 52.0,
    "gyro": 52.0,
    "mag": 50.0,
    "ppg": 55.0,
}

STREAM_ANCHOR_PRIORITY = ["acc", "hr", "gyro", "mag", "ppg", "ppi"]


@dataclass(frozen=True)
class StreamSpec:
    stream_type: str
    payload_schema: str
    time_field: str | None


@dataclass(frozen=True)
class TimelineStrategy:
    cadence_anchor: str


TIMELINE_STRATEGIES: dict[str, TimelineStrategy] = {
    "hr": TimelineStrategy(cadence_anchor="end"),
    "ppi": TimelineStrategy(cadence_anchor="start"),
    "acc": TimelineStrategy(cadence_anchor="start"),
    "gyro": TimelineStrategy(cadence_anchor="start"),
    "mag": TimelineStrategy(cadence_anchor="start"),
    "ppg": TimelineStrategy(cadence_anchor="start"),
}


@dataclass(frozen=True)
class AlignmentDecision:
    level: str
    basis: str
    details: str
    confidence: str
    shift_ns: int | None


@dataclass(frozen=True)
class SessionBasisCandidate:
    level: str
    start: pd.Timestamp | None
    end: pd.Timestamp | None
    quality: str
    reason: str


def _as_float(value: Any) -> float | None:
    try:
        if value is None:
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def _parse_ts(value: Any) -> pd.Timestamp | None:
    ts = pd.to_datetime(value, utc=True, errors="coerce")
    return None if pd.isna(ts) else ts


def _ns_to_ts_utc(ns_value: int, *, with_polar_epoch: bool) -> pd.Timestamp | None:
    epoch_ns = ns_value + POLAR_EPOCH_OFFSET_NS if with_polar_epoch else ns_value
    ts = pd.to_datetime(epoch_ns, unit="ns", utc=True, errors="coerce")
    return None if pd.isna(ts) else ts


def _ts_to_iso(ts: pd.Timestamp | None) -> str | None:
    if ts is None:
        return None
    return ts.isoformat().replace("+00:00", "Z")


def _is_plausible_ts(ts: pd.Timestamp | None) -> bool:
    return ts is not None and MIN_PLAUSIBLE_YEAR <= ts.year <= MAX_PLAUSIBLE_YEAR


def _is_plausible_window(start: pd.Timestamp | None, end: pd.Timestamp | None) -> bool:
    if start is None or end is None:
        return False
    if not _is_plausible_ts(start) or not _is_plausible_ts(end):
        return False
    if end < start:
        return False
    duration_s = float((end - start).total_seconds())
    return duration_s <= 48 * 3600


def _degrade(confidence: str, steps: int = 1) -> str:
    levels = ["low", "medium", "high"]
    idx = levels.index(confidence) if confidence in levels else 0
    return levels[max(idx - steps, 0)]


def _ppi_step_seconds(sample: dict[str, Any], default_rate_hz: float) -> float:
    pp_ms = sample.get("ppInMs")
    if isinstance(pp_ms, (int, float)) and pp_ms > 0:
        return float(pp_ms) / 1000.0
    if default_rate_hz > 0:
        return 1.0 / default_rate_hz
    return 1.0


class PolarVerityOfflineNormalizer:
    name = "PolarVerityOfflineNormalizer"

    def __init__(self, spec: StreamSpec) -> None:
        self.spec = spec
        self.timeline = TIMELINE_STRATEGIES.get(spec.stream_type, TimelineStrategy(cadence_anchor="start"))

    def _extract_l0_candidate(self, chunk: dict[str, Any], samples_count: int, sample_rate_hz: float) -> SessionBasisCandidate:
        time_info = chunk.get("time") if isinstance(chunk.get("time"), dict) else {}
        payload = chunk.get("payload") if isinstance(chunk.get("payload"), dict) else {}

        start = _parse_ts(time_info.get("recording_start_utc") or payload.get("recording_start_utc"))
        end = _parse_ts(time_info.get("recording_end_utc") or payload.get("recording_end_utc"))

        if start is not None and end is None and samples_count > 1 and sample_rate_hz > 0:
            end = start + pd.to_timedelta(float(samples_count - 1) / sample_rate_hz, unit="s")
        if end is not None and start is None and samples_count > 1 and sample_rate_hz > 0:
            start = end - pd.to_timedelta(float(samples_count - 1) / sample_rate_hz, unit="s")

        if _is_plausible_window(start, end):
            return SessionBasisCandidate(level="L0", start=start, end=end, quality="high", reason="device_recording_metadata")
        return SessionBasisCandidate(level="L0", start=start, end=end, quality="low", reason="missing_or_implausible_l0")

    def _extract_l1_candidate(self, sample_timestamps: list[int], chunk: dict[str, Any]) -> SessionBasisCandidate:
        if not sample_timestamps:
            return SessionBasisCandidate(level="L1", start=None, end=None, quality="low", reason="no_sample_timestamps")

        time_info = chunk.get("time") if isinstance(chunk.get("time"), dict) else {}
        sync_state = str(time_info.get("clock_sync_state") or "unknown").lower()
        drift_ppm = _as_float(time_info.get("clock_drift_estimate"))

        start = _ns_to_ts_utc(sample_timestamps[0], with_polar_epoch=True)
        end = _ns_to_ts_utc(sample_timestamps[-1], with_polar_epoch=True)
        if not _is_plausible_window(start, end):
            if (start is not None and start.year > MAX_PLAUSIBLE_YEAR) or (end is not None and end.year > MAX_PLAUSIBLE_YEAR):
                return SessionBasisCandidate(level="L1", start=start, end=end, quality="low", reason="implausible_future_mapping")
            time_info = chunk.get("time") if isinstance(chunk.get("time"), dict) else {}
            server = chunk.get("server") if isinstance(chunk.get("server"), dict) else {}
            reference_hint = _parse_ts(
                time_info.get("fetch_started_at_collector")
                or time_info.get("first_sample_received_at_collector")
                or time_info.get("uploaded_at_collector")
                or server.get("received_at_server")
            )
            if reference_hint is None or start is None or end is None:
                return SessionBasisCandidate(level="L1", start=start, end=end, quality="low", reason="implausible_direct_mapping")
            shift = reference_hint - start
            shifted_start = start + shift
            shifted_end = end + shift
            if _is_plausible_window(shifted_start, shifted_end):
                return SessionBasisCandidate(level="L1", start=shifted_start, end=shifted_end, quality="medium", reason="shifted_to_reference_hint")
            return SessionBasisCandidate(level="L1", start=start, end=end, quality="low", reason="implausible_direct_mapping")

        if sync_state != "synced":
            return SessionBasisCandidate(level="L1", start=start, end=end, quality="medium", reason="clock_not_synced")
        if drift_ppm is not None and drift_ppm > 100.0:
            return SessionBasisCandidate(level="L1", start=start, end=end, quality="medium", reason="clock_drift_high")
        return SessionBasisCandidate(level="L1", start=start, end=end, quality="high", reason="sample_ts_with_valid_clock_mapping")

    def _extract_l4_candidate(self, chunk: dict[str, Any], samples_count: int, sample_rate_hz: float) -> SessionBasisCandidate:
        time_info = chunk.get("time") if isinstance(chunk.get("time"), dict) else {}
        server = chunk.get("server") if isinstance(chunk.get("server"), dict) else {}
        fetch_start = _parse_ts(time_info.get("fetch_started_at_collector") or time_info.get("first_sample_received_at_collector"))
        fetch_end = _parse_ts(time_info.get("fetch_completed_at_collector") or time_info.get("uploaded_at_collector") or server.get("received_at_server"))

        if fetch_start is None and fetch_end is None:
            return SessionBasisCandidate(level="L4", start=None, end=None, quality="low", reason="no_collector_server_time")

        if fetch_start is None:
            fetch_start = fetch_end
        if fetch_end is None:
            fetch_end = fetch_start

        if fetch_end is not None and fetch_start is not None and fetch_end < fetch_start:
            fetch_start, fetch_end = fetch_end, fetch_start

        if fetch_start is not None and fetch_end is not None and fetch_start == fetch_end and samples_count > 1 and sample_rate_hz > 0:
            fetch_start = fetch_end - pd.to_timedelta(float(samples_count - 1) / sample_rate_hz, unit="s")

        return SessionBasisCandidate(level="L4", start=fetch_start, end=fetch_end, quality="low", reason="collector_server_fallback")

    def _resolve_basis(self, chunk: dict[str, Any], sample_timestamps: list[int], samples_count: int, sample_rate_hz: float) -> tuple[AlignmentDecision, list[str]]:
        warnings: list[str] = []
        l0 = self._extract_l0_candidate(chunk, samples_count, sample_rate_hz)
        l1 = self._extract_l1_candidate(sample_timestamps, chunk)
        l4 = self._extract_l4_candidate(chunk, samples_count, sample_rate_hz)

        if _is_plausible_window(l0.start, l0.end):
            shift_ns = 0
            if sample_timestamps:
                first_raw = _ns_to_ts_utc(sample_timestamps[0], with_polar_epoch=True)
                if first_raw is not None and l0.start is not None:
                    shift_ns = int((l0.start - first_raw).total_seconds() * 1_000_000_000)
            return AlignmentDecision(level="L0", basis="recording_start_utc/recording_end_utc", details=l0.reason, confidence="high", shift_ns=shift_ns), warnings

        if _is_plausible_window(l1.start, l1.end):
            shift_ns = 0
            if sample_timestamps:
                first_raw = _ns_to_ts_utc(sample_timestamps[0], with_polar_epoch=True)
                if first_raw is not None and l1.start is not None:
                    shift_ns = int((l1.start - first_raw).total_seconds() * 1_000_000_000)
            return AlignmentDecision(level="L1", basis="payload.samples[].timeStamp", details=l1.reason, confidence=l1.quality, shift_ns=shift_ns), warnings

        if _is_plausible_window(l4.start, l4.end):
            # We have a plausible anchor window but no trustworthy absolute sample mapping.
            # Reconstruct on cadence from a weak anchor => L3.
            return AlignmentDecision(
                level="L3",
                basis="reconstructed_from_collector_and_cadence",
                details="cadence_based_from_collector_anchor",
                confidence="low",
                shift_ns=None,
            ), warnings

        warnings.append("fallback_to_collector_server_time_L4")
        warnings.append("unable_to_establish_session_time_basis")
        return AlignmentDecision(level="L4", basis="unresolved", details="no_valid_candidate", confidence="low", shift_ns=None), warnings

    def _ts_from_ns(self, ns_value: int, *, shift_ns: int | None) -> pd.Timestamp | None:
        base = _ns_to_ts_utc(ns_value, with_polar_epoch=True)
        if base is None:
            return None
        if shift_ns:
            try:
                base = base + pd.to_timedelta(shift_ns, unit="ns")
            except (OverflowError, ValueError):
                return None
        return base

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
        source_app_origin = "unknown"

        decision = AlignmentDecision(level="L4", basis="unresolved", details="not_evaluated", confidence="low", shift_ns=None)
        ppi_invalid_or_zero_timestamps = 0
        valid_timestamp_count = 0
        total_timestamp_fields = 0

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
            source_app_origin = str(time_info.get("source_app_origin") or source_app_origin or "unknown")

            if not samples:
                warnings.append(f"line {line_number}: empty or malformed payload.samples")
                continue

            stream_rate_hz = _as_float(payload.get("sample_rate_hz")) or OFFLINE_DEFAULT_RATE_HZ.get(self.spec.stream_type, 1.0)
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
                        if self.spec.stream_type == "ppi":
                            ppi_invalid_or_zero_timestamps += 1
                        continue
                    sample_ts_values.append(raw)
                    valid_timestamp_count += 1

            if chunks_count == 1:
                decision, basis_warnings = self._resolve_basis(chunk, sample_ts_values, len(samples), stream_rate_hz)
                warnings.extend(basis_warnings)

            session_start = self._extract_l0_candidate(chunk, len(samples), stream_rate_hz).start if decision.level == "L0" else None
            if session_start is None and sample_ts_values:
                session_start = self._ts_from_ns(sample_ts_values[0], shift_ns=decision.shift_ns)
            if session_start is None:
                session_start = _parse_ts(time_info.get("fetch_started_at_collector") or time_info.get("first_sample_received_at_collector"))

            ppi_ts_candidates: dict[int, pd.Timestamp] = {}
            if self.spec.stream_type == "ppi" and self.spec.time_field:
                for idx, sample in enumerate(samples):
                    if not isinstance(sample, dict):
                        continue
                    raw_ts = sample.get(self.spec.time_field)
                    if isinstance(raw_ts, int) and raw_ts > 0:
                        parsed = self._ts_from_ns(int(raw_ts), shift_ns=decision.shift_ns)
                        if parsed is not None:
                            ppi_ts_candidates[idx] = parsed

            for sample_idx, sample in enumerate(samples, start=1):
                if not isinstance(sample, dict):
                    skipped_samples_count += 1
                    warnings.append(f"line {line_number}: sample {sample_idx} malformed")
                    continue

                ts: pd.Timestamp | None = None
                raw_sample_ts = sample.get(self.spec.time_field) if self.spec.time_field else None
                if isinstance(raw_sample_ts, int) and (self.spec.stream_type != "ppi" or raw_sample_ts > 0):
                    ts = self._ts_from_ns(int(raw_sample_ts), shift_ns=decision.shift_ns)

                if ts is None and self.spec.stream_type == "ppi":
                    idx = sample_idx - 1
                    if idx in ppi_ts_candidates:
                        ts = ppi_ts_candidates[idx]
                    else:
                        prev_idx = max((k for k in ppi_ts_candidates.keys() if k < idx), default=None)
                        next_idx = min((k for k in ppi_ts_candidates.keys() if k > idx), default=None)
                        if prev_idx is not None and next_idx is not None and next_idx > prev_idx:
                            prev_ts = ppi_ts_candidates[prev_idx]
                            next_ts = ppi_ts_candidates[next_idx]
                            fraction = float(idx - prev_idx) / float(next_idx - prev_idx)
                            ts = prev_ts + (next_ts - prev_ts) * fraction
                        elif prev_idx is not None:
                            step = _ppi_step_seconds(sample, stream_rate_hz)
                            ts = ppi_ts_candidates[prev_idx] + pd.to_timedelta(step * (idx - prev_idx), unit="s")
                        elif next_idx is not None:
                            step = _ppi_step_seconds(sample, stream_rate_hz)
                            ts = ppi_ts_candidates[next_idx] - pd.to_timedelta(step * (next_idx - idx), unit="s")

                if ts is None and session_start is not None and stream_rate_hz > 0:
                    index = int(sample.get("sample_index")) if isinstance(sample.get("sample_index"), int) else (sample_idx - 1)
                    if self.timeline.cadence_anchor == "end":
                        reverse_offset = max(len(samples) - 1 - index, 0) / stream_rate_hz
                        ts = session_start - pd.to_timedelta(reverse_offset, unit="s")
                    else:
                        ts = session_start + pd.to_timedelta(index / stream_rate_hz, unit="s")

                if ts is None:
                    skipped_samples_count += 1
                    warnings.append(f"line {line_number}: sample {sample_idx} missing resolvable timestamp")
                    continue

                row = {
                    "ts_utc": _ts_to_iso(ts),
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

        valid_ratio = (float(valid_timestamp_count) / float(total_timestamp_fields)) if total_timestamp_fields > 0 else 0.0
        confidence = decision.confidence
        if source_app_origin == "third_party" and decision.level != "L0":
            confidence = _degrade(confidence)
            warnings.append("third_party_origin_without_l0_metadata")
        if 0.0 < valid_ratio < 0.8:
            confidence = _degrade(confidence)
            warnings.append("mixed_valid_invalid_timestamps")
        if self.spec.stream_type == "ppi" and ppi_invalid_or_zero_timestamps > 0:
            warnings.append("ppi invalid_or_zero_timestamps fallback used for timestamp reconstruction")
            confidence = _degrade(confidence)

        start_iso = _ts_to_iso(start.tz_convert(timezone.utc) if start is not None and start.tzinfo is not None else start)
        end_iso = _ts_to_iso(end.tz_convert(timezone.utc) if end is not None and end.tzinfo is not None else end)

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
            # backward-compatible keys
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
