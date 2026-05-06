from __future__ import annotations

import math
from typing import Any

from ...common.base import BASE_COLUMNS
from .common import H10OnlineSamplePolicy, H10OnlineSampleStreamNormalizer

ACC_COLUMNS = BASE_COLUMNS + [
    "device_time_ns",
    "x_mg",
    "y_mg",
    "z_mg",
    "vector_magnitude_mg",
]


def _acc_fields(sample: dict[str, Any]) -> dict[str, Any] | None:
    x_mg = sample.get("x_mg")
    y_mg = sample.get("y_mg")
    z_mg = sample.get("z_mg")
    if x_mg is None or y_mg is None or z_mg is None:
        return None
    x = float(x_mg)
    y = float(y_mg)
    z = float(z_mg)
    return {
        "device_time_ns": sample.get("device_time_ns"),
        "x_mg": x,
        "y_mg": y,
        "z_mg": z,
        "vector_magnitude_mg": math.sqrt((x * x) + (y * y) + (z * z)),
    }


ACC_POLICY = H10OnlineSamplePolicy(
    payload_schema="polar.acc",
    stream_type="acc",
    report_confidence="medium",
    report_alignment_basis="payload.samples[].received_at_collector",
    row_columns=ACC_COLUMNS,
    sample_to_fields=_acc_fields,
)


class PolarAccNormalizer(H10OnlineSampleStreamNormalizer):
    name = "PolarAccNormalizer"
    payload_schema = "polar.acc"

    def __init__(self) -> None:
        super().__init__(name=self.name, policy=ACC_POLICY)
