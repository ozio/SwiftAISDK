# SwiftAISDK

SwiftAISDK is a SwiftPM port of the provider-facing parts of Vercel AI SDK.
It provides provider factories plus an `AI` facade for text, durable batches,
structured output, evaluation, embeddings, media, streaming and realtime audio, reranking,
file operations, middleware, MCP tools, and typed tool execution.

Licensed under the [Apache License 2.0](LICENSE). SwiftAISDK is an independent
Swift port; references to Vercel AI SDK describe compatibility and provenance,
not affiliation or endorsement.

## Install

Add the package to `Package.swift`:

```swift
.package(url: "https://github.com/ozio/SwiftAISDK.git", from: "1.1.1")
```

Applications that require a reviewed, reproducible SDK build can use SwiftPM's
`exact:` requirement for the release they have validated. Avoid depending on
the moving `main` branch in production.

Then depend on the library product:

```swift
.product(name: "SwiftAISDK", package: "SwiftAISDK")
```

## Quick Start

```swift
import SwiftAISDK

let provider = try AIProviders.openAI()
let model = try provider.languageModel("gpt-4.1")

let result = try await model.generateText("Write one sentence about Swift.")

print(result.text)
```

Provider factories read their upstream-style environment variables by default,
for example `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_GENERATIVE_AI_API_KEY`,
and `GEMINI_API_KEY`. Provider-specific defaults live in the corresponding
factory in `Sources/SwiftAISDK/Providers/ProviderRegistry.swift`. You can also
pass credentials explicitly:

```swift
let provider = try AIProviders.openAI(
    settings: ProviderSettings(apiKey: "your-api-key")
)
```

## Core Facade

The `AI` facade mirrors the high-level shape of `ai` while using Swift
protocols for each model family:

```swift
let text = try await model.generateText("Hello")

let embeddings = try await AI.embedMany(
    model: try provider.embeddingModel("text-embedding-3-small"),
    values: ["alpha", "beta"],
    chunkSize: 100
)

let image = try await AI.generateImage(
    model: try provider.imageModel("gpt-image-1"),
    prompt: "A small watercolor robot"
)
```

Streaming text is exposed as an async sequence:

```swift
for try await part in model.streamText("Stream this") {
    print(part)
}
```

Built-in HTTP language providers deliver parts incrementally as response bytes
arrive; they do not wait for the HTTP body to finish. If you inject a custom
transport, streaming requires the transport to conform to
`AIStreamingTransport`. A send-only `AITransport` remains valid for unary
generation, but `stream` fails with a non-retryable transport argument error
instead of buffering through `send`.

Built-in model streams use one canonical semantic lifecycle for each content
block: `textStart` → `textDeltaPart` → `textEnd`, with the corresponding
reasoning parts for reasoning blocks. The older `textDelta`, `reasoningDelta`,
and `finish` cases remain source-compatible for custom models; facade calls
normalize them to the part-aware lifecycle and `finishMetadata`. Built-in
providers do not emit the legacy cases alongside canonical events. This keeps text,
reasoning, UI snapshots, structured output, and tool-loop accumulation from
counting the same provider delta twice.

Each logical built-in model response has one terminal `finishMetadata` part.
Custom models should follow the same contract; clean custom EOF without a
terminal is preserved rather than assigned a guessed outcome. Provider error
events remain visible as repeatable in-band `error` parts on the full stream;
`part.streamProviderError` exposes normalized type, code, HTTP-equivalent
status, retryability, and raw payload through `AIStreamProviderError`. Setup,
HTTP, framing, and network failures throw. `toTextStream()`
intentionally emits only canonical text deltas and ignores in-band error parts,
while still propagating thrown stream failures.

Facade calls retry transient failures by default with `maxRetries: 2`.
Streaming keeps the conservative default: setup failures may retry, but an
attempt is not replayed after its first public part unless `streamRetries` is
set. A positive `streamRetries` value additionally retries retryable in-band
provider errors after streaming has started. Tool-call, finish, usage, and
provider-metadata state from the failed attempt is isolated from the next
attempt, and a recovered provider-error part is not exposed. Text already
yielded to the caller cannot be retracted and the replacement attempt may emit
the same prefix again. Stopping iteration or aborting the request cancels the
upstream response body. Pass `retryPolicy: .none` or a custom `AIRetryPolicy`
to tune setup retries and backoff:

```swift
for try await part in AI.streamText(
    model: model,
    prompt: "Stream this.",
    streamRetries: 1
) {
    print(part)
}
```

For streaming stalls, `AIStreamTimeoutConfiguration` distinguishes the total
operation deadline, each model-call step, the first semantic output, and the
gap between semantic output parts. Total and step budgets include retry
backoff, step budgets stay active through client-side tool execution, and a
timeout aborts the provider/tool signal with a `TimeoutError` reason. The same
configuration works with typed `Output` streams. Step/first/inter-chunk timers
restart for every model-call step; metadata, raw keep-alives, lifecycle
markers, and empty deltas do not reset the semantic timers:

```swift
for try await part in AI.streamText(
    model: model,
    prompt: "Stream this.",
    timeout: AIStreamTimeoutConfiguration(
        totalNanoseconds: 60_000_000_000,
        stepNanoseconds: 30_000_000_000,
        firstChunkNanoseconds: 10_000_000_000,
        chunkNanoseconds: 15_000_000_000
    )
) {
    print(part)
}
```

Embedding calls validate that each provider response contains one vector per
requested value before results are merged. Image no-output failures expose the
same per-call diagnostics as successful `ImageGenerationResult.calls` through
`AINoOutputError.calls`.

`AIChatSession.sendMessage(_:replacingMessageID:)` uses the supplied ID only to
locate the old message; an explicit ID on the replacement becomes the new
transcript ID. UI tool approvals retain their provider descriptor, and failed
tool-result metadata is restored onto the associated model-facing tool call.

## Structured Output

`AI.generateObject` requests JSON output, validates it when a JSON Schema is
supplied, and decodes the result into a Swift `Decodable` type:

```swift
struct Summary: Decodable, Sendable {
    var title: String
    var bullets: [String]
}

let schema = AIJSONSchema<Summary>(
    [
        "type": "object",
        "properties": [
            "title": ["type": "string"],
            "bullets": ["type": "array", "items": ["type": "string"]]
        ],
        "required": ["title", "bullets"]
    ],
    name: "summary"
)

let result = try await model.generateObject(
    "Summarize this changelog.",
    schema: schema
)

print(result.object.title)
```

The upstream-style `Output` entry point is available on `generateText` and
`streamText` when you want one facade for text, object, array, choice, and
schema-free JSON output:

```swift
let result = try await model.generateText(
    "Summarize this changelog.",
    output: Output.object(schema: schema)
)

print(result.output.title)
```

Array output can publish the same bounds in its JSON Schema and enforce them
when the final value is decoded:

```swift
let result = try await model.generateText(
    "Return two or three labels.",
    output: Output.array(
        element: ["type": "string"],
        minItems: 2,
        maxItems: 3,
        as: String.self
    )
)
```

For source compatibility, invalid bound combinations are reported when the
strategy executes, before model work begins, rather than by the nonthrowing
`Output.array` constructor itself.

Streaming and JSON strategies are also available through `streamObject`,
`generateObjectArray`, `streamObjectArray`, `generateEnum`, `streamEnum`,
`generateJSON`, and `streamJSON`.

## Tools

`generateText` and `streamText` can execute typed Swift tools and continue
the conversation until the model returns a final answer or `maxSteps` is
reached:

```swift
let weather = AITool(
    name: "weather",
    description: "Get the current weather.",
    parameters: [
        "type": "object",
        "properties": ["city": ["type": "string"]],
        "required": ["city"]
    ]
) { arguments in
    ["forecast": "sunny in \(arguments["city"]?.stringValue ?? "unknown")"]
}

let answer = try await model.generateText(
    "What should I wear in Tokyo?",
    tools: LanguageToolOptions([weather], maxSteps: 3)
)
```

Tools support argument refinement, JSON Schema validation, dynamic MCP-backed
tools, approval hooks, and provider-defined helpers such as `OpenAITools`,
`AnthropicTools`, `XAITools`, `GoogleTools`, and `GatewayTools`.
When tool choice is `required` or names a specific tool, a response that does
not contain the required call throws `AIToolChoiceViolationError` instead of
being accepted as a successful text-only result. Approval requests can carry an
opaque provider `descriptor` for presentation; treat it as untrusted display
metadata.
For OpenAI Responses, `OpenAITools.programmaticToolCalling(...)` enables
programmatic tool orchestration; function schemas accept OpenAI
`allowedCallers` and `outputSchema` provider options.
OpenAI 4.0.43 parity also includes `OpenAITools.computer()` and
`allowedTools`: the Responses request builder resolves declared function,
built-in, MCP, and custom tools into `tool_choice.allowed_tools`, warns when an
entry cannot be allow-listed, and rejects an allow-list that becomes empty.
The older `computerUse(...)` helper remains available for the separate
`computer_use` wire tool.
For xAI Responses, `XAITools.imageGeneration(action:)` exposes the hosted image
tool with generated/streamed prompt and failure results. Gateway failures retain
their normalized `AIAPICallError` through `GatewayError.cause`.
`OpenAITools.imageGeneration(action:)` and
`AzureOpenAITools.imageGeneration(action:)` expose the matching OpenAI action
field.

## Durable Batch And Video Operations

Batch V4 is provider-owned: each request carries its model ID and modality,
while the returned provider reference can be persisted and resumed in another
process. Anthropic Messages Batch, OpenAI Responses Batch, xAI Responses Batch,
Google Generative AI Batch, and Gateway Batch V4 implement the shared surface:

```swift
let anthropic = try AIProviders.anthropic()
let batch = anthropic.experimentalBatch()
let started = try await AI.startBatch(
    provider: batch,
    requests: [.text(TextBatchRequest(
        id: "summary-1",
        modelID: "claude-sonnet-4-5",
        request: LanguageModelRequest(messages: [.user("Summarize this.")])
    ))]
)

let status = try await AI.getBatchStatus(
    provider: batch,
    batch: started.batch.reference
)

for try await item in try AI.getBatchResults(
    provider: batch,
    batch: started.batch.reference
) {
    // Each text or image request reaches an independent terminal result.
    print(item)
}
```

xAI and Google also accept `.image(ImageBatchRequest(...))`; xAI may mix models
and modalities in one batch, while Google requires a common model endpoint.
Anthropic accepts text requests with per-request model IDs. OpenAI and Gateway
accept text only and require one common model. Inspect the batch provider's
`supportedURLs` before deciding whether an input URL can be forwarded directly.

Gateway and Google forward `webhookURL` through their native callback fields.
Direct Anthropic, OpenAI, and xAI batch adapters return an unsupported warning,
so callers can poll without silently assuming webhook delivery. Starting a
batch is not retried automatically because it may create billable work; status,
listing, and result setup use the normal retry policy. The older model-owned
`AI.startTextBatch(model:requests:)` API remains source compatible.

Async Video V4 keeps unary `generateVideo` source compatible while adding
serializable start/status operations, core-owned polling/webhook waiting, and a
stable logical-start idempotency key. Black Forest Labs FLUX 3, Fal, ByteDance,
and Gateway expose operation adapters; select the managed flow with
`poll: VideoGenerationPollOptions(...)` or a webhook registration. Fal and
Gateway forward native webhook URLs, while providers without native webhooks
fall back to polling with a warning. Requests above a model's
`maxVideosPerCall` are split into independent starts and merged in input order.

Use `AI.startVideo` and `AI.getVideoStatus` when the operation must outlive the
current process or be polled by another worker:

```swift
let model = try AIProviders.gateway().videoModel("bytedance/seedance-1-5-pro")
let started = try await AI.startVideo(
    model: model,
    request: VideoGenerationRequest(prompt: "A lantern floating over Tokyo")
)

let status = try await AI.getVideoStatus(
    model: model,
    operation: started.operation
)
```

## Providers

Provider factories live under `AIProviders`, including OpenAI, Azure,
Anthropic, Google, Google Vertex, Gateway, xAI, Mistral, Groq, Cohere, Voyage,
MiniMax, Bedrock, Replicate, fal, Fish Audio, GMI Cloud, Deepgram, ElevenLabs,
Cartesia, and other official `@ai-sdk/*` provider packages.

MiniMax uses its Anthropic-compatible Messages endpoint and reads
`MINIMAX_API_KEY` by default. Adaptive thinking is selected through the
`minimax` provider-options namespace:

```swift
let miniMax = try AIProviders.miniMax()
let model = try miniMax("minimax-m3")
let result = try await model.generateText(
    "How many r letters are in strawberry?",
    options: LanguageGenerationOptions(
        providerOptions: [
            "minimax": ["thinking": ["type": "adaptive"]]
        ]
    )
)

print(result.reasoning)
print(result.text)
```

MiniMax-H3 video generation uses the same API key and a dedicated video API
root. Text-to-video, first/last frames, and reference inputs are supported:

```swift
let videoModel = try miniMax.video("MiniMax-H3")
let video = try await videoModel.generateVideo(VideoGenerationRequest(
    prompt: "A white kitten chases a butterfly across a sunlit garden.",
    aspectRatio: "16:9",
    durationSeconds: 5
))

print(video.urls)
```

Use `customProvider(...)` and `createProviderRegistry(...)` for upstream-style
provider composition and combined model IDs:

```swift
let registry = createProviderRegistry([
    "openai": try AIProviders.openAI(),
    "anthropic": try AIProviders.anthropic()
])

AIDefaultProvider.set(registry)

let result = try await AI.generateText(
    model: "openai:gpt-4.1-mini",
    prompt: "Write a launch checklist."
)
```

Provider-specific options can be passed through request types or facade
overloads via `providerOptions`, `extraBody`, `headers`, and `ProviderSettings`.
DeepSeek V4 Flash Vision accepts image data, URLs, and uploaded DeepSeek file
references; `try AIProviders.deepSeek().files()` exposes its `user_data` upload
route. OpenAI-compatible chat accepts hosted video input through
`AIContentPart.videoURL(...)` and preserves Gemini thought signatures under a
custom provider namespace.

### Files V4

`AIFileClient` advertises `supportedFileOperations` and may implement upload,
metadata lookup, streamed download, and deletion. OpenAI and xAI implement the
complete contract; providers that remain upload-only reject unsupported
operations before I/O.

```swift
let files = try AIProviders.openAI().files()
let uploaded = try await AI.uploadFile(
    client: files,
    request: FileUploadRequest(
        data: documentData,
        mediaType: "application/pdf",
        filename: "report.pdf",
        purpose: "assistants"
    )
)

let metadata = try await AI.getFileMetadata(
    client: files,
    request: FileMetadataRequest(file: uploaded.providerReference)
)
let download = try await AI.downloadFile(
    client: files,
    request: FileDownloadRequest(file: uploaded.providerReference)
)
let deleted = try await AI.deleteFile(
    client: files,
    request: FileDeleteRequest(file: uploaded.providerReference)
)
```

`FileUploadRequest(stream:...)` avoids buffering a large upload. Its byte
stream is single-use, is cancelled on failure, and disables automatic retry;
buffered `Data` uploads keep the normal retry policy. Upload/metadata results
expose byte size and creation/expiry timestamps when supplied by the provider.
Download content is an `AsyncThrowingStream<Data, Error>`.

Open Responses callers can set `ProviderSettings.strictResponseInput` so
ID-less assistant history uses the provider's strict easy-input form. OpenAI
also recognizes GPT-6 reasoning-update options, the `ultrafast` service tier,
and `gpt-4o-transcribe-diarize` chunking/segment metadata through the existing
provider-options surface.

Google Interactions preserves assistant reasoning, built-in and function tool
history, stateful compaction, provider file references, media resolution, and
system-instruction precedence across generated and streamed calls. Video input
and output plus processing calls/results retain their provider metadata. Google
Batch validates every result key and preserves thought signatures even when the
associated text delta is empty.

Cartesia has dedicated speech and batch-transcription models:

```swift
let cartesia = try AIProviders.cartesia()

let speech = try cartesia.speech("sonic-3.5")
let audio = try await speech.speak(SpeechRequest(
    text: "Hello from SwiftAISDK.",
    voice: "694f9389-aac1-45b6-b726-9d9369183238",
    providerOptions: [
        "cartesia": [
            "container": "mp3",
            "sampleRate": 44_100,
            "language": "en"
        ]
    ]
))

let transcription = try cartesia.transcription("ink-whisper")
let transcript = try await transcription.transcribe(AudioTranscriptionRequest(
    audio: audio.audio,
    mimeType: audio.contentType ?? "audio/mpeg",
    providerOptions: [
        "cartesia": [
            "language": "en",
            "timestampGranularities": ["word"]
        ]
    ]
))
```

Cartesia Ink 2 also exposes duplex streaming transcription through the reusable
`AIDuplexWebSocketTransport` and `AIStreamingAudioInput` lifecycle:

```swift
let streaming = try cartesia.streamingTranscription("ink-2")
let pipe = AIStreamingAudioInput.makeStream()
let session = try await streaming.stream(StreamingTranscriptionRequest(
    audio: pipe.input,
    inputAudioFormat: AIStreamingAudioFormat(
        mediaType: "audio/pcm",
        sampleRate: 16_000
    )
))
```

The transport is injectable, access tokens are removed from request metadata,
and stopping either side cancels the socket/audio producer. This
transcription-only lifecycle is separate from a full realtime response session.

Gateway exposes the same streaming-transcription protocol and can mint a
short-lived, model-bound client token on a trusted server:

```swift
let gateway = try AIProviders.gateway()
let credential = try await gateway.experimentalTranscription.getToken(.init(
    model: "openai/gpt-realtime-whisper",
    expiresAfterSeconds: 120
))

let gatewayStreaming = gateway.experimentalTranscription(
    "openai/gpt-realtime-whisper"
)
```

`gateway.streamingTranscription(_:)` is the direct model alias. The injectable
duplex transport preserves Gateway auth/team subprotocols, splits large audio
frames safely, and maps provider stream metadata and errors into the shared
Swift lifecycle.

## Evaluation V4

`AI.experimentalEvaluate` evaluates Choice, Score, and Boolean questions over
one shared JSON state. OpenAI, Anthropic, and Google adapt their structured
language models; Gateway can call a native Evaluation V4 model directly.

```swift
let anthropic = try AIProviders.anthropic()
let evaluator = try anthropic.evaluationModel("claude-sonnet-4-6")

let result = try await AI.experimentalEvaluate(
    model: evaluator,
    state: [
        "answer": "Paris",
        "reference": "Paris"
    ],
    questions: [
        "correct": .boolean(
            instructions: "Does the answer match the reference?"
        ),
        "quality": .score(
            instructions: "Rate answer quality.",
            criteria: ["Incorrect", "Partially correct", "Fully correct"]
        ),
        "tone": .choice(
            instructions: "Classify the tone.",
            criteria: [
                "neutral": "Plain and factual.",
                "promotional": "Persuasive or sales-oriented."
            ]
        )
    ]
)
```

Answers keep the caller's question IDs and preserve provider usage, warnings,
metadata, response headers/body, and declared rounding. Model IDs can also be
resolved through `AIProviderRegistry` or `customProvider`.

## Realtime Sessions

`AIRealtimeModelV4` and `AIRealtimeSession` provide a provider-neutral duplex
session for turn-based or continuous text/audio conversations, tool calls,
normalized server events, aborts, and explicit close/cancel behavior. xAI
provides the turn-based adapter: it creates an ephemeral client secret,
negotiates the WebSocket subprotocol, maps session/audio/text/tool events, and
keeps provider-specific events available as custom events.

```swift
let xai = try AIProviders.xAI()
let realtimeModel = try xai.realtime("grok-voice-latest")
let session = try await AIRealtimeSession.connect(
    model: realtimeModel,
    sessionConfiguration: AIRealtimeSessionConfiguration(
        instructions: "Answer briefly.",
        voice: "Ara",
        outputModalities: [.audio],
        inputAudioFormat: AIRealtimeAudioFormat(
            type: "audio/pcm",
            rate: 24_000
        )
    )
)

try await session.appendAudio(pcmChunk)
try await session.commitAudio()
try await session.createResponse()

for try await event in session {
    if case let .server(.audioDelta(_, _, base64Audio, _)) = event {
        // Decode or enqueue base64Audio for playback.
    }
}
```

OpenAI Live uses the same session lifecycle in continuous mode over an
authenticated server WebSocket. Audio is consumed continuously, so callers do
not send `commitAudio()` or `createResponse()`:

```swift
let openAI = try AIProviders.openAI()
let liveModel = try openAI.experimentalRealtime("gpt-live-1")
let live = try await AIRealtimeSession.connect(
    model: liveModel,
    sessionConfiguration: .init(
        instructions: "Answer briefly.",
        inputAudioFormat: .init(type: "audio/pcm", rate: 24_000),
        outputAudioFormat: .init(type: "audio/pcm", rate: 24_000)
    )
)

try await live.appendAudio(pcmChunk)
try await live.muteInput()
try await live.unmuteInput()

for try await event in live {
    if case let .server(.audioChunk(delta, _)) = event {
        // Decode or enqueue the base64 audio delta.
    }
}
```

OpenAI Live confirms `session.start` readiness and `session.close`
finalization, and exposes continuous usage, transcript, audio, delegation,
acknowledgement, and correlated error events. Browser WebRTC, provider-backed
Responses delegation, non-Live OpenAI Realtime models, Google realtime, and
ElevenLabs realtime transcription remain deferred.

## Middleware

Models and registries can be wrapped with middleware, mirroring upstream
`wrapLanguageModel`, `wrapImageModel`, `wrapEmbeddingModel`, `wrapProvider`,
specialized text transforms, and default settings helpers:

```swift
let tunedModel = wrapLanguageModel(
    model,
    middleware: defaultSettingsMiddleware(settings: AIDefaultLanguageModelSettings(
        temperature: 0.3,
        providerOptions: ["openai": ["parallelToolCalls": false]]
    ))
)

let instructedModel = wrapLanguageModel(
    model,
    middleware: defaultInstructionsMiddleware(
        instructions: "Answer concisely and cite uncertainty."
    )
)

let jsonReady = wrapLanguageModel(model, middleware: extractJsonMiddleware())
let simulatedStream = wrapLanguageModel(model, middleware: simulateStreamingMiddleware())
```

## MCP

`MCPClient` mirrors the core of official `@ai-sdk/mcp@2.0.54`: initialize handshake,
tool discovery, dynamic `AITool` conversion, resources, prompts, elicitation,
HTTP/SSE transport, stdio transport, and OAuth helpers.
OAuth providers can implement `authorize(resourceMetadataURL:scope:)` to receive
the scope advertised by `WWW-Authenticate` or Protected Resource Metadata; the
existing `authorize(resourceMetadataURL:)` requirement remains source-compatible.
The 2.0.54 behavior is absorbed in the protocol/HTTP transport and OAuth layers:
stored authorization-server information survives a discovery failure, and
concurrent stale-token 401 responses share one authorization refresh instead
of racing or clearing a newly saved token. Earlier behavior remains available
without changing the high-level `MCPClient` workflow. `MCPToolAnnotations`
provides typed access to standard title/read-only/destructive/idempotent/open-
world hints while the raw annotation object remains available; these are
untrusted server hints, not authorization policy. Structured-only tool results
are normalized into model-visible JSON text, malformed known annotations fail
tool discovery, and origin-only OAuth issuer URLs normalize a trailing slash.
Non-successful POST/SSE responses preserve HTTP status, URL, and body details;
upstream Windows command-shim handling has no Swift process-transport analogue.

```swift
let mcp = try await MCPClient.connect(
    transport: try MCPHTTPTransport(url: "https://mcp.example.com/rpc")
)

let tools = try await mcp.tools()
let answer = try await model.generateText(
    "Search the docs.",
    tools: LanguageToolOptions(Array(tools.values))
)
```

Focused examples live in `Tests/SwiftAISDKTests/MCP*Tests.swift`.

## Tests And Docs

Run the mock-backed suite:

```sh
swift test
```

Optional live smoke tests are available with real keys:

```sh
LIVE_AI_TESTS=1 swift test --filter LiveProviderSmoke
```

Cartesia live checks read `CARTESIA_API_KEY` and optionally
`LIVE_CARTESIA_SPEECH_MODEL`, `LIVE_CARTESIA_TRANSCRIPTION_MODEL`, and
`LIVE_CARTESIA_VOICE`.

Useful project docs:

- [Docs/README.md](Docs/README.md): documentation map and ownership.
- [Docs/ProductDocumentation.md](Docs/ProductDocumentation.md): public documentation contract and verification gates.
- [Docs/PortingStatus.md](Docs/PortingStatus.md): current porting status, active gaps, and release-readiness checklist.
- [Docs/AgentPortingGuide.md](Docs/AgentPortingGuide.md): workflow for porting upstream code, tests, and docs.
- [Docs/ProviderCapabilityMatrix.md](Docs/ProviderCapabilityMatrix.md): generated provider/capability table.
- [Docs/ProviderVersionLedger.md](Docs/ProviderVersionLedger.md): tracked npm package baselines and evidence files.

Future coding agents should also read [AGENTS.md](AGENTS.md) before making
porting changes.

The user-facing documentation site lives in `docs-site` and is generated before
build:

```sh
npm ci --prefix docs-site
npm --prefix docs-site run check
npm --prefix docs-site run build
```
