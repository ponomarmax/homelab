from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

from wearable_pipeline_api.pipeline.common import StepRunRecord, StreamRunResult
from wearable_pipeline_api.pipeline.state import RunStateStore, utc_now_iso

from .registry import session_summary_handler_registry

logger = logging.getLogger(__name__)


def _session_status_from_results(results: list[StreamRunResult]) -> str:
    if not results:
        return "failed"
    statuses = {item.status for item in results}
    if "failed" in statuses:
        return "failed"
    if statuses == {"success"}:
        return "success"
    return "partial"


def _session_dir_from_feature_path(path: Path) -> Path | None:
    for parent in path.parents:
        if parent.name.startswith("session_id="):
            return parent
    return None


class SessionSummaryStepRunner:
    step_name = "build_session_summary"

    def __init__(self, processed_root: Path, state_store: RunStateStore) -> None:
        self.processed_root = processed_root
        self.state_store = state_store
        self.registry = session_summary_handler_registry()

    def _discover_feature_paths(self, session_id: str) -> list[Path]:
        pattern = f"window_features/**/session_id={session_id}/streams/*/data.parquet"
        return sorted(path for path in self.processed_root.glob(pattern) if path.is_file())

    def _feature_paths_from_previous_step(self, window_feature_step_result: dict[str, Any]) -> list[Path]:
        paths: list[Path] = []
        for result in window_feature_step_result.get("per_stream_results", []):
            output_path = str(result.get("output_path") or "").strip()
            if not output_path:
                continue
            paths.append(Path(output_path))
        return sorted(paths)

    def run_for_session(
        self,
        session_id: str,
        window_feature_step_result: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        run_id = self.state_store.new_run_id()
        started_at = utc_now_iso()
        logger.info("session_summary_step_started", extra={"session_id": session_id, "run_id": run_id})

        if window_feature_step_result is None:
            feature_paths = self._discover_feature_paths(session_id=session_id)
        else:
            feature_paths = self._feature_paths_from_previous_step(window_feature_step_result)
            if not feature_paths:
                feature_paths = self._discover_feature_paths(session_id=session_id)

        session_dir = None
        for path in feature_paths:
            session_dir = _session_dir_from_feature_path(path)
            if session_dir is not None:
                break
        if session_dir is None:
            session_dir = self.processed_root / "window_features" / f"session_id={session_id}"
        session_dir.mkdir(parents=True, exist_ok=True)
        summary_path = session_dir / "session_summary.json"

        stream_warnings: list[str] = []
        per_stream_results: list[StreamRunResult] = []
        summary_streams: dict[str, Any] = {}
        available_window_sizes: set[str] = set()
        input_paths = sorted(str(path) for path in feature_paths)

        for stream_type, handler in sorted(self.registry.items()):
            stream_paths = [path for path in feature_paths if path.parent.name == stream_type]
            if not stream_paths:
                warning = f"missing input stream for summary: {stream_type}"
                logger.warning("session_summary_stream_missing", extra={"session_id": session_id, "stream_type": stream_type})
                stream_warnings.append(warning)
            output = handler.handle(window_feature_paths=stream_paths, generated_summary_path=str(summary_path))
            available_window_sizes.update(output.available_window_sizes)
            stream_warnings.extend(output.warnings)
            summary_streams[stream_type] = output.stream_summary
            per_stream_results.append(
                StreamRunResult(
                    stream_type=stream_type,
                    handler_name=handler.name,
                    status=output.status,
                    input_path=str(stream_paths[0]) if stream_paths else "",
                    output_path=str(summary_path),
                    error=None,
                )
            )

        overall_quality = "unknown"
        if summary_streams:
            quality_values = [str(stream.get("data_quality", {}).get("status") or "unknown") for stream in summary_streams.values()]
            if any(item == "poor" for item in quality_values):
                overall_quality = "poor"
            elif any(item == "partial" for item in quality_values):
                overall_quality = "partial"
            elif all(item == "good" for item in quality_values):
                overall_quality = "good"
            else:
                overall_quality = "unknown"

        summary_payload = {
            "schema_version": "1.0",
            "generated_at_utc": utc_now_iso(),
            "session_id": session_id,
            "inputs": {
                "window_feature_paths": input_paths,
                "available_window_sizes": sorted(available_window_sizes, key=lambda value: ("30s", "1m", "5m").index(value) if value in ("30s", "1m", "5m") else 99),
            },
            "streams": summary_streams,
            "overall_quality": overall_quality,
        }
        summary_path.write_text(json.dumps(summary_payload, indent=2), encoding="utf-8")

        finished_at = utc_now_iso()
        run_record = StepRunRecord(
            run_id=run_id,
            step_name=self.step_name,
            session_id=session_id,
            started_at_utc=started_at,
            finished_at_utc=finished_at,
            status=_session_status_from_results(per_stream_results),
            discovered_streams=sorted(self.registry.keys()),
            per_stream_results=[item.as_dict() for item in per_stream_results],
            warnings=stream_warnings,
        )
        state_path = self.state_store.write(run_record)
        logger.info(
            "session_summary_step_finished",
            extra={
                "session_id": session_id,
                "run_id": run_id,
                "status": run_record.status,
                "processed_streams": len(per_stream_results),
                "summary_path": str(summary_path),
            },
        )
        return {
            "run_id": run_record.run_id,
            "status": run_record.status,
            "session_id": session_id,
            "step_name": self.step_name,
            "state_path": str(state_path),
            "discovered_streams": run_record.discovered_streams,
            "per_stream_results": run_record.per_stream_results,
            "warnings": stream_warnings,
        }
