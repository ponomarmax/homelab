from __future__ import annotations

from pathlib import Path

import pandas as pd

from .hr import EXPECTED_WINDOW_SIZES, HrSummaryOutput, _safe_float


class DeviceBatterySummaryHandler:
    name = "DeviceBatterySummaryHandler"
    stream_type = "battery"

    def _empty_summary(self, generated_summary_path: str, source_paths: list[str], warnings: list[str]) -> HrSummaryOutput:
        summary = {
            "status": "missing",
            "coverage": {
                "window_counts": {size: 0 for size in EXPECTED_WINDOW_SIZES},
                "window_count_total": 0,
                "sample_count_total": 0,
                "estimated_duration_seconds": 0,
            },
            "battery": {
                "first_level": None,
                "last_level": None,
                "min_level": None,
                "max_level": None,
                "mean_level": None,
                "samples_count": 0,
                "charge_states_observed": [],
                "drain_per_hour": None,
            },
            "data_quality": {
                "status": "unknown",
                "missing_windows": len(EXPECTED_WINDOW_SIZES),
                "anomaly_count": None,
            },
            "warnings": warnings,
            "artifacts": {
                "source_window_features": source_paths,
                "source_clean_timeseries": [],
                "generated_summary_path": generated_summary_path,
            },
        }
        return HrSummaryOutput(
            stream_summary=summary,
            status="missing",
            warnings=warnings,
            available_window_sizes=[],
            source_paths=source_paths,
        )

    def _read_clean_timeseries(self, paths: list[str], warnings: list[str]) -> pd.DataFrame:
        frames: list[pd.DataFrame] = []
        for path_str in sorted(set(paths)):
            path = Path(path_str)
            if not path.exists():
                warnings.append(f"missing clean artifact referenced by window features: {path}")
                continue
            try:
                frame = pd.read_parquet(path)
            except Exception as exc:  # pragma: no cover - protected by integration tests
                warnings.append(f"failed to read clean artifact {path}: {exc}")
                continue
            if frame.empty:
                continue
            expected_columns = {"ts_utc", "level_percent", "charge_state"}
            missing_columns = sorted(expected_columns - set(frame.columns))
            if missing_columns:
                warnings.append(f"invalid clean battery schema ({path}): missing {', '.join(missing_columns)}")
                continue
            scoped = frame[list(expected_columns)].copy()
            frames.append(scoped)
        if not frames:
            return pd.DataFrame(columns=["ts_utc", "level_percent", "charge_state"])
        data = pd.concat(frames, ignore_index=True)
        data["ts_utc"] = pd.to_datetime(data["ts_utc"], utc=True, errors="coerce")
        data["level_percent"] = pd.to_numeric(data["level_percent"], errors="coerce")
        data = data.dropna(subset=["ts_utc", "level_percent"]).sort_values("ts_utc").reset_index(drop=True)
        return data

    def handle(self, window_feature_paths: list[Path], generated_summary_path: str) -> HrSummaryOutput:
        warnings: list[str] = []
        source_paths = sorted(str(path) for path in window_feature_paths)
        if not window_feature_paths:
            warnings.append("empty dataset")
            return self._empty_summary(generated_summary_path, source_paths, warnings)

        frames: list[pd.DataFrame] = []
        for path in sorted(window_feature_paths):
            if not path.exists():
                warnings.append(f"missing window feature file: {path}")
                continue
            frame = pd.read_parquet(path)
            if frame.empty:
                continue
            expected_columns = {
                "window_size",
                "window_start_utc",
                "window_end_utc",
                "sample_count",
                "samples_count",
                "level_min",
                "level_max",
                "level_mean",
                "level_first",
                "level_last",
                "drain_per_hour",
                "input_artifact_reference",
            }
            missing_columns = sorted(expected_columns - set(frame.columns))
            if missing_columns:
                warnings.append(f"invalid window feature schema ({path}): missing {', '.join(missing_columns)}")
                continue
            scoped = frame[list(expected_columns)].copy()
            scoped["source_window_feature_path"] = str(path)
            frames.append(scoped)

        if not frames:
            warnings.append("empty dataset")
            return self._empty_summary(generated_summary_path, source_paths, warnings)

        data = pd.concat(frames, ignore_index=True)
        data["window_size"] = data["window_size"].astype(str)
        data["window_start_utc"] = pd.to_datetime(data["window_start_utc"], utc=True, errors="coerce")
        data["window_end_utc"] = pd.to_datetime(data["window_end_utc"], utc=True, errors="coerce")
        numeric_columns = [
            "sample_count",
            "samples_count",
            "level_min",
            "level_max",
            "level_mean",
            "level_first",
            "level_last",
            "drain_per_hour",
        ]
        for column in numeric_columns:
            data[column] = pd.to_numeric(data[column], errors="coerce")
        data = data.dropna(subset=["window_size", "window_start_utc"]).sort_values("window_start_utc").reset_index(drop=True)

        available_window_sizes = [size for size in EXPECTED_WINDOW_SIZES if (data["window_size"] == size).any()]
        window_counts = {size: int((data["window_size"] == size).sum()) for size in EXPECTED_WINDOW_SIZES}
        missing_sizes = [size for size in EXPECTED_WINDOW_SIZES if size not in available_window_sizes]
        for size in missing_sizes:
            warnings.append(f"missing expected window size: {size}")

        analysis_size = next((size for size in EXPECTED_WINDOW_SIZES if window_counts[size] > 0), None)
        analysis_df = data[data["window_size"] == analysis_size].copy() if analysis_size else pd.DataFrame(columns=data.columns)
        analysis_df = analysis_df.sort_values("window_start_utc").reset_index(drop=True)
        if analysis_df.empty:
            warnings.append("empty dataset")
            return self._empty_summary(generated_summary_path, source_paths, warnings)

        duration_seconds = 0
        min_start = analysis_df["window_start_utc"].min()
        max_end = analysis_df["window_end_utc"].max()
        if pd.notna(min_start) and pd.notna(max_end):
            duration_seconds = max(int((max_end - min_start).total_seconds()), 0)

        clean_paths = [str(item) for item in analysis_df["input_artifact_reference"].dropna().astype(str).tolist()]
        clean_df = self._read_clean_timeseries(clean_paths, warnings)

        first_level = _safe_float(analysis_df["level_first"].iloc[0]) if not analysis_df.empty else None
        last_level = _safe_float(analysis_df["level_last"].iloc[-1]) if not analysis_df.empty else None
        min_level = _safe_float(analysis_df["level_min"].min())
        max_level = _safe_float(analysis_df["level_max"].max())
        mean_level = _safe_float(analysis_df["level_mean"].mean())
        samples_count = int(analysis_df["samples_count"].fillna(0).sum())
        charge_states_observed: list[str] = []
        drain_per_hour = _safe_float(analysis_df["drain_per_hour"].dropna().mean())

        if not clean_df.empty:
            first_level = _safe_float(clean_df["level_percent"].iloc[0])
            last_level = _safe_float(clean_df["level_percent"].iloc[-1])
            min_level = _safe_float(clean_df["level_percent"].min())
            max_level = _safe_float(clean_df["level_percent"].max())
            mean_level = _safe_float(clean_df["level_percent"].mean())
            samples_count = int(len(clean_df.index))
            charge_states_observed = sorted({str(item) for item in clean_df["charge_state"].dropna().astype(str) if str(item)})
            if len(clean_df.index) >= 2:
                elapsed_hours = (clean_df["ts_utc"].iloc[-1] - clean_df["ts_utc"].iloc[0]).total_seconds() / 3600.0
                if elapsed_hours > 0:
                    drain_per_hour = _safe_float((float(clean_df["level_percent"].iloc[0]) - float(clean_df["level_percent"].iloc[-1])) / elapsed_hours)

        anomaly_count = 0
        for column in ["level_min", "level_max", "level_mean", "level_first", "level_last"]:
            anomaly_count += int(analysis_df[column].isna().sum())
        if anomaly_count > 0:
            warnings.append("any NaN values detected")

        stream_status = "success"
        if missing_sizes or anomaly_count > 0:
            stream_status = "partial"
        if samples_count == 0:
            stream_status = "missing"

        data_quality = "good"
        if samples_count == 0:
            data_quality = "poor"
        elif missing_sizes or anomaly_count > 0:
            data_quality = "partial"

        summary = {
            "status": stream_status,
            "coverage": {
                "window_counts": window_counts,
                "window_count_total": int(len(analysis_df.index)),
                "sample_count_total": int(analysis_df["sample_count"].fillna(0).sum()),
                "estimated_duration_seconds": duration_seconds,
            },
            "battery": {
                "first_level": first_level,
                "last_level": last_level,
                "min_level": min_level,
                "max_level": max_level,
                "mean_level": mean_level,
                "samples_count": samples_count,
                "charge_states_observed": charge_states_observed,
                "drain_per_hour": drain_per_hour,
            },
            "data_quality": {
                "status": data_quality,
                "missing_windows": int(len(missing_sizes)),
                "anomaly_count": anomaly_count,
            },
            "warnings": warnings,
            "artifacts": {
                "source_window_features": source_paths,
                "source_clean_timeseries": sorted(set(clean_paths)),
                "generated_summary_path": generated_summary_path,
            },
        }
        return HrSummaryOutput(
            stream_summary=summary,
            status=stream_status,
            warnings=warnings,
            available_window_sizes=available_window_sizes,
            source_paths=source_paths,
        )
