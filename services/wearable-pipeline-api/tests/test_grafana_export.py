from __future__ import annotations

import json
import hashlib
import sys
import tempfile
import unittest
from pathlib import Path

import pandas as pd

WEARABLE_PIPELINE_API_ROOT = Path(__file__).resolve().parents[1]
if str(WEARABLE_PIPELINE_API_ROOT) not in sys.path:
    sys.path.insert(0, str(WEARABLE_PIPELINE_API_ROOT))

try:
    from wearable_pipeline_api.pipeline.export_grafana import GrafanaViewsExportStepRunner
    from wearable_pipeline_api.pipeline.state import RunStateStore

    DEPS_AVAILABLE = True
except ModuleNotFoundError:
    DEPS_AVAILABLE = False


@unittest.skipUnless(DEPS_AVAILABLE, "pipeline dependencies are not installed")
class GrafanaExportStepTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.processed_root = self.root / "processed"
        self.state_root = self.root / "pipeline_runs"
        self.grafana_root = self.root / "grafana"
        self.runner = GrafanaViewsExportStepRunner(
            processed_root=self.processed_root,
            state_store=RunStateStore(self.state_root),
            grafana_root=self.grafana_root,
        )

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def _write_ppi(self, session_id: str, rows: list[dict[str, object]]) -> Path:
        target = self.processed_root / "clean_timeseries" / "user_id=1" / "source=polar_verity_sense" / f"session_id={session_id}" / "streams" / "ppi" / "data.parquet"
        target.parent.mkdir(parents=True, exist_ok=True)
        pd.DataFrame(rows).to_parquet(target, index=False)
        return target

    def _write_summary(self, session_id: str) -> Path:
        target = self.processed_root / "window_features" / "user_id=1" / "source=polar_verity_sense" / f"session_id={session_id}" / "session_summary.json"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(
            json.dumps(
                {
                    "session_id": session_id,
                    "status": "partial",
                    "started_at_utc": "2026-05-01T00:00:00Z",
                    "ended_at_utc": "2026-05-01T00:01:00Z",
                    "duration_seconds": 60,
                    "streams_present": ["ppi"],
                    "streams_missing": ["acc"],
                }
            ),
            encoding="utf-8",
        )
        return target

    def test_exports_ppi_and_quality_events(self) -> None:
        session_id = "session-grafana-ppi"
        self._write_ppi(
            session_id,
            [
                {
                    "ts_utc": "2026-05-01T00:00:00Z",
                    "pp_in_ms": 900,
                    "pp_error_estimate": 8,
                    "sample_quality_blocked": False,
                    "sample_quality_skin_contact_missing": False,
                    "sample_quality_tier": "high",
                    "pp_error_band": "strict_lt10ms",
                    "payload_schema": "polar.offline.ppi",
                    "source_vendor": "polar",
                    "source_device_model": "verity_sense",
                },
                {
                    "ts_utc": "2026-05-01T00:00:10Z",
                    "pp_in_ms": 880,
                    "pp_error_estimate": 40,
                    "sample_quality_blocked": True,
                    "sample_quality_skin_contact_missing": True,
                    "sample_quality_tier": "low",
                    "pp_error_band": "high_gt30ms",
                    "payload_schema": "polar.offline.ppi",
                    "source_vendor": "polar",
                    "source_device_model": "verity_sense",
                },
            ],
        )
        self._write_summary(session_id)

        result = self.runner.run_for_session(session_id)

        self.assertEqual(result["status"], "success")
        self.assertEqual(result["normalized_ppi_rows_exported"], 2)
        self.assertGreaterEqual(result["quality_events_rows_exported"], 3)
        self.assertTrue(Path(result["generated_paths"]["normalized_ppi_points_csv"]).exists())
        self.assertTrue(Path(result["generated_paths"]["sessions_json"]).exists())
        session_root = Path(result["generated_paths"]["session_root"])
        self.assertTrue((session_root / "normalized_ppi_points.csv").exists())
        self.assertTrue((session_root / "session.json").exists())
        points = pd.read_csv(result["generated_paths"]["normalized_ppi_points_csv"])
        subset = points[points["session_id"] == session_id]
        self.assertIn("ppi_high", subset.columns)
        self.assertIn("ppi_medium", subset.columns)
        self.assertIn("ppi_low", subset.columns)
        self.assertIn("ppi_trend", subset.columns)
        self.assertEqual(int(subset["ppi_high"].notna().sum()), 1)
        self.assertEqual(int(subset["ppi_low"].notna().sum()), 1)

    def test_missing_optional_columns_writes_nulls_and_warning(self) -> None:
        session_id = "session-grafana-missing-cols"
        self._write_ppi(
            session_id,
            [
                {
                    "ts_utc": "2026-05-01T00:00:00Z",
                    "pp_in_ms": 910,
                }
            ],
        )

        result = self.runner.run_for_session(session_id)

        self.assertEqual(result["normalized_ppi_rows_exported"], 1)
        self.assertTrue(any("missing normalized PPI column" in item for item in result["warnings"]))

    def test_missing_feature_artifacts_does_not_fail(self) -> None:
        session_id = "session-grafana-no-features"
        self._write_ppi(
            session_id,
            [{"ts_utc": "2026-05-01T00:00:00Z", "pp_in_ms": 900}],
        )

        result = self.runner.run_for_session(session_id)

        self.assertIn("missing feature artifacts", result["warnings"])
        self.assertEqual(result["status"], "success")

    def test_idempotent_rerun_keeps_row_counts(self) -> None:
        session_id = "session-grafana-idempotent"
        self._write_ppi(
            session_id,
            [
                {"ts_utc": "2026-05-01T00:00:00Z", "pp_in_ms": 900},
                {"ts_utc": "2026-05-01T00:00:01Z", "pp_in_ms": 890},
            ],
        )

        first = self.runner.run_for_session(session_id)
        second = self.runner.run_for_session(session_id)

        self.assertEqual(first["normalized_ppi_rows_exported"], second["normalized_ppi_rows_exported"])
        self.assertEqual(first["quality_events_rows_exported"], second["quality_events_rows_exported"])

    def test_export_does_not_mutate_source_artifacts(self) -> None:
        session_id = "session-grafana-immutability"
        source_path = self._write_ppi(
            session_id,
            [{"ts_utc": "2026-05-01T00:00:00Z", "pp_in_ms": 900}],
        )
        before_hash = hashlib.sha256(source_path.read_bytes()).hexdigest()

        self.runner.run_for_session(session_id)

        after_hash = hashlib.sha256(source_path.read_bytes()).hexdigest()
        self.assertEqual(before_hash, after_hash)


if __name__ == "__main__":
    unittest.main()
