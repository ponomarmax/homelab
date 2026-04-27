from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import pandas as pd

from wearable_pipeline_api.pipeline.common import StepRunRecord, StreamRunResult
from wearable_pipeline_api.pipeline.state import RunStateStore, utc_now_iso

from .registry import session_summary_handler_registry

logger = logging.getLogger(__name__)

SUPPORTED_SESSION_STREAMS = ("hr", "acc", "ecg", "device_battery")
STREAM_KEY_BY_PAYLOAD_SCHEMA = {
    "polar.hr": "hr",
    "polar.acc": "acc",
    "polar.ecg": "ecg",
    "polar.device_battery": "device_battery",
}


@dataclass(frozen=True)
class FeatureArtifactMetadata:
    path: Path
    stream_type: str
    payload_schema: str
    source_vendor: str
    device_model: str
    window_start_utc: pd.Timestamp | None
    window_end_utc: pd.Timestamp | None


def _iso_utc_or_none(value: pd.Timestamp | None) -> str | None:
    if value is None or pd.isna(value):
        return None
    ts = value.tz_convert(timezone.utc) if value.tzinfo else value.tz_localize(timezone.utc)
    return ts.isoformat().replace("+00:00", "Z")


def _summary_status(stream_statuses: list[str], streams_missing: list[str]) -> str:
    usable_statuses = {"success", "partial"}
    usable_count = sum(1 for status in stream_statuses if status in usable_statuses)
    if usable_count == 0:
        return "failed"
    if streams_missing:
        return "partial"
    if any(status in {"failed", "missing"} for status in stream_statuses):
        return "partial"
    if all(status == "success" for status in stream_statuses):
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

    def _candidate_dates(self, requested_date: str | None) -> list[str]:
        if not requested_date:
            return []
        try:
            parsed = date.fromisoformat(requested_date)
        except ValueError:
            return []
        previous_day = parsed - timedelta(days=1)
        return [parsed.isoformat(), previous_day.isoformat()]

    def _discover_feature_paths(self, session_id: str, requested_date: str | None = None) -> list[Path]:
        patterns = [f"window_features/**/session_id={session_id}/streams/*/data.parquet"]
        for candidate in self._candidate_dates(requested_date):
            patterns.append(f"window_features/**/date={candidate}/session_id={session_id}/streams/*/data.parquet")

        discovered: set[Path] = set()
        for pattern in patterns:
            for path in self.processed_root.glob(pattern):
                if path.is_file():
                    discovered.add(path)
        return sorted(discovered)

    def _feature_paths_from_previous_step(self, window_feature_step_result: dict[str, Any]) -> list[Path]:
        paths: list[Path] = []
        for result in window_feature_step_result.get("per_stream_results", []):
            output_path = str(result.get("output_path") or "").strip()
            if not output_path:
                continue
            paths.append(Path(output_path))
        return sorted(paths)

    def _load_feature_metadata(self, path: Path) -> FeatureArtifactMetadata | None:
        try:
            frame = pd.read_parquet(path)
        except Exception as exc:  # pragma: no cover - protected by integration tests
            logger.warning("session_summary_feature_read_failed", extra={"path": str(path), "error": str(exc)})
            return None
        if frame.empty:
            return FeatureArtifactMetadata(
                path=path,
                stream_type=path.parent.name.lower(),
                payload_schema="",
                source_vendor="",
                device_model="",
                window_start_utc=None,
                window_end_utc=None,
            )

        stream_type = str(path.parent.name).strip().lower()
        if "stream_type" in frame.columns:
            stream_values = frame["stream_type"].dropna().astype(str)
            if not stream_values.empty:
                stream_type = stream_values.iloc[0].strip().lower()

        payload_schema = ""
        if "payload_schema" in frame.columns:
            payload_values = frame["payload_schema"].dropna().astype(str)
            if not payload_values.empty:
                payload_schema = payload_values.iloc[0].strip().lower()

        source_vendor = ""
        if "source_vendor" in frame.columns:
            source_values = frame["source_vendor"].dropna().astype(str)
            if not source_values.empty:
                source_vendor = source_values.iloc[0].strip().lower()

        device_model = ""
        if "device_model" in frame.columns:
            device_values = frame["device_model"].dropna().astype(str)
            if not device_values.empty:
                device_model = device_values.iloc[0].strip().lower()

        start_at = None
        end_at = None
        if "window_start_utc" in frame.columns:
            starts = pd.to_datetime(frame["window_start_utc"], utc=True, errors="coerce").dropna()
            if not starts.empty:
                start_at = starts.min()
        if "window_end_utc" in frame.columns:
            ends = pd.to_datetime(frame["window_end_utc"], utc=True, errors="coerce").dropna()
            if not ends.empty:
                end_at = ends.max()

        return FeatureArtifactMetadata(
            path=path,
            stream_type=stream_type,
            payload_schema=payload_schema,
            source_vendor=source_vendor,
            device_model=device_model,
            window_start_utc=start_at,
            window_end_utc=end_at,
        )

    def _resolve_summary_stream_key(self, metadata: FeatureArtifactMetadata) -> str | None:
        stream = metadata.stream_type.strip().lower()
        schema = metadata.payload_schema.strip().lower()
        vendor = metadata.source_vendor.strip().lower()
        device_model = metadata.device_model.strip().lower()

        if vendor == "polar" and schema in STREAM_KEY_BY_PAYLOAD_SCHEMA:
            if schema == "polar.hr":
                if device_model in {"h10", "verity_sense", ""}:
                    return "hr"
                return "hr"
            if schema in {"polar.acc", "polar.ecg", "polar.device_battery"} and device_model in {"h10", ""}:
                return STREAM_KEY_BY_PAYLOAD_SCHEMA[schema]
            return STREAM_KEY_BY_PAYLOAD_SCHEMA[schema]

        if stream in SUPPORTED_SESSION_STREAMS:
            return stream
        return None

    def run_for_session(
        self,
        session_id: str,
        window_feature_step_result: dict[str, Any] | None = None,
        requested_date: str | None = None,
    ) -> dict[str, Any]:
        run_id = self.state_store.new_run_id()
        started_at = utc_now_iso()
        logger.info("session_summary_step_started", extra={"session_id": session_id, "run_id": run_id})

        if window_feature_step_result is None:
            feature_paths = self._discover_feature_paths(session_id=session_id, requested_date=requested_date)
        else:
            feature_paths = self._feature_paths_from_previous_step(window_feature_step_result)
            if not feature_paths:
                feature_paths = self._discover_feature_paths(session_id=session_id, requested_date=requested_date)

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
        stream_paths_by_key: dict[str, list[Path]] = {key: [] for key in SUPPORTED_SESSION_STREAMS}
        feature_metadata: list[FeatureArtifactMetadata] = []

        for path in feature_paths:
            metadata = self._load_feature_metadata(path)
            if metadata is None:
                stream_warnings.append(f"failed to read window features: {path}")
                continue
            feature_metadata.append(metadata)
            stream_key = self._resolve_summary_stream_key(metadata)
            if stream_key is None:
                warning = (
                    "unsupported summary stream artifact: "
                    f"path={path} stream_type={metadata.stream_type or 'unknown'} "
                    f"payload_schema={metadata.payload_schema or 'unknown'} "
                    f"vendor={metadata.source_vendor or 'unknown'} "
                    f"device_model={metadata.device_model or 'unknown'}"
                )
                stream_warnings.append(warning)
                continue
            stream_paths_by_key[stream_key].append(path)

        for stream_type in SUPPORTED_SESSION_STREAMS:
            handler = self.registry.get(stream_type)
            if handler is None:
                continue
            stream_paths = sorted(set(stream_paths_by_key.get(stream_type, [])))
            if not stream_paths:
                warning = f"missing input stream for summary: {stream_type}"
                logger.warning("session_summary_stream_missing", extra={"session_id": session_id, "stream_type": stream_type})
                stream_warnings.append(warning)
            try:
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
            except Exception as exc:  # pragma: no cover - protected by integration tests
                logger.exception("session_summary_stream_failed", extra={"stream_type": stream_type, "session_id": session_id})
                error_message = str(exc)
                stream_warnings.append(f"summary stream failed: {stream_type}: {error_message}")
                summary_streams[stream_type] = {
                    "status": "failed",
                    "warnings": [error_message],
                    "artifacts": {
                        "source_window_features": [str(path) for path in stream_paths],
                        "generated_summary_path": str(summary_path),
                    },
                }
                per_stream_results.append(
                    StreamRunResult(
                        stream_type=stream_type,
                        handler_name=handler.name,
                        status="failed",
                        input_path=str(stream_paths[0]) if stream_paths else "",
                        output_path=str(summary_path),
                        error=error_message,
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

        starts = [item.window_start_utc for item in feature_metadata if item.window_start_utc is not None]
        ends = [item.window_end_utc for item in feature_metadata if item.window_end_utc is not None]
        started_at_utc = _iso_utc_or_none(min(starts) if starts else None)
        ended_at_utc = _iso_utc_or_none(max(ends) if ends else None)
        duration_seconds = 0
        if started_at_utc and ended_at_utc:
            start_dt = datetime.fromisoformat(started_at_utc.replace("Z", "+00:00"))
            end_dt = datetime.fromisoformat(ended_at_utc.replace("Z", "+00:00"))
            duration_seconds = max(int((end_dt - start_dt).total_seconds()), 0)
        crosses_midnight = False
        if started_at_utc and ended_at_utc:
            start_dt = datetime.fromisoformat(started_at_utc.replace("Z", "+00:00"))
            end_dt = datetime.fromisoformat(ended_at_utc.replace("Z", "+00:00"))
            crosses_midnight = start_dt.date() != end_dt.date()

        streams_present = [stream for stream in SUPPORTED_SESSION_STREAMS if stream_paths_by_key.get(stream)]
        streams_missing = [stream for stream in SUPPORTED_SESSION_STREAMS if stream not in streams_present]
        stream_statuses = [str(summary_streams.get(stream, {}).get("status") or "missing") for stream in SUPPORTED_SESSION_STREAMS]
        summary_status = _summary_status(stream_statuses=stream_statuses, streams_missing=streams_missing)

        per_stream_artifact_paths = {
            stream: sorted(str(path) for path in stream_paths_by_key.get(stream, [])) for stream in SUPPORTED_SESSION_STREAMS
        }
        summary_payload = {
            "schema_version": "1.0",
            "session_id": session_id,
            "started_at_utc": started_at_utc,
            "ended_at_utc": ended_at_utc,
            "duration_seconds": duration_seconds,
            "crosses_midnight": crosses_midnight,
            "streams_present": streams_present,
            "streams_missing": streams_missing,
            "stream_summaries": summary_streams,
            "artifact_paths": {
                "window_feature_paths": input_paths,
                "stream_window_feature_paths": per_stream_artifact_paths,
                "session_summary_path": str(summary_path),
            },
            "generated_at_utc": utc_now_iso(),
            "status": summary_status,
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
            status=summary_status,
            discovered_streams=list(SUPPORTED_SESSION_STREAMS),
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
