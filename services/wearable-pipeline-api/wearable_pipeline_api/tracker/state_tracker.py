from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


@dataclass
class TrackerRecord:
    raw_path: str
    file_size: int
    last_modified: float
    processed_at: str
    output_path: str
    report_path: str
    status: str


class StateTracker:
    def __init__(self, state_root: Path) -> None:
        self._state_file = state_root / "state.json"
        self._state_file.parent.mkdir(parents=True, exist_ok=True)
        self._state = self._load()

    @property
    def state_file(self) -> Path:
        return self._state_file

    def _load(self) -> dict[str, dict[str, object]]:
        if not self._state_file.exists():
            return {}
        try:
            data = json.loads(self._state_file.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return {}
        return data if isinstance(data, dict) else {}

    def _save(self) -> None:
        self._state_file.write_text(json.dumps(self._state, indent=2, sort_keys=True), encoding="utf-8")

    def should_skip(self, raw_path: Path, file_size: int, last_modified: float) -> bool:
        existing = self._state.get(str(raw_path))
        if not existing:
            return False
        return (
            existing.get("status") == "processed"
            and existing.get("file_size") == file_size
            and existing.get("last_modified") == last_modified
        )

    def update(self, record: TrackerRecord) -> None:
        self._state[record.raw_path] = asdict(record)
        self._save()

    def mark_processed(
        self,
        raw_path: Path,
        file_size: int,
        last_modified: float,
        output_path: Path,
        report_path: Path,
    ) -> None:
        self.update(
            TrackerRecord(
                raw_path=str(raw_path),
                file_size=file_size,
                last_modified=last_modified,
                processed_at=utc_now_iso(),
                output_path=str(output_path),
                report_path=str(report_path),
                status="processed",
            )
        )

    def mark_failed(
        self,
        raw_path: Path,
        file_size: int,
        last_modified: float,
        output_path: Path,
        report_path: Path,
    ) -> None:
        self.update(
            TrackerRecord(
                raw_path=str(raw_path),
                file_size=file_size,
                last_modified=last_modified,
                processed_at=utc_now_iso(),
                output_path=str(output_path),
                report_path=str(report_path),
                status="failed",
            )
        )
