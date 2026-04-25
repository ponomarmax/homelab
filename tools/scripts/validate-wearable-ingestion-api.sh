#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${LOCAL_PROJECT_ROOT}/.env"
EXAMPLE_ENV_FILE="${LOCAL_PROJECT_ROOT}/.env.example"
SSH_SCRIPT="${SCRIPT_DIR}/ssh.sh"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy.sh"
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

INGESTION_HOST="${WEARABLE_INGESTION_API_LAN_HOST:-${INGESTION_API_LAN_HOST:-${SERVER_IP}}}"
INGESTION_PORT="${WEARABLE_INGESTION_API_PORT:-${INGESTION_API_PORT:-18090}}"
BASE_URL="http://${INGESTION_HOST}:${INGESTION_PORT}"

echo "Deploying wearable-ingestion-api..."
"${DEPLOY_SCRIPT}" --confirm wearable-ingestion-api

echo "Checking running container..."
is_running="false"
for _ in $(seq 1 20); do
  if "${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} ps --status running --services | grep -Fx 'wearable-ingestion-api' >/dev/null"; then
    is_running="true"
    break
  fi
  sleep 1
done

if [[ "${is_running}" != "true" ]]; then
  echo "wearable-ingestion-api is not in running state"
  exit 1
fi

restart_count="$("${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} ps -q wearable-ingestion-api | xargs docker inspect -f '{{ .RestartCount }}'" | tr -d '[:space:]')"
if [[ "${restart_count}" != "0" ]]; then
  echo "wearable-ingestion-api restart count is ${restart_count} (expected 0)"
  exit 1
fi

echo "Checking health endpoint..."
health_body=""
for _ in $(seq 1 30); do
  if health_body="$(curl -fsS "${BASE_URL}/healthz" 2>/dev/null)"; then
    break
  fi
  sleep 1
done

if [[ -z "${health_body}" ]]; then
  echo "Health endpoint did not become ready: ${BASE_URL}/healthz"
  exit 1
fi

python3 -c 'import json,sys; payload=json.loads(sys.stdin.read()); assert payload["status"]=="ok"; assert payload["service"]=="wearable-ingestion-api"' <<< "${health_body}"

echo "Checking OpenAPI endpoint..."
openapi_body="$(curl -fsS "${BASE_URL}/openapi.json")"
python3 -c '
import json,sys
payload=json.loads(sys.stdin.read())
assert payload["info"]["title"]=="wearable-ingestion-api"
assert "/upload-chunk" in payload["paths"]
assert "/healthz" in payload["paths"]
upload=payload["paths"]["/upload-chunk"]["post"]
req_ref=upload["requestBody"]["content"]["application/json"]["schema"]["$ref"]
assert req_ref.endswith("/UploadChunkRequest")
schemas=payload["components"]["schemas"]
assert "UploadChunkRequest" in schemas
assert "AckResponse" in schemas
assert "ErrorResponse" in schemas
assert "200" in upload["responses"]
assert "400" in upload["responses"]
' <<< "${openapi_body}"

echo "Checking Swagger docs endpoint..."
docs_status="$(curl -sS -o /dev/null -w "%{http_code}" "${BASE_URL}/docs")"
if [[ "${docs_status}" != "200" ]]; then
  echo "Expected 200 for /docs, got ${docs_status}"
  exit 1
fi

run_id="$(date +%s)"
chunk_id="deploy-${run_id}-001"
session_id="deploy-session-${run_id}"
stream_id="stream-hr-deploy-${run_id}"

valid_payload="$(mktemp)"
invalid_payload="$(mktemp)"
trap 'rm -f "${valid_payload}" "${invalid_payload}"' EXIT

cat > "${valid_payload}" <<EOF
{
  "schema_version": "1.0",
  "chunk_id": "${chunk_id}",
  "session_id": "${session_id}",
  "stream_id": "${stream_id}",
  "sequence": 1,
  "time": {
    "received_at_collector": "2026-04-25T11:00:00Z",
    "uploaded_at_collector": "2026-04-25T11:00:01Z"
  },
  "transport": {
    "encoding": "json",
    "compression": "none",
    "payload_schema": "polar.hr",
    "payload_version": "1.0"
  },
  "payload": {
    "samples": [
      {
        "hr": 71,
        "ppgQuality": 0,
        "correctedHr": 0,
        "rrsMs": [],
        "rrAvailable": false,
        "contactStatus": false,
        "contactStatusSupported": false
      }
    ]
  }
}
EOF

cat > "${invalid_payload}" <<EOF
{
  "schema_version": "1.0",
  "chunk_id": "invalid-${chunk_id}",
  "session_id": "${session_id}",
  "stream_id": "${stream_id}",
  "sequence": 2,
  "time": {
    "received_at_collector": "2026-04-25T11:01:00Z",
    "uploaded_at_collector": "2026-04-25T11:01:01Z"
  },
  "transport": {
    "encoding": "json",
    "compression": "none",
    "payload_schema": "polar.hr",
    "payload_version": "1.0"
  },
  "payload": {
    "samples": [
      {
        "ppgQuality": 0,
        "correctedHr": 0,
        "rrsMs": [],
        "rrAvailable": false,
        "contactStatus": false,
        "contactStatusSupported": false
      }
    ]
  }
}
EOF

echo "Posting valid HR upload..."
valid_response="$(curl -sS -X POST "${BASE_URL}/upload-chunk" -H "Content-Type: application/json" --data-binary "@${valid_payload}" -w $'\n%{http_code}')"
valid_status="${valid_response##*$'\n'}"
valid_body="${valid_response%$'\n'*}"

if [[ "${valid_status}" != "200" ]]; then
  echo "Expected 200 for valid payload, got ${valid_status}"
  echo "${valid_body}"
  exit 1
fi

storage_path="$(python3 -c 'import json,sys; payload=json.loads(sys.stdin.read()); assert payload["accepted"] is True; assert payload["status"]=="accepted"; print(payload["storage"]["storage_path"])' <<< "${valid_body}")"
if [[ -z "${storage_path}" ]]; then
  echo "Failed to read storage path from ACK response"
  exit 1
fi

echo "Validating raw JSONL was written..."
"${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} exec -T wearable-ingestion-api sh -lc 'test -s ${storage_path}'"
"${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} exec -T wearable-ingestion-api sh -lc 'grep -F \"${chunk_id}\" ${storage_path} >/dev/null'"
"${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} exec -T wearable-ingestion-api sh -lc 'tail -n 1 ${storage_path}'" \
  | python3 -c 'import json,sys; persisted=json.loads(sys.stdin.read()); sent=json.load(open(sys.argv[1], "r", encoding="utf-8")); assert persisted==sent; assert "received_at_server" not in persisted["time"]' "${valid_payload}"

before_lines="$("${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} exec -T wearable-ingestion-api sh -lc 'wc -l < ${storage_path}'" | tr -d '[:space:]')"

echo "Posting invalid HR upload..."
invalid_response="$(curl -sS -X POST "${BASE_URL}/upload-chunk" -H "Content-Type: application/json" --data-binary "@${invalid_payload}" -w $'\n%{http_code}')"
invalid_status="${invalid_response##*$'\n'}"
invalid_body="${invalid_response%$'\n'*}"

if [[ "${invalid_status}" != "400" ]]; then
  echo "Expected 400 for invalid payload, got ${invalid_status}"
  echo "${invalid_body}"
  exit 1
fi

python3 -c 'import json,sys; payload=json.loads(sys.stdin.read()); assert payload["accepted"] is False; assert payload["status"]=="rejected"; assert payload["error_code"]=="validation_error"; assert "details" in payload and payload["details"]' <<< "${invalid_body}"

echo "Recreating service to verify persistent raw volume..."
"${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} up -d --force-recreate wearable-ingestion-api >/dev/null"

health_body_after=""
for _ in $(seq 1 30); do
  if health_body_after="$(curl -fsS "${BASE_URL}/healthz" 2>/dev/null)"; then
    break
  fi
  sleep 1
done

if [[ -z "${health_body_after}" ]]; then
  echo "Health endpoint did not become ready after recreate: ${BASE_URL}/healthz"
  exit 1
fi

python3 -c 'import json,sys; payload=json.loads(sys.stdin.read()); assert payload["status"]=="ok"' <<< "${health_body_after}"

"${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} exec -T wearable-ingestion-api sh -lc 'test -s ${storage_path}'"
after_lines="$("${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} exec -T wearable-ingestion-api sh -lc 'wc -l < ${storage_path}'" | tr -d '[:space:]')"

if [[ "${after_lines}" -lt "${before_lines}" ]]; then
  echo "Raw JSONL line count decreased after recreate: before=${before_lines}, after=${after_lines}"
  exit 1
fi

"${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} exec -T wearable-ingestion-api sh -lc 'grep -F \"${chunk_id}\" ${storage_path} >/dev/null'"

echo "Checking service logs for startup/runtime errors..."
if "${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} logs --tail 120 wearable-ingestion-api | grep -Eiq \"traceback|exception|error\""; then
  echo "Found error-like lines in wearable-ingestion-api logs"
  exit 1
fi

echo "OK: container is running"
echo "OK: health endpoint responds"
echo "OK: OpenAPI is exposed (Swagger available at /docs)"
echo "OK: valid HR upload returns ACK"
echo "OK: raw JSONL is created/appended on server with exact payload preservation"
echo "OK: invalid payload returns structured error"
echo "OK: raw JSONL persists after restart/recreate"
