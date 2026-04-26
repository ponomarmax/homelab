from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any


@dataclass(frozen=True)
class StreamContext:
    session_id: str
    stream_type: str
    raw_path: str
    user_id: str
    source: str
    source_vendor: str
    device_model: str


@dataclass
class StreamRunResult:
    stream_type: str
    handler_name: str
    status: str
    input_path: str
    output_path: str | None
    error: str | None = None

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class StepRunRecord:
    run_id: str
    step_name: str
    session_id: str
    started_at_utc: str
    finished_at_utc: str
    status: str
    discovered_streams: list[str]
    per_stream_results: list[dict[str, Any]]
    warnings: list[str]

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class PipelineRunSummary:
    normalize: dict[str, Any]
    window_features: dict[str, Any]
