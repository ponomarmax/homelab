from __future__ import annotations

from fastapi import APIRouter

from wearable_pipeline_api.models import NormalizeHrResponse
from wearable_pipeline_api.pipeline import HrPipelineRunner


def build_router(runner: HrPipelineRunner) -> APIRouter:
    router = APIRouter()

    @router.post("/api/v1/pipeline/normalize/hr", response_model=NormalizeHrResponse)
    async def normalize_hr() -> dict[str, object]:
        return runner.run()

    return router
