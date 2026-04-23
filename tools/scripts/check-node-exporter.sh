#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BASE_COMPOSE_FILE="${PROJECT_ROOT}/infra/compose/docker-compose.yml"
OBSERVABILITY_COMPOSE_FILE="${PROJECT_ROOT}/infra/compose/observability.yml"
ENV_FILE="${PROJECT_ROOT}/.env"
EXAMPLE_ENV_FILE="${PROJECT_ROOT}/.env.example"
SERVICE_NAME="node-exporter"
MODE="${1:-local}"
EXPLICIT_NODE_EXPORTER_LAN_HOST="${NODE_EXPORTER_LAN_HOST:-}"

if [[ -f "${ENV_FILE}" ]]; then
  compose_env_file="${ENV_FILE}"
else
  compose_env_file="${EXAMPLE_ENV_FILE}"
fi

# shellcheck disable=SC1090
source "${compose_env_file}"

if [[ -n "${EXPLICIT_NODE_EXPORTER_LAN_HOST}" ]]; then
  NODE_EXPORTER_LAN_HOST="${EXPLICIT_NODE_EXPORTER_LAN_HOST}"
fi

NODE_EXPORTER_PORT="${NODE_EXPORTER_PORT:-9100}"
METRICS_URL="http://localhost:${NODE_EXPORTER_PORT}/metrics"
NODE_EXPORTER_LAN_HOST="${NODE_EXPORTER_LAN_HOST:-${SERVER_IP:-}}"

validate_metrics_url() {
  local metrics_url="$1"
  local label="$2"
  local metrics_file

  metrics_file="$(mktemp)"

  if ! curl --fail --silent --show-error "${metrics_url}" >"${metrics_file}"; then
    rm -f "${metrics_file}"
    echo "Node Exporter ${label} endpoint did not return a successful response: ${metrics_url}"
    return 1
  fi

  if [[ ! -s "${metrics_file}" ]]; then
    rm -f "${metrics_file}"
    echo "Node Exporter ${label} endpoint returned an empty response: ${metrics_url}"
    return 1
  fi

  local required_metrics=(
    "^node_exporter_build_info"
    "^node_cpu_seconds_total"
    "^node_memory_MemTotal_bytes"
    "^node_filesystem_size_bytes"
  )

  local metric
  for metric in "${required_metrics[@]}"; do
    if ! grep -qE "${metric}" "${metrics_file}"; then
      rm -f "${metrics_file}"
      echo "Expected Node Exporter metric not found at ${label} endpoint: ${metric}"
      return 1
    fi
  done

  rm -f "${metrics_file}"
  echo "Node Exporter ${label} endpoint is serving host-style metrics: ${metrics_url}"
  return 0
}

if [[ "${MODE}" == "--lan" ]]; then
  if [[ -z "${NODE_EXPORTER_LAN_HOST}" ]]; then
    echo "NODE_EXPORTER_LAN_HOST or SERVER_IP must be set for LAN validation."
    exit 1
  fi

  validate_metrics_url "http://${NODE_EXPORTER_LAN_HOST}:${NODE_EXPORTER_PORT}/metrics" "LAN"
  exit 0
fi

if [[ "${MODE}" == "--remote" ]]; then
  SSH_SCRIPT="${SCRIPT_DIR}/ssh.sh"
  REMOTE_PROJECT_ROOT="${PROJECT_ROOT}"

  "${SSH_SCRIPT}" \
    "REMOTE_PROJECT_ROOT='${REMOTE_PROJECT_ROOT}' NODE_EXPORTER_PORT='${NODE_EXPORTER_PORT}' bash -s" <<'REMOTE_CHECK'
set -euo pipefail

SERVICE_NAME="node-exporter"
METRICS_URL="http://localhost:${NODE_EXPORTER_PORT}/metrics"

docker compose \
  --env-file "${REMOTE_PROJECT_ROOT}/.env" \
  -f "${REMOTE_PROJECT_ROOT}/compose/docker-compose.yml" \
  -f "${REMOTE_PROJECT_ROOT}/compose/observability.yml" \
  config >/dev/null

docker compose \
  --env-file "${REMOTE_PROJECT_ROOT}/.env" \
  -f "${REMOTE_PROJECT_ROOT}/compose/docker-compose.yml" \
  -f "${REMOTE_PROJECT_ROOT}/compose/observability.yml" \
  up -d "${SERVICE_NAME}" >/dev/null

container_id="$(
  docker compose \
    --env-file "${REMOTE_PROJECT_ROOT}/.env" \
    -f "${REMOTE_PROJECT_ROOT}/compose/docker-compose.yml" \
    -f "${REMOTE_PROJECT_ROOT}/compose/observability.yml" \
    ps -q "${SERVICE_NAME}"
)"

if [[ -z "${container_id}" ]]; then
  echo "Node Exporter container was not created."
  exit 1
fi

container_state="$(docker inspect -f '{{.State.Status}}' "${container_id}")"
restart_count="$(docker inspect -f '{{.RestartCount}}' "${container_id}")"

if [[ "${container_state}" != "running" ]]; then
  echo "Node Exporter is not running. Current state: ${container_state}"
  exit 1
fi

if [[ "${restart_count}" != "0" ]]; then
  echo "Node Exporter restart count is ${restart_count}; inspect logs before continuing."
  exit 1
fi

metrics_file="$(mktemp)"
trap 'rm -f "${metrics_file}"' EXIT

curl --fail --silent --show-error "${METRICS_URL}" >"${metrics_file}"

required_metrics=(
  "^node_exporter_build_info"
  "^node_cpu_seconds_total"
  "^node_memory_MemTotal_bytes"
  "^node_filesystem_size_bytes"
)

for metric in "${required_metrics[@]}"; do
  if ! grep -qE "${metric}" "${metrics_file}"; then
    echo "Expected Node Exporter metric not found: ${metric}"
    exit 1
  fi
done

echo "Node Exporter is running and serving host-style metrics."
echo "Metrics endpoint: ${METRICS_URL}"

lan_ip="$(hostname -I | awk '{print $1}')"
if [[ -n "${lan_ip}" ]]; then
  lan_metrics_url="http://${lan_ip}:${NODE_EXPORTER_PORT}/metrics"
  lan_metrics_file="$(mktemp)"
  trap 'rm -f "${metrics_file}" "${lan_metrics_file}"' EXIT

  curl --fail --silent --show-error "${lan_metrics_url}" >"${lan_metrics_file}"

  for metric in "${required_metrics[@]}"; do
    if ! grep -qE "${metric}" "${lan_metrics_file}"; then
      echo "Expected Node Exporter metric not found at host LAN endpoint: ${metric}"
      exit 1
    fi
  done

  echo "Node Exporter host LAN interface is serving host-style metrics: ${lan_metrics_url}"
fi
REMOTE_CHECK

  exit 0
fi

if [[ "${MODE}" != "local" ]]; then
  echo "Usage: tools/scripts/check-node-exporter.sh [--remote|--lan]"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed or not available in PATH"
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose plugin is not available"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is not installed or not available in PATH"
  exit 1
fi

docker compose \
  --env-file "${compose_env_file}" \
  -f "${BASE_COMPOSE_FILE}" \
  -f "${OBSERVABILITY_COMPOSE_FILE}" \
  config >/dev/null

docker compose \
  --env-file "${compose_env_file}" \
  -f "${BASE_COMPOSE_FILE}" \
  -f "${OBSERVABILITY_COMPOSE_FILE}" \
  up -d "${SERVICE_NAME}"

container_id="$(
  docker compose \
    --env-file "${compose_env_file}" \
    -f "${BASE_COMPOSE_FILE}" \
    -f "${OBSERVABILITY_COMPOSE_FILE}" \
    ps -q "${SERVICE_NAME}"
)"

if [[ -z "${container_id}" ]]; then
  echo "Node Exporter container was not created."
  exit 1
fi

container_state="$(docker inspect -f '{{.State.Status}}' "${container_id}")"
restart_count="$(docker inspect -f '{{.RestartCount}}' "${container_id}")"

if [[ "${container_state}" != "running" ]]; then
  echo "Node Exporter is not running. Current state: ${container_state}"
  exit 1
fi

if [[ "${restart_count}" != "0" ]]; then
  echo "Node Exporter restart count is ${restart_count}; inspect logs before continuing."
  exit 1
fi

for _ in {1..20}; do
  if validate_metrics_url "${METRICS_URL}" "local"; then
    exit 0
  fi

  sleep 1
done
