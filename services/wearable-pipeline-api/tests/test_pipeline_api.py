from __future__ import annotations

import json
import sys
import tempfile
import time
import unittest
from pathlib import Path

import pandas as pd

WEARABLE_PIPELINE_API_ROOT = Path(__file__).resolve().parents[1]
if str(WEARABLE_PIPELINE_API_ROOT) not in sys.path:
    sys.path.insert(0, str(WEARABLE_PIPELINE_API_ROOT))

try:
    from fastapi.testclient import TestClient

    from wearable_pipeline_api.config.settings import Settings
    from wearable_pipeline_api.normalizers import HrNormalizer
    from wearable_pipeline_api.pipeline import HrPipelineRunner
    from wearable_pipeline_api.server import create_app
    from wearable_pipeline_api.storage.layout import derive_artifact_paths
    from wearable_pipeline_api.tracker import StateTracker

    DEPS_AVAILABLE = True
except ModuleNotFoundError:
    DEPS_AVAILABLE = False


def build_chunk(chunk_id: str, sequence: int, samples: list[dict[str, object]]) -> dict[str, object]:
    return {
        "schema_version": "1.0",
        "chunk_id": chunk_id,
        "session_id": "session-001",
        "stream_id": "stream-hr-001",
        "stream_type": "hr",
        "sequence": sequence,
        "source": {
            "vendor": "polar",
            "device_model": "verity_sense",
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
            "payload_schema": "polar.hr",
            "payload_version": "1.0",
        },
        "payload": {"samples": samples},
        "server": {"received_at_server": "2026-04-25T10:00:02Z"},
        "user_id": "1",
    }


def write_hr_raw_file(raw_root: Path, chunks: list[dict[str, object]]) -> Path:
    target = (
        raw_root
        / "user_id=1"
        / "source=polar_verity_sense"
        / "date=2026-04-25"
        / "session_id=session-001"
        / "streams"
        / "hr"
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

    def _runner(self) -> HrPipelineRunner:
        return HrPipelineRunner(
            raw_root=self.raw_root,
            processed_root=self.processed_root,
            tracker=StateTracker(self.state_root),
            normalizer=HrNormalizer(),
        )

    def test_hr_normalization_expands_samples_and_traceability(self) -> None:
        raw_path = write_hr_raw_file(
            self.raw_root,
            [
                build_chunk(
                    "chunk-1",
                    1,
                    [
                        {"received_at_collector": "2026-04-25T10:00:00.100Z", "hr": 70},
                        {"received_at_collector": "2026-04-25T10:00:00.200Z", "hr": 71},
                    ],
                ),
                build_chunk(
                    "chunk-2",
                    2,
                    [
                        {"received_at_collector": "2026-04-25T10:00:00.300Z", "hr": 72},
                        {"hr": 73},
                    ],
                ),
            ],
        )

        result = HrNormalizer().normalize(raw_path)

        self.assertEqual(len(result.dataframe.index), 3)
        self.assertTrue(pd.api.types.is_datetime64_any_dtype(result.dataframe["ts_utc"]))
        self.assertEqual(set(["source_chunk_id", "source_sequence", "source_line_number"]) - set(result.dataframe.columns), set())
        self.assertEqual(result.report["samples_count"], 3)
        self.assertEqual(result.report["skipped_samples_count"], 1)

    def test_artifact_creation_with_expected_schema_and_report(self) -> None:
        raw_path = write_hr_raw_file(
            self.raw_root,
            [build_chunk("chunk-1", 1, [{"received_at_collector": "2026-04-25T10:00:00.100Z", "hr": 70}])],
        )

        summary = self._runner().run()
        self.assertEqual(summary["processed"], 1)

        output_path, report_path = derive_artifact_paths(raw_path, self.raw_root, self.processed_root)
        self.assertTrue(output_path.exists())
        self.assertTrue(report_path.exists())

        df = pd.read_parquet(output_path)
        required_columns = {
            "ts_utc",
            "hr",
            "received_at_collector",
            "uploaded_at_collector",
            "received_at_server",
            "session_id",
            "stream_id",
            "stream_type",
            "user_id",
            "source_vendor",
            "source_device_model",
            "source_device_id",
            "collection_mode",
            "source_chunk_id",
            "source_sequence",
            "source_line_number",
            "alignment_confidence",
        }
        self.assertEqual(required_columns - set(df.columns), set())

        report = json.loads(report_path.read_text(encoding="utf-8"))
        self.assertEqual(report["alignment_basis"], "payload.samples[].received_at_collector")
        self.assertEqual(report["confidence"], "medium")
        self.assertEqual(report["samples_count"], 1)

    def test_tracker_skips_unchanged_file_on_second_run(self) -> None:
        write_hr_raw_file(
            self.raw_root,
            [build_chunk("chunk-1", 1, [{"received_at_collector": "2026-04-25T10:00:00.100Z", "hr": 70}])],
        )

        first = self._runner().run()
        second = self._runner().run()

        self.assertEqual(first["processed"], 1)
        self.assertEqual(second["skipped"], 1)
        self.assertEqual(second["processed"], 0)

    def test_tracker_reprocesses_after_raw_file_change(self) -> None:
        raw_path = write_hr_raw_file(
            self.raw_root,
            [build_chunk("chunk-1", 1, [{"received_at_collector": "2026-04-25T10:00:00.100Z", "hr": 70}])],
        )

        first = self._runner().run()
        output_path, _ = derive_artifact_paths(raw_path, self.raw_root, self.processed_root)
        first_mtime = output_path.stat().st_mtime

        chunks = [
            build_chunk("chunk-1", 1, [{"received_at_collector": "2026-04-25T10:00:00.100Z", "hr": 70}]),
            build_chunk("chunk-2", 2, [{"received_at_collector": "2026-04-25T10:00:00.200Z", "hr": 71}]),
        ]
        time.sleep(1.1)
        raw_path.write_text("\n".join(json.dumps(chunk) for chunk in chunks) + "\n", encoding="utf-8")
        raw_path.touch()

        second = self._runner().run()
        second_mtime = output_path.stat().st_mtime

        self.assertEqual(first["processed"], 1)
        self.assertEqual(second["processed"], 1)
        self.assertGreater(second_mtime, first_mtime)
        df = pd.read_parquet(output_path)
        self.assertEqual(len(df.index), 2)

    def test_api_endpoint_returns_pipeline_summary(self) -> None:
        write_hr_raw_file(
            self.raw_root,
            [build_chunk("chunk-1", 1, [{"received_at_collector": "2026-04-25T10:00:00.100Z", "hr": 70}])],
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
        self.assertEqual(payload["discovered"], 1)
        self.assertEqual(payload["processed"], 1)
        self.assertEqual(payload["failed"], 0)
        self.assertEqual(len(payload["artifacts"]), 1)
        self.assertEqual(payload["artifacts"][0]["status"], "processed")


if __name__ == "__main__":
    unittest.main()
