#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BASE_COMPOSE_FILE="${PROJECT_ROOT}/infra/compose/docker-compose.yml"
OBSERVABILITY_COMPOSE_FILE="${PROJECT_ROOT}/infra/compose/observability.yml"
ENV_FILE="${PROJECT_ROOT}/.env"
EXAMPLE_ENV_FILE="${PROJECT_ROOT}/.env.example"
MODE="${1:-local}"
EXPLICIT_PROMETHEUS_LAN_HOST="${PROMETHEUS_LAN_HOST:-}"

if [[ -f "${ENV_FILE}" ]]; then
  compose_env_file="${ENV_FILE}"
else
  compose_env_file="${EXAMPLE_ENV_FILE}"
fi

# shellcheck disable=SC1090
source "${compose_env_file}"

if [[ -n "${EXPLICIT_PROMETHEUS_LAN_HOST}" ]]; then
  PROMETHEUS_LAN_HOST="${EXPLICIT_PROMETHEUS_LAN_HOST}"
fi

PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
PROMETHEUS_LAN_HOST="${PROMETHEUS_LAN_HOST:-${SERVER_IP:-}}"

check_http_metrics_api() {
  local base_url="$1"
  local label="$2"
  local targets_file
  local query_file

  curl --fail --silent --show-error "${base_url}/-/healthy" >/dev/null

  targets_file="$(mktemp)"
  query_file="$(mktemp)"
  trap 'rm -f "${targets_file}" "${query_file}"' RETURN

  curl --fail --silent --show-error \
    "${base_url}/api/v1/targets?state=active" >"${targets_file}"

  if ! grep -q '"job":"node-exporter"' "${targets_file}" || ! grep -q '"health":"up"' "${targets_file}"; then
    echo "Prometheus ${label} endpoint does not report node-exporter as an up target."
    return 1
  fi

  curl --fail --silent --show-error --get \
    --data-urlencode 'query=up{job="node-exporter"}' \
    "${base_url}/api/v1/query" >"${query_file}"

  if ! grep -q '"status":"success"' "${query_file}" || ! grep -q '"job":"node-exporter"' "${query_file}"; then
    echo "Prometheus ${label} endpoint did not return query data for node-exporter."
    return 1
  fi

  echo "Prometheus ${label} endpoint is healthy, scraping Node Exporter, and answering queries: ${base_url}"
  return 0
}

if [[ "${MODE}" == "--lan" ]]; then
  if [[ -z "${PROMETHEUS_LAN_HOST}" ]]; then
    echo "PROMETHEUS_LAN_HOST or SERVER_IP must be set for LAN validation."
    exit 1
  fi

  check_http_metrics_api "http://${PROMETHEUS_LAN_HOST}:${PROMETHEUS_PORT}" "LAN"
  exit 0
fi

if [[ "${MODE}" == "--remote" ]]; then
  SSH_SCRIPT="${SCRIPT_DIR}/ssh.sh"
  REMOTE_PROJECT_ROOT="${PROJECT_ROOT}"

  "${SSH_SCRIPT}" \
    "REMOTE_PROJECT_ROOT='${REMOTE_PROJECT_ROOT}' PROMETHEUS_PORT='${PROMETHEUS_PORT}' bash -s" <<'REMOTE_CHECK'
set -euo pipefail

PROMETHEUS_URL="http://localhost:${PROMETHEUS_PORT}"
PROMETHEUS_VOLUME="homelab_prometheus_data"

check_prometheus_api() {
  local base_url="$1"
  local label="$2"
  local targets_file
  local query_file

  curl --fail --silent --show-error "${base_url}/-/healthy" >/dev/null

  targets_file="$(mktemp)"
  query_file="$(mktemp)"
  trap 'rm -f "${targets_file}" "${query_file}"' RETURN

  curl --fail --silent --show-error \
    "${base_url}/api/v1/targets?state=active" >"${targets_file}"

  if ! grep -q '"job":"node-exporter"' "${targets_file}" || ! grep -q '"health":"up"' "${targets_file}"; then
    echo "Prometheus ${label} endpoint does not report node-exporter as an up target."
    return 1
  fi

  curl --fail --silent --show-error --get \
    --data-urlencode 'query=up{job="node-exporter"}' \
    "${base_url}/api/v1/query" >"${query_file}"

  if ! grep -q '"status":"success"' "${query_file}" || ! grep -q '"job":"node-exporter"' "${query_file}"; then
    echo "Prometheus ${label} endpoint did not return query data for node-exporter."
    return 1
  fi

  echo "Prometheus ${label} endpoint is healthy, scraping Node Exporter, and answering queries: ${base_url}"
  return 0
}

compose_args=(
  --env-file "${REMOTE_PROJECT_ROOT}/.env"
  -f "${REMOTE_PROJECT_ROOT}/compose/docker-compose.yml"
  -f "${REMOTE_PROJECT_ROOT}/compose/observability.yml"
)

docker compose "${compose_args[@]}" config >/dev/null
docker compose "${compose_args[@]}" up -d node-exporter prometheus >/dev/null

container_id="$(docker compose "${compose_args[@]}" ps -q prometheus)"

if [[ -z "${container_id}" ]]; then
  echo "Prometheus container was not created."
  exit 1
fi

container_state="$(docker inspect -f '{{.State.Status}}' "${container_id}")"

if [[ "${container_state}" != "running" ]]; then
  echo "Prometheus is not running. Current state: ${container_state}"
  exit 1
fi

restart_count_before="$(docker inspect -f '{{.RestartCount}}' "${container_id}")"
sleep 2
restart_count_after="$(docker inspect -f '{{.RestartCount}}' "${container_id}")"

if [[ "${restart_count_before}" != "${restart_count_after}" ]]; then
  echo "Prometheus restart count changed from ${restart_count_before} to ${restart_count_after}; inspect logs before continuing."
  exit 1
fi

ready="false"
for _ in {1..40}; do
  if check_prometheus_api "${PROMETHEUS_URL}" "host-local" >/dev/null 2>&1; then
    ready="true"
    break
  fi

  sleep 3
done

if [[ "${ready}" != "true" ]]; then
  check_prometheus_api "${PROMETHEUS_URL}" "host-local"
  exit 1
fi

check_prometheus_api "${PROMETHEUS_URL}" "host-local"

docker volume inspect "${PROMETHEUS_VOLUME}" >/dev/null

if ! docker exec "${container_id}" sh -c 'test -d /prometheus && find /prometheus -mindepth 1 -maxdepth 2 | head -1 | grep -q .'; then
  echo "Prometheus data directory exists but does not show expected runtime data."
  exit 1
fi

docker compose "${compose_args[@]}" up -d --force-recreate prometheus >/dev/null
container_id="$(docker compose "${compose_args[@]}" ps -q prometheus)"

ready="false"
for _ in {1..40}; do
  if check_prometheus_api "${PROMETHEUS_URL}" "post-recreate" >/dev/null 2>&1; then
    ready="true"
    break
  fi

  sleep 3
done

if [[ "${ready}" != "true" ]]; then
  check_prometheus_api "${PROMETHEUS_URL}" "post-recreate"
  exit 1
fi

check_prometheus_api "${PROMETHEUS_URL}" "post-recreate"

if ! docker exec "${container_id}" sh -c 'test -d /prometheus && find /prometheus -mindepth 1 -maxdepth 2 | head -1 | grep -q .'; then
  echo "Prometheus data directory is not populated after recreate."
  exit 1
fi

lan_ip="$(hostname -I | awk '{print $1}')"
if [[ -n "${lan_ip}" ]]; then
  check_prometheus_api "http://${lan_ip}:${PROMETHEUS_PORT}" "host LAN interface" >/dev/null
  echo "Prometheus host LAN interface is reachable and queryable."
fi

echo "Prometheus is running, scraping Node Exporter, answering queries, and using persistent volume ${PROMETHEUS_VOLUME}."
REMOTE_CHECK

  exit 0
fi

if [[ "${MODE}" != "local" ]]; then
  echo "Usage: tools/scripts/check-prometheus.sh [--remote|--lan]"
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
  up -d node-exporter prometheus

for _ in {1..40}; do
  if check_http_metrics_api "http://localhost:${PROMETHEUS_PORT}" "local" >/dev/null 2>&1; then
    check_http_metrics_api "http://localhost:${PROMETHEUS_PORT}" "local"
    exit 0
  fi

  sleep 3
done

check_http_metrics_api "http://localhost:${PROMETHEUS_PORT}" "local"
