# Product Gap Audit

Snapshot date: 2026-06-01
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
  `streamText`, and `streamObject`; `streamText` and `streamObject` also emit
  abort events when the consumer cancels the stream. Step/tool execution events
  exist for `generateText` and `streamText` tool loops, with per-call or globally
  registered integrations. `AIObjectGenerationCallbacks` now mirrors upstream's
  object lifecycle callbacks for `generateObject` and `streamObject`.
  `AIWarningLogging` now mirrors upstream warning logging controls with default,
  custom, and disabled logger modes. Telemetry integrations can now wrap
  language model calls and tool execution with upstream-style execute hooks.
  `AIAbortController`/`AIAbortSignal` now provide a Swift-native equivalent of
  upstream request `abortSignal`, with facade retry sleeps, stream wrappers,
  `AIHTTPRequest`, `URLSessionTransport`, OpenAI-compatible model calls, Google
  Generative AI, Google Vertex, Amazon Bedrock, file upload polling, media
  polling/download helpers, native audio polling flows, MCP dynamic tool calls,
  and MCP HTTP requests honoring it. SDK-managed media/file URL downloads now
  validate through `validateDownloadURL(...)`, matching upstream
  provider-utils protection against localhost, private IP, link-local/cloud
  metadata, unsafe schemes, and IPv4-mapped private IPv6 targets. The shared
  download helper also validates `AIHTTPResponse.url` so URLSession redirects
  cannot bypass the guard, and `AIHTTPRequest.maxResponseBytes` lets
  URLSession-backed downloads enforce upstream's default 2 GiB ceiling while
  reading bytes incrementally. Media type helper parity now covers
  provider-utils signature detection, extension mapping, and full media type
  resolution; Google GenerateContent and Interactions use it to turn top-level
  inline media types into full IANA media types before sending requests. Shared
  header helper parity now covers normalization, combining, and user-agent
  suffix construction; broad provider header-casing migration remains staged so
  existing Swift request assertions do not churn all at once. JSON parsing
  parity now routes `decodeJSONBody(...)` through a secure parser that rejects
  upstream's forbidden prototype-pollution keys and exposes parse/safe-parse
  helpers for provider and facade code. Provider reference helper parity now
  covers detecting provider-reference records, resolving provider-specific IDs,
  and typed missing-reference errors for uploaded file and skill results.
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
  streaming parse/schema/decode failures. Strict OpenAI-compatible and Cerebras
  structured outputs now run the upstream provider-utils
  `additionalProperties: false` normalization over object schemas unless
  `strictJsonSchema` is explicitly disabled. Mistral now maps standard sampling,
  seed, JSON response formats, reasoning effort, function tools, and tool choice
  to native chat requests, returns unsupported warnings for settings the
  provider ignores, preserves response metadata, forwards abort signals, and
  emits stream-start plus text/reasoning lifecycle parts. Its structured output
  pass covers native `response_format` requests, including `json_schema`,
  `json_object`, `structuredOutputs`, `strictJsonSchema`, and the upstream JSON
  system instruction for no-schema JSON calls. Groq now maps
  standard JSON response formats to native `json_schema`/`json_object`
  requests, keeps `structuredOutputs`/`strictJsonSchema` as control options
  instead of leaking them into the provider body, maps top-level
  seed/frequency/presence/reasoning settings, preserves response metadata,
  forwards abort signals, emits text/reasoning stream lifecycle parts, and
  returns upstream unsupported warnings for `topK`, schema output with
  structured outputs disabled, and unsupported provider-defined tools.
  DeepSeek now requests `json_object`, injects the upstream JSON
  system instruction or schema instruction, returns compatibility and
  unsupported-setting warnings, maps nested `deepseek` provider options plus
  top-level reasoning/frequency/presence settings, preserves
  response/provider metadata, forwards abort signals, emits text/reasoning
  stream lifecycle parts, and sends OpenAI-style function tools/tool choice.
  Google GenerateContent and Google
  Vertex now map standard JSON response formats into
  `generationConfig.responseMimeType` and `generationConfig.responseSchema`,
  using the same JSON-Schema-to-OpenAPI conversion path as Google function
  tools and honoring `structuredOutputs: false`. Google Interactions now maps
  standard JSON response formats into `response_format` text entries, appends
  provider-defined response-format entries, and warns while dropping call-level
  structured output when an agent is selected. Perplexity now maps standard
  JSON response formats into native `response_format.type=json_schema`
  requests, keeps Perplexity-specific options scoped, returns upstream-style
  warnings for unsupported call settings, preserves response/provider
  metadata including usage/cost/images, forwards abort signals, and emits
  text stream lifecycle parts.
  Hugging Face Responses now maps standard JSON response formats into
  `text.format.type=json_schema`, honors `strictJsonSchema`, returns upstream
  unsupported-setting warnings, preserves response metadata, and emits
  v4-shaped stream lifecycle parts for text, reasoning, and tool inputs.
  Cohere chat now maps v4 sampling settings, `response_format.type=json_object`,
  provider-scoped thinking options, function tools, and tool choice into the
  native `/v2/chat` request, returns reasoning text, preserves response
  metadata, forwards abort signals, and emits stream-start plus text/reasoning
  lifecycle parts.
  Richer provider-specific structured-output passes still need follow-up work.
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
- `TokenUsage` now keeps richer upstream-style cache/read, text/reasoning, and
  raw usage slots in addition to the compact input/output/total counters, but
  providers still need to fill those fields where upstream exposes them.
- `LanguageStreamPart` has v4-shaped lifecycle cases, but provider population
  is still uneven: OpenAI-compatible chat/responses, Anthropic, Google
  GenerateContent/Interactions, native Bedrock, Gateway, Mistral, Cohere,
  Groq, DeepSeek, Cerebras, and Alibaba streams now emit tool input
  start/delta/end parts alongside final tool calls. OpenAI-compatible chat and
  Perplexity emit text lifecycle parts; OpenAI-compatible chat, Mistral,
  Cohere, Groq, DeepSeek, Cerebras, Alibaba, and Hugging Face Responses also emit
  text/reasoning start/delta/end parts. Remaining native language stream
  parsers should get the same treatment where upstream exposes equivalent
  events.
- `TranscriptionResult` now has text, raw JSON, segments, language, duration,
  warnings, request/response info, and provider metadata, but provider passes
  still need to keep filling those fields wherever upstream exposes them.
- `SpeechResult`, `VideoGenerationResult`, `RerankingResult`,
  `FileUploadResult`, and `SkillUploadResult` now have the shared slots needed
  for upstream parity, but still need provider-by-provider population passes
  where upstream exposes additional provider-specific details beyond the shared
  request/response metadata.

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
  metadata, streamed errors, and opt-in raw chunks. Provider implementations
  now gate raw stream chunks behind `includeRawChunks`, matching upstream's
  default-no-raw behavior. The shared OpenAI-compatible layer now carries
  upstream-style response headers and raw JSON bodies through
  `AIResponseMetadata` for text, stream, embedding, image, transcription, and
  speech calls; Anthropic language and Google/Vertex language plus embedding
  models now do the same for their native response headers/bodies and stream
  response metadata. OpenAI-compatible chat streams now also emit v4-shaped
  text/reasoning lifecycle parts while retaining legacy deltas for existing
  consumers. Google Generative AI image/video/files and Google Vertex
  image/video now also preserve native response metadata, including fallback
  timestamps for responses without provider-created times. Native audio and
  transcription models for Deepgram, ElevenLabs, LMNT, Hume, fal, AssemblyAI,
  Rev.ai, Gladia, and Groq now preserve response metadata too, using the final
  provider result response for submit/poll flows. Native image/video models for
  Replicate, fal, Fireworks, DeepInfra, TogetherAI, xAI, QuiverAI, and generic
  JSON media wrappers now preserve response metadata as well; submit/download
  flows keep the provider submit response as metadata rather than the
  SDK-managed asset download. File and skill clients now preserve response
  metadata for OpenAI-compatible multipart files, Google resumable files, xAI
  files, and OpenAI/Anthropic skill uploads; those upload results also preserve
  safe request metadata for file paths, media types, byte lengths, display
  titles, and scalar options without storing raw uploaded bytes. File uploads
  now also return upstream-style unsupported warnings when a provider ignores
  options such as `displayName` or `purpose`, instead of dropping them
  silently. Native embedding and reranking models for OpenAI-compatible,
  Google Generative AI, Google Vertex, Cohere, Voyage, Mistral, Baseten,
  Gateway, Amazon Bedrock, TogetherAI, and generic JSON reranking wrappers now
  preserve safe request metadata for their provider JSON bodies alongside
  provider response headers and raw JSON bodies. Native image/video models now
  also preserve safe request metadata for provider JSON bodies or safe request
  snapshots, omitting inline/base64 media payloads while retaining prompt,
  size/aspect, count, duration, URL, and option fields. Native transcription
  models now
  map upstream-style segments,
  language, and duration for Deepgram, ElevenLabs, Groq/OpenAI-compatible
  verbose JSON, AssemblyAI, Rev.ai, Gladia, fal, Gateway, and generic JSON
  transcription wrappers. OpenAI-compatible chat, completion, and Responses
  language models now also lift upstream provider metadata such as prediction
  token details, logprobs, response IDs, and service tiers into
  `providerMetadata` for both generate and stream finishes. Native speech
  models now populate request metadata for their provider JSON bodies, and
  OpenAI-compatible/Groq multipart transcription preserves safe form metadata
  without storing raw audio bytes. The AI facade also fills safe fallback request
  metadata for custom embedding, media, audio, reranking, file, and skill models
  or clients that return empty metadata, keeping product-level telemetry
  consistent across built-in and user-provided implementations. Mistral and
  Cohere chat now preserve native response metadata and stream response metadata
  for language calls, and follow the richer v4 stream lifecycle for text and
  reasoning chunks.
  Follow-up passes should keep filling richer metadata and lifecycle fields
  consistently across the remaining native providers.

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
- Google GenerateContent now preserves `thoughtSignature` provider metadata on
  function-call parts and replays it on assistant tool-call history, matching
  upstream's requirement for live Gemini tool loops.
- Tool streams for OpenAI-compatible chat/responses, Anthropic, Google
  GenerateContent/Interactions, native Bedrock, Gateway, Mistral, Cohere,
  Groq, DeepSeek, Cerebras, and Alibaba now emit upstream-style
  `LanguageStreamPart.toolInputStart`, `.toolInputDelta`, and `.toolInputEnd`
  parts in addition to legacy `.toolCallDelta` and final `.toolCall` parts, so
  consumers can observe argument assembly without waiting for the final tool
  call.
- Groq chat now follows the upstream native model path more closely: top-level
  `seed`, `frequencyPenalty`, `presencePenalty`, and reasoning map into the
  OpenAI-compatible Groq request, generate/stream calls preserve response
  metadata and forward abort signals, streams emit start/delta/end lifecycle
  parts for reasoning and text, and unsupported `topK`/provider-tool warnings
  are returned to callers.
- Cerebras chat now uses the upstream OpenAI-compatible function-tool wire
  shape, maps call-level `responseFormat` into native structured outputs,
  forwards abort signals, preserves response/provider metadata, and emits
  text/reasoning stream lifecycle parts while keeping the upstream mixed
  structured-output/tool-call normalization.
- DeepSeek chat now mirrors the upstream native model path more closely:
  top-level reasoning, `frequencyPenalty`, `presencePenalty`, unsupported
  `topK`/`seed` warnings, JSON response-format injection, function tools/tool
  choice, response/provider metadata, abort signals, and text/reasoning stream
  lifecycle parts are covered in a dedicated provider test file.
- Perplexity language now follows the upstream native model path more closely:
  mapped finish reasons, response/provider metadata for usage, cost, and
  images, first-chunk response metadata and citations, abort signals, and
  text stream lifecycle parts are covered by focused tests.
- MoonshotAI chat now follows its upstream OpenAI-compatible subclass more
  closely: provider-scoped thinking and reasoning-history options are
  transformed, streaming usage is requested by default, Moonshot cache and
  reasoning usage details populate rich `TokenUsage` fields with raw usage
  retained, streams emit text lifecycle parts, and generate/stream abort
  propagation is covered by focused tests.
- Baseten now follows its upstream provider split more closely:
  `ProviderSettings.modelURL` represents dedicated model endpoints, chat uses
  the Model API base by default or dedicated `/sync/v1` URLs with the upstream
  placeholder model ID, `/predict` and plain `/sync` chat endpoints are
  rejected, embeddings require `/sync` or `/sync/v1`, nested Baseten embedding
  options are stripped before transport, and chat/stream/embedding abort
  propagation is covered by focused tests.
- Alibaba chat now follows its native upstream model more closely: top-level
  sampling, seed, reasoning budget, JSON response format, function tools/tool
  choice, assistant tool-call history, tool-result messages, response metadata,
  abort signals, unsupported `frequencyPenalty` warnings, and text/reasoning
  stream lifecycle parts are covered by focused tests.
- `MCPClient` now covers the first official `@ai-sdk/mcp` bridge: initialize,
  `tools/list`, `tools/call`, cached `toolsFromDefinitions`, HTTP/custom
  transports, and conversion of MCP tool definitions into dynamic `AITool`
  values with MCP provider metadata. It also covers `resources/list`,
  `resources/read`, `resources/templates/list`, `prompts/list`, and
  `prompts/get`, plus the client-side core for incoming `elicitation/create`
  requests through `MCPElicitationRequest` and `MCPElicitResult`. `AITool` now
  has an upstream-style `toModelOutput` hook, and MCP tools use it to convert
  MCP text/image/unknown content into model-facing output while preserving the
  raw MCP call result. `AIToolExecutionContext` now mirrors upstream tool
  execution options for cancellation: `AI.generateText`/`AI.streamText` pass the
  request `AIAbortSignal` into local tool execution, and MCP dynamic tools
  forward it through `MCPRequestOptions` to `MCPHTTPTransport` requests.
  `MCPHTTPTransport` now also follows the upstream Streamable HTTP shape for
  protocol-version headers, `mcp-session-id` persistence, DELETE session
  termination, JSON response parsing, buffered SSE fallback parsing, and true
  streaming SSE request/response handling when the underlying transport conforms
  to `AIStreamingTransport`. `URLSessionTransport` now provides that streaming
  transport path. Inbound SSE also tracks event IDs and reconnects with
  `last-event-id` after stream failures. MCP transports can now take an
  `MCPOAuthProvider`, attach bearer tokens, invalidate stale tokens on 401
  responses, parse `resource_metadata` from `WWW-Authenticate`, run an
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
- Mock transport tests prove wire shape, and the opt-in live smoke suite now
  covers representative first-party text generation, text streaming, executable
  generate/stream tool loops, and embeddings.
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
   facade retries honor `Retry-After` on retryable status codes. `streamText`
   and `streamObject` now record consumer cancellation as telemetry `abort`
   instead of `error`. `AIAbortController`/`AIAbortSignal` are now available on
   core request structs and `AIHTTPRequest`; OpenAI-compatible providers, Google
   Generative AI, Google Vertex, Amazon Bedrock, file clients, media
   polling/download flows, native audio polling flows, MCP dynamic tool calls,
   and MCP HTTP requests forward them to transport. Provider-returned and
   user-provided URLs fetched by SDK download fallbacks now pass through
   `validateDownloadURL(...)` before transport execution and validate the final
   response URL after redirects when the transport exposes it. `downloadURL(...)`
   also sets `maxResponseBytes`, with URLSession checking `Content-Length` early
   and aborting incremental reads that exceed the limit. Next passes should keep
   new provider and transport helpers covered by propagation tests.

4. **Facade pass 3: telemetry.**
   First telemetry slices are in place with `AITelemetryOptions`,
   `AITelemetryIntegration`, `AITelemetry.register(...)`, lifecycle events for
   non-streaming facade operations including `generateObject`,
   start/end/error/abort events for `streamText` and `streamObject`, and
   step/tool execution events for `generateText` and `streamText` tool loops.
   Events carry call IDs,
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
