from __future__ import annotations

from pathlib import Path
from typing import Any

from wearable_pipeline_api.pipeline.common import discover_session_streams
from wearable_pipeline_api.pipeline.features import WindowFeaturesStepRunner
from wearable_pipeline_api.pipeline.normalize import NormalizeStepRunner
from wearable_pipeline_api.pipeline.state import RunStateStore
from wearable_pipeline_api.pipeline.summary import SessionSummaryStepRunner


class SessionPipelineRunner:
    def __init__(self, raw_root: Path, processed_root: Path, state_root: Path) -> None:
        self.raw_root = raw_root
        self.processed_root = processed_root
        self.state_store = RunStateStore(state_root)
        self.normalize_step = NormalizeStepRunner(raw_root=raw_root, processed_root=processed_root, state_store=self.state_store)
        self.window_features_step = WindowFeaturesStepRunner(
            raw_root=raw_root,
            processed_root=processed_root,
            state_store=self.state_store,
        )
        self.session_summary_step = SessionSummaryStepRunner(
            processed_root=processed_root,
            state_store=self.state_store,
        )

    def run(self) -> dict[str, Any]:
        sessions = discover_session_streams(self.raw_root)
        normalize_runs: list[dict[str, Any]] = []
        window_feature_runs: list[dict[str, Any]] = []
        session_summary_runs: list[dict[str, Any]] = []

        for session_id, streams in sorted(sessions.items()):
            normalize_result = self.normalize_step.run_for_session(session_id=session_id, streams=streams)
            normalize_runs.append(normalize_result)

            feature_result = self.window_features_step.run_for_session(
                session_id=session_id,
                normalize_step_result=normalize_result,
            )
            window_feature_runs.append(feature_result)
            summary_result = self.session_summary_step.run_for_session(
                session_id=session_id,
                window_feature_step_result=feature_result,
            )
            session_summary_runs.append(summary_result)

        return {
            "sessions_discovered": len(sessions),
            "normalize_runs": normalize_runs,
            "window_feature_runs": window_feature_runs,
            "session_summary_runs": session_summary_runs,
        }


# Backward-compatible alias for previous imports.
HrPipelineRunner = SessionPipelineRunner
