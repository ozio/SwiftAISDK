# SwiftAISDK

SwiftAISDK is a SwiftPM port of the provider-facing parts of Vercel AI SDK.
It exposes provider factories plus an `AI` facade for text, objects,
embeddings, media, audio, reranking, uploads, and typed tool execution.

## Install

Add the package to `Package.swift`:

```swift
.package(url: "https://github.com/ozio/SwiftAISDK.git", branch: "main")
```

Then depend on the library product:

```swift
.product(name: "SwiftAISDK", package: "SwiftAISDK")
```

## Quick Start

```swift
import SwiftAISDK

let provider = try AIProviders.openAI()
let model = try provider.languageModel("gpt-4.1")

let result = try await AI.generateText(
    model: model,
    prompt: "Write one sentence about Swift."
)

print(result.text)
```

## Facade Calls

The `AI` facade mirrors the high-level shape of `@ai-sdk/ai` while using Swift
protocols for each model family:

```swift
let text = try await AI.generateText(model: model, prompt: "Hello")

for try await part in AI.streamText(model: model, prompt: "Stream this") {
    print(part)
}

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

Provider-specific options can be passed through request types or facade
overloads via `providerOptions`, `extraBody`, and `headers`.

Facade calls retry transient failures by default (`maxRetries: 2`). Streaming
calls retry only when the failure occurs before the first emitted part, so
already-delivered chunks are never duplicated. Pass `retryPolicy: .none` to
disable retries, or a custom `AIRetryPolicy` to tune retry count, backoff, and
per-attempt timeout:

```swift
let text = try await AI.generateText(
    model: model,
    prompt: "Hello",
    retryPolicy: AIRetryPolicy(
        maxRetries: 1,
        initialDelayNanoseconds: 500_000_000,
        timeoutNanoseconds: 30_000_000_000
    )
)
```

Telemetry integrations can observe facade lifecycle events, streaming
start/end/error events, object-generation events, and tool-loop step/tool
execution events:

```swift
struct LoggerTelemetry: AITelemetryIntegration {
    func record(_ event: AITelemetryEvent) async {
        print(event.kind, event.operationID, event.providerID)
    }
}

AITelemetry.register(LoggerTelemetry())
```

## Structured Output

`AI.generateObject` requests JSON output, validates it when a JSON Schema is
supplied, and decodes the result into a Swift `Decodable` type:

```swift
struct Summary: Decodable, Sendable {
    var title: String
    var bullets: [String]
}

let summarySchema = AIJSONSchema<Summary>(
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

let result = try await AI.generateObject(
    model: model,
    prompt: "Summarize this changelog.",
    schema: summarySchema
)

print(result.object.title)
```

Object generation also supports `jsonInstruction`, `repairText`, lifecycle
callbacks, and non-streaming array/enum/no-schema JSON strategies through
`generateObjectArray`, `generateEnum`, and `generateJSON`.

`AI.streamObject` is the streaming counterpart. It emits text deltas,
best-effort `JSONValue` partial objects, typed partials when possible, and the
final decoded object:

```swift
for try await part in AI.streamObject(
    model: model,
    prompt: "Stream a compact summary.",
    as: Summary.self
) {
    if case let .object(result) = part {
        print(result.object.title)
    }
}
```

Streaming variants are also available for upstream-style array, enum, and
no-schema JSON strategies through `streamObjectArray`, `streamEnum`, and
`streamJSON`.

## Tools

`AI.generateText` and `AI.streamText` can execute typed Swift tools and continue
the conversation until the model returns a final answer or `maxSteps` is
reached:

```swift
let weather = AITool(
    name: "weather",
    description: "Get the current weather.",
    parameters: [
        "type": "object",
        "properties": ["city": ["type": "string"]]
    ],
    refineArguments: { arguments in
        guard let city = arguments["city"]?.stringValue else {
            throw AIError.invalidArgument(argument: "city", message: "city is required.")
        }
        return ["city": .string(city.trimmingCharacters(in: .whitespacesAndNewlines))]
    }
) { arguments in
    ["forecast": "sunny in \(arguments["city"]?.stringValue ?? "unknown")"]
}

let answer = try await AI.generateText(
    model: model,
    prompt: "What should I wear in Tokyo?",
    executableTools: [weather],
    maxSteps: 3,
    stopWhen: [.isStepCount(2)]
)

print(answer.text)
```

Tool arguments are parsed, refined, and validated against the tool JSON Schema
before execution. Streaming tool loops yield model parts, tool input lifecycle
parts, and `.toolResult(...)` parts before the next model step starts.

Use `AITool.dynamic(...)` for runtime-discovered tools, including tools loaded
from MCP. Swift marks related tool calls, stream parts, tool results, and
follow-up messages with `dynamic: true`. Tools can also provide `toModelOutput`
when the model-facing follow-up content should differ from the raw Swift result.

Tool approval mirrors upstream policy hooks. Returning `.denied(...)` records an
approval response and sends an `execution-denied` tool result back into the
loop; returning `.userApproval` emits a `.toolApprovalRequest(...)` stream part
and stops before executing. OpenAI Responses MCP approvals round-trip through
the same core approval types.

Provider-defined tools live beside their provider helpers, for example
`OpenAITools.webSearch(...)`, `OpenAITools.fileSearch(...)`,
`OpenAITools.mcp(...)`, `OpenAITools.shell(...)`, `AnthropicTools`, `XAITools`,
`GoogleTools`, and `GatewayTools`.

## MCP

`MCPClient` mirrors the core of official `@ai-sdk/mcp`: it performs the
initialize handshake, lists server tools, converts them into dynamic `AITool`
values, maps MCP tool content into model output, reads resources/templates and
prompts, and can answer server elicitation requests when the transport supports
incoming JSON-RPC requests.

```swift
let mcp = try await MCPClient.connect(
    transport: try MCPHTTPTransport(url: "https://mcp.example.com/rpc")
)

let tools = try await mcp.tools()
let answer = try await AI.generateText(
    model: model,
    prompt: "Search the docs.",
    executableTools: Array(tools.values)
)
```

`MCPHTTPTransport` supports JSON and SSE responses, protocol/session headers,
`mcp-session-id`, inbound SSE reconnects, and DELETE session termination.
`MCPStdioTransport` supports local servers with `command`, `args`, `env`, and
`cwd`. Protected servers can use `MCPOAuthProvider`, `MCPOAuthDiscovery`, and
`MCPOAuth` for upstream-compatible metadata discovery, dynamic registration,
PKCE, token refresh, and callback exchange.

See `Tests/SwiftAISDKTests/MCP*Tests.swift` for focused HTTP, stdio, OAuth,
resource, prompt, elicitation, and tool-output examples.

## Provider Factories

Provider factories live under `AIProviders`, including OpenAI, Azure,
Anthropic, Google, Google Vertex, Gateway, xAI, Mistral, Groq, Cohere, Voyage,
Bedrock, Replicate, fal, Deepgram, ElevenLabs, and other official
`@ai-sdk/*` provider packages.

Use `customProvider(...)` or `AIProviders.customProvider(...)` to compose local
model aliases and a fallback provider, matching upstream's `customProvider`
surface:

```swift
let appProvider = customProvider(
    providerID: "app",
    languageModels: [
        "fast": try AIProviders.openAI().languageModel("gpt-4.1-mini")
    ],
    fallbackProvider: try AIProviders.gateway()
)

let fast = try appProvider.languageModel("fast")
let fallback = try appProvider.languageModel("anthropic/claude-sonnet-4")
```

Use `createProviderRegistry(...)` when you want upstream-style combined IDs:

```swift
let registry = createProviderRegistry([
    "openai": try AIProviders.openAI(),
    "anthropic": try AIProviders.anthropic()
])

let chat = try registry.languageModel("openai:gpt-4.1-mini")
let claude = try registry.languageModel("anthropic:claude-sonnet-4-20250514")
```

The `AI` facade can resolve string model IDs through an explicit provider or a
global default provider:

```swift
AIDefaultProvider.set(registry)

let result = try await AI.generateText(
    model: "openai:gpt-4.1-mini",
    prompt: "Write a launch checklist."
)
```

## Middleware

Registries and individual models can be wrapped with middleware, mirroring
upstream `wrapLanguageModel`, `wrapImageModel`, `wrapEmbeddingModel`,
`wrapProvider`, specialized text transforms, and default settings helpers:

```swift
let tunedModel = wrapLanguageModel(
    model,
    middleware: defaultSettingsMiddleware(settings: AIDefaultLanguageModelSettings(
        temperature: 0.3,
        providerOptions: ["openai": ["parallelToolCalls": false]]
    ))
)

let jsonReady = wrapLanguageModel(model, middleware: extractJsonMiddleware())
let reasoningReady = wrapLanguageModel(model, middleware: extractReasoningMiddleware(tagName: "think"))
let simulatedStream = wrapLanguageModel(model, middleware: simulateStreamingMiddleware())
```

## Provider Matrix And Sync Docs

Use `AIProviderCapabilities.all` for a machine-readable provider/capability
matrix, or read [Docs/ProviderCapabilityMatrix.md](Docs/ProviderCapabilityMatrix.md)
for the generated human table.

Optional live smoke tests are available with real keys:

```sh
LIVE_AI_TESTS=1 swift test --filter LiveProviderSmoke
```

The live suite covers first-party text generation, text streaming, executable
generate/stream tool loops, and representative embeddings. Override model IDs
with `LIVE_OPENAI_MODEL`, `LIVE_ANTHROPIC_MODEL`, `LIVE_GOOGLE_MODEL`,
`LIVE_OPENAI_EMBEDDING_MODEL`, and `LIVE_GOOGLE_EMBEDDING_MODEL`.

See [Docs/UpstreamSync.md](Docs/UpstreamSync.md) for the upstream porting
workflow, [Docs/ProviderVersionLedger.md](Docs/ProviderVersionLedger.md) for
tracked npm baselines, and [Docs/ProductGapAudit.md](Docs/ProductGapAudit.md)
for remaining product-level gaps.
