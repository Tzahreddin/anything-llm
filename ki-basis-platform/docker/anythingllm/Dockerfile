# syntax=docker/dockerfile:1
# Optional pin/ensure tooling for PM-knowledge wrappers (DEC-0030).
# Upstream mintplexlabs/anythingllm:pg already ships git + python3 on Ubuntu 24.04.
# Patches: Intelligent Skill Selector domain-bypass (toolReranker.js).
FROM mintplexlabs/anythingllm:pg

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends git python3 ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /opt/wiki/bin /srv/PM-knowledge /srv/git \
 && chown -R anythingllm:anythingllm /opt/wiki /srv/PM-knowledge /srv/git

# ki-basis: domain bypass + lexicon-router + inventory/list + GLiNER-first + skill-router fail-open.
COPY docker/anythingllm/patches/toolReranker.js \
     /app/server/utils/agents/aibitat/utils/toolReranker.js
COPY docker/anythingllm/patches/skillRouter.js \
     /app/server/utils/agents/aibitat/utils/skillRouter.js
COPY docker/anythingllm/patches/glinerFirstRouter.js \
     /app/server/utils/agents/aibitat/utils/glinerFirstRouter.js
COPY docker/anythingllm/patches/projectLexicon.js \
     /app/server/utils/agents/aibitat/utils/projectLexicon.js
COPY docker/anythingllm/patches/lexiconMemoryStore.js \
     /app/server/utils/agents/aibitat/utils/lexiconMemoryStore.js
COPY docker/anythingllm/patches/listResourceRules.js \
     /app/server/utils/agents/aibitat/utils/listResourceRules.js
COPY docker/anythingllm/patches/resourceReadRouter.js \
     /app/server/utils/agents/aibitat/utils/resourceReadRouter.js
COPY docker/anythingllm/patches/fixtures/wp-create-lexicon.json \
     /app/server/utils/agents/aibitat/utils/fixtures/wp-create-lexicon.json
COPY docker/anythingllm/patches/fixtures/user-create-lexicon.json \
     /app/server/utils/agents/aibitat/utils/fixtures/user-create-lexicon.json
COPY docker/anythingllm/patches/lexiconRouter.js \
     /app/server/utils/agents/aibitat/utils/lexiconRouter.js
COPY docker/anythingllm/patches/chunkStops.js \
     /app/server/utils/agents/aibitat/utils/chunkStops.js
COPY docker/anythingllm/patches/lexiconLearn.js \
     /app/server/utils/agents/aibitat/utils/lexiconLearn.js
COPY docker/anythingllm/patches/lexiconPaths.js \
     /app/server/utils/agents/aibitat/utils/lexiconPaths.js
COPY docker/anythingllm/patches/lexiconStoreIO.js \
     /app/server/utils/agents/aibitat/utils/lexiconStoreIO.js
COPY docker/anythingllm/patches/lemmaClient.js \
     /app/server/utils/agents/aibitat/utils/lemmaClient.js
COPY docker/anythingllm/patches/agentOpsClient.js \
     /app/server/utils/agents/aibitat/utils/agentOpsClient.js
COPY docker/anythingllm/patches/agentOpsPrefsInject.js \
     /app/server/utils/agents/aibitat/utils/agentOpsPrefsInject.js
COPY docker/anythingllm/patches/userLearningGoalInject.js \
     /app/server/utils/agents/aibitat/utils/userLearningGoalInject.js
COPY docker/anythingllm/patches/pageContextInject.js \
     /app/server/utils/agents/aibitat/utils/pageContextInject.js
COPY docker/anythingllm/page-context/registry.json \
     /app/config/page-context/registry.json
COPY docker/anythingllm/patches/agentOpsResp.js \
     /app/server/utils/agents/aibitat/utils/agentOpsResp.js
COPY docker/anythingllm/patches/agentOpsClassify.js \
     /app/server/utils/agents/aibitat/utils/agentOpsClassify.js
COPY docker/anythingllm/patches/agentOpsFeedbackWorker.js \
     /app/server/utils/agents/aibitat/utils/agentOpsFeedbackWorker.js
COPY docker/anythingllm/patches/chatFeedbackExtend.js \
     /app/server/utils/agents/aibitat/utils/chatFeedbackExtend.js
COPY docker/anythingllm/patches/dateNormalize.js \
     /app/server/utils/agents/aibitat/utils/dateNormalize.js
COPY docker/anythingllm/patches/executionPlan.js \
     /app/server/utils/agents/aibitat/utils/executionPlan.js
COPY docker/anythingllm/patches/runbookRunner.js \
     /app/server/utils/agents/aibitat/utils/runbookRunner.js
COPY docker/anythingllm/patches/runbooks/ \
     /app/server/utils/agents/aibitat/utils/runbooks/
COPY docker/anythingllm/patches/lexiconUnlearn.js \
     /app/server/utils/agents/aibitat/utils/lexiconUnlearn.js
COPY docker/anythingllm/patches/lexiconHandoff.js \
     /app/server/utils/agents/aibitat/utils/lexiconHandoff.js
COPY docker/anythingllm/patches/planLoop.js \
     /app/server/utils/agents/aibitat/utils/planLoop.js
COPY docker/anythingllm/patches/opWriteConfirm.js \
     /app/server/utils/agents/aibitat/utils/opWriteConfirm.js
COPY docker/anythingllm/patches/opUserToken.js \
     /app/server/utils/agents/aibitat/utils/opUserToken.js
COPY docker/anythingllm/patches/factSource.js \
     /app/server/utils/agents/aibitat/utils/factSource.js
COPY docker/anythingllm/patches/statusReportBaseline.js \
     /app/server/utils/agents/aibitat/utils/statusReportBaseline.js
COPY docker/anythingllm/patches/statusPack.js \
     /app/server/utils/agents/aibitat/utils/statusPack.js
COPY docker/anythingllm/patches/budgetVariance.js \
     /app/server/utils/agents/aibitat/utils/budgetVariance.js
COPY docker/anythingllm/patches/fireflyProjectBudgetMap.js \
     /app/server/utils/agents/aibitat/utils/fireflyProjectBudgetMap.js
COPY docker/anythingllm/patches/stateInference.js \
     /app/server/utils/agents/aibitat/utils/stateInference.js
COPY docker/anythingllm/patches/apiTermBridge.js \
     /app/server/utils/agents/aibitat/utils/apiTermBridge.js
COPY docker/anythingllm/patches/domainOntology.js \
     /app/server/utils/agents/aibitat/utils/domainOntology.js
COPY docker/anythingllm/patches/otLookup.js \
     /app/server/utils/agents/aibitat/utils/otLookup.js
COPY docker/anythingllm/patches/omlxEnsureLoaded.js \
     /app/server/utils/agents/aibitat/utils/omlxEnsureLoaded.js
COPY docker/anythingllm/patches/otSuggest.js \
     /app/server/utils/agents/aibitat/utils/otSuggest.js
COPY docker/anythingllm/patches/wikiOtRewrite.js \
     /app/server/utils/agents/aibitat/utils/wikiOtRewrite.js
COPY docker/anythingllm/patches/lexiconDebugThoughts.js \
     /app/server/utils/agents/aibitat/utils/lexiconDebugThoughts.js
COPY docker/anythingllm/patches/listResourceSynonyms.json \
     /app/server/utils/agents/aibitat/utils/listResourceSynonyms.json
COPY docker/anythingllm/patches/lexicon/ \
     /app/server/utils/agents/aibitat/utils/lexicon/
COPY docker/anythingllm/patches/aibitat-index.js \
     /app/server/utils/agents/aibitat/index.js
COPY docker/anythingllm/patches/omlxAgentCompletionExtras.js \
     /app/server/utils/agents/aibitat/providers/helpers/omlxAgentCompletionExtras.js
COPY docker/anythingllm/patches/omlxToolPayloadSlim.js \
     /app/server/utils/agents/aibitat/providers/helpers/omlxToolPayloadSlim.js
COPY docker/anythingllm/patches/tooled.js \
     /app/server/utils/agents/aibitat/providers/helpers/tooled.js
RUN chown anythingllm:anythingllm \
      /app/server/utils/agents/aibitat/utils/toolReranker.js \
      /app/server/utils/agents/aibitat/utils/skillRouter.js \
      /app/server/utils/agents/aibitat/utils/glinerFirstRouter.js \
      /app/server/utils/agents/aibitat/utils/projectLexicon.js \
      /app/server/utils/agents/aibitat/utils/lexiconMemoryStore.js \
      /app/server/utils/agents/aibitat/utils/listResourceRules.js \
      /app/server/utils/agents/aibitat/utils/resourceReadRouter.js \
      /app/server/utils/agents/aibitat/utils/listResourceSynonyms.json \
      /app/server/utils/agents/aibitat/utils/fixtures/wp-create-lexicon.json \
      /app/server/utils/agents/aibitat/utils/fixtures/user-create-lexicon.json \
      /app/server/utils/agents/aibitat/utils/lexiconRouter.js \
      /app/server/utils/agents/aibitat/utils/chunkStops.js \
      /app/server/utils/agents/aibitat/utils/lexiconLearn.js \
      /app/server/utils/agents/aibitat/utils/lexiconPaths.js \
      /app/server/utils/agents/aibitat/utils/lexiconStoreIO.js \
      /app/server/utils/agents/aibitat/utils/lemmaClient.js \
      /app/server/utils/agents/aibitat/utils/agentOpsClient.js \
      /app/server/utils/agents/aibitat/utils/agentOpsResp.js \
      /app/server/utils/agents/aibitat/utils/agentOpsClassify.js \
      /app/server/utils/agents/aibitat/utils/agentOpsFeedbackWorker.js \
      /app/server/utils/agents/aibitat/utils/chatFeedbackExtend.js \
      /app/server/utils/agents/aibitat/utils/dateNormalize.js \
      /app/server/utils/agents/aibitat/utils/executionPlan.js \
      /app/server/utils/agents/aibitat/utils/runbookRunner.js \
      /app/server/utils/agents/aibitat/utils/lexiconUnlearn.js \
      /app/server/utils/agents/aibitat/utils/lexiconHandoff.js \
      /app/server/utils/agents/aibitat/utils/planLoop.js \
      /app/server/utils/agents/aibitat/utils/opWriteConfirm.js \
      /app/server/utils/agents/aibitat/utils/opUserToken.js \
      /app/server/utils/agents/aibitat/utils/factSource.js \
      /app/server/utils/agents/aibitat/utils/statusReportBaseline.js \
      /app/server/utils/agents/aibitat/utils/statusPack.js \
      /app/server/utils/agents/aibitat/utils/budgetVariance.js \
      /app/server/utils/agents/aibitat/utils/fireflyProjectBudgetMap.js \
      /app/server/utils/agents/aibitat/utils/stateInference.js \
      /app/server/utils/agents/aibitat/utils/apiTermBridge.js \
      /app/server/utils/agents/aibitat/utils/domainOntology.js \
      /app/server/utils/agents/aibitat/utils/otLookup.js \
      /app/server/utils/agents/aibitat/utils/omlxEnsureLoaded.js \
      /app/server/utils/agents/aibitat/utils/otSuggest.js \
      /app/server/utils/agents/aibitat/utils/wikiOtRewrite.js \
      /app/server/utils/agents/aibitat/utils/lexiconDebugThoughts.js \
      /app/server/utils/agents/aibitat/index.js \
 && chown -R anythingllm:anythingllm /app/server/utils/agents/aibitat/utils/lexicon

# Controlled learning: extend chat-feedback API + 👍/👎 UI dialogs (fragile bundle patch)
COPY docker/anythingllm/patches/agentOpsFeedbackDialog.js \
     /app/server/public/agent-ops-feedback-dialog.js
COPY docker/anythingllm/patches/apply-chat-feedback-patches.sh \
     /tmp/apply-chat-feedback-patches.sh
RUN chmod +x /tmp/apply-chat-feedback-patches.sh \
 && /tmp/apply-chat-feedback-patches.sh /app \
 && chown anythingllm:anythingllm /app/server/public/agent-ops-feedback-dialog.js \
 && rm -f /tmp/apply-chat-feedback-patches.sh


# Skill-View (OP #480) — read-only catalog API + minimal DE UI
COPY docker/anythingllm/patches/skillViewCatalog.js \
     /app/server/utils/agents/aibitat/utils/skillViewCatalog.js
COPY docker/anythingllm/patches/skillViewEndpoints.js \
     /app/server/endpoints/skillView.js
COPY docker/anythingllm/patches/skill-view.html \
     /app/server/public/skill-view.html
COPY docker/anythingllm/patches/skillProfileMerge.js \
     /app/server/utils/agents/aibitat/utils/skillProfileMerge.js
COPY docker/anythingllm/patches/skillProfileStore.js \
     /app/server/utils/agents/aibitat/utils/skillProfileStore.js
COPY docker/anythingllm/patches/skillProfileEndpoints.js \
     /app/server/endpoints/skillProfile.js
COPY docker/anythingllm/patches/skill-profiles.html \
     /app/server/public/skill-profiles.html
COPY docker/anythingllm/patches/userRunbookValidate.js \
     /app/server/utils/agents/aibitat/utils/userRunbookValidate.js
COPY docker/anythingllm/patches/userRunbookExecutor.js \
     /app/server/utils/agents/aibitat/utils/userRunbookExecutor.js
COPY docker/anythingllm/patches/userRunbookStore.js \
     /app/server/utils/agents/aibitat/utils/userRunbookStore.js
COPY docker/anythingllm/patches/userRunbookEndpoints.js \
     /app/server/endpoints/userRunbook.js
COPY docker/anythingllm/patches/skill-runbooks.html \
     /app/server/public/skill-runbooks.html
COPY docker/anythingllm/patches/apply-skill-view-patches.sh \
     /tmp/apply-skill-view-patches.sh
COPY docker/anythingllm/patches/wire-skill-view-index.sh \
     /tmp/wire-skill-view-index.sh
RUN chmod +x /tmp/apply-skill-view-patches.sh /tmp/wire-skill-view-index.sh \
 && /tmp/apply-skill-view-patches.sh /app \
 && /tmp/wire-skill-view-index.sh /app \
 && chown anythingllm:anythingllm \
      /app/server/utils/agents/aibitat/utils/skillViewCatalog.js \
      /app/server/endpoints/skillView.js \
      /app/server/public/skill-view.html \
      /app/server/utils/agents/aibitat/utils/skillProfileMerge.js \
      /app/server/utils/agents/aibitat/utils/skillProfileStore.js \
      /app/server/endpoints/skillProfile.js \
      /app/server/public/skill-profiles.html \
      /app/server/utils/agents/aibitat/utils/userRunbookValidate.js \
      /app/server/utils/agents/aibitat/utils/userRunbookExecutor.js \
      /app/server/utils/agents/aibitat/utils/userRunbookStore.js \
      /app/server/endpoints/userRunbook.js \
      /app/server/public/skill-runbooks.html \
      /app/server/index.js \
 && rm -f /tmp/apply-skill-view-patches.sh /tmp/wire-skill-view-index.sh

USER anythingllm

# OP #498 — user learning goals (skill-view family)
COPY docker/anythingllm/patches/userLearningGoalStore.js \
     /app/server/utils/agents/aibitat/utils/userLearningGoalStore.js
COPY docker/anythingllm/patches/userLearningGoalEndpoints.js \
     /app/server/utils/agents/aibitat/utils/userLearningGoalEndpoints.js
COPY docker/anythingllm/patches/skillViewAuth.js \
     /app/server/utils/agents/aibitat/utils/skillViewAuth.js
COPY docker/anythingllm/patches/learning-goals.html \
     /app/server/public/learning-goals.html
COPY docker/anythingllm/patches/userLearningGoal.js \
     /app/server/endpoints/userLearningGoal.js
COPY docker/anythingllm/patches/apply-skill-view-patches.sh \
     /tmp/apply-skill-view-patches.sh
COPY docker/anythingllm/patches/wire-skill-view-index.sh \
     /tmp/wire-skill-view-index.sh
USER root
RUN chmod +x /tmp/apply-skill-view-patches.sh /tmp/wire-skill-view-index.sh \
 && /tmp/apply-skill-view-patches.sh /app \
 && /tmp/wire-skill-view-index.sh /app \
 && chown anythingllm:anythingllm \
      /app/server/utils/agents/aibitat/utils/userLearningGoalStore.js \
      /app/server/utils/agents/aibitat/utils/userLearningGoalEndpoints.js \
      /app/server/utils/agents/aibitat/utils/skillViewAuth.js \
      /app/server/public/learning-goals.html \
      /app/server/endpoints/userLearningGoal.js \
      /app/server/index.js \
 && rm -f /tmp/apply-skill-view-patches.sh /tmp/wire-skill-view-index.sh
USER anythingllm

