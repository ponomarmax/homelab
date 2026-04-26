from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from wearable_pipeline_api.pipeline.common import StepRunRecord


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


class RunStateStore:
    def __init__(self, state_root: Path) -> None:
        self.state_root = state_root

    def new_run_id(self) -> str:
        return uuid4().hex

    def write(self, record: StepRunRecord) -> Path:
        step_dir = self.state_root / record.step_name
        step_dir.mkdir(parents=True, exist_ok=True)
        target = step_dir / f"{record.run_id}.json"
        target.write_text(json.dumps(record.as_dict(), indent=2), encoding="utf-8")
        return target
