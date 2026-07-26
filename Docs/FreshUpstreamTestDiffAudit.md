# Fresh Upstream Test Diff Audit

This file tracks changed upstream test files between the checked SwiftAISDK
test inventory baseline and the current weekly-check upstream checkout. It is a
working audit, not a generated inventory.

Snapshot:

- Date: `2026-07-27`
- Baseline upstream ref: `vercel/ai@6cd7c74acf0d7ec84dd58a841fc0e20970d6f2e8`
- Current upstream ref: `vercel/ai@c8baafc4864bbdc82b90c6c50d8eeb2ef0791d56`
- Diff command:

  ```sh
  git -C /tmp/vercel-ai-upstream-20260727.bjQKnU diff --name-status \
    6cd7c74acf0d7ec84dd58a841fc0e20970d6f2e8..c8baafc4864bbdc82b90c6c50d8eeb2ef0791d56 \
    -- 'packages/**/**.test.ts' 'packages/**/**.test.tsx' \
       'packages/**/**.test-d.ts'
  ```

Status meanings:

- `ported`: new upstream behavior is covered by Swift tests/runtime.
- `covered`: existing Swift coverage already proves the changed behavior.
- `deferred`: portable behavior was audited, but needs a broader public/runtime
  design than this weekly batch.
- `no-swift-action`: upstream diff does not add portable Swift behavior.
- `out-of-scope`: package/product surface is intentionally not exposed by
  SwiftAISDK per `Docs/AgentPortingGuide.md`.

## 2026-07-27 Diff

| Upstream test file(s) | Status | Swift evidence / rationale |
| --- | --- | --- |
| `packages/ai/src/generate-text/tool-approval-signature.test.ts` | `ported` | `ToolPreparation.swift` now uses the versioned injective JSON-array HMAC payload, ECMAScript number/string serialization and UTF-16 key ordering, verifies safe legacy signatures, and closes newline/control-character retupling. `AiToolApprovalSignatureUpstreamTests.swift` carries Node-fixed interoperability vectors plus the upstream collision and compatibility regressions. |
| `packages/ai/src/prompt/convert-to-language-model-prompt.test.ts` | `ported` | `PromptConversion.swift` deep-merges message-level provider metadata into the preceding tool content part at each combined-message boundary. `AiConvertToLanguageModelPromptUpstreamTests.swift` proves part values override message values and later message metadata remains top-level. |
| `packages/ai/src/transcribe/transcribe.test.ts`; `packages/provider-utils/src/detect-media-type.test.ts` | `ported` | `MediaType.swift` recognizes ISO-BMFF `ftyp` audio in an audio context, keeps generic MP4 detection as video, and bounds raw/base64 ID3 scanning through the upstream 128 KiB edge. `MediaTypeTests.swift` covers both representations and the exact limit. |
| `packages/ai/src/generate-text/stream-text-timeout.test.ts`; `packages/ai/src/generate-text/stream-text.test-d.ts`; `packages/ai/src/prompt/prepare-language-model-call-options.test.ts`; `packages/ai/src/util/create-stitchable-stream.test.ts` | `deferred` | The new `firstChunkMs` timeout, semantic-content-only `chunkMs` reset, per-step re-arming, and error/cancellation timer cleanup need one structured Swift timeout API. Current Swift only exposes total `timeoutNanoseconds`; a narrow internal timer patch would not provide faithful public parity. |
| `packages/ai/src/ui-message-stream/read-ui-message-stream.test.ts` | `deferred` | The regression scopes repeated tool-call ids to the current model step and searches older steps only for late outputs. Swift's reducer has a global id index and `LanguageStreamPart` has no explicit step markers, so this needs a coordinated stream-enum/reducer change. |
| `packages/ai/src/text-stream/pipe-text-stream-to-response.test.ts`; `packages/ai/src/util/write-to-server-response.test.ts` | `out-of-scope` | These tests require Node `ServerResponse` helpers to return promises and reject on stream read/write errors. SwiftAISDK has no Node response-piping surface; `AsyncThrowingStream` errors already reach Swift consumers through iteration. |
| `packages/amazon-bedrock/src/amazon-bedrock-chat-language-model.test.ts`; `packages/amazon-bedrock/src/amazon-bedrock-prepare-tools.test.ts`; `packages/amazon-bedrock/src/anthropic/amazon-bedrock-anthropic-provider.test.ts`; `packages/amazon-bedrock/src/convert-to-amazon-bedrock-chat-messages.test.ts` | `ported` | `AmazonBedrockLanguageModel.swift`, `AmazonBedrockShared.swift`, and the shared Anthropic adapter now encode slash-containing ARN model ids, preserve supported exact case-sensitive `s3://` image sources in messages and tool results, sanitize replayed tool names, sanitize native-output schemas, and omit strict/native structured-output fields for Claude families Bedrock rejects. `AmazonBedrockTests.swift` carries focused ARN, S3, malformed-S3, tool-name, schema, and capability regressions. |
| `packages/anthropic/src/anthropic-language-model.test.ts`; `packages/anthropic/src/anthropic-unknown-model-max-output-tokens.test.ts`; `packages/anthropic/src/convert-to-anthropic-prompt.test.ts` | `ported` | The provider changes are covered by `AnthropicModels.swift`, `AnthropicOptions.swift`, and `AnthropicParsing.swift`: Claude Opus 5 and unknown-Claude capability defaults, conservative legacy/non-Claude handling, default-token warnings, `fallbacks: default`, disabled-thinking effort limits, JSON-tool parallel warnings, and thinking-token usage. Mid-conversation `toolChanges` in `AIMessage.providerMetadata` produce mapped tool-addition/removal blocks and both required beta headers; toolChanges-only messages omit empty text without consuming a cache breakpoint, while initial-system changes warn and are ignored. Focused Anthropic parity tests cover these paths. |
| `packages/gateway/src/gateway-language-model.test.ts` | `covered` | The only test change deletes the retired `hipaaCompliant` option cases. Swift has no typed HIPAA option to remove, remaining Gateway provider options continue through the existing JSON pass-through tests, and the stale compliance wording was removed from generated provider docs. |
| `packages/google/src/convert-to-google-messages.test.ts`; `packages/google/src/google-language-model.test.ts`; `packages/google/src/google-model-capabilities.test.ts`; `packages/google/src/google-prepare-tools.test.ts` | `ported` | `GoogleModelCapabilities.swift` and the GenerateContent request/parsing paths now default unknown future Gemini ids to newest supported behavior while retaining known legacy boundaries, preserve valid unsigned parallel calls after a signed standard call, surface `responseId` once, associate repeated code-execution results with their call, and apply provider-specific standard function-id handling. The focused Google and Vertex tests mirror these changed fixtures. |
| `packages/google/src/realtime/google-realtime-event-mapper.test.ts` | `out-of-scope` | The new `goAway`, `sessionResumptionUpdate`, and distinct `generationComplete` lifecycle events belong to the Google Live WebSocket protocol. SwiftAISDK currently has no realtime/WebSocket model surface, so mapping these JS realtime events would create an orphan API. |
| `packages/openai/src/image/openai-image-model.test.ts`; `packages/openai/src/openai-forward-compatible-defaults.test.ts`; `packages/openai/src/openai-language-model-capabilities.test.ts`; `packages/openai/src/responses/convert-to-openai-responses-input-tool-search.test.ts`; `packages/openai/src/responses/convert-to-openai-responses-input.test.ts`; `packages/openai/src/responses/openai-responses-language-model.test.ts`; `packages/openai/src/responses/openai-responses-prepare-tools.test.ts`; `packages/openai/src/tool/programmatic-tool-calling.test-d.ts` | `ported` | The OpenAI-compatible Chat/Responses/image changes add forward-compatible GPT reasoning and image-family defaults, preserve stored tool-search ids, and support programmatic tool definitions, caller linkage, output schemas, generated/streamed program items, forced tool choice, and multi-step continuation. Chat reasoning requests now omit every unsupported sampling/penalty field, surface matching generate/stream warnings, and always remove `topLogprobs`, including GPT-5.1+ effort `none`. `OpenAIProgrammaticAndForwardCompatibilityTests.swift`, `OpenAIChatTests.swift`, and updated OpenAI-compatible tests cover the changed request, parse, warning, and stream shapes. |
| `packages/devtools/src/viewer/client/theme.test.ts`; `packages/devtools/tests/e2e/theme.e2e.test.ts` | `out-of-scope` | These are browser viewer theme persistence and end-to-end DOM tests for the untracked `@ai-sdk/devtools` web application. They do not exercise a provider-facing Swift runtime contract. |
| `packages/harness/src/agent/harness-agent-settings.test-d.ts`; `packages/harness/src/agent/harness-agent-tool-result-continuation.test.ts`; `packages/harness/src/agent/harness-agent.test.ts`; `packages/harness/src/agent/internal/run-prompt.test.ts`; `packages/harness/src/agent/internal/turn-telemetry.test.ts`; `packages/harness/src/agent/internal/validate-tool-call.test.ts`; `packages/harness/src/agent/telemetry-integration.test.ts`; `packages/harness/src/bridge/index.test.ts`; `packages/harness/src/utils/sandbox-channel.test.ts` | `out-of-scope` | `@ai-sdk/harness` is an untracked JavaScript coding-agent runtime with its own bridge, sandbox channel, telemetry, and continuation protocol. SwiftAISDK's `AIAgent` surface does not expose this harness product contract. |
| `packages/harness-claude-code/src/bridge/create-emit-stream-event.test.ts`; `packages/harness-claude-code/src/bridge/json-schema-to-zod.test.ts`; `packages/harness-claude-code/src/claude-code-bridge-protocol.test.ts`; `packages/harness-claude-code/src/claude-code-harness.test.ts` | `out-of-scope` | Claude Code bridge framing, Zod conversion, process protocol, and harness lifecycle belong to the untracked JavaScript harness adapter rather than the Anthropic provider implementation. |
| `packages/harness-codex/src/bridge/create-emit-stream-event.test.ts`; `packages/harness-codex/src/bridge/index.test.ts`; `packages/harness-codex/src/codex-bridge-protocol.test.ts`; `packages/harness-codex/src/codex-harness.test.ts`; `packages/harness-codex/src/codex-instructions.test.ts` | `out-of-scope` | These tests cover the untracked Codex CLI harness bridge, child-process protocol, event translation, and instruction discovery; none maps to SwiftAISDK's provider-facing APIs. |
| `packages/harness-deepagents/src/bridge/create-emit-stream-event.test.ts`; `packages/harness-deepagents/src/bridge/tool-filtering.test.ts`; `packages/harness-deepagents/src/deepagents-bridge-protocol.test.ts` | `out-of-scope` | DeepAgents bridge events and tool filtering are adapter-specific JavaScript harness behavior, not a tracked Swift provider or core surface. |
| `packages/harness-opencode/src/bridge/create-emit-stream-event.test.ts`; `packages/harness-opencode/src/bridge/opencode-events.test.ts`; `packages/harness-opencode/src/opencode-bridge-protocol.test.ts` | `out-of-scope` | OpenCode event translation and bridge framing are untracked coding-harness process behavior with no SwiftAISDK protocol counterpart. |
| `packages/harness-pi/src/pi-auth.test.ts`; `packages/harness-pi/src/pi-model-resolver.test.ts`; `packages/harness-pi/src/pi-session.test.ts` | `out-of-scope` | Pi credential loading, model resolution, and session integration belong to the untracked JavaScript harness adapter and do not alter provider-facing Swift behavior. |
| `packages/langchain/src/adapter.test.ts`; `packages/langchain/src/utils.test.ts` | `no-swift-action` | The changes exercise the untracked TypeScript LangChain stream adapter and JavaScript utility conversions. SwiftAISDK has no LangChain JS object model or event stream to translate. |
| `packages/workflow/src/stream-text-iterator.test.ts` | `no-swift-action` | This test covers iterator behavior inside the untracked JavaScript workflow package. Swift async-sequence streaming is independent of the workflow serialization/runtime contract. |

Coverage check: the upstream command returns 64 paths, and the table references
64 unique paths with no missing, extra, or duplicate entries.

The baseline ref already contains the `generateText` abort-during-tool regression
and loose known UI-chunk compatibility tests, so those files do not appear in
this ref-to-ref list. The abort behavior was nevertheless ported for the npm
`ai@7.0.31 -> 7.0.37` audit; the Zod wire-schema change has no direct typed
Swift decoder surface. No `@ai-sdk/react` test file changed in this diff.
