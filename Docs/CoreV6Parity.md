# Core V7 Parity

Snapshot date: 2026-08-31

This document tracks SwiftAISDK against the current AI SDK Core and Errors
reference. It is intentionally high-level: product status belongs in
`PortingStatus.md`, provider package drift belongs in `ProviderVersionLedger.md`,
and provider behavior belongs in focused tests.
Implementation-sensitive UI/chat items are also checked against npm source
snapshots, currently `ai@7.0.85`, `@ai-sdk/provider@4.0.9`,
`@ai-sdk/provider-utils@5.0.34`, and `@ai-sdk/react@4.0.88`.

References:

- <https://ai-sdk.dev/docs/reference/ai-sdk-core>
- <https://ai-sdk.dev/docs/reference/ai-sdk-errors>
- <https://ai-sdk.dev/docs/reference/ai-sdk-ui>

## Latest Core Package Diff Notes

Checked npm package diffs:

- `ai@7.0.77 -> 7.0.85`
- `@ai-sdk/provider@4.0.7 -> 4.0.9`
- `@ai-sdk/provider-utils@5.0.29 -> 5.0.34`
- `@ai-sdk/react@4.0.80 -> 4.0.88`
- `ai@7.0.68 -> 7.0.77`
- `@ai-sdk/provider@4.0.7` (unchanged)
- `@ai-sdk/provider-utils@5.0.27 -> 5.0.29`
- `@ai-sdk/react@4.0.71 -> 4.0.80`
- `ai@7.0.66 -> 7.0.68` (dependency-only)
- `@ai-sdk/react@4.0.69 -> 4.0.71` (dependency-only)
- `ai@7.0.58 -> 7.0.66`
- `@ai-sdk/provider@4.0.7` (unchanged)
- `@ai-sdk/provider-utils@5.0.25 -> 5.0.27`
- `@ai-sdk/react@4.0.61 -> 4.0.69`
- `ai@7.0.48 -> 7.0.58`
- `@ai-sdk/provider@4.0.4 -> 4.0.7`
- `@ai-sdk/provider-utils@5.0.18 -> 5.0.25`
- `@ai-sdk/react@4.0.51 -> 4.0.61`
- `ai@7.0.44 -> 7.0.48`
- `@ai-sdk/provider@4.0.4` (unchanged)
- `@ai-sdk/provider-utils@5.0.16 -> 5.0.18`
- `@ai-sdk/react@4.0.47 -> 4.0.51`
- `ai@7.0.37 -> 7.0.44`
- `@ai-sdk/provider@4.0.3 -> 4.0.4`
- `@ai-sdk/provider-utils@5.0.12 -> 5.0.16`
- `@ai-sdk/react@4.0.40 -> 4.0.47`
- `ai@7.0.31 -> 7.0.37`
- `@ai-sdk/provider-utils@5.0.11 -> 5.0.12`
- `@ai-sdk/react@4.0.34 -> 4.0.40`
- `ai@6.0.208 -> 7.0.31`
- `@ai-sdk/provider@3.0.10 -> 4.0.3`
- `@ai-sdk/provider-utils@4.0.30 -> 5.0.11`
- `@ai-sdk/react@3.0.210 -> 4.0.34`
- `ai@6.0.200 -> 6.0.208`
- `@ai-sdk/provider@3.0.10`
- `@ai-sdk/react@3.0.206 -> 3.0.210`
- `@ai-sdk/provider-utils@4.0.29 -> 4.0.30`
- `@ai-sdk/provider-utils@4.0.30 -> 5.0.1` response size-limit patch

Port decisions:

- `ai@7.0.85`, `@ai-sdk/provider@4.0.9`, and
  `@ai-sdk/provider-utils@5.0.34` extend the Swift public core vertically:
  image results expose their underlying per-call outputs; embedding models can
  declare a UTF-8 byte budget combined with the per-call count limit; Batch V4
  accepts completion webhooks and retains full result content plus validated
  native request counts; and `AIStreamProviderError` preserves provider-owned
  type, code, HTTP status, retryability, and raw data for in-band stream
  failures.
- Manual approval requests retain an optional policy reason. Replayed approved
  calls are revalidated against the current tool schema and signature secret;
  invalid persisted input becomes a model-visible error result so the loop can
  continue without executing it. Object output parsing also avoids treating a
  mixed tool-call finish as terminal structured output while retaining valid
  text when the provider omits a finish reason.
- The current core batch alignment carries the complete language-model option
  surface into provider batches and makes webhook support explicit: Gateway
  forwards its callback URL while direct Anthropic, OpenAI, and xAI batch
  adapters return an unsupported warning. Native counts are exposed only when
  nonnegative values reconcile to the total.
- Canonical-hash preservation for JavaScript `undefined` array slots has no
  Swift `JSONValue` analogue. Stateful/empty-match JavaScript RegExp handling
  in `smoothStream`, React hook updates, and cancellation before a JavaScript
  stitchable stream registers its inner stream are runtime-specific and do not
  add Swift behavior.
- Transient body-read `URLError` values were already retryable in the shared
  Swift retry boundary. Parsed output was already emitted to `streamText` end
  callbacks, and the UI reducer already preserves active parts, so those
  upstream patches require regression evidence rather than new runtime code.
- Typed UI-tool schema conversion, automatic chat submission after a denied
  approval, operation-level UI outcomes, byte-array approval secrets, true
  image request splitting with per-call metadata, and Gateway cost aggregation
  across those split calls remain deferred. They need broader public UI/media
  contracts than the additive `ImageGenerationResult.calls` surface alone.
- `@ai-sdk/react@4.0.88` contains React hook and dependency propagation only;
  SwiftAISDK continues to expose `AIChatSession` rather than React stores.
- `ai@7.0.68 -> 7.0.77` ports every applicable core behavior: automatic tool
  execution now stops after unsafe finish reasons; preliminary tool output can
  be filtered from model-message conversion; in-band `streamObject` errors
  terminate with the provider failure; client approval stops a loop even while
  a provider result is deferred; text/reasoning stream IDs remain unique across
  steps; and `AI.startVideo` / `AI.getVideoStatus` expose direct persisted
  operation calls. Streaming callbacks are nonthrowing Swift closures, so the
  JavaScript callback-rejection failure mode is already impossible. Nullish
  branded-ID UI schema inference is TypeScript-only.
- The WorkflowAgent retry `reset-step` addition is deferred because SwiftAISDK
  has no resumable indexed WorkflowAgent chunk transport or reset-step
  producer; adding a public case without that runtime would not port the
  behavior.
- `@ai-sdk/provider-utils@5.0.29` preserves schema-valued
  `additionalProperties` recursively and normalizes empty generated/streamed
  tool-call IDs. Focused Swift tests cover both. Blob request bodies and
  fetch-less module import are JavaScript runtime concerns.
- `@ai-sdk/react@4.0.80` carries React hook/dependency changes only. SwiftAISDK
  continues to expose its native `AIChatSession`; no React-specific patch is
  applicable. `@ai-sdk/provider@4.0.7` has no version or source drift.
- `ai@7.0.68` and `@ai-sdk/react@4.0.71` contain dependency propagation only;
  their published `src` trees are unchanged from 7.0.66 and 4.0.69.
- The 2026-08-19 provider patch train advances Amazon Bedrock, Azure, Baseten,
  Cerebras, DeepInfra, Fireworks, Gateway, Google, Google Vertex, Hugging Face,
  MCP, OpenAI, OpenAI-compatible, and TogetherAI. Core-facing portable changes
  are Fireworks JSON Schema output, the Gemini 3.7 Flash `low` thinking floor,
  OpenAI Responses `allowedTools` plus the `computer` tool, MCP 2.0.33
  compatibility hardening, Bedrock EventStream failure/EOF propagation, and
  preservation of OpenAI-compatible raw usage details. The remaining package
  deltas are version, dependency, or forward-compatible model-ID propagation.
- `ai@7.0.66` array output wrappers now hoist both root `definitions` and
  `$defs`, preserving schemas whose array items reference root definitions.
  `AIChatSession` also stays `.submitted` for metadata-only response-start
  snapshots and moves to `.streaming` only when response content arrives.
- The remaining `ai@7.0.66` changes are covered or do not map to Swift:
  reasoning UI parts already retain IDs; reconnect snapshots never clone the
  previous assistant response; Swift chat inputs require no asynchronous
  browser-file preparation; every provider can be stored behind `AIProvider`
  even when reranking throws unsupported; and ToolLoop settings are already
  accepted by the runtime types. TypeScript declaration emit, React message
  cloning, and promise rejection from a JavaScript `onFinish` callback have no
  direct Swift runtime surface.
- `@ai-sdk/provider-utils@5.0.27` keeps the original streamed size-limit error
  if response cancellation also fails. Swift cancellation is not awaited on
  that error path, so it already preserves the primary failure. The safe
  module import without a global JavaScript `fetch` is likewise inapplicable.
- `@ai-sdk/react@4.0.69` changes `useChat`, `useCompletion`, and `useObject`
  hook/store behavior. SwiftAISDK exposes a native `AIChatSession` rather than
  React hooks, so no framework-specific state patch is applied.
- Provider-facing language streams now consume `AIStreamingTransport` bodies
  incrementally rather than awaiting a buffered `AIHTTPResponse`. Shared SSE
  parsing follows `eventsource-parser` chunk, line-ending, BOM, field-space,
  and incomplete-EOF behavior; Amazon EventStream parsing validates frame
  lengths and CRCs. Focused gated and loopback tests prove first-part delivery
  before EOF plus cancellation of the response body on abort or early stop.
  Custom send-only transports remain valid for unary generation and fail
  streaming with a non-retryable argument error.
- Built-in language streams use one part-aware text/reasoning lifecycle instead
  of emitting both legacy and identified deltas. The facade normalizes
  legacy-only custom streams, rejects ambiguous mixed-family streams, preserves
  repeatable in-band provider errors, and validates that a stream does not emit
  duplicate terminals for one logical response. Built-in providers guarantee
  one terminal outcome per response; clean custom EOF without a terminal is
  left unspecified rather than assigned a guessed reason. Cross-surface tests
  guard exact accumulation in text,
  reasoning, UI, structured-output, and tool-loop consumers.
- `ai@7.0.58` default instructions, agent-level default timeouts, and
  reconnect cancellation are ported through `defaultInstructionsMiddleware`,
  `AIToolLoopAgent.timeoutNanoseconds`, and `AIChatReconnectRequest.abortSignal`.
  Focused tests cover call-level system-message precedence, timeout override
  precedence, and resume-stream abort propagation.
- `@ai-sdk/provider-utils@5.0.25` streamed tool-call correlation is ported for
  both the generic tracker and OpenAI-style provider streams: non-empty IDs
  take precedence over explicit indexes, missing indexes continue the latest
  call, reused indexes can start distinct calls, and finalization happens only
  on stream flush. Generic OpenAI-compatible text-token usage is also clamped
  at zero when a provider reports more reasoning than completion tokens.
- `ai@7.0.68` and `@ai-sdk/provider@4.0.7` Batch V4 and async Video V4 are
  represented by shared Swift protocols and facades. Text batches expose
  persistable references, normalized status/counts, cancellable JSONL terminal
  result streams, and per-item failures; Anthropic Messages Batch and OpenAI
  Responses Batch provide vertical adapters. `AsyncVideoModel` exposes
  serializable start/status state, core-owned polling/webhook waiting,
  cancellation, provider-metadata merging, and one stable `idempotency-key`
  across start retries while preserving unary `VideoModel` calls. Black Forest
  Labs FLUX 3 and Fal provide operation adapters; Fal forwards a native webhook,
  BFL warns and falls back to polling, and requests above a provider's
  `maxVideosPerCall` are split into ordered logical starts.
- `@ai-sdk/react@4.0.61` changes React `useChat` subscription throttling so an
  unrelated render cannot bypass the configured cadence. SwiftAISDK has no
  `useSyncExternalStore`/React render subscription, so there is no direct
  portable runtime change.
- `ai@7.0.45` extends the experimental tool-caller graph from `generateText`
  into `streamText` and `ToolLoopAgent`. Swift still has no shared late-bound
  local/provider caller abstraction, so the existing generic tool-caller gap
  now explicitly covers all three orchestration surfaces rather than adding a
  provider-specific shortcut.
- `ai@7.0.45` streaming timeout behavior is represented by
  `AIStreamTimeoutConfiguration`: total, per-model-step,
  first-semantic-output, and inter-semantic-output deadlines are public;
  total and step budgets include retry backoff, the step signal remains active
  through client-side tool execution, and timeout aborts reach provider and
  tool signals with the `TimeoutError` reason name. Step/first/inter-chunk
  timers re-arm for every model step; metadata, lifecycle, raw keep-alives,
  tool results, and empty deltas do not reset the semantic timers. Typed
  `Output` streams accept the same configuration. `AIStreamTimeoutError`
  identifies the first-chunk or chunk phase, while the legacy flat total
  timeout remains source-compatible. The clarified `GenerateTextResult.output`
  no-output documentation matches Swift's existing `AINoOutputError` behavior.
- `@ai-sdk/provider-utils@5.0.18` centralizes empty usage and common response
  metadata construction without changing result shapes. Swift already uses
  shared `TokenUsage` and `AIResponseMetadata` conversion paths. Its switch
  from a JavaScript symbol to an `experimental_toolCaller` object property is
  part of the deferred caller abstraction above and has no standalone Swift
  representation.
- `@ai-sdk/react@4.0.47 -> 4.0.51` contains dependency/version propagation
  only; no portable React source contract changed.
- `ai@7.0.44` telemetry end events attribute the resolved response model rather
  than only the requested model ID. Swift now uses response metadata for the
  same attribution and carries focused generate/stream telemetry regressions.
- `ai@7.0.42` metadata on empty text deltas is preserved by the Swift stream
  accumulator and output mapper instead of being discarded with an empty text
  payload. `ai@7.0.38` provider-executed invalid tool calls no longer cause a
  duplicate client-side error result or execution attempt.
- `ai@7.0.42` per-`prepareStep` call-setting overlays remain deferred. Swift can
  return a replacement request, but currently persists that request into later
  steps; faithful parity needs an isolated validated overlay and matching
  telemetry for each model call.
- `ai@7.0.43` generic provider tool-callers remain deferred. OpenAI and
  Anthropic wire formats already accept manual allowed-caller provider options,
  but automatic tool-owned caller registration needs one late-binding core
  contract rather than provider-specific shortcuts.
- `@ai-sdk/provider@4.0.4` and `ai@7.0.38` add experimental streaming speech
  translation. Swift now has reusable `AIDuplexWebSocketTransport`, streaming
  audio input, lifecycle/result/error types, a Cartesia Ink 2 streaming
  transcription adapter, and provider-neutral `AIRealtimeModelV4`/
  `AIRealtimeSession` contracts with xAI as the first full Realtime V4 adapter.
  Google/OpenAI translation, ElevenLabs realtime transcription, and full
  non-xAI speech-session adapters still need provider-specific translations
  above those shared contracts.
- `@ai-sdk/provider-utils@5.0.16` adds resolver-backed DNS address validation
  and connection pinning. Swift still validates literal/private hosts and every
  redirect, but URLSession does not expose the same connector hook; DNS
  rebinding protection is therefore recorded as a transport-level gap rather
  than claimed as covered. Workflow serialization and JavaScript WebSocket
  helper changes have no direct Swift runtime surface.
- `@ai-sdk/react@4.0.40 -> 4.0.47` is dependency/version propagation only; no
  portable React source contract changed.
- `ai@7.0.36` injective tool-approval signatures are ported through
  `toolApprovalSecret`: Swift signs the versioned JSON-array payload, accepts
  safe legacy newline-format signatures only when the signed identity fields
  contain no newline, and rejects delimiter retupling. Canonical JSON matches
  ECMAScript `JSON.stringify` and UTF-16 object-key ordering, including numeric
  exponent thresholds, `-0`, and large integral doubles, so Node and Swift
  signatures remain interoperable. Focused tests cover published Node vectors,
  Unicode key ordering, control characters, legacy compatibility, and the
  original collision.
- `ai@7.0.33` consecutive tool-message provider options are represented by
  Swift provider metadata. When tool messages are combined, the earlier
  message metadata is deep-merged into its boundary content part, with
  part-level values winning, while the later message metadata remains on the
  combined message.
- `ai@7.0.32` multi-step non-streaming generation now rechecks the caller abort
  signal before every later model step. Cancellation during tool execution
  preserves the original `AIAbortError` reason and prevents a second model
  call even when the tool returns normally.
- `@ai-sdk/provider-utils@5.0.12` media sniffing is ported: ID3-prefixed raw and
  base64/base64url inputs decode only a bounded prefix, optional base64 padding
  is restored, the 128 KiB tag boundary matches upstream, and ISO-BMFF `ftyp`
  bytes resolve to `audio/mp4` in an audio context while generic detection keeps
  the ambiguous container as `video/mp4`.
- `ai@7.0.35` `stepMs`, `firstChunkMs`, and semantic-content-only `chunkMs`
  behavior is ported through `AIStreamTimeoutConfiguration`, including
  per-model-step re-arming and timer cleanup on normal completion, provider
  failure, timeout, and consumer cancellation.
- `ai@7.0.33` repeated tool-call ids across explicit UI stream steps are
  deferred. `AIUIMessageStreamReducer` currently indexes tool parts globally,
  and `LanguageStreamPart` has no `start-step` / `finish-step` cases from which
  to define the upstream step boundary without a broader public stream change.
- `ai@7.0.35` Node `ServerResponse` piping promises and read/write error
  propagation remain JS-server-only. `ai@7.0.32` loose Zod UI-message chunk
  schemas likewise have no direct Swift patch because SwiftAISDK exposes typed
  in-process `LanguageStreamPart` values rather than that Zod wire decoder.
- `ai@7.0.12` response-message tool-result ordering is ported in
  `toResponseMessages`: non-provider-executed tool results are sorted by the
  original tool-call order while approval responses keep their relative slots.
- `ai@7.0.12` `extractJsonMiddleware` streamed suffix whitespace fix is not a
  separate Swift runtime patch because SwiftAISDK buffers per text block before
  applying the transform; the upstream partial-stream boundary that caused the
  bug is not exposed.
- `ai@7.0.7` `convertToModelMessages` empty-assistant fix and `ai@7.0.5`
  orphaned approval-response pruning are already covered by upstream-style
  Swift regression tests.
- `@ai-sdk/provider@4.0.3` ProviderV4 additions are represented by Swift's
  existing stable protocols: provider references, file uploads, custom content,
  reasoning files, top-level reasoning, tool-result file content, video
  `frameImages`/`inputReferences`, and `generateAudio` request fields. The
  ProviderV4 type names, ESM packaging, and Node 22 engine requirement are
  JavaScript-only concerns.
- `@ai-sdk/provider-utils@5.0.11` security/runtime changes were audited against
  Swift transports and parsers. Response-size limits, same-origin credential
  hardening, SSRF download validation, typed JSON parsing, and body cancellation
  semantics are covered or Swift-native. Redirects are followed manually,
  every hop is validated before use, same-origin provider credentials are kept,
  and cross-origin provider credentials are removed. JavaScript
  prototype-pollution fixes are not applicable to Swift value dictionaries.
- `@ai-sdk/provider-utils@5.0.11` and `ai@7.0.14` streaming transcription are
  represented by `StreamingTranscriptionModel`, `StreamingTranscriptionPart`,
  `AIStreamingAudioInput`, and the injectable duplex WebSocket transport, with
  Cartesia Ink 2 as the first vertical adapter. Realtime session/media
  negotiation is represented separately by `AIRealtimeModelV4` and
  `AIRealtimeSession`; xAI is the first provider adapter, while full non-xAI
  realtime remains deferred.
- `@ai-sdk/openai@4.0.43` Responses `allowedTools` resolves declared function,
  built-in, MCP, custom, and current computer tools to upstream allow-list
  entries, warns for entries that cannot be represented, and rejects an
  allow-list that becomes empty. `OpenAITools.computer()` is distinct from the
  older `computerUse(...)` wire tool. `@ai-sdk/open-responses@2.0.28` remains
  intentionally narrower: provider-defined tools warn and are dropped, matching
  upstream rather than inventing an execution contract.
- `@ai-sdk/mcp@2.0.33` is represented by the current MCP client, HTTP/SSE and
  stdio transports, tool conversion, and OAuth helpers. The patch is treated as
  protocol/transport and OAuth compatibility hardening; product-facing details
  stay documented conservatively until the complete source vertical is settled.
- `@ai-sdk/react@4.0.34 -> 4.0.40` has no direct source or declaration diff.
  Its releases only propagate `ai`, provider-utils, gateway, and MCP dependency
  updates. SwiftAISDK's UI analog remains `AIChatSession`,
  `AIObjectGenerationSession`, `DirectAIChatTransport`, and
  `AIUIMessageStreamReducer`; there is no React iframe renderer to port.
- `provider-utils@4.0.30` SSRF hardening is ported in `validateDownloadURL`
  and `downloadURL`: trailing-dot hostnames are normalized before local-host
  checks, additional private/reserved IPv4 and IPv6 ranges are blocked,
  embedded IPv4-in-IPv6 forms are decoded, and redirects are followed manually
  with each hop validated before the next request is issued.
- `provider-utils@4.0.30` same-origin credential hardening is ported through the
  shared `isSameOrigin` helper and provider-specific guards for
  Black Forest Labs, FAL, Fireworks, Gladia, Google Veo, and Replicate.
- `provider-utils@5.0.1` response-handler memory hardening is ported at the
  Swift transport boundary: `URLSessionTransport.send` now applies
  `AIDefaultMaxDownloadSize` even when a request does not pass an explicit
  `maxResponseBytes`, so buffered JSON/error responses are rejected from
  `Content-Length` or while streaming before unbounded accumulation.
- `ai@6.0.201` array-output transform fix is already Swift-native: array output
  returns decoded `Element` values from the final validated object array path,
  and Swift has no Zod-style transform pipeline that could return raw elements.
- `ai@6.0.202` approval replay HMAC is no longer a documented Swift gap. The
  current signed replay path is covered by the `ai@7.0.36` injective-payload
  implementation described above.
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
| `generateText` | `covered` | `AI.generateText`, `LanguageModelRequest`, `TextGenerationResult` | Supports prompt/request overloads, tools, multi-step loops, retries, telemetry, provider metadata, response metadata, raw chunks, and abort signals. Later tool-loop steps recheck cancellation before another model call and preserve the caller's abort reason. |
| `streamText` | `covered` | `AI.streamText`, `LanguageStreamPart`, `AIStreamProviderError`, `AIStreamingTransport`, `AIStreamTimeoutConfiguration`, incremental SSE/EventStream and semantic-timeout regressions | Async sequence surface with provider parts delivered before HTTP EOF, one part-aware content lifecycle, one built-in terminal outcome per logical response, typed in-band provider failures, tools, approvals, retries-before-first-yield, telemetry, and total/per-step/first-semantic/inter-semantic deadlines. Total/step budgets include retry backoff, step deadlines span client tool execution, typed `Output` streams share the configuration, and timeout aborts propagate to provider/tool signals. |
| `embed` | `covered` | `AI.embed`, `EmbeddingRequest`, `EmbeddingResult` | Single-value helper delegates through the embedding request shape. |
| `embedMany` | `covered` | `AI.embedMany`, `EmbeddingModel.maxEmbeddingsPerCall`, `EmbeddingModel.maxInputBytesPerCall` | Splits once against the caller/model count limit and provider UTF-8 byte budget, keeps an individually oversized value intact, and aggregates usage/warnings/metadata in request order. |
| `rerank` | `covered` | `AI.rerank`, `RerankingRequest`, `RerankingResult` | Native model family exists. |
| `generateImage` | `covered` | `AI.generateImage`, `ImageGenerationRequest`, `ImageGenerationResult.calls` | Includes files, masks, provider options, aggregate metadata, per-call results, warnings, retries, and aborts. True request splitting and provider-specific cost aggregation across multiple calls remain deferred. |
| `transcribe` | `covered` | `AI.transcribe`, `AudioTranscriptionRequest`, `detectMediaType` | Upstream now documents `transcribe`; older experimental naming is intentionally not mirrored. Shared media detection recognizes MP4/M4A from the ISO-BMFF `ftyp` box in an audio context and bounds ID3 scanning. |
| `StreamingTranscriptionModel` | `covered` | `StreamingTranscriptionModel`, `AIStreamingAudioInput`, `StreamingTranscriptionPart`, `CartesiaStreamingTranscriptionModel`, `GatewayTranscriptionModel` | Provider-neutral duplex transcription lifecycle with Cartesia Ink 2 and Gateway adapters. Gateway adds a short-lived route-bound token factory; ElevenLabs realtime STT remains deferred. |
| `generateSpeech` | `covered` | `AI.generateSpeech`, `SpeechRequest` | Native model family exists. |
| `experimental_generateVideo` | `covered` | `AI.generateVideo`, `AI.startVideo`, `AI.getVideoStatus`, `VideoGenerationRequest`, `AsyncVideoModel`, `VideoGenerationPollOptions` | Stable Swift naming preserves unary generation and adds directly persistable V4 start/status, polling, webhook waiting, cancellation, metadata merging, logical-start idempotency, and count splitting. BFL, Fal, ByteDance, and Gateway are vertical adapters; Fal and Gateway support native callback URLs while BFL and ByteDance fall back to polling with a warning. |
| `startTextBatch` / `getBatchStatus` / `getBatchResults` | `covered` | `AI.startTextBatch`, `AI.getBatchStatus`, `AI.getBatchResults`, `BatchLanguageModel` | Durable text batches expose persistable references, optional completion webhooks, normalized status/counts, full result content, and complete per-item terminal streams through Anthropic Messages Batch, OpenAI Responses Batch, Gateway Batch V4, and xAI Responses Batch. Gateway forwards webhooks; the direct providers warn that they are unsupported. |
| `Experimental_RealtimeModelV4` | `covered` | `AIRealtimeModelV4`, `AIRealtimeSession`, `XAIRealtimeModel` | Provider-neutral client-secret, duplex event, audio/text/tool, abort and close lifecycle with xAI as the first full adapter. Full non-xAI realtime adapters remain deferred. |
| `Output` | `covered` | `Output.text/object/array/choice/json`, `AI.generateText(... output:)`, `AI.streamText(... output:)`, existing object-generation facades | Swift now mirrors the v6-style `generateText/streamText + Output.*` entry point while still keeping the older Swift-native object/array/enum/json facades. `Output.object` partial streaming uses `JSONValue` because Swift has no automatic `DeepPartial<T>`. |
| `Agent` interface | `covered` | `AIAgent`, `AIAgentCallOptions` | Swift-native agent protocol mirrors upstream `version: "agent-v1"`, optional `id`, tool exposure, and generate/stream calls over model messages or prompts. |
| `ToolLoopAgent` | `covered` | `AIToolLoopAgent`, tool-loop overloads on `AI.generateText` and `AI.streamText` | Reusable agent object wraps the existing Swift tool loop. Default `maxSteps` is 20 to match upstream `stepCountIs(20)` behavior. |
| `createAgentUIStream` | `partial` | `createAgentUIStream`, `AIUIMessageStreamReducer.snapshots(from:)` | Converts validated `AIUIMessage` history to model messages, streams through any `AIAgent`, and returns assistant UI-message snapshots. Repeated tool-call ids across explicit upstream step boundaries remain deferred until the Swift stream type represents those boundaries. |
| `createAgentUIStreamResponse` | `out of scope candidate` | none | JS response/server surface; likely not a SwiftPM core priority unless a Swift server use case is chosen. |
| `pipeAgentUIStreamToResponse` | `out of scope candidate` | none | Same as above. |
| `tool` | `swift-native` | `AITool` | Swift uses a concrete typed tool struct rather than a TS inference helper. |
| `dynamicTool` | `swift-native` | `AITool.dynamic`, MCP tool conversion | Behavior exists; naming differs. |
| `createMCPClient` | `covered` | `MCPClient.connect`, `MCPHTTPTransport`, `MCPStdioTransport`, `MCPApps` | Broad MCP client, transport, OAuth, resources, prompts, completions, elicitation, MCP Apps metadata/resource helpers, session resume callbacks, initial initialize result reuse, paginated tool discovery, tool-call retries, tool conversion, and non-successful POST/SSE diagnostics through `@ai-sdk/mcp@2.0.41`. OAuth scope reaches dynamic registration, and private credential endpoints are rejected without redirects. |
| `Experimental_StdioMCPTransport` | `covered` | `MCPStdioTransport` | Swift uses stable transport naming. |
| `jsonSchema` | `swift-native` | `AIJSONSchema`, `JSONValue`, `parseJSON`, schema validator | Usable JSON Schema adapter exists; exact factory naming does not. |
| `zodSchema` | `out of scope candidate` | none | Zod is TypeScript-specific. Could document `AIJSONSchema` as the Swift alternative. |
| `valibotSchema` | `out of scope candidate` | none | Valibot is TypeScript-specific. |
| `ModelMessage` | `covered` | `AIMessage`, `AIContentPart`, `MessageRole`, `convertToLanguageModelPrompt` | Swift naming differs but covers system/user/assistant/tool plus text, file, image URL, provider references, tool calls/results, approvals. Consecutive tool messages preserve message-level provider metadata at each combined-content boundary. |
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
| `AI_InvalidToolInputError` | `covered` | `AIInvalidToolInputError`, `AITypeValidationError`, `AITool` validation/refinement | New tool argument JSON/schema failures throw typed tool-input errors. Invalid persisted approved calls become model-visible error results and continue without executing the tool. |
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
| `AI_StreamProviderError` | `covered` | `AIStreamProviderError`, `LanguageStreamPart.providerError`, `LanguageStreamPart.streamProviderError` | Public typed view of an in-band provider failure, preserving the provider's message, type, string/numeric code, HTTP status, retryability, and raw payload while retaining the source-compatible stream error case. |
| `AI_ToolCallNotFoundForApprovalError` | `covered` | `AIToolCallNotFoundForApprovalError`, `validateUIMessages` | Approval requests that reference a missing tool call now surface as a typed error in throwing validation. |
| `AI_ToolCallRepairError` / `ToolCallRepairError` | `covered` | `AIToolCallRepairError`, `AITool.refineArguments` | Swift maps the existing argument-refinement hook to a typed tool-call repair failure. |
| `AI_TooManyEmbeddingValuesForCallError` | `covered` | `AITooManyEmbeddingValuesForCallError`, embedding model preflight guards | OpenAI-compatible, Google, Google Vertex, Voyage, Mistral, Cohere, and Amazon Bedrock embedding limits now throw a typed error carrying provider, model id, max count, and values. |
| `AI_TypeValidationError` | `covered` | `AITypeValidationError`, `AIJSONSchemaValidator`, `AIObjectGenerationError.kind == .schemaValidation` | Schema validation now has a standalone public type-validation error, while object generation continues to wrap schema failures in `AIObjectGenerationError`. |
| `AI_UIMessageStreamError` | `covered` | `AIUIMessageStreamError` | Used for UI message validation and stream-reduction failures. Carries `chunkType`/`chunkID` for out-of-sequence stream chunks, plus Swift validation issues. |
| `AI_UnsupportedFunctionalityError` | `partial` | `AIError.unsupportedModel`, `AIWarning(type: "unsupported", ...)`, provider invalid-argument paths | Unsupported features are represented, but not as a dedicated public error class. |

## Recommended Next Passes

1. Decide how explicit model-step boundaries should enter
   `LanguageStreamPart`, then scope `AIUIMessageStreamReducer` tool lookup to
   the current step while retaining backwards lookup for late tool outputs.
2. Continue polishing the new `AIOutput` surface where it proves useful:
   document examples and consider array `elementStream` ergonomics. The
   `choice/json` factories already propagate `name` and `description` as
   provider hints.
3. Decide whether `DefaultGeneratedFile` deserves a named Swift analog or
   whether `AIStreamFile` plus generated media result structs are sufficient.
4. Keep JS response helpers (`createAgentUIStreamResponse`,
   `pipeAgentUIStreamToResponse`, `createUIMessageStreamResponse`,
   `pipeUIMessageStreamToResponse`) out of core unless SwiftAISDK grows a
   server-side Swift target.
5. Continue typed-error parity only where it improves Swift diagnostics. The
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
| `readUIMessageStream` / UI stream reducer | `AIUIMessageStreamReducer` | partial | Converts `LanguageStreamPart` into stable UI message snapshots, so UI layers do not hand-roll streaming assembly. ID-based text/reasoning/tool-input chunks reject missing starts like upstream `processUIMessageStream`; Swift keeps id-less language deltas as a compatibility convenience. Repeated tool-call ids across model steps remain deferred because the stream enum does not yet expose step boundaries. |
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
