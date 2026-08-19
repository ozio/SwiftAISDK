# SwiftAISDK

SwiftAISDK is a SwiftPM port of the provider-facing parts of Vercel AI SDK.
It provides provider factories plus an `AI` facade for text, durable batches,
structured output, embeddings, media, streaming and realtime audio, reranking,
uploads, middleware, MCP tools, and typed tool execution.

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
terminal is preserved rather than assigned a guessed outcome. Provider
error events remain visible as repeatable in-band `error` parts on the full
stream; setup, HTTP, framing, and network failures throw. `toTextStream()`
intentionally emits only canonical text deltas and ignores in-band error parts,
while still propagating thrown stream failures.

Facade calls retry transient failures by default with `maxRetries: 2`.
Streaming retries only happen before the first emitted part, so already-delivered
chunks are not duplicated. Stopping iteration or aborting the request cancels
the upstream response body. Pass `retryPolicy: .none` or a custom
`AIRetryPolicy` to tune retries, backoff, and timeout.

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

## Durable Batch And Video Operations

Batch V4 exposes persistable text-batch references plus status and terminal
result streams. Anthropic Messages Batch and OpenAI Responses Batch implement
the shared adapter:

```swift
let anthropic = try AIProviders.anthropic()
let model = try anthropic.messages("claude-sonnet-4-5")
let started = try await AI.startTextBatch(
    model: model,
    requests: [TextBatchRequest(
        id: "summary-1",
        request: LanguageModelRequest(messages: [.user("Summarize this.")])
    )]
)

// OpenAI Responses uses the same facade:
let openAI = try AIProviders.openAI()
let openAIBatchModel = try openAI.batchLanguageModel("gpt-5.6")
```

Async Video V4 keeps unary `generateVideo` source compatible while adding
serializable start/status operations, core-owned polling/webhook waiting, and a
stable logical-start idempotency key. Black Forest Labs FLUX 3 and Fal expose
operation adapters; select the flow with `poll: VideoGenerationPollOptions(...)`
or a webhook registration. Fal forwards its native webhook URL, while BFL
warns and falls back to polling. Requests above a model's
`maxVideosPerCall` are split into independent starts and merged in input order.

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

## Realtime Sessions

`AIRealtimeModelV4` and `AIRealtimeSession` provide a provider-neutral duplex
session for text, audio, tool calls, normalized server events, aborts, and
explicit close/cancel behavior. xAI is the first full Realtime V4 adapter: it
creates an ephemeral client secret, negotiates the WebSocket subprotocol, maps
session/audio/text/tool events, and keeps provider-specific events available as
custom events.

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

Full provider adapters for non-xAI realtime speech sessions, Google/OpenAI
streaming translation, and ElevenLabs realtime transcription remain deferred.

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

`MCPClient` mirrors the core of official `@ai-sdk/mcp@2.0.33`: initialize handshake,
tool discovery, dynamic `AITool` conversion, resources, prompts, elicitation,
HTTP/SSE transport, stdio transport, and OAuth helpers.
OAuth providers can implement `authorize(resourceMetadataURL:scope:)` to receive
the scope advertised by `WWW-Authenticate` or Protected Resource Metadata; the
existing `authorize(resourceMetadataURL:)` requirement remains source-compatible.
The 2.0.33 compatibility patch is absorbed in the protocol/HTTP transport and
OAuth layers without changing the high-level `MCPClient` workflow. Public
wording stays conservative while that upstream source vertical settles.

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
