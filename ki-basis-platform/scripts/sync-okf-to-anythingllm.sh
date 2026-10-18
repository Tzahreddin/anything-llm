#!/usr/bin/env bash
# Sync OKF markdown from docs/knowledge/ into AnythingLLM workspaces (config/anythingllm/workspaces.yaml).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${COMPOSE_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${COMPOSE_DIR}/.env" 2>/dev/null || true

ANYTHINGLLM_URL="${ANYTHINGLLM_URL:-http://127.0.0.1:${ANYTHINGLLM_HOST_PORT:-3003}}"
ANYTHINGLLM_API_KEY="${ANYTHINGLLM_API_KEY:?Set ANYTHINGLLM_API_KEY in docker/.env}"
WORKSPACES_YAML="${REPO_ROOT}/config/anythingllm/workspaces.yaml"
KNOWLEDGE_ROOT="${REPO_ROOT}/docs/knowledge"

if [[ ! -f "${WORKSPACES_YAML}" ]]; then
  echo "Not found: ${WORKSPACES_YAML}" >&2
  exit 1
fi

auth_header="Authorization: Bearer ${ANYTHINGLLM_API_KEY}"

echo "=== OKF → AnythingLLM sync ==="
echo "URL: ${ANYTHINGLLM_URL}"
echo ""

ensure_workspace() {
  local slug="$1"
  local name="$2"
  local existing
  existing="$(curl -sfS "${ANYTHINGLLM_URL}/api/v1/workspaces" -H "${auth_header}")"
  local has_workspace
  has_workspace="$(python3 -c 'import json,sys; slug=sys.argv[1]; data=json.load(sys.stdin); workspaces=data if isinstance(data,list) else data.get("workspaces",[]); print(any(w.get("slug")==slug for w in workspaces))' "${slug}" <<<"${existing}")"
  if [[ "${has_workspace}" != "True" ]]; then
    curl -sfS -X POST "${ANYTHINGLLM_URL}/api/v1/workspace/new" \
      -H "${auth_header}" \
      -H 'Content-Type: application/json' \
      -d "{\"name\":\"${slug}\"}" >/dev/null
    echo "  Created workspace: ${slug} (${name})"
  else
    echo "  Workspace exists: ${slug}"
  fi
}

upload_okf_file() {
  local file="$1"
  local slug="$2"
  local rel="${file#${REPO_ROOT}/}"
  echo "    ↑ ${rel}"
  curl -sfS -X POST "${ANYTHINGLLM_URL}/api/v1/document/upload" \
    -H "${auth_header}" \
    -F "file=@${file}" \
    -F "addToWorkspaces=${slug}" >/dev/null
}

while IFS=$'\t' read -r slug name okf_path; do
  bundle_dir="${REPO_ROOT}/${okf_path}"
  if [[ ! -d "${bundle_dir}" ]]; then
    echo "SKIP  ${slug} — missing: ${bundle_dir}"
    continue
  fi

  echo "Bundle: ${slug} (${bundle_dir})"
  ensure_workspace "${slug}" "${name}"

  while IFS= read -r -d '' md_file; do
    base="$(basename "${md_file}")"
    if [[ "${base}" == "index.md" || "${base}" == log.md ]]; then
      continue
    fi
    upload_okf_file "${md_file}" "${slug}"
  done < <(find "${bundle_dir}" -name '*.md' -type f -print0)

  echo ""
done < <(python3 - "${WORKSPACES_YAML}" <<'PY'
import sys
try:
    import yaml
except ImportError:
    sys.exit("PyYAML required: pip install pyyaml")
from pathlib import Path

data = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8")) or {}
for ws in data.get("workspaces", []):
    print(f"{ws['slug']}\t{ws.get('name', ws['slug'])}\t{ws['okf_path']}")
PY
)

echo "OKF sync complete. Check workspaces at ${ANYTHINGLLM_URL}"
