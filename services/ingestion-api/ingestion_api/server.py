from __future__ import annotations

import argparse
import json
import os
import re
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from .validation import validate_upload_chunk_contract


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def sanitize_segment(value: str) -> str:
    return re.sub(r"[^a-zA-Z0-9._-]", "_", value)


def append_jsonl(raw_root: Path, chunk: dict[str, Any]) -> str:
    session_id = sanitize_segment(chunk["session_id"])
    stream_id = sanitize_segment(chunk["stream_id"])

    session_dir = raw_root / session_id
    session_dir.mkdir(parents=True, exist_ok=True)

    target_file = session_dir / f"{stream_id}.jsonl"
    with target_file.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(chunk, separators=(",", ":"), ensure_ascii=False))
        handle.write("\n")

    return str(target_file)


def ack_response(chunk: dict[str, Any], received_at_server: str, storage_path: str) -> dict[str, Any]:
    return {
        "accepted": True,
        "status": "accepted",
        "chunk_id": chunk["chunk_id"],
        "session_id": chunk["session_id"],
        "stream_id": chunk["stream_id"],
        "received_at_server": received_at_server,
        "storage": {
            "raw_persisted": True,
            "storage_path": storage_path,
        },
        "message": "Chunk accepted and raw payload persisted.",
    }


def error_response(
    error_code: str,
    message: str,
    details: list[dict[str, str]] | None = None,
) -> dict[str, Any]:
    response: dict[str, Any] = {
        "accepted": False,
        "status": "rejected",
        "error_code": error_code,
        "message": message,
    }
    if details:
        response["details"] = details
    return response


class IngestionRequestHandler(BaseHTTPRequestHandler):
    raw_root: Path = Path("data/raw/wearable")

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/upload-chunk":
            self._write_json(
                HTTPStatus.NOT_FOUND,
                error_response(
                    "malformed_request",
                    "Unsupported endpoint. Use POST /upload-chunk",
                ),
            )
            return

        content_length_header = self.headers.get("Content-Length", "")
        try:
            content_length = int(content_length_header)
        except ValueError:
            self._write_json(
                HTTPStatus.BAD_REQUEST,
                error_response(
                    "malformed_request",
                    "Content-Length header must be an integer",
                ),
            )
            return

        body = self.rfile.read(content_length)

        try:
            chunk = json.loads(body.decode("utf-8"))
        except json.JSONDecodeError as exc:
            self._write_json(
                HTTPStatus.BAD_REQUEST,
                error_response(
                    "malformed_request",
                    "Request body must be valid JSON",
                    details=[{"field": "request", "issue": str(exc)}],
                ),
            )
            return

        error_code, issues = validate_upload_chunk_contract(chunk)
        if error_code:
            status = (
                HTTPStatus.UNPROCESSABLE_ENTITY
                if error_code in {"validation_error", "unsupported_schema"}
                else HTTPStatus.BAD_REQUEST
            )
            self._write_json(
                status,
                error_response(
                    error_code,
                    "Upload chunk validation failed",
                    details=issues,
                ),
            )
            return

        received_at_server = utc_now_iso()

        # Raw-first rule: persist transport chunk as-is, without timestamp normalization.
        chunk["time"]["received_at_server"] = received_at_server

        try:
            storage_path = append_jsonl(self.raw_root, chunk)
        except OSError as exc:
            self._write_json(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                error_response(
                    "persistence_error",
                    "Failed to persist raw chunk",
                    details=[{"field": "storage", "issue": str(exc)}],
                ),
            )
            return

        self._write_json(
            HTTPStatus.OK,
            ack_response(chunk, received_at_server, storage_path),
        )

    def log_message(self, format: str, *args: object) -> None:  # noqa: A003
        return

    def _write_json(self, status_code: HTTPStatus, payload: dict[str, Any]) -> None:
        data = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def create_server(host: str, port: int, raw_root: Path) -> ThreadingHTTPServer:
    class ConfiguredHandler(IngestionRequestHandler):
        pass

    ConfiguredHandler.raw_root = raw_root
    return ThreadingHTTPServer((host, port), ConfiguredHandler)


def resolve_default_raw_root() -> Path:
    repo_root = Path(__file__).resolve().parents[3]
    return repo_root / "data" / "raw" / "wearable"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Wearable ingestion API")
    parser.add_argument("--host", default=os.environ.get("INGESTION_API_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("INGESTION_API_PORT", "8090")))
    parser.add_argument(
        "--raw-root",
        default=os.environ.get("WEARABLE_RAW_DATA_PATH", str(resolve_default_raw_root())),
    )

    args = parser.parse_args(argv)

    raw_root = Path(args.raw_root)
    raw_root.mkdir(parents=True, exist_ok=True)

    server = create_server(args.host, args.port, raw_root)
    print(f"Ingestion API listening on http://{args.host}:{args.port}")
    print(f"Raw path: {raw_root}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
