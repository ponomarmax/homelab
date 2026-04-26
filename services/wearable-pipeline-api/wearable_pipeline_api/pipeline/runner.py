from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

from wearable_pipeline_api.normalizers import HrNormalizer
from wearable_pipeline_api.storage import derive_artifact_paths, discover_hr_raw_files
from wearable_pipeline_api.tracker import StateTracker

logger = logging.getLogger(__name__)


class HrPipelineRunner:
    def __init__(
        self,
        raw_root: Path,
        processed_root: Path,
        tracker: StateTracker,
        normalizer: HrNormalizer | None = None,
    ) -> None:
        self.raw_root = raw_root
        self.processed_root = processed_root
        self.tracker = tracker
        self.normalizer = normalizer or HrNormalizer()

    def run(self) -> dict[str, Any]:
        logger.info("pipeline_hr_normalization_started")
        raw_files = discover_hr_raw_files(self.raw_root)
        logger.info("pipeline_hr_discovered_files", extra={"count": len(raw_files)})

        summary: dict[str, Any] = {
            "discovered": len(raw_files),
            "skipped": 0,
            "processed": 0,
            "failed": 0,
            "artifacts": [],
        }

        for raw_path in raw_files:
            file_size = raw_path.stat().st_size
            last_modified = raw_path.stat().st_mtime
            output_path, report_path = derive_artifact_paths(raw_path, self.raw_root, self.processed_root)

            if self.tracker.should_skip(raw_path, file_size, last_modified):
                summary["skipped"] += 1
                summary["artifacts"].append(
                    {
                        "raw_path": str(raw_path),
                        "output_path": str(output_path),
                        "report_path": str(report_path),
                        "status": "skipped",
                    }
                )
                logger.info("pipeline_hr_skipped", extra={"raw_path": str(raw_path)})
                continue

            try:
                result = self.normalizer.normalize(raw_path)
                output_path.parent.mkdir(parents=True, exist_ok=True)
                result.dataframe.to_parquet(output_path, index=False)
                report_path.write_text(json.dumps(result.report, indent=2), encoding="utf-8")

                self.tracker.mark_processed(raw_path, file_size, last_modified, output_path, report_path)
                summary["processed"] += 1
                summary["artifacts"].append(
                    {
                        "raw_path": str(raw_path),
                        "output_path": str(output_path),
                        "report_path": str(report_path),
                        "status": "processed",
                    }
                )
                logger.info(
                    "pipeline_hr_processed",
                    extra={
                        "raw_path": str(raw_path),
                        "output_path": str(output_path),
                        "report_path": str(report_path),
                    },
                )
            except Exception:
                logger.exception("pipeline_hr_processing_failed", extra={"raw_path": str(raw_path)})
                self.tracker.mark_failed(raw_path, file_size, last_modified, output_path, report_path)
                summary["failed"] += 1
                summary["artifacts"].append(
                    {
                        "raw_path": str(raw_path),
                        "output_path": str(output_path),
                        "report_path": str(report_path),
                        "status": "failed",
                    }
                )

        logger.info(
            "pipeline_hr_normalization_finished",
            extra={
                "discovered": summary["discovered"],
                "skipped": summary["skipped"],
                "processed": summary["processed"],
                "failed": summary["failed"],
            },
        )
        return summary
