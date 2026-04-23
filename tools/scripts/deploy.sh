#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPOSE_FILE="${LOCAL_PROJECT_ROOT}/infra/compose/docker-compose.yml"
OBSERVABILITY_COMPOSE_FILE="${LOCAL_PROJECT_ROOT}/infra/compose/observability.yml"
ENV_FILE="${LOCAL_PROJECT_ROOT}/.env"
EXAMPLE_ENV_FILE="${LOCAL_PROJECT_ROOT}/.env.example"
SSH_SCRIPT="${SCRIPT_DIR}/ssh.sh"

if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${EXAMPLE_ENV_FILE}" "${ENV_FILE}"
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

REMOTE_PROJECT_ROOT="${PROJECT_ROOT}"
CONFIRM_DEPLOY="false"
SERVICES=()

for arg in "$@"; do
  if [[ "${arg}" == "--confirm" ]]; then
    CONFIRM_DEPLOY="true"
    continue
  fi

  SERVICES+=("${arg}")
done

if [[ ${#SERVICES[@]} -eq 0 ]]; then
  SERVICES=("bootstrap-check")
fi

"${SCRIPT_DIR}/check.sh"

if [[ -f "${OBSERVABILITY_COMPOSE_FILE}" ]]; then
  "${SCRIPT_DIR}/check-observability.sh"
  REMOTE_COMPOSE_FILES="-f ${REMOTE_PROJECT_ROOT}/compose/docker-compose.yml -f ${REMOTE_PROJECT_ROOT}/compose/observability.yml"
else
  REMOTE_COMPOSE_FILES="-f ${REMOTE_PROJECT_ROOT}/compose/docker-compose.yml"
fi

if [[ "${CONFIRM_DEPLOY}" != "true" ]]; then
  echo "Validation passed."
  echo "Dry run only. No containers were started."
  echo "When deployment is approved, run:"
  echo "mkdir -p ${LOCAL_PROJECT_ROOT}/.deploy/compose"
  echo "cp ${ENV_FILE} ${LOCAL_PROJECT_ROOT}/.deploy/.env"
  echo "cp -R ${LOCAL_PROJECT_ROOT}/infra/compose/* ${LOCAL_PROJECT_ROOT}/.deploy/compose/"
  echo "${SSH_SCRIPT} mkdir -p ${REMOTE_PROJECT_ROOT}"
  echo "scp -r ${LOCAL_PROJECT_ROOT}/.deploy/compose ${LOCAL_PROJECT_ROOT}/.deploy/.env ${SERVER_USER}@${SERVER_IP}:${REMOTE_PROJECT_ROOT}/"
  echo "${SSH_SCRIPT} docker compose --env-file ${REMOTE_PROJECT_ROOT}/.env ${REMOTE_COMPOSE_FILES} up -d ${SERVICES[*]}"
  exit 0
fi

mkdir -p "${LOCAL_PROJECT_ROOT}/.deploy/compose"
cp "${ENV_FILE}" "${LOCAL_PROJECT_ROOT}/.deploy/.env"
cp -R "${LOCAL_PROJECT_ROOT}/infra/compose/." "${LOCAL_PROJECT_ROOT}/.deploy/compose/"

"${SSH_SCRIPT}" "mkdir -p '${REMOTE_PROJECT_ROOT}'"
scp -r "${LOCAL_PROJECT_ROOT}/.deploy/compose" "${LOCAL_PROJECT_ROOT}/.deploy/.env" \
  "${SERVER_USER}@${SERVER_IP}:${REMOTE_PROJECT_ROOT}/"

"${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} up -d ${SERVICES[*]}"
