from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel

from wearable_pipeline_api.models import PipelineRunResponse
from wearable_pipeline_api.config.settings import LEGACY_NORMALIZE_HR_PATH, PIPELINE_RUN_PATH
from wearable_pipeline_api.pipeline import SessionPipelineRunner


class PipelineRunRequest(BaseModel):
    session_id: str | None = None


def build_router(runner: SessionPipelineRunner) -> APIRouter:
    router = APIRouter()

    @router.post(PIPELINE_RUN_PATH, response_model=PipelineRunResponse)
    async def run_pipeline(request: PipelineRunRequest | None = None) -> dict[str, object]:
        selected_session_id = str(request.session_id).strip() if request and request.session_id is not None else None
        if selected_session_id == "":
            selected_session_id = None
        return runner.run(session_id=selected_session_id)

    @router.post(LEGACY_NORMALIZE_HR_PATH, response_model=PipelineRunResponse)
    async def normalize_hr_legacy_alias(request: PipelineRunRequest | None = None) -> dict[str, object]:
        selected_session_id = str(request.session_id).strip() if request and request.session_id is not None else None
        if selected_session_id == "":
            selected_session_id = None
        return runner.run(session_id=selected_session_id)

    return router
