#!/usr/bin/env bash
# Sync filtered vendor + domain markdown into AnythingLLM workspaces (workspaces.yaml).
# Upload each unique file once; attach to tool workspace(s) + stack when MULTI_ATTACH=1.
#
# Probed 2026-07-27: comma-separated addToWorkspaces works → MULTI_ATTACH=1 (see docs_sync_api.py).
#
# Env: ANYTHINGLLM_URL, ANYTHINGLLM_API_KEY (from docker/.env), optional DOCS_SYNC_DRY_RUN=1,
#      DOCS_SYNC_PYTHON (interpreter with PyYAML; set by sync-ext-corpus.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
# Bash 3.2 (macOS): failed `source` is fatal even with `|| true` — guard with -f.
if [[ -f "${COMPOSE_DIR}/.env" ]]; then
  source "${COMPOSE_DIR}/.env"
fi

export ANYTHINGLLM_URL="${ANYTHINGLLM_URL:-http://127.0.0.1:${ANYTHINGLLM_HOST_PORT:-3003}}"

if [[ "${DOCS_SYNC_DRY_RUN:-}" != "1" ]]; then
  export ANYTHINGLLM_API_KEY="${ANYTHINGLLM_API_KEY:?Set ANYTHINGLLM_API_KEY in docker/.env}"
fi

exec "${DOCS_SYNC_PYTHON:-python3}" "${SCRIPT_DIR}/lib/docs_sync_api.py" "$@"
