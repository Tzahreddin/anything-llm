#!/usr/bin/env bash
# Provision declarative AnythingLLM Agent Skills (config/anythingllm/agent-skills)
# into the AnythingLLM storage volume using a validated, idempotent Python sync
# (lib/agent_skills_sync.py).
#
# Better approach vs. the old loop-copy script:
#   - Single plan/apply step with manifest + handler.js validation
#   - Removes orphaned skills that were deleted from config
#   - Idempotent "no changes = no-op" behaviour
#   - Optional --dry-run to preview without touching the volume
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${COMPOSE_DIR}/.." && pwd)"
ENV_FILE="${COMPOSE_DIR}/.env"
# Default: symlink to ~/dev/skills (legacy). Prefer twin+shared merge when enabled.
SKILLS_SRC="${REPO_ROOT}/config/anythingllm/agent-skills"
MERGED_SRC="${REPO_ROOT}/config/anythingllm/agent-skills-merged"

# --- CLI ---
DRY_RUN=0
RESTART=0
SKIP_TWIN_SYNC=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --restart) RESTART=1; shift ;;
    --skip-twin-sync) SKIP_TWIN_SYNC=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

PROJECT="${COMPOSE_PROJECT_NAME:-ki-basis}"
ANYTHINGLLM_STORAGE_VOLUME="${ANYTHINGLLM_STORAGE_VOLUME:-${PROJECT}-anythingllm-storage}"

# WP #573 / DEC-0061: merge twin domain skills + shared platform into staging (Phase 1:
# empty twin overlays → bit-identical to ~/dev/skills). Disable with AGENT_SKILLS_USE_MERGED=0.
if [[ "${AGENT_SKILLS_USE_MERGED:-1}" == "1" ]]; then
  if [[ "${SKIP_TWIN_SYNC}" != "1" ]]; then
    bash "${SCRIPT_DIR}/sync-twin-agent-skills.sh"
  fi
  if [[ -d "${MERGED_SRC}" ]]; then
    SKILLS_SRC="${MERGED_SRC}"
  fi
fi

if [[ ! -d "${SKILLS_SRC}" ]]; then
  echo "Missing ${SKILLS_SRC}" >&2
  exit 1
fi
echo "Using SKILLS_SRC=${SKILLS_SRC}"

if ! docker volume inspect "${ANYTHINGLLM_STORAGE_VOLUME}" >/dev/null 2>&1; then
  echo "Volume ${ANYTHINGLLM_STORAGE_VOLUME} not found — run: bash scripts/create-volumes.sh" >&2
  exit 1
fi

# Materialise the volume's current agent-skills content into a scratch dir so the
# Python sync can read/write it as a plain directory (validation + orphan pruning).
SCRATCH="$(mktemp -d)"
trap 'rm -rf "${SCRATCH}"' EXIT

docker run --rm \
  -v "${ANYTHINGLLM_STORAGE_VOLUME}:/storage" \
  -v "${SCRATCH}:/scratch" \
  alpine:3.21 sh -c '
    mkdir -p /scratch/plugins
    if [ -d /storage/plugins/agent-skills ]; then
      cp -a /storage/plugins/agent-skills /scratch/plugins/
    fi
  '

# Run validated, idempotent sync against the scratch copy.
PY_ARGS=(--skills-src "${SKILLS_SRC}" --volume-dir "${SCRATCH}")
if [[ "${DRY_RUN}" == "1" ]]; then
  PY_ARGS+=(--dry-run)
fi

set +e
python3 "${SCRIPT_DIR}/lib/agent_skills_sync.py" "${PY_ARGS[@]}"
rc=$?
set -e

if [[ ${rc} -ne 0 ]]; then
  echo "Skill-Sync fehlgeschlagen — Storage nicht geändert." >&2
  exit ${rc}
fi

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "(--dry-run — keine Änderungen geschrieben)"
  exit 0
fi

# Push the reconciled skills back into the volume (single copy pass).
docker run --rm \
  -v "${ANYTHINGLLM_STORAGE_VOLUME}:/storage" \
  -v "${SCRATCH}:/scratch" \
  alpine:3.21 sh -c '
    mkdir -p /storage/plugins/agent-skills
    rm -rf /storage/plugins/agent-skills
    cp -a /scratch/plugins/agent-skills /storage/plugins/
  '

echo "Provisioned agent-skills into ${ANYTHINGLLM_STORAGE_VOLUME}:/storage/plugins/agent-skills/"

# Fan-out OPENPROJECT_API_KEY / Firefly / Paperless from docker/.env into every
# matching skill (idempotent; placeholders are skipped, missing apps warn only).
echo "Applying skill secrets from ${ENV_FILE} ..."
bash "${SCRIPT_DIR}/provision-anythingllm-skills-secrets.sh"

# Derived Skill-Speicher index (pgvector). Soft-fail unless DB expected.
if [[ -n "${SKILL_REGISTRY_DSN:-}" ]]; then
  echo "Syncing skill_registry.skill_index ..."
  bash "${SCRIPT_DIR}/provision-skill-catalog.sh" || {
    echo "WARNUNG: skill catalog index fehlgeschlagen (Stack-Start läuft weiter)." >&2
  }
else
  echo "HINWEIS: SKILL_REGISTRY_DSN nicht gesetzt — skill_index Sync übersprungen"
fi

if [[ "${RESTART}" == "1" ]]; then
  echo "Restarting AnythingLLM to load skills..."
  docker restart "${PROJECT}-anythingllm" || {
    echo "WARNING: AnythingLLM-Container nicht neu gestartet (Name '${PROJECT}-anythingllm')." >&2
  }
fi
