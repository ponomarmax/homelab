from __future__ import annotations

from pathlib import Path

from ..common import PolarVerityOfflineNormalizer, StreamSpec
from .policies import GYRO_POLICY
from ....common.base import NormalizeHandlerOutput


class VeritySenseOfflineGyroNormalizer:
    name = "VeritySenseOfflineGyroNormalizer"

    def __init__(self) -> None:
        self._handler = PolarVerityOfflineNormalizer(
            StreamSpec(stream_type="gyro", payload_schema="polar.offline.gyro", time_field="timeStamp"),
            policy=GYRO_POLICY,
        )

    def handle(self, raw_path: Path) -> NormalizeHandlerOutput:
        return self._handler.handle(raw_path)
