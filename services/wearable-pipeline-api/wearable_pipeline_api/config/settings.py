from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

SERVICE_NAME = "wearable-pipeline-api"
HEALTH_PATH = "/health"
PIPELINE_RUN_PATH = "/api/v1/pipeline/run"
LEGACY_NORMALIZE_HR_PATH = "/api/v1/pipeline/normalize/hr"

ENV_HOST = "WEARABLE_PIPELINE_API_HOST"
ENV_PORT = "WEARABLE_PIPELINE_API_PORT"
ENV_RAW_ROOT = "RAW_ROOT"
ENV_PROCESSED_ROOT = "PROCESSED_ROOT"
ENV_PIPELINE_STATE_ROOT = "PIPELINE_STATE_ROOT"
ENV_LOG_LEVEL = "LOG_LEVEL"
ENV_L0_CROSS_STREAM_MAX_START_DELTA_SECONDS = "L0_CROSS_STREAM_MAX_START_DELTA_SECONDS"
ENV_L0_CROSS_STREAM_MAX_END_DELTA_SECONDS = "L0_CROSS_STREAM_MAX_END_DELTA_SECONDS"
ENV_L0_CROSS_STREAM_MIN_OVERLAP_RATIO = "L0_CROSS_STREAM_MIN_OVERLAP_RATIO"
ENV_L0_CROSS_STREAM_MIN_ANCHOR_STREAMS = "L0_CROSS_STREAM_MIN_ANCHOR_STREAMS"
ENV_L0_CROSS_STREAM_ANCHOR_STREAMS = "L0_CROSS_STREAM_ANCHOR_STREAMS"

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8091
DEFAULT_RAW_ROOT = "/data/wearable/raw"
DEFAULT_PROCESSED_ROOT = "/data/wearable/processed"
DEFAULT_PIPELINE_STATE_ROOT = "/data/wearable/pipeline_runs"
DEFAULT_LOG_LEVEL = "INFO"
DEFAULT_L0_CROSS_STREAM_MAX_START_DELTA_SECONDS = 10.0
DEFAULT_L0_CROSS_STREAM_MAX_END_DELTA_SECONDS = 10.0
DEFAULT_L0_CROSS_STREAM_MIN_OVERLAP_RATIO = 0.5
DEFAULT_L0_CROSS_STREAM_MIN_ANCHOR_STREAMS = 2
DEFAULT_L0_CROSS_STREAM_ANCHOR_STREAMS = ("acc", "gyro", "mag", "ppg")


@dataclass(frozen=True)
class Settings:
    host: str
    port: int
    raw_root: Path
    processed_root: Path
    pipeline_state_root: Path
    log_level: str
    l0_cross_stream_max_start_delta_seconds: float = DEFAULT_L0_CROSS_STREAM_MAX_START_DELTA_SECONDS
    l0_cross_stream_max_end_delta_seconds: float = DEFAULT_L0_CROSS_STREAM_MAX_END_DELTA_SECONDS
    l0_cross_stream_min_overlap_ratio: float = DEFAULT_L0_CROSS_STREAM_MIN_OVERLAP_RATIO
    l0_cross_stream_min_anchor_streams: int = DEFAULT_L0_CROSS_STREAM_MIN_ANCHOR_STREAMS
    l0_cross_stream_anchor_streams: tuple[str, ...] = DEFAULT_L0_CROSS_STREAM_ANCHOR_STREAMS

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            host=os.environ.get(ENV_HOST, DEFAULT_HOST),
            port=int(os.environ.get(ENV_PORT, str(DEFAULT_PORT))),
            raw_root=Path(os.environ.get(ENV_RAW_ROOT, DEFAULT_RAW_ROOT)),
            processed_root=Path(os.environ.get(ENV_PROCESSED_ROOT, DEFAULT_PROCESSED_ROOT)),
            pipeline_state_root=Path(os.environ.get(ENV_PIPELINE_STATE_ROOT, DEFAULT_PIPELINE_STATE_ROOT)),
            log_level=os.environ.get(ENV_LOG_LEVEL, DEFAULT_LOG_LEVEL),
            l0_cross_stream_max_start_delta_seconds=float(
                os.environ.get(ENV_L0_CROSS_STREAM_MAX_START_DELTA_SECONDS, str(DEFAULT_L0_CROSS_STREAM_MAX_START_DELTA_SECONDS))
            ),
            l0_cross_stream_max_end_delta_seconds=float(
                os.environ.get(ENV_L0_CROSS_STREAM_MAX_END_DELTA_SECONDS, str(DEFAULT_L0_CROSS_STREAM_MAX_END_DELTA_SECONDS))
            ),
            l0_cross_stream_min_overlap_ratio=float(
                os.environ.get(ENV_L0_CROSS_STREAM_MIN_OVERLAP_RATIO, str(DEFAULT_L0_CROSS_STREAM_MIN_OVERLAP_RATIO))
            ),
            l0_cross_stream_min_anchor_streams=int(
                os.environ.get(ENV_L0_CROSS_STREAM_MIN_ANCHOR_STREAMS, str(DEFAULT_L0_CROSS_STREAM_MIN_ANCHOR_STREAMS))
            ),
            l0_cross_stream_anchor_streams=tuple(
                item.strip().lower()
                for item in os.environ.get(
                    ENV_L0_CROSS_STREAM_ANCHOR_STREAMS,
                    ",".join(DEFAULT_L0_CROSS_STREAM_ANCHOR_STREAMS),
                ).split(",")
                if item.strip()
            ),
        )
