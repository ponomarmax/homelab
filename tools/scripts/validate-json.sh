#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

find "${PROJECT_ROOT}/packages/schemas" -name '*.json' -print0 | while IFS= read -r -d '' file; do
  python3 -m json.tool "${file}" >/dev/null
done

echo "Schema and example JSON files are syntactically valid."
