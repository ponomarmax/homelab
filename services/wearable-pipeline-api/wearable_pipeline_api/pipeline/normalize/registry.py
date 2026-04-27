from __future__ import annotations

from pathlib import Path
from typing import Protocol

from .acc import PolarAccNormalizer
from .base import NormalizeHandlerOutput
from .device_battery import PolarDeviceBatteryNormalizer
from .ecg import PolarEcgNormalizer
from .hr import PolarHrNormalizer


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
    }
