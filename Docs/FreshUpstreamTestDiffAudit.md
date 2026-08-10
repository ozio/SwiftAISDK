# Fresh Upstream Test Diff Audit

This file tracks changed upstream test files between the checked SwiftAISDK
test inventory baseline and the current weekly-check upstream checkout. It is a
working audit, not a generated inventory.

Snapshot:

- Date: `2026-08-10`
- Baseline upstream ref: `vercel/ai@3bc0d4f40df7a77af4b181bc97dc1c54843545ab`
- Current upstream ref: `vercel/ai@74abcdfb6a41666b9910974510d6c9afd960ea1b`
- Diff command:

  ```sh
  git -C /tmp/vercel-ai-upstream-20260810 diff --name-status \
    3bc0d4f40df7a77af4b181bc97dc1c54843545ab..74abcdfb6a41666b9910974510d6c9afd960ea1b \
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

## 2026-08-10 Diff

The exact command above returns 110 changed test paths. They are grouped by
package below; the path count in each row sums back to 110 so newly added
untracked-product fixtures remain visible rather than disappearing behind a
provider-only filter.

| Upstream test group | Paths | Status | Swift evidence / rationale |
| --- | ---: | --- | --- |
| `packages/ai/**` | 16 | `ported/deferred/no-swift-action` | Default-instructions middleware, ToolLoopAgent default timeout, reconnect abort propagation, stale-run behavior and provider metadata are ported or already covered. Batch V4, generic async Video V4 and remaining typed tool-caller changes need shared public contracts; JavaScript async-iterable lock mechanics have no direct Swift analogue. |
| `packages/alibaba/**` | 4 | `ported/covered/deferred` | Streamed tool-call identity is ported and loose usage/tool mapping is covered. The video start/status split waits on async Video V4 while the unary wire flow remains covered. |
| `packages/amazon-bedrock/**` | 1 | `ported` | Converse conversion drops assistant turns left empty after unsigned reasoning is filtered. |
| `packages/anthropic/**` | 7 | `ported/deferred` | Advisor token caps/stop reasons, message lifecycle protection and code-execution replay have focused Swift coverage. Messages Batch waits on the shared batch model. |
| `packages/baseten/**` | 2 | `ported` | OpenAI-compatible HTTP embeddings/options/errors and default streamed usage are covered by Baseten tests. |
| `packages/black-forest-labs/**` | 2 | `ported` | Provider capability and FLUX 3 video request/poll/result fixtures are translated into the unary Swift model. |
| `packages/bytedance/**` | 1 | `covered/deferred` | Existing request/poll behavior is covered; async operation ownership remains deferred. |
| `packages/cartesia/**` | 1 | `deferred` | The changed Ink2 encodings belong to duplex WebSocket transcription. |
| `packages/fal/**` | 1 | `covered/deferred` | Unary queue polling is covered; webhook operations wait on async Video V4. |
| `packages/fish-audio/**` | 4 | `deferred` | New provider discovered and scoped for follow-up; this task intentionally does not auto-port it. |
| `packages/gateway/**` | 1 | `covered/deferred` | Unary video is covered; callback/start/status and stable logical-start idempotency wait on async Video V4. |
| `packages/google/**` | 2 | `covered/deferred` | Unary Veo behavior is covered; the speech-translation rename still targets the missing duplex protocol. |
| `packages/google-vertex/**` | 1 | `covered/deferred` | Existing Vertex request/poll mapping is covered; start/status APIs wait on async Video V4. |
| `packages/klingai/**` | 1 | `covered/deferred` | Unary submit/poll parsing remains covered; public async operations are deferred. |
| `packages/minimax/**` | 1 | `ported` | H3 text-to-video defaults/fallbacks use `16:9` while frame/reference behavior remains intact. |
| `packages/openai-compatible/**` | 2 | `ported` | Text token usage never becomes negative and stream tool calls inherit the shared identity fix. |
| `packages/openai/**` | 6 | `ported/deferred` | Output-schema tool results and rotating response item IDs are ported; Batch and duplex speech translation remain shared gaps, while `serviceTier: fast` already passes through. |
| `packages/otel/**` | 2 | `covered` | Swift telemetry already carries provider metadata and resolved response model attribution in terminal model-call events. |
| `packages/provider-utils/**` | 3 | `ported/no-swift-action` | Tracker identity/finalization is ported. Stateful JavaScript URL regex and Zod tree-shaking/schema tests do not map to Swift value types. |
| `packages/react/**` | 1 | `no-swift-action` | The changed `useChat` cadence fixture is React subscription/render behavior. |
| `packages/replicate/**` | 1 | `covered/deferred` | Unary polling is covered; webhook/status operations wait on async Video V4. |
| `packages/xai/**` | 1 | `covered/deferred` | Existing create/poll behavior is covered; the operation split waits on async Video V4. |
| `packages/code-mode/**` | 4 | `out-of-scope` | JavaScript sandbox approvals, exceptions, protocol and invocation behavior are not provider-facing Swift models. |
| `packages/harness-acp/**` | 23 | `out-of-scope` | New ACP harness lifecycle, bridge, host-tool, permission and session behavior belongs to an untracked JavaScript agent adapter. |
| `packages/harness-claude-code/**` | 2 | `out-of-scope` | Claude Code harness/bridge protocol behavior is not the Anthropic provider API. |
| `packages/harness-codex/**` | 3 | `out-of-scope` | Codex harness event and bridge protocol behavior is outside the provider port. |
| `packages/harness-deepagents/**` | 1 | `out-of-scope` | DeepAgents bridge protocol is an untracked harness adapter. |
| `packages/harness-grok-build/**` | 2 | `out-of-scope` | The newly published Grok Build harness is not a model provider. |
| `packages/harness-opencode/**` | 2 | `out-of-scope` | OpenCode relay authentication and bridge protocol remain harness-specific. |
| `packages/harness/**` | 6 | `out-of-scope` | Harness errors, bootstrap, telemetry and bridge capability behavior belong to the untracked product runtime. |
| `packages/langchain/**` | 2 | `out-of-scope` | TypeScript LangChain adapter conversions are not part of SwiftAISDK. |
| `packages/sandbox-vercel/**` | 1 | `out-of-scope` | Vercel sandbox behavior is an untracked JavaScript sandbox package. |
| `packages/workflow-harness/**` | 1 | `out-of-scope` | Workflow harness agent slicing is outside provider-facing scope. |
| `packages/workflow/**` | 2 | `out-of-scope` | JavaScript workflow iterator/agent behavior has no SwiftAISDK product surface. |

Coverage check: package-group path counts total 110, matching the exact upstream
diff command with no unclassified package group.

## 2026-08-03 Diff

| Upstream test file(s) | Status | Swift evidence / rationale |
| --- | --- | --- |
| `packages/fireworks/src/fireworks-provider.test.ts` | `ported` | Fireworks chat, completion, and embedding now accept both legacy string errors and the actual nested object envelope, preserving the provider's `error.message` in `AIAPICallError`; focused Swift coverage exercises both shapes while image errors retain generic body handling. |
| `packages/minimax/src/minimax-provider.test.ts`; `packages/minimax/src/minimax-video-model.test.ts` | `ported` | The provider now exposes MiniMax-H3 video generation alongside the existing Anthropic-compatible language factory. Focused Swift tests cover provider aliases/capabilities, text-to-video, first/last-frame and reference inputs, request options, polling, result download metadata, warnings, errors, and abort behavior. |
| `packages/provider-utils/src/create-null-language-model-usage.test.ts` | `covered` | Swift represents unavailable usage with optional `TokenUsage` fields rather than a JavaScript object whose every nested token field is `undefined`; existing absent-usage generate and stream fixtures prove the equivalent public result. |
| `packages/harness-claude-code/src/claude-code-harness.test.ts`; `packages/harness-codex/src/codex-harness.test.ts`; `packages/harness-deepagents/src/deepagents-harness.test.ts`; `packages/harness-opencode/src/bridge/create-emit-stream-event.test.ts`; `packages/harness-opencode/src/bridge/opencode-events.test.ts`; `packages/harness-opencode/src/bridge/opencode-usage.test.ts`; `packages/harness-opencode/src/opencode-harness.test.ts`; `packages/harness/src/agent/harness-agent.test.ts`; `packages/harness/src/agent/internal/bootstrap-recipe.test.ts`; `packages/harness/src/agent/internal/sandbox-bootstrap.test.ts`; `packages/harness/src/agent/prepare-sandbox-for-harness.test.ts` | `out-of-scope` | These changes cover untracked JavaScript coding-harness adapters, bridge events, bootstrap recipes, sandbox setup, and usage accounting rather than provider-facing Swift model behavior. |

Coverage check: the upstream command returns 15 paths, and the table references
15 unique paths with no missing, extra, or duplicate entries.

## 2026-08-01 Diff

| Upstream test file(s) | Status | Swift evidence / rationale |
| --- | --- | --- |
| `packages/ai/src/generate-text/generate-text.test.ts`; `packages/ai/src/generate-text/stream-language-model-call.test.ts`; `packages/ai/src/generate-text/stream-text.test.ts`; `packages/otel/src/open-telemetry.test.ts` | `ported` | Generate and stream paths now ignore provider-executed tool calls for client execution/results, retain metadata-bearing empty text deltas, and report the response model id in terminal telemetry. Focused Swift tests cover each changed result and event shape. |
| `packages/ai/src/agent/tool-loop-agent.test-d.ts`; `packages/ai/src/agent/tool-loop-agent.test.ts`; `packages/ai/src/generate-text/generate-text.test-d.ts`; `packages/ai/src/generate-text/stream-text.test-d.ts` | `deferred` | The new local/provider `experimental_toolCallers` graph changes public tool typing, binding, visibility, and provider-option preparation. SwiftAISDK has no equivalent caller abstraction yet, so a faithful port needs a coordinated core API design. |
| `packages/ai/src/generate-text/stream-text-timeout.test.ts` | `ported` | The changed fixture only adds provider metadata to an empty text delta in the existing first-chunk-timeout case. Swift now forwards that metadata-bearing empty delta and merges its metadata into the completed text content, covered by the focused stream/output regressions above. |
| `packages/ai/src/generate-object/generate-object.test.ts`; `packages/ai/src/generate-object/stream-object.test.ts` | `covered` | The upstream change promotes `repairText` while retaining the experimental alias. Swift's existing object-repair callback is already stable rather than experimental and preserves the same repair precedence behavior. |
| `packages/ai/src/generate-text/generated-file.test-d.ts` | `covered` | Swift generated-file output is already a typed `GeneratedFile` value rather than a TypeScript structural type, so the new declaration-only branding regression requires no runtime change. |
| `packages/ai/src/logger/log-warnings.test.ts` | `no-swift-action` | This changes Node-specific `process.emitWarning` versus `console.warn` routing. SwiftAISDK returns typed warnings to callers and has no Node logger surface. |
| `packages/ai/src/translate/stream-translate.test.ts` | `deferred` | Streaming speech translation is a new core/provider protocol surface. It should be introduced together with provider translation models rather than as an orphan facade. |
| `packages/amazon-bedrock/src/amazon-bedrock-chat-language-model.test.ts`; `packages/amazon-bedrock/src/amazon-bedrock-prepare-tools.test.ts`; `packages/amazon-bedrock/src/convert-to-amazon-bedrock-chat-messages.test.ts` | `ported` | Bedrock now maps all ten video MIME types to formats, accepts inline/file and tool-result S3 media, emits strict unsupported-input warnings, keeps ordinary tools beside JSON structured output, and extracts balanced JSON in generate and stream parsing. |
| `packages/anthropic/src/anthropic-language-model.test.ts` | `deferred` | The changed regression is part of the generic tool-caller/provider-caller surface. Existing Anthropic behavior remains covered; caller linkage waits on the shared core design above. |
| `packages/azure/src/azure-openai-tools.test-d.ts`; `packages/openai/src/responses/openai-responses-language-model.test.ts`; `packages/openai/src/responses/openai-responses-prepare-tools.test.ts` | `ported` | OpenAI and Azure Responses web-search options now encode `blockedDomains` as `blocked_domains`, with focused request-builder coverage. |
| `packages/code-mode/src/core.test.ts`; `packages/code-mode/src/e2e/code-mode-haiku.e2e.test.ts`; `packages/code-mode/src/exceptions.test.ts`; `packages/code-mode/src/runtime/async-context.test.ts`; `packages/code-mode/src/runtime/bridge-lifecycle.test.ts`; `packages/code-mode/src/runtime/bundled-runtime.test.ts`; `packages/code-mode/src/runtime/console.test.ts`; `packages/code-mode/src/runtime/max-workers.test.ts`; `packages/code-mode/src/runtime/protocol.test.ts`; `packages/code-mode/src/runtime/security.test.ts`; `packages/code-mode/src/runtime/timeouts.test.ts`; `packages/code-mode/src/runtime/tool-concurrency.test.ts`; `packages/code-mode/src/runtime/worker-concurrency.test.ts`; `packages/code-mode/src/tool-invocation.test.ts`; `packages/code-mode/src/tool-prompt.test.ts`; `packages/code-mode/src/utils/options.test.ts`; `packages/code-mode/src/utils/source-cache.test.ts` | `out-of-scope` | `@ai-sdk/code-mode` is a new JavaScript sandbox/worker product package, not a provider-facing model package. It is reported by registry discovery but is not auto-ported in this provider update. |
| `packages/devtools/src/integration.test.ts`; `packages/devtools/src/middleware.test.ts`; `packages/devtools/src/serialize.test.ts`; `packages/devtools/src/viewer/client/media-components.test.ts`; `packages/devtools/src/viewer/client/media.test.ts`; `packages/devtools/tests/e2e/theme.e2e.test.ts` | `out-of-scope` | Devtools middleware, serialization, media rendering, and browser-theme behavior belong to the untracked web viewer product. |
| `packages/elevenlabs/src/elevenlabs-transcription-model.test.ts` | `deferred` | The changed behavior is ElevenLabs realtime transcription over WebSocket. SwiftAISDK currently exposes batch transcription only; this belongs with a shared realtime transport API. |
| `packages/google/src/google-files.test.ts`; `packages/google/src/interactions/google-interactions-language-model.test.ts` | `ported` | Google Files no longer forces a payload `Content-Length`, while Interactions forwards `topK` and `seed` and returns complete unsupported-setting/agent warnings. |
| `packages/google/src/translation/google-translation-model.test.ts` | `deferred` | Google streaming translation is deferred with the shared translation protocol above. |
| `packages/groq/src/groq-transcription-model.test.ts` | `ported` | Groq transcription accepts raw `text` responses and falls back to word-level segments when verbose responses omit aggregate segments. |
| `packages/harness/src/agent/internal/run-prompt.test.ts`; `packages/workflow-harness/src/run-harness-agent-slice.test.ts`; `packages/langchain/src/utils.test.ts`; `packages/workflow/src/serializable-schema.test.ts`; `packages/workflow/src/stream-text-iterator.test.ts`; `packages/workflow/src/workflow-agent.test-d.ts`; `packages/workflow/src/workflow-agent.test.ts` | `out-of-scope` | These paths exercise untracked JavaScript harness, LangChain, and workflow runtime contracts rather than SwiftAISDK's provider-facing APIs. |
| `packages/klingai/src/klingai-auth.test.ts`; `packages/klingai/src/klingai-provider.test.ts` | `ported` | Public Kling settings now support API-key and legacy access/secret credentials with deterministic precedence, while an explicit Authorization header still overrides generated auth. |
| `packages/mcp/src/tool/mcp-client.test.ts`; `packages/mcp/src/tool/mcp-http-transport.test.ts`; `packages/mcp/src/tool/mcp-sse-transport.test.ts` | `ported` | MCP initialization and request calls now support individual and total timeout budgets, use the effective minimum deadline, map cancellation consistently, and clean pending request state. Swift transport construction preserves these settings across HTTP/SSE clients. |
| `packages/minimax/src/minimax-provider.test.ts`; `packages/minimax/src/minimax-reasoning.test.ts` | `ported` | `MiniMaxProviderTests.swift` translates the published provider/auth/alias/unsupported-family contract and the exact adaptive-thinking fixture, including ordered reasoning/text output. Additional focused coverage proves custom header precedence, empty URL capabilities, signature metadata, usage/response metadata, and the shared Anthropic stream lifecycle. The Swift baseline is current `@ai-sdk/minimax@3.0.1`; its provider source is byte-identical to the originally audited `3.0.0`. |
| `packages/mistral/src/convert-to-mistral-chat-messages.test.ts`; `packages/mistral/src/mistral-transcription-model.test-d.ts`; `packages/mistral/src/mistral-transcription-model.test.ts` | `ported` | Mistral message conversion preserves assistant reasoning as typed thinking blocks, and the new Voxtral transcription model covers multipart input, options/validation, segment parsing, and rich response metadata. |
| `packages/openai/src/files/openai-files.test.ts` | `ported` | OpenAI file upload expiry now uses the accepted nested multipart fields `expires_after[anchor]` and `expires_after[seconds]`, with provider-option validation and request-metadata coverage in `FileAndSkillClientTests.swift`. |
| `packages/openai/src/openai-stream-error.test.ts`; `packages/openai/src/tool/web-search.test-d.ts`; `packages/openai/src/translation/openai-translation-model.test.ts` | `deferred` | Generic stream-error recovery, typed web-search caller linkage, and realtime translation need the shared streaming/tool-caller/translation designs. Existing web-search behavior remains covered. |
| `packages/perplexity/src/perplexity-embedding-model.test.ts` | `ported` | Perplexity embeddings now expose typed dimensions/encoding options, enforce the 512-input limit, decode signed/base64 binary vectors, and return token plus cost metadata. |
| `packages/provider-utils/src/connect-to-websocket.test.ts`; `packages/provider-utils/src/safe-node-fetch.test.ts` | `deferred` | WebSocket close metadata belongs with the missing realtime transport surface. DNS-result pinning for downloads needs a URLSession-level resolver/connection design; URL allowlisting alone cannot faithfully reproduce the Node connector guarantee. |
| `packages/provider-utils/src/is-record.test.ts`; `packages/provider-utils/src/serialize-model-options.test.ts` | `no-swift-action` | JavaScript cross-realm record detection and async-option serialization error branding do not map to Swift's static value types. |
| `packages/togetherai/src/togetherai-provider.test.ts` | `ported` | Together chat and completion request builders now append `includeUsage=true`, with request URL coverage. |
| `packages/xai/src/responses/xai-responses-language-model.test.ts`; `packages/xai/src/xai-video-model.test.ts` | `ported` | xAI Responses emits the new unsupported-setting warnings; video polling tolerates repeated `202` responses and carries the latest request state until completion. |

Coverage check: the upstream command returns 78 paths, and the table references
78 unique paths with no missing, extra, or duplicate entries.

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
