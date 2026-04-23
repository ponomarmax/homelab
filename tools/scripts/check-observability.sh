#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BASE_COMPOSE_FILE="${PROJECT_ROOT}/infra/compose/docker-compose.yml"
OBSERVABILITY_COMPOSE_FILE="${PROJECT_ROOT}/infra/compose/observability.yml"
ENV_FILE="${PROJECT_ROOT}/.env"
EXAMPLE_ENV_FILE="${PROJECT_ROOT}/.env.example"

required_paths=(
  "infra/observability/README.md"
  "infra/observability/config/prometheus/README.md"
  "infra/observability/config/prometheus/prometheus.yml"
  "infra/observability/config/prometheus/rules"
  "infra/observability/config/grafana/README.md"
  "infra/observability/config/grafana/dashboards"
  "infra/observability/config/grafana/provisioning"
  "infra/observability/config/cadvisor/README.md"
  "infra/observability/config/node-exporter/README.md"
  "infra/observability/scripts/README.md"
  "infra/observability/validation/README.md"
  "tools/scripts/check-node-exporter.sh"
  "tools/scripts/check-prometheus.sh"
  "data/observability/README.md"
  "data/observability/prometheus"
  "data/observability/grafana"
)

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed or not available in PATH"
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose plugin is not available"
  exit 1
fi

for path in "${required_paths[@]}"; do
  if [[ ! -e "${PROJECT_ROOT}/${path}" ]]; then
    echo "Required observability scaffold path is missing: ${path}"
    exit 1
  fi
done

if [[ -f "${ENV_FILE}" ]]; then
  compose_env_file="${ENV_FILE}"
else
  compose_env_file="${EXAMPLE_ENV_FILE}"
fi

docker compose \
  --env-file "${compose_env_file}" \
  -f "${BASE_COMPOSE_FILE}" \
  -f "${OBSERVABILITY_COMPOSE_FILE}" \
  config >/dev/null

echo "Observability scaffold is valid."
echo "Project root: ${PROJECT_ROOT}"
