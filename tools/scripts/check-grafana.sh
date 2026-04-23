#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BASE_COMPOSE_FILE="${PROJECT_ROOT}/infra/compose/docker-compose.yml"
OBSERVABILITY_COMPOSE_FILE="${PROJECT_ROOT}/infra/compose/observability.yml"
ENV_FILE="${PROJECT_ROOT}/.env"
EXAMPLE_ENV_FILE="${PROJECT_ROOT}/.env.example"
MODE="${1:-local}"
EXPLICIT_GRAFANA_LAN_HOST="${GRAFANA_LAN_HOST:-}"

if [[ -f "${ENV_FILE}" ]]; then
  compose_env_file="${ENV_FILE}"
else
  compose_env_file="${EXAMPLE_ENV_FILE}"
fi

# shellcheck disable=SC1090
source "${compose_env_file}"

if [[ -n "${EXPLICIT_GRAFANA_LAN_HOST}" ]]; then
  GRAFANA_LAN_HOST="${EXPLICIT_GRAFANA_LAN_HOST}"
fi

GRAFANA_PORT="${GRAFANA_PORT:-3000}"
GRAFANA_LAN_HOST="${GRAFANA_LAN_HOST:-${SERVER_IP:-}}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"

if [[ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
  echo "GRAFANA_ADMIN_PASSWORD must be set in .env for Grafana validation."
  exit 1
fi

check_grafana_api() {
  local base_url="$1"
  local label="$2"
  local datasource_file
  local dashboard_file
  local query_file

  curl --fail --silent --show-error "${base_url}/api/health" >/dev/null

  datasource_file="$(mktemp)"
  dashboard_file="$(mktemp)"
  query_file="$(mktemp)"
  trap 'rm -f "${datasource_file}" "${dashboard_file}" "${query_file}"' RETURN

  curl --fail --silent --show-error \
    --user "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    "${base_url}/api/datasources/uid/prometheus" >"${datasource_file}"

  if ! grep -q '"name":"Prometheus"' "${datasource_file}" || ! grep -q '"type":"prometheus"' "${datasource_file}"; then
    echo "Grafana ${label} endpoint does not expose the provisioned Prometheus datasource."
    return 1
  fi

  curl --fail --silent --show-error \
    --user "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    "${base_url}/api/datasources/proxy/uid/prometheus/api/v1/query?query=up" >"${query_file}"

  if ! grep -q '"status":"success"' "${query_file}" || ! grep -q '"__name__":"up"' "${query_file}"; then
    echo "Grafana ${label} endpoint could not query Prometheus data through the datasource proxy."
    return 1
  fi

  for dashboard_uid in homelab-host-linux homelab-docker-containers; do
    curl --fail --silent --show-error \
      --user "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
      "${base_url}/api/dashboards/uid/${dashboard_uid}" >"${dashboard_file}"

    if ! grep -q "\"uid\":\"${dashboard_uid}\"" "${dashboard_file}" || ! grep -q '"datasource":{"type":"prometheus","uid":"prometheus"}' "${dashboard_file}"; then
      echo "Grafana ${label} endpoint does not expose expected provisioned dashboard: ${dashboard_uid}"
      return 1
    fi
  done

  local dashboard_queries=(
    'node_load1{job="node-exporter"}'
    'node_memory_MemAvailable_bytes{job="node-exporter"}'
    'node_filesystem_size_bytes{job="node-exporter",mountpoint="/"}'
    'node_network_receive_bytes_total{job="node-exporter",device!="lo"}'
    'container_cpu_usage_seconds_total{job="cadvisor",name!="",image!=""}'
    'container_memory_working_set_bytes{job="cadvisor",name!="",image!=""}'
    'container_network_receive_bytes_total{job="cadvisor",name!="",image!=""}'
    'container_fs_reads_bytes_total{job="cadvisor",name!="",image!=""}'
  )

  local query
  for query in "${dashboard_queries[@]}"; do
    curl --fail --silent --show-error --get \
      --user "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
      --data-urlencode "query=${query}" \
      "${base_url}/api/datasources/proxy/uid/prometheus/api/v1/query" >"${query_file}"

    if ! grep -q '"status":"success"' "${query_file}" || ! grep -Fq '"result":[{' "${query_file}"; then
      echo "Grafana ${label} endpoint returned no data for dashboard query: ${query}"
      return 1
    fi
  done

  echo "Grafana ${label} endpoint is healthy, has the Prometheus datasource, provisioned dashboards, and queryable dashboard metrics: ${base_url}"
  return 0
}

if [[ "${MODE}" == "--lan" ]]; then
  if [[ -z "${GRAFANA_LAN_HOST}" ]]; then
    echo "GRAFANA_LAN_HOST or SERVER_IP must be set for LAN validation."
    exit 1
  fi

  check_grafana_api "http://${GRAFANA_LAN_HOST}:${GRAFANA_PORT}" "LAN"
  exit 0
fi

if [[ "${MODE}" == "--remote" ]]; then
  SSH_SCRIPT="${SCRIPT_DIR}/ssh.sh"
  REMOTE_PROJECT_ROOT="${PROJECT_ROOT}"

  "${SSH_SCRIPT}" \
    "REMOTE_PROJECT_ROOT='${REMOTE_PROJECT_ROOT}' bash -s" <<'REMOTE_CHECK'
set -euo pipefail

# shellcheck disable=SC1090
source "${REMOTE_PROJECT_ROOT}/.env"

GRAFANA_PORT="${GRAFANA_PORT:-3000}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_URL="http://localhost:${GRAFANA_PORT}"
GRAFANA_VOLUME="homelab_grafana_data"

if [[ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
  echo "GRAFANA_ADMIN_PASSWORD must be set in remote .env for Grafana validation."
  exit 1
fi

check_grafana_api() {
  local base_url="$1"
  local label="$2"
  local datasource_file
  local dashboard_file
  local query_file

  curl --fail --silent --show-error "${base_url}/api/health" >/dev/null

  datasource_file="$(mktemp)"
  dashboard_file="$(mktemp)"
  query_file="$(mktemp)"
  trap 'rm -f "${datasource_file}" "${dashboard_file}" "${query_file}"' RETURN

  curl --fail --silent --show-error \
    --user "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    "${base_url}/api/datasources/uid/prometheus" >"${datasource_file}"

  if ! grep -q '"name":"Prometheus"' "${datasource_file}" || ! grep -q '"type":"prometheus"' "${datasource_file}"; then
    echo "Grafana ${label} endpoint does not expose the provisioned Prometheus datasource."
    return 1
  fi

  curl --fail --silent --show-error \
    --user "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    "${base_url}/api/datasources/proxy/uid/prometheus/api/v1/query?query=up" >"${query_file}"

  if ! grep -q '"status":"success"' "${query_file}" || ! grep -q '"__name__":"up"' "${query_file}"; then
    echo "Grafana ${label} endpoint could not query Prometheus data through the datasource proxy."
    return 1
  fi

  for dashboard_uid in homelab-host-linux homelab-docker-containers; do
    curl --fail --silent --show-error \
      --user "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
      "${base_url}/api/dashboards/uid/${dashboard_uid}" >"${dashboard_file}"

    if ! grep -q "\"uid\":\"${dashboard_uid}\"" "${dashboard_file}" || ! grep -q '"datasource":{"type":"prometheus","uid":"prometheus"}' "${dashboard_file}"; then
      echo "Grafana ${label} endpoint does not expose expected provisioned dashboard: ${dashboard_uid}"
      return 1
    fi
  done

  local dashboard_queries=(
    'node_load1{job="node-exporter"}'
    'node_memory_MemAvailable_bytes{job="node-exporter"}'
    'node_filesystem_size_bytes{job="node-exporter",mountpoint="/"}'
    'node_network_receive_bytes_total{job="node-exporter",device!="lo"}'
    'container_cpu_usage_seconds_total{job="cadvisor",name!="",image!=""}'
    'container_memory_working_set_bytes{job="cadvisor",name!="",image!=""}'
    'container_network_receive_bytes_total{job="cadvisor",name!="",image!=""}'
    'container_fs_reads_bytes_total{job="cadvisor",name!="",image!=""}'
  )

  local query
  for query in "${dashboard_queries[@]}"; do
    curl --fail --silent --show-error --get \
      --user "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
      --data-urlencode "query=${query}" \
      "${base_url}/api/datasources/proxy/uid/prometheus/api/v1/query" >"${query_file}"

    if ! grep -q '"status":"success"' "${query_file}" || ! grep -Fq '"result":[{' "${query_file}"; then
      echo "Grafana ${label} endpoint returned no data for dashboard query: ${query}"
      return 1
    fi
  done

  echo "Grafana ${label} endpoint is healthy, has the Prometheus datasource, provisioned dashboards, and queryable dashboard metrics: ${base_url}"
  return 0
}

compose_args=(
  --env-file "${REMOTE_PROJECT_ROOT}/.env"
  -f "${REMOTE_PROJECT_ROOT}/compose/docker-compose.yml"
  -f "${REMOTE_PROJECT_ROOT}/compose/observability.yml"
)

docker compose "${compose_args[@]}" config >/dev/null
docker compose "${compose_args[@]}" up -d prometheus grafana >/dev/null

container_id="$(docker compose "${compose_args[@]}" ps -q grafana)"

if [[ -z "${container_id}" ]]; then
  echo "Grafana container was not created."
  exit 1
fi

container_state="$(docker inspect -f '{{.State.Status}}' "${container_id}")"

if [[ "${container_state}" != "running" ]]; then
  echo "Grafana is not running. Current state: ${container_state}"
  exit 1
fi

restart_count_before="$(docker inspect -f '{{.RestartCount}}' "${container_id}")"
sleep 2
restart_count_after="$(docker inspect -f '{{.RestartCount}}' "${container_id}")"

if [[ "${restart_count_before}" != "${restart_count_after}" ]]; then
  echo "Grafana restart count changed from ${restart_count_before} to ${restart_count_after}; inspect logs before continuing."
  exit 1
fi

ready="false"
for _ in {1..60}; do
  if check_grafana_api "${GRAFANA_URL}" "host-local" >/dev/null 2>&1; then
    ready="true"
    break
  fi

  sleep 3
done

if [[ "${ready}" != "true" ]]; then
  check_grafana_api "${GRAFANA_URL}" "host-local"
  exit 1
fi

check_grafana_api "${GRAFANA_URL}" "host-local"

docker volume inspect "${GRAFANA_VOLUME}" >/dev/null

if ! docker exec "${container_id}" sh -c 'test -f /var/lib/grafana/grafana.db && test -d /var/lib/grafana/plugins'; then
  echo "Grafana persistent data directory does not show expected state files."
  exit 1
fi

docker compose "${compose_args[@]}" up -d --force-recreate grafana >/dev/null
container_id="$(docker compose "${compose_args[@]}" ps -q grafana)"

ready="false"
for _ in {1..60}; do
  if check_grafana_api "${GRAFANA_URL}" "post-recreate" >/dev/null 2>&1; then
    ready="true"
    break
  fi

  sleep 3
done

if [[ "${ready}" != "true" ]]; then
  check_grafana_api "${GRAFANA_URL}" "post-recreate"
  exit 1
fi

check_grafana_api "${GRAFANA_URL}" "post-recreate"

if ! docker exec "${container_id}" sh -c 'test -f /var/lib/grafana/grafana.db && test -d /var/lib/grafana/plugins'; then
  echo "Grafana persistent data directory is not intact after recreate."
  exit 1
fi

lan_ip="$(hostname -I | awk '{print $1}')"
if [[ -n "${lan_ip}" ]]; then
  check_grafana_api "http://${lan_ip}:${GRAFANA_PORT}" "host LAN interface" >/dev/null
  echo "Grafana host LAN interface is reachable and queryable."
fi

echo "Grafana is running, provisioned with Prometheus dashboards, queryable, and using persistent volume ${GRAFANA_VOLUME}."
REMOTE_CHECK

  exit 0
fi

if [[ "${MODE}" != "local" ]]; then
  echo "Usage: tools/scripts/check-grafana.sh [--remote|--lan]"
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
  up -d prometheus grafana

for _ in {1..60}; do
  if check_grafana_api "http://localhost:${GRAFANA_PORT}" "local" >/dev/null 2>&1; then
    check_grafana_api "http://localhost:${GRAFANA_PORT}" "local"
    exit 0
  fi

  sleep 3
done

check_grafana_api "http://localhost:${GRAFANA_PORT}" "local"
