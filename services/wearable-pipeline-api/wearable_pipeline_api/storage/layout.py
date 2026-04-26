from __future__ import annotations

from pathlib import Path


class RawPathError(ValueError):
    pass


def _extract_value(segment: str, prefix: str) -> str:
    if not segment.startswith(prefix):
        raise RawPathError(f"Expected segment with prefix '{prefix}', got '{segment}'")
    return segment[len(prefix) :]


def derive_artifact_paths(raw_path: Path, raw_root: Path, processed_root: Path) -> tuple[Path, Path]:
    relative = raw_path.relative_to(raw_root)
    parts = relative.parts
    if len(parts) < 7:
        raise RawPathError(f"Raw path structure is invalid: {raw_path}")

    user_id = _extract_value(parts[0], "user_id=")
    source = _extract_value(parts[1], "source=")
    session_id = _extract_value(parts[3], "session_id=")

    output_dir = (
        processed_root
        / "clean_timeseries"
        / f"user_id={user_id}"
        / f"source={source}"
        / f"session_id={session_id}"
        / "streams"
        / "hr"
    )
    return output_dir / "data.parquet", output_dir / "time_alignment_report.json"
