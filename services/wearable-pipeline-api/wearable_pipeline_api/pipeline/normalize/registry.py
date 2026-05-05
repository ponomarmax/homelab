from __future__ import annotations

from pathlib import Path
from typing import Protocol

from .acc import PolarAccNormalizer
from .base import NormalizeHandlerOutput
from .device_battery import PolarDeviceBatteryNormalizer
from .ecg import PolarEcgNormalizer
from .hr import PolarHrNormalizer
from .polar_offline import PolarVerityOfflineNormalizer, StreamSpec


class NormalizeHandler(Protocol):
    name: str

    def handle(self, raw_path: Path) -> NormalizeHandlerOutput:
        pass


HandlerKey = tuple[str, str, str]


def normalize_handler_registry() -> dict[HandlerKey, NormalizeHandler]:
    return {
        ("polar", "h10", "polar.hr"): PolarHrNormalizer(),
        ("polar", "h10", "polar.acc"): PolarAccNormalizer(),
        ("polar", "h10", "polar.ecg"): PolarEcgNormalizer(),
        ("polar", "h10", "polar.device_battery"): PolarDeviceBatteryNormalizer(),
        ("polar", "verity_sense", "polar.hr"): PolarHrNormalizer(),
        ("polar", "verity_sense", "polar.offline.hr"): PolarVerityOfflineNormalizer(StreamSpec(stream_type="hr", payload_schema="polar.offline.hr", time_field=None)),
        ("polar", "verity_sense", "polar.offline.ppi"): PolarVerityOfflineNormalizer(StreamSpec(stream_type="ppi", payload_schema="polar.offline.ppi", time_field="timeStamp")),
        ("polar", "verity_sense", "polar.offline.acc"): PolarVerityOfflineNormalizer(StreamSpec(stream_type="acc", payload_schema="polar.offline.acc", time_field="timeStamp")),
        ("polar", "verity_sense", "polar.offline.gyro"): PolarVerityOfflineNormalizer(StreamSpec(stream_type="gyro", payload_schema="polar.offline.gyro", time_field="timeStamp")),
        ("polar", "verity_sense", "polar.offline.mag"): PolarVerityOfflineNormalizer(StreamSpec(stream_type="mag", payload_schema="polar.offline.mag", time_field="timeStamp")),
        ("polar", "verity_sense", "polar.offline.ppg"): PolarVerityOfflineNormalizer(StreamSpec(stream_type="ppg", payload_schema="polar.offline.ppg", time_field="timeStamp")),
    }
