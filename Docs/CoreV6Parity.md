# Core V6 Parity

Snapshot date: 2026-06-23

This document tracks SwiftAISDK against the current AI SDK v6 Core and Errors
reference. It is intentionally high-level: provider package drift belongs in
`ProviderVersionLedger.md` and provider behavior belongs in focused tests.
Implementation-sensitive UI/chat items are also checked against npm source
snapshots, currently `ai@6.0.208`, `@ai-sdk/provider@3.0.10`,
`@ai-sdk/provider-utils@4.0.30`, and `@ai-sdk/react@3.0.210`.

References:

- <https://ai-sdk.dev/docs/reference/ai-sdk-core>
- <https://ai-sdk.dev/docs/reference/ai-sdk-errors>
- <https://ai-sdk.dev/docs/reference/ai-sdk-ui>

## Latest Core Package Diff Notes

Checked npm package diffs:

- `ai@6.0.200 -> 6.0.208`
- `@ai-sdk/provider@3.0.10`
- `@ai-sdk/react@3.0.206 -> 3.0.210`
- `@ai-sdk/provider-utils@4.0.29 -> 4.0.30`

Port decisions:

- `provider-utils@4.0.30` SSRF hardening is ported in `validateDownloadURL`
  and `downloadURL`: trailing-dot hostnames are normalized before local-host
  checks, additional private/reserved IPv4 and IPv6 ranges are blocked,
  embedded IPv4-in-IPv6 forms are decoded, and redirects are followed manually
  with each hop validated before the next request is issued.
- `provider-utils@4.0.30` same-origin credential hardening is ported through the
  shared `isSameOrigin` helper and provider-specific guards for
  Black Forest Labs, FAL, Fireworks, Gladia, Google Veo, and Replicate.
- `ai@6.0.201` array-output transform fix is already Swift-native: array output
  returns decoded `Element` values from the final validated object array path,
  and Swift has no Zod-style transform pipeline that could return raw elements.
- `ai@6.0.202` approval replay HMAC fix has no direct Swift replay path to
  patch. Swift tool execution only runs fresh tool calls from the current model
  step after JSON/schema validation and `toolApproval` evaluation; approvals
  converted from UI history are message content, not an execution trigger.
- `ai@6.0.203` stream-part prototype-pollution hardening is not directly
  applicable to Swift value dictionaries and typed reducers; related stream
  accumulators are keyed by Swift `String`/`Int` values without JS prototype
  inheritance.
- `ai@6.0.203` UI-message server error redaction is a JS response-stream
  default. Swift has no `createUIMessageStream` server helper; local
  `AIUIMessageStreamReducer` wraps unexpected reducer errors as
  `AIUIMessageStreamError` for in-process callers rather than serializing a
  public client error chunk.

## Status Labels

| Status | Meaning |
| --- | --- |
| `covered` | SwiftAISDK has a direct product-level API or type for this surface. |
| `swift-native` | The behavior is present, but intentionally shaped differently for Swift. |
| `partial` | Important behavior exists, but the upstream surface is not fully represented. |
| `missing` | No meaningful current equivalent. |
| `out of scope candidate` | Likely frontend, JS-framework, or TS-specific surface; needs an explicit product decision. |

## AI SDK Core Reference

| Upstream reference item | SwiftAISDK status | Current Swift evidence | Notes / next decision |
| --- | --- | --- | --- |
| `generateText` | `covered` | `AI.generateText`, `LanguageModelRequest`, `TextGenerationResult` | Supports prompt/request overloads, tools, multi-step loops, retries, telemetry, provider metadata, response metadata, raw chunks, and abort signals. |
| `streamText` | `covered` | `AI.streamText`, `LanguageStreamPart` | Async sequence surface with lifecycle parts, tools, approvals, retries-before-first-yield, telemetry, and abort propagation. |
| `embed` | `covered` | `AI.embed`, `EmbeddingRequest`, `EmbeddingResult` | Single-value helper delegates through the embedding request shape. |
| `embedMany` | `covered` | `AI.embedMany` | Supports batching through `chunkSize` and aggregates usage/warnings/metadata. |
| `rerank` | `covered` | `AI.rerank`, `RerankingRequest`, `RerankingResult` | Native model family exists. |
| `generateImage` | `covered` | `AI.generateImage`, `ImageGenerationRequest` | Includes files, masks, provider options, metadata, warnings, retries, and aborts. |
| `transcribe` | `covered` | `AI.transcribe`, `AudioTranscriptionRequest` | Upstream now documents `transcribe`; older experimental naming is intentionally not mirrored. |
| `generateSpeech` | `covered` | `AI.generateSpeech`, `SpeechRequest` | Native model family exists. |
| `experimental_generateVideo` | `covered` | `AI.generateVideo`, `VideoGenerationRequest` | Swift uses stable `generateVideo` naming. Decide only if an `experimental_` alias is useful for discoverability. |
| `Output` | `covered` | `Output.text/object/array/choice/json`, `AI.generateText(... output:)`, `AI.streamText(... output:)`, existing object-generation facades | Swift now mirrors the v6-style `generateText/streamText + Output.*` entry point while still keeping the older Swift-native object/array/enum/json facades. `Output.object` partial streaming uses `JSONValue` because Swift has no automatic `DeepPartial<T>`. |
| `Agent` interface | `covered` | `AIAgent`, `AIAgentCallOptions` | Swift-native agent protocol mirrors upstream `version: "agent-v1"`, optional `id`, tool exposure, and generate/stream calls over model messages or prompts. |
| `ToolLoopAgent` | `covered` | `AIToolLoopAgent`, tool-loop overloads on `AI.generateText` and `AI.streamText` | Reusable agent object wraps the existing Swift tool loop. Default `maxSteps` is 20 to match upstream `stepCountIs(20)` behavior. |
| `createAgentUIStream` | `covered` | `createAgentUIStream`, `AIUIMessageStreamReducer.snapshots(from:)` | Converts validated `AIUIMessage` history to model messages, streams through any `AIAgent`, and returns assistant UI-message snapshots. |
| `createAgentUIStreamResponse` | `out of scope candidate` | none | JS response/server surface; likely not a SwiftPM core priority unless a Swift server use case is chosen. |
| `pipeAgentUIStreamToResponse` | `out of scope candidate` | none | Same as above. |
| `tool` | `swift-native` | `AITool` | Swift uses a concrete typed tool struct rather than a TS inference helper. |
| `dynamicTool` | `swift-native` | `AITool.dynamic`, MCP tool conversion | Behavior exists; naming differs. |
| `createMCPClient` | `covered` | `MCPClient.connect`, `MCPHTTPTransport`, `MCPStdioTransport` | Broad MCP client, transport, OAuth, resources, prompts, elicitation, and tool conversion coverage. |
| `Experimental_StdioMCPTransport` | `covered` | `MCPStdioTransport` | Swift uses stable transport naming. |
| `jsonSchema` | `swift-native` | `AIJSONSchema`, `JSONValue`, `parseJSON`, schema validator | Usable JSON Schema adapter exists; exact factory naming does not. |
| `zodSchema` | `out of scope candidate` | none | Zod is TypeScript-specific. Could document `AIJSONSchema` as the Swift alternative. |
| `valibotSchema` | `out of scope candidate` | none | Valibot is TypeScript-specific. |
| `ModelMessage` | `covered` | `AIMessage`, `AIContentPart`, `MessageRole` | Swift naming differs but covers system/user/assistant/tool plus text, file, image URL, provider references, tool calls/results, approvals. |
| `UIMessage` | `covered` | `AIUIMessage`, `AIUIMessagePart`, text/reasoning/data/file/source/tool/approval/custom parts | Swift keeps UI/render messages separate from `AIMessage` model-request messages. |
| `validateUIMessages` | `covered` | `validateUIMessages` | Validates non-empty message arrays/parts, ids, tool JSON arguments, tool-result links, and approval links. Schema-driven metadata/data/tool validation remains Swift-native rather than a direct Zod/Standard Schema port. |
| `safeValidateUIMessages` | `covered` | `safeValidateUIMessages`, `AIUIMessageValidationResult` | Non-throwing validation result for UI persistence/import flows. Swift returns accumulated issues instead of the upstream `{ success, data/error }` union. |
| `createProviderRegistry` | `covered` | `createProviderRegistry`, `AIProviderRegistry` | Registry and default-provider flows exist. |
| `customProvider` | `covered` | `customProvider`, `AICustomProvider` | Supports configured models/clients and fallbacks. |
| `cosineSimilarity` | `covered` | `cosineSimilarity(_:_:)` for `Double` and `Float` vectors | Mirrors upstream empty-vector and zero-magnitude behavior, and throws `AIError.invalidArgument` for mismatched lengths. |
| `wrapLanguageModel` | `covered` | `wrapLanguageModel`, `AILanguageModelMiddleware` | Includes generate/stream wrapping and request transforms. |
| `wrapImageModel` | `covered` | `wrapImageModel`, `AIImageModelMiddleware` | Direct surface exists. |
| `LanguageModelV3Middleware` | `covered` | `AILanguageModelMiddleware` | Swift-specific type name; semantics are similar. |
| `extractReasoningMiddleware` | `covered` | `extractReasoningMiddleware` | Direct helper exists. |
| `simulateStreamingMiddleware` | `covered` | `simulateStreamingMiddleware` | Direct helper exists. |
| `defaultSettingsMiddleware` | `covered` | `defaultSettingsMiddleware` | Direct helper exists. Swift also has embedding defaults. |
| `addToolInputExamplesMiddleware` | `covered` | `addToolInputExamplesMiddleware` | Direct helper exists. |
| `extractJsonMiddleware` | `covered` | `extractJsonMiddleware`, `extractJSONMiddleware` | Direct helper plus Swift capitalization alias. |
| `stepCountIs` | `swift-native` | `AIStopCondition.isStepCount` | Behavior exists; helper name differs. |
| `hasToolCall` | `swift-native` | `AIStopCondition.hasToolCall` | Behavior exists; helper name differs. |
| `simulateReadableStream` | `covered` | `simulateReadableStream(chunks:initialDelayNanoseconds:chunkDelayNanoseconds:)` | Swift-native `AsyncThrowingStream` equivalent with `nil` delays as the no-delay path. |
| `smoothStream` | `covered` | `smoothStream(_:delayNanoseconds:chunking:)`, custom detector overload | Smooths text/reasoning deltas by word, line, or custom detector; flushes before non-text chunks and preserves metadata. |
| `generateId` | `covered` | `generateId()` | Public 16-character non-secure ID helper matching upstream default length/alphabet. |
| `createIdGenerator` | `covered` | `createIdGenerator(prefix:separator:size:alphabet:)` | Supports prefix, separator, size, and alphabet. Separator is only used when `prefix` is provided, matching upstream provider-utils behavior. |
| `DefaultGeneratedFile` | `missing` | `AIStreamFile`, generated media result structs | File/media objects exist, but not the upstream named type. |

## AI SDK Errors Reference

SwiftAISDK currently favors fewer stable Swift error types instead of one public
error class per upstream `AI_*` error. That gives a simpler Swift surface, but
it means JavaScript-style error-class parity is only partial.

| Upstream error | SwiftAISDK status | Current Swift evidence | Notes / next decision |
| --- | --- | --- | --- |
| `AI_APICallError` | `covered` | `AIAPICallError`, `AIError.apiCallError`, provider-specific HTTP error mapping | Swift keeps existing `AIError.httpStatus*` compatibility while exposing a richer API-call error shape for status/body/headers/retryability diagnostics. |
| `AI_DownloadError` | `covered` | `AIDownloadError` | Direct Swift analog exists. |
| `AI_EmptyResponseBodyError` | `partial` | `AIError.invalidResponse` | Empty-body cases are reported through general invalid-response errors. |
| `AI_InvalidArgumentError` | `covered` | `AIError.invalidArgument` | Direct functional analog exists. |
| `AI_InvalidDataContentError` | `partial` | `AIError.invalidArgument`, `AIDownloadError`, media validation paths | No dedicated public type. |
| `AI_InvalidMessageRoleError` | `partial` | `MessageRole` enum, provider message conversion validation | Swift enum prevents many invalid roles, but conversion failures use general errors. |
| `AI_InvalidPromptError` | `partial` | `AIError.invalidArgument`, provider conversion errors | No dedicated prompt error with structured prompt details. |
| `AI_InvalidResponseDataError` | `covered` | `AIError.invalidResponse` | Functional analog exists, though less structured. |
| `AI_InvalidToolApprovalError` | `covered` | `AIInvalidToolApprovalError`, `validateUIMessages` | Throwing UI-message validation now reports unknown approval response ids with a typed approval error; `safeValidateUIMessages` still returns accumulated issues. |
| `AI_InvalidToolInputError` | `covered` | `AIInvalidToolInputError`, `AITypeValidationError`, `AITool` validation/refinement | Tool argument JSON/schema failures now throw typed tool-input errors. |
| `AI_JSONParseError` | `covered` | `AIJSONParseError` | Direct Swift analog exists. |
| `AI_LoadAPIKeyError` | `covered` | `AIError.missingAPIKey` | Functional analog exists. |
| `AI_LoadSettingError` | `partial` | `AIError.invalidArgument`, provider settings validation | No dedicated setting-load error. |
| `AI_MessageConversionError` | `partial` | provider-specific conversion errors via `AIError.invalidArgument`/warnings | No dedicated public message-conversion error. |
| `AI_NoContentGeneratedError` | `covered` | `AINoContentGeneratedError` | Public cross-modal no-content analog exists for callers that want the generic upstream error concept. |
| `AI_NoImageGeneratedError` | `covered` | `AINoImageGeneratedError`, `AI.generateImage` | The public facade throws a typed error when a successful image model call returns no URL or base64 image. Provider-specific low-level models may still throw narrower invalid-response errors before returning. |
| `AI_NoTranscriptGeneratedError` | `covered` | `AINoTranscriptGeneratedError`, `AI.transcribe` | The public facade throws a typed error for empty final transcript text. |
| `AI_NoVideoGeneratedError` | `covered` | `AINoVideoGeneratedError`, `AI.generateVideo` | The public facade throws a typed error when no URL or base64 video is returned. |
| `AI_NoSpeechGeneratedError` | `covered` | `AINoSpeechGeneratedError`, `AI.generateSpeech` | The public facade throws a typed error for empty generated audio. |
| `AI_NoObjectGeneratedError` | `covered` | `AIObjectGenerationError` with `kind` and `strategy` | Swift groups object/array/enum/json failures into one typed error. |
| `AI_NoOutputGeneratedError` | `covered` | `AINoOutputGeneratedError`, `AIObjectGenerationError` | The v6-style `Output` stream mapper now has a dedicated no-output error for streams that finish without final output. Object parsing still uses `AIObjectGenerationError` for invalid generated output. |
| `AI_NoSuchModelError` | `covered` | `AIError.unsupportedModel` | Functional analog exists. |
| `AI_NoSuchProviderError` | `covered` | `AIProviderRegistryError.noSuchProvider` | Direct registry analog exists. |
| `AI_NoSuchToolError` | `covered` | `AINoSuchToolError` | Local tool loops now throw a typed error when the model asks for an unavailable non-provider-executed tool. |
| `AI_RetryError` | `covered` | `AIRetryError`, `AIRetryErrorReason` | Direct Swift analog exists. |
| `AI_ToolCallNotFoundForApprovalError` | `covered` | `AIToolCallNotFoundForApprovalError`, `validateUIMessages` | Approval requests that reference a missing tool call now surface as a typed error in throwing validation. |
| `AI_ToolCallRepairError` / `ToolCallRepairError` | `covered` | `AIToolCallRepairError`, `AITool.refineArguments` | Swift maps the existing argument-refinement hook to a typed tool-call repair failure. |
| `AI_TooManyEmbeddingValuesForCallError` | `covered` | `AITooManyEmbeddingValuesForCallError`, embedding model preflight guards | OpenAI-compatible, Google, Google Vertex, Voyage, Mistral, Cohere, and Amazon Bedrock embedding limits now throw a typed error carrying provider, model id, max count, and values. |
| `AI_TypeValidationError` | `covered` | `AITypeValidationError`, `AIJSONSchemaValidator`, `AIObjectGenerationError.kind == .schemaValidation` | Schema validation now has a standalone public type-validation error, while object generation continues to wrap schema failures in `AIObjectGenerationError`. |
| `AI_UIMessageStreamError` | `covered` | `AIUIMessageStreamError` | Used for UI message validation and stream-reduction failures. Carries `chunkType`/`chunkID` for out-of-sequence stream chunks, plus Swift validation issues. |
| `AI_UnsupportedFunctionalityError` | `partial` | `AIError.unsupportedModel`, `AIWarning(type: "unsupported", ...)`, provider invalid-argument paths | Unsupported features are represented, but not as a dedicated public error class. |

## Recommended Next Passes

1. Continue polishing the new `AIOutput` surface where it proves useful:
   document examples and consider array `elementStream` ergonomics. The
   `choice/json` factories already propagate `name` and `description` as
   provider hints.
2. Decide whether `DefaultGeneratedFile` deserves a named Swift analog or
   whether `AIStreamFile` plus generated media result structs are sufficient.
3. Keep JS response helpers (`createAgentUIStreamResponse`,
   `pipeAgentUIStreamToResponse`, `createUIMessageStreamResponse`,
   `pipeUIMessageStreamToResponse`) out of core unless SwiftAISDK grows a
   server-side Swift target.
4. Continue typed-error parity only where it improves Swift diagnostics. The
   middle-path batches now cover API calls, type validation, no-output,
   no-such-tool, invalid tool input, tool-call repair, approval-link failures,
   no-generated media, and too-many embedding values. Remaining candidates are
   mostly prompt/message conversion and narrower provider response-shape errors.

## SwiftUI UI Layer Candidates

The AI SDK UI reference is web-framework oriented, but several ideas map well
to SwiftUI. These are not intended as direct ports of React/Svelte/Vue hooks;
they are candidate Swift-native product surfaces for a future SwiftUI layer.

| Upstream UI idea | SwiftUI candidate | Priority | Notes |
| --- | --- | --- | --- |
| `useChat` | `AIChatSession` | done | Combine-backed `ObservableObject` for iOS 15/macOS 12+ that manages `messages`, `status`, `error`, `sendMessage`, submit-existing-transcript, replacement, `regenerate`, `stop`, `resumeStream`, `addToolOutput`, and `addToolApprovalResponse` over `AIChatTransport`. Uses upstream status names and mirrors `onError`, `onFinish`, abort/resume finish semantics, and `sendAutomaticallyWhen`. Swift tool output currently appends tool-role messages instead of mutating stateful upstream tool UI parts. |
| `UIMessage` and message parts | `AIUIMessage`, `AIUIMessagePart`, metadata/data parts | done | Core render-message model exists without depending on SwiftUI/Observation. |
| `convertToModelMessages` | `convertToModelMessages` | done | Converts supported `AIUIMessage` parts into `AIMessage` history for model calls; render-only parts are ignored, unsupported URL files fail with `AIUIMessageStreamError`. |
| `readUIMessageStream` / UI stream reducer | `AIUIMessageStreamReducer` | done | Converts `LanguageStreamPart` into stable UI message snapshots, so UI layers do not hand-roll streaming assembly. ID-based text/reasoning/tool-input chunks now reject missing starts like upstream `processUIMessageStream`; Swift keeps id-less language deltas as a compatibility convenience. |
| `useObject` | `AIObjectGenerationSession<Output, Partial>` | done | Combine-backed `ObservableObject` over v6-style `Output` streaming with `partialObject`, final `object`, `result`, status, error, text, warnings, metadata, `submit`, `stop`, and `clear`. Final object validation errors are reported through `onFinish`, matching upstream `useObject` semantics. |
| `DirectChatTransport` | `AIChatTransport`, `AIChatTransportRequest`, `AIChatRequestOptions`, `DirectAIChatTransport` | done | In-process transport streams `AIUIMessage` snapshots from `AI.streamText`, supports tool-loop options, request defaults, aborts, retry/timeout/telemetry, and reasoning/source/finish filters. Leave room for an `HTTPChatTransport` later when an app talks to its own backend. |

### Not Worth Directly Porting

| Upstream UI idea | Decision | Reason |
| --- | --- | --- |
| `useCompletion` | `defer` | Most SwiftUI completion use cases can be handled by a small view model over `streamText`; add only if repeated app code proves the need. |
| `createUIMessageStreamResponse` | `out of scope candidate` | Web response helper; not useful for local SwiftUI unless SwiftAISDK grows a server-side Swift story. |
| `pipeUIMessageStreamToResponse` | `out of scope candidate` | Node/server response helper; same rationale as above. |
| `InferUITools` / `InferUITool` | `out of scope` | TypeScript inference helpers with no direct Swift equivalent. |

### Suggested Build Order

1. Add examples/docs for `AIObjectGenerationSession` and agent UI streams once the public naming settles.
2. Consider `useCompletion` only if real SwiftUI app code repeatedly needs a dedicated completion session.
