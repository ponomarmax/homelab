from __future__ import annotations

import json
from pathlib import Path

from .types import StreamContext


STREAM_GLOB = "**/session_id=*/streams/*/chunks.jsonl"


def _extract_segment(parts: tuple[str, ...], prefix: str) -> str:
    for part in parts:
        if part.startswith(prefix):
            return part[len(prefix) :]
    return ""


def _peek_source(raw_path: Path) -> tuple[str, str]:
    with raw_path.open("r", encoding="utf-8") as handle:
        for line in handle:
            payload = line.strip()
            if not payload:
                continue
            try:
                chunk = json.loads(payload)
            except json.JSONDecodeError:
                continue
            if not isinstance(chunk, dict):
                continue
            source = chunk.get("source") if isinstance(chunk.get("source"), dict) else {}
            vendor = str(source.get("vendor") or "").strip().lower()
            device_model = str(source.get("device_model") or "").strip().lower()
            return vendor, device_model
    return "", ""


def discover_session_streams(raw_root: Path) -> dict[str, list[StreamContext]]:
    if not raw_root.exists():
        return {}

    sessions: dict[str, list[StreamContext]] = {}
    raw_files = sorted(path for path in raw_root.glob(STREAM_GLOB) if path.is_file())

    for raw_path in raw_files:
        relative = raw_path.relative_to(raw_root)
        parts = relative.parts
        if len(parts) < 7:
            continue

        session_id = _extract_segment(parts, "session_id=")
        stream_type = raw_path.parent.name
        user_id = _extract_segment(parts, "user_id=")
        source = _extract_segment(parts, "source=")
        source_vendor, device_model = _peek_source(raw_path)

        if not session_id or not stream_type:
            continue

        stream = StreamContext(
            session_id=session_id,
            stream_type=stream_type,
            raw_path=str(raw_path),
            user_id=user_id,
            source=source,
            source_vendor=source_vendor,
            device_model=device_model,
        )
        sessions.setdefault(session_id, []).append(stream)

    return sessions
