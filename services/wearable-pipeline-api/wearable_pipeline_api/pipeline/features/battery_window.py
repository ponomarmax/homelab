from __future__ import annotations

from typing import Any

import pandas as pd

from .hr_window import FeatureHandlerOutput, WINDOWS


class BatteryWindowFeatureBuilder:
    name = "BatteryWindowFeatureBuilder"

    def handle(self, clean_df: pd.DataFrame, run_id: str, input_artifact_reference: str) -> FeatureHandlerOutput:
        if clean_df.empty:
            return FeatureHandlerOutput(dataframe=pd.DataFrame())

        df = clean_df.copy()
        df["ts_utc"] = pd.to_datetime(df["ts_utc"], utc=True, errors="coerce")
        df = df.dropna(subset=["ts_utc"]).sort_values("ts_utc").reset_index(drop=True)

        rows: list[dict[str, Any]] = []
        for window_size, freq in WINDOWS:
            grouped = df.groupby(df["ts_utc"].dt.floor(freq), dropna=False)
            for window_start, group in grouped:
                if pd.isna(window_start):
                    continue

                levels = group["level_percent"].astype(float)
                first_level = float(levels.iloc[0])
                last_level = float(levels.iloc[-1])
                first_ts = group["ts_utc"].iloc[0]
                last_ts = group["ts_utc"].iloc[-1]
                duration_hours = max((last_ts - first_ts).total_seconds() / 3600.0, 0.0)
                drain_per_hour = None
                if len(levels.index) >= 2 and duration_hours > 0:
                    drain_per_hour = (first_level - last_level) / duration_hours

                rows.append(
                    {
                        "user_id": str(group["user_id"].iloc[0]),
                        "session_id": str(group["session_id"].iloc[0]),
                        "stream_id": str(group["stream_id"].iloc[0]),
                        "stream_type": str(group["stream_type"].iloc[0]),
                        "payload_schema": str(group.get("payload_schema", pd.Series([""])).iloc[0]),
                        "source_vendor": str(group["source_vendor"].iloc[0]),
                        "device_model": str(group["source_device_model"].iloc[0]),
                        "window_size": window_size,
                        "window_start_utc": window_start,
                        "window_end_utc": window_start + pd.Timedelta(freq),
                        "sample_count": int(len(group.index)),
                        "level_min": float(levels.min()),
                        "level_max": float(levels.max()),
                        "level_mean": float(levels.mean()),
                        "level_first": first_level,
                        "level_last": last_level,
                        "samples_count": int(len(group.index)),
                        "drain_per_hour": float(drain_per_hour) if drain_per_hour is not None else None,
                        "input_artifact_reference": input_artifact_reference,
                        "run_id": run_id,
                    }
                )

        features = pd.DataFrame(rows)
        if not features.empty:
            features = features.sort_values(["window_size", "window_start_utc"]).reset_index(drop=True)
        return FeatureHandlerOutput(dataframe=features)
