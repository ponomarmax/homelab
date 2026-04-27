from __future__ import annotations

import json
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
    stream_dir: str,
    rows: list[dict[str, object]],
    source: str = "polar_h10",
    date_partition: str | None = None,
) -> Path:
    base = processed_root / "window_features" / "user_id=1" / f"source={source}"
    if date_partition:
        base = base / f"date={date_partition}"
    target = base / f"session_id={session_id}" / "streams" / stream_dir / "data.parquet"
    target.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_parquet(target, index=False)
    return target


def write_battery_clean_timeseries(
    processed_root: Path,
    *,
    session_id: str,
    stream_dir: str = "unknown",
    rows: list[dict[str, object]],
) -> Path:
    target = (
        processed_root
        / "clean_timeseries"
        / "user_id=1"
        / "source=polar_h10"
        / f"session_id={session_id}"
        / "streams"
        / stream_dir
        / "data.parquet"
    )
    target.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_parquet(target, index=False)
    return target


def build_hr_rows() -> list[dict[str, object]]:
    return [
        {
            "window_size": "30s",
            "window_start_utc": "2026-04-25T10:00:00Z",
            "window_end_utc": "2026-04-25T10:00:30Z",
            "sample_count": 10,
            "hr_mean": 70,
            "stream_type": "hr",
            "payload_schema": "polar.hr",
            "source_vendor": "polar",
            "device_model": "h10",
        },
        {
            "window_size": "30s",
            "window_start_utc": "2026-04-25T10:00:30Z",
            "window_end_utc": "2026-04-25T10:01:00Z",
            "sample_count": 10,
            "hr_mean": 80,
            "stream_type": "hr",
            "payload_schema": "polar.hr",
            "source_vendor": "polar",
            "device_model": "h10",
        },
        {
            "window_size": "30s",
            "window_start_utc": "2026-04-25T10:01:00Z",
            "window_end_utc": "2026-04-25T10:01:30Z",
            "sample_count": 10,
            "hr_mean": 90,
            "stream_type": "hr",
            "payload_schema": "polar.hr",
            "source_vendor": "polar",
            "device_model": "h10",
        },
        {
            "window_size": "1m",
            "window_start_utc": "2026-04-25T10:00:00Z",
            "window_end_utc": "2026-04-25T10:01:00Z",
            "sample_count": 20,
            "hr_mean": 75,
            "stream_type": "hr",
            "payload_schema": "polar.hr",
            "source_vendor": "polar",
            "device_model": "h10",
        },
        {
            "window_size": "5m",
            "window_start_utc": "2026-04-25T10:00:00Z",
            "window_end_utc": "2026-04-25T10:05:00Z",
            "sample_count": 60,
            "hr_mean": 80,
            "stream_type": "hr",
            "payload_schema": "polar.hr",
            "source_vendor": "polar",
            "device_model": "h10",
        },
    ]


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
        paths = sorted(self.processed_root.glob(f"window_features/**/session_id={session_id}/session_summary.json"))
        self.assertTrue(paths, "session_summary.json must exist")
        return json.loads(paths[0].read_text(encoding="utf-8"))

    def _write_full_multistream(self, session_id: str) -> None:
        write_window_features(self.processed_root, session_id=session_id, stream_dir="hr", rows=build_hr_rows())
        write_window_features(
            self.processed_root,
            session_id=session_id,
            stream_dir="acc",
            rows=[
                {
                    "window_size": "30s",
                    "window_start_utc": "2026-04-25T10:00:00Z",
                    "window_end_utc": "2026-04-25T10:00:30Z",
                    "sample_count": 50,
                    "vector_magnitude_mean": 110.0,
                    "vector_magnitude_std": 8.0,
                    "vector_magnitude_max": 140.0,
                    "activity_energy": 2500.0,
                    "stream_type": "acc",
                    "payload_schema": "polar.acc",
                    "source_vendor": "polar",
                    "device_model": "h10",
                },
                {
                    "window_size": "1m",
                    "window_start_utc": "2026-04-25T10:00:00Z",
                    "window_end_utc": "2026-04-25T10:01:00Z",
                    "sample_count": 100,
                    "vector_magnitude_mean": 115.0,
                    "vector_magnitude_std": 7.0,
                    "vector_magnitude_max": 145.0,
                    "activity_energy": 5000.0,
                    "stream_type": "acc",
                    "payload_schema": "polar.acc",
                    "source_vendor": "polar",
                    "device_model": "h10",
                },
                {
                    "window_size": "5m",
                    "window_start_utc": "2026-04-25T10:00:00Z",
                    "window_end_utc": "2026-04-25T10:05:00Z",
                    "sample_count": 500,
                    "vector_magnitude_mean": 112.0,
                    "vector_magnitude_std": 6.5,
                    "vector_magnitude_max": 150.0,
                    "activity_energy": 22000.0,
                    "stream_type": "acc",
                    "payload_schema": "polar.acc",
                    "source_vendor": "polar",
                    "device_model": "h10",
                },
            ],
        )
        write_window_features(
            self.processed_root,
            session_id=session_id,
            stream_dir="ecg",
            rows=[
                {
                    "window_size": "30s",
                    "window_start_utc": "2026-04-25T10:00:00Z",
                    "window_end_utc": "2026-04-25T10:00:30Z",
                    "sample_count": 80,
                    "ecg_mean": 10.0,
                    "ecg_std": 25.0,
                    "ecg_min": -75.0,
                    "ecg_max": 65.0,
                    "amplitude_range": 140.0,
                    "stream_type": "ecg",
                    "payload_schema": "polar.ecg",
                    "source_vendor": "polar",
                    "device_model": "h10",
                },
                {
                    "window_size": "1m",
                    "window_start_utc": "2026-04-25T10:00:00Z",
                    "window_end_utc": "2026-04-25T10:01:00Z",
                    "sample_count": 160,
                    "ecg_mean": 12.0,
                    "ecg_std": 26.0,
                    "ecg_min": -80.0,
                    "ecg_max": 70.0,
                    "amplitude_range": 150.0,
                    "stream_type": "ecg",
                    "payload_schema": "polar.ecg",
                    "source_vendor": "polar",
                    "device_model": "h10",
                },
                {
                    "window_size": "5m",
                    "window_start_utc": "2026-04-25T10:00:00Z",
                    "window_end_utc": "2026-04-25T10:05:00Z",
                    "sample_count": 800,
                    "ecg_mean": 11.0,
                    "ecg_std": 24.0,
                    "ecg_min": -78.0,
                    "ecg_max": 72.0,
                    "amplitude_range": 150.0,
                    "stream_type": "ecg",
                    "payload_schema": "polar.ecg",
                    "source_vendor": "polar",
                    "device_model": "h10",
                },
            ],
        )
        clean_battery_path = write_battery_clean_timeseries(
            self.processed_root,
            session_id=session_id,
            rows=[
                {"ts_utc": "2026-04-25T10:00:00Z", "level_percent": 90, "charge_state": "discharging"},
                {"ts_utc": "2026-04-25T10:30:00Z", "level_percent": 88, "charge_state": "discharging"},
            ],
        )
        write_window_features(
            self.processed_root,
            session_id=session_id,
            stream_dir="unknown",
            rows=[
                {
                    "window_size": "30s",
                    "window_start_utc": "2026-04-25T10:00:00Z",
                    "window_end_utc": "2026-04-25T10:00:30Z",
                    "sample_count": 1,
                    "samples_count": 1,
                    "level_min": 90.0,
                    "level_max": 90.0,
                    "level_mean": 90.0,
                    "level_first": 90.0,
                    "level_last": 90.0,
                    "drain_per_hour": None,
                    "stream_type": "unknown",
                    "payload_schema": "polar.device_battery",
                    "source_vendor": "polar",
                    "device_model": "h10",
                    "input_artifact_reference": str(clean_battery_path),
                },
                {
                    "window_size": "1m",
                    "window_start_utc": "2026-04-25T10:00:00Z",
                    "window_end_utc": "2026-04-25T10:01:00Z",
                    "sample_count": 1,
                    "samples_count": 1,
                    "level_min": 90.0,
                    "level_max": 90.0,
                    "level_mean": 90.0,
                    "level_first": 90.0,
                    "level_last": 90.0,
                    "drain_per_hour": None,
                    "stream_type": "unknown",
                    "payload_schema": "polar.device_battery",
                    "source_vendor": "polar",
                    "device_model": "h10",
                    "input_artifact_reference": str(clean_battery_path),
                },
                {
                    "window_size": "5m",
                    "window_start_utc": "2026-04-25T10:00:00Z",
                    "window_end_utc": "2026-04-25T10:05:00Z",
                    "sample_count": 2,
                    "samples_count": 2,
                    "level_min": 88.0,
                    "level_max": 90.0,
                    "level_mean": 89.0,
                    "level_first": 90.0,
                    "level_last": 88.0,
                    "drain_per_hour": 4.0,
                    "stream_type": "unknown",
                    "payload_schema": "polar.device_battery",
                    "source_vendor": "polar",
                    "device_model": "h10",
                    "input_artifact_reference": str(clean_battery_path),
                },
            ],
        )

    def test_existing_hr_summary_behavior_still_available(self) -> None:
        write_window_features(self.processed_root, session_id="session-hr", stream_dir="hr", rows=build_hr_rows())
        result = self.runner.run_for_session("session-hr")
        payload = self._read_summary("session-hr")

        self.assertEqual(result["status"], "partial")
        self.assertEqual(payload["stream_summaries"]["hr"]["status"], "success")
        self.assertAlmostEqual(payload["stream_summaries"]["hr"]["hr_statistics"]["mean"], 80.0)
        self.assertAlmostEqual(payload["stream_summaries"]["hr"]["trend"]["delta"], 20.0)

    def test_multi_stream_session_summary_hr_acc_ecg_battery(self) -> None:
        self._write_full_multistream("session-all")
        result = self.runner.run_for_session("session-all")
        payload = self._read_summary("session-all")

        self.assertEqual(result["status"], "success")
        self.assertEqual(payload["status"], "success")
        self.assertEqual(sorted(payload["streams_present"]), ["acc", "device_battery", "ecg", "hr"])
        self.assertEqual(payload["streams_missing"], [])
        self.assertEqual(payload["stream_summaries"]["acc"]["status"], "success")
        self.assertEqual(payload["stream_summaries"]["ecg"]["status"], "success")
        self.assertEqual(payload["stream_summaries"]["device_battery"]["status"], "success")
        self.assertEqual(payload["stream_summaries"]["device_battery"]["battery"]["first_level"], 90.0)
        self.assertEqual(payload["stream_summaries"]["device_battery"]["battery"]["last_level"], 88.0)
        self.assertEqual(payload["stream_summaries"]["device_battery"]["battery"]["charge_states_observed"], ["discharging"])

    def test_battery_recognized_by_payload_schema_not_stream_type(self) -> None:
        session_id = "session-battery-schema"
        clean_battery_path = write_battery_clean_timeseries(
            self.processed_root,
            session_id=session_id,
            rows=[
                {"ts_utc": "2026-04-25T10:00:00Z", "level_percent": 87, "charge_state": "discharging"},
                {"ts_utc": "2026-04-25T10:15:00Z", "level_percent": 86, "charge_state": "discharging"},
            ],
        )
        write_window_features(
            self.processed_root,
            session_id=session_id,
            stream_dir="unknown",
            rows=[
                {
                    "window_size": "30s",
                    "window_start_utc": "2026-04-25T10:00:00Z",
                    "window_end_utc": "2026-04-25T10:00:30Z",
                    "sample_count": 1,
                    "samples_count": 2,
                    "level_min": 86.0,
                    "level_max": 87.0,
                    "level_mean": 86.5,
                    "level_first": 87.0,
                    "level_last": 86.0,
                    "drain_per_hour": 4.0,
                    "stream_type": "unknown",
                    "payload_schema": "polar.device_battery",
                    "source_vendor": "polar",
                    "device_model": "h10",
                    "input_artifact_reference": str(clean_battery_path),
                }
            ],
        )

        result = self.runner.run_for_session(session_id)
        payload = self._read_summary(session_id)

        self.assertEqual(result["status"], "partial")
        self.assertIn("device_battery", payload["streams_present"])
        self.assertNotIn("unknown", payload["streams_present"])
        self.assertEqual(payload["stream_summaries"]["device_battery"]["status"], "partial")

    def test_cross_midnight_session_discovery_requested_date_and_previous_day(self) -> None:
        session_id = "session-cross-midnight"
        write_window_features(
            self.processed_root,
            session_id=session_id,
            stream_dir="hr",
            date_partition="2026-04-24",
            rows=[
                {
                    "window_size": "30s",
                    "window_start_utc": "2026-04-24T23:59:30Z",
                    "window_end_utc": "2026-04-25T00:00:00Z",
                    "sample_count": 6,
                    "hr_mean": 65,
                    "stream_type": "hr",
                    "payload_schema": "polar.hr",
                    "source_vendor": "polar",
                    "device_model": "h10",
                }
            ],
        )
        write_window_features(
            self.processed_root,
            session_id=session_id,
            stream_dir="hr",
            date_partition="2026-04-25",
            rows=[
                {
                    "window_size": "1m",
                    "window_start_utc": "2026-04-25T00:00:00Z",
                    "window_end_utc": "2026-04-25T00:01:00Z",
                    "sample_count": 12,
                    "hr_mean": 66,
                    "stream_type": "hr",
                    "payload_schema": "polar.hr",
                    "source_vendor": "polar",
                    "device_model": "h10",
                },
                {
                    "window_size": "5m",
                    "window_start_utc": "2026-04-25T00:00:00Z",
                    "window_end_utc": "2026-04-25T00:05:00Z",
                    "sample_count": 60,
                    "hr_mean": 67,
                    "stream_type": "hr",
                    "payload_schema": "polar.hr",
                    "source_vendor": "polar",
                    "device_model": "h10",
                },
            ],
        )

        self.runner.run_for_session(session_id, requested_date="2026-04-25")
        payload = self._read_summary(session_id)
        summary_paths = sorted(self.processed_root.glob(f"window_features/**/session_id={session_id}/session_summary.json"))

        self.assertEqual(payload["crosses_midnight"], True)
        self.assertEqual(payload["started_at_utc"], "2026-04-24T23:59:30Z")
        self.assertEqual(payload["ended_at_utc"], "2026-04-25T00:05:00Z")
        self.assertEqual(len(summary_paths), 1)

    def test_missing_streams_do_not_fail_whole_summary(self) -> None:
        write_window_features(self.processed_root, session_id="session-missing", stream_dir="hr", rows=build_hr_rows())
        result = self.runner.run_for_session("session-missing")
        payload = self._read_summary("session-missing")

        self.assertEqual(result["status"], "partial")
        self.assertEqual(payload["status"], "partial")
        self.assertNotEqual(payload["status"], "failed")
        self.assertIn("acc", payload["streams_missing"])
        self.assertIn("ecg", payload["streams_missing"])
        self.assertIn("device_battery", payload["streams_missing"])

    def test_summary_does_not_read_or_modify_raw_jsonl(self) -> None:
        write_window_features(self.processed_root, session_id="session-no-raw", stream_dir="hr", rows=build_hr_rows())
        raw_path = (
            self.root
            / "raw"
            / "user_id=1"
            / "source=polar_h10"
            / "date=2026-04-25"
            / "session_id=session-no-raw"
            / "streams"
            / "hr"
            / "chunks.jsonl"
        )
        raw_path.parent.mkdir(parents=True, exist_ok=True)
        raw_initial = '{"raw":"should-not-change"}\n'
        raw_path.write_text(raw_initial, encoding="utf-8")

        self.runner.run_for_session("session-no-raw")
        raw_after = raw_path.read_text(encoding="utf-8")

        self.assertEqual(raw_after, raw_initial)

    def test_summary_json_has_deterministic_structure(self) -> None:
        self._write_full_multistream("session-structure")
        self.runner.run_for_session("session-structure")
        payload = self._read_summary("session-structure")

        expected_top_level_keys = [
            "schema_version",
            "session_id",
            "started_at_utc",
            "ended_at_utc",
            "duration_seconds",
            "crosses_midnight",
            "streams_present",
            "streams_missing",
            "stream_summaries",
            "artifact_paths",
            "generated_at_utc",
            "status",
            "inputs",
            "streams",
            "overall_quality",
        ]
        self.assertEqual(list(payload.keys()), expected_top_level_keys)
        self.assertEqual(list(payload["stream_summaries"].keys()), ["hr", "acc", "ecg", "device_battery"])
        self.assertEqual(set(payload["inputs"].keys()), {"window_feature_paths", "available_window_sizes"})


if __name__ == "__main__":
    unittest.main()
