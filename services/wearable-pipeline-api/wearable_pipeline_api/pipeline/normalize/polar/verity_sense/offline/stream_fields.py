from __future__ import annotations

import math
from typing import Any

from .alignment import as_float

PPI_ERROR_STRICT_MS = 10
PPI_ERROR_LOW_CONFIDENCE_MS = 30


def ppi_step_seconds(sample: dict[str, Any], default_rate_hz: float) -> float:
    pp_ms = sample.get("ppInMs")
    if isinstance(pp_ms, (int, float)) and pp_ms > 0:
        return float(pp_ms) / 1000.0
    if default_rate_hz > 0:
        return 1.0 / default_rate_hz
    return 1.0


def build_hr_fields(sample: dict[str, Any]) -> dict[str, Any]:
    return {
        "hr": sample.get("hr"),
        "corrected_hr": sample.get("corrected_hr"),
        "ppg_quality": sample.get("ppg_quality"),
        "rrs_ms": sample.get("rrs_ms") if isinstance(sample.get("rrs_ms"), list) else [],
        "rr_available": sample.get("rr_available"),
        "contact_status": sample.get("contact_status"),
        "contact_status_supported": sample.get("contact_status_supported"),
    }


def build_ppi_fields(sample: dict[str, Any]) -> dict[str, Any]:
    pp_error_estimate = sample.get("ppErrorEstimate")
    blocker_bit = sample.get("blockerBit")
    skin_contact_status = sample.get("skinContactStatus")
    skin_contact_supported = sample.get("skinContactSupported")

    if isinstance(pp_error_estimate, (int, float)):
        if pp_error_estimate < PPI_ERROR_STRICT_MS:
            pp_error_band = "strict_lt10ms"
        elif pp_error_estimate <= PPI_ERROR_LOW_CONFIDENCE_MS:
            pp_error_band = "moderate_10_to_30ms"
        else:
            pp_error_band = "high_gt30ms"
    else:
        pp_error_band = "unknown"

    blocked = bool(blocker_bit == 1)
    skin_contact_missing = bool(skin_contact_supported == 1 and skin_contact_status == 0)

    if blocked:
        quality_tier = "low"
    elif pp_error_band == "high_gt30ms":
        quality_tier = "low"
    elif pp_error_band == "moderate_10_to_30ms" or skin_contact_missing:
        quality_tier = "medium"
    else:
        quality_tier = "high"

    return {
        "hr": sample.get("hr"),
        "pp_in_ms": sample.get("ppInMs"),
        "pp_error_estimate": pp_error_estimate,
        "blocker_bit": blocker_bit,
        "skin_contact_status": skin_contact_status,
        "skin_contact_supported": skin_contact_supported,
        "pp_error_band": pp_error_band,
        "sample_quality_tier": quality_tier,
        "sample_quality_blocked": blocked,
        "sample_quality_skin_contact_missing": skin_contact_missing,
    }


def _build_vector_fields(sample: dict[str, Any]) -> dict[str, Any]:
    x = as_float(sample.get("x"))
    y = as_float(sample.get("y"))
    z = as_float(sample.get("z"))
    return {
        "x": x,
        "y": y,
        "z": z,
        "vector_magnitude": (math.sqrt((x * x) + (y * y) + (z * z)) if x is not None and y is not None and z is not None else None),
    }


def build_acc_fields(sample: dict[str, Any]) -> dict[str, Any]:
    return _build_vector_fields(sample)


def build_gyro_fields(sample: dict[str, Any]) -> dict[str, Any]:
    return _build_vector_fields(sample)


def build_mag_fields(sample: dict[str, Any]) -> dict[str, Any]:
    return _build_vector_fields(sample)


def build_ppg_fields(sample: dict[str, Any]) -> dict[str, Any]:
    values = sample.get("channelSamples") if isinstance(sample.get("channelSamples"), list) else []
    return {
        "ppg0": sample.get("ppg0"),
        "ppg1": sample.get("ppg1"),
        "ppg2": sample.get("ppg2"),
        "ambient": sample.get("ambient"),
        "channel_samples": values,
    }
