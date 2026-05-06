from __future__ import annotations

from typing import Any

from ....common.base import BASE_COLUMNS
from ..common import VeritySenseOnlineOffsetNormalizer, VeritySenseOnlineOffsetStreamPolicy

PPI_COLUMNS = BASE_COLUMNS + [
    "sample_index",
    "offset_ns",
    "device_time_ns",
    "raw_sample_timestamp_ns",
    "ppi_ms",
    "hr_bpm",
    "pp_error_estimate_ms",
    "blocker",
    "skin_contact_supported",
    "skin_contact",
]


def _as_int(value: Any) -> int | None:
    try:
        if value is None:
            return None
        return int(value)
    except (TypeError, ValueError):
        return None


def _resolve_ppi_ms(sample: dict[str, Any]) -> int | None:
    for key in ("ppi_ms", "pp_ms", "ppInMs"):
        resolved = _as_int(sample.get(key))
        if resolved is not None and resolved >= 0:
            return resolved
    return None


def _resolve_hr_bpm(sample: dict[str, Any]) -> int | None:
    for key in ("hr_bpm", "hr"):
        resolved = _as_int(sample.get(key))
        if resolved is not None and resolved >= 0:
            return resolved
    return None


def _resolve_offset_ns(sample: dict[str, Any]) -> int | None:
    for key in ("offset_ns", "device_time_ns", "timeStamp"):
        resolved = _as_int(sample.get(key))
        if resolved is not None and resolved >= 0:
            return resolved
    return None


def _ppi_fields(sample: dict[str, Any], fallback_index: int) -> dict[str, Any] | None:
    ppi_ms = _resolve_ppi_ms(sample)
    if ppi_ms is None:
        return None
    return {
        "sample_index": sample.get("sample_index") if isinstance(sample.get("sample_index"), int) else fallback_index,
        "offset_ns": sample.get("offset_ns"),
        "device_time_ns": sample.get("device_time_ns"),
        "raw_sample_timestamp_ns": sample.get("timeStamp"),
        "ppi_ms": ppi_ms,
        "hr_bpm": _resolve_hr_bpm(sample),
        "pp_error_estimate_ms": _as_int(sample.get("pp_error_estimate_ms") if sample.get("pp_error_estimate_ms") is not None else sample.get("ppErrorEstimate")),
        "blocker": sample.get("blocker") if sample.get("blocker") is not None else sample.get("blockerBit"),
        "skin_contact_supported": sample.get("skin_contact_supported") if sample.get("skin_contact_supported") is not None else sample.get("skinContactSupported"),
        "skin_contact": sample.get("skin_contact") if sample.get("skin_contact") is not None else sample.get("skinContactStatus"),
    }


def _next_offset_ns(sample: dict[str, Any], resolved_offset_ns: int) -> int:
    ppi_ms = _resolve_ppi_ms(sample) or 0
    return resolved_offset_ns + (ppi_ms * 1_000_000)


PPI_POLICY = VeritySenseOnlineOffsetStreamPolicy(
    payload_schema="polar.ppi",
    stream_type="ppi",
    report_confidence="medium",
    report_alignment_basis="time.first_sample_received_at_collector + payload.samples[].offset_ns",
    row_columns=PPI_COLUMNS,
    sample_to_fields=_ppi_fields,
    resolve_offset_ns=_resolve_offset_ns,
    next_offset_ns=_next_offset_ns,
)


class PolarPpiNormalizer(VeritySenseOnlineOffsetNormalizer):
    name = "PolarPpiNormalizer"
    payload_schema = "polar.ppi"

    def __init__(self) -> None:
        super().__init__(name=self.name, policy=PPI_POLICY)


class VeritySenseOnlinePpiNormalizer(PolarPpiNormalizer):
    name = "VeritySenseOnlinePpiNormalizer"
