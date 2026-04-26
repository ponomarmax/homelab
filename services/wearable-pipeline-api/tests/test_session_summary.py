from __future__ import annotations

import json
import math
import sys
import tempfile
import unittest
from pathlib import Path

import pandas as pd

WEARABLE_PIPELINE_API_ROOT = Path(__file__).resolve().parents[1]
if str(WEARABLE_PIPELINE_API_ROOT) not in sys.path:
    sys.path.insert(0, str(WEARABLE_PIPELINE_API_ROOT))

try:
    from wearable_pipeline_api.pipeline.state import RunStateStore
    from wearable_pipeline_api.pipeline.summary import SessionSummaryStepRunner

    DEPS_AVAILABLE = True
except ModuleNotFoundError:
    DEPS_AVAILABLE = False


def write_window_features(
    processed_root: Path,
    *,
    session_id: str,
    rows: list[dict[str, object]],
) -> Path:
    target = (
        processed_root
        / "window_features"
        / "user_id=1"
        / "source=polar_verity_sense"
        / f"session_id={session_id}"
        / "streams"
        / "hr"
        / "data.parquet"
    )
    target.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_parquet(target, index=False)
    return target


@unittest.skipUnless(DEPS_AVAILABLE, "pipeline dependencies are not installed")
class SessionSummaryStepTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.processed_root = self.root / "processed"
        self.state_root = self.root / "pipeline_runs"
        self.runner = SessionSummaryStepRunner(
            processed_root=self.processed_root,
            state_store=RunStateStore(self.state_root),
        )

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def _read_summary(self, session_id: str) -> dict[str, object]:
        summary_path = (
            self.processed_root
            / "window_features"
            / "user_id=1"
            / "source=polar_verity_sense"
            / f"session_id={session_id}"
            / "session_summary.json"
        )
        self.assertTrue(summary_path.exists())
        return json.loads(summary_path.read_text(encoding="utf-8"))

    def test_full_window_sets_builds_success_summary(self) -> None:
        write_window_features(
            self.processed_root,
            session_id="session-full",
            rows=[
                {"window_size": "30s", "window_start_utc": "2026-04-25T10:00:00Z", "window_end_utc": "2026-04-25T10:00:30Z", "hr_mean": 70},
                {"window_size": "30s", "window_start_utc": "2026-04-25T10:00:30Z", "window_end_utc": "2026-04-25T10:01:00Z", "hr_mean": 80},
                {"window_size": "30s", "window_start_utc": "2026-04-25T10:01:00Z", "window_end_utc": "2026-04-25T10:01:30Z", "hr_mean": 90},
                {"window_size": "1m", "window_start_utc": "2026-04-25T10:00:00Z", "window_end_utc": "2026-04-25T10:01:00Z", "hr_mean": 75},
                {"window_size": "5m", "window_start_utc": "2026-04-25T10:00:00Z", "window_end_utc": "2026-04-25T10:05:00Z", "hr_mean": 80},
            ],
        )

        result = self.runner.run_for_session("session-full")
        self.assertEqual(result["status"], "success")

        payload = self._read_summary("session-full")
        hr = payload["streams"]["hr"]
        self.assertEqual(hr["status"], "success")
        self.assertEqual(hr["coverage"]["window_counts"]["30s"], 3)
        self.assertAlmostEqual(hr["hr_statistics"]["mean"], 80.0)
        self.assertAlmostEqual(hr["trend"]["delta"], 20.0)
        self.assertEqual(payload["overall_quality"], "good")

    def test_missing_window_size_marks_partial(self) -> None:
        write_window_features(
            self.processed_root,
            session_id="session-missing-size",
            rows=[
                {"window_size": "30s", "window_start_utc": "2026-04-25T10:00:00Z", "window_end_utc": "2026-04-25T10:00:30Z", "hr_mean": 70},
                {"window_size": "30s", "window_start_utc": "2026-04-25T10:00:30Z", "window_end_utc": "2026-04-25T10:01:00Z", "hr_mean": 72},
                {"window_size": "30s", "window_start_utc": "2026-04-25T10:01:00Z", "window_end_utc": "2026-04-25T10:01:30Z", "hr_mean": 73},
                {"window_size": "1m", "window_start_utc": "2026-04-25T10:00:00Z", "window_end_utc": "2026-04-25T10:01:00Z", "hr_mean": 71},
            ],
        )

        result = self.runner.run_for_session("session-missing-size")
        self.assertEqual(result["status"], "partial")

        payload = self._read_summary("session-missing-size")
        hr = payload["streams"]["hr"]
        self.assertEqual(hr["status"], "partial")
        self.assertEqual(hr["data_quality"]["status"], "partial")
        self.assertEqual(hr["data_quality"]["missing_windows"], 1)
        self.assertIn("missing expected window size: 5m", hr["warnings"])

    def test_empty_dataset_marks_missing(self) -> None:
        write_window_features(
            self.processed_root,
            session_id="session-empty",
            rows=[],
        )

        result = self.runner.run_for_session("session-empty")
        self.assertEqual(result["status"], "partial")

        payload = self._read_summary("session-empty")
        hr = payload["streams"]["hr"]
        self.assertEqual(hr["status"], "missing")
        self.assertEqual(hr["data_quality"]["status"], "unknown")
        self.assertIn("empty dataset", hr["warnings"])

    def test_nan_handling_marks_partial_and_tracks_anomalies(self) -> None:
        write_window_features(
            self.processed_root,
            session_id="session-nan",
            rows=[
                {"window_size": "30s", "window_start_utc": "2026-04-25T10:00:00Z", "window_end_utc": "2026-04-25T10:00:30Z", "hr_mean": 70},
                {"window_size": "30s", "window_start_utc": "2026-04-25T10:00:30Z", "window_end_utc": "2026-04-25T10:01:00Z", "hr_mean": math.nan},
                {"window_size": "30s", "window_start_utc": "2026-04-25T10:01:00Z", "window_end_utc": "2026-04-25T10:01:30Z", "hr_mean": 75},
            ],
        )

        result = self.runner.run_for_session("session-nan")
        self.assertEqual(result["status"], "partial")

        payload = self._read_summary("session-nan")
        hr = payload["streams"]["hr"]
        self.assertEqual(hr["status"], "partial")
        self.assertEqual(hr["data_quality"]["anomaly_count"], 1)
        self.assertIn("any NaN values detected", hr["warnings"])

    def test_summary_json_structure_validation(self) -> None:
        write_window_features(
            self.processed_root,
            session_id="session-schema",
            rows=[
                {"window_size": "30s", "window_start_utc": "2026-04-25T10:00:00Z", "window_end_utc": "2026-04-25T10:00:30Z", "hr_mean": 65},
                {"window_size": "30s", "window_start_utc": "2026-04-25T10:00:30Z", "window_end_utc": "2026-04-25T10:01:00Z", "hr_mean": 68},
                {"window_size": "30s", "window_start_utc": "2026-04-25T10:01:00Z", "window_end_utc": "2026-04-25T10:01:30Z", "hr_mean": 72},
            ],
        )
        self.runner.run_for_session("session-schema")

        payload = self._read_summary("session-schema")
        self.assertEqual(payload["schema_version"], "1.0")
        self.assertEqual(payload["session_id"], "session-schema")
        self.assertIn("generated_at_utc", payload)
        self.assertEqual(set(payload["inputs"].keys()), {"window_feature_paths", "available_window_sizes"})
        self.assertIn("hr", payload["streams"])
        self.assertIn(payload["overall_quality"], {"good", "partial", "poor", "unknown"})


if __name__ == "__main__":
    unittest.main()
