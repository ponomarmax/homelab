from __future__ import annotations

from pathlib import Path

from ..common import PolarVerityOfflineNormalizer, StreamSpec
from .policies import PPG_POLICY
from ....common.base import NormalizeHandlerOutput


class VeritySenseOfflinePpgNormalizer:
    name = "VeritySenseOfflinePpgNormalizer"

    def __init__(self) -> None:
        self._handler = PolarVerityOfflineNormalizer(
            StreamSpec(stream_type="ppg", payload_schema="polar.offline.ppg", time_field="timeStamp"),
            policy=PPG_POLICY,
        )

    def handle(self, raw_path: Path) -> NormalizeHandlerOutput:
        return self._handler.handle(raw_path)
