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
    from fastapi.testclient import TestClient

    from wearable_pipeline_api.config.settings import Settings
    from wearable_pipeline_api.pipeline import SessionPipelineRunner
    from wearable_pipeline_api.pipeline.normalize import (
        NormalizeHandlerOutput,
        PolarAccNormalizer,
        PolarDeviceBatteryNormalizer,
        PolarEcgNormalizer,
        PolarHrNormalizer,
    )
    from wearable_pipeline_api.server import create_app

    DEPS_AVAILABLE = True
except ModuleNotFoundError:
    DEPS_AVAILABLE = False


def build_chunk(
    *,
    chunk_id: str,
    sequence: int,
    stream_type: str,
    payload_schema: str,
    samples: list[dict[str, object]] | None = None,
    payload: dict[str, object] | None = None,
    session_id: str = "session-001",
    stream_id: str = "stream-hr-001",
    vendor: str = "polar",
    device_model: str = "h10",
) -> dict[str, object]:
    resolved_payload = payload if payload is not None else {"samples": samples or []}
    return {
        "schema_version": "1.0",
        "chunk_id": chunk_id,
        "session_id": session_id,
        "stream_id": stream_id,
        "stream_type": stream_type,
        "sequence": sequence,
        "source": {
            "vendor": vendor,
            "device_model": device_model,
            "device_id": "dev-001",
        },
        "collection": {"mode": "online_live"},
        "time": {
            "device_time_reference": "ref-001",
            "first_sample_received_at_collector": "2026-04-25T10:00:00Z",
            "uploaded_at_collector": "2026-04-25T10:00:01Z",
        },
        "transport": {
            "encoding": "json",
            "compression": "none",
            "payload_schema": payload_schema,
            "payload_version": "1.0",
        },
        "payload": resolved_payload,
        "server": {"received_at_server": "2026-04-25T10:00:02Z"},
        "user_id": "1",
    }


def write_raw_stream(
    raw_root: Path,
    *,
    session_id: str,
    stream_type: str,
    chunks: list[dict[str, object]],
) -> Path:
    source_dir = f"source={chunks[0].get('source', {}).get('vendor', 'polar')}_{chunks[0].get('source', {}).get('device_model', 'h10')}"
    target = (
        raw_root
        / "user_id=1"
        / source_dir
        / "date=2026-04-25"
        / f"session_id={session_id}"
        / "streams"
        / stream_type
        / "chunks.jsonl"
    )
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(json.dumps(chunk) for chunk in chunks) + "\n", encoding="utf-8")
    return target


@unittest.skipUnless(DEPS_AVAILABLE, "pipeline dependencies are not installed")
class PipelineApiTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.raw_root = self.root / "raw"
        self.processed_root = self.root / "processed"
        self.state_root = self.root / "pipeline_runs"

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def _runner(self) -> SessionPipelineRunner:
        return SessionPipelineRunner(
            raw_root=self.raw_root,
            processed_root=self.processed_root,
            state_root=self.state_root,
        )

    def test_normalizer_and_dispatch(self) -> None:
        raw_path = write_raw_stream(
            self.raw_root,
            session_id="session-001",
            stream_type="hr",
            chunks=[
                build_chunk(
                    chunk_id="chunk-1",
                    sequence=1,
                    stream_type="hr",
                    payload_schema="polar.hr",
                    samples=[
                        {"received_at_collector": "2026-04-25T10:00:00.100Z", "hr": 70},
                        {"received_at_collector": "2026-04-25T10:00:00.200Z", "hr": 71},
                    ],
                )
            ],
        )

        normalized = PolarHrNormalizer().handle(raw_path)
        self.assertEqual(len(normalized.dataframe.index), 2)
        self.assertEqual(
            set(["source_chunk_id", "source_sequence", "source_line_number"]) - set(normalized.dataframe.columns),
            set(),
        )

        summary = self._runner().run()
        stream_result = summary["normalize_runs"][0]["per_stream_results"][0]
        self.assertEqual(stream_result["handler_name"], "PolarHrNormalizer")
        self.assertEqual(stream_result["status"], "success")

    def test_normalizers_acc_ecg_and_battery(self) -> None:
        acc_path = write_raw_stream(
            self.raw_root,
            session_id="session-001",
            stream_type="acc",
            chunks=[
                build_chunk(
                    chunk_id="chunk-acc-1",
                    sequence=1,
                    stream_type="acc",
                    payload_schema="polar.acc",
                    stream_id="stream-acc-001",
                    samples=[
                        {
                            "received_at_collector": "2026-04-25T10:00:00.100Z",
                            "device_time_ns": 100,
                            "x_mg": 3.0,
                            "y_mg": 4.0,
                            "z_mg": 0.0,
                        }
                    ],
                )
            ],
        )
        ecg_path = write_raw_stream(
            self.raw_root,
            session_id="session-001",
            stream_type="ecg",
            chunks=[
                build_chunk(
                    chunk_id="chunk-ecg-1",
                    sequence=1,
                    stream_type="ecg",
                    payload_schema="polar.ecg",
                    stream_id="stream-ecg-001",
                    samples=[
                        {
                            "received_at_collector": "2026-04-25T10:00:00.120Z",
                            "device_time_ns": 200,
                            "ecg_uv": 145,
                        }
                    ],
                )
            ],
        )
        battery_path = write_raw_stream(
            self.raw_root,
            session_id="session-001",
            stream_type="unknown",
            chunks=[
                build_chunk(
                    chunk_id="chunk-battery-1",
                    sequence=1,
                    stream_type="unknown",
                    payload_schema="polar.device_battery",
                    stream_id="stream-battery-001",
                    payload={
                        "received_at_collector": "2026-04-25T10:00:00.300Z",
                        "level_percent": 87,
                        "charge_state": "discharging",
                        "power_sources": ["battery"],
                        "event_type": "status",
                        "sdk_raw": {"source": "sdk"},
                    },
                )
            ],
        )

        acc_df = PolarAccNormalizer().handle(acc_path).dataframe
        self.assertAlmostEqual(float(acc_df.iloc[0]["vector_magnitude_mg"]), 5.0)
        self.assertEqual(int(acc_df.iloc[0]["device_time_ns"]), 100)

        ecg_df = PolarEcgNormalizer().handle(ecg_path).dataframe
        self.assertEqual(float(ecg_df.iloc[0]["ecg_uv"]), 145.0)

        battery_df = PolarDeviceBatteryNormalizer().handle(battery_path).dataframe
        self.assertEqual(float(battery_df.iloc[0]["level_percent"]), 87.0)
        self.assertEqual(str(battery_df.iloc[0]["stream_type"]), "unknown")

    def test_battery_normalizer_supports_nested_battery_payload(self) -> None:
        battery_path = write_raw_stream(
            self.raw_root,
            session_id="session-battery-nested",
            stream_type="unknown",
            chunks=[
                build_chunk(
                    chunk_id="chunk-battery-nested-1",
                    sequence=1,
                    stream_type="unknown",
                    payload_schema="polar.device_battery",
                    stream_id="stream-battery-nested-001",
                    payload={
                        "received_at_collector": "2026-04-25T10:00:00.300Z",
                        "battery": {
                            "level_percent": 86,
                            "charge_state": "discharging",
                            "power_sources": ["battery"],
                        },
                        "event_type": "poll_snapshot",
                        "sdk_raw": {"source": "sdk"},
                    },
                )
            ],
        )

        battery_df = PolarDeviceBatteryNormalizer().handle(battery_path).dataframe
        self.assertEqual(float(battery_df.iloc[0]["level_percent"]), 86.0)
        self.assertEqual(str(battery_df.iloc[0]["charge_state"]), "discharging")
        self.assertEqual(list(battery_df.iloc[0]["power_sources"]), ["battery"])

    def test_multi_stream_support_hr_acc_ecg_battery(self) -> None:
        write_raw_stream(
            self.raw_root,
            session_id="session-001",
            stream_type="hr",
            chunks=[
                build_chunk(
                    chunk_id="chunk-1",
                    sequence=1,
                    stream_type="hr",
                    payload_schema="polar.hr",
                    samples=[{"received_at_collector": "2026-04-25T10:00:00.100Z", "hr": 70}],
                )
            ],
        )
        write_raw_stream(
            self.raw_root,
            session_id="session-001",
            stream_type="acc",
            chunks=[
                build_chunk(
                    chunk_id="chunk-acc-1",
                    sequence=1,
                    stream_type="acc",
                    payload_schema="polar.acc",
                    samples=[
                        {
                            "received_at_collector": "2026-04-25T10:00:00.100Z",
                            "device_time_ns": 100,
                            "x_mg": 1.0,
                            "y_mg": 2.0,
                            "z_mg": 3.0,
                        }
                    ],
                    stream_id="stream-acc-001",
                )
            ],
        )
        write_raw_stream(
            self.raw_root,
            session_id="session-001",
            stream_type="ecg",
            chunks=[
                build_chunk(
                    chunk_id="chunk-ecg-1",
                    sequence=1,
                    stream_type="ecg",
                    payload_schema="polar.ecg",
                    stream_id="stream-ecg-001",
                    samples=[
                        {
                            "received_at_collector": "2026-04-25T10:00:00.100Z",
                            "device_time_ns": 200,
                            "ecg_uv": 120,
                        }
                    ],
                )
            ],
        )
        write_raw_stream(
            self.raw_root,
            session_id="session-001",
            stream_type="unknown",
            chunks=[
                build_chunk(
                    chunk_id="chunk-battery-1",
                    sequence=1,
                    stream_type="unknown",
                    payload_schema="polar.device_battery",
                    stream_id="stream-battery-001",
                    payload={
                        "received_at_collector": "2026-04-25T10:00:00.200Z",
                        "level_percent": 90,
                        "charge_state": "discharging",
                        "power_sources": ["battery"],
                        "event_type": "status",
                        "sdk_raw": {"source": "sdk"},
                    },
                )
            ],
        )

        summary = self._runner().run()
        results = {item["stream_type"]: item for item in summary["normalize_runs"][0]["per_stream_results"]}

        self.assertEqual(results["hr"]["status"], "success")
        self.assertEqual(results["acc"]["status"], "success")
        self.assertEqual(results["ecg"]["status"], "success")
        self.assertEqual(results["unknown"]["status"], "success")

    def test_multi_stream_support_with_vendor_prefixed_device_model(self) -> None:
        write_raw_stream(
            self.raw_root,
            session_id="session-prefixed-model",
            stream_type="hr",
            chunks=[
                build_chunk(
                    chunk_id="chunk-hr-prefixed-1",
                    sequence=1,
                    stream_type="hr",
                    payload_schema="polar.hr",
                    device_model="polar h10",
                    samples=[{"received_at_collector": "2026-04-25T10:00:00.100Z", "hr": 70}],
                )
            ],
        )
        write_raw_stream(
            self.raw_root,
            session_id="session-prefixed-model",
            stream_type="acc",
            chunks=[
                build_chunk(
                    chunk_id="chunk-acc-prefixed-1",
                    sequence=1,
                    stream_type="acc",
                    payload_schema="polar.acc",
                    stream_id="stream-acc-prefixed-001",
                    device_model="polar h10",
                    samples=[
                        {
                            "received_at_collector": "2026-04-25T10:00:00.100Z",
                            "device_time_ns": 100,
                            "x_mg": 1.0,
                            "y_mg": 2.0,
                            "z_mg": 3.0,
                        }
                    ],
                )
            ],
        )
        write_raw_stream(
            self.raw_root,
            session_id="session-prefixed-model",
            stream_type="ecg",
            chunks=[
                build_chunk(
                    chunk_id="chunk-ecg-prefixed-1",
                    sequence=1,
                    stream_type="ecg",
                    payload_schema="polar.ecg",
                    stream_id="stream-ecg-prefixed-001",
                    device_model="polar h10",
                    samples=[
                        {
                            "received_at_collector": "2026-04-25T10:00:00.100Z",
                            "device_time_ns": 200,
                            "ecg_uv": 120,
                        }
                    ],
                )
            ],
        )
        write_raw_stream(
            self.raw_root,
            session_id="session-prefixed-model",
            stream_type="unknown",
            chunks=[
                build_chunk(
                    chunk_id="chunk-battery-prefixed-1",
                    sequence=1,
                    stream_type="unknown",
                    payload_schema="polar.device_battery",
                    stream_id="stream-battery-prefixed-001",
                    device_model="polar h10",
                    payload={
                        "received_at_collector": "2026-04-25T10:00:00.200Z",
                        "level_percent": 90,
                        "charge_state": "discharging",
                        "power_sources": ["battery"],
                        "event_type": "status",
                        "sdk_raw": {"source": "sdk"},
                    },
                )
            ],
        )

        summary = self._runner().run()

        normalize_results = {item["stream_type"]: item for item in summary["normalize_runs"][0]["per_stream_results"]}
        self.assertEqual(normalize_results["hr"]["status"], "success")
        self.assertEqual(normalize_results["acc"]["status"], "success")
        self.assertEqual(normalize_results["ecg"]["status"], "success")
        self.assertEqual(normalize_results["unknown"]["status"], "success")

        feature_results = {item["stream_type"]: item for item in summary["window_feature_runs"][0]["per_stream_results"]}
        self.assertEqual(feature_results["hr"]["status"], "success")
        self.assertEqual(feature_results["acc"]["status"], "success")
        self.assertEqual(feature_results["ecg"]["status"], "success")
        self.assertEqual(feature_results["unknown"]["status"], "success")

    def test_unsupported_only_stream_marks_partial_without_crash(self) -> None:
        write_raw_stream(
            self.raw_root,
            session_id="session-unsupported-only",
            stream_type="ppi",
            chunks=[
                build_chunk(
                    chunk_id="chunk-ppi-only-1",
                    sequence=1,
                    stream_type="ppi",
                    payload_schema="polar.ppi",
                    samples=[{"received_at_collector": "2026-04-25T10:00:00.100Z", "x": 1}],
                    stream_id="stream-ppi-only-001",
                )
            ],
        )

        summary = self._runner().run()
        normalize_run = summary["normalize_runs"][0]
        self.assertEqual(normalize_run["status"], "partial")
        self.assertEqual(normalize_run["per_stream_results"][0]["status"], "skipped")

    def test_state_file_and_failed_stream_isolation(self) -> None:
        write_raw_stream(
            self.raw_root,
            session_id="session-001",
            stream_type="hr",
            chunks=[
                build_chunk(
                    chunk_id="chunk-hr-1",
                    sequence=1,
                    stream_type="hr",
                    payload_schema="polar.hr",
                    samples=[{"received_at_collector": "2026-04-25T10:00:00.100Z", "hr": 80}],
                )
            ],
        )
        write_raw_stream(
            self.raw_root,
            session_id="session-001",
            stream_type="acc",
            chunks=[
                build_chunk(
                    chunk_id="chunk-acc-1",
                    sequence=1,
                    stream_type="acc",
                    payload_schema="polar.acc",
                    samples=[
                        {
                            "received_at_collector": "2026-04-25T10:00:00.100Z",
                            "device_time_ns": 100,
                            "x_mg": 1.0,
                            "y_mg": 2.0,
                            "z_mg": 3.0,
                        }
                    ],
                    stream_id="stream-acc-001",
                )
            ],
        )

        class FailingHrHandler:
            name = "FailingHrHandler"

            def handle(self, raw_path: Path) -> NormalizeHandlerOutput:
                raise RuntimeError("synthetic normalize failure")

        class AccPassThroughHandler:
            name = "AccPassThroughHandler"

            def handle(self, raw_path: Path) -> NormalizeHandlerOutput:
                df = pd.DataFrame(
                    [
                        {
                            "ts_utc": pd.Timestamp("2026-04-25T10:00:00Z"),
                            "received_at_collector": "2026-04-25T10:00:00Z",
                            "uploaded_at_collector": "2026-04-25T10:00:01Z",
                            "received_at_server": "2026-04-25T10:00:02Z",
                            "session_id": "session-001",
                            "stream_id": "stream-acc-001",
                            "stream_type": "acc",
                            "payload_schema": "polar.acc",
                            "user_id": "1",
                            "source_vendor": "polar",
                            "source_device_model": "h10",
                            "source_device_id": "dev-001",
                            "collection_mode": "online_live",
                            "source_chunk_id": "chunk-acc-1",
                            "source_sequence": 1,
                            "source_line_number": 1,
                            "alignment_confidence": "low",
                            "x_mg": 0.0,
                            "y_mg": 0.0,
                            "z_mg": 0.0,
                            "vector_magnitude_mg": 0.0,
                        }
                    ]
                )
                return NormalizeHandlerOutput(dataframe=df, report={"warnings": []}, warnings=[])

        runner = self._runner()
        runner.normalize_step.registry[("polar", "h10", "polar.hr")] = FailingHrHandler()
        runner.normalize_step.registry[("polar", "h10", "polar.acc")] = AccPassThroughHandler()

        summary = runner.run()
        normalize_run = summary["normalize_runs"][0]

        self.assertEqual(normalize_run["status"], "partial")
        statuses = sorted(item["status"] for item in normalize_run["per_stream_results"])
        self.assertEqual(statuses, ["failed", "success"])

        normalize_states = sorted((self.state_root / "normalize").glob("*.json"))
        features_states = sorted((self.state_root / "window_features").glob("*.json"))
        summary_states = sorted((self.state_root / "build_session_summary").glob("*.json"))
        self.assertEqual(len(normalize_states), 1)
        self.assertEqual(len(features_states), 1)
        self.assertEqual(len(summary_states), 1)

        state_payload = json.loads(normalize_states[0].read_text(encoding="utf-8"))
        self.assertIn("per_stream_results", state_payload)
        self.assertEqual(len(state_payload["per_stream_results"]), 2)

    def test_window_features_stats_schema_and_artifacts(self) -> None:
        write_raw_stream(
            self.raw_root,
            session_id="session-001",
            stream_type="hr",
            chunks=[
                build_chunk(
                    chunk_id="chunk-1",
                    sequence=1,
                    stream_type="hr",
                    payload_schema="polar.hr",
                    samples=[
                        {"received_at_collector": "2026-04-25T10:00:05.000Z", "hr": 60},
                        {"received_at_collector": "2026-04-25T10:00:10.000Z", "hr": 90},
                        {"received_at_collector": "2026-04-25T10:00:40.000Z", "hr": 75},
                    ],
                )
            ],
        )

        summary = self._runner().run()
        normalize_result = summary["normalize_runs"][0]["per_stream_results"][0]
        features_result = summary["window_feature_runs"][0]["per_stream_results"][0]

        clean_path = Path(normalize_result["output_path"])
        features_path = Path(features_result["output_path"])
        self.assertTrue(clean_path.exists())
        self.assertTrue(features_path.exists())

        clean_df = pd.read_parquet(clean_path)
        self.assertEqual(
            set(["source_chunk_id", "source_sequence", "session_id", "stream_id"]) - set(clean_df.columns),
            set(),
        )

        features_df = pd.read_parquet(features_path)
        required_columns = {
            "user_id",
            "session_id",
            "stream_id",
            "stream_type",
            "payload_schema",
            "source_vendor",
            "device_model",
            "window_size",
            "window_start_utc",
            "window_end_utc",
            "sample_count",
            "hr_mean",
            "hr_min",
            "hr_max",
            "hr_std",
            "hr_median",
            "hr_first",
            "hr_last",
            "coverage_ratio",
            "input_artifact_reference",
            "run_id",
        }
        self.assertEqual(required_columns - set(features_df.columns), set())

        thirty_seconds = features_df[features_df["window_size"] == "30s"].sort_values("window_start_utc")
        first_window = thirty_seconds.iloc[0]
        self.assertEqual(int(first_window["sample_count"]), 2)
        self.assertAlmostEqual(float(first_window["hr_mean"]), 75.0)
        self.assertAlmostEqual(float(first_window["hr_min"]), 60.0)
        self.assertAlmostEqual(float(first_window["hr_max"]), 90.0)

    def test_window_features_for_acc_ecg_battery(self) -> None:
        session_id = "session-feature-streams"
        write_raw_stream(
            self.raw_root,
            session_id=session_id,
            stream_type="acc",
            chunks=[
                build_chunk(
                    chunk_id="chunk-acc-1",
                    sequence=1,
                    stream_type="acc",
                    payload_schema="polar.acc",
                    stream_id="stream-acc-001",
                    samples=[
                        {"received_at_collector": "2026-04-25T10:00:00.000Z", "device_time_ns": 100, "x_mg": 1, "y_mg": 2, "z_mg": 2},
                        {"received_at_collector": "2026-04-25T10:00:10.000Z", "device_time_ns": 110, "x_mg": 3, "y_mg": 4, "z_mg": 0},
                    ],
                )
            ],
        )
        write_raw_stream(
            self.raw_root,
            session_id=session_id,
            stream_type="ecg",
            chunks=[
                build_chunk(
                    chunk_id="chunk-ecg-1",
                    sequence=1,
                    stream_type="ecg",
                    payload_schema="polar.ecg",
                    stream_id="stream-ecg-001",
                    samples=[
                        {"received_at_collector": "2026-04-25T10:00:00.000Z", "device_time_ns": 100, "ecg_uv": 100},
                        {"received_at_collector": "2026-04-25T10:00:10.000Z", "device_time_ns": 110, "ecg_uv": -50},
                    ],
                )
            ],
        )
        write_raw_stream(
            self.raw_root,
            session_id=session_id,
            stream_type="unknown",
            chunks=[
                build_chunk(
                    chunk_id="chunk-battery-1",
                    sequence=1,
                    stream_type="unknown",
                    payload_schema="polar.device_battery",
                    stream_id="stream-battery-001",
                    payload={
                        "received_at_collector": "2026-04-25T10:00:00.000Z",
                        "level_percent": 90,
                        "charge_state": "discharging",
                        "power_sources": ["battery"],
                        "event_type": "status",
                        "sdk_raw": {"s": 1},
                    },
                ),
                build_chunk(
                    chunk_id="chunk-battery-2",
                    sequence=2,
                    stream_type="unknown",
                    payload_schema="polar.device_battery",
                    stream_id="stream-battery-001",
                    payload={
                        "received_at_collector": "2026-04-25T10:00:30.000Z",
                        "level_percent": 89,
                        "charge_state": "discharging",
                        "power_sources": ["battery"],
                        "event_type": "status",
                        "sdk_raw": {"s": 2},
                    },
                ),
            ],
        )

        summary = self._runner().run()
        feature_results = summary["window_feature_runs"][0]["per_stream_results"]
        self.assertEqual(len(feature_results), 3)
        by_stream = {item["stream_type"]: item for item in feature_results}
        self.assertEqual(by_stream["acc"]["status"], "success")
        self.assertEqual(by_stream["ecg"]["status"], "success")
        self.assertEqual(by_stream["unknown"]["status"], "success")

        acc_df = pd.read_parquet(Path(by_stream["acc"]["output_path"]))
        self.assertIn("activity_energy", acc_df.columns)
        self.assertIn("vector_magnitude_mean", acc_df.columns)

        ecg_df = pd.read_parquet(Path(by_stream["ecg"]["output_path"]))
        self.assertIn("amplitude_range", ecg_df.columns)
        self.assertIn("abs_mean", ecg_df.columns)

        battery_df = pd.read_parquet(Path(by_stream["unknown"]["output_path"]))
        self.assertIn("samples_count", battery_df.columns)
        self.assertIn("drain_per_hour", battery_df.columns)

    def test_api_endpoint_returns_pipeline_summary(self) -> None:
        write_raw_stream(
            self.raw_root,
            session_id="session-001",
            stream_type="hr",
            chunks=[
                build_chunk(
                    chunk_id="chunk-1",
                    sequence=1,
                    stream_type="hr",
                    payload_schema="polar.hr",
                    samples=[{"received_at_collector": "2026-04-25T10:00:00.100Z", "hr": 70}],
                )
            ],
        )

        settings = Settings(
            host="127.0.0.1",
            port=8091,
            raw_root=self.raw_root,
            processed_root=self.processed_root,
            pipeline_state_root=self.state_root,
            log_level="INFO",
        )
        client = TestClient(create_app(settings))

        response = client.post("/api/v1/pipeline/normalize/hr")
        self.assertEqual(response.status_code, 200)

        payload = response.json()
        self.assertEqual(payload["sessions_discovered"], 1)
        self.assertEqual(len(payload["normalize_runs"]), 1)
        self.assertEqual(len(payload["window_feature_runs"]), 1)
        self.assertEqual(len(payload["session_summary_runs"]), 1)


if __name__ == "__main__":
    unittest.main()
