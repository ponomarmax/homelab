from __future__ import annotations

import json
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

INGESTION_API_ROOT = Path(__file__).resolve().parents[1]
if str(INGESTION_API_ROOT) not in sys.path:
    sys.path.insert(0, str(INGESTION_API_ROOT))

from ingestion_api.server import create_server


class IngestionApiTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.raw_root = Path(self.temp_dir.name)

        self.server = create_server("127.0.0.1", 0, self.raw_root)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

        host, port = self.server.server_address
        self.url = f"http://{host}:{port}/upload-chunk"

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.temp_dir.cleanup()

    def post_json(self, body: dict) -> tuple[int, dict]:
        request = urllib.request.Request(
            self.url,
            data=json.dumps(body).encode("utf-8"),
            method="POST",
            headers={"Content-Type": "application/json"},
        )

        try:
            with urllib.request.urlopen(request) as response:
                payload = json.loads(response.read().decode("utf-8"))
                return response.status, payload
        except urllib.error.HTTPError as exc:
            payload = json.loads(exc.read().decode("utf-8"))
            return exc.code, payload

    def test_upload_success_writes_raw_jsonl_and_returns_ack(self) -> None:
        chunk = {
            "schema_version": "1.0",
            "chunk_id": "chunk-real-001",
            "session_id": "session-real-001",
            "stream_id": "stream-hr-001",
            "sequence": 1,
            "time": {
                "received_at_collector": "2026-04-25T10:00:00Z",
                "uploaded_at_collector": "2026-04-25T10:00:01Z",
            },
            "transport": {
                "encoding": "json",
                "compression": "none",
                "payload_schema": "polar.hr",
                "payload_version": "1.0",
            },
            "payload": {
                "samples": [
                    {
                        "hr": 71,
                        "ppgQuality": 0,
                        "correctedHr": 0,
                        "rrsMs": [],
                        "rrAvailable": False,
                        "contactStatus": False,
                        "contactStatusSupported": False,
                    }
                ]
            },
        }

        status, response = self.post_json(chunk)

        self.assertEqual(status, 200)
        self.assertTrue(response["accepted"])
        self.assertEqual(response["status"], "accepted")
        self.assertEqual(response["chunk_id"], "chunk-real-001")
        self.assertTrue(response["storage"]["raw_persisted"])

        raw_path = Path(response["storage"]["storage_path"])
        self.assertTrue(raw_path.exists())

        lines = raw_path.read_text(encoding="utf-8").strip().splitlines()
        self.assertEqual(len(lines), 1)

        stored = json.loads(lines[0])
        self.assertEqual(stored["chunk_id"], "chunk-real-001")
        self.assertEqual(stored["payload"]["samples"][0]["hr"], 71)
        self.assertIn("received_at_server", stored["time"])

    def test_invalid_payload_is_rejected_with_structured_error(self) -> None:
        chunk = {
            "schema_version": "1.0",
            "chunk_id": "chunk-real-002",
            "session_id": "session-real-001",
            "stream_id": "stream-hr-001",
            "sequence": 2,
            "time": {
                "received_at_collector": "2026-04-25T10:01:00Z",
                "uploaded_at_collector": "2026-04-25T10:01:01Z",
            },
            "transport": {
                "encoding": "json",
                "compression": "none",
                "payload_schema": "polar.hr",
                "payload_version": "1.0",
            },
            "payload": {
                "samples": [
                    {
                        "ppgQuality": 0,
                        "correctedHr": 0,
                        "rrsMs": [],
                        "rrAvailable": False,
                        "contactStatus": False,
                        "contactStatusSupported": False,
                    }
                ]
            },
        }

        status, response = self.post_json(chunk)

        self.assertEqual(status, 422)
        self.assertFalse(response["accepted"])
        self.assertEqual(response["status"], "rejected")
        self.assertEqual(response["error_code"], "validation_error")
        self.assertIn("details", response)
        self.assertTrue(any(item["field"].endswith(".hr") for item in response["details"]))

        persisted_files = list(self.raw_root.rglob("*.jsonl"))
        self.assertEqual(persisted_files, [])


if __name__ == "__main__":
    unittest.main()
