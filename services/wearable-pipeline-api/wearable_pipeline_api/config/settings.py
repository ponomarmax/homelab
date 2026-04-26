from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

SERVICE_NAME = "wearable-pipeline-api"
HEALTH_PATH = "/health"
NORMALIZE_HR_PATH = "/api/v1/pipeline/normalize/hr"

ENV_HOST = "WEARABLE_PIPELINE_API_HOST"
ENV_PORT = "WEARABLE_PIPELINE_API_PORT"
ENV_RAW_ROOT = "RAW_ROOT"
ENV_PROCESSED_ROOT = "PROCESSED_ROOT"
ENV_PIPELINE_STATE_ROOT = "PIPELINE_STATE_ROOT"
ENV_LOG_LEVEL = "LOG_LEVEL"

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8091
DEFAULT_RAW_ROOT = "/data/wearable/raw"
DEFAULT_PROCESSED_ROOT = "/data/wearable/processed"
DEFAULT_PIPELINE_STATE_ROOT = "/data/wearable/pipeline_runs"
DEFAULT_LOG_LEVEL = "INFO"


@dataclass(frozen=True)
class Settings:
    host: str
    port: int
    raw_root: Path
    processed_root: Path
    pipeline_state_root: Path
    log_level: str

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            host=os.environ.get(ENV_HOST, DEFAULT_HOST),
            port=int(os.environ.get(ENV_PORT, str(DEFAULT_PORT))),
            raw_root=Path(os.environ.get(ENV_RAW_ROOT, DEFAULT_RAW_ROOT)),
            processed_root=Path(os.environ.get(ENV_PROCESSED_ROOT, DEFAULT_PROCESSED_ROOT)),
            pipeline_state_root=Path(os.environ.get(ENV_PIPELINE_STATE_ROOT, DEFAULT_PIPELINE_STATE_ROOT)),
            log_level=os.environ.get(ENV_LOG_LEVEL, DEFAULT_LOG_LEVEL),
        )
