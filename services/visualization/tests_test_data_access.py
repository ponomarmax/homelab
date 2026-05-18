from __future__ import annotations

import tempfile
from pathlib import Path
from unittest import TestCase
from unittest.mock import patch

from wearable_operator_dashboard.data_access import (
    DashboardConfig,
    build_ppi_points_from_raw_artifact,
    classify_ppi_quality_tier,
    discover_normalized_files,
    fetch_session_details,
    fetch_sessions,
    infer_duration_seconds,
    load_stream_points,
)


class DashboardDataAccessTests(TestCase):
    def test_infer_duration_seconds(self) -> None:
        duration = infer_duration_seconds("2026-01-01T00:00:00Z", "2026-01-01T00:01:30Z")
        self.assertEqual(duration, 90.0)

    @patch("wearable_operator_dashboard.data_access._get_json")
    def test_fetch_sessions(self, mock_get_json) -> None:
        mock_get_json.return_value = {"sessions": [{"session_id": "abc"}]}
        config = DashboardConfig("http://api", Path("/raw"), Path("/processed"))
        sessions = fetch_sessions(config)

        self.assertEqual(sessions[0]["session_id"], "abc")

    @patch("wearable_operator_dashboard.data_access._get_json")
    def test_fetch_session_details(self, mock_get_json) -> None:
        mock_get_json.return_value = {"session_id": "xyz"}
        config = DashboardConfig("http://api", Path("/raw"), Path("/processed"))
        details = fetch_session_details(config, "xyz")

        self.assertEqual(details["session_id"], "xyz")

    def test_load_stream_points(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            file_path = Path(tmpdir) / "ppi.jsonl"
            file_path.write_text(
                '{"timestamp_utc":"2026-01-01T00:00:00Z","ppi_ms":800,"quality":"high"}\n',
                encoding="utf-8",
            )
            points = load_stream_points(file_path)
            self.assertEqual(len(points), 1)
            self.assertEqual(points[0]["value"], 800)
            self.assertEqual(points[0]["quality"], "high")

    def test_discover_normalized_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            target = root / "normalize" / "x" / "session_id=s1" / "streams" / "ppi" / "normalized_ppi.jsonl"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("{}\n", encoding="utf-8")

            config = DashboardConfig("http://api", root / "raw", root)
            files = discover_normalized_files(config, "s1")

            self.assertIn("ppi", files)

    def test_classify_ppi_quality_tier(self) -> None:
        self.assertEqual(classify_ppi_quality_tier(5, 0), "high")
        self.assertEqual(classify_ppi_quality_tier(8, 0), "medium")
        self.assertEqual(classify_ppi_quality_tier(5, 1), "low")

    def test_build_ppi_points_from_raw_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            raw_path = Path(tmpdir) / "chunks.jsonl"
            raw_path.write_text(
                "\n".join(
                    [
                        '{"time":{"recording_start_utc":"2026-01-01T00:00:00Z"},"payload":{"samples":[{"ppInMs":900,"ppErrorEstimate":5,"blockerBit":0},{"ppInMs":920,"ppErrorEstimate":9,"blockerBit":0},{"ppInMs":880,"ppErrorEstimate":4,"blockerBit":1}]}}',
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            points = build_ppi_points_from_raw_artifact(raw_path, max_points=1000)
            self.assertEqual(len(points), 3)
            self.assertEqual(points[0]["quality_tier"], "high")
            self.assertEqual(points[1]["quality_tier"], "medium")
            self.assertEqual(points[2]["quality_tier"], "low")
