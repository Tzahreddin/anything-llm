#!/usr/bin/env bash
# Merge declarative MCP server config into AnythingLLM storage (plugins/anythingllm_mcp_servers.json).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${COMPOSE_DIR}/.." && pwd)"
ENV_FILE="${COMPOSE_DIR}/.env"
MCP_CONFIG="${REPO_ROOT}/config/anythingllm/mcp_servers.json"

# shellcheck source=compose-status-helpers.sh
source "${SCRIPT_DIR}/compose-status-helpers.sh"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

if [[ ! -f "${MCP_CONFIG}" ]]; then
  echo "Missing ${MCP_CONFIG}" >&2
  exit 1
fi

PROJECT="${COMPOSE_PROJECT_NAME:-ki-basis}"
ANYTHINGLLM_STORAGE_VOLUME="${ANYTHINGLLM_STORAGE_VOLUME:-${PROJECT}-anythingllm-storage}"
TARGET_REL="plugins/anythingllm_mcp_servers.json"

if ! docker volume inspect "${ANYTHINGLLM_STORAGE_VOLUME}" >/dev/null 2>&1; then
  echo "Volume ${ANYTHINGLLM_STORAGE_VOLUME} not found — run: bash scripts/create-volumes.sh" >&2
  exit 1
fi

COMPOSE_DIR="${COMPOSE_DIR}" ki_basis_list_running_services
# Require the OpenProject web alias (web) to be reachable on the network, or the
# OpenProject web container to be running.
# The ki-pm stack was renamed ki-pm-pm -> ki-pm (DEC-0021), so accept both names.
if ! docker exec ki-basis-anythingllm getent hosts web >/dev/null 2>&1 \
  && ! getent hosts web >/dev/null 2>&1 \
  && ! docker ps --format '{{.Names}}' | grep -Eq '^ki-pm(-pm)?-web$'; then
  echo "OpenProject web (ki-pm-web / ki-pm-pm-web) is not running — start ki-pm before provisioning MCP config" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

existing_json="${tmp_dir}/existing.json"
if docker run --rm \
  -v "${ANYTHINGLLM_STORAGE_VOLUME}:/storage:ro" \
  alpine:3.21 sh -c "test -f /storage/${TARGET_REL} && cat /storage/${TARGET_REL}" \
  >"${existing_json}" 2>/dev/null; then
  :
else
  echo '{"mcpServers":{}}' >"${existing_json}"
fi

merged_json="${tmp_dir}/anythingllm_mcp_servers.json"
python3 - "${existing_json}" "${MCP_CONFIG}" "${merged_json}" <<'PY'
import json
import sys
from pathlib import Path

existing = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8") or "{}")
incoming = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
out_path = Path(sys.argv[3])

merged = {"mcpServers": dict(existing.get("mcpServers") or {})}
merged["mcpServers"].update(incoming.get("mcpServers") or {})
out_path.write_text(json.dumps(merged, indent=2) + "\n", encoding="utf-8")
PY

docker run --rm \
  -v "${ANYTHINGLLM_STORAGE_VOLUME}:/storage" \
  -v "${merged_json}:/seed/anythingllm_mcp_servers.json:ro" \
  alpine:3.21 sh -c "mkdir -p /storage/plugins && cp /seed/anythingllm_mcp_servers.json /storage/${TARGET_REL}"

echo "${ANYTHINGLLM_STORAGE_VOLUME}:/storage/${TARGET_REL}"
