from __future__ import annotations

from typing import Any


def flatten_pipeline_response(response: dict[str, Any]) -> list[dict[str, Any]]:
    runs: list[dict[str, Any]] = []
    runs.extend(response.get("normalize_runs", []) or [])
    runs.extend(response.get("window_feature_runs", []) or [])
    runs.extend(response.get("session_summary_runs", []) or [])
    return [run for run in runs if isinstance(run, dict)]


def filter_runs_for_session(runs: list[dict[str, Any]], session_id: str) -> list[dict[str, Any]]:
    return [run for run in runs if str(run.get("session_id", "")) == str(session_id)]


def summarize_run(run: dict[str, Any]) -> dict[str, Any]:
    per_stream = run.get("per_stream_results", []) or []
    success = 0
    skipped = 0
    failed = 0

    statuses: list[str] = []
    for item in per_stream:
        if not isinstance(item, dict):
            continue
        status = str(item.get("status", "")).lower()
        stream = str(item.get("stream_type", "unknown"))
        statuses.append(f"{stream}:{status}")
        if status == "success":
            success += 1
        elif status == "skipped":
            skipped += 1
        elif status == "failed":
            failed += 1

    return {
        "run_id": str(run.get("run_id", "")),
        "step_name": str(run.get("step_name", "unknown")),
        "status": str(run.get("status", "unknown")),
        "session_id": str(run.get("session_id", "")),
        "stream_success": success,
        "stream_skipped": skipped,
        "stream_failed": failed,
        "stream_statuses": statuses,
        "warnings": run.get("warnings", []) or [],
        "state_path": str(run.get("state_path", "")),
    }


def format_run_line(summary: dict[str, Any]) -> str:
    step = summary.get("step_name", "unknown")
    status = summary.get("status", "unknown")
    ok_count = summary.get("stream_success", 0)
    skip_count = summary.get("stream_skipped", 0)
    fail_count = summary.get("stream_failed", 0)
    return f"[{step}] status={status} streams: success={ok_count} skipped={skip_count} failed={fail_count}"


def summarize_pipeline_for_session(response: dict[str, Any], session_id: str) -> list[dict[str, Any]]:
    runs = flatten_pipeline_response(response)
    session_runs = filter_runs_for_session(runs, session_id=session_id)
    return [summarize_run(run) for run in session_runs]
