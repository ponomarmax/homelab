from __future__ import annotations

from typing import Any

from ...common.base import BASE_COLUMNS
from .common import H10OnlineSamplePolicy, H10OnlineSampleStreamNormalizer

ECG_COLUMNS = BASE_COLUMNS + [
    "device_time_ns",
    "ecg_uv",
]


def _ecg_fields(sample: dict[str, Any]) -> dict[str, Any] | None:
    ecg_uv = sample.get("ecg_uv")
    if ecg_uv is None:
        return None
    return {
        "device_time_ns": sample.get("device_time_ns"),
        "ecg_uv": float(ecg_uv),
    }


ECG_POLICY = H10OnlineSamplePolicy(
    payload_schema="polar.ecg",
    stream_type="ecg",
    report_confidence="medium",
    report_alignment_basis="payload.samples[].received_at_collector",
    row_columns=ECG_COLUMNS,
    sample_to_fields=_ecg_fields,
)


class PolarEcgNormalizer(H10OnlineSampleStreamNormalizer):
    name = "PolarEcgNormalizer"
    payload_schema = "polar.ecg"

    def __init__(self) -> None:
        super().__init__(name=self.name, policy=ECG_POLICY)
