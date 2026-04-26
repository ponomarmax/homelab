from __future__ import annotations

import json
import logging
import os
import shlex
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from remote_sync import load_remote_config, run_ssh_command
from run_state_viewer import format_run_line, summarize_pipeline_for_session, summarize_run

LOGGER = logging.getLogger(__name__)

DEFAULT_PIPELINE_API_BASE_URL = "http://127.0.0.1:18091"
DEFAULT_PIPELINE_PATH = "/api/v1/pipeline/normalize/hr"
DEFAULT_SERVER_PIPELINE_PORT = "18091"


class PipelineClientError(RuntimeError):
    """Raised for pipeline client failures."""


def _load_env_file(env_path: str | os.PathLike[str] | None) -> None:
    if env_path is None:
        return
    path = Path(env_path)
    if not path.exists():
        return

    for line in path.read_text(encoding="utf-8").splitlines():
        text = line.strip()
        if not text or text.startswith("#") or "=" not in text:
            continue
        key, value = text.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def _load_default_env_sources(env_path: str | os.PathLike[str] | None) -> None:
    candidates: list[Path] = []
    if env_path is not None:
        candidates.append(Path(env_path))

    module_path = Path(__file__).resolve()
    notebooks_root = module_path.parents[1]
    repo_root = module_path.parents[2]
    candidates.append(notebooks_root / ".env")
    candidates.append(repo_root / ".env")

    seen: set[Path] = set()
    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        if candidate.exists():
            _load_env_file(candidate)


def _post_json(url: str, payload: dict[str, Any] | None = None, timeout_seconds: int = 300) -> dict[str, Any]:
    body = json.dumps(payload or {}).encode("utf-8")
    request = urllib.request.Request(
        url=url,
        data=body,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            raw = response.read().decode("utf-8")
            data = json.loads(raw) if raw else {}
            if not isinstance(data, dict):
                raise PipelineClientError(f"Unexpected non-object response from {url}")
            return data
    except urllib.error.URLError as exc:
        raise PipelineClientError(f"Failed POST {url}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise PipelineClientError(f"Invalid JSON response from {url}") from exc


def _pipeline_port_from_env() -> str:
    return (
        os.environ.get("WEARABLE_PIPELINE_API_PORT", "").strip()
        or os.environ.get("WEARABLE_PIPELINE_API_INTERNAL_PORT", "").strip()
        or DEFAULT_SERVER_PIPELINE_PORT
    )


def _derive_pipeline_base_url() -> str:
    explicit = os.environ.get("PIPELINE_API_BASE_URL", "").strip()
    if explicit:
        return explicit

    lan_host = os.environ.get("WEARABLE_PIPELINE_API_LAN_HOST", "").strip()
    if lan_host:
        return f"http://{lan_host}:{_pipeline_port_from_env()}"

    server_ip = os.environ.get("SERVER_IP", "").strip()
    if server_ip:
        return f"http://{server_ip}:{_pipeline_port_from_env()}"

    return DEFAULT_PIPELINE_API_BASE_URL


def _post_pipeline_via_ssh(env_path: str | os.PathLike[str] | None, timeout_seconds: int) -> dict[str, Any]:
    cfg = load_remote_config(env_path=env_path)
    port = _pipeline_port_from_env()
    cmd = (
        "curl -fsS -X POST "
        + "-H 'accept: application/json' "
        + "-H 'content-type: application/json' "
        + f"http://127.0.0.1:{port}{DEFAULT_PIPELINE_PATH}"
    )
    output = run_ssh_command(cfg, cmd, retries=max(1, int(timeout_seconds // 15)))
    try:
        payload = json.loads(output) if output else {}
    except json.JSONDecodeError as exc:
        raise PipelineClientError("Pipeline SSH trigger returned non-JSON response.") from exc
    if not isinstance(payload, dict):
        raise PipelineClientError("Pipeline SSH trigger returned invalid JSON object.")
    return payload


def _state_root_from_env() -> str:
    return os.environ.get("PIPELINE_STATE_ROOT", f"{os.environ.get('REMOTE_BASE_PATH', '/data/wearable')}/pipeline_runs")


def _discover_pipeline_container(config) -> str | None:
    cmd = "docker ps --format '{{.Names}}' | grep -E 'wearable-pipeline-api' | head -n 1"
    out = run_ssh_command(config, cmd)
    return out.strip() or None


def _fetch_remote_state_records(session_id: str, env_path: str | os.PathLike[str] | None) -> list[dict[str, Any]]:
    cfg = load_remote_config(env_path=env_path)
    state_root = _state_root_from_env()
    session_literal = json.dumps(str(session_id))

    cmd = (
        "find "
        + shlex.quote(state_root)
        + " -type f -name '*.json' 2>/dev/null | while read -r f; do "
        + "grep -Fq '"
        + '"session_id": '
        + f"{session_literal}' "
        + '"$f" && { echo "__STATE_FILE__:$f"; cat "$f"; echo; }; '
        + "done"
    )

    output = run_ssh_command(cfg, cmd)
    if not output.strip():
        container = _discover_pipeline_container(cfg)
        if container:
            container_state_root = os.environ.get("REMOTE_CONTAINER_STATE_ROOT", "/data/wearable/pipeline_runs")
            cmd = (
                f"docker exec {shlex.quote(container)} sh -lc "
                + shlex.quote(
                    "find "
                    + shlex.quote(container_state_root)
                    + " -type f -name '*.json' 2>/dev/null | while read -r f; do "
                    + "grep -Fq '"
                    + '\"session_id\": '
                    + f"{session_literal}' "
                    + '\"$f\" && { echo \"__STATE_FILE__:$f\"; cat \"$f\"; echo; }; '
                    + "done"
                )
            )
            output = run_ssh_command(cfg, cmd)
    records: list[dict[str, Any]] = []
    current_path: str | None = None
    current_lines: list[str] = []

    for line in output.splitlines():
        if line.startswith("__STATE_FILE__:"):
            if current_path is not None and current_lines:
                parsed = _parse_state_json_block("\n".join(current_lines), current_path)
                if parsed is not None:
                    records.append(parsed)
            current_path = line.split(":", 1)[1]
            current_lines = []
            continue

        if current_path is not None:
            current_lines.append(line)

    if current_path is not None and current_lines:
        parsed = _parse_state_json_block("\n".join(current_lines), current_path)
        if parsed is not None:
            records.append(parsed)

    return records


def _parse_state_json_block(text: str, path: str) -> dict[str, Any] | None:
    payload = text.strip()
    if not payload:
        return None

    try:
        data = json.loads(payload)
    except json.JSONDecodeError:
        return None

    if not isinstance(data, dict):
        return None

    data.setdefault("state_path", path)
    return data


def run_full_pipeline(
    session_id: str,
    user_id: int | str,
    api_base_url: str | None = None,
    poll_interval_seconds: float = 3.0,
    request_timeout_seconds: int = 1200,
    env_path: str | os.PathLike[str] | None = None,
    live_progress: bool = True,
) -> dict[str, Any]:
    """Trigger pipeline run and print progress while running."""
    _load_default_env_sources(env_path)

    base_url = (api_base_url or _derive_pipeline_base_url()).rstrip("/")
    url = f"{base_url}{DEFAULT_PIPELINE_PATH}"

    LOGGER.info("pipeline_run_start", extra={"session_id": session_id, "user_id": str(user_id), "url": url})

    result_holder: dict[str, Any] = {}
    error_holder: dict[str, BaseException] = {}

    def _runner() -> None:
        try:
            result_holder["response"] = _post_json(url, payload={}, timeout_seconds=request_timeout_seconds)
        except BaseException as direct_exc:  # noqa: BLE001
            LOGGER.warning("pipeline_http_trigger_failed", extra={"error": str(direct_exc), "url": url})
            try:
                # Fallback: trigger directly on the server over SSH.
                result_holder["response"] = _post_pipeline_via_ssh(env_path=env_path, timeout_seconds=request_timeout_seconds)
            except BaseException as ssh_exc:  # noqa: BLE001
                error_holder["error"] = ssh_exc

    worker = threading.Thread(target=_runner, daemon=True)
    worker.start()

    seen_progress: set[tuple[str, str, str]] = set()
    while worker.is_alive():
        if live_progress:
            try:
                state_records = _fetch_remote_state_records(session_id=session_id, env_path=env_path)
                for record in state_records:
                    summary = summarize_run(record)
                    marker = (
                        str(summary.get("run_id", "")),
                        str(summary.get("step_name", "")),
                        str(summary.get("status", "")),
                    )
                    if marker in seen_progress:
                        continue
                    seen_progress.add(marker)
                    print(format_run_line(summary))
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("pipeline_progress_poll_failed", extra={"error": str(exc)})

        time.sleep(max(0.5, float(poll_interval_seconds)))

    worker.join()

    if "error" in error_holder:
        raise PipelineClientError(str(error_holder["error"])) from error_holder["error"]

    response = result_holder.get("response")
    if not isinstance(response, dict):
        raise PipelineClientError("Pipeline response is missing or invalid.")

    session_summaries = summarize_pipeline_for_session(response=response, session_id=str(session_id))
    if session_summaries:
        print("Final step summary:")
        for summary in session_summaries:
            print(format_run_line(summary))
    else:
        print(
            "Warning: selected session was not found in pipeline response. "
            "The API may have processed different sessions."
        )

    LOGGER.info("pipeline_run_finished", extra={"session_id": session_id, "summary_count": len(session_summaries)})
    return {
        "response": response,
        "session_summaries": session_summaries,
    }
