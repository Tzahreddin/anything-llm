# pm-knowledge AnythingLLM chat prompt (SoT for Lab)

Apply via API after workspace create / RAG purge:

```bash
# example — see docs/overnight/rag-eval-plan.md
curl -sS -X POST "$ANYTHINGLLM_URL/api/v1/workspace/pm-knowledge/update" \
  -H "Authorization: Bearer $ANYTHINGLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d @config/anythingllm/pm-knowledge-prompt.json
```

Also set workspace chat to oMLX: `chatProvider=generic-openai`, `chatModel=$GENERIC_OPEN_AI_MODEL_PREF`.

## Pins

- **Pin:** `AA-10-02.md` (Incident Zweck/Zone/Compose-Kopf).
- **Do not dual-pin** `owner-freigabe-checkliste.md` together with AA-10-02 — the checklist becomes CONTEXT 0 and crowds out the AA Kopf (G1 miss). Checklist still retrieves via vector for G4; draft→active Pflicht is also in prompt Rule 8.
