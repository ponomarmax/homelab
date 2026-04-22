#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${LOCAL_PROJECT_ROOT}/.env"
EXAMPLE_ENV_FILE="${LOCAL_PROJECT_ROOT}/.env.example"
SSH_SCRIPT="${SCRIPT_DIR}/ssh.sh"

TAIL_LINES="${TAIL_LINES:-100}"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
else
  # shellcheck disable=SC1090
  source "${EXAMPLE_ENV_FILE}"
fi

REMOTE_PROJECT_ROOT="${PROJECT_ROOT}"

exec "${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' -f '${REMOTE_PROJECT_ROOT}/compose/docker-compose.yml' logs --tail '${TAIL_LINES}' $*"
