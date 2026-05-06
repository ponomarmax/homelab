from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

import pandas as pd

POLAR_EPOCH_OFFSET_NS = 946_684_800_000_000_000
CURRENT_YEAR = datetime.now(UTC).year
MIN_PLAUSIBLE_YEAR = 2018
MAX_PLAUSIBLE_YEAR = CURRENT_YEAR + 1


@dataclass(frozen=True)
class StreamSpec:
    stream_type: str
    payload_schema: str
    time_field: str | None


@dataclass(frozen=True)
class TimelineStrategy:
    cadence_anchor: str


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


def as_float(value: Any) -> float | None:
    try:
        if value is None:
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def parse_ts(value: Any) -> pd.Timestamp | None:
    ts = pd.to_datetime(value, utc=True, errors="coerce")
    return None if pd.isna(ts) else ts


def ns_to_ts_utc(ns_value: int, *, with_polar_epoch: bool) -> pd.Timestamp | None:
    epoch_ns = ns_value + POLAR_EPOCH_OFFSET_NS if with_polar_epoch else ns_value
    ts = pd.to_datetime(epoch_ns, unit="ns", utc=True, errors="coerce")
    return None if pd.isna(ts) else ts


def ts_to_iso(ts: pd.Timestamp | None) -> str | None:
    if ts is None:
        return None
    return ts.isoformat().replace("+00:00", "Z")


def is_plausible_window(start: pd.Timestamp | None, end: pd.Timestamp | None) -> bool:
    if start is None or end is None:
        return False
    if not (MIN_PLAUSIBLE_YEAR <= start.year <= MAX_PLAUSIBLE_YEAR):
        return False
    if not (MIN_PLAUSIBLE_YEAR <= end.year <= MAX_PLAUSIBLE_YEAR):
        return False
    if end < start:
        return False
    duration_s = float((end - start).total_seconds())
    return duration_s <= 48 * 3600


def degrade_confidence(confidence: str, steps: int = 1) -> str:
    levels = ["low", "medium", "high"]
    idx = levels.index(confidence) if confidence in levels else 0
    return levels[max(idx - steps, 0)]


class VeritySenseOfflineAlignmentResolver:
    def extract_l0_candidate(self, chunk: dict[str, Any], samples_count: int, sample_rate_hz: float) -> SessionBasisCandidate:
        time_info = chunk.get("time") if isinstance(chunk.get("time"), dict) else {}
        payload = chunk.get("payload") if isinstance(chunk.get("payload"), dict) else {}

        start = parse_ts(time_info.get("recording_start_utc") or payload.get("recording_start_utc"))
        end = parse_ts(time_info.get("recording_end_utc") or payload.get("recording_end_utc"))

        if start is not None and end is None and samples_count > 1 and sample_rate_hz > 0:
            end = start + pd.to_timedelta(float(samples_count - 1) / sample_rate_hz, unit="s")
        if end is not None and start is None and samples_count > 1 and sample_rate_hz > 0:
            start = end - pd.to_timedelta(float(samples_count - 1) / sample_rate_hz, unit="s")

        if is_plausible_window(start, end):
            return SessionBasisCandidate(level="L0", start=start, end=end, quality="high", reason="device_recording_metadata")
        return SessionBasisCandidate(level="L0", start=start, end=end, quality="low", reason="missing_or_implausible_l0")

    def extract_l1_candidate(self, sample_timestamps: list[int], chunk: dict[str, Any]) -> SessionBasisCandidate:
        if not sample_timestamps:
            return SessionBasisCandidate(level="L1", start=None, end=None, quality="low", reason="no_sample_timestamps")

        time_info = chunk.get("time") if isinstance(chunk.get("time"), dict) else {}
        sync_state = str(time_info.get("clock_sync_state") or "unknown").lower()
        drift_ppm = as_float(time_info.get("clock_drift_estimate"))

        start = ns_to_ts_utc(sample_timestamps[0], with_polar_epoch=True)
        end = ns_to_ts_utc(sample_timestamps[-1], with_polar_epoch=True)
        if not is_plausible_window(start, end):
            if (start is not None and start.year > MAX_PLAUSIBLE_YEAR) or (end is not None and end.year > MAX_PLAUSIBLE_YEAR):
                return SessionBasisCandidate(level="L1", start=start, end=end, quality="low", reason="implausible_future_mapping")
            server = chunk.get("server") if isinstance(chunk.get("server"), dict) else {}
            reference_hint = parse_ts(
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
            if is_plausible_window(shifted_start, shifted_end):
                return SessionBasisCandidate(level="L1", start=shifted_start, end=shifted_end, quality="medium", reason="shifted_to_reference_hint")
            return SessionBasisCandidate(level="L1", start=start, end=end, quality="low", reason="implausible_direct_mapping")

        if sync_state != "synced":
            return SessionBasisCandidate(level="L1", start=start, end=end, quality="medium", reason="clock_not_synced")
        if drift_ppm is not None and drift_ppm > 100.0:
            return SessionBasisCandidate(level="L1", start=start, end=end, quality="medium", reason="clock_drift_high")
        return SessionBasisCandidate(level="L1", start=start, end=end, quality="high", reason="sample_ts_with_valid_clock_mapping")

    def extract_l4_candidate(self, chunk: dict[str, Any], samples_count: int, sample_rate_hz: float) -> SessionBasisCandidate:
        time_info = chunk.get("time") if isinstance(chunk.get("time"), dict) else {}
        server = chunk.get("server") if isinstance(chunk.get("server"), dict) else {}
        fetch_start = parse_ts(time_info.get("fetch_started_at_collector") or time_info.get("first_sample_received_at_collector"))
        fetch_end = parse_ts(time_info.get("fetch_completed_at_collector") or time_info.get("uploaded_at_collector") or server.get("received_at_server"))

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

    def resolve_basis(self, chunk: dict[str, Any], sample_timestamps: list[int], samples_count: int, sample_rate_hz: float) -> tuple[AlignmentDecision, list[str]]:
        warnings: list[str] = []
        l0 = self.extract_l0_candidate(chunk, samples_count, sample_rate_hz)
        l1 = self.extract_l1_candidate(sample_timestamps, chunk)
        l4 = self.extract_l4_candidate(chunk, samples_count, sample_rate_hz)

        if is_plausible_window(l0.start, l0.end):
            shift_ns = 0
            if sample_timestamps:
                first_raw = ns_to_ts_utc(sample_timestamps[0], with_polar_epoch=True)
                if first_raw is not None and l0.start is not None:
                    shift_ns = int((l0.start - first_raw).total_seconds() * 1_000_000_000)
            return AlignmentDecision(level="L0", basis="recording_start_utc/recording_end_utc", details=l0.reason, confidence="high", shift_ns=shift_ns), warnings

        if is_plausible_window(l1.start, l1.end):
            shift_ns = 0
            if sample_timestamps:
                first_raw = ns_to_ts_utc(sample_timestamps[0], with_polar_epoch=True)
                if first_raw is not None and l1.start is not None:
                    shift_ns = int((l1.start - first_raw).total_seconds() * 1_000_000_000)
            return AlignmentDecision(level="L1", basis="payload.samples[].timeStamp", details=l1.reason, confidence=l1.quality, shift_ns=shift_ns), warnings

        if is_plausible_window(l4.start, l4.end):
            return AlignmentDecision(level="L3", basis="reconstructed_from_collector_and_cadence", details="cadence_based_from_collector_anchor", confidence="low", shift_ns=None), warnings

        warnings.append("fallback_to_collector_server_time_L4")
        warnings.append("unable_to_establish_session_time_basis")
        return AlignmentDecision(level="L4", basis="unresolved", details="no_valid_candidate", confidence="low", shift_ns=None), warnings

    def ts_from_ns(self, ns_value: int, *, shift_ns: int | None) -> pd.Timestamp | None:
        base = ns_to_ts_utc(ns_value, with_polar_epoch=True)
        if base is None:
            return None
        if shift_ns:
            try:
                base = base + pd.to_timedelta(shift_ns, unit="ns")
            except (OverflowError, ValueError):
                return None
        return base
