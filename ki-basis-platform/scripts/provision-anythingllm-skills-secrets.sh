#!/usr/bin/env bash
# Provision AnythingLLM Skill-Secrets (setup_args values) into the storage volume.
#
# AnythingLLM reads a Custom Agent Skill's setup_args values (API tokens,
# endpoints) from its plugin.json in the storage volume (parseCallOptions).
# Our config-as-code plugin.json files are deliberately value-less (no secrets
# in the repo, DEC-0021). This script fills in the live values so the Paperless,
# Firefly III and OpenProject skills can authenticate — without writing secrets
# to the repository.
#
# Token sources (from docker/.env, only set if present; never printed):
#   - PAPERLESS_API_TOKEN  (Paperless, Auth: Token <t>); priority: explicit
#                           .env value, else auto-detected Paperless DB token
#   - FIREFLY_API_TOKEN    (Firefly,  Auth: Bearer <t>)
#   - OPENPROJECT_API_KEY  (OpenProject, Auth: Basic base64("apikey:<t>"))
#
# Only touches plugin.json files already provisioned in the volume; writes the
# base/UI defaults plus the above tokens per skill (merge logic in
# docker/scripts/lib/skill_secrets.py, covered by the test-suite):
#   - paperless-*          -> paperless_base_url / paperless_ui_url / paperless_token
#   - firefly-*            -> firefly_base_url / firefly_token
#   - openproject-*        -> openproject_base_url / openproject_token
#
# Usage:
#   bash provision-anythingllm-skills-secrets.sh [--dry-run]
#   bash provision-anythingllm-skills-secrets.sh --token <TOKEN>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${COMPOSE_DIR}/.." && pwd)"
ENV_FILE="${COMPOSE_DIR}/.env"

PROJECT="${COMPOSE_PROJECT_NAME:-ki-basis}"
ANYTHINGLLM_STORAGE_VOLUME="${ANYTHINGLLM_STORAGE_VOLUME:-${PROJECT}-anythingllm-storage}"
PYTHON_IMG="${SKILL_SECRETS_PYTHON_IMAGE:-python:3-alpine}"

DRY_RUN=0
EXPLICIT_TOKEN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --token) EXPLICIT_TOKEN="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,26p' "$0" | sed -E 's/^# //; s/^#$//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# --- Preconditions ---
if ! docker volume inspect "${ANYTHINGLLM_STORAGE_VOLUME}" >/dev/null 2>&1; then
  echo "Volume ${ANYTHINGLLM_STORAGE_VOLUME} not found — provision skills first." >&2
  exit 1
fi

read_env() { grep -E "^${1}=" "$2" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' || true; }

# Empty / .env.example placeholders must not be written into live skills.
_usable_secret() {
  local v="${1:-}"
  [[ -n "${v}" ]] || return 1
  case "${v}" in
    change-me*|Change-me*|CHANGE-ME*|changeme*|Changeme*) return 1 ;;
  esac
  return 0
}

# --- Resolve Paperless API token (optional: OpenProject/Firefly still apply) ---
TOKEN="${EXPLICIT_TOKEN:-}"
if [[ -z "${TOKEN}" && -f "${ENV_FILE}" ]]; then
  TOKEN="$(read_env PAPERLESS_API_TOKEN "${ENV_FILE}")"
fi

if [[ -z "${TOKEN}" ]]; then
  # Auto-detect from Paperless postgres DB (admin authtoken), via psql.
  PG_CT="$(docker ps --format '{{.Names}}' | grep -E '^ki-basis-postgres$' | head -1 || true)"
  if [[ -n "${PG_CT}" ]]; then
    TOKEN="$(docker exec "${PG_CT}" psql -U postgres -d paperless -Atc \
      "SELECT t.key FROM auth_user u JOIN authtoken_token t ON t.user_id=u.id WHERE u.username='admin' LIMIT 1" 2>/dev/null || true)"
  fi
fi

if ! _usable_secret "${TOKEN}"; then
  echo "Hinweis: Kein nutzbares Paperless-API-Token (PAPERLESS_API_TOKEN / DB) — Paperless-Skills bleiben ohne Token." >&2
  TOKEN=""
fi

PAPERLESS_UI_URL="$(read_env PAPERLESS_UI_URL "${ENV_FILE}")"
PAPERLESS_UI_URL="${PAPERLESS_UI_URL:-http://127.0.0.1:8012}"

# --- Firefly III Personal Access Token (platform .env -> belegstack .env) ---
# Prefer a usable platform token; if empty/placeholder, fall back to belegstack PAT.
FIREFLY_TOKEN="$(read_env FIREFLY_API_TOKEN "${ENV_FILE}")"
FIREFLY_SRC="platform .env (FIREFLY_API_TOKEN)"
if ! _usable_secret "${FIREFLY_TOKEN}" && [[ -f ~/dev/belegstack/docker/.env ]]; then
  # belegstack uses the name FIREFLY_ACCESS_TOKEN for the same PAT.
  FIREFLY_TOKEN="$(read_env FIREFLY_ACCESS_TOKEN ~/dev/belegstack/docker/.env)"
  FIREFLY_SRC="belegstack/.env (FIREFLY_ACCESS_TOKEN)"
fi

# --- OpenProject API Key (platform .env -> running MCP container) ---
# The ki-pm stack was renamed ki-pm-pm -> ki-pm (DEC-0021). Accept either the
# new (ki-pm-openproject-mcp) or the legacy (ki-pm-pm-openproject-mcp) name so
# the script stays robust during/after a Rollback too.
OPENPROJECT_TOKEN="$(read_env OPENPROJECT_API_KEY "${ENV_FILE}")"


OP_MCP_CT=""
for _cand in ki-pm-openproject-mcp ki-pm-pm-openproject-mcp; do
  if docker inspect "${_cand}" >/dev/null 2>&1; then
    OP_MCP_CT="${_cand}"
    break
  fi
done
if [[ -z "${OPENPROJECT_TOKEN}" && -n "${OP_MCP_CT}" ]]; then
  OPENPROJECT_TOKEN="$(docker inspect "${OP_MCP_CT}" \
    --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
    | grep -E '^OPENPROJECT_API_KEY=' | head -1 | cut -d= -f2-)"

  OPENPROJECT_SRC="MCP-Container (${OP_MCP_CT})"
else
  OPENPROJECT_SRC="platform .env (OPENPROJECT_API_KEY)"
fi

if ! _usable_secret "${FIREFLY_TOKEN}"; then
  echo "Hinweis: Kein nutzbares Firefly-Token (FIREFLY_API_TOKEN) — Firefly-Skills bleiben ohne Token." >&2
  FIREFLY_TOKEN=""
fi
if ! _usable_secret "${OPENPROJECT_TOKEN}"; then
  echo "Hinweis: Kein nutzbares OpenProject-API-Key (OPENPROJECT_API_KEY / MCP) — OpenProject-Skills bleiben ohne Token." >&2
  OPENPROJECT_TOKEN=""
  OPENPROJECT_SRC="unset"
fi

# --- Persist resolved tokens back into the platform .env (never committed) ---
if [[ -f "${ENV_FILE}" && "${DRY_RUN}" == "0" ]]; then
  PAPERLESS_API_TOKEN="${TOKEN}" \
  FIREFLY_API_TOKEN="${FIREFLY_TOKEN:-}" \
  OPENPROJECT_API_KEY="${OPENPROJECT_TOKEN:-}" \
  python3 - "${ENV_FILE}" <<'PY'
import os
import sys
from pathlib import Path

env_path = Path(sys.argv[1])
values = {k: v for k, v in {
    "PAPERLESS_API_TOKEN": os.environ.get("PAPERLESS_API_TOKEN", ""),
    "FIREFLY_API_TOKEN": os.environ.get("FIREFLY_API_TOKEN", ""),
    "OPENPROJECT_API_KEY": os.environ.get("OPENPROJECT_API_KEY", ""),
}.items() if v and not v.startswith("change-me")}

text = env_path.read_text(encoding="utf-8")
lines = text.splitlines(keepends=True)
for key, val in values.items():
    pat = f"{key}="
    idx = next((i for i, ln in enumerate(lines) if ln.startswith(pat)), None)
    if idx is not None:
        cur = lines[idx].split("=", 1)[1].strip().strip('"')
        if cur.startswith("change-me"):
            lines[idx] = f"{key}={val}\n"
    else:
        lines.append(f"{key}={val}\n")
env_path.write_text("".join(lines), encoding="utf-8")
PY
fi

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "(--dry-run) Quelle: $([ -z "${EXPLICIT_TOKEN}" ] && echo PAPERLESS_DB/.env || echo --token)"
  echo "(--dry-run) Paperless: $([ -n "${TOKEN}" ] && echo "Token (${#TOKEN} Zeichen)" || echo "kein Token")"
  echo "(--dry-run) Firefly:   $([ -n "${FIREFLY_TOKEN}" ] && echo "Token (${#FIREFLY_TOKEN} Zeichen, ${FIREFLY_SRC})" || echo "kein Token (FIREFLY_API_TOKEN / belegstack FIREFLY_ACCESS_TOKEN)")"
  echo "(--dry-run) OpenProject:$([ -n "${OPENPROJECT_TOKEN}" ] && echo "Key (${#OPENPROJECT_TOKEN} Zeichen, ${OPENPROJECT_SRC})" || echo "kein Key (OPENPROJECT_API_KEY / OP-MCP-Container)")"
  echo "(--dry-run) Skills erhalten setup_args values; Storage unverändert."
  exit 0
fi

# --- Write setup_args values into the volume's plugin.json files (root container) ---
# The actual merge logic lives in lib/skill_secrets.py (single source of truth,
# covered by the test-suite). We mount the repo's lib dir into the throwaway
# container so the same code is used here as in tests.
docker run --rm -i \
  -v "${ANYTHINGLLM_STORAGE_VOLUME}:/storage" \
  -v "${SCRIPT_DIR}/lib:/opt/skills-helper:ro" \
  -e "PAPERLESS_TOKEN=${TOKEN}" \
  -e "PAPERLESS_UI_URL=${PAPERLESS_UI_URL}" \
  -e "FIREFLY_TOKEN=${FIREFLY_TOKEN:-}" \
  -e "OPENPROJECT_TOKEN=${OPENPROJECT_TOKEN:-}" \
  -e "PYTHONPATH=/opt/skills-helper" \
  "${PYTHON_IMG}" python -c '
import os
from pathlib import Path
from skill_secrets import apply_secret_overrides

tokens = {k: v for k, v in [
    ("paperless_token", os.environ.get("PAPERLESS_TOKEN", "")),
    ("firefly_token", os.environ.get("FIREFLY_TOKEN", "")),
    ("openproject_token", os.environ.get("OPENPROJECT_TOKEN", "")),
] if v}

changes = apply_secret_overrides(
    agent_skills_dir=Path("/storage/plugins/agent-skills"),
    tokens=tokens,
    ui_url=os.environ.get("PAPERLESS_UI_URL", "http://127.0.0.1:8012"),
)
if changes:
    print("Secret-Preservation geschrieben für:")
    for c in changes:
        print(f"  - {c}")
else:
    print("Keine Token-Änderungen (values bereits aktuell oder Platzhalter/.env leer).")
'
