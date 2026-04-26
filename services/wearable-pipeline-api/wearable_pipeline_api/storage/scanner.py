from __future__ import annotations

from pathlib import Path


def discover_hr_raw_files(raw_root: Path) -> list[Path]:
    if not raw_root.exists():
        return []
    files = [path for path in raw_root.glob("**/streams/hr/chunks.jsonl") if path.is_file()]
    return sorted(files)


def discover_raw_stream_files(raw_root: Path) -> list[Path]:
    if not raw_root.exists():
        return []
    files = [path for path in raw_root.glob("**/session_id=*/streams/*/chunks.jsonl") if path.is_file()]
    return sorted(files)
