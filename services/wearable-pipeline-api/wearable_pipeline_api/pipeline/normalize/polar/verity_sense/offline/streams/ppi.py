from __future__ import annotations

from pathlib import Path

from ..common import PolarVerityOfflineNormalizer, StreamSpec
from .policies import PPI_POLICY
from ....common.base import NormalizeHandlerOutput


class VeritySenseOfflinePpiNormalizer:
    name = "VeritySenseOfflinePpiNormalizer"

    def __init__(self) -> None:
        self._handler = PolarVerityOfflineNormalizer(
            StreamSpec(stream_type="ppi", payload_schema="polar.offline.ppi", time_field="timeStamp"),
            policy=PPI_POLICY,
        )

    def handle(self, raw_path: Path) -> NormalizeHandlerOutput:
        return self._handler.handle(raw_path)
