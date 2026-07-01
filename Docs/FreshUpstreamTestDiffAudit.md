# Fresh Upstream Test Diff Audit

This file tracks changed upstream test files between the checked SwiftAISDK
test inventory baseline and the current weekly-check upstream checkout. It is a
working audit, not a generated inventory.

Snapshot:

- Baseline upstream ref: `vercel/ai@184dc39c2b2cf8cb9302d81f87edcf2f665cfd8c`
- Current upstream ref: `vercel/ai@11ee77873a5f2e783249579d41619ae2db2f026e`
- Diff command:

  ```sh
  git -C /tmp/vercel-ai-tests diff --name-status \
    184dc39c2b2cf8cb9302d81f87edcf2f665cfd8c..11ee77873a5f2e783249579d41619ae2db2f026e \
    -- 'packages/**/**.test.ts' 'packages/**/**.test.tsx'
  ```

Status meanings:

- `ported`: new upstream behavior is covered by Swift tests/runtime.
- `covered`: existing Swift coverage already proves the changed behavior.
- `no-swift-action`: upstream diff does not add portable Swift behavior.
- `out-of-scope`: package/product surface is intentionally not exposed by
  SwiftAISDK per `Docs/AgentPortingGuide.md`.

## 2026-06-30 Diff

| Upstream test file | Status | Swift evidence / rationale |
| --- | --- | --- |
| `packages/ai/src/generate-text/prune-messages.test.ts` | `ported` | `AiPruneMessagesUpstreamTests.swift` covers the selective approval-pruning regression: approval responses are pruned with their request/tool call, and unresolved approval responses do not survive as authority context. |
| `packages/ai/src/generate-video/generate-video.test.ts` | `ported` | `AiGenerateVideoUpstreamTests.swift` covers `frameImages` / `inputReferences` facade semantics, normalization, precedence, and warnings. |
| `packages/ai/src/model/as-video-model-v4.test.ts` | `out-of-scope` | JS V3-to-V4 adapter helper. Swift exposes one current `VideoModel` protocol and has no versioned adapter layer. |
| `packages/ai/src/ui/convert-to-model-messages.test.ts` | `ported` | `AiConvertToModelMessagesUpstreamTests.swift` covers the persistent data-before-model-stream regression: data parts do not emit an empty assistant model message. |
| `packages/alibaba/src/alibaba-video-model.test.ts` | `ported` | `AlibabaProviderLanguageAndVideoTests.swift` covers first/last frame and input-reference serialization/warnings for Alibaba video models. |
| `packages/anthropic/src/anthropic-language-model.test.ts` | `ported` | `AnthropicProviderExecutedCodeExecutionUpstreamParityTests.anthropicStreamedSkillToolCallPreservesTextEditorDiscriminatorLikeUpstream` covers streamed `pptx` skill reads preserving `text_editor_code_execution` after an empty first input delta. |
| `packages/bytedance/src/bytedance-video-model.test.ts` | `ported` | `ByteDanceProviderTests.swift` covers first/last frame and input-reference serialization. |
| `packages/fal/src/fal-video-model.test.ts` | `no-swift-action` | Upstream only adds default option baselines with `frameImages: undefined` / `inputReferences: undefined`; no new serializer behavior exists to port. Existing Fal video tests cover current Swift request behavior. |
| `packages/gateway/src/gateway-video-model.test.ts` | `ported` | `GatewayTests.swift` covers `frameImages` and `inputReferences` request serialization. |
| `packages/google-vertex/src/google-vertex-video-model.test.ts` | `ported` | `GoogleVertexMediaAndMaaSTests.swift` covers first/last frame and reference-image serialization. |
| `packages/google/src/google-video-model.test.ts` | `ported` | `GoogleGenerativeAIVideoAndInteractionsTests.swift` covers first/last frame and reference-image serialization. |
| `packages/harness-codex/src/codex-instructions.test.ts` | `out-of-scope` | Codex harness start-frame/instructions timing is an upstream harness product surface. SwiftAISDK does not expose `@ai-sdk/harness-codex` or its bridge/session protocol. |
| `packages/harness-deepagents/src/deepagents-harness.test.ts` | `out-of-scope` | DeepAgents harness built-in tool/default context-window tests were removed upstream. SwiftAISDK does not expose `@ai-sdk/harness-deepagents`. |
| `packages/klingai/src/klingai-video-model.test.ts` | `ported` | `KlingAIProviderTests.swift` covers first/last frame, multi-image, reference-to-video input references, and unsupported-combination warnings. |
| `packages/moonshotai/src/moonshotai-provider.test.ts` | `ported` | `MoonshotAIProviderUpstreamTests.swift` covers `kimi-k*` structured outputs and top-level `$schema` stripping; legacy Moonshot models still use JSON object mode. |
| `packages/openai/src/chat/openai-chat-language-model.test.ts` | `ported` | `OpenAIChatLanguageModelUpstreamTests.swift` covers Azure content-filter stream chunks with empty `choices` and trailing filter metadata while preserving text deltas. |
| `packages/openai/src/openai-provider.test.ts` | `covered` | `OpenAIResponsesProviderIdentityTests.swift` already covers default language model routing to `/v1/responses` and chat model routing to `/v1/chat/completions`. |
| `packages/openai/src/responses/openai-responses-language-model.test.ts` | `covered` | `OpenAIResponsesStreamingMiscAndErrorsTests.swift` covers Chat Completions stream mismatch errors; existing OpenAI Responses streaming tests cover the fresh citation/phase slices. |
| `packages/prodia/src/prodia-video-model.test.ts` | `no-swift-action` | Upstream only adds default option baselines with `frameImages: undefined` / `inputReferences: undefined`; no new serializer behavior exists to port. Existing Prodia video tests cover current Swift request behavior. |
| `packages/react/src/use-chat.ui.test.tsx` | `out-of-scope` | React hook identity/rerender behavior for `useChat({ id: undefined })` is a framework adapter surface. SwiftAISDK has typed `AIChatSession`, not React hooks. |
| `packages/replicate/src/replicate-video-model.test.ts` | `no-swift-action` | Upstream only adds default option baselines with `frameImages: undefined` / `inputReferences: undefined`; no new serializer behavior exists to port. Existing Replicate video tests cover current Swift request behavior. |
| `packages/workflow/src/workflow-agent-compat.test.ts` | `out-of-scope` | WorkflowAgent reasoning propagation is an upstream `@ai-sdk/workflow` product surface. SwiftAISDK does not expose WorkflowAgent or WorkflowChatTransport. |
| `packages/workflow/src/workflow-agent.test.ts` | `out-of-scope` | Same `@ai-sdk/workflow` product-surface exclusion; generation-setting propagation belongs to WorkflowAgent, not SwiftAISDK's current public API. |
| `packages/workflow/src/workflow-chat-transport.stream-repair.test.ts` | `out-of-scope` | New JS `WorkflowChatTransport` UIMessageChunk repair tests target workflow transport replay/interleaving behavior. SwiftAISDK has no WorkflowChatTransport chunk stream surface. |
| `packages/xai/src/xai-video-model.test.ts` | `ported` | `XAIProviderTests.swift` covers video first-frame editing, input references, unsupported last-frame/reference combinations, and warnings. |

Current result: all changed tracked SwiftAISDK surfaces in this diff are
`ported` or `covered`; remaining changed files are framework/harness/workflow
product surfaces or no-op default baselines.
