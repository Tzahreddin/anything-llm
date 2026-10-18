#!/usr/bin/env bash
# Plan 3 acceptance: Skill-Verzeichnisse, Kataloge und Handler.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${COMPOSE_DIR}/.." && pwd)"
ENV_FILE="${COMPOSE_DIR}/.env"
SKILLS_LINK="${REPO_ROOT}/config/anythingllm/agent-skills"
PROJECT="${COMPOSE_PROJECT_NAME:-ki-basis}"
CTR="${PROJECT}-anythingllm"
ORCH_CTR="${PROJECT}-agent-orchestrator"
STORE="/app/server/storage/plugins/agent-skills"
FAIL=0

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
fi

ok() { echo "OK  $*"; }
bad() { echo "FAIL $*"; FAIL=1; }

echo "=== Plan 3: Skill-Verzeichnisse / Kataloge / Handler ==="

if [[ -L "${SKILLS_LINK}" ]]; then
  ok "ki-basis symlink → $(readlink "${SKILLS_LINK}")"
else
  bad "missing symlink ${SKILLS_LINK}"
fi

SKILLS_SRC="$(cd "${SKILLS_LINK}" && pwd -P)"
for d in projects platform workflows knowledge scripts; do
  [[ -d "${SKILLS_SRC}/${d}" ]] && ok "source tree has ${d}/" || bad "source missing ${d}/"
done
[[ -f "${SKILLS_SRC}/CATALOG.json" ]] && ok "source CATALOG.json" || bad "source CATALOG.json missing"
[[ -f "${SKILLS_SRC}/projects/openproject/openproject-projects/handler.js" ]] \
  && ok "source openproject-projects/handler.js" \
  || bad "source openproject-projects/handler.js missing"
[[ -f "${SKILLS_SRC}/platform/api-client/apiClient.js" ]] \
  && ok "source platform/api-client" \
  || bad "source platform/api-client missing"

if rg -q '/api/v3/projects' "${SKILLS_SRC}/projects/openproject/openproject-projects/handler.js"; then
  ok "openproject-projects list uses /api/v3/projects"
else
  bad "openproject-projects handler missing /api/v3/projects"
fi
if rg -q 'mcp|MCP' "${SKILLS_SRC}/projects/openproject/openproject-projects/handler.js"; then
  bad "openproject-projects handler references MCP"
else
  ok "openproject-projects handler has no MCP path"
fi

if docker inspect "${CTR}" >/dev/null 2>&1; then
  if docker exec "${CTR}" sh -c "
    test -f ${STORE}/CATALOG.json &&
    test -f ${STORE}/projects/openproject/openproject-projects/handler.js &&
    test -f ${STORE}/projects/openproject/openproject-projects/plugin.json &&
    test -f ${STORE}/platform/api-client/apiClient.js &&
    test -f ${STORE}/projects/openproject/_lib/opFetch.js &&
    test -f ${STORE}/projects/firefly-iii/_lib/ffFetch.js
  "; then
    ok "STORE has CATALOG, OP handler/plugin, api-client, _lib"
  else
    bad "STORE incomplete — run provision-anythingllm-skills.sh"
  fi
else
  bad "container ${CTR} not running"
fi

if docker inspect "${ORCH_CTR}" >/dev/null 2>&1; then
  MOUNTS="$(docker inspect "${ORCH_CTR}" --format '{{range .Mounts}}{{.Destination}} {{end}}')"
  echo "${MOUNTS}" | rg -q '/app/skills' && ok "orchestrator mounts /app/skills" \
    || bad "orchestrator missing /app/skills mount"
  echo "${MOUNTS}" | rg -q '/skills/agent-skills' && ok "orchestrator mounts agent-skills" \
    || bad "orchestrator missing /skills/agent-skills mount"
else
  echo "SKIP orchestrator container not running"
fi

: "${POSTGRES_USER:=postgres}"
: "${POSTGRES_PASSWORD:=change-me-postgres}"
if docker inspect "${PROJECT}-postgres" >/dev/null 2>&1; then
  COUNT="$(docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" "${PROJECT}-postgres" \
    psql -U "${POSTGRES_USER}" -d skill_registry -tAc "SELECT count(*) FROM skill_index;" 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ -n "${COUNT}" && "${COUNT}" =~ ^[0-9]+$ && "${COUNT}" -gt 0 ]]; then
    ok "skill_registry.skill_index rows=${COUNT}"
  else
    bad "skill_registry.skill_index empty or unreachable (count='${COUNT}')"
  fi
else
  bad "postgres container missing"
fi

echo "=== Plan 3 result: $([[ ${FAIL} -eq 0 ]] && echo PASS || echo FAIL) ==="
exit "${FAIL}"
