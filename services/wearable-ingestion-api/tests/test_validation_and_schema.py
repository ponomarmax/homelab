from __future__ import annotations

import sys
import unittest
from pathlib import Path

WEARABLE_INGESTION_API_ROOT = Path(__file__).resolve().parents[1]
if str(WEARABLE_INGESTION_API_ROOT) not in sys.path:
    sys.path.insert(0, str(WEARABLE_INGESTION_API_ROOT))

from wearable_ingestion_api.validation import validate_upload_chunk_contract


class ValidationAndSchemaTests(unittest.TestCase):
    def test_generic_payload_without_samples_passes_upload_contract_validation(self) -> None:
        payload = {"events": [{"name": "button_press", "value": 1}]}

        chunk = {
            "schema_version": "1.0",
            "chunk_id": "chunk-001",
            "session_id": "session-001",
            "stream_id": "stream-hr-001",
            "stream_type": "hr",
            "sequence": 1,
            "source": {
                "vendor": "polar",
                "device_model": "verity_sense",
                "device_id": "dev-01",
            },
            "collection": {
                "mode": "online_live",
            },
            "time": {
                "device_time_reference": "ref-1",
                "first_sample_received_at_collector": "2026-04-25T10:00:00Z",
                "uploaded_at_collector": "2026-04-25T10:00:01Z",
            },
            "transport": {
                "encoding": "json",
                "compression": "none",
                "payload_schema": "custom.any",
                "payload_version": "0.1",
            },
            "payload": payload,
        }

        error_code, issues = validate_upload_chunk_contract(chunk)
        self.assertIsNone(error_code)
        self.assertEqual(issues, [])

    def test_malformed_transport_is_rejected(self) -> None:
        chunk = {
            "schema_version": "1.0",
            "chunk_id": "chunk-001",
            "session_id": "session-001",
            "stream_id": "stream-hr-001",
            "stream_type": "hr",
            "source": {
                "vendor": "polar",
                "device_model": "verity_sense",
                "device_id": "dev-01",
            },
            "collection": {
                "mode": "online_live",
            },
            "time": {
                "device_time_reference": "ref-1",
                "first_sample_received_at_collector": "2026-04-25T10:00:00Z",
                "uploaded_at_collector": "2026-04-25T10:00:01Z",
            },
            "transport": {
                "encoding": "json",
                "compression": "none",
                "payload_schema": "polar.hr",
                "payload_version": "1.0",
            },
            "payload": {},
        }

        error_code, issues = validate_upload_chunk_contract(chunk)
        self.assertEqual(error_code, "validation_error")
        self.assertTrue(any(item["field"] == "sequence" for item in issues))

    def test_chunk_time_with_legacy_server_timestamp_field_is_ignored(self) -> None:
        chunk = {
            "schema_version": "1.0",
            "chunk_id": "chunk-001",
            "session_id": "session-001",
            "stream_id": "stream-hr-001",
            "stream_type": "hr",
            "sequence": 1,
            "source": {
                "vendor": "polar",
                "device_model": "verity_sense",
                "device_id": "dev-01",
            },
            "collection": {
                "mode": "online_live",
            },
            "time": {
                "device_time_reference": "ref-1",
                "received_at_server": "2026-04-25T10:00:00Z",
                "uploaded_at_collector": "2026-04-25T10:00:01Z",
                "first_sample_received_at_collector": "2026-04-25T10:00:00Z",
            },
            "transport": {
                "encoding": "json",
                "compression": "none",
                "payload_schema": "polar.hr",
                "payload_version": "1.0",
            },
            "payload": {},
        }

        error_code, issues = validate_upload_chunk_contract(chunk)
        self.assertIsNone(error_code)
        self.assertEqual(issues, [])


if __name__ == "__main__":
    unittest.main()
