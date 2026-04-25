from __future__ import annotations

from typing import Any

from pydantic import ValidationError

from .models import UploadChunkRequest


def _loc_to_field(loc: tuple[Any, ...]) -> str:
    parts: list[str] = []
    for item in loc:
        if item == "body":
            continue
        if isinstance(item, int):
            if not parts:
                parts.append(f"[{item}]")
            else:
                parts[-1] = f"{parts[-1]}[{item}]"
            continue
        parts.append(str(item))
    return ".".join(parts) or "request"


def format_validation_issues(exc: ValidationError) -> list[dict[str, str]]:
    issues: list[dict[str, str]] = []
    for issue in exc.errors():
        issues.append(
            {
                "field": _loc_to_field(tuple(issue.get("loc", ()))),
                "issue": issue.get("msg", "invalid value"),
            }
        )
    return issues


def validate_upload_chunk_contract(chunk: Any) -> tuple[str | None, list[dict[str, str]]]:
    if not isinstance(chunk, dict):
        return "malformed_request", [{"field": "request", "issue": "must be a JSON object"}]

    try:
        UploadChunkRequest.model_validate(chunk)
    except ValidationError as exc:
        return "validation_error", format_validation_issues(exc)

    return None, []
