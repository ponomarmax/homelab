from __future__ import annotations

from pathlib import Path

import pandas as pd

from .hr import EXPECTED_WINDOW_SIZES, HrSummaryOutput, _safe_float


class EcgSummaryHandler:
    name = "EcgSummaryHandler"
    stream_type = "ecg"

    def _empty_summary(self, generated_summary_path: str, source_paths: list[str], warnings: list[str]) -> HrSummaryOutput:
        summary = {
            "status": "missing",
            "coverage": {
                "window_counts": {size: 0 for size in EXPECTED_WINDOW_SIZES},
                "window_count_total": 0,
                "sample_count_total": 0,
                "estimated_duration_seconds": 0,
            },
            "ecg_uv": {
                "mean": None,
                "std": None,
                "min": None,
                "max": None,
            },
            "amplitude_range": {
                "mean": None,
                "min": None,
                "max": None,
            },
            "data_quality": {
                "status": "unknown",
                "missing_windows": len(EXPECTED_WINDOW_SIZES),
                "anomaly_count": None,
            },
            "warnings": warnings,
            "artifacts": {
                "source_window_features": source_paths,
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
                "ecg_mean",
                "ecg_std",
                "ecg_min",
                "ecg_max",
                "amplitude_range",
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
        numeric_columns = ["sample_count", "ecg_mean", "ecg_std", "ecg_min", "ecg_max", "amplitude_range"]
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

        anomaly_count = 0
        for column in ["ecg_mean", "ecg_std", "ecg_min", "ecg_max", "amplitude_range"]:
            anomaly_count += int(analysis_df[column].isna().sum())
        if anomaly_count > 0:
            warnings.append("any NaN values detected")

        stream_status = "success"
        if missing_sizes or anomaly_count > 0:
            stream_status = "partial"

        data_quality = "good"
        if int(len(analysis_df.index)) < 1:
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
            "ecg_uv": {
                "mean": _safe_float(analysis_df["ecg_mean"].mean()),
                "std": _safe_float(analysis_df["ecg_std"].mean()),
                "min": _safe_float(analysis_df["ecg_min"].min()),
                "max": _safe_float(analysis_df["ecg_max"].max()),
            },
            "amplitude_range": {
                "mean": _safe_float(analysis_df["amplitude_range"].mean()),
                "min": _safe_float(analysis_df["amplitude_range"].min()),
                "max": _safe_float(analysis_df["amplitude_range"].max()),
            },
            "data_quality": {
                "status": data_quality,
                "missing_windows": int(len(missing_sizes)),
                "anomaly_count": anomaly_count,
            },
            "warnings": warnings,
            "artifacts": {
                "source_window_features": source_paths,
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
