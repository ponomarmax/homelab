from __future__ import annotations

from pydantic import BaseModel


class StreamResult(BaseModel):
    stream_type: str
    handler_name: str
    status: str
    input_path: str
    output_path: str | None
    error: str | None = None


class StepRun(BaseModel):
    run_id: str
    status: str
    session_id: str
    step_name: str
    state_path: str
    discovered_streams: list[str]
    per_stream_results: list[StreamResult]
    warnings: list[str]


class PipelineRunResponse(BaseModel):
    sessions_discovered: int
    normalize_runs: list[StepRun]
    window_feature_runs: list[StepRun]
    session_summary_runs: list[StepRun]
