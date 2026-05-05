from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

from wearable_pipeline_api.pipeline.common import StepRunRecord, StreamContext, StreamRunResult, canonicalize_device_model
from wearable_pipeline_api.pipeline.state import RunStateStore, utc_now_iso
from wearable_pipeline_api.storage import derive_artifact_paths

from .registry import NormalizeHandler, normalize_handler_registry

logger = logging.getLogger(__name__)


def _select_handler(
    registry: dict[tuple[str, str, str], NormalizeHandler], stream: StreamContext
) -> NormalizeHandler | None:
    key = (
        stream.source_vendor.lower(),
        canonicalize_device_model(stream.device_model),
        stream.payload_schema.lower(),
    )
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

    def __init__(
        self,
        raw_root: Path,
        processed_root: Path,
        state_store: RunStateStore,
        *,
        l0_cross_stream_max_start_delta_seconds: float,
        l0_cross_stream_max_end_delta_seconds: float,
        l0_cross_stream_min_overlap_ratio: float,
        l0_cross_stream_min_anchor_streams: int,
        l0_cross_stream_anchor_streams: tuple[str, ...],
    ) -> None:
        self.raw_root = raw_root
        self.processed_root = processed_root
        self.state_store = state_store
        self.registry = normalize_handler_registry()
        self.l0_cross_stream_max_start_delta_seconds = l0_cross_stream_max_start_delta_seconds
        self.l0_cross_stream_max_end_delta_seconds = l0_cross_stream_max_end_delta_seconds
        self.l0_cross_stream_min_overlap_ratio = l0_cross_stream_min_overlap_ratio
        self.l0_cross_stream_min_anchor_streams = l0_cross_stream_min_anchor_streams
        self.l0_cross_stream_anchor_streams = set(l0_cross_stream_anchor_streams)

    @staticmethod
    def _parse_utc(value: Any):
        if not value:
            return None
        try:
            import pandas as pd

            ts = pd.to_datetime(value, utc=True, errors="coerce")
            if pd.isna(ts):
                return None
            if hasattr(ts, "to_pydatetime"):
                try:
                    return ts.to_pydatetime(warn=False)
                except TypeError:
                    return ts.to_pydatetime()
            return ts
        except Exception:
            return None

    @staticmethod
    def _degrade_confidence(value: str) -> str:
        levels = ["low", "medium", "high"]
        if value not in levels:
            return "low"
        idx = max(levels.index(value) - 1, 0)
        return levels[idx]

    def _apply_l0_cross_stream_gate(
        self,
        reports_by_stream: dict[str, dict[str, Any]],
    ) -> list[str]:
        anchor_windows: list[tuple[Any, Any]] = []
        for stream_type, report in reports_by_stream.items():
            if stream_type not in self.l0_cross_stream_anchor_streams:
                continue
            if report.get("alignment_basis_level") != "L0":
                continue
            start = self._parse_utc(report.get("session_window_start") or (report.get("normalized_time_range") or {}).get("start_utc"))
            end = self._parse_utc(report.get("session_window_end") or (report.get("normalized_time_range") or {}).get("end_utc"))
            if start is None or end is None or end <= start:
                continue
            anchor_windows.append((start, end))

        if len(anchor_windows) < self.l0_cross_stream_min_anchor_streams:
            return []

        anchor_start = min(item[0] for item in anchor_windows)
        anchor_end = max(item[1] for item in anchor_windows)
        warnings: list[str] = []

        for stream_type, report in reports_by_stream.items():
            if report.get("alignment_basis_level") != "L0":
                continue
            stream_start = self._parse_utc(report.get("session_window_start") or (report.get("normalized_time_range") or {}).get("start_utc"))
            stream_end = self._parse_utc(report.get("session_window_end") or (report.get("normalized_time_range") or {}).get("end_utc"))
            if stream_start is None or stream_end is None or stream_end <= stream_start:
                continue

            start_delta = abs((stream_start - anchor_start).total_seconds())
            end_delta = abs((stream_end - anchor_end).total_seconds())
            overlap_start = max(stream_start, anchor_start)
            overlap_end = min(stream_end, anchor_end)
            overlap_seconds = max((overlap_end - overlap_start).total_seconds(), 0.0)
            stream_duration = max((stream_end - stream_start).total_seconds(), 1e-9)
            overlap_ratio = overlap_seconds / stream_duration

            if (
                start_delta <= self.l0_cross_stream_max_start_delta_seconds
                and end_delta <= self.l0_cross_stream_max_end_delta_seconds
                and overlap_ratio >= self.l0_cross_stream_min_overlap_ratio
            ):
                continue

            report["alignment_basis_level"] = "L2"
            report["alignment_basis"] = "cross_stream_anchoring"
            report["epoch_offset_decision"] = "l0_cross_stream_inconsistent"
            report["confidence"] = self._degrade_confidence(str(report.get("confidence") or "low"))
            details = report.get("alignment_basis_details")
            if not isinstance(details, dict):
                details = {}
            details["selected_source"] = "cross_stream_anchoring"
            details["selected_reason"] = "l0_cross_stream_inconsistent"
            details["anchor_streams"] = sorted(self.l0_cross_stream_anchor_streams)
            details["start_delta_seconds"] = round(start_delta, 3)
            details["end_delta_seconds"] = round(end_delta, 3)
            details["overlap_ratio"] = round(overlap_ratio, 4)
            report["alignment_basis_details"] = details
            report.setdefault("warnings", [])
            if "l0_cross_stream_inconsistent" not in report["warnings"]:
                report["warnings"].append("l0_cross_stream_inconsistent")
            warnings.append(f"stream {stream_type}: l0_cross_stream_inconsistent")

        return warnings

    def run_for_session(self, session_id: str, streams: list[StreamContext]) -> dict[str, Any]:
        run_id = self.state_store.new_run_id()
        started_at = utc_now_iso()
        warnings: list[str] = []
        per_stream_results: list[StreamRunResult] = []
        reports_by_stream: dict[str, dict[str, Any]] = {}
        report_paths_by_stream: dict[str, Path] = {}

        for stream in sorted(streams, key=lambda item: item.stream_type):
            raw_path = Path(stream.raw_path)
            output_path, report_path = derive_artifact_paths(raw_path, self.raw_root, self.processed_root)
            handler = _select_handler(self.registry, stream)
            if handler is None:
                warning = (
                    f"unsupported stream: session_id={stream.session_id} stream_type={stream.stream_type} "
                    f"payload_schema={stream.payload_schema or 'unknown'} "
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
                reports_by_stream[stream.stream_type] = result.report
                report_paths_by_stream[stream.stream_type] = report_path
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

        warnings.extend(self._apply_l0_cross_stream_gate(reports_by_stream))
        for stream_type, report in reports_by_stream.items():
            path = report_paths_by_stream.get(stream_type)
            if path is None:
                continue
            path.write_text(json.dumps(report, indent=2), encoding="utf-8")

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
