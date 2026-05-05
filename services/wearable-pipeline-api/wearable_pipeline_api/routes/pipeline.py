from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel

from wearable_pipeline_api.models import PipelineRunResponse
from wearable_pipeline_api.config.settings import LEGACY_NORMALIZE_HR_PATH, PIPELINE_RUN_PATH
from wearable_pipeline_api.pipeline import SessionPipelineRunner


class PipelineRunRequest(BaseModel):
    session_id: str | None = None
    run_window_features: bool = True
    run_session_summary: bool = True


def build_router(runner: SessionPipelineRunner) -> APIRouter:
    router = APIRouter()

    @router.post(PIPELINE_RUN_PATH, response_model=PipelineRunResponse)
    async def run_pipeline(request: PipelineRunRequest | None = None) -> dict[str, object]:
        selected_session_id = str(request.session_id).strip() if request and request.session_id is not None else None
        if selected_session_id == "":
            selected_session_id = None
        run_window_features = bool(request.run_window_features) if request else True
        run_session_summary = bool(request.run_session_summary) if request else True
        if not run_window_features:
            run_session_summary = False
        return runner.run(
            session_id=selected_session_id,
            run_window_features=run_window_features,
            run_session_summary=run_session_summary,
        )

    @router.post(LEGACY_NORMALIZE_HR_PATH, response_model=PipelineRunResponse)
    async def normalize_hr_legacy_alias(request: PipelineRunRequest | None = None) -> dict[str, object]:
        selected_session_id = str(request.session_id).strip() if request and request.session_id is not None else None
        if selected_session_id == "":
            selected_session_id = None
        run_window_features = bool(request.run_window_features) if request else True
        run_session_summary = bool(request.run_session_summary) if request else True
        if not run_window_features:
            run_session_summary = False
        return runner.run(
            session_id=selected_session_id,
            run_window_features=run_window_features,
            run_session_summary=run_session_summary,
        )

    return router
