#!/usr/bin/env python3
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

SERVICE_ROOT = Path(__file__).resolve().parents[1]
if str(SERVICE_ROOT) not in sys.path:
    sys.path.insert(0, str(SERVICE_ROOT))

try:
    from fastapi.testclient import TestClient
    from wearable_ingestion_api.server import create_app
except ModuleNotFoundError as exc:
    print(f"SKIP: missing dependency for smoke test: {exc}")
    raise SystemExit(0)


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp_dir:
        app = create_app(Path(tmp_dir))
        client = TestClient(app)

        valid_chunk = {
            "schema_version": "1.0",
            "chunk_id": "smoke-chunk-001",
            "session_id": "smoke-session-001",
            "stream_id": "stream-hr-001",
            "sequence": 1,
            "time": {
                "received_at_collector": "2026-04-25T11:00:00Z",
                "uploaded_at_collector": "2026-04-25T11:00:01Z",
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
                        "received_at_collector": "2026-04-25T11:00:00.000Z",
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

        invalid_chunk = {
            **valid_chunk,
            "chunk_id": "smoke-chunk-002",
            "transport": {
                "compression": "none",
                "payload_schema": "polar.hr",
                "payload_version": "1.0",
            },
        }

        valid_response = client.post("/upload-chunk", json=valid_chunk)
        invalid_response = client.post("/upload-chunk", json=invalid_chunk)

        if valid_response.status_code != 200:
            print("FAIL: valid payload was not accepted")
            return 1

        valid_body = valid_response.json()
        storage_path = Path(valid_body["storage"]["storage_path"])
        if not storage_path.exists():
            print("FAIL: raw JSONL file was not written")
            return 1

        raw_line = storage_path.read_text(encoding="utf-8").strip()
        if not raw_line:
            print("FAIL: raw JSONL file is empty")
            return 1

        if invalid_response.status_code != 400 or invalid_response.json().get("status") != "rejected":
            print("FAIL: malformed transport was not rejected")
            return 1

        print("OK: HR upload accepted")
        print(f"OK: raw JSONL written at {storage_path}")
        print("OK: ACK returned")
        print("OK: malformed transport rejected")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
