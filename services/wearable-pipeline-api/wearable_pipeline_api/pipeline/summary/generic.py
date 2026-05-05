from __future__ import annotations

from pathlib import Path

import pandas as pd

from .hr import EXPECTED_WINDOW_SIZES, HrSummaryOutput, _safe_float


class GenericWindowSummaryHandler:
    def __init__(self, stream_type: str) -> None:
        self.name = f"{stream_type.title()}SummaryHandler"
        self.stream_type = stream_type

    def handle(self, window_feature_paths: list[Path], generated_summary_path: str) -> HrSummaryOutput:
        warnings: list[str] = []
        source_paths = sorted(str(path) for path in window_feature_paths)
        if not window_feature_paths:
            warnings.append("empty dataset")
            return HrSummaryOutput(
                stream_summary={
                    "status": "missing",
                    "coverage": {
                        "window_counts": {size: 0 for size in EXPECTED_WINDOW_SIZES},
                        "window_count_total": 0,
                        "sample_count_total": 0,
                    },
                    "data_quality": {"status": "unknown", "missing_windows": len(EXPECTED_WINDOW_SIZES), "anomaly_count": None},
                    "warnings": warnings,
                    "artifacts": {
                        "source_window_features": source_paths,
                        "generated_summary_path": generated_summary_path,
                    },
                },
                status="missing",
                warnings=warnings,
                available_window_sizes=[],
                source_paths=source_paths,
            )

        frames: list[pd.DataFrame] = []
        for path in sorted(window_feature_paths):
            if not path.exists():
                warnings.append(f"missing window feature file: {path}")
                continue
            frame = pd.read_parquet(path)
            if frame.empty:
                continue
            expected_columns = {"window_size", "window_start_utc", "window_end_utc", "sample_count"}
            missing = sorted(expected_columns - set(frame.columns))
            if missing:
                warnings.append(f"invalid window feature schema ({path}): missing {', '.join(missing)}")
                continue
            frames.append(frame)

        if not frames:
            warnings.append("empty dataset")
            return HrSummaryOutput(
                stream_summary={
                    "status": "missing",
                    "coverage": {"window_counts": {size: 0 for size in EXPECTED_WINDOW_SIZES}},
                    "data_quality": {"status": "unknown", "missing_windows": len(EXPECTED_WINDOW_SIZES), "anomaly_count": None},
                    "warnings": warnings,
                    "artifacts": {"source_window_features": source_paths, "generated_summary_path": generated_summary_path},
                },
                status="missing",
                warnings=warnings,
                available_window_sizes=[],
                source_paths=source_paths,
            )

        data = pd.concat(frames, ignore_index=True)
        data["window_size"] = data["window_size"].astype(str)
        data["window_start_utc"] = pd.to_datetime(data["window_start_utc"], utc=True, errors="coerce")
        data["window_end_utc"] = pd.to_datetime(data["window_end_utc"], utc=True, errors="coerce")
        data["sample_count"] = pd.to_numeric(data["sample_count"], errors="coerce")
        data = data.dropna(subset=["window_size", "window_start_utc"]).sort_values("window_start_utc").reset_index(drop=True)

        available_window_sizes = [size for size in EXPECTED_WINDOW_SIZES if (data["window_size"] == size).any()]
        window_counts = {size: int((data["window_size"] == size).sum()) for size in EXPECTED_WINDOW_SIZES}
        missing_sizes = [size for size in EXPECTED_WINDOW_SIZES if size not in available_window_sizes]
        for size in missing_sizes:
            warnings.append(f"missing expected window size: {size}")

        anomaly_count = int(data["sample_count"].isna().sum())
        if anomaly_count > 0:
            warnings.append("any NaN values detected")

        status = "success" if not missing_sizes and anomaly_count == 0 else "partial"
        data_quality = "good" if status == "success" else "partial"

        summary = {
            "status": status,
            "coverage": {
                "window_counts": window_counts,
                "window_count_total": int(len(data.index)),
                "sample_count_total": int(data["sample_count"].fillna(0).sum()),
            },
            "sample_count": {
                "min": _safe_float(data["sample_count"].min()),
                "max": _safe_float(data["sample_count"].max()),
                "mean": _safe_float(data["sample_count"].mean()),
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
            status=status,
            warnings=warnings,
            available_window_sizes=available_window_sizes,
            source_paths=source_paths,
        )

