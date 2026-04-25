from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[3]
INGESTION_API_ROOT = Path(__file__).resolve().parents[1]
if str(INGESTION_API_ROOT) not in sys.path:
    sys.path.insert(0, str(INGESTION_API_ROOT))

from ingestion_api.validation import validate_upload_chunk_contract


class ValidationAndSchemaTests(unittest.TestCase):
    def test_polar_hr_schema_matches_real_stream_shape(self) -> None:
        schema_path = PROJECT_ROOT / "packages/schemas/payloads/polar/polar.hr.v1.schema.json"
        schema = json.loads(schema_path.read_text(encoding="utf-8"))

        sample_required = schema["properties"]["samples"]["items"]["required"]
        self.assertEqual(
            sample_required,
            [
                "hr",
                "ppgQuality",
                "correctedHr",
                "rrsMs",
                "rrAvailable",
                "contactStatus",
                "contactStatusSupported",
            ],
        )

        self.assertNotIn("offset_ns", sample_required)

    def test_polar_hr_example_passes_upload_contract_validation(self) -> None:
        example_path = PROJECT_ROOT / "packages/schemas/examples/payloads/polar.hr.v1.json"
        payload = json.loads(example_path.read_text(encoding="utf-8"))

        chunk = {
            "schema_version": "1.0",
            "chunk_id": "chunk-001",
            "session_id": "session-001",
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
            "payload": payload,
        }

        error_code, issues = validate_upload_chunk_contract(chunk)
        self.assertIsNone(error_code)
        self.assertEqual(issues, [])


if __name__ == "__main__":
    unittest.main()
