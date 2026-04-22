#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/compose/docker-compose.yml"
ENV_FILE="${PROJECT_ROOT}/.env"
EXAMPLE_ENV_FILE="${PROJECT_ROOT}/.env.example"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed or not available in PATH"
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose plugin is not available"
  exit 1
fi

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "Compose file not found: ${COMPOSE_FILE}"
  exit 1
fi

if [[ -f "${ENV_FILE}" ]]; then
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" config >/dev/null
else
  docker compose --env-file "${EXAMPLE_ENV_FILE}" -f "${COMPOSE_FILE}" config >/dev/null
fi

if [[ ! -f "${PROJECT_ROOT}/compose/smoke/index.html" ]]; then
  echo "Smoke test page not found: ${PROJECT_ROOT}/compose/smoke/index.html"
  exit 1
fi

echo "Compose configuration is valid."
echo "Project root: ${PROJECT_ROOT}"
