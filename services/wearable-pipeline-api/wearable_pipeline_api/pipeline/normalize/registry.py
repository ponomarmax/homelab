from __future__ import annotations

from pathlib import Path
from typing import Protocol

from .hr import NormalizeHandlerOutput, PolarHrNormalizer


class NormalizeHandler(Protocol):
    name: str

    def handle(self, raw_path: Path) -> NormalizeHandlerOutput:
        pass


HandlerKey = tuple[str, str, str]


def normalize_handler_registry() -> dict[HandlerKey, NormalizeHandler]:
    return {
        ("polar", "verity_sense", "hr"): PolarHrNormalizer(),
    }
