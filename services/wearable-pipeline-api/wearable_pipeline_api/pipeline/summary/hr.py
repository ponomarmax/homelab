from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pandas as pd


EXPECTED_WINDOW_SIZES = ("30s", "1m", "5m")


@dataclass
class HrSummaryOutput:
    stream_summary: dict[str, Any]
    status: str
    warnings: list[str]
    available_window_sizes: list[str]
    source_paths: list[str]


def _safe_float(value: object) -> float | None:
    if value is None:
        return None
    try:
        numeric = float(value)
    except (TypeError, ValueError):
        return None
    if pd.isna(numeric):
        return None
    return numeric


class HrSummaryHandler:
    name = "HrSummaryHandler"
    stream_type = "hr"

    def _empty_summary(self, generated_summary_path: str, source_paths: list[str], warnings: list[str]) -> HrSummaryOutput:
        summary = {
            "status": "missing",
            "coverage": {
                "window_counts": {size: 0 for size in EXPECTED_WINDOW_SIZES},
                "estimated_duration_seconds": 0,
            },
            "hr_statistics": {
                "min": None,
                "max": None,
                "mean": None,
                "median": None,
                "std": None,
                "p05": None,
                "p10": None,
                "p90": None,
                "p95": None,
                "range": None,
                "cv": None,
            },
            "trend": {
                "first_window_mean": None,
                "last_window_mean": None,
                "delta": None,
            },
            "extremes": {
                "lowest_window_mean": None,
                "highest_window_mean": None,
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
            expected_columns = {"window_size", "window_start_utc", "window_end_utc", "hr_mean"}
            missing_columns = sorted(expected_columns - set(frame.columns))
            if missing_columns:
                warnings.append(f"invalid window feature schema ({path}): missing {', '.join(missing_columns)}")
                continue
            scoped = frame[["window_size", "window_start_utc", "window_end_utc", "hr_mean"]].copy()
            scoped["source_window_feature_path"] = str(path)
            frames.append(scoped)

        if not frames:
            warnings.append("empty dataset")
            return self._empty_summary(generated_summary_path, source_paths, warnings)

        data = pd.concat(frames, ignore_index=True)
        data["window_size"] = data["window_size"].astype(str)
        data["window_start_utc"] = pd.to_datetime(data["window_start_utc"], utc=True, errors="coerce")
        data["window_end_utc"] = pd.to_datetime(data["window_end_utc"], utc=True, errors="coerce")
        data["hr_mean"] = pd.to_numeric(data["hr_mean"], errors="coerce")
        data = data.dropna(subset=["window_size", "window_start_utc"]).sort_values("window_start_utc").reset_index(drop=True)

        available_window_sizes = [size for size in EXPECTED_WINDOW_SIZES if (data["window_size"] == size).any()]
        window_counts = {size: int((data["window_size"] == size).sum()) for size in EXPECTED_WINDOW_SIZES}
        missing_sizes = [size for size in EXPECTED_WINDOW_SIZES if size not in available_window_sizes]
        for size in missing_sizes:
            warnings.append(f"missing expected window size: {size}")

        analysis_size = next((size for size in EXPECTED_WINDOW_SIZES if window_counts[size] > 0), None)
        analysis_df = data[data["window_size"] == analysis_size].copy() if analysis_size else pd.DataFrame(columns=data.columns)
        analysis_df = analysis_df.sort_values("window_start_utc").reset_index(drop=True)

        nan_count = int(analysis_df["hr_mean"].isna().sum()) if not analysis_df.empty else 0
        if nan_count > 0:
            warnings.append("any NaN values detected")

        valid_values = analysis_df["hr_mean"].dropna()
        if analysis_df.empty or valid_values.empty:
            warnings.append("empty dataset")
            return self._empty_summary(generated_summary_path, source_paths, warnings)

        if int(len(valid_values.index)) < 3:
            warnings.append("too few windows")

        first_value = _safe_float(analysis_df["hr_mean"].dropna().iloc[0]) if not analysis_df["hr_mean"].dropna().empty else None
        last_value = _safe_float(analysis_df["hr_mean"].dropna().iloc[-1]) if not analysis_df["hr_mean"].dropna().empty else None
        delta = None
        if first_value is not None and last_value is not None:
            delta = last_value - first_value

        duration_seconds = 0
        min_start = analysis_df["window_start_utc"].min()
        max_end = analysis_df["window_end_utc"].max()
        if pd.notna(min_start) and pd.notna(max_end):
            duration_seconds = max(int((max_end - min_start).total_seconds()), 0)

        stream_status = "success"
        if missing_sizes or nan_count > 0:
            stream_status = "partial"

        data_quality = "good"
        if int(len(valid_values.index)) < 3:
            data_quality = "poor"
        elif missing_sizes or nan_count > 0:
            data_quality = "partial"

        mean_value = _safe_float(valid_values.mean())
        std_value = _safe_float(valid_values.std(ddof=0))
        cv_value = None
        if mean_value is not None and std_value is not None and mean_value > 0:
            cv_value = std_value / mean_value

        hr_statistics = {
            "min": _safe_float(valid_values.min()),
            "max": _safe_float(valid_values.max()),
            "mean": mean_value,
            "median": _safe_float(valid_values.median()),
            "std": std_value,
            "p05": _safe_float(valid_values.quantile(0.05)),
            "p10": _safe_float(valid_values.quantile(0.10)),
            "p90": _safe_float(valid_values.quantile(0.90)),
            "p95": _safe_float(valid_values.quantile(0.95)),
            "range": _safe_float(valid_values.max() - valid_values.min()),
            "cv": _safe_float(cv_value),
        }

        summary = {
            "status": stream_status,
            "coverage": {
                "window_counts": window_counts,
                "estimated_duration_seconds": duration_seconds,
            },
            "hr_statistics": hr_statistics,
            "trend": {
                "first_window_mean": first_value,
                "last_window_mean": last_value,
                "delta": _safe_float(delta),
            },
            "extremes": {
                "lowest_window_mean": _safe_float(valid_values.min()),
                "highest_window_mean": _safe_float(valid_values.max()),
            },
            "data_quality": {
                "status": data_quality,
                "missing_windows": int(len(missing_sizes)),
                "anomaly_count": nan_count,
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
