from __future__ import annotations

from typing import Any

import pandas as pd

from .hr_window import FeatureHandlerOutput, WINDOWS


class EcgWindowFeatureBuilder:
    name = "EcgWindowFeatureBuilder"

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

                ecg = group["ecg_uv"].astype(float)
                max_value = float(ecg.max())
                min_value = float(ecg.min())

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
                        "ecg_mean": float(ecg.mean()),
                        "ecg_std": float(ecg.std(ddof=0)),
                        "ecg_min": min_value,
                        "ecg_max": max_value,
                        "amplitude_range": max_value - min_value,
                        "abs_mean": float(ecg.abs().mean()),
                        "input_artifact_reference": input_artifact_reference,
                        "run_id": run_id,
                    }
                )

        features = pd.DataFrame(rows)
        if not features.empty:
            features = features.sort_values(["window_size", "window_start_utc"]).reset_index(drop=True)
        return FeatureHandlerOutput(dataframe=features)
