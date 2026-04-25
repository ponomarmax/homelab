from __future__ import annotations

from typing import Any


def _is_non_empty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def validate_polar_hr_payload(payload: Any) -> list[dict[str, str]]:
    issues: list[dict[str, str]] = []

    if not isinstance(payload, dict):
        return [{"field": "payload", "issue": "must be an object"}]

    samples = payload.get("samples")
    if not isinstance(samples, list) or len(samples) == 0:
        issues.append({"field": "payload.samples", "issue": "must be a non-empty array"})
        return issues

    for index, sample in enumerate(samples):
        field_prefix = f"payload.samples[{index}]"
        if not isinstance(sample, dict):
            issues.append({"field": field_prefix, "issue": "must be an object"})
            continue

        required_keys = {
            "hr",
            "ppgQuality",
            "correctedHr",
            "rrsMs",
            "rrAvailable",
            "contactStatus",
            "contactStatusSupported",
        }

        for key in required_keys:
            if key not in sample:
                issues.append({"field": f"{field_prefix}.{key}", "issue": "is required"})

        allowed_keys = required_keys
        unknown = set(sample.keys()) - allowed_keys
        for key in sorted(unknown):
            issues.append({"field": f"{field_prefix}.{key}", "issue": "is not allowed"})

        if "hr" in sample and (not isinstance(sample["hr"], int) or sample["hr"] < 0):
            issues.append({"field": f"{field_prefix}.hr", "issue": "must be integer >= 0"})

        if "ppgQuality" in sample and not isinstance(sample["ppgQuality"], int):
            issues.append({"field": f"{field_prefix}.ppgQuality", "issue": "must be an integer"})

        if "correctedHr" in sample and (
            not isinstance(sample["correctedHr"], int) or sample["correctedHr"] < 0
        ):
            issues.append({"field": f"{field_prefix}.correctedHr", "issue": "must be integer >= 0"})

        if "rrsMs" in sample:
            rrs_ms = sample["rrsMs"]
            if not isinstance(rrs_ms, list):
                issues.append({"field": f"{field_prefix}.rrsMs", "issue": "must be an array"})
            else:
                for rr_index, rr in enumerate(rrs_ms):
                    if not isinstance(rr, int) or rr < 0:
                        issues.append(
                            {
                                "field": f"{field_prefix}.rrsMs[{rr_index}]",
                                "issue": "must be integer >= 0",
                            }
                        )

        for boolean_key in ["rrAvailable", "contactStatus", "contactStatusSupported"]:
            if boolean_key in sample and not isinstance(sample[boolean_key], bool):
                issues.append(
                    {
                        "field": f"{field_prefix}.{boolean_key}",
                        "issue": "must be boolean",
                    }
                )

    return issues


def validate_upload_chunk_contract(chunk: Any) -> tuple[str | None, list[dict[str, str]]]:
    issues: list[dict[str, str]] = []

    if not isinstance(chunk, dict):
        return "malformed_request", [{"field": "request", "issue": "must be a JSON object"}]

    required_fields = [
        "schema_version",
        "chunk_id",
        "session_id",
        "stream_id",
        "sequence",
        "time",
        "transport",
        "payload",
    ]

    for key in required_fields:
        if key not in chunk:
            issues.append({"field": key, "issue": "is required"})

    if issues:
        return "validation_error", issues

    if chunk.get("schema_version") != "1.0":
        issues.append({"field": "schema_version", "issue": "must be '1.0'"})

    for key in ["chunk_id", "session_id", "stream_id"]:
        if not _is_non_empty_string(chunk.get(key)):
            issues.append({"field": key, "issue": "must be a non-empty string"})

    sequence = chunk.get("sequence")
    if not isinstance(sequence, int) or sequence < 1:
        issues.append({"field": "sequence", "issue": "must be integer >= 1"})

    time_obj = chunk.get("time")
    if not isinstance(time_obj, dict):
        issues.append({"field": "time", "issue": "must be an object"})
    else:
        for key in ["received_at_collector", "uploaded_at_collector"]:
            if not _is_non_empty_string(time_obj.get(key)):
                issues.append({"field": f"time.{key}", "issue": "must be a non-empty string"})

    transport = chunk.get("transport")
    if not isinstance(transport, dict):
        issues.append({"field": "transport", "issue": "must be an object"})
        return "validation_error", issues

    if transport.get("encoding") != "json":
        issues.append({"field": "transport.encoding", "issue": "must be 'json'"})

    payload_schema = transport.get("payload_schema")
    payload_version = transport.get("payload_version")

    if not _is_non_empty_string(payload_schema):
        issues.append({"field": "transport.payload_schema", "issue": "must be a non-empty string"})
    if not _is_non_empty_string(payload_version):
        issues.append({"field": "transport.payload_version", "issue": "must be a non-empty string"})

    if issues:
        return "validation_error", issues

    if payload_schema != "polar.hr" or payload_version != "1.0":
        return "unsupported_schema", [
            {
                "field": "transport",
                "issue": "only polar.hr@1.0 is supported in CP3",
            }
        ]

    payload_issues = validate_polar_hr_payload(chunk.get("payload"))
    if payload_issues:
        return "validation_error", payload_issues

    return None, []
