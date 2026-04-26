from __future__ import annotations

import logging
import re
from collections import defaultdict
from datetime import datetime

from remote_sync import RemoteConfig, load_remote_config, run_ssh_command

LOGGER = logging.getLogger(__name__)

SESSION_PATTERN = re.compile(
    r".*/(?P<layer>raw|processed)/.*?/user_id=(?P<user_id>[^/]+)/"
    r"(?:source=(?P<source>[^/]+)/)?(?:date=(?P<date>[^/]+)/)?session_id=(?P<session_id>[^/]+)(?:/.*)?$"
)


def _find_remote_session_paths(config: RemoteConfig, user_id: int | str) -> list[str]:
    base = config.remote_base_path.rstrip("/")
    user_segment = f"user_id={user_id}"

    raw_cmd = (
        f"find {base}/raw -type d -path '*/{user_segment}/*/session_id=*' "
        "2>/dev/null | sed -E 's#/(streams.*)?$##' || true"
    )
    processed_cmd = (
        f"find {base}/processed -type d -path '*/{user_segment}/*/session_id=*' "
        "2>/dev/null | sed -E 's#/(streams.*)?$##' || true"
    )

    raw_lines = [line.strip() for line in run_ssh_command(config, raw_cmd).splitlines() if line.strip()]
    processed_lines = [line.strip() for line in run_ssh_command(config, processed_cmd).splitlines() if line.strip()]
    return sorted(set(raw_lines + processed_lines))


def _normalize_record(path: str) -> dict[str, str]:
    match = SESSION_PATTERN.match(path)
    if not match:
        return {}

    row = match.groupdict()
    row["path"] = path
    row["source"] = row.get("source") or ""
    row["date"] = row.get("date") or ""
    return row


def _stream_and_artifact_commands(config: RemoteConfig, session_paths: list[str]) -> tuple[str, str]:
    quoted_paths = " ".join(f"'{path}'" for path in session_paths)
    streams_cmd = (
        "for p in "
        + quoted_paths
        + "; do "
        + "if [ -d \"$p/streams\" ]; then "
        + "for d in \"$p/streams\"/*; do [ -d \"$d\" ] && basename \"$d\"; done; "
        + "fi; done"
    )

    artifact_cmd = (
        "for p in "
        + quoted_paths
        + "; do "
        + "find \"$p\" -maxdepth 3 -type f "
        + "\\( -name '*.parquet' -o -name '*.json' -o -name '*.jsonl' \\) "
        + "2>/dev/null; "
        + "done"
    )
    return streams_cmd, artifact_cmd


def list_sessions(
    user_id: int | str,
    config: RemoteConfig | None = None,
    env_path: str | None = None,
) -> list[dict[str, object]]:
    """List sessions for user_id discovered via SSH from raw+processed trees."""
    cfg = config or load_remote_config(env_path=env_path)
    paths = _find_remote_session_paths(cfg, user_id=user_id)

    grouped: dict[str, dict[str, object]] = defaultdict(
        lambda: {
            "session_id": "",
            "user_id": str(user_id),
            "available_streams": set(),
            "available_artifacts": set(),
            "sources": set(),
            "dates": set(),
            "raw_paths": set(),
            "processed_paths": set(),
            "sort_ts": "",
        }
    )

    for path in paths:
        row = _normalize_record(path)
        if not row:
            continue

        session_id = row["session_id"]
        entry = grouped[session_id]
        entry["session_id"] = session_id

        if row["source"]:
            entry["sources"].add(row["source"])
        if row["date"]:
            entry["dates"].add(row["date"])
            entry["sort_ts"] = max(entry["sort_ts"], row["date"])

        if row["layer"] == "raw":
            entry["raw_paths"].add(path)
        if row["layer"] == "processed":
            entry["processed_paths"].add(path)

    for session_id, entry in grouped.items():
        session_paths = sorted(entry["raw_paths"] | entry["processed_paths"])
        if not session_paths:
            continue

        streams_cmd, artifact_cmd = _stream_and_artifact_commands(cfg, session_paths)
        streams = [line.strip() for line in run_ssh_command(cfg, streams_cmd).splitlines() if line.strip()]
        artifacts = [line.strip() for line in run_ssh_command(cfg, artifact_cmd).splitlines() if line.strip()]

        entry["available_streams"] = set(streams)
        entry["available_artifacts"] = set(_artifact_label(path) for path in artifacts)

    out: list[dict[str, object]] = []
    for session_id, entry in grouped.items():
        raw_paths = sorted(str(p) for p in entry["raw_paths"])
        processed_paths = sorted(str(p) for p in entry["processed_paths"])

        out.append(
            {
                "session_id": session_id,
                "user_id": str(entry["user_id"]),
                "available_streams": sorted(entry["available_streams"]),
                "available_artifacts": sorted(entry["available_artifacts"]),
                "sources": sorted(entry["sources"]),
                "dates": sorted(entry["dates"]),
                "raw_paths": raw_paths,
                "processed_paths": processed_paths,
                "sort_ts": entry["sort_ts"] or _fallback_sort_timestamp(session_id),
            }
        )

    out.sort(key=lambda row: str(row["sort_ts"]), reverse=True)
    LOGGER.info("session_discovery_completed", extra={"user_id": str(user_id), "session_count": len(out)})
    return out


def get_latest_session(
    user_id: int | str,
    config: RemoteConfig | None = None,
    env_path: str | None = None,
) -> dict[str, object]:
    sessions = list_sessions(user_id=user_id, config=config, env_path=env_path)
    if not sessions:
        raise ValueError(f"No sessions found for user_id={user_id}")
    latest = sessions[0]
    LOGGER.info("latest_session_selected", extra={"user_id": str(user_id), "session_id": latest["session_id"]})
    return latest


def _artifact_label(path: str) -> str:
    if path.endswith("chunks.jsonl"):
        return "raw_chunks"
    if path.endswith("session_summary.json"):
        return "session_summary"
    if "window_features" in path and path.endswith(".parquet"):
        return "window_features"
    if "clean_timeseries" in path and path.endswith(".parquet"):
        return "clean_timeseries"
    return path.rsplit("/", maxsplit=1)[-1]


def _fallback_sort_timestamp(session_id: str) -> str:
    for token in re.split(r"[^0-9]", session_id):
        if len(token) == 8:
            try:
                return datetime.strptime(token, "%Y%m%d").date().isoformat()
            except ValueError:
                continue
    return ""
