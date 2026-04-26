from __future__ import annotations

import json
import re
from datetime import datetime
from pathlib import Path


def sanitize_segment(value: str) -> str:
    return re.sub(r"[^a-zA-Z0-9._-]", "_", value)


def _source_segment(vendor: str, device_model: str) -> str:
    return f"{sanitize_segment(vendor)}_{sanitize_segment(device_model)}"


def build_chunks_path(
    raw_root: Path,
    user_id: str,
    vendor: str,
    device_model: str,
    received_at_server: str,
    session_id: str,
    stream_type: str,
) -> Path:
    date_segment = datetime.fromisoformat(received_at_server.replace("Z", "+00:00")).date().isoformat()
    return (
        raw_root
        / f"user_id={sanitize_segment(user_id)}"
        / f"source={_source_segment(vendor, device_model)}"
        / f"date={date_segment}"
        / f"session_id={sanitize_segment(session_id)}"
        / "streams"
        / sanitize_segment(stream_type)
        / "chunks.jsonl"
    )


def append_chunk_jsonl(
    raw_root: Path,
    user_id: str,
    vendor: str,
    device_model: str,
    received_at_server: str,
    session_id: str,
    stream_type: str,
    record: dict[str, object],
) -> str:
    target_file = build_chunks_path(
        raw_root=raw_root,
        user_id=user_id,
        vendor=vendor,
        device_model=device_model,
        received_at_server=received_at_server,
        session_id=session_id,
        stream_type=stream_type,
    )
    target_file.parent.mkdir(parents=True, exist_ok=True)

    raw_line = json.dumps(record, separators=(",", ":"), ensure_ascii=False)
    with target_file.open("a", encoding="utf-8") as handle:
        handle.write(raw_line)
        handle.write("\n")

    return str(target_file)
