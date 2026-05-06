from __future__ import annotations

from pathlib import Path

from ..common import PolarVerityOfflineNormalizer, StreamSpec
from .policies import MAG_POLICY
from ....common.base import NormalizeHandlerOutput


class VeritySenseOfflineMagNormalizer:
    name = "VeritySenseOfflineMagNormalizer"

    def __init__(self) -> None:
        self._handler = PolarVerityOfflineNormalizer(
            StreamSpec(stream_type="mag", payload_schema="polar.offline.mag", time_field="timeStamp"),
            policy=MAG_POLICY,
        )

    def handle(self, raw_path: Path) -> NormalizeHandlerOutput:
        return self._handler.handle(raw_path)
