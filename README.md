# SwiftAISDK

SwiftAISDK is a SwiftPM port of the provider-facing parts of Vercel AI SDK.
It provides provider factories plus an `AI` facade for text, structured output,
embeddings, media, audio, reranking, uploads, middleware, MCP tools, and typed
tool execution.

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

The `AI` facade mirrors the high-level shape of `@ai-sdk/ai` while using Swift
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

Facade calls retry transient failures by default with `maxRetries: 2`.
Streaming retries only happen before the first emitted part, so already-delivered
chunks are not duplicated. Pass `retryPolicy: .none` or a custom
`AIRetryPolicy` to tune retries, backoff, and timeout.

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

## Providers

Provider factories live under `AIProviders`, including OpenAI, Azure,
Anthropic, Google, Google Vertex, Gateway, xAI, Mistral, Groq, Cohere, Voyage,
Bedrock, Replicate, fal, Deepgram, ElevenLabs, and other official
`@ai-sdk/*` provider packages.

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

let jsonReady = wrapLanguageModel(model, middleware: extractJsonMiddleware())
let simulatedStream = wrapLanguageModel(model, middleware: simulateStreamingMiddleware())
```

## MCP

`MCPClient` mirrors the core of official `@ai-sdk/mcp`: initialize handshake,
tool discovery, dynamic `AITool` conversion, resources, prompts, elicitation,
HTTP/SSE transport, stdio transport, and OAuth helpers.

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
npm --prefix docs-site run build
```
