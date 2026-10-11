# Fresh Upstream Test Diff Audit

Snapshot date: 2026-10-11

Baseline: `vercel/ai@15f1a4d0531ac641a4a4d9cc602c0536c1906834`.
Current: `vercel/ai@ba05943b69ad070558bb5bc912da99ec66d7d263`.
The inventory has 1,024 executable test/spec files in 84 groups, up from 976.
This diff has **190 executable paths and 18 declaration-test paths**. Published old/latest npm tarballs control the behavior baseline; monorepo-only subcases are excluded even when the same file also has ported published fixtures. Declaration tests are reviewed but never counted as executed Swift tests.

```sh
git diff --name-status 15f1a4d0531ac641a4a4d9cc602c0536c1906834..ba05943b69ad070558bb5bc912da99ec66d7d263 -- packages examples
```

Each row records one added/changed/deleted/renamed destination path. Source/fixture decisions are expanded in `Docs/UpstreamPackageDiffAudit.md`. Full `swift test` gates all retained native tests.

| Change | Upstream path | Disposition | Swift evidence / boundary |
| --- | --- | --- | --- |
| `M` | `packages/ai/src/agent/create-agent-ui-stream-response.test.ts` | `ported; deferred step/wire subcases` | WeeklyUI20261011 and native validation/conversion/session/reducer suites; explicit UI steps/browser wire state and unpublished reconnect helper are excluded. |
| `A` | `packages/ai/src/agent/create-agent-ui-stream.test-d.ts` | `declaration-review` | TypeScript type/export assertions; native public overloads and generated symbol docs reviewed separately. |
| `M` | `packages/ai/src/agent/create-agent-ui-stream.test.ts` | `ported; deferred step/wire subcases` | WeeklyUI20261011 and native validation/conversion/session/reducer suites; explicit UI steps/browser wire state and unpublished reconnect helper are excluded. |
| `A` | `packages/ai/src/agent/default-stop-condition.test.ts` | `ported or covered` | WeeklyCore20261011 / WeeklyRemainingProviders20261011 plus retained core tests; value/protocol/interface-only refactors need no duplicated native behavior. |
| `A` | `packages/ai/src/agent/pipe-agent-ui-stream-to-response.test.ts` | `out-of-scope` | Browser HTTP/WebSocket/Node response or tracing adapter absent from the native public surface. |
| `A` | `packages/ai/src/decide/decide.test-d.ts` | `declaration-review` | TypeScript type/export assertions; native public overloads and generated symbol docs reviewed separately. |
| `R051` | `packages/ai/src/decide/decide.test.ts` | `ported` | Decision/Evaluation focused suites, media/strict-answer/refusal/registry/telemetry fixtures. |
| `A` | `packages/ai/src/decide/deprecated-aliases.test.ts` | `ported` | Decision/Evaluation focused suites, media/strict-answer/refusal/registry/telemetry fixtures. |
| `A` | `packages/ai/src/decide/openai-decisions.test.ts` | `ported` | Decision/Evaluation focused suites, media/strict-answer/refusal/registry/telemetry fixtures. |
| `A` | `packages/ai/src/embed/embed-dimensions.test.ts` | `ported or covered` | WeeklyCore20261011 / WeeklyRemainingProviders20261011 plus retained core tests; value/protocol/interface-only refactors need no duplicated native behavior. |
| `A` | `packages/ai/src/error/decision-refusal-error.test.ts` | `ported` | Decision/Evaluation focused suites, media/strict-answer/refusal/registry/telemetry fixtures. |
| `R054` | `packages/ai/src/error/decision-unsupported-question-type-error.test.ts` | `ported` | Decision/Evaluation focused suites, media/strict-answer/refusal/registry/telemetry fixtures. |
| `D` | `packages/ai/src/evaluate/evaluate.test-d.ts` | `declaration-review` | TypeScript type/export assertions; native public overloads and generated symbol docs reviewed separately. |
| `M` | `packages/ai/src/generate-object/generate-object.test.ts` | `ported or covered` | WeeklyCore20261011 / WeeklyRemainingProviders20261011 plus retained core tests; value/protocol/interface-only refactors need no duplicated native behavior. |
| `M` | `packages/ai/src/generate-object/stream-object.test.ts` | `ported or covered` | WeeklyCore20261011 / WeeklyRemainingProviders20261011 plus retained core tests; value/protocol/interface-only refactors need no duplicated native behavior. |
| `A` | `packages/ai/src/generate-text/citations.test-d.ts` | `declaration-review` | TypeScript type/export assertions; native public overloads and generated symbol docs reviewed separately. |
| `A` | `packages/ai/src/generate-text/citations.test.ts` | `unpublished` | Monorepo citation surface is ahead of ai@7.0.137; published source/declarations remain the baseline. |
| `M` | `packages/ai/src/generate-text/generate-text.test-d.ts` | `declaration-review` | TypeScript type/export assertions; native public overloads and generated symbol docs reviewed separately. |
| `M` | `packages/ai/src/generate-text/stream-text-timeout.test.ts` | `ported or covered` | WeeklyCore20261011 / WeeklyRemainingProviders20261011 plus retained core tests; value/protocol/interface-only refactors need no duplicated native behavior. |
| `M` | `packages/ai/src/generate-text/stream-text.test-d.ts` | `declaration-review` | TypeScript type/export assertions; native public overloads and generated symbol docs reviewed separately. |
| `M` | `packages/ai/src/generate-text/stream-text.test.ts` | `ported or covered` | WeeklyCore20261011 / WeeklyRemainingProviders20261011 plus retained core tests; value/protocol/interface-only refactors need no duplicated native behavior. |
| `A` | `packages/ai/src/generate-text/tool-approval-follow-up.test.ts` | `ported or covered` | WeeklyCore20261011 / WeeklyRemainingProviders20261011 plus retained core tests; value/protocol/interface-only refactors need no duplicated native behavior. |
| `A` | `packages/ai/src/global.test.ts` | `ported or covered` | WeeklyCore20261011 / WeeklyRemainingProviders20261011 plus retained core tests; value/protocol/interface-only refactors need no duplicated native behavior. |
| `A` | `packages/ai/src/logger/deprecations.test.ts` | `ported or covered` | WeeklyCore20261011 / WeeklyRemainingProviders20261011 plus retained core tests; value/protocol/interface-only refactors need no duplicated native behavior. |
| `A` | `packages/ai/src/logger/log-warnings.node.test.ts` | `out-of-scope` | Browser HTTP/WebSocket/Node response or tracing adapter absent from the native public surface. |
| `M` | `packages/ai/src/logger/log-warnings.test.ts` | `ported or covered` | WeeklyCore20261011 / WeeklyRemainingProviders20261011 plus retained core tests; value/protocol/interface-only refactors need no duplicated native behavior. |
| `M` | `packages/ai/src/model/as-language-model-v3.test.ts` | `ported or covered` | WeeklyCore20261011 / WeeklyRemainingProviders20261011 plus retained core tests; value/protocol/interface-only refactors need no duplicated native behavior. |
| `M` | `packages/ai/src/prompt/convert-to-language-model-prompt.test.ts` | `ported or covered` | WeeklyCore20261011 / WeeklyRemainingProviders20261011 plus retained core tests; value/protocol/interface-only refactors need no duplicated native behavior. |
| `M` | `packages/ai/src/prompt/convert-to-language-model-prompt.validation.test.ts` | `ported or covered` | WeeklyCore20261011 / WeeklyRemainingProviders20261011 plus retained core tests; value/protocol/interface-only refactors need no duplicated native behavior. |
| `M` | `packages/ai/src/prompt/prepare-language-model-call-options.test.ts` | `ported or covered` | WeeklyCore20261011 / WeeklyRemainingProviders20261011 plus retained core tests; value/protocol/interface-only refactors need no duplicated native behavior. |
| `R058` | `packages/ai/src/registry/decision-model.test-d.ts` | `declaration-review` | TypeScript type/export assertions; native public overloads and generated symbol docs reviewed separately. |
| `R055` | `packages/ai/src/registry/decision-model.test.ts` | `ported` | Decision/Evaluation focused suites, media/strict-answer/refusal/registry/telemetry fixtures. |
| `M` | `packages/ai/src/telemetry/create-telemetry-dispatcher.test.ts` | `ported or covered` | WeeklyCore20261011 / WeeklyRemainingProviders20261011 plus retained core tests; value/protocol/interface-only refactors need no duplicated native behavior. |
| `M` | `packages/ai/src/telemetry/tracing-channel.test.ts` | `out-of-scope` | Browser HTTP/WebSocket/Node response or tracing adapter absent from the native public surface. |
| `M` | `packages/ai/src/transcribe/transcribe.test.ts` | `ported or covered` | WeeklyCore20261011 / WeeklyRemainingProviders20261011 plus retained core tests; value/protocol/interface-only refactors need no duplicated native behavior. |
| `A` | `packages/ai/src/types/usage.test.ts` | `ported or covered` | WeeklyCore20261011 / WeeklyRemainingProviders20261011 plus retained core tests; value/protocol/interface-only refactors need no duplicated native behavior. |
| `M` | `packages/ai/src/ui-message-stream/read-ui-message-stream.test.ts` | `ported; deferred step/wire subcases` | WeeklyUI20261011 and native validation/conversion/session/reducer suites; explicit UI steps/browser wire state and unpublished reconnect helper are excluded. |
| `M` | `packages/ai/src/ui-message-stream/to-ui-message-stream.test.ts` | `ported; deferred step/wire subcases` | WeeklyUI20261011 and native validation/conversion/session/reducer suites; explicit UI steps/browser wire state and unpublished reconnect helper are excluded. |
| `M` | `packages/ai/src/ui/chat.test.ts` | `ported; deferred step/wire subcases` | WeeklyUI20261011 and native validation/conversion/session/reducer suites; explicit UI steps/browser wire state and unpublished reconnect helper are excluded. |
| `M` | `packages/ai/src/ui/convert-to-model-messages.test.ts` | `ported; deferred step/wire subcases` | WeeklyUI20261011 and native validation/conversion/session/reducer suites; explicit UI steps/browser wire state and unpublished reconnect helper are excluded. |
| `M` | `packages/ai/src/ui/direct-chat-transport.test.ts` | `ported; deferred step/wire subcases` | WeeklyUI20261011 and native validation/conversion/session/reducer suites; explicit UI steps/browser wire state and unpublished reconnect helper are excluded. |
| `M` | `packages/ai/src/ui/http-chat-transport.test.ts` | `out-of-scope` | Browser HTTP/WebSocket/Node response or tracing adapter absent from the native public surface. |
| `M` | `packages/ai/src/ui/process-ui-message-stream.test.ts` | `ported; deferred step/wire subcases` | WeeklyUI20261011 and native validation/conversion/session/reducer suites; explicit UI steps/browser wire state and unpublished reconnect helper are excluded. |
| `M` | `packages/ai/src/ui/validate-ui-messages.test.ts` | `ported; deferred step/wire subcases` | WeeklyUI20261011 and native validation/conversion/session/reducer suites; explicit UI steps/browser wire state and unpublished reconnect helper are excluded. |
| `A` | `packages/ai/src/ui/websocket-chat-transport.test-d.ts` | `declaration-review` | TypeScript type/export assertions; native public overloads and generated symbol docs reviewed separately. |
| `A` | `packages/ai/src/ui/websocket-chat-transport.test.ts` | `out-of-scope` | Browser HTTP/WebSocket/Node response or tracing adapter absent from the native public surface. |
| `M` | `packages/ai/src/util/serial-job-executor.test.ts` | `ported or covered` | WeeklyCore20261011 / WeeklyRemainingProviders20261011 plus retained core tests; value/protocol/interface-only refactors need no duplicated native behavior. |
| `M` | `packages/alibaba/src/alibaba-embedding-model.test.ts` | `ported or covered` | WeeklyRemainingProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/alibaba/src/alibaba-video-model.test.ts` | `ported or covered` | WeeklyRemainingProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `A` | `packages/amazon-bedrock/src/amazon-bedrock-anthropic-model-support.test.ts` | `ported or covered` | WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/amazon-bedrock/src/amazon-bedrock-chat-language-model.test.ts` | `ported or covered` | WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/amazon-bedrock/src/amazon-bedrock-embedding-model.test.ts` | `ported or covered` | WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/amazon-bedrock/src/amazon-bedrock-prepare-tools.test.ts` | `ported or covered` | WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/amazon-bedrock/src/amazon-bedrock-sigv4-fetch.test.ts` | `ported or covered` | WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/amazon-bedrock/src/anthropic/amazon-bedrock-anthropic-provider.test.ts` | `ported or covered` | WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/anthropic-aws/src/anthropic-aws-fetch.test.ts` | `ported or covered` | WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/anthropic/src/anthropic-batch.test.ts` | `ported or covered` | WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `R080` | `packages/anthropic/src/anthropic-decision.test.ts` | `ported or covered` | WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/anthropic/src/anthropic-language-model.test.ts` | `ported or covered` | WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/anthropic/src/anthropic-prepare-tools.test.ts` | `ported or covered` | WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/anthropic/src/anthropic-provider.test-d.ts` | `declaration-review` | TypeScript type/export assertions; native public overloads and generated symbol docs reviewed separately. |
| `M` | `packages/anthropic/src/convert-to-anthropic-prompt.test.ts` | `ported or covered` | WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `A` | `packages/azure/src/azure-mai-image-generate-image.test.ts` | `ported or covered` | WeeklyAzure20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `A` | `packages/azure/src/azure-mai-image-model.test.ts` | `ported or covered` | WeeklyAzure20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/azure/src/azure-openai-provider.test.ts` | `ported or covered` | WeeklyAzure20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/black-forest-labs/src/black-forest-labs-image-model.test.ts` | `ported or covered` | WeeklyBFLXAI20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/cartesia/src/cartesia-transcription-model.test.ts` | `covered` | Existing Cartesia Data/transport regressions; published ArrayBuffer generic cast is type-only. |
| `M` | `packages/cohere/src/cohere-chat-language-model.test.ts` | `ported or covered` | WeeklyProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/cohere/src/cohere-embedding-model.test.ts` | `ported or covered` | WeeklyProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/deepseek/src/chat/convert-to-deepseek-chat-messages.test.ts` | `ported or covered` | WeeklyRemainingProviders20261011 / shared Data coverage; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/deepseek/src/chat/deepseek-chat-language-model.test.ts` | `ported or covered` | WeeklyRemainingProviders20261011 / shared Data coverage; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/deepseek/src/chat/is-deepseek-v4-model.test.ts` | `ported or covered` | WeeklyRemainingProviders20261011 / shared Data coverage; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/elevenlabs/src/elevenlabs-transcription-model.test.ts` | `ported or covered` | WeeklyRemainingProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `A` | `packages/fireworks/src/fireworks-chat-language-model.test.ts` | `ported or covered` | WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/fireworks/src/fireworks-provider.test.ts` | `ported or covered` | WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `A` | `packages/gateway/scripts/generate-model-settings.test.ts` | `ported or covered` | DecisionProviderTests / WeeklyRemainingProviders20261011 / existing Gateway batch tests; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/gateway/src/gateway-batch.test.ts` | `ported or covered` | DecisionProviderTests / WeeklyRemainingProviders20261011 / existing Gateway batch tests; published package behavior only, monorepo-ahead subcases excluded. |
| `R063` | `packages/gateway/src/gateway-decision-model.test.ts` | `ported or covered` | DecisionProviderTests / WeeklyRemainingProviders20261011 / existing Gateway batch tests; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/gateway/src/gateway-embedding-model.test.ts` | `ported or covered` | DecisionProviderTests / WeeklyRemainingProviders20261011 / existing Gateway batch tests; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/gateway/src/gateway-fetch-metadata.test.ts` | `ported or covered` | DecisionProviderTests / WeeklyRemainingProviders20261011 / existing Gateway batch tests; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/gateway/src/gateway-provider-options.test-d.ts` | `declaration-review` | TypeScript type/export assertions; native public overloads and generated symbol docs reviewed separately. |
| `M` | `packages/gateway/src/gateway-provider-options.test.ts` | `ported or covered` | DecisionProviderTests / WeeklyRemainingProviders20261011 / existing Gateway batch tests; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/gateway/src/gateway-provider.test-d.ts` | `declaration-review` | TypeScript type/export assertions; native public overloads and generated symbol docs reviewed separately. |
| `M` | `packages/gateway/src/gateway-transcription-model.test.ts` | `ported or covered` | DecisionProviderTests / WeeklyRemainingProviders20261011 / existing Gateway batch tests; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/google-vertex/src/google-vertex-embedding-model.test.ts` | `ported or covered` | WeeklyGoogle20261011 / existing GoogleVertexTests; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/google-vertex/src/google-vertex-image-model.test.ts` | `ported or covered` | WeeklyGoogle20261011 / existing GoogleVertexTests; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/google-vertex/src/google-vertex-language-model.test.ts` | `ported or covered` | WeeklyGoogle20261011 / existing GoogleVertexTests; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/google/src/convert-to-google-messages.test.ts` | `ported or covered` | WeeklyGoogle20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/google/src/google-batch.test.ts` | `ported or covered` | WeeklyGoogle20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `R079` | `packages/google/src/google-decision.test.ts` | `ported or covered` | WeeklyGoogle20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/google/src/google-embedding-model.test.ts` | `ported or covered` | WeeklyGoogle20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/google/src/google-image-model.test.ts` | `ported or covered` | WeeklyGoogle20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/google/src/google-language-model.test.ts` | `ported or covered` | WeeklyGoogle20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/google/src/google-model-capabilities.test.ts` | `ported or covered` | WeeklyGoogle20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/google/src/google-provider-metadata.test-d.ts` | `declaration-review` | TypeScript type/export assertions; native public overloads and generated symbol docs reviewed separately. |
| `A` | `packages/google/src/structured-output-with-tools.test.ts` | `ported or covered` | WeeklyGoogle20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/groq/src/groq-chat-language-model.test.ts` | `ported or covered` | WeeklyProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/groq/src/groq-prepare-tools.test.ts` | `ported or covered` | WeeklyProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `A` | `packages/groq/src/structured-output-with-tools.test.ts` | `ported or covered` | WeeklyProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/harness-acp/src/acp-harness.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `A` | `packages/harness-acp/src/v1/bridge/create-emit-stream-event.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-acp/src/v1/bridge/host-tool-correlation.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-acp/src/v1/bridge/host-tool-relay-authorization.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `A` | `packages/harness-acp/src/v1/bridge/merge-observed-tool-call.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-acp/src/v1/bridge/permission-controller.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `A` | `packages/harness-acp/src/v1/bridge/resolve-host-tool-call.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-claude-code/src/bridge/create-emit-stream-event.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-claude-code/src/bridge/index.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `A` | `packages/harness-claude-code/src/bridge/task-notification-result.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-claude-code/src/bridge/tool-filtering.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-claude-code/src/claude-code-harness.test-d.ts` | `declaration-review` | TypeScript type/export assertions; native public overloads and generated symbol docs reviewed separately. |
| `M` | `packages/harness-claude-code/src/claude-code-harness.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-codex/src/bridge/create-app-server-event-handler.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-codex/src/bridge/create-emit-stream-event.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-deepagents/src/bridge/create-emit-stream-event.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-deepagents/src/bridge/index.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `A` | `packages/harness-deepagents/src/bridge/mcp-tool-errors.integration.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `A` | `packages/harness-deepagents/src/bridge/mcp-tool-errors.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-fx/src/fx-harness.test-d.ts` | `declaration-review` | TypeScript type/export assertions; native public overloads and generated symbol docs reviewed separately. |
| `M` | `packages/harness-fx/src/fx-harness.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-github-copilot/src/github-copilot-harness.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-grok-build/src/grok-build-harness.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-opencode/src/bridge/create-emit-stream-event.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `A` | `packages/harness-opencode/src/bridge/host-tool-schemas.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-opencode/src/bridge/index.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-opencode/src/opencode-harness.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-pi/src/pi-harness.test-d.ts` | `declaration-review` | TypeScript type/export assertions; native public overloads and generated symbol docs reviewed separately. |
| `M` | `packages/harness-pi/src/pi-model-resolver.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-pi/src/pi-paths.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-pi/src/pi-remote-ops.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-pi/src/pi-session.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-pi/src/pi-translate.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness-pi/src/pi-workspace-mirror.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness/src/agent/harness-agent.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness/src/agent/internal/run-prompt.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness/src/agent/internal/validate-tool-call.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness/src/agent/telemetry-integration.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/harness/src/v1/harness-v1-stream-part.test-d.ts` | `declaration-review` | TypeScript type/export assertions; native public overloads and generated symbol docs reviewed separately. |
| `A` | `packages/heygen/src/heygen-provider.test.ts` | `announced` | New provider deliberately unimplemented; dedicated native async-video vertical proposed in package audit. |
| `A` | `packages/heygen/src/heygen-video-model.test.ts` | `announced` | New provider deliberately unimplemented; dedicated native async-video vertical proposed in package audit. |
| `M` | `packages/mcp/src/index.test-d.ts` | `declaration-review` | TypeScript type/export assertions; native public overloads and generated symbol docs reviewed separately. |
| `M` | `packages/mcp/src/tool/mcp-client.test.ts` | `ported` | WeeklyMCPEvents20261011 / WeeklyMCPCore20261011 / MCPOAuthFlowTests; deprecated EventSource adapter absent. |
| `A` | `packages/mcp/src/tool/mcp-event-webhook.test.ts` | `ported` | WeeklyMCPEvents20261011 / WeeklyMCPCore20261011 / MCPOAuthFlowTests; deprecated EventSource adapter absent. |
| `A` | `packages/mcp/src/tool/mcp-events-adapter-creation.test.ts` | `ported` | WeeklyMCPEvents20261011 / WeeklyMCPCore20261011 / MCPOAuthFlowTests; deprecated EventSource adapter absent. |
| `A` | `packages/mcp/src/tool/mcp-events-adapter.test.ts` | `ported` | WeeklyMCPEvents20261011 / WeeklyMCPCore20261011 / MCPOAuthFlowTests; deprecated EventSource adapter absent. |
| `A` | `packages/mcp/src/tool/mcp-events.test.ts` | `ported` | WeeklyMCPEvents20261011 / WeeklyMCPCore20261011 / MCPOAuthFlowTests; deprecated EventSource adapter absent. |
| `M` | `packages/mcp/src/tool/oauth-credential-invalidation.test.ts` | `ported` | WeeklyMCPEvents20261011 / WeeklyMCPCore20261011 / MCPOAuthFlowTests; deprecated EventSource adapter absent. |
| `M` | `packages/mcp/src/tool/oauth.test.ts` | `ported` | WeeklyMCPEvents20261011 / WeeklyMCPCore20261011 / MCPOAuthFlowTests; deprecated EventSource adapter absent. |
| `A` | `packages/mistral/src/convert-to-mistral-conversation-inputs.test.ts` | `ported or covered` | WeeklyMistral20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/mistral/src/mistral-chat-language-model.test.ts` | `ported or covered` | WeeklyMistral20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `A` | `packages/mistral/src/mistral-conversation-language-model.test.ts` | `ported or covered` | WeeklyMistral20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `A` | `packages/mistral/src/mistral-conversation-prepare-tools.test.ts` | `ported or covered` | WeeklyMistral20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/mistral/src/mistral-embedding-model.test.ts` | `ported or covered` | WeeklyMistral20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/moonshotai/src/moonshotai-chat-language-model.test.ts` | `ported or covered` | WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/moonshotai/src/moonshotai-provider.test.ts` | `ported or covered` | WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/open-responses/src/responses/open-responses-language-model.test.ts` | `ported or covered` | Retained focused native provider suite; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/openai-compatible/src/chat/convert-to-openai-compatible-chat-messages.test.ts` | `ported or covered` | WeeklyOpenAI20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/openai-compatible/src/chat/openai-compatible-chat-language-model.test.ts` | `ported or covered` | WeeklyOpenAI20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/openai-compatible/src/embedding/openai-compatible-embedding-model.test.ts` | `ported or covered` | WeeklyOpenAI20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/openai/src/chat/convert-to-openai-chat-messages.test.ts` | `ported or covered` | DecisionProviderTests / WeeklyOpenAI20261011 / WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/openai/src/embedding/openai-embedding-model.test.ts` | `ported or covered` | DecisionProviderTests / WeeklyOpenAI20261011 / WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/openai/src/openai-batch.test.ts` | `ported or covered` | DecisionProviderTests / WeeklyOpenAI20261011 / WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `A` | `packages/openai/src/openai-decision.test.ts` | `ported or covered` | DecisionProviderTests / WeeklyOpenAI20261011 / WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `D` | `packages/openai/src/openai-evaluation.test.ts` | `ported or covered` | DecisionProviderTests / WeeklyOpenAI20261011 / WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/openai/src/openai-language-model-capabilities.test.ts` | `ported or covered` | DecisionProviderTests / WeeklyOpenAI20261011 / WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/openai/src/responses/convert-to-openai-responses-input.test.ts` | `ported or covered` | DecisionProviderTests / WeeklyOpenAI20261011 / WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/openai/src/responses/openai-responses-language-model.test.ts` | `ported or covered` | DecisionProviderTests / WeeklyOpenAI20261011 / WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/openai/src/responses/openai-responses-reasoning-effort-update.test.ts` | `ported or covered` | DecisionProviderTests / WeeklyOpenAI20261011 / WeeklyMajorProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/otel/src/legacy-open-telemetry.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/otel/src/open-telemetry.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/otel/src/stringify-for-telemetry.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/perplexity/src/perplexity-embedding-model.test.ts` | `ported or covered` | WeeklyRemainingProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/perplexity/src/perplexity-language-model.test.ts` | `ported or covered` | WeeklyRemainingProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `A` | `packages/provider-utils/src/convert-json-response-tool-stream.test.ts` | `ported or Data-covered` | DecisionProviderTests / WeeklyCore20261011 / WeeklyGoogle20261011 / WeeklyProviders20261011; unpublished exact-label schema subcases excluded. |
| `R070` | `packages/provider-utils/src/decision-language-model.test.ts` | `ported or Data-covered` | DecisionProviderTests / WeeklyCore20261011 / WeeklyGoogle20261011 / WeeklyProviders20261011; unpublished exact-label schema subcases excluded. |
| `M` | `packages/provider-utils/src/map-reasoning-to-provider.test.ts` | `ported or Data-covered` | DecisionProviderTests / WeeklyCore20261011 / WeeklyGoogle20261011 / WeeklyProviders20261011; unpublished exact-label schema subcases excluded. |
| `M` | `packages/provider-utils/src/response-handler.test.ts` | `ported or Data-covered` | DecisionProviderTests / WeeklyCore20261011 / WeeklyGoogle20261011 / WeeklyProviders20261011; unpublished exact-label schema subcases excluded. |
| `M` | `packages/provider-utils/src/streaming-tool-call-tracker.test.ts` | `ported or Data-covered` | DecisionProviderTests / WeeklyCore20261011 / WeeklyGoogle20261011 / WeeklyProviders20261011; unpublished exact-label schema subcases excluded. |
| `M` | `packages/react/src/use-chat.ui.test.tsx` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/react/src/use-object.ui.test.tsx` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `R073` | `packages/typesafe-ai/src/typesafe-ai-decision-model.test.ts` | `ported or covered` | DecisionProviderTests / TypesafeAIProviderTests; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/typesafe-ai/src/typesafe-ai-provider.test.ts` | `ported or covered` | DecisionProviderTests / TypesafeAIProviderTests; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/voyage/src/voyage-embedding-model.test.ts` | `ported or covered` | WeeklyRemainingProviders20261011; published package behavior only, monorepo-ahead subcases excluded. |
| `M` | `packages/vue/src/use-chat.ui.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/workflow-harness/src/run-harness-agent-output.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `A` | `packages/workflow/src/do-generate-step.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/workflow/src/do-stream-step.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `R090` | `packages/workflow/src/model-call-iterator.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `A` | `packages/workflow/src/model-call-payload.integration.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/workflow/src/serializable-schema.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `A` | `packages/workflow/src/workflow-agent-approval.integration.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `A` | `packages/workflow/src/workflow-agent-approval.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `A` | `packages/workflow/src/workflow-agent-boundaries.integration.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/workflow/src/workflow-agent-compat.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `A` | `packages/workflow/src/workflow-agent-contract.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/workflow/src/workflow-agent-e2e.integration.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `A` | `packages/workflow/src/workflow-agent-generate.test-d.ts` | `declaration-review` | TypeScript type/export assertions; native public overloads and generated symbol docs reviewed separately. |
| `A` | `packages/workflow/src/workflow-agent-generate.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/workflow/src/workflow-agent-stream-error.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `A` | `packages/workflow/src/workflow-agent-telemetry.integration.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/workflow/src/workflow-agent.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/workflow/src/workflow-chat-transport.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `A` | `packages/workflow/src/workflow-execution-result.test.ts` | `out-of-scope` | Framework/harness/workflow/Node tooling outside the native provider-model contract. |
| `M` | `packages/xai/src/responses/xai-responses-language-model.test.ts` | `ported` | WeeklyBFLXAI20261011 and existing Responses/realtime/files tests; Blob cast covered by Data. |
| `A` | `packages/xai/src/tool/x-search.test.ts` | `ported` | WeeklyBFLXAI20261011 and existing Responses/realtime/files tests; Blob cast covered by Data. |
| `M` | `packages/xai/src/xai-image-model.test.ts` | `ported` | WeeklyBFLXAI20261011 and existing Responses/realtime/files tests; Blob cast covered by Data. |
| `M` | `packages/xai/src/xai-provider.test.ts` | `ported` | WeeklyBFLXAI20261011 and existing Responses/realtime/files tests; Blob cast covered by Data. |
| `M` | `packages/xai/src/xai-transcription-model.test.ts` | `ported` | WeeklyBFLXAI20261011 and existing Responses/realtime/files tests; Blob cast covered by Data. |

## Published versus monorepo boundaries

Anthropic citations/tool-choice-none, later Google capability updates, OpenAI annotations, openai-compatible tool_content/files, Decision exact-choice labels and relaxed rounded maxima, and the native-unimplemented browser reconnect helper are not silently taken from newer checkout tests. Package-specific fixtures for existing native paths remain covered by the full suite. HeyGen fixtures stay announced. TypeScript declaration counts and parameterized Swift invocations are reported separately from test-function totals.
