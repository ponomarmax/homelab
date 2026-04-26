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
        "stream_type": "hr",
        "sequence": 1,
        "source": {
            "vendor": "polar",
            "device_model": "verity_sense",
            "device_id": "dev-123",
        },
        "collection": {
            "mode": "online_live",
        },
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

    def test_upload_creates_expected_directory_structure_and_file(self) -> None:
        chunk = build_valid_chunk()

        response = self.client.post("/upload-chunk", json=chunk, headers={"X-User-ID": "42"})
        self.assertEqual(response.status_code, 200)

        payload = response.json()
        self.assertTrue(payload["accepted"])
        self.assertEqual(payload["status"], "accepted")
        self.assertEqual(payload["chunk_id"], "chunk-real-001")
        self.assertTrue(payload["storage"]["raw_persisted"])

        raw_path = Path(payload["storage"]["storage_path"])
        self.assertTrue(raw_path.exists())
        self.assertEqual(raw_path.name, "chunks.jsonl")
        relative_parts = raw_path.relative_to(self.raw_root).parts
        self.assertEqual(relative_parts[0], "user_id=42")
        self.assertEqual(relative_parts[1], "source=polar_verity_sense")
        self.assertTrue(relative_parts[2].startswith("date="))
        self.assertEqual(relative_parts[3], "session_id=session-real-001")
        self.assertEqual(relative_parts[4], "streams")
        self.assertEqual(relative_parts[5], "hr")
        self.assertEqual(relative_parts[6], "chunks.jsonl")

        lines = raw_path.read_text(encoding="utf-8").strip().splitlines()
        self.assertEqual(len(lines), 1)

        stored = json.loads(lines[0])
        self.assertEqual(stored["chunk_id"], chunk["chunk_id"])
        self.assertEqual(stored["user_id"], "42")
        self.assertIn("server", stored)
        self.assertIn("received_at_server", stored["server"])

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

    def test_data_is_appended_for_multiple_requests(self) -> None:
        chunk = build_valid_chunk()
        response1 = self.client.post("/upload-chunk", json=chunk, headers={"X-User-ID": "9"})
        self.assertEqual(response1.status_code, 200)

        chunk_2 = build_valid_chunk()
        chunk_2["chunk_id"] = "chunk-real-002"
        chunk_2["sequence"] = 2
        response2 = self.client.post("/upload-chunk", json=chunk_2, headers={"X-User-ID": "9"})
        self.assertEqual(response2.status_code, 200)

        raw_path = Path(response1.json()["storage"]["storage_path"])
        self.assertEqual(raw_path, Path(response2.json()["storage"]["storage_path"]))
        lines = raw_path.read_text(encoding="utf-8").strip().splitlines()
        self.assertEqual(len(lines), 2)

        stored_first = json.loads(lines[0])
        stored_second = json.loads(lines[1])
        self.assertEqual(stored_first["chunk_id"], "chunk-real-001")
        self.assertEqual(stored_second["chunk_id"], "chunk-real-002")

    def test_missing_user_header_falls_back_to_default_user_id(self) -> None:
        chunk = build_valid_chunk()

        response = self.client.post("/upload-chunk", json=chunk)
        self.assertEqual(response.status_code, 200)

        raw_path = Path(response.json()["storage"]["storage_path"])
        self.assertIn("/user_id=1/", str(raw_path))
        stored = json.loads(raw_path.read_text(encoding="utf-8").strip().splitlines()[0])
        self.assertEqual(stored["user_id"], "1")

    def test_server_received_timestamp_is_added(self) -> None:
        chunk = build_valid_chunk()

        response = self.client.post("/upload-chunk", json=chunk)
        self.assertEqual(response.status_code, 200)

        raw_path = Path(response.json()["storage"]["storage_path"])
        stored = json.loads(raw_path.read_text(encoding="utf-8").strip().splitlines()[0])
        self.assertIn("server", stored)
        self.assertIn("received_at_server", stored["server"])
        self.assertTrue(stored["server"]["received_at_server"].endswith("Z"))

    def test_client_received_at_server_field_is_ignored(self) -> None:
        chunk = build_valid_chunk()
        chunk["time"]["received_at_server"] = "1999-01-01T00:00:00Z"

        response = self.client.post("/upload-chunk", json=chunk)
        self.assertEqual(response.status_code, 200)

        raw_path = Path(response.json()["storage"]["storage_path"])
        stored = json.loads(raw_path.read_text(encoding="utf-8").strip().splitlines()[0])
        self.assertNotIn("received_at_server", stored["time"])
        self.assertIn("received_at_server", stored["server"])
        self.assertNotEqual(stored["server"]["received_at_server"], "1999-01-01T00:00:00Z")

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
