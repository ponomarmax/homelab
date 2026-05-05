from __future__ import annotations

from pathlib import Path
from typing import Protocol

from .acc import AccSummaryHandler
from .device_battery import DeviceBatterySummaryHandler
from .ecg import EcgSummaryHandler
from .hr import HrSummaryHandler, HrSummaryOutput


class SessionSummaryHandler(Protocol):
    name: str
    stream_type: str

    def handle(self, window_feature_paths: list[Path], generated_summary_path: str) -> HrSummaryOutput:
        pass


def session_summary_handler_registry() -> dict[str, SessionSummaryHandler]:
    return {
        "acc": AccSummaryHandler(),
        "battery": DeviceBatterySummaryHandler(),
        "ecg": EcgSummaryHandler(),
        "hr": HrSummaryHandler(),
    }
