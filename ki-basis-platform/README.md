# ki-basis platform archive (AnythingLLM era)

Moved out of `~/dev/ki-basis` after DEC-0061 (Open WebUI replaces AnythingLLM).

Contents:
- `docker/anythingllm/` — former platform image Dockerfile, wiki-wrapper snapshot, page-context
- `docker/anythingllm-sso-bridge/` — Authentik Simple-SSO bridge (unused)
- `config/anythingllm/` — workspaces / MCP / prompts (agent-skills symlink not copied; SoT is `~/dev/skills`)
- `scripts/` — provision/sync/bootstrap helpers for the removed Compose service

Do not run these against a current ki-basis stack. Chat path is Open WebUI + Cascade + skill-runner.
