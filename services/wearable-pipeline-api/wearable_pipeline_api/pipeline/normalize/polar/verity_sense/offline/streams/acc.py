from __future__ import annotations

from pathlib import Path

from ..common import PolarVerityOfflineNormalizer, StreamSpec
from .policies import ACC_POLICY
from ....common.base import NormalizeHandlerOutput


class VeritySenseOfflineAccNormalizer:
    name = "VeritySenseOfflineAccNormalizer"

    def __init__(self) -> None:
        self._handler = PolarVerityOfflineNormalizer(
            StreamSpec(stream_type="acc", payload_schema="polar.offline.acc", time_field="timeStamp"),
            policy=ACC_POLICY,
        )

    def handle(self, raw_path: Path) -> NormalizeHandlerOutput:
        return self._handler.handle(raw_path)
