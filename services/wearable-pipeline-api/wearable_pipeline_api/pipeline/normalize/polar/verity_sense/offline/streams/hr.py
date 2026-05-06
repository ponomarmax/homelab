from __future__ import annotations

from pathlib import Path

from ..common import PolarVerityOfflineNormalizer, StreamSpec
from .policies import HR_POLICY
from ....common.base import NormalizeHandlerOutput


class VeritySenseOfflineHrNormalizer:
    name = "VeritySenseOfflineHrNormalizer"

    def __init__(self) -> None:
        self._handler = PolarVerityOfflineNormalizer(
            StreamSpec(stream_type="hr", payload_schema="polar.offline.hr", time_field=None),
            policy=HR_POLICY,
        )

    def handle(self, raw_path: Path) -> NormalizeHandlerOutput:
        return self._handler.handle(raw_path)
