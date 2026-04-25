from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

WEARABLE_INGESTION_API_ROOT = Path(__file__).resolve().parents[1]
if str(WEARABLE_INGESTION_API_ROOT) not in sys.path:
    sys.path.insert(0, str(WEARABLE_INGESTION_API_ROOT))

try:
    from fastapi.testclient import TestClient
    from wearable_ingestion_api.server import create_app

    FASTAPI_AVAILABLE = True
except ModuleNotFoundError:
    FASTAPI_AVAILABLE = False


def build_valid_chunk() -> dict[str, object]:
    return {
        "schema_version": "1.0",
        "chunk_id": "chunk-real-001",
        "session_id": "session-real-001",
        "stream_id": "stream-hr-001",
        "sequence": 1,
        "time": {
            "first_sample_received_at_collector": "2026-04-25T10:00:00Z",
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
                    "received_at_collector": "2026-04-25T10:00:00.000Z",
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


@unittest.skipUnless(FASTAPI_AVAILABLE, "fastapi is not installed in local python environment")
class IngestionApiTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.raw_root = Path(self.temp_dir.name)
        app = create_app(self.raw_root)
        self.client = TestClient(app)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_upload_success_writes_raw_jsonl_and_returns_ack(self) -> None:
        chunk = build_valid_chunk()

        response = self.client.post("/upload-chunk", json=chunk)
        self.assertEqual(response.status_code, 200)

        payload = response.json()
        self.assertTrue(payload["accepted"])
        self.assertEqual(payload["status"], "accepted")
        self.assertEqual(payload["chunk_id"], "chunk-real-001")
        self.assertTrue(payload["storage"]["raw_persisted"])

        raw_path = Path(payload["storage"]["storage_path"])
        self.assertTrue(raw_path.exists())

        lines = raw_path.read_text(encoding="utf-8").strip().splitlines()
        self.assertEqual(len(lines), 1)

        stored = json.loads(lines[0])
        self.assertEqual(stored, chunk)
        self.assertNotIn("received_at_server", stored["time"])

    def test_health_endpoint_returns_ok(self) -> None:
        response = self.client.get("/healthz")
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["status"], "ok")
        self.assertEqual(payload["service"], "wearable-ingestion-api")

    def test_missing_required_fields_returns_400(self) -> None:
        chunk = build_valid_chunk()
        del chunk["sequence"]

        response = self.client.post("/upload-chunk", json=chunk)
        self.assertEqual(response.status_code, 400)
        payload = response.json()
        self.assertFalse(payload["accepted"])
        self.assertEqual(payload["status"], "rejected")
        self.assertEqual(payload["error_code"], "validation_error")
        self.assertTrue(any(item["field"] == "sequence" for item in payload["details"]))

        persisted_files = list(self.raw_root.rglob("*.jsonl"))
        self.assertEqual(persisted_files, [])

    def test_arbitrary_payload_shape_is_accepted(self) -> None:
        chunk = build_valid_chunk()
        chunk["payload"] = {"samples": [{"hr": "not-an-int"}], "opaque": {"nested": ["value"]}}

        response = self.client.post("/upload-chunk", json=chunk)
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertTrue(payload["accepted"])
        self.assertEqual(payload["status"], "accepted")

    def test_payload_without_samples_is_accepted(self) -> None:
        chunk = build_valid_chunk()
        chunk["payload"] = {"events": [{"kind": "marker", "value": 1}], "metadata": {"source": "custom"}}

        response = self.client.post("/upload-chunk", json=chunk)
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertTrue(payload["accepted"])

        raw_path = Path(payload["storage"]["storage_path"])
        stored = json.loads(raw_path.read_text(encoding="utf-8").strip().splitlines()[0])
        self.assertEqual(stored["payload"], chunk["payload"])

    def test_unknown_payload_schema_is_accepted(self) -> None:
        chunk = build_valid_chunk()
        chunk["transport"] = {
            "encoding": "json",
            "compression": "none",
            "payload_schema": "polar.unknown",
            "payload_version": "99.0",
        }

        response = self.client.post("/upload-chunk", json=chunk)
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertTrue(payload["accepted"])
        self.assertEqual(payload["status"], "accepted")

    def test_openapi_exposes_typed_contract_models(self) -> None:
        response = self.client.get("/openapi.json")
        self.assertEqual(response.status_code, 200)
        spec = response.json()

        schemas = spec["components"]["schemas"]
        self.assertIn("UploadChunkRequest", schemas)
        self.assertIn("AckResponse", schemas)
        self.assertIn("ErrorResponse", schemas)

        upload_post = spec["paths"]["/upload-chunk"]["post"]
        request_ref = upload_post["requestBody"]["content"]["application/json"]["schema"]["$ref"]
        self.assertTrue(request_ref.endswith("/UploadChunkRequest"))
        self.assertIn("200", upload_post["responses"])
        self.assertIn("400", upload_post["responses"])


if __name__ == "__main__":
    unittest.main()
