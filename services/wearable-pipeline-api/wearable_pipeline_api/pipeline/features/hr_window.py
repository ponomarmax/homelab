from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import pandas as pd


WINDOWS = [("30s", "30s"), ("1m", "1min"), ("5m", "5min")]


@dataclass
class FeatureHandlerOutput:
    dataframe: pd.DataFrame


class HrWindowFeatureBuilder:
    name = "HrWindowFeatureBuilder"

    def handle(self, clean_df: pd.DataFrame, run_id: str, input_artifact_reference: str) -> FeatureHandlerOutput:
        if clean_df.empty:
            empty_columns = [
                "user_id",
                "session_id",
                "stream_id",
                "stream_type",
                "source_vendor",
                "device_model",
                "window_size",
                "window_start_utc",
                "window_end_utc",
                "sample_count",
                "hr_mean",
                "hr_min",
                "hr_max",
                "hr_std",
                "hr_median",
                "hr_first",
                "hr_last",
                "coverage_ratio",
                "input_artifact_reference",
                "run_id",
            ]
            return FeatureHandlerOutput(dataframe=pd.DataFrame(columns=empty_columns))

        df = clean_df.copy()
        df["ts_utc"] = pd.to_datetime(df["ts_utc"], utc=True, errors="coerce")
        df = df.dropna(subset=["ts_utc"]).sort_values("ts_utc").reset_index(drop=True)

        rows: list[dict[str, Any]] = []
        for window_size, freq in WINDOWS:
            grouped = df.groupby(df["ts_utc"].dt.floor(freq), dropna=False)
            for window_start, group in grouped:
                if pd.isna(window_start):
                    continue

                hr_values = group["hr"].astype(float)
                first_ts = group["ts_utc"].iloc[0]
                last_ts = group["ts_utc"].iloc[-1]
                window_seconds = pd.Timedelta(freq).total_seconds()
                covered_seconds = max((last_ts - first_ts).total_seconds(), 0.0)
                coverage_ratio = min(covered_seconds / window_seconds, 1.0) if window_seconds > 0 else 0.0

                rows.append(
                    {
                        "user_id": str(group["user_id"].iloc[0]),
                        "session_id": str(group["session_id"].iloc[0]),
                        "stream_id": str(group["stream_id"].iloc[0]),
                        "stream_type": str(group["stream_type"].iloc[0]),
                        "source_vendor": str(group["source_vendor"].iloc[0]),
                        "device_model": str(group["source_device_model"].iloc[0]),
                        "window_size": window_size,
                        "window_start_utc": window_start,
                        "window_end_utc": window_start + pd.Timedelta(freq),
                        "sample_count": int(len(group.index)),
                        "hr_mean": float(hr_values.mean()),
                        "hr_min": float(hr_values.min()),
                        "hr_max": float(hr_values.max()),
                        "hr_std": float(hr_values.std(ddof=0)),
                        "hr_median": float(hr_values.median()),
                        "hr_first": float(hr_values.iloc[0]),
                        "hr_last": float(hr_values.iloc[-1]),
                        "coverage_ratio": float(coverage_ratio),
                        "input_artifact_reference": input_artifact_reference,
                        "run_id": run_id,
                    }
                )

        features = pd.DataFrame(rows)
        if not features.empty:
            features = features.sort_values(["window_size", "window_start_utc"]).reset_index(drop=True)
        return FeatureHandlerOutput(dataframe=features)
