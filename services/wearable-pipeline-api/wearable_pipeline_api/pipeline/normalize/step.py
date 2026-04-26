from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

from wearable_pipeline_api.pipeline.common import StepRunRecord, StreamContext, StreamRunResult
from wearable_pipeline_api.pipeline.state import RunStateStore, utc_now_iso
from wearable_pipeline_api.storage import derive_artifact_paths

from .registry import NormalizeHandler, normalize_handler_registry

logger = logging.getLogger(__name__)


def _select_handler(
    registry: dict[tuple[str, str, str], NormalizeHandler], stream: StreamContext
) -> NormalizeHandler | None:
    key = (stream.source_vendor.lower(), stream.device_model.lower(), stream.stream_type.lower())
    return registry.get(key)


def _status_from_results(results: list[StreamRunResult]) -> str:
    if not results:
        return "failed"
    has_failed = any(item.status == "failed" for item in results)
    has_success = any(item.status == "success" for item in results)
    has_skipped = any(item.status == "skipped" for item in results)
    if has_failed and has_success:
        return "partial"
    if has_failed:
        return "failed"
    if has_skipped and not has_success:
        return "partial"
    return "success"


class NormalizeStepRunner:
    step_name = "normalize"

    def __init__(self, raw_root: Path, processed_root: Path, state_store: RunStateStore) -> None:
        self.raw_root = raw_root
        self.processed_root = processed_root
        self.state_store = state_store
        self.registry = normalize_handler_registry()

    def run_for_session(self, session_id: str, streams: list[StreamContext]) -> dict[str, Any]:
        run_id = self.state_store.new_run_id()
        started_at = utc_now_iso()
        warnings: list[str] = []
        per_stream_results: list[StreamRunResult] = []

        for stream in sorted(streams, key=lambda item: item.stream_type):
            raw_path = Path(stream.raw_path)
            output_path, report_path = derive_artifact_paths(raw_path, self.raw_root, self.processed_root)
            handler = _select_handler(self.registry, stream)
            if handler is None:
                warning = (
                    f"unsupported stream: session_id={stream.session_id} stream_type={stream.stream_type} "
                    f"vendor={stream.source_vendor or 'unknown'} device_model={stream.device_model or 'unknown'}"
                )
                warnings.append(warning)
                per_stream_results.append(
                    StreamRunResult(
                        stream_type=stream.stream_type,
                        handler_name="unsupported",
                        status="skipped",
                        input_path=str(raw_path),
                        output_path=None,
                        error=warning,
                    )
                )
                continue

            try:
                result = handler.handle(raw_path)
                output_path.parent.mkdir(parents=True, exist_ok=True)
                result.dataframe.to_parquet(output_path, index=False)
                report_path.write_text(json.dumps(result.report, indent=2), encoding="utf-8")
                warnings.extend(result.warnings)
                per_stream_results.append(
                    StreamRunResult(
                        stream_type=stream.stream_type,
                        handler_name=handler.name,
                        status="success",
                        input_path=str(raw_path),
                        output_path=str(output_path),
                    )
                )
            except Exception as exc:  # pragma: no cover - safeguarded by integration tests
                logger.exception("normalize_stream_failed", extra={"raw_path": str(raw_path)})
                per_stream_results.append(
                    StreamRunResult(
                        stream_type=stream.stream_type,
                        handler_name=handler.name,
                        status="failed",
                        input_path=str(raw_path),
                        output_path=None,
                        error=str(exc),
                    )
                )

        finished_at = utc_now_iso()
        run_record = StepRunRecord(
            run_id=run_id,
            step_name=self.step_name,
            session_id=session_id,
            started_at_utc=started_at,
            finished_at_utc=finished_at,
            status=_status_from_results(per_stream_results),
            discovered_streams=sorted({stream.stream_type for stream in streams}),
            per_stream_results=[item.as_dict() for item in per_stream_results],
            warnings=warnings,
        )
        state_path = self.state_store.write(run_record)
        return {
            "run_id": run_record.run_id,
            "status": run_record.status,
            "session_id": session_id,
            "step_name": self.step_name,
            "state_path": str(state_path),
            "discovered_streams": run_record.discovered_streams,
            "per_stream_results": run_record.per_stream_results,
            "warnings": warnings,
        }
