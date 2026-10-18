#!/usr/bin/env bash
# Install custom AnythingLLM logo into storage volume (#487).
# Usage: bash docker/scripts/install-allm-logo.sh [path-to.png]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${COMPOSE_DIR}/.." && pwd)"
ENV_FILE="${COMPOSE_DIR}/.env"
[[ -f "$ENV_FILE" ]] && { set -a; # shellcheck disable=SC1090
  source "$ENV_FILE"; set +a; }
SRC="${1:-$REPO_ROOT/branding/ki-buero/logo-512.png}"
LIGHT="${2:-$REPO_ROOT/branding/ki-buero/logo-512-light.png}"
C="${COMPOSE_PROJECT_NAME:-ki-basis}-anythingllm"
test -f "$SRC"
EXT="${SRC##*.}"
NEW_NAME="$(uuidgen | tr '[:upper:]' '[:lower:]').${EXT}"
docker exec "$C" mkdir -p /app/server/storage/assets
docker cp "$SRC" "$C:/app/server/storage/assets/${NEW_NAME}"
if [[ -f "$LIGHT" ]]; then
  docker cp "$SRC" "$C:/app/server/storage/assets/anything-llm.png"
  docker cp "$LIGHT" "$C:/app/server/storage/assets/anything-llm-invert.png"
fi
docker exec -i ki-basis-postgres psql -U "${ANYTHINGLLM_DB_USER:-anythingllm}" -d "${ANYTHINGLLM_DB_NAME:-anythingllm}" <<SQL
INSERT INTO system_settings (label, value, "createdAt", "lastUpdatedAt")
VALUES ('logo_filename', '${NEW_NAME}', NOW(), NOW())
ON CONFLICT (label) DO UPDATE SET value = EXCLUDED.value, "lastUpdatedAt" = NOW();
SQL
echo "Installed custom logo_filename=${NEW_NAME}"
# Verify API
docker exec "$C" node -e '
const http=require("http");
http.get("http://127.0.0.1:3001/api/system/is-default-logo",(r)=>{let d="";r.on("data",c=>d+=c);r.on("end",()=>console.log(r.statusCode,d));});
'
