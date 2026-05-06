from __future__ import annotations

from pathlib import Path
from typing import Protocol

from .polar.common.base import NormalizeHandlerOutput
from .polar.common.online.hr import PolarHrNormalizer
from .polar.h10.online.acc import PolarAccNormalizer
from .polar.h10.online.device_battery import PolarDeviceBatteryNormalizer
from .polar.h10.online.ecg import PolarEcgNormalizer
from .polar.verity_sense.offline.streams.acc import VeritySenseOfflineAccNormalizer
from .polar.verity_sense.offline.streams.gyro import VeritySenseOfflineGyroNormalizer
from .polar.verity_sense.offline.streams.hr import VeritySenseOfflineHrNormalizer
from .polar.verity_sense.offline.streams.mag import VeritySenseOfflineMagNormalizer
from .polar.verity_sense.offline.streams.ppg import VeritySenseOfflinePpgNormalizer
from .polar.verity_sense.offline.streams.ppi import VeritySenseOfflinePpiNormalizer
from .polar.verity_sense.online.streams import VeritySenseOnlinePpiNormalizer


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
        ("polar", "verity_sense", "polar.ppi"): VeritySenseOnlinePpiNormalizer(),
        ("polar", "verity_sense", "polar.offline.hr"): VeritySenseOfflineHrNormalizer(),
        ("polar", "verity_sense", "polar.offline.ppi"): VeritySenseOfflinePpiNormalizer(),
        ("polar", "verity_sense", "polar.offline.acc"): VeritySenseOfflineAccNormalizer(),
        ("polar", "verity_sense", "polar.offline.gyro"): VeritySenseOfflineGyroNormalizer(),
        ("polar", "verity_sense", "polar.offline.mag"): VeritySenseOfflineMagNormalizer(),
        ("polar", "verity_sense", "polar.offline.ppg"): VeritySenseOfflinePpgNormalizer(),
    }
