#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"
EXAMPLE_ENV_FILE="${PROJECT_ROOT}/.env.example"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
else
  # shellcheck disable=SC1090
  source "${EXAMPLE_ENV_FILE}"
fi

if [[ -z "${SERVER_USER:-}" || -z "${SERVER_IP:-}" ]]; then
  echo "SERVER_USER and SERVER_IP must be set"
  exit 1
fi

exec ssh "${SERVER_USER}@${SERVER_IP}" "$@"
