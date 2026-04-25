from __future__ import annotations

import argparse
import json
import logging
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

from fastapi import Body, FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from .config import (
    HEALTH_PATH,
    SERVICE_NAME,
    UPLOAD_PATH,
    resolve_host,
    resolve_port,
    resolve_raw_root_from_env,
)
from .models import AckResponse, AckStorage, ErrorResponse, UploadChunkRequest
from .validation import validate_upload_chunk_contract

logger = logging.getLogger(__name__)


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def sanitize_segment(value: str) -> str:
    return re.sub(r"[^a-zA-Z0-9._-]", "_", value)


def append_jsonl(raw_root: Path, session_id: str, stream_id: str, chunk: dict[str, object]) -> str:
    session_dir = raw_root / sanitize_segment(session_id)
    session_dir.mkdir(parents=True, exist_ok=True)

    target_file = session_dir / f"{sanitize_segment(stream_id)}.jsonl"
    raw_line = json.dumps(chunk, separators=(",", ":"), ensure_ascii=False)
    with target_file.open("a", encoding="utf-8") as handle:
        handle.write(raw_line)
        handle.write("\n")

    return str(target_file)


def ack_response(chunk: UploadChunkRequest, received_at_server: str, storage_path: str) -> AckResponse:
    return AckResponse(
        accepted=True,
        status="accepted",
        chunk_id=chunk.chunk_id,
        session_id=chunk.session_id,
        stream_id=chunk.stream_id,
        received_at_server=received_at_server,
        storage=AckStorage(raw_persisted=True, storage_path=storage_path),
        message="Chunk accepted and raw payload persisted.",
    )


def error_response(
    error_code: Literal["validation_error", "unsupported_schema", "persistence_error", "malformed_request"],
    message: str,
    details: list[dict[str, str]] | None = None,
) -> ErrorResponse:
    return ErrorResponse(
        accepted=False,
        status="rejected",
        error_code=error_code,
        message=message,
        details=details,
    )


def _format_request_validation_details(exc: RequestValidationError) -> list[dict[str, str]]:
    details: list[dict[str, str]] = []
    for issue in exc.errors():
        loc = []
        for part in issue.get("loc", ()):
            if part == "body":
                continue
            if isinstance(part, int) and loc:
                loc[-1] = f"{loc[-1]}[{part}]"
            else:
                loc.append(str(part))
        details.append({"field": ".".join(loc) or "request", "issue": issue.get("msg", "invalid request")})
    return details


def create_app(raw_root: Path) -> FastAPI:
    raw_root.mkdir(parents=True, exist_ok=True)
    app = FastAPI(title=SERVICE_NAME, version="1.0.0")
    app.state.raw_root = raw_root

    @app.exception_handler(RequestValidationError)
    async def request_validation_exception_handler(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        details = _format_request_validation_details(exc)
        has_json_parse_error = any(issue.get("type") == "json_invalid" for issue in exc.errors())
        error_code = "malformed_request" if has_json_parse_error else "validation_error"
        message = "Request body must be valid JSON" if has_json_parse_error else "Upload chunk validation failed"
        logger.warning(
            "request_validation_failed",
            extra={
                "error_code": error_code,
                "issues_count": len(details),
                "path": str(request.url.path),
            },
        )
        return JSONResponse(
            status_code=400,
            content=error_response(error_code, message, details=details or None).model_dump(),
        )

    @app.get(HEALTH_PATH)
    async def healthz() -> dict[str, str]:
        return {"status": "ok", "service": SERVICE_NAME}

    @app.post(
        UPLOAD_PATH,
        response_model=AckResponse,
        responses={
            400: {"model": ErrorResponse, "description": "Validation or malformed request error"},
            500: {"model": ErrorResponse, "description": "Persistence error"},
        },
    )
    async def upload_chunk(
        request: Request,
        chunk: UploadChunkRequest = Body(..., description="UploadChunk transport contract payload."),
    ) -> AckResponse | JSONResponse:
        raw_chunk = await request.json()
        error_code, issues = validate_upload_chunk_contract(raw_chunk)
        if error_code:
            logger.warning(
                "upload_validation_failed",
                extra={
                    "error_code": error_code,
                    "issues_count": len(issues),
                    "chunk_id": chunk.chunk_id,
                    "session_id": chunk.session_id,
                    "stream_id": chunk.stream_id,
                },
            )
            return JSONResponse(
                status_code=400,
                content=error_response(
                    error_code,
                    "Upload chunk validation failed",
                    details=issues or None,
                ).model_dump(),
            )

        received_at_server = utc_now_iso()

        try:
            storage_path = append_jsonl(app.state.raw_root, chunk.session_id, chunk.stream_id, raw_chunk)
        except OSError as exc:
            logger.exception(
                "upload_persistence_failed",
                extra={
                    "chunk_id": chunk.chunk_id,
                    "session_id": chunk.session_id,
                    "stream_id": chunk.stream_id,
                },
            )
            return JSONResponse(
                status_code=500,
                content=error_response(
                    "persistence_error",
                    "Failed to persist raw chunk",
                    details=[{"field": "storage", "issue": str(exc)}],
                ).model_dump(),
            )

        logger.info(
            "upload_accepted",
            extra={
                "chunk_id": chunk.chunk_id,
                "session_id": chunk.session_id,
                "stream_id": chunk.stream_id,
                "storage_path": storage_path,
            },
        )
        return ack_response(chunk, received_at_server, storage_path)

    return app


def main(argv: list[str] | None = None) -> int:
    import uvicorn

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")

    parser = argparse.ArgumentParser(description="Wearable ingestion API")
    parser.add_argument("--host", default=resolve_host())
    parser.add_argument("--port", type=int, default=resolve_port())
    parser.add_argument("--raw-root", default=str(resolve_raw_root_from_env()))
    args = parser.parse_args(argv)

    app = create_app(Path(args.raw_root))
    logger.info("%s listening on http://%s:%s", SERVICE_NAME, args.host, args.port)
    logger.info("raw path: %s", Path(args.raw_root))
    uvicorn.run(app, host=args.host, port=args.port, log_level="warning")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
