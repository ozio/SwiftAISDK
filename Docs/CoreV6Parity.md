# Core V6 Parity

Snapshot date: 2026-06-03

This document tracks SwiftAISDK against the current AI SDK v6 Core and Errors
reference. It is intentionally high-level: provider package drift belongs in
`ProviderVersionLedger.md` and provider behavior belongs in focused tests.

References:

- <https://ai-sdk.dev/docs/reference/ai-sdk-core>
- <https://ai-sdk.dev/docs/reference/ai-sdk-errors>
- <https://ai-sdk.dev/docs/reference/ai-sdk-ui>

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
| `Agent` interface | `missing` | none | Decide whether SwiftAISDK should port agent abstractions or keep tool loops inside `AI.generateText`/`AI.streamText`. |
| `ToolLoopAgent` | `partial` | tool-loop overloads on `AI.generateText` and `AI.streamText` | Behavior exists as facade options, not as a reusable agent object. |
| `createAgentUIStream` | `partial` | `AIUIMessageStreamReducer`, `AIUIMessageStreamReducer.snapshots(from:)` | Swift now has the core UI-message reducer needed for agent/UI streams, but no dedicated `Agent` stream wrapper yet. |
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
| `validateUIMessages` | `covered` | `validateUIMessages` | Validates ids, tool JSON arguments, tool-result links, and approval links. |
| `safeValidateUIMessages` | `covered` | `safeValidateUIMessages`, `AIUIMessageValidationResult` | Non-throwing validation result for UI persistence/import flows. |
| `createProviderRegistry` | `covered` | `createProviderRegistry`, `AIProviderRegistry` | Registry and default-provider flows exist. |
| `customProvider` | `covered` | `customProvider`, `AICustomProvider` | Supports configured models/clients and fallbacks. |
| `cosineSimilarity` | `missing` | none | Small helper; straightforward to add if desired. |
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
| `simulateReadableStream` | `missing` | none | JS stream test helper; likely not central for Swift, but could map to `AsyncThrowingStream` test utilities. |
| `smoothStream` | `missing` | none | Streaming text smoothing helper is not represented. |
| `generateId` | `missing` | none | Small utility; decide whether public helper belongs in core. |
| `createIdGenerator` | `missing` | none | Same as `generateId`. |
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
| `AI_InvalidToolApprovalError` | `partial` | `AIToolApprovalStatus`, approval request/response flow | Approval validation exists, but no dedicated public error type. |
| `AI_InvalidToolInputError` | `covered` | `AIInvalidToolInputError`, `AITypeValidationError`, `AITool` validation/refinement | Tool argument JSON/schema failures now throw typed tool-input errors. |
| `AI_JSONParseError` | `covered` | `AIJSONParseError` | Direct Swift analog exists. |
| `AI_LoadAPIKeyError` | `covered` | `AIError.missingAPIKey` | Functional analog exists. |
| `AI_LoadSettingError` | `partial` | `AIError.invalidArgument`, provider settings validation | No dedicated setting-load error. |
| `AI_MessageConversionError` | `partial` | provider-specific conversion errors via `AIError.invalidArgument`/warnings | No dedicated public message-conversion error. |
| `AI_NoContentGeneratedError` | `partial` | media/audio/video/text invalid-response paths | No dedicated cross-modal no-content type. |
| `AI_NoImageGeneratedError` | `partial` | image model invalid-response paths | No dedicated public type. |
| `AI_NoTranscriptGeneratedError` | `partial` | transcription invalid-response paths | No dedicated public type. |
| `AI_NoVideoGeneratedError` | `partial` | video invalid-response paths | No dedicated public type. |
| `AI_NoSpeechGeneratedError` | `partial` | speech invalid-response paths | No dedicated public type. |
| `AI_NoObjectGeneratedError` | `covered` | `AIObjectGenerationError` with `kind` and `strategy` | Swift groups object/array/enum/json failures into one typed error. |
| `AI_NoOutputGeneratedError` | `covered` | `AINoOutputGeneratedError`, `AIObjectGenerationError` | The v6-style `Output` stream mapper now has a dedicated no-output error for streams that finish without final output. Object parsing still uses `AIObjectGenerationError` for invalid generated output. |
| `AI_NoSuchModelError` | `covered` | `AIError.unsupportedModel` | Functional analog exists. |
| `AI_NoSuchProviderError` | `covered` | `AIProviderRegistryError.noSuchProvider` | Direct registry analog exists. |
| `AI_NoSuchToolError` | `covered` | `AINoSuchToolError` | Local tool loops now throw a typed error when the model asks for an unavailable non-provider-executed tool. |
| `AI_RetryError` | `covered` | `AIRetryError`, `AIRetryErrorReason` | Direct Swift analog exists. |
| `AI_ToolCallNotFoundForApprovalError` | `partial` | approval flow validation | No dedicated public type. |
| `AI_ToolCallRepairError` / `ToolCallRepairError` | `covered` | `AIToolCallRepairError`, `AITool.refineArguments` | Swift maps the existing argument-refinement hook to a typed tool-call repair failure. |
| `AI_TooManyEmbeddingValuesForCallError` | `partial` | provider/model preflight errors via `AIError.invalidArgument` | Behavior is tested for providers, but no dedicated public error. |
| `AI_TypeValidationError` | `covered` | `AITypeValidationError`, `AIJSONSchemaValidator`, `AIObjectGenerationError.kind == .schemaValidation` | Schema validation now has a standalone public type-validation error, while object generation continues to wrap schema failures in `AIObjectGenerationError`. |
| `AI_UIMessageStreamError` | `covered` | `AIUIMessageStreamError` | Used for UI message validation and stream-reduction failures. |
| `AI_UnsupportedFunctionalityError` | `partial` | `AIError.unsupportedModel`, `AIWarning(type: "unsupported", ...)`, provider invalid-argument paths | Unsupported features are represented, but not as a dedicated public error class. |

## Recommended Next Passes

1. Decide whether SwiftAISDK wants exact v6 API names for small helpers:
   `cosineSimilarity`, `generateId`, `createIdGenerator`, and maybe
   `simulateReadableStream`.
2. Continue polishing the new `AIOutput` surface where it proves useful:
   document examples and consider array `elementStream` ergonomics. The
   `choice/json` factories already propagate `name` and `description` as
   provider hints.
3. Build object-generation session state over the existing `Output` streaming
   surface. Agent-specific UI streams can sit on the same reducer and transport
   contracts.
4. Continue typed-error parity only where it improves Swift diagnostics. The
   first middle-path batch now covers API calls, type validation, no-output,
   no-such-tool, invalid tool input, and tool-call repair. Remaining candidates
   are approval-specific errors and narrower media no-content errors.

## SwiftUI UI Layer Candidates

The AI SDK UI reference is web-framework oriented, but several ideas map well
to SwiftUI. These are not intended as direct ports of React/Svelte/Vue hooks;
they are candidate Swift-native product surfaces for a future SwiftUI layer.

| Upstream UI idea | SwiftUI candidate | Priority | Notes |
| --- | --- | --- | --- |
| `useChat` | `AIChatSession` | done | Combine-backed `ObservableObject` for iOS 15/macOS 12+ that manages `messages`, `status`, `error`, `sendMessage`, replacement, `regenerate`, `stop`, `resumeStream`, `addToolOutput`, and `addToolApprovalResponse` over `AIChatTransport`. Uses `ready/submitted/streaming/error` status names to mirror upstream. |
| `UIMessage` and message parts | `AIUIMessage`, `AIUIMessagePart`, metadata/data parts | done | Core render-message model exists without depending on SwiftUI/Observation. |
| `convertToModelMessages` | `convertToModelMessages` | done | Converts supported `AIUIMessage` parts into `AIMessage` history for model calls; render-only parts are ignored, unsupported URL files fail with `AIUIMessageStreamError`. |
| `readUIMessageStream` / UI stream reducer | `AIUIMessageStreamReducer` | done | Converts `LanguageStreamPart` into stable UI message snapshots, so UI layers do not hand-roll streaming assembly. |
| `useObject` | `@Observable` `AIObjectGenerationSession<Output>` | P2 | Wrap `streamObject` for SwiftUI with `partialObject`, `object`, `isStreaming`, `error`, `submit`, and cancellation. Useful for forms, inspectors, and structured assistant panels. |
| `DirectChatTransport` | `AIChatTransport`, `AIChatTransportRequest`, `AIChatRequestOptions`, `DirectAIChatTransport` | done | In-process transport streams `AIUIMessage` snapshots from `AI.streamText`, supports tool-loop options, request defaults, aborts, retry/timeout/telemetry, and reasoning/source/finish filters. Leave room for an `HTTPChatTransport` later when an app talks to its own backend. |

### Not Worth Directly Porting

| Upstream UI idea | Decision | Reason |
| --- | --- | --- |
| `useCompletion` | `defer` | Most SwiftUI completion use cases can be handled by a small view model over `streamText`; add only if repeated app code proves the need. |
| `createUIMessageStreamResponse` | `out of scope candidate` | Web response helper; not useful for local SwiftUI unless SwiftAISDK grows a server-side Swift story. |
| `pipeUIMessageStreamToResponse` | `out of scope candidate` | Node/server response helper; same rationale as above. |
| `InferUITools` / `InferUITool` | `out of scope` | TypeScript inference helpers with no direct Swift equivalent. |

### Suggested Build Order

1. Add `AIObjectGenerationSession<Output>` after the chat state model settles.
2. Consider agent-specific UI stream wrappers on top of `AIUIMessageStreamReducer`.
