#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BASE_COMPOSE_FILE="${PROJECT_ROOT}/infra/compose/docker-compose.yml"
OBSERVABILITY_COMPOSE_FILE="${PROJECT_ROOT}/infra/compose/observability.yml"
ENV_FILE="${PROJECT_ROOT}/.env"
EXAMPLE_ENV_FILE="${PROJECT_ROOT}/.env.example"
MODE="${1:-local}"
EXPLICIT_CADVISOR_LAN_HOST="${CADVISOR_LAN_HOST:-}"

if [[ -f "${ENV_FILE}" ]]; then
  compose_env_file="${ENV_FILE}"
else
  compose_env_file="${EXAMPLE_ENV_FILE}"
fi

# shellcheck disable=SC1090
source "${compose_env_file}"

if [[ -n "${EXPLICIT_CADVISOR_LAN_HOST}" ]]; then
  CADVISOR_LAN_HOST="${EXPLICIT_CADVISOR_LAN_HOST}"
fi

CADVISOR_PORT="${CADVISOR_PORT:-8080}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
CADVISOR_LAN_HOST="${CADVISOR_LAN_HOST:-${SERVER_IP:-}}"

check_cadvisor_metrics() {
  local metrics_url="$1"
  local label="$2"
  local metrics_file

  metrics_file="$(mktemp)"

  if ! curl --fail --silent --show-error "${metrics_url}" >"${metrics_file}"; then
    rm -f "${metrics_file}"
    echo "cAdvisor ${label} endpoint did not return a successful response: ${metrics_url}"
    return 1
  fi

  if [[ ! -s "${metrics_file}" ]]; then
    rm -f "${metrics_file}"
    echo "cAdvisor ${label} endpoint returned an empty response: ${metrics_url}"
    return 1
  fi

  local required_metrics=(
    "^cadvisor_version_info"
    "^container_cpu_usage_seconds_total"
    "^container_memory_working_set_bytes"
    "^container_fs_usage_bytes"
  )

  local metric
  for metric in "${required_metrics[@]}"; do
    if ! grep -qE "${metric}" "${metrics_file}"; then
      rm -f "${metrics_file}"
      echo "Expected cAdvisor metric not found at ${label} endpoint: ${metric}"
      return 1
    fi
  done

  rm -f "${metrics_file}"
  echo "cAdvisor ${label} endpoint is serving container metrics: ${metrics_url}"
  return 0
}

check_prometheus_cadvisor() {
  local base_url="$1"
  local label="$2"
  local targets_file
  local query_file

  targets_file="$(mktemp)"
  query_file="$(mktemp)"
  trap 'rm -f "${targets_file}" "${query_file}"' RETURN

  curl --fail --silent --show-error \
    "${base_url}/api/v1/targets?state=active" >"${targets_file}"

  if ! grep -q '"job":"cadvisor"' "${targets_file}" || ! grep -q '"health":"up"' "${targets_file}"; then
    echo "Prometheus ${label} endpoint does not report cadvisor as an up target."
    return 1
  fi

  curl --fail --silent --show-error --get \
    --data-urlencode 'query=container_cpu_usage_seconds_total' \
    "${base_url}/api/v1/query" >"${query_file}"

  if ! grep -q '"status":"success"' "${query_file}" || ! grep -q 'container_cpu_usage_seconds_total' "${query_file}"; then
    echo "Prometheus ${label} endpoint did not return cAdvisor container CPU data."
    return 1
  fi

  echo "Prometheus ${label} endpoint is scraping cAdvisor and returning container data."
  return 0
}

if [[ "${MODE}" == "--lan" ]]; then
  if [[ -z "${CADVISOR_LAN_HOST}" ]]; then
    echo "CADVISOR_LAN_HOST or SERVER_IP must be set for LAN validation."
    exit 1
  fi

  check_cadvisor_metrics "http://${CADVISOR_LAN_HOST}:${CADVISOR_PORT}/metrics" "LAN"
  check_prometheus_cadvisor "http://${CADVISOR_LAN_HOST}:${PROMETHEUS_PORT}" "LAN"
  exit 0
fi

if [[ "${MODE}" == "--remote" ]]; then
  SSH_SCRIPT="${SCRIPT_DIR}/ssh.sh"
  REMOTE_PROJECT_ROOT="${PROJECT_ROOT}"

  "${SSH_SCRIPT}" \
    "REMOTE_PROJECT_ROOT='${REMOTE_PROJECT_ROOT}' CADVISOR_PORT='${CADVISOR_PORT}' PROMETHEUS_PORT='${PROMETHEUS_PORT}' bash -s" <<'REMOTE_CHECK'
set -euo pipefail

CADVISOR_URL="http://localhost:${CADVISOR_PORT}"
PROMETHEUS_URL="http://localhost:${PROMETHEUS_PORT}"

check_cadvisor_metrics() {
  local metrics_url="$1"
  local label="$2"
  local metrics_file

  metrics_file="$(mktemp)"

  if ! curl --fail --silent --show-error "${metrics_url}" >"${metrics_file}"; then
    rm -f "${metrics_file}"
    echo "cAdvisor ${label} endpoint did not return a successful response: ${metrics_url}"
    return 1
  fi

  local required_metrics=(
    "^cadvisor_version_info"
    "^container_cpu_usage_seconds_total"
    "^container_memory_working_set_bytes"
    "^container_fs_usage_bytes"
  )

  local metric
  for metric in "${required_metrics[@]}"; do
    if ! grep -qE "${metric}" "${metrics_file}"; then
      rm -f "${metrics_file}"
      echo "Expected cAdvisor metric not found at ${label} endpoint: ${metric}"
      return 1
    fi
  done

  rm -f "${metrics_file}"
  echo "cAdvisor ${label} endpoint is serving container metrics: ${metrics_url}"
  return 0
}

check_prometheus_cadvisor() {
  local base_url="$1"
  local label="$2"
  local targets_file
  local query_file

  targets_file="$(mktemp)"
  query_file="$(mktemp)"
  trap 'rm -f "${targets_file}" "${query_file}"' RETURN

  curl --fail --silent --show-error \
    "${base_url}/api/v1/targets?state=active" >"${targets_file}"

  if ! grep -q '"job":"cadvisor"' "${targets_file}" || ! grep -q '"health":"up"' "${targets_file}"; then
    echo "Prometheus ${label} endpoint does not report cadvisor as an up target."
    return 1
  fi

  curl --fail --silent --show-error --get \
    --data-urlencode 'query=container_cpu_usage_seconds_total' \
    "${base_url}/api/v1/query" >"${query_file}"

  if ! grep -q '"status":"success"' "${query_file}" || ! grep -q 'container_cpu_usage_seconds_total' "${query_file}"; then
    echo "Prometheus ${label} endpoint did not return cAdvisor container CPU data."
    return 1
  fi

  echo "Prometheus ${label} endpoint is scraping cAdvisor and returning container data."
  return 0
}

compose_args=(
  --env-file "${REMOTE_PROJECT_ROOT}/.env"
  -f "${REMOTE_PROJECT_ROOT}/compose/docker-compose.yml"
  -f "${REMOTE_PROJECT_ROOT}/compose/observability.yml"
)

docker compose "${compose_args[@]}" config >/dev/null
docker compose "${compose_args[@]}" up -d cadvisor >/dev/null
docker compose "${compose_args[@]}" up -d --force-recreate prometheus >/dev/null

container_id="$(docker compose "${compose_args[@]}" ps -q cadvisor)"

if [[ -z "${container_id}" ]]; then
  echo "cAdvisor container was not created."
  exit 1
fi

container_state="$(docker inspect -f '{{.State.Status}}' "${container_id}")"

if [[ "${container_state}" != "running" ]]; then
  echo "cAdvisor is not running. Current state: ${container_state}"
  exit 1
fi

restart_count_before="$(docker inspect -f '{{.RestartCount}}' "${container_id}")"
sleep 2
restart_count_after="$(docker inspect -f '{{.RestartCount}}' "${container_id}")"

if [[ "${restart_count_before}" != "${restart_count_after}" ]]; then
  echo "cAdvisor restart count changed from ${restart_count_before} to ${restart_count_after}; inspect logs before continuing."
  exit 1
fi

ready="false"
for _ in {1..40}; do
  if check_cadvisor_metrics "${CADVISOR_URL}/metrics" "host-local" >/dev/null 2>&1; then
    ready="true"
    break
  fi

  sleep 3
done

if [[ "${ready}" != "true" ]]; then
  check_cadvisor_metrics "${CADVISOR_URL}/metrics" "host-local"
  exit 1
fi

check_cadvisor_metrics "${CADVISOR_URL}/metrics" "host-local"

ready="false"
for _ in {1..40}; do
  if check_prometheus_cadvisor "${PROMETHEUS_URL}" "host-local" >/dev/null 2>&1; then
    ready="true"
    break
  fi

  sleep 3
done

if [[ "${ready}" != "true" ]]; then
  check_prometheus_cadvisor "${PROMETHEUS_URL}" "host-local"
  exit 1
fi

check_prometheus_cadvisor "${PROMETHEUS_URL}" "host-local"

lan_ip="$(hostname -I | awk '{print $1}')"
if [[ -n "${lan_ip}" ]]; then
  check_cadvisor_metrics "http://${lan_ip}:${CADVISOR_PORT}/metrics" "host LAN interface" >/dev/null
  check_prometheus_cadvisor "http://${lan_ip}:${PROMETHEUS_PORT}" "host LAN interface" >/dev/null
  echo "cAdvisor and Prometheus host LAN interfaces are reachable and queryable."
fi

echo "cAdvisor is running, exposing container metrics, and Prometheus is scraping it."
REMOTE_CHECK

  exit 0
fi

if [[ "${MODE}" != "local" ]]; then
  echo "Usage: tools/scripts/check-cadvisor.sh [--remote|--lan]"
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

docker compose \
  --env-file "${compose_env_file}" \
  -f "${BASE_COMPOSE_FILE}" \
  -f "${OBSERVABILITY_COMPOSE_FILE}" \
  config >/dev/null

docker compose \
  --env-file "${compose_env_file}" \
  -f "${BASE_COMPOSE_FILE}" \
  -f "${OBSERVABILITY_COMPOSE_FILE}" \
  up -d cadvisor

docker compose \
  --env-file "${compose_env_file}" \
  -f "${BASE_COMPOSE_FILE}" \
  -f "${OBSERVABILITY_COMPOSE_FILE}" \
  up -d --force-recreate prometheus

for _ in {1..40}; do
  if check_cadvisor_metrics "http://localhost:${CADVISOR_PORT}/metrics" "local" >/dev/null 2>&1; then
    check_cadvisor_metrics "http://localhost:${CADVISOR_PORT}/metrics" "local"
    check_prometheus_cadvisor "http://localhost:${PROMETHEUS_PORT}" "local"
    exit 0
  fi

  sleep 3
done

check_cadvisor_metrics "http://localhost:${CADVISOR_PORT}/metrics" "local"
