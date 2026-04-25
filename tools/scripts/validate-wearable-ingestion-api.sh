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
session_id="deploy-session-${run_id}"
stream_id="stream-generic-deploy-${run_id}"
generic_chunk_id="deploy-${run_id}-generic-001"
hr_chunk_id="deploy-${run_id}-hr-001"
nosamples_chunk_id="deploy-${run_id}-nosamples-001"
invalid_chunk_id="deploy-${run_id}-invalid-001"

generic_payload_file="$(mktemp)"
hr_payload_file="$(mktemp)"
no_samples_payload_file="$(mktemp)"
invalid_payload_file="$(mktemp)"
trap 'rm -f "${generic_payload_file}" "${hr_payload_file}" "${no_samples_payload_file}" "${invalid_payload_file}"' EXIT

cat > "${generic_payload_file}" <<EOF
{
  "schema_version": "1.0",
  "chunk_id": "${generic_chunk_id}",
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
    "payload_schema": "custom.generic",
    "payload_version": "0.1"
  },
  "payload": {
    "events": [
      {"kind": "marker", "value": 1}
    ],
    "meta": {"source": "deploy-validation"}
  }
}
EOF

cat > "${hr_payload_file}" <<EOF
{
  "schema_version": "1.0",
  "chunk_id": "${hr_chunk_id}",
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
        "received_at_collector": "2026-04-25T11:00:00.357Z",
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

cat > "${no_samples_payload_file}" <<EOF
{
  "schema_version": "1.0",
  "chunk_id": "${nosamples_chunk_id}",
  "session_id": "${session_id}",
  "stream_id": "${stream_id}",
  "sequence": 3,
  "time": {
    "received_at_collector": "2026-04-25T11:02:00Z",
    "uploaded_at_collector": "2026-04-25T11:02:01Z"
  },
  "transport": {
    "encoding": "json",
    "compression": "none",
    "payload_schema": "custom.nosamples",
    "payload_version": "1.0"
  },
  "payload": {
    "metadata": {
      "session_type": "test"
    },
    "reading": 123.45
  }
}
EOF

cat > "${invalid_payload_file}" <<EOF
{
  "schema_version": "1.0",
  "chunk_id": "${invalid_chunk_id}",
  "session_id": "${session_id}",
  "stream_id": "${stream_id}",
  "sequence": 4,
  "time": {
    "received_at_collector": "2026-04-25T11:03:00Z",
    "uploaded_at_collector": "2026-04-25T11:03:01Z"
  },
  "transport": {
    "compression": "none",
    "payload_schema": "polar.hr",
    "payload_version": "1.0"
  },
  "payload": {
    "samples": [
      {
        "received_at_collector": "2026-04-25T11:03:00.357Z",
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

post_chunk() {
  local payload_file="$1"
  curl -sS -X POST "${BASE_URL}/upload-chunk" -H "Content-Type: application/json" --data-binary "@${payload_file}" -w $'\n%{http_code}'
}

echo "Posting valid generic upload..."
generic_response="$(post_chunk "${generic_payload_file}")"
generic_status="${generic_response##*$'\n'}"
generic_body="${generic_response%$'\n'*}"

if [[ "${generic_status}" != "200" ]]; then
  echo "Expected 200 for generic payload, got ${generic_status}"
  echo "${generic_body}"
  exit 1
fi

generic_storage_path="$(python3 -c 'import json,sys; payload=json.loads(sys.stdin.read()); assert payload["accepted"] is True; assert payload["status"]=="accepted"; print(payload["storage"]["storage_path"])' <<< "${generic_body}")"

if [[ -z "${generic_storage_path}" ]]; then
  echo "Failed to read storage path from generic ACK response"
  exit 1
fi

echo "Validating generic raw JSONL preservation..."
"${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} exec -T wearable-ingestion-api sh -lc 'test -s ${generic_storage_path}'"
"${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} exec -T wearable-ingestion-api sh -lc 'grep -F \"${generic_chunk_id}\" ${generic_storage_path} >/dev/null'"
"${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} exec -T wearable-ingestion-api sh -lc 'tail -n 1 ${generic_storage_path}'" \
  | python3 -c 'import json,sys; persisted=json.loads(sys.stdin.read()); sent=json.load(open(sys.argv[1], "r", encoding="utf-8")); assert persisted==sent; assert "received_at_server" not in persisted["time"]' "${generic_payload_file}"

echo "Posting valid HR upload..."
hr_response="$(post_chunk "${hr_payload_file}")"
hr_status="${hr_response##*$'\n'}"
hr_body="${hr_response%$'\n'*}"

if [[ "${hr_status}" != "200" ]]; then
  echo "Expected 200 for HR payload, got ${hr_status}"
  echo "${hr_body}"
  exit 1
fi

hr_storage_path="$(python3 -c 'import json,sys; payload=json.loads(sys.stdin.read()); assert payload["accepted"] is True; assert payload["status"]=="accepted"; print(payload["storage"]["storage_path"])' <<< "${hr_body}")"
"${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} exec -T wearable-ingestion-api sh -lc 'grep -F \"${hr_chunk_id}\" ${hr_storage_path} >/dev/null'"
"${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} exec -T wearable-ingestion-api sh -lc 'tail -n 1 ${hr_storage_path}'" \
  | python3 -c 'import json,sys; persisted=json.loads(sys.stdin.read()); sent=json.load(open(sys.argv[1], "r", encoding="utf-8")); assert persisted==sent; sample=sent["payload"]["samples"][0]; assert "received_at_collector" in sample' "${hr_payload_file}"

echo "Posting valid payload without samples..."
no_samples_response="$(post_chunk "${no_samples_payload_file}")"
no_samples_status="${no_samples_response##*$'\n'}"
no_samples_body="${no_samples_response%$'\n'*}"
if [[ "${no_samples_status}" != "200" ]]; then
  echo "Expected 200 for payload without samples, got ${no_samples_status}"
  echo "${no_samples_body}"
  exit 1
fi
python3 -c 'import json,sys; payload=json.loads(sys.stdin.read()); assert payload["accepted"] is True; assert payload["status"]=="accepted"' <<< "${no_samples_body}"

echo "Posting malformed transport payload..."
invalid_response="$(post_chunk "${invalid_payload_file}")"
invalid_status="${invalid_response##*$'\n'}"
invalid_body="${invalid_response%$'\n'*}"
if [[ "${invalid_status}" != "400" ]]; then
  echo "Expected 400 for malformed transport, got ${invalid_status}"
  echo "${invalid_body}"
  exit 1
fi
python3 -c 'import json,sys; payload=json.loads(sys.stdin.read()); assert payload["accepted"] is False; assert payload["status"]=="rejected"; assert payload["error_code"]=="validation_error"; assert "details" in payload and payload["details"]; assert any(d["field"]=="transport.encoding" for d in payload["details"])' <<< "${invalid_body}"

before_lines="$("${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} exec -T wearable-ingestion-api sh -lc 'wc -l < ${generic_storage_path}'" | tr -d '[:space:]')"

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

"${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} exec -T wearable-ingestion-api sh -lc 'test -s ${generic_storage_path}'"
after_lines="$("${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} exec -T wearable-ingestion-api sh -lc 'wc -l < ${generic_storage_path}'" | tr -d '[:space:]')"

if [[ "${after_lines}" -lt "${before_lines}" ]]; then
  echo "Raw JSONL line count decreased after recreate: before=${before_lines}, after=${after_lines}"
  exit 1
fi

"${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} exec -T wearable-ingestion-api sh -lc 'grep -F \"${generic_chunk_id}\" ${generic_storage_path} >/dev/null'"

echo "Checking service logs for startup/runtime errors..."
if "${SSH_SCRIPT}" "docker compose --env-file '${REMOTE_PROJECT_ROOT}/.env' ${REMOTE_COMPOSE_FILES} logs --tail 120 wearable-ingestion-api | grep -Eiq \"traceback|exception|error\""; then
  echo "Found error-like lines in wearable-ingestion-api logs"
  exit 1
fi

echo "OK: container is running"
echo "OK: health endpoint responds"
echo "OK: OpenAPI is exposed (Swagger available at /docs)"
echo "OK: valid generic upload returns ACK"
echo "OK: valid HR upload with sample-level received_at_collector returns ACK"
echo "OK: payload without samples returns ACK"
echo "OK: raw JSONL preserves payload exactly as received"
echo "OK: malformed transport envelope returns structured validation error"
echo "OK: raw JSONL persists after restart/recreate"
