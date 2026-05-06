from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class BaseStreamPolicy:
    payload_schema: str
    stream_type: str
    report_confidence: str
    report_alignment_basis: str
    row_columns: list[str]
