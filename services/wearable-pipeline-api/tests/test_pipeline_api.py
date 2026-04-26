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
    from wearable_pipeline_api.pipeline.normalize import NormalizeHandlerOutput, PolarHrNormalizer
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
    samples: list[dict[str, object]],
    session_id: str = "session-001",
    stream_id: str = "stream-hr-001",
    vendor: str = "polar",
    device_model: str = "verity_sense",
) -> dict[str, object]:
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
        "payload": {"samples": samples},
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
    target = (
        raw_root
        / "user_id=1"
        / "source=polar_verity_sense"
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

    def test_multi_stream_support_and_skip_unsupported(self) -> None:
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
                    samples=[{"received_at_collector": "2026-04-25T10:00:00.100Z", "x": 1}],
                    stream_id="stream-acc-001",
                )
            ],
        )

        summary = self._runner().run()
        results = {item["stream_type"]: item for item in summary["normalize_runs"][0]["per_stream_results"]}

        self.assertEqual(results["hr"]["status"], "success")
        self.assertEqual(results["acc"]["status"], "skipped")

    def test_unsupported_only_stream_marks_partial_without_crash(self) -> None:
        write_raw_stream(
            self.raw_root,
            session_id="session-unsupported-only",
            stream_type="acc",
            chunks=[
                build_chunk(
                    chunk_id="chunk-acc-only-1",
                    sequence=1,
                    stream_type="acc",
                    payload_schema="polar.acc",
                    samples=[{"received_at_collector": "2026-04-25T10:00:00.100Z", "x": 1}],
                    stream_id="stream-acc-only-001",
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
                    samples=[{"received_at_collector": "2026-04-25T10:00:00.100Z", "x": 1}],
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
                            "hr": 0,
                            "received_at_collector": "2026-04-25T10:00:00Z",
                            "uploaded_at_collector": "2026-04-25T10:00:01Z",
                            "received_at_server": "2026-04-25T10:00:02Z",
                            "session_id": "session-001",
                            "stream_id": "stream-acc-001",
                            "stream_type": "acc",
                            "user_id": "1",
                            "source_vendor": "polar",
                            "source_device_model": "verity_sense",
                            "source_device_id": "dev-001",
                            "collection_mode": "online_live",
                            "source_chunk_id": "chunk-acc-1",
                            "source_sequence": 1,
                            "source_line_number": 1,
                            "alignment_confidence": "low",
                        }
                    ]
                )
                return NormalizeHandlerOutput(dataframe=df, report={"warnings": []}, warnings=[])

        runner = self._runner()
        runner.normalize_step.registry[("polar", "verity_sense", "hr")] = FailingHrHandler()
        runner.normalize_step.registry[("polar", "verity_sense", "acc")] = AccPassThroughHandler()

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
