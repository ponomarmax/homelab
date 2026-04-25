from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


class ContractModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class UploadChunkTime(ContractModel):
    device_time_reference: str | None = Field(
        default=None, min_length=1, description="Opaque device time reference from collector."
    )
    received_at_collector: datetime = Field(..., description="Collector receive time.")
    uploaded_at_collector: datetime = Field(..., description="Collector upload time.")
    received_at_server: datetime | None = Field(
        default=None,
        description="Optional server receive time from caller; ingestion service does not mutate it.",
    )


class UploadChunkTransport(ContractModel):
    encoding: Literal["json"] = Field(..., description="Transport encoding.")
    compression: Literal["none", "gzip"] | None = Field(
        default=None, description="Transport compression."
    )
    payload_schema: str = Field(..., min_length=1, description="Payload schema name.")
    payload_version: str = Field(..., min_length=1, description="Payload schema version.")


class UploadChunkRequest(ContractModel):
    schema_version: Literal["1.0"] = Field(..., description="Upload chunk transport contract version.")
    chunk_id: str = Field(..., min_length=1, description="Unique chunk id from collector.")
    session_id: str = Field(..., min_length=1, description="Session id reference.")
    stream_id: str = Field(..., min_length=1, description="Stream id reference.")
    sequence: int = Field(..., ge=1, description="Monotonic chunk sequence number.")
    time: UploadChunkTime = Field(..., description="Collector/server transport timing metadata.")
    transport: UploadChunkTransport = Field(..., description="Transport metadata for payload.")
    payload: dict[str, Any] = Field(
        ..., description="Opaque stream-defined payload retained exactly as provided."
    )


class SessionCollector(ContractModel):
    collector_id: str = Field(..., min_length=1)
    runtime_type: Literal["ios", "android", "desktop", "server_import"]
    app_version: str = Field(..., min_length=1)
    build_version: str | None = Field(default=None, min_length=1)


class SessionDevice(ContractModel):
    vendor: Literal["polar", "muse", "other"]
    model: str = Field(..., min_length=1)
    device_id: str = Field(..., min_length=1)


class SessionTime(ContractModel):
    started_at_source: datetime = Field(..., description="Source-side session start time.")
    started_at_server: datetime | None = Field(default=None, description="Server-side session start time.")


class SessionMetadataDetails(ContractModel):
    notes: str | None = None
    tags: list[str] | None = None


class SessionMetadata(ContractModel):
    schema_version: Literal["1.0"]
    session_id: str = Field(..., min_length=1)
    device_session_id: str | None = Field(default=None, min_length=1)
    session_mode: Literal["online_live", "offline_recording", "file_import", "playback"]
    collector: SessionCollector
    device: SessionDevice
    time: SessionTime
    metadata: SessionMetadataDetails | None = None


class StreamDescriptorMetadata(ContractModel):
    sample_rate_hz: float | None = Field(default=None, gt=0)
    units: str | None = Field(default=None, min_length=1)
    channels: list[str] | None = Field(default=None)
    notes: str | None = Field(default=None)


class StreamDescriptor(ContractModel):
    schema_version: Literal["1.0"]
    stream_id: str = Field(..., min_length=1)
    session_id: str = Field(..., min_length=1)
    stream_family: Literal["cardio", "motion", "neural", "optical", "derived", "quality", "marker", "unknown"]
    stream_type: Literal[
        "hr",
        "ppi",
        "ppg",
        "acc",
        "gyro",
        "mag",
        "eeg",
        "optics",
        "fnirs",
        "marker",
        "unknown",
    ]
    origin: Literal["raw", "vendor_processed", "server_derived"]
    mode: Literal["online_live", "offline_recording", "file_import", "playback"]
    payload_schema: str = Field(..., min_length=1)
    payload_version: str = Field(..., min_length=1)
    metadata: StreamDescriptorMetadata | None = None


class AckStorage(ContractModel):
    raw_persisted: bool = Field(..., description="Whether raw JSONL append succeeded.")
    storage_path: str | None = Field(default=None, min_length=1, description="Filesystem path to JSONL file.")


class AckResponse(ContractModel):
    accepted: Literal[True] = True
    status: Literal["accepted", "duplicate", "rejected"] = "accepted"
    chunk_id: str = Field(..., min_length=1)
    session_id: str = Field(..., min_length=1)
    stream_id: str = Field(..., min_length=1)
    received_at_server: str = Field(..., description="Server timestamp when request was accepted.")
    storage: AckStorage
    message: str | None = None


class ErrorDetail(ContractModel):
    field: str = Field(..., min_length=1)
    issue: str = Field(..., min_length=1)


class ErrorResponse(ContractModel):
    accepted: Literal[False] = False
    status: Literal["rejected"] = "rejected"
    error_code: Literal["validation_error", "unsupported_schema", "persistence_error", "malformed_request"]
    message: str = Field(..., min_length=1)
    details: list[ErrorDetail] | None = None
