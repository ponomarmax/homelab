from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter
from pydantic import BaseModel

from wearable_pipeline_api.models import PipelineRunResponse
from wearable_pipeline_api.config.settings import LEGACY_NORMALIZE_HR_PATH, PIPELINE_RUN_PATH
from wearable_pipeline_api.pipeline import SessionPipelineRunner


class PipelineRunRequest(BaseModel):
    session_id: str | None = None
    run_window_features: bool = True
    run_session_summary: bool = True


class PipelineTriggerRequest(BaseModel):
    session_id: str
    requested_steps: list[str] = ["normalize"]


def _parse_iso(value: str | None) -> datetime | None:
    if not value:
        return None
    normalized = value.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(normalized)
    except ValueError:
        return None


def _duration_seconds(start: datetime | None, end: datetime | None) -> float | None:
    if start is None or end is None:
        return None
    return max(0.0, (end - start).total_seconds())


def _collect_streams_for_session(raw_root: Path, session_id: str) -> dict[str, dict[str, object]]:
    streams: dict[str, dict[str, object]] = {}
    for chunk_file in raw_root.glob(f"**/session_id={session_id}/streams/*/chunks.jsonl"):
        if not chunk_file.is_file():
            continue
        stream = chunk_file.parent.name
        streams[stream] = {"raw_path": str(chunk_file), "present": True}
    return streams


def _load_summary_status(processed_root: Path, session_id: str) -> dict[str, object]:
    summary_paths = sorted(processed_root.glob(f"window_features/**/session_id={session_id}/session_summary.json"))
    if not summary_paths:
        return {"normalization_status": "unknown", "feature_status": "unknown", "summary_status": "missing", "artifacts": {}}
    payload = json.loads(summary_paths[-1].read_text(encoding="utf-8"))
    return {
        "normalization_status": "completed",
        "feature_status": "completed",
        "summary_status": payload.get("status", "unknown"),
        "artifacts": payload.get("artifact_paths", {}),
        "stream_summaries": payload.get("stream_summaries", {}),
    }


def _read_first_valid_jsonl(path: Path) -> dict[str, object] | None:
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            text = line.strip()
            if not text:
                continue
            try:
                item = json.loads(text)
            except json.JSONDecodeError:
                continue
            if isinstance(item, dict):
                return item
    return None


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

    @router.post("/api/v1/pipeline/trigger")
    async def trigger_pipeline(request: PipelineTriggerRequest) -> dict[str, object]:
        steps = [item.strip().lower() for item in request.requested_steps if item.strip()]
        supported = {"normalize", "window_features", "session_summary"}
        accepted_steps = [item for item in steps if item in supported]
        rejected_steps = [item for item in steps if item not in supported]
        if not accepted_steps:
            return {
                "accepted": False,
                "session_id": request.session_id,
                "requested_steps": steps,
                "accepted_steps": [],
                "rejected_steps": rejected_steps,
                "message": "No supported steps requested",
            }

        run_window_features = "window_features" in accepted_steps or "session_summary" in accepted_steps
        run_session_summary = "session_summary" in accepted_steps
        runner.run(
            session_id=request.session_id,
            run_window_features=run_window_features,
            run_session_summary=run_session_summary,
        )
        return {
            "accepted": True,
            "session_id": request.session_id,
            "requested_steps": steps,
            "accepted_steps": accepted_steps,
            "rejected_steps": rejected_steps,
            "message": "Pipeline trigger accepted",
            "dashboard_url": f"/api/v1/operator/sessions/{request.session_id}",
        }

    @router.get("/api/v1/operator/sessions")
    async def list_operator_sessions() -> dict[str, object]:
        sessions: dict[str, dict[str, object]] = {}
        for path in runner.raw_root.glob("**/session_id=*/streams/*/chunks.jsonl"):
            if not path.is_file():
                continue
            session_part = next((part for part in path.parts if part.startswith("session_id=")), "")
            if not session_part:
                continue
            session_id = session_part.split("=", 1)[1]
            payload = sessions.setdefault(
                session_id,
                {
                    "session_id": session_id,
                    "user_id": "unknown",
                    "device": "unknown",
                    "device_id": "unknown",
                    "collection_mode": "unknown",
                    "started_at": None,
                    "ended_at": None,
                    "duration": None,
                    "streams_present": [],
                    "raw_upload_status": "present",
                    "created_at": None,
                    "updated_at": None,
                },
            )
            payload["streams_present"] = sorted(set(payload["streams_present"] + [path.parent.name]))
            user_part = next((part for part in path.parts if part.startswith("user_id=")), "")
            if user_part:
                payload["user_id"] = user_part.split("=", 1)[1] or payload["user_id"]
            item = _read_first_valid_jsonl(path)
            if item is None:
                continue
            source = item.get("source") or {}
            payload["device"] = f"{source.get('vendor', 'unknown')}-{source.get('device_model', 'unknown')}"
            payload["device_id"] = str(source.get("device_id", payload["device_id"]))
            payload["collection_mode"] = ((item.get("collection") or {}).get("mode")) or payload["collection_mode"]
            t = item.get("time") or {}
            start = _parse_iso(t.get("recording_start_utc"))
            end = _parse_iso(t.get("recording_end_utc"))
            uploaded = _parse_iso(t.get("uploaded_at_collector"))
            started_at = _parse_iso(payload["started_at"]) if payload["started_at"] else None
            ended_at = _parse_iso(payload["ended_at"]) if payload["ended_at"] else None
            created_at = _parse_iso(payload["created_at"]) if payload["created_at"] else None
            updated_at = _parse_iso(payload["updated_at"]) if payload["updated_at"] else None

            if start and (started_at is None or start < started_at):
                payload["started_at"] = start.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
            if end and (ended_at is None or end > ended_at):
                payload["ended_at"] = end.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
            if uploaded and (created_at is None or uploaded < created_at):
                payload["created_at"] = uploaded.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
            if uploaded and (updated_at is None or uploaded > updated_at):
                payload["updated_at"] = uploaded.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")

        rows = []
        for session_id, payload in sessions.items():
            started = _parse_iso(payload["started_at"])
            ended = _parse_iso(payload["ended_at"])
            payload["duration"] = _duration_seconds(started, ended)
            payload.update(_load_summary_status(runner.processed_root, session_id))
            rows.append(payload)
        rows.sort(key=lambda item: str(item.get("updated_at") or ""), reverse=True)
        return {"sessions": rows}

    @router.get("/api/v1/operator/sessions/{session_id}")
    async def get_operator_session(session_id: str) -> dict[str, object]:
        streams = _collect_streams_for_session(runner.raw_root, session_id)
        summary = _load_summary_status(runner.processed_root, session_id)
        return {
            "session_id": session_id,
            "streams": streams,
            "raw_artifacts": [item["raw_path"] for item in streams.values()],
            "processed_artifacts": summary.get("artifacts", {}),
            "pipeline_run_status": {
                "normalization_status": summary.get("normalization_status"),
                "feature_status": summary.get("feature_status"),
                "summary_status": summary.get("summary_status"),
            },
            "stream_summaries": summary.get("stream_summaries", {}),
        }

    return router
