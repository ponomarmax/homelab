from __future__ import annotations

from fastapi import APIRouter

from wearable_pipeline_api.models import PipelineRunResponse
from wearable_pipeline_api.pipeline import SessionPipelineRunner


def build_router(runner: SessionPipelineRunner) -> APIRouter:
    router = APIRouter()

    @router.post("/api/v1/pipeline/normalize/hr", response_model=PipelineRunResponse)
    async def normalize_hr() -> dict[str, object]:
        return runner.run()

    return router
