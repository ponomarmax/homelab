from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pandas as pd

from wearable_pipeline_api.pipeline.common import StepRunRecord
from wearable_pipeline_api.pipeline.state import RunStateStore, utc_now_iso


class GrafanaViewsExportStepRunner:
    step_name = "export_grafana_views"

    def __init__(self, processed_root: Path, state_store: RunStateStore, grafana_root: Path) -> None:
        self.processed_root = processed_root
        self.state_store = state_store
        self.grafana_root = grafana_root

    def _resolve_normalized_ppi_path(self, session_id: str) -> Path | None:
        paths = sorted(self.processed_root.glob(f"clean_timeseries/**/session_id={session_id}/streams/ppi/data.parquet"))
        return paths[-1] if paths else None

    def _resolve_feature_paths(self, session_id: str) -> list[Path]:
        return sorted(self.processed_root.glob(f"window_features/**/session_id={session_id}/streams/*/data.parquet"))

    def _resolve_summary_path(self, session_id: str) -> Path | None:
        paths = sorted(self.processed_root.glob(f"window_features/**/session_id={session_id}/session_summary.json"))
        return paths[-1] if paths else None

    def _load_existing_csv(self, path: Path, columns: list[str]) -> pd.DataFrame:
        if not path.exists():
            return pd.DataFrame(columns=columns)
        frame = pd.read_csv(path)
        for col in columns:
            if col not in frame.columns:
                frame[col] = None
        return frame[columns]

    def _load_existing_sessions_json(self, path: Path) -> list[dict[str, Any]]:
        if not path.exists():
            return []
        payload = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(payload, list):
            return [item for item in payload if isinstance(item, dict)]
        return []

    def _normalized_ppi_points(self, session_id: str, normalized_path: Path, warnings: list[str]) -> pd.DataFrame:
        frame = pd.read_parquet(normalized_path)
        if frame.empty:
            return pd.DataFrame()

        def _col(name: str) -> pd.Series:
            if name not in frame.columns:
                warnings.append(f"missing normalized PPI column: {name}")
                return pd.Series([None] * len(frame))
            return frame[name]

        points = pd.DataFrame(
            {
                "session_id": [session_id] * len(frame),
                "ts_utc": pd.to_datetime(_col("ts_utc"), utc=True, errors="coerce"),
                "ppi_ms": pd.to_numeric(_col("pp_in_ms"), errors="coerce"),
                "hr_bpm": pd.to_numeric(_col("hr"), errors="coerce"),
                "pp_error_estimate_ms": pd.to_numeric(_col("pp_error_estimate"), errors="coerce"),
                "blocker": _col("sample_quality_blocked"),
                "skin_contact": _col("sample_quality_skin_contact_missing"),
                "sample_quality_tier": _col("sample_quality_tier").astype("string"),
                "pp_error_band": _col("pp_error_band").astype("string"),
            }
        )
        points = points.dropna(subset=["ts_utc"]).sort_values("ts_utc")
        points["ts_utc"] = points["ts_utc"].dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        points["blocker"] = points["blocker"].apply(lambda v: "true" if bool(v) else "false")
        points["skin_contact"] = points["skin_contact"].apply(lambda v: "lost" if bool(v) else "ok")
        tier = points["sample_quality_tier"].astype("string")
        points["ppi_high"] = points["ppi_ms"].where(tier == "high")
        points["ppi_medium"] = points["ppi_ms"].where(tier == "medium")
        points["ppi_low"] = points["ppi_ms"].where(tier == "low")
        points["ppi_trend"] = points["ppi_ms"]
        return points

    def _quality_events(self, points: pd.DataFrame, session_id: str) -> pd.DataFrame:
        if points.empty:
            return pd.DataFrame(columns=["session_id", "ts_utc", "event_type", "severity", "source"])

        events: list[dict[str, Any]] = []
        prev = None
        for _, row in points.iterrows():
            ts = row.get("ts_utc")
            if str(row.get("blocker")) == "true":
                events.append({"session_id": session_id, "ts_utc": ts, "event_type": "blocker_detected", "severity": "high", "source": "normalized_ppi"})
            if str(row.get("skin_contact")) == "lost":
                events.append({"session_id": session_id, "ts_utc": ts, "event_type": "contact_lost", "severity": "medium", "source": "normalized_ppi"})
            tier = row.get("sample_quality_tier")
            if tier is not None and not pd.isna(tier) and str(tier) == "low":
                events.append({"session_id": session_id, "ts_utc": ts, "event_type": "quality_bad", "severity": "high", "source": "normalized_ppi"})
            if prev is not None:
                cur_ts = pd.to_datetime(ts, utc=True, errors="coerce")
                prev_ts = pd.to_datetime(prev, utc=True, errors="coerce")
                if pd.notna(cur_ts) and pd.notna(prev_ts):
                    if (cur_ts - prev_ts).total_seconds() > 5:
                        events.append({"session_id": session_id, "ts_utc": ts, "event_type": "gap_detected", "severity": "medium", "source": "derived_gap"})
            prev = ts
        return pd.DataFrame(events, columns=["session_id", "ts_utc", "event_type", "severity", "source"])

    def _feature_windows(self, session_id: str, feature_paths: list[Path], warnings: list[str]) -> pd.DataFrame:
        rows: list[dict[str, Any]] = []
        for path in feature_paths:
            try:
                frame = pd.read_parquet(path)
            except Exception as exc:
                warnings.append(f"failed reading feature artifact: {path}: {exc}")
                continue
            if frame.empty:
                continue
            for _, r in frame.iterrows():
                window_size = str(r.get("window_size") or "")
                window_start = str(r.get("window_start_utc") or "")
                for key, value in r.items():
                    if key in {"window_size", "window_start_utc", "window_end_utc", "stream_type", "payload_schema", "source_vendor", "device_model", "sample_count", "samples_count", "input_artifact_reference"}:
                        continue
                    if isinstance(value, (int, float)) and pd.notna(value):
                        rows.append(
                            {
                                "session_id": session_id,
                                "window_size": window_size,
                                "window_start": window_start,
                                "feature_name": str(key),
                                "feature_value": float(value),
                            }
                        )
        return pd.DataFrame(rows, columns=["session_id", "window_size", "window_start", "feature_name", "feature_value"])

    def _session_object(
        self,
        *,
        session_id: str,
        normalized_path: Path | None,
        feature_paths: list[Path],
        summary_path: Path | None,
        points_rows: int,
    ) -> dict[str, Any]:
        started_at = None
        ended_at = None
        duration_seconds = None
        available_streams: list[str] = []
        artifact_paths: dict[str, Any] = {
            "normalized_ppi": str(normalized_path) if normalized_path else None,
            "feature_paths": [str(path) for path in feature_paths],
            "summary_path": str(summary_path) if summary_path else None,
        }
        if summary_path and summary_path.exists():
            payload = json.loads(summary_path.read_text(encoding="utf-8"))
            started_at = payload.get("started_at_utc")
            ended_at = payload.get("ended_at_utc")
            duration_seconds = payload.get("duration_seconds")
            available_streams = payload.get("streams_present") or []
        if not available_streams and normalized_path is not None and points_rows > 0:
            available_streams = ["ppi"]
        return {
            "session_id": session_id,
            "available_streams": available_streams,
            "started_at": started_at,
            "ended_at": ended_at,
            "duration_seconds": duration_seconds,
            "artifact_paths": artifact_paths,
            "summary_exists": bool(summary_path),
            "feature_exists": bool(feature_paths),
            "exported_at_utc": utc_now_iso(),
        }

    def run_for_session(self, session_id: str) -> dict[str, Any]:
        run_id = self.state_store.new_run_id()
        started_at = utc_now_iso()
        warnings: list[str] = []

        normalized_path = self._resolve_normalized_ppi_path(session_id)
        feature_paths = self._resolve_feature_paths(session_id)
        summary_path = self._resolve_summary_path(session_id)

        if normalized_path is None:
            warnings.append("missing normalized PPI artifact")
        if not feature_paths:
            warnings.append("missing feature artifacts")
        if summary_path is None:
            warnings.append("missing session_summary.json")

        points_df = (
            self._normalized_ppi_points(session_id, normalized_path, warnings)
            if normalized_path is not None
            else pd.DataFrame(
                columns=[
                    "session_id",
                    "ts_utc",
                    "ppi_ms",
                    "hr_bpm",
                    "pp_error_estimate_ms",
                    "blocker",
                    "skin_contact",
                    "sample_quality_tier",
                    "pp_error_band",
                    "ppi_high",
                    "ppi_medium",
                    "ppi_low",
                    "ppi_trend",
                ]
            )
        )
        features_df = self._feature_windows(session_id, feature_paths, warnings)
        events_df = self._quality_events(points_df, session_id)
        session_obj = self._session_object(
            session_id=session_id,
            normalized_path=normalized_path,
            feature_paths=feature_paths,
            summary_path=summary_path,
            points_rows=int(len(points_df.index)),
        )

        self.grafana_root.mkdir(parents=True, exist_ok=True)
        sessions_path = self.grafana_root / "sessions.json"
        ppi_path = self.grafana_root / "normalized_ppi_points.csv"
        feature_path = self.grafana_root / "feature_windows.csv"
        events_path = self.grafana_root / "quality_events.csv"

        existing_sessions = [item for item in self._load_existing_sessions_json(sessions_path) if item.get("session_id") != session_id]
        existing_sessions.append(session_obj)
        existing_sessions.sort(key=lambda item: str(item.get("session_id") or ""))
        sessions_path.write_text(json.dumps(existing_sessions, indent=2), encoding="utf-8")

        ppi_cols = [
            "session_id",
            "ts_utc",
            "ppi_ms",
            "hr_bpm",
            "pp_error_estimate_ms",
            "blocker",
            "skin_contact",
            "sample_quality_tier",
            "pp_error_band",
            "ppi_high",
            "ppi_medium",
            "ppi_low",
            "ppi_trend",
        ]
        existing_ppi = self._load_existing_csv(ppi_path, ppi_cols)
        existing_ppi = existing_ppi[existing_ppi["session_id"] != session_id]
        merged_ppi = pd.concat([existing_ppi, points_df[ppi_cols]], ignore_index=True).sort_values(["session_id", "ts_utc"], kind="stable")
        merged_ppi.to_csv(ppi_path, index=False)

        fw_cols = ["session_id", "window_size", "window_start", "feature_name", "feature_value"]
        existing_fw = self._load_existing_csv(feature_path, fw_cols)
        existing_fw = existing_fw[existing_fw["session_id"] != session_id]
        merged_fw = pd.concat([existing_fw, features_df[fw_cols]], ignore_index=True).sort_values(["session_id", "window_start", "feature_name"], kind="stable")
        merged_fw.to_csv(feature_path, index=False)

        ev_cols = ["session_id", "ts_utc", "event_type", "severity", "source"]
        existing_ev = self._load_existing_csv(events_path, ev_cols)
        existing_ev = existing_ev[existing_ev["session_id"] != session_id]
        merged_ev = pd.concat([existing_ev, events_df[ev_cols]], ignore_index=True).sort_values(["session_id", "ts_utc", "event_type"], kind="stable")
        merged_ev.to_csv(events_path, index=False)

        session_root = self.grafana_root / f"session_id={session_id}"
        session_root.mkdir(parents=True, exist_ok=True)
        points_df[ppi_cols].to_csv(session_root / "normalized_ppi_points.csv", index=False)
        features_df[fw_cols].to_csv(session_root / "feature_windows.csv", index=False)
        events_df[ev_cols].to_csv(session_root / "quality_events.csv", index=False)
        (session_root / "session.json").write_text(json.dumps([session_obj], indent=2), encoding="utf-8")

        finished_at = utc_now_iso()
        status = "success" if normalized_path is not None else "partial"
        run_record = StepRunRecord(
            run_id=run_id,
            step_name=self.step_name,
            session_id=session_id,
            started_at_utc=started_at,
            finished_at_utc=finished_at,
            status=status,
            discovered_streams=["ppi"],
            per_stream_results=[
                {
                    "stream_type": "ppi",
                    "handler_name": "GrafanaViewsExportStepRunner",
                    "status": "success" if normalized_path is not None else "skipped",
                    "input_path": str(normalized_path) if normalized_path else "",
                    "output_path": str(ppi_path),
                    "error": None if normalized_path is not None else "missing normalized PPI artifact",
                }
            ],
            warnings=warnings,
        )
        state_path = self.state_store.write(run_record)

        return {
            "run_id": run_id,
            "status": status,
            "session_id": session_id,
            "step_name": self.step_name,
            "state_path": str(state_path),
            "generated_paths": {
                "sessions_json": str(sessions_path),
                "normalized_ppi_points_csv": str(ppi_path),
                "feature_windows_csv": str(feature_path),
                "quality_events_csv": str(events_path),
                "session_root": str(session_root),
            },
            "normalized_ppi_rows_exported": int(len(points_df.index)),
            "quality_events_rows_exported": int(len(events_df.index)),
            "feature_windows_rows_exported": int(len(features_df.index)),
            "warnings": warnings,
        }
