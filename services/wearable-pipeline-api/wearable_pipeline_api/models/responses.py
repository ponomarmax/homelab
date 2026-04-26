from __future__ import annotations

from pydantic import BaseModel


class ArtifactStatus(BaseModel):
    raw_path: str
    output_path: str
    report_path: str
    status: str


class NormalizeHrResponse(BaseModel):
    discovered: int
    skipped: int
    processed: int
    failed: int
    artifacts: list[ArtifactStatus]
