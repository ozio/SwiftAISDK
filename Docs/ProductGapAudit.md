# Product Gap Audit

Snapshot date: 2026-05-31
Upstream commit: `ab6d66482d31afe15f4973a51c5f7cfa09c92ea6`

This audit looks at the package from the top down. The provider ports are broad,
but the product is not yet equivalent to the AI SDK experience because the
Swift package mostly exposes low-level provider models.

## Current Shape

The Swift package is a library-only SwiftPM package with one product,
`SwiftAISDK`. Public APIs are concentrated in:

- `Core.swift`: model protocols, request/result structs, stream parts, warnings.
- `ProviderRegistry.swift`: provider factories.
- `ProviderCapabilityMatrix.swift`: machine-readable provider/package
  capability coverage.
- `Models/*`: provider-specific request/response implementations.
- `Docs/UpstreamSync.md`: provider sync playbook.

The provider registry has broad coverage of official provider packages from the
upstream repository:

```text
alibaba, amazon-bedrock, anthropic, anthropic-aws, assemblyai, azure, baseten,
black-forest-labs, bytedance, cerebras, cohere, deepgram, deepinfra, deepseek,
elevenlabs, fal, fireworks, gateway, gladia, google, google-vertex, groq,
huggingface, hume, klingai, lmnt, luma, mistral, moonshotai, open-responses,
openai, openai-compatible, perplexity, prodia, quiverai, replicate, revai,
togetherai, vercel, voyage, xai
```

That means the biggest missing work is no longer "add the next provider". The
larger gaps are in the SDK layer above providers and in the fidelity of the core
protocol contract.

## Serious Gaps

### 1. AI SDK facade layer is still partial

Upstream `packages/ai/src/index.ts` exports product-level APIs:

```text
generateText, streamText, generateObject, streamObject, embed, embedMany,
generateImage, experimental_generateVideo, experimental_generateSpeech,
experimental_transcribe, rerank, uploadFile, uploadSkill,
middleware wrappers, prompt conversion, telemetry, UI streams, agents
```

The Swift package now has an `AI` facade for the common calls, but deeper
product behavior still trails upstream.

Impact:

- Facade calls now have a retry policy for transient errors, a per-attempt
  timeout on `AIRetryPolicy`, and direct stream timeouts on `streamText` and
  `streamObject`. HTTP `Retry-After` headers are now preserved from provider
  responses and honored by facade retries, including stream retries before the
  first emitted part. A Swift telemetry surface now emits start, retry, end,
  and error events for non-streaming facade calls plus `generateObject`,
  `streamText`, and `streamObject`, and step/tool execution events for
  `generateText` and `streamText` tool loops, with per-call or globally
  registered integrations. `AIObjectGenerationCallbacks` now mirrors upstream's
  object lifecycle callbacks for `generateObject` and `streamObject`.
  `AIWarningLogging` now mirrors upstream warning logging controls with default,
  custom, and disabled logger modes. Telemetry integrations can now wrap
  language model calls and tool execution with upstream-style execute hooks.
  Richer cancellation controls still need follow-up work.
- Tool execution exists for `generateText` and `streamText`, including
  upstream-style stop conditions and per-step request/model/tool preparation,
  but richer schema validation, provider-defined tool wrapping, and UI-facing
  approval plumbing still need follow-up work.
- Object generation exists for `Decodable` results, and `streamObject` can now
  stream JSON text deltas, best-effort partial JSON objects, typed partial
  values when the current JSON can decode, and a final decoded object.
  Non-streaming and streaming array, enum, and no-schema JSON strategies are
  also available. Object parse/schema/decode failures now throw
  `AIObjectGenerationError`, and `AIObjectSchema`/`AIJSONSchema` provide a
  reusable schema-adapter surface for object and array outputs.
  `AIJSONInstruction` can inject upstream-style JSON instructions as an opt-in
  fallback for providers without native structured-output support.
  `AIObjectGenerationCallbacks.onError` now fires for both non-streaming and
  streaming parse/schema/decode failures. Richer provider-specific
  structured-output passes still need follow-up work.
- `customProvider(...)` exists as a Swift-native composition layer for local
  model maps, fallback providers, and files/skills clients.
  `createProviderRegistry(...)` also routes combined IDs such as
  `provider:model` through registered Swift providers. `AIDefaultProvider` and
  the string-model overloads on the `AI` facade now mirror upstream global
  default-provider model resolution.
- Model middleware now covers the upstream wrapper layer for language, image,
  and embedding models: request transforms, operation wrappers,
  provider/model ID overrides, `defaultSettingsMiddleware` for language
  defaults, `defaultEmbeddingSettingsMiddleware` for embedding defaults,
  JSON/reasoning extraction, simulated streaming, and tool input-example
  description transforms. `wrapProvider(...)` can apply all three middleware
  families, and `createProviderRegistry(...)` can apply language and image
  middleware to routed models. Telemetry now has lifecycle events and execute
  wrappers for model/tool spans; deeper middleware-specific trace metadata
  remains follow-up product work.

Recommendation:

Continue growing the `AI` facade above provider models: cancellation,
timeouts, telemetry, and richer schema/object generation should be separate
product rounds.

### 2. Core model contract is lossy compared with upstream v4

Upstream provider v4 model contracts carry richer call options and richer
results. Examples:

- `LanguageModelV4CallOptions` includes `topK`, penalties, `seed`,
  `responseFormat`, `reasoning`, `includeRawChunks`, `abortSignal`, structured
  `providerOptions`, tool choice, and typed function/provider tools.
- `LanguageModelV4StreamPart` has block lifecycle events (`text-start`,
  `text-end`, reasoning start/end), tool input start/delta/end, tool result,
  tool approval requests, files, reasoning files, custom content,
  `stream-start` warnings, response metadata, finish provider metadata, raw
  chunks, and streamed errors.
- Image, speech, transcription, embedding, reranking, file, and skill results
  carry response metadata, provider metadata, warnings, usage, request bodies,
  headers, timestamps, and sometimes segment-level output.

The Swift contract keeps only a compact subset. For example:

- `LanguageModelRequest` has temperature, topP, maxOutputTokens, stopSequences,
  tools as raw `JSONValue`, `extraBody`, and headers.
- `LanguageStreamPart` has text/reasoning deltas, tool-call deltas/final calls,
  source, metadata, raw, and finish, but no stream-start warnings, response
  metadata event, tool input lifecycle, tool results, approval requests, files,
  streamed errors, or per-part provider metadata.
- `TranscriptionResult` only returns text and raw JSON; upstream has segments,
  language, duration, warnings, request/response info, and provider metadata.
- `SpeechResult`, `VideoGenerationResult`, `RerankingResult`, and
  `FileUploadResult` expose much less provider metadata than upstream.

Impact:

- Some provider behavior cannot be faithfully ported without inventing ad hoc
  side channels.
- Stream parity is capped even when provider implementations parse richer data.
- More warning work will continue to leak into special cases unless result
  shapes consistently support upstream result fields.

Recommendation:

Introduce v4-shaped Swift core structs before expanding deeper provider parity:

- richer request options (`topK`, penalties, seed, response format, reasoning,
  providerOptions, abort/cancellation);
- richer stream parts with start/end, response metadata, stream-start warnings,
  tool results/approval, file/custom/error parts, and provider metadata;
- shared response metadata and provider metadata on every result type;
- warnings on every result type that upstream can warn from.

Progress:

- First contract slice added: language requests now carry v4-style sampling,
  response-format, reasoning, raw-chunk, tool-choice, and provider-options
  fields; every model request has a `providerOptions` slot; result types now
  carry shared warnings/provider metadata/response metadata where upstream v4 can
  report them; language streams can represent lifecycle parts, stream-start
  warnings, tool results, tool approval requests, files, custom parts, response
  metadata, and streamed errors. Provider implementations still need follow-up
  passes to populate these fields consistently.

### 3. Tool execution is represented as JSON, not as a Swift product surface

Provider-defined tools exist as builders such as `OpenAITools`,
`AnthropicTools`, `GoogleTools`, `GatewayTools`, `GroqTools`, and `XAITools`.
Generic low-level provider requests can still pass raw JSON tools through
`LanguageModelRequest.tools`, but the facade now also exposes typed executable
tools.

Impact:

- Upstream-style dynamic tools are now represented by `AITool.dynamic(...)`;
  richer typed output/error surfaces are still missing. Tool input refinement
  exists through `AITool.refineArguments`, and refined tool arguments now pass
  through first-pass JSON Schema validation before execution.
- Automatic multi-step execution exists for `AI.generateText` and `AI.streamText`.
- Stop conditions now mirror the upstream `isStepCount`, `isLoopFinished`, and
  `hasToolCall` helpers.
- `prepareStep` now exists as a Swift hook for per-step request/model/tool
  overrides, with accumulated steps and response messages passed into the
  callback.
- `AITool.refineArguments` mirrors upstream `experimental_refineToolInput` for
  validating or normalizing parsed tool arguments before execution.
- `AITool.dynamic(...)` marks runtime-discovered tools while keeping provider
  request schemas in function-tool form, matching upstream `dynamicTool(...)`
  behavior for tool calls, stream parts, results, and follow-up messages.
- Mistral chat message conversion now preserves assistant `tool_calls` and
  serializes follow-up tool messages with `name`, `tool_call_id`, and
  upstream-style `modelOutput ?? result` content, so multi-step Mistral tool
  loops no longer flatten tool history to empty text.
- `MCPClient` now covers the first official `@ai-sdk/mcp` bridge: initialize,
  `tools/list`, `tools/call`, cached `toolsFromDefinitions`, HTTP/custom
  transports, and conversion of MCP tool definitions into dynamic `AITool`
  values with MCP provider metadata. It also covers `resources/list`,
  `resources/read`, `resources/templates/list`, `prompts/list`, and
  `prompts/get`, plus the client-side core for incoming `elicitation/create`
  requests through `MCPElicitationRequest` and `MCPElicitResult`. `AITool` now
  has an upstream-style `toModelOutput` hook, and MCP tools use it to convert
  MCP text/image/unknown content into model-facing output while preserving the
  raw MCP call result. `MCPHTTPTransport` now also follows the upstream
  Streamable HTTP shape for protocol-version headers, `mcp-session-id`
  persistence, DELETE session termination, JSON response parsing, buffered SSE
  fallback parsing, and true streaming SSE request/response handling when the
  underlying transport conforms to `AIStreamingTransport`. `URLSessionTransport`
  now provides that streaming transport path. Inbound SSE also tracks event IDs
  and reconnects with `last-event-id` after stream failures. MCP transports can
  now take an `MCPOAuthProvider`, attach bearer tokens, invalidate stale tokens
  on 401 responses, parse `resource_metadata` from `WWW-Authenticate`, run an
  authorization recovery hook, and retry the original request once.
  `MCPStdioTransport` now covers the local-server `@ai-sdk/mcp/mcp-stdio`
  path on macOS/Linux with command/args/env/cwd process spawning,
  newline-delimited JSON-RPC over stdin/stdout, response matching, and incoming
  server requests answered through `MCPClient`.
  `MCPOAuthDiscovery` now mirrors upstream OAuth metadata discovery for MCP
  resources: it discovers protected-resource metadata, tries path-aware URLs
  before root fallback, resolves OAuth/OIDC authorization-server metadata, and
  rejects OIDC metadata that cannot support S256 PKCE. It also retries metadata
  discovery without the MCP protocol header after transport failures, matching
  upstream's browser/CORS fallback behavior.
  `MCPOAuth` now covers the next helper layer: PKCE authorization URL creation,
  authorization-code exchange, refresh-token exchange with refresh-token
  preservation, OAuth server error parsing, client authentication method
  selection, dynamic client registration, and full provider-flow orchestration
  through `MCPOAuthClientProvider`, including resource selection, callback state
  validation, redirect start, token refresh, credential invalidation/retry for
  OAuth errors, authorization-code exchange, and custom token endpoint client
  authentication hooks for assertion/proprietary auth schemes.
- `toolApproval` exists on `AI.generateText` and `AI.streamText` for
  Swift-executed tools. It supports automatic approve/deny stages and stops the
  loop for `.userApproval`, matching the first upstream approval control flow.
- OpenAI Responses now maps provider-executed MCP approval requests into
  `AIToolApprovalRequest` values and sends provider-executed
  `AIToolApprovalResponse` values back as `mcp_approval_response` items,
  including `store: false` and duplicate-response handling.
- Tool-result messages are now first-class in core, but provider passes should
  keep tightening wire-format parity.

Recommendation:

Build on the new `AITool` abstraction: add richer typed validation errors,
provider-defined tool schema adapters, richer provider-native handling for
multimodal `modelOutput`, richer stream tool lifecycle events, and
provider-executed approval response mapping for non-OpenAI providers that expose
an equivalent native wire format. Keep
provider-defined tools as specialized `AITool` values instead of plain JSON
where possible.

### 4. Object generation and schema validation are partial

Upstream has `generateObject`, `streamObject`, schema adapters, JSON repair, and
object output strategies. Swift now has `AI.generateObject` for `Decodable`
types and `AI.streamObject` for streaming text deltas, partial `JSONValue`
objects, typed partial `Decodable` values, and a final decoded object, backed by
provider JSON response-format hints. Array, enum, and no-schema JSON strategies
are exposed as both non-streaming and streaming variants:
`generateObjectArray`, `streamObjectArray`, `generateEnum`, `streamEnum`,
`generateJSON`, and `streamJSON`. `AIObjectSchema` and `AIJSONSchema` now let
callers pass reusable schema adapters instead of raw `JSONValue` schemas, and
`AIJSONInstruction` can inject upstream-style JSON instructions for fallback
providers that ignore native response-format hints.

Impact:

- Basic object generation, partial JSON object streaming, typed partial object
  streaming, final-object streaming, final JSON Schema validation, and typed
  object-generation failures are available at product level.
- Streaming array/enum/no-schema strategies and first-pass schema adapter
  protocols are now available.
- Upstream-style JSON instruction injection is available as an opt-in fallback.
- Provider-specific schema support has first end-to-end coverage, but needs
  broader provider passes.

Recommendation:

Extend object generation beyond the first Swift-native slices: add
provider-specific structured-output parity and richer schema adapter
integrations.

### 5. Product reality is not fully gated yet

The README, upstream sync guide, and provider capability matrix now make the
current product shape visible, but the verification gates are still uneven.

Impact:

- Provider breadth is visible through `AIProviderCapabilities`, but matrix rows
  are now rendered from that source and guarded by a drift test. The remaining
  risk is that a provider pass forgets to update the source inventory itself.
- Mock transport tests prove wire shape, but live provider health is only covered
  by an opt-in smoke suite for representative first-party providers.
- A user can start from the README and generated matrix, but there is not yet a
  per-provider cookbook.

Recommendation:

Keep turning documentation into executable product evidence:

- keep the markdown capability matrix generated from `AIProviderCapabilities`;
- expand live smoke coverage by provider family without making it default CI;
- add per-provider quick-start snippets only where the SDK surface differs;
- keep `UpstreamSync.md` as a short manifest/checklist, with detailed evidence
  in the matrix and tests.

Progress:

- `AIProviderCapabilities.markdownDocument()` now renders
  `Docs/ProviderCapabilityMatrix.md`, and
  `providerCapabilityMatrixDocumentationMatchesGeneratedMarkdown()` fails if the
  checked-in document drifts from source.

## Recommended Next Rounds

1. **Core v4 result/stream contract pass.**
   First slice is in place. Continue wiring providers into the richer fields and
   add missing request/result details where upstream tests prove concrete
   behavior.

2. **Facade pass 1: direct wrappers.**
   Add `AI.generateText`, `AI.streamText`, `AI.embed`, `AI.embedMany`,
   `AI.generateImage`, `AI.transcribe`, `AI.generateSpeech`,
   `AI.generateVideo`, and `AI.rerank` as thin wrappers over existing model
   protocols.
   First slice is in place, including upload-file and upload-skill wrappers plus
   stream-side local tool execution and `customProvider(...)` for local model
   maps plus fallback providers. `createProviderRegistry(...)` now covers
   upstream-style `provider:model` routing and string model IDs through
   `AIDefaultProvider`. Follow-up work should add richer result objects,
   cancellation/timeout behavior, and streaming orchestration.

3. **Facade pass 2: retries and cancellation.**
   First retry slice is in place with `AIRetryPolicy` and default
   `maxRetries: 2` for product-level calls. Non-streaming facade calls can now
   set a per-attempt `timeoutNanoseconds` on `AIRetryPolicy`, and `streamText`
   plus `streamObject` accept direct stream timeouts. Streams retry retryable
   start failures before the first emitted part and do not retry after chunks
   have been yielded. Provider HTTP errors now preserve response headers, and
   facade retries honor `Retry-After` on retryable status codes. Next passes
   should add richer cancellation controls.

4. **Facade pass 3: telemetry.**
   First telemetry slices are in place with `AITelemetryOptions`,
   `AITelemetryIntegration`, `AITelemetry.register(...)`, lifecycle events for
   non-streaming facade operations including `generateObject`, start/end/error
   events for `streamText` and `streamObject`, and step/tool execution events
   for `generateText` and `streamText` tool loops. Events carry call IDs,
   operation IDs, provider/model
   IDs, retry attempts, timing, usage, warnings, metadata, response metadata,
   object lifecycle callbacks for `generateObject` and `streamObject`,
   input/output payloads gated by record flags, and execute wrappers for
   language model calls plus tool execution.

5. **Facade pass 4: warning logging.**
   `AIWarningLogging` mirrors upstream `AI_SDK_LOG_WARNINGS`: non-empty warning
   arrays from facade calls are sent to a default stderr logger, callers can
   install a custom `AIWarningLogger`, and logging can be disabled globally or
   scoped to an async task without removing warnings from result values, stream
   lifecycle parts, or telemetry events. Current coverage includes non-streaming
   facade calls and stream completion logging for `streamText`/`streamObject`.

6. **Tool loop pass.**
   First `generateText` and `streamText` slices are in place with typed
   `AITool`, execute callbacks, step/tool-result messages, streamed tool-result
   parts, upstream-style stop conditions, a Swift `prepareStep` hook, and tool
   argument refinement, dynamic tool marking, first-pass tool approval
   policies, and an MCP client bridge for server-discovered dynamic tools,
   resources, resource templates, prompts, incoming elicitation requests, and
   MCP-style tool model-output conversion and first-pass Streamable HTTP
   session plus streaming semantics. Next passes should add typed validation
   errors, provider-executed approval responses, and richer stream lifecycle
   handling.

7. **Object generation pass.**
   First `AI.generateObject` slice is in place for `Decodable` plus JSON
   schema hints and repair callbacks. `AI.streamObject` now emits text deltas,
   best-effort partial `JSONValue` objects, typed partial `Decodable` values
   when the current partial JSON decodes, and final `Decodable` output.
   Array, enum, and no-schema JSON output strategies now mirror upstream's
   wrapper schemas for both non-streaming and streaming calls, and
   `AIObjectGenerationError` exposes typed parse/schema/decode failures.
   `AIObjectSchema` and `AIJSONSchema` add a first reusable schema-adapter
   surface, and `AIObjectGenerationCallbacks` covers non-streaming and streaming
   object lifecycle hooks including error callbacks. Next passes should add
   provider-specific structured output parity, richer repair telemetry, and
   deeper adapter integrations.

8. **README and capability matrix.**
   README now has a quick-start and facade/tool/object examples. A first
   machine-readable provider capability matrix and opt-in live smoke harness are
   in place. The markdown table is generated from source and guarded by tests.
   Next pass should add deeper provider-option examples.

Provider micro-parity should continue, but it should be the second track. The
first track should now be the SDK facade and core contract, because those change
what provider behavior can even be represented.
