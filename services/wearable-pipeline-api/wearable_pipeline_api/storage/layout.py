from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


class RawPathError(ValueError):
    pass


def _extract_value(segment: str, prefix: str) -> str:
    if not segment.startswith(prefix):
        raise RawPathError(f"Expected segment with prefix '{prefix}', got '{segment}'")
    return segment[len(prefix) :]


@dataclass(frozen=True)
class RawPathMetadata:
    user_id: str
    source: str
    session_id: str
    stream_type: str


def parse_raw_path(raw_path: Path, raw_root: Path) -> RawPathMetadata:
    relative = raw_path.relative_to(raw_root)
    parts = relative.parts
    if len(parts) < 7:
        raise RawPathError(f"Raw path structure is invalid: {raw_path}")

    user_id = _extract_value(parts[0], "user_id=")
    source = _extract_value(parts[1], "source=")
    session_id = _extract_value(parts[3], "session_id=")
    stream_type = parts[5]
    return RawPathMetadata(user_id=user_id, source=source, session_id=session_id, stream_type=stream_type)


def derive_artifact_paths(raw_path: Path, raw_root: Path, processed_root: Path) -> tuple[Path, Path]:
    meta = parse_raw_path(raw_path, raw_root)
    output_dir = (
        processed_root
        / "clean_timeseries"
        / f"user_id={meta.user_id}"
        / f"source={meta.source}"
        / f"session_id={meta.session_id}"
        / "streams"
        / meta.stream_type
    )
    return output_dir / "data.parquet", output_dir / "time_alignment_report.json"


def derive_window_feature_path(raw_path: Path, raw_root: Path, processed_root: Path) -> Path:
    meta = parse_raw_path(raw_path, raw_root)
    output_dir = (
        processed_root
        / "window_features"
        / f"user_id={meta.user_id}"
        / f"source={meta.source}"
        / f"session_id={meta.session_id}"
        / "streams"
        / meta.stream_type
    )
    return output_dir / "data.parquet"
