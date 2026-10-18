#!/usr/bin/env bash
# Bootstrap AnythingLLM API key and workspaces from config/anythingllm/workspaces.yaml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${COMPOSE_DIR}/.." && pwd)"
ENV_FILE="${COMPOSE_DIR}/.env"
WORKSPACES_YAML="${REPO_ROOT}/config/anythingllm/workspaces.yaml"

ANYTHINGLLM_URL="${ANYTHINGLLM_URL:-http://127.0.0.1:${ANYTHINGLLM_HOST_PORT:-3003}}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

api_key="${ANYTHINGLLM_API_KEY:-}"
if [[ -z "${api_key}" || "${api_key}" == change-me-after-first-login ]]; then
  response="$(curl -sfS -X POST "${ANYTHINGLLM_URL}/api/system/generate-api-key" \
    -H 'Content-Type: application/json' \
    -d '{}')"
  api_key="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["apiKey"]["secret"])' <<<"${response}")"
  if grep -q '^ANYTHINGLLM_API_KEY=' "${ENV_FILE}"; then
    sed -i.bak "s|^ANYTHINGLLM_API_KEY=.*|ANYTHINGLLM_API_KEY=${api_key}|" "${ENV_FILE}"
    rm -f "${ENV_FILE}.bak"
  else
    echo "ANYTHINGLLM_API_KEY=${api_key}" >> "${ENV_FILE}"
  fi
  echo "AnythingLLM API key written to ${ENV_FILE}"
else
  echo "AnythingLLM API key already set in ${ENV_FILE}"
fi

if [[ ! -f "${WORKSPACES_YAML}" ]]; then
  echo "No workspaces.yaml at ${WORKSPACES_YAML} — skipping workspace bootstrap"
  exit 0
fi

while IFS=$'\t' read -r slug name; do
  [[ -z "${slug}" ]] && continue
  existing="$(curl -sfS "${ANYTHINGLLM_URL}/api/v1/workspaces" \
    -H "Authorization: Bearer ${api_key}")"
  has_workspace="$(python3 -c 'import json,sys; slug=sys.argv[1]; data=json.load(sys.stdin); workspaces=data if isinstance(data,list) else data.get("workspaces",[]); print(any(w.get("slug")==slug for w in workspaces))' "${slug}" <<<"${existing}")"
  if [[ "${has_workspace}" != "True" ]]; then
    curl -sfS -X POST "${ANYTHINGLLM_URL}/api/v1/workspace/new" \
      -H "Authorization: Bearer ${api_key}" \
      -H 'Content-Type: application/json' \
      -d "{\"name\":\"${slug}\"}" >/dev/null
    echo "Created AnythingLLM workspace '${slug}' (${name})"
  else
    echo "AnythingLLM workspace '${slug}' already exists"
  fi
done < <(python3 - "${WORKSPACES_YAML}" <<'PY'
import sys
try:
    import yaml
except ImportError:
    sys.exit("PyYAML required: pip install pyyaml")
from pathlib import Path

data = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8")) or {}
for ws in data.get("workspaces", []):
    print(f"{ws['slug']}\t{ws.get('name', ws['slug'])}")
PY
)
