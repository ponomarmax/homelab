from __future__ import annotations

import os
from pathlib import Path

SERVICE_NAME = "wearable-ingestion-api"
HEALTH_PATH = "/healthz"
UPLOAD_PATH = "/upload-chunk"

ENV_HOST = "WEARABLE_INGESTION_API_HOST"
ENV_PORT = "WEARABLE_INGESTION_API_PORT"
ENV_RAW_ROOT = "WEARABLE_INGESTION_RAW_DATA_PATH"

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8090
DEFAULT_RAW_ROOT = "/data/wearable/raw"


def resolve_host() -> str:
    return os.environ.get(ENV_HOST, DEFAULT_HOST)


def resolve_port() -> int:
    return int(os.environ.get(ENV_PORT, str(DEFAULT_PORT)))


def resolve_raw_root_from_env() -> Path:
    raw_root = os.environ.get(ENV_RAW_ROOT)
    if raw_root:
        return Path(raw_root)
    return Path(DEFAULT_RAW_ROOT)
