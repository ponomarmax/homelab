from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import pandas as pd

from wearable_pipeline_api.pipeline.common import StepRunRecord, StreamRunResult
from wearable_pipeline_api.pipeline.state import RunStateStore, utc_now_iso
from wearable_pipeline_api.storage import derive_window_feature_path

from .registry import FeatureHandler, feature_handler_registry

logger = logging.getLogger(__name__)


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


class WindowFeaturesStepRunner:
    step_name = "window_features"

    def __init__(self, raw_root: Path, processed_root: Path, state_store: RunStateStore) -> None:
        self.raw_root = raw_root
        self.processed_root = processed_root
        self.state_store = state_store
        self.registry = feature_handler_registry()

    def _select_handler(self, vendor: str, device_model: str, stream_type: str) -> FeatureHandler | None:
        key = (vendor.lower(), device_model.lower(), stream_type.lower())
        return self.registry.get(key)

    def run_for_session(self, session_id: str, normalize_step_result: dict[str, Any]) -> dict[str, Any]:
        run_id = self.state_store.new_run_id()
        started_at = utc_now_iso()
        warnings: list[str] = []
        per_stream_results: list[StreamRunResult] = []

        for stream_result in normalize_step_result.get("per_stream_results", []):
            status = stream_result.get("status")
            stream_type = str(stream_result.get("stream_type") or "")
            input_path = stream_result.get("output_path")

            if status != "success" or not input_path:
                continue

            clean_path = Path(str(input_path))
            if not clean_path.exists():
                per_stream_results.append(
                    StreamRunResult(
                        stream_type=stream_type,
                        handler_name="HrWindowFeatureBuilder",
                        status="failed",
                        input_path=str(clean_path),
                        output_path=None,
                        error="missing normalized artifact",
                    )
                )
                continue

            clean_df = pd.read_parquet(clean_path)
            if clean_df.empty:
                warning = f"empty clean stream: {clean_path}"
                warnings.append(warning)
                per_stream_results.append(
                    StreamRunResult(
                        stream_type=stream_type,
                        handler_name="HrWindowFeatureBuilder",
                        status="skipped",
                        input_path=str(clean_path),
                        output_path=None,
                        error=warning,
                    )
                )
                continue

            first = clean_df.iloc[0]
            vendor = str(first.get("source_vendor") or "").strip().lower()
            device_model = str(first.get("source_device_model") or "").strip().lower()
            stream_type = str(first.get("stream_type") or stream_type).strip().lower()
            handler = self._select_handler(vendor, device_model, stream_type)
            if handler is None:
                warning = (
                    f"unsupported feature stream: session_id={session_id} stream_type={stream_type} "
                    f"vendor={vendor or 'unknown'} device_model={device_model or 'unknown'}"
                )
                warnings.append(warning)
                per_stream_results.append(
                    StreamRunResult(
                        stream_type=stream_type,
                        handler_name="unsupported",
                        status="skipped",
                        input_path=str(clean_path),
                        output_path=None,
                        error=warning,
                    )
                )
                continue

            try:
                raw_path = Path(str(stream_result.get("input_path") or ""))
                output_path = derive_window_feature_path(raw_path, self.raw_root, self.processed_root)
                features = handler.handle(clean_df, run_id=run_id, input_artifact_reference=str(clean_path))
                output_path.parent.mkdir(parents=True, exist_ok=True)
                features.dataframe.to_parquet(output_path, index=False)
                per_stream_results.append(
                    StreamRunResult(
                        stream_type=stream_type,
                        handler_name=handler.name,
                        status="success",
                        input_path=str(clean_path),
                        output_path=str(output_path),
                    )
                )
            except Exception as exc:  # pragma: no cover - safeguarded by integration tests
                logger.exception("window_features_stream_failed", extra={"clean_path": str(clean_path)})
                per_stream_results.append(
                    StreamRunResult(
                        stream_type=stream_type,
                        handler_name=handler.name,
                        status="failed",
                        input_path=str(clean_path),
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
            discovered_streams=sorted({str(item.get("stream_type") or "") for item in normalize_step_result.get("per_stream_results", []) if str(item.get("stream_type") or "")}),
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
