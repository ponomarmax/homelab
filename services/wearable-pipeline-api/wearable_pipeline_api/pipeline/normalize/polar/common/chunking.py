from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from .base import parse_jsonl_chunks


@dataclass(frozen=True)
class ChunkContext:
    chunk: dict[str, Any]
    line_number: int
    payload_schema: str
    source: dict[str, Any]
    collection: dict[str, Any]
    time_info: dict[str, Any]
    server: dict[str, Any]
    payload: dict[str, Any]
    samples: list[dict[str, Any]]


def iter_chunks_for_schema(raw_path: Path, payload_schema_expected: str) -> tuple[Iterable[ChunkContext], list[str]]:
    chunks, warnings = parse_jsonl_chunks(raw_path)
    contexts: list[ChunkContext] = []
    for chunk in chunks:
        line_number = int(chunk.get("__line_number") or 0)
        payload_schema = str(((chunk.get("transport") or {}).get("payload_schema") or "")).strip().lower()
        if payload_schema != payload_schema_expected:
            continue
        source = chunk.get("source") if isinstance(chunk.get("source"), dict) else {}
        collection = chunk.get("collection") if isinstance(chunk.get("collection"), dict) else {}
        time_info = chunk.get("time") if isinstance(chunk.get("time"), dict) else {}
        server = chunk.get("server") if isinstance(chunk.get("server"), dict) else {}
        payload = chunk.get("payload") if isinstance(chunk.get("payload"), dict) else {}
        samples_raw = payload.get("samples")
        samples = samples_raw if isinstance(samples_raw, list) else []
        contexts.append(
            ChunkContext(
                chunk=chunk,
                line_number=line_number,
                payload_schema=payload_schema,
                source=source,
                collection=collection,
                time_info=time_info,
                server=server,
                payload=payload,
                samples=samples,
            )
        )
    return contexts, warnings
