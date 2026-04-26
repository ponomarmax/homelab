from __future__ import annotations

from pathlib import Path
from typing import Protocol

from .hr import HrSummaryHandler, HrSummaryOutput


class SessionSummaryHandler(Protocol):
    name: str
    stream_type: str

    def handle(self, window_feature_paths: list[Path], generated_summary_path: str) -> HrSummaryOutput:
        pass


def session_summary_handler_registry() -> dict[str, SessionSummaryHandler]:
    return {
        "hr": HrSummaryHandler(),
    }
