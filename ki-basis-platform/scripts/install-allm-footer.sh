#!/usr/bin/env bash
# Set AnythingLLM custom footer icons (#488) — replaces Mintplex GitHub/Discord defaults.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${COMPOSE_DIR}/.env"
[[ -f "$ENV_FILE" ]] && { set -a; # shellcheck disable=SC1090
  source "$ENV_FILE"; set +a; }
ALLM_URL="${ALLM_PUBLIC_URL:-http://127.0.0.1:${ANYTHINGLLM_HOST_PORT:-3003}}"
OP_URL="${OPENPROJECT_PUBLIC_URL:-http://127.0.0.1:${OPENPROJECT_HOST_PORT:-8084}}"
FOOTER=$(ALLM_URL="$ALLM_URL" OP_URL="$OP_URL" python3 - <<'PY'
import json, os
print(json.dumps([
  {"icon": "HouseLine", "url": os.environ["ALLM_URL"].rstrip("/") + "/skill-view.html"},
  {"icon": "Briefcase", "url": os.environ["OP_URL"].rstrip("/") + "/"},
  {"icon": "BookOpen", "url": os.environ["ALLM_URL"].rstrip("/") + "/skill-profiles.html"},
]))
PY
)
docker exec -i ki-basis-postgres psql -U "${ANYTHINGLLM_DB_USER:-anythingllm}" -d "${ANYTHINGLLM_DB_NAME:-anythingllm}" <<SQL
INSERT INTO system_settings (label, value, "createdAt", "lastUpdatedAt")
VALUES ('footer_data', \$json\$${FOOTER}\$json\$, NOW(), NOW())
ON CONFLICT (label) DO UPDATE SET value = EXCLUDED.value, "lastUpdatedAt" = NOW();
SQL
echo "footer_data set → Skill-View / OpenProject / Profiles"
