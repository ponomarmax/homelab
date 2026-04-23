#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${LOCAL_PROJECT_ROOT}/.env"
EXAMPLE_ENV_FILE="${LOCAL_PROJECT_ROOT}/.env.example"
SSH_SCRIPT="${SCRIPT_DIR}/ssh.sh"

TAIL_LINES="${TAIL_LINES:-100}"
OBSERVABILITY_COMPOSE_FILE="${LOCAL_PROJECT_ROOT}/infra/compose/observability.yml"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
else
  # shellcheck disable=SC1090
  source "${EXAMPLE_ENV_FILE}"
fi

REMOTE_PROJECT_ROOT="${PROJECT_ROOT}"

if [[ -f "${OBSERVABILITY_COMPOSE_FILE}" ]]; then
  REMOTE_COMPOSE_FILES="-f ${REMOTE_PROJECT_ROOT}/compose/docker-compose.yml -f ${REMOTE_PROJECT_ROOT}/compose/observability.yml"
else
  REMOTE_COMPOSE_FILES="-f ${REMOTE_PROJECT_ROOT}/compose/docker-compose.yml"
fi

exec "${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} logs --tail '${TAIL_LINES}' $*"
