#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import tempfile
import threading
import urllib.error
import urllib.request
from pathlib import Path

SERVICE_ROOT = Path(__file__).resolve().parents[1]
if str(SERVICE_ROOT) not in sys.path:
    sys.path.insert(0, str(SERVICE_ROOT))

from ingestion_api.server import create_server


def post_json(url: str, body: dict) -> tuple[int, dict]:
    request = urllib.request.Request(
        url,
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


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp_dir:
        raw_root = Path(tmp_dir)
        server = create_server("127.0.0.1", 0, raw_root)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        host, port = server.server_address
        url = f"http://{host}:{port}/upload-chunk"

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
            "sequence": 2,
            "payload": {"samples": [{"hr": 71}]},
        }

        valid_status, valid_response = post_json(url, valid_chunk)
        invalid_status, invalid_response = post_json(url, invalid_chunk)

        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

        if valid_status != 200:
            print("FAIL: valid payload was not accepted")
            return 1

        storage_path = Path(valid_response["storage"]["storage_path"])
        if not storage_path.exists():
            print("FAIL: raw JSONL file was not written")
            return 1

        raw_line = storage_path.read_text(encoding="utf-8").strip()
        if not raw_line:
            print("FAIL: raw JSONL file is empty")
            return 1

        if invalid_status != 422 or invalid_response.get("status") != "rejected":
            print("FAIL: invalid payload was not rejected")
            return 1

        print("OK: HR upload accepted")
        print(f"OK: raw JSONL written at {storage_path}")
        print("OK: ACK returned")
        print("OK: invalid payload rejected")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
