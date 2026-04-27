from __future__ import annotations

from typing import Any

import pandas as pd

from .hr_window import FeatureHandlerOutput, WINDOWS


class AccWindowFeatureBuilder:
    name = "AccWindowFeatureBuilder"

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

                x = group["x_mg"].astype(float)
                y = group["y_mg"].astype(float)
                z = group["z_mg"].astype(float)
                vector = group["vector_magnitude_mg"].astype(float)

                diff_x = x.diff().fillna(0.0)
                diff_y = y.diff().fillna(0.0)
                diff_z = z.diff().fillna(0.0)
                activity_energy = float(((diff_x * diff_x) + (diff_y * diff_y) + (diff_z * diff_z)).sum())

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
                        "mean_x": float(x.mean()),
                        "mean_y": float(y.mean()),
                        "mean_z": float(z.mean()),
                        "std_x": float(x.std(ddof=0)),
                        "std_y": float(y.std(ddof=0)),
                        "std_z": float(z.std(ddof=0)),
                        "min_x": float(x.min()),
                        "min_y": float(y.min()),
                        "min_z": float(z.min()),
                        "max_x": float(x.max()),
                        "max_y": float(y.max()),
                        "max_z": float(z.max()),
                        "vector_magnitude_mean": float(vector.mean()),
                        "vector_magnitude_std": float(vector.std(ddof=0)),
                        "vector_magnitude_max": float(vector.max()),
                        "activity_energy": activity_energy,
                        "input_artifact_reference": input_artifact_reference,
                        "run_id": run_id,
                    }
                )

        features = pd.DataFrame(rows)
        if not features.empty:
            features = features.sort_values(["window_size", "window_start_utc"]).reset_index(drop=True)
        return FeatureHandlerOutput(dataframe=features)
