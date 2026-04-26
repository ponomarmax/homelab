from __future__ import annotations

import logging
import os
import re
import shlex
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

LOGGER = logging.getLogger(__name__)

DEFAULT_RETRIES = 3
DEFAULT_RETRY_DELAY_SECONDS = 2.0
CONTAINER_PREFIX = "container://"
DEFAULT_CONTAINER_DATA_ROOT = "/data/wearable"


class RemoteSyncError(RuntimeError):
    """Raised when remote SSH/rsync actions fail."""


@dataclass(frozen=True)
class RemoteConfig:
    remote_host: str
    remote_user: str
    remote_base_path: str
    ssh_key_path: str | None = None

    @property
    def target(self) -> str:
        return f"{self.remote_user}@{self.remote_host}"


def load_remote_config(env_path: str | os.PathLike[str] | None = None) -> RemoteConfig:
    _load_default_env_sources(env_path=env_path)

    host = (os.environ.get("REMOTE_HOST", "") or os.environ.get("SERVER_IP", "")).strip()
    user = (os.environ.get("REMOTE_USER", "") or os.environ.get("SERVER_USER", "")).strip()
    base_path = os.environ.get("REMOTE_BASE_PATH", "/data/wearable").strip()
    ssh_key = os.environ.get("SSH_KEY_PATH", "").strip() or None

    if not host or not user:
        raise RemoteSyncError(
            "Remote connection is not configured. Set REMOTE_HOST/REMOTE_USER "
            "(or SERVER_IP/SERVER_USER) in notebooks/.env or repository .env."
        )

    return RemoteConfig(
        remote_host=host,
        remote_user=user,
        remote_base_path=base_path,
        ssh_key_path=ssh_key,
    )


def _load_env_file(env_path: Path) -> None:
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def _load_default_env_sources(env_path: str | os.PathLike[str] | None = None) -> None:
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


def _quote(value: str) -> str:
    return shlex.quote(value)


def _ssh_base_cmd(config: RemoteConfig) -> list[str]:
    cmd = ["ssh", "-o", "BatchMode=yes"]
    if config.ssh_key_path:
        cmd.extend(["-i", config.ssh_key_path])
    cmd.append(config.target)
    return cmd


def run_ssh_command(
    config: RemoteConfig,
    remote_command: str,
    retries: int = DEFAULT_RETRIES,
    retry_delay_seconds: float = DEFAULT_RETRY_DELAY_SECONDS,
) -> str:
    last_error: Exception | None = None
    command = _ssh_base_cmd(config) + [remote_command]

    for attempt in range(1, retries + 1):
        LOGGER.info("ssh_command_start", extra={"attempt": attempt, "command": remote_command})
        try:
            result = subprocess.run(command, check=True, capture_output=True, text=True)
            LOGGER.info("ssh_command_success", extra={"attempt": attempt})
            return result.stdout.strip()
        except subprocess.CalledProcessError as exc:
            last_error = exc
            LOGGER.warning(
                "ssh_command_failed",
                extra={"attempt": attempt, "stderr": (exc.stderr or "").strip()},
            )
            if attempt < retries:
                time.sleep(retry_delay_seconds)

    raise RemoteSyncError(f"SSH command failed after {retries} attempts: {remote_command}") from last_error


def _rsync_base_cmd(config: RemoteConfig) -> list[str]:
    ssh_parts = ["ssh", "-o", "BatchMode=yes"]
    if config.ssh_key_path:
        ssh_parts.extend(["-i", config.ssh_key_path])

    return [
        "rsync",
        "-az",
        "--partial",
        "--info=stats1,progress2",
        "-e",
        " ".join(ssh_parts),
    ]


def _discover_pipeline_container(config: RemoteConfig) -> str | None:
    cmd = "docker ps --format '{{.Names}}' | grep -E 'wearable-pipeline-api' | head -n 1"
    out = run_ssh_command(config, cmd)
    name = out.strip()
    return name or None


def _discover_session_paths_host(config: RemoteConfig, user_id: int | str, session_id: str | None = None) -> list[str]:
    user_segment = f"user_id={user_id}"
    session_filter = f"session_id={session_id}" if session_id else "session_id=*"

    processed_root = f"{config.remote_base_path.rstrip('/')}/processed"
    raw_root = f"{config.remote_base_path.rstrip('/')}/raw"

    processed_cmd = (
        f"find {_quote(processed_root)} -type d -path '*/{user_segment}/*{session_filter}' 2>/dev/null || true"
    )
    raw_cmd = f"find {_quote(raw_root)} -type d -path '*/{user_segment}/*{session_filter}' 2>/dev/null || true"

    processed = [line.strip() for line in run_ssh_command(config, processed_cmd).splitlines() if line.strip()]
    raw = [line.strip() for line in run_ssh_command(config, raw_cmd).splitlines() if line.strip()]
    return sorted(set(processed + raw))


def _container_data_root() -> str:
    return os.environ.get("REMOTE_CONTAINER_DATA_ROOT", DEFAULT_CONTAINER_DATA_ROOT).rstrip("/")


def _discover_session_paths_container(
    config: RemoteConfig,
    container: str,
    user_id: int | str,
    session_id: str | None = None,
) -> list[str]:
    data_root = _container_data_root()
    user_segment = f"user_id={user_id}"
    session_filter = f"session_id={session_id}" if session_id else "session_id=*"

    processed_root = f"{data_root}/processed"
    raw_root = f"{data_root}/raw"

    processed_find = f"find {_quote(processed_root)} -type d -path '*/{user_segment}/*{session_filter}' 2>/dev/null || true"
    raw_find = f"find {_quote(raw_root)} -type d -path '*/{user_segment}/*{session_filter}' 2>/dev/null || true"

    cmd = (
        f"docker exec {_quote(container)} sh -lc "
        + _quote(processed_find + "\n" + raw_find)
    )
    out = run_ssh_command(config, cmd)
    raw_paths = [line.strip() for line in out.splitlines() if line.strip()]
    return sorted({f"{CONTAINER_PREFIX}{container}{path}" for path in raw_paths})


def _discover_session_paths(config: RemoteConfig, user_id: int | str, session_id: str | None = None) -> list[str]:
    host_paths = _discover_session_paths_host(config, user_id=user_id, session_id=session_id)
    if host_paths:
        LOGGER.info("session_discovery_mode", extra={"mode": "host_fs", "count": len(host_paths)})
        return host_paths

    container = _discover_pipeline_container(config)
    if not container:
        return []

    container_paths = _discover_session_paths_container(
        config,
        container=container,
        user_id=user_id,
        session_id=session_id,
    )
    if container_paths:
        LOGGER.info("session_discovery_mode", extra={"mode": "container_fs", "count": len(container_paths)})
    return container_paths


def _extract_session_id(path: str) -> str:
    match = re.search(r"/session_id=([^/]+)", path)
    return match.group(1) if match else ""


def _extract_date(path: str) -> str:
    match = re.search(r"/date=([^/]+)", path)
    return match.group(1) if match else ""


def _split_container_path(value: str) -> tuple[str, str] | None:
    if not value.startswith(CONTAINER_PREFIX):
        return None
    rest = value[len(CONTAINER_PREFIX) :]
    slash = rest.find("/")
    if slash <= 0:
        return None
    container = rest[:slash]
    remote_path = rest[slash:]
    return container, remote_path


def _discover_streams_for_paths(config: RemoteConfig, session_paths: list[str]) -> set[str]:
    streams: set[str] = set()
    for session_path in session_paths:
        container_parts = _split_container_path(session_path)
        if container_parts:
            container, remote_path = container_parts
            cmd = (
                f"docker exec {_quote(container)} sh -lc "
                + _quote(
                    f"if [ -d {_quote(remote_path + '/streams')} ]; then "
                    f"for d in {_quote(remote_path + '/streams')}/*; do [ -d \"$d\" ] && basename \"$d\"; done; "
                    "fi"
                )
            )
        else:
            cmd = (
                f"if [ -d {_quote(session_path + '/streams')} ]; then "
                f"for d in {_quote(session_path + '/streams')}/*; do [ -d \"$d\" ] && basename \"$d\"; done; "
                "fi"
            )

        out = run_ssh_command(config, cmd)
        streams.update(line.strip() for line in out.splitlines() if line.strip())
    return streams


def _latest_epoch_for_path(config: RemoteConfig, session_path: str) -> float:
    container_parts = _split_container_path(session_path)
    if container_parts:
        container, remote_path = container_parts
        cmd = (
            f"docker exec {_quote(container)} sh -lc "
            + _quote(
                f"(find {_quote(remote_path)} -type f -printf '%T@\\n' 2>/dev/null | sort -nr | head -n 1) "
                f"|| stat -c %Y {_quote(remote_path)} 2>/dev/null || echo 0"
            )
        )
    else:
        cmd = (
            f"(find {_quote(session_path)} -type f -printf '%T@\\n' 2>/dev/null | sort -nr | head -n 1) "
            f"|| stat -c %Y {_quote(session_path)} 2>/dev/null || echo 0"
        )

    output = run_ssh_command(config, cmd)
    first_line = output.splitlines()[0].strip() if output.strip() else "0"
    try:
        return float(first_line)
    except ValueError:
        return 0.0


def _latest_epoch_for_session(config: RemoteConfig, session_paths: list[str]) -> float:
    values = [_latest_epoch_for_path(config, path) for path in session_paths]
    return max(values) if values else 0.0


def list_sessions(
    user_id: int | str,
    config: RemoteConfig | None = None,
    env_path: str | os.PathLike[str] | None = None,
) -> list[dict[str, object]]:
    """Discover available sessions for a user from remote raw+processed trees."""
    cfg = config or load_remote_config(env_path=env_path)
    paths = _discover_session_paths(cfg, user_id=user_id)

    grouped: dict[str, dict[str, object]] = {}
    for path in paths:
        logical_path = path
        parts = _split_container_path(path)
        if parts:
            _, logical_path = parts

        session_id = _extract_session_id(logical_path)
        if not session_id:
            continue

        row = grouped.setdefault(
            session_id,
            {
                "session_id": session_id,
                "available_streams": set(),
                "raw_paths": set(),
                "processed_paths": set(),
                "dates": set(),
                "latest_epoch": 0.0,
            },
        )

        if "/raw/" in logical_path:
            row["raw_paths"].add(path)
        if "/processed/" in logical_path:
            row["processed_paths"].add(path)

        date_value = _extract_date(logical_path)
        if date_value:
            row["dates"].add(date_value)

    for session_id, row in grouped.items():
        session_paths = sorted(list(row["raw_paths"]) + list(row["processed_paths"]))
        streams = _discover_streams_for_paths(cfg, session_paths)
        row["available_streams"] = streams
        row["latest_epoch"] = _latest_epoch_for_session(cfg, session_paths)

    out: list[dict[str, object]] = []
    for session_id, row in grouped.items():
        dates = sorted(row["dates"])
        out.append(
            {
                "session_id": session_id,
                "available_streams": sorted(row["available_streams"]),
                "raw_paths": sorted(row["raw_paths"]),
                "processed_paths": sorted(row["processed_paths"]),
                "dates": dates,
                "latest_epoch": float(row["latest_epoch"]),
                "sort_key": dates[-1] if dates else session_id,
            }
        )

    out.sort(key=lambda item: (float(item["latest_epoch"]), str(item["sort_key"])), reverse=True)
    LOGGER.info("session_discovery_completed", extra={"user_id": str(user_id), "count": len(out)})
    return out


def _sync_path_via_rsync(config: RemoteConfig, remote_path: str, destination: Path) -> None:
    source = f"{config.target}:{remote_path.rstrip('/')}/"
    cmd = _rsync_base_cmd(config) + [source, str(destination)]
    subprocess.run(cmd, check=True, capture_output=True, text=True)


def _sync_path_via_container_tar(config: RemoteConfig, container: str, remote_path: str, destination: Path) -> None:
    relative = remote_path.lstrip("/")
    ssh_cmd = _ssh_base_cmd(config) + [
        f"docker exec {_quote(container)} sh -lc " + _quote(f"tar -C / -cf - {_quote(relative)}")
    ]
    tar_cmd = ["tar", "-xf", "-", "-C", str(destination)]

    proc_ssh = subprocess.Popen(ssh_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    proc_tar = subprocess.Popen(tar_cmd, stdin=proc_ssh.stdout, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert proc_ssh.stdout is not None
    proc_ssh.stdout.close()

    _, tar_err = proc_tar.communicate()
    ssh_err = proc_ssh.stderr.read().decode("utf-8", errors="replace") if proc_ssh.stderr is not None else ""
    ssh_code = proc_ssh.wait()

    if ssh_code != 0:
        raise RemoteSyncError(f"Container tar stream failed: {ssh_err.strip()}")
    if proc_tar.returncode != 0:
        raise RemoteSyncError(f"Local tar extract failed: {tar_err.decode('utf-8', errors='replace').strip()}")


def _sync_paths(
    config: RemoteConfig,
    local_cache_root: Path,
    session_id: str,
    remote_paths: list[str],
    retries: int = DEFAULT_RETRIES,
    retry_delay_seconds: float = DEFAULT_RETRY_DELAY_SECONDS,
) -> Path:
    local_cache_root.mkdir(parents=True, exist_ok=True)
    session_cache = local_cache_root / f"session_id={session_id}"
    session_cache.mkdir(parents=True, exist_ok=True)

    for remote_path in remote_paths:
        container_parts = _split_container_path(remote_path)

        last_error: Exception | None = None
        for attempt in range(1, retries + 1):
            try:
                LOGGER.info(
                    "sync_start",
                    extra={"attempt": attempt, "session_id": session_id, "remote_path": remote_path},
                )
                if container_parts:
                    container, path_in_container = container_parts
                    _sync_path_via_container_tar(config, container=container, remote_path=path_in_container, destination=session_cache)
                else:
                    _sync_path_via_rsync(config, remote_path=remote_path, destination=session_cache)

                LOGGER.info(
                    "sync_success",
                    extra={"attempt": attempt, "session_id": session_id, "remote_path": remote_path},
                )
                break
            except Exception as exc:  # noqa: BLE001
                last_error = exc
                LOGGER.warning("sync_failed", extra={"attempt": attempt, "error": str(exc)})
                if attempt < retries:
                    time.sleep(retry_delay_seconds)
                else:
                    raise RemoteSyncError(
                        f"Failed to sync remote path '{remote_path}' for session '{session_id}'."
                    ) from last_error

    return session_cache


def get_session_by_id(
    user_id: int | str,
    session_id: str,
    local_cache_root: str | os.PathLike[str] = "notebooks/data_cache",
    config: RemoteConfig | None = None,
    env_path: str | os.PathLike[str] | None = None,
) -> Path:
    """Sync processed and matching raw artifacts for one session into local cache."""
    cfg = config or load_remote_config(env_path=env_path)
    session_id = str(session_id).strip()
    if not session_id:
        raise RemoteSyncError("session_id must be non-empty")

    remote_paths = _discover_session_paths(cfg, user_id=user_id, session_id=session_id)
    if not remote_paths:
        raise RemoteSyncError(f"No remote data found for user_id={user_id}, session_id={session_id}.")

    LOGGER.info("session_sync_start", extra={"user_id": str(user_id), "session_id": session_id})
    session_cache = _sync_paths(
        config=cfg,
        local_cache_root=Path(local_cache_root),
        session_id=session_id,
        remote_paths=remote_paths,
    )
    LOGGER.info("session_sync_finished", extra={"session_id": session_id, "cache_path": str(session_cache)})
    return session_cache


def get_latest_session(
    user_id: int | str,
    local_cache_root: str | os.PathLike[str] = "notebooks/data_cache",
    config: RemoteConfig | None = None,
    env_path: str | os.PathLike[str] | None = None,
) -> Path:
    sessions = list_sessions(user_id=user_id, config=config, env_path=env_path)
    if not sessions:
        raise RemoteSyncError(f"No sessions found for user_id={user_id}")

    latest = sessions[0]
    return get_session_by_id(
        user_id=user_id,
        session_id=str(latest["session_id"]),
        local_cache_root=local_cache_root,
        config=config,
        env_path=env_path,
    )
