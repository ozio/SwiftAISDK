# SwiftAISDK

SwiftAISDK is a SwiftPM port of the provider-facing parts of Vercel AI SDK.
It exposes provider factories plus an `AI` facade for common model calls,
embeddings, media, reranking, uploads, and typed tool execution.

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

The `AI` facade mirrors the high-level shape of `@ai-sdk/ai` while staying close
to Swift protocols:

```swift
let text = try await AI.generateText(model: model, prompt: "Hello")

for try await part in AI.streamText(model: model, prompt: "Stream this") {
    // handle LanguageStreamPart
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

Facade calls retry transient failures by default (`maxRetries: 2`), matching the
AI SDK product-level default. Pass `retryPolicy: .none` to disable retries, or a
custom `AIRetryPolicy` to tune retry count, backoff, and per-attempt timeout:

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

## Objects

`AI.generateObject` requests JSON output and decodes the result into a Swift
`Decodable` type:

```swift
struct Summary: Decodable, Sendable {
    var title: String
    var bullets: [String]
}

let result = try await AI.generateObject(
    model: model,
    prompt: "Summarize this changelog.",
    as: Summary.self,
    schema: [
        "type": "object",
        "properties": [
            "title": ["type": "string"],
            "bullets": ["type": "array", "items": ["type": "string"]]
        ],
        "required": ["title", "bullets"]
    ],
    schemaName: "summary"
)

print(result.object.title)
```

When a schema is supplied, the final decoded JSON is also checked against that
schema; `repairText` can repair parsing or schema-validation failures. Failed
object parsing throws `AIObjectGenerationError`, including the output strategy,
failure kind, schema path when available, original text, and whether repair was
attempted.

The facade also mirrors upstream's non-streaming object output strategies:
`generateObjectArray` wraps an element schema as `{ "elements": [...] }` for
the model and returns `[Element]`, `generateEnum` wraps allowed strings as
`{ "result": "..." }` and returns `String`, and `generateJSON` requests JSON
without a schema and returns raw `JSONValue`.

`AI.streamObject` is the streaming counterpart for `Decodable` output. It emits
text deltas and best-effort `JSONValue` partial objects while the model streams
JSON, then yields the final decoded object:

```swift
for try await part in AI.streamObject(
    model: model,
    prompt: "Stream a compact summary.",
    as: Summary.self
) {
    if case let .partialObject(partial) = part {
        print(partial)
    }
    if case let .object(result) = part {
        print(result.object.title)
    }
}
```

## Tools

`AI.generateText` and `AI.streamText` can execute typed Swift tools and continue
the conversation until the model returns a final answer or `maxSteps` is
reached. Use `stopWhen` to mirror upstream step controls such as `isStepCount`
and `hasToolCall`:

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
print(answer.steps.count)
```

Swift-executed tool arguments are parsed, refined, and validated against the
tool JSON Schema before the execute callback runs.

Streaming tools yield the model parts, then a `.toolResult(...)` part before the
next model step starts:

```swift
for try await part in AI.streamText(
    model: model,
    prompt: "What should I wear in Tokyo?",
    executableTools: [weather],
    maxSteps: 3,
    stopWhen: [.hasToolCall("weather")]
) {
    // handle LanguageStreamPart
}
```

Use `AITool.dynamic(...)` for runtime-discovered tools, such as tools loaded
from an MCP server. Dynamic tools are sent to providers as normal function
tools, while Swift marks related tool calls, stream parts, tool results, and
follow-up messages with `dynamic: true`:

```swift
let runtimeSearch = AITool.dynamic(
    name: "runtimeSearch",
    description: "Search a runtime tool source.",
    parameters: [
        "type": "object",
        "properties": ["query": ["type": "string"]]
    ]
) { arguments in
    ["items": ["Found \(arguments["query"]?.stringValue ?? "something")"]]
}
```

`MCPClient` mirrors the core of official `@ai-sdk/mcp`: it performs the MCP
initialize handshake, lists server tools, converts them into dynamic `AITool`
values, and can also read MCP resources, resource templates, and prompts:

```swift
let mcp = try await MCPClient.connect(
    transport: try MCPHTTPTransport(url: "https://mcp.example.com/rpc")
)
let mcpTools = try await mcp.tools()
let docs = try await mcp.listResources()
let topic = docs.resources.first?.name ?? "docs"
let summarize = try await mcp.experimentalGetPrompt(
    name: "summarize",
    arguments: ["topic": .string(topic)]
)

let answer = try await AI.generateText(
    model: model,
    prompt: summarize.messages.first?.content["text"]?.stringValue ?? "Search the docs.",
    executableTools: Array(mcpTools.values)
)
```

Use `toolApproval` when a tool call needs a policy decision before execution.
Returning `.denied(...)` records an approval response and sends an
`execution-denied` tool result back into the loop; returning `.userApproval`
emits a `.toolApprovalRequest(...)` stream part and stops before executing:

```swift
let guarded = try await AI.generateText(
    model: model,
    prompt: "Delete the temporary file.",
    executableTools: [deleteFile],
    toolApproval: { context in
        context.toolCall.name == "deleteFile" ? .userApproval : .notApplicable
    }
)
```

OpenAI Responses MCP approvals also round-trip through the same core approval
types: provider `mcp_approval_request` items surface as `AIToolApprovalRequest`,
and `AIToolApprovalResponse(providerExecuted: true)` is sent back as
`mcp_approval_response`.

Use `prepareStep` when a later tool-loop step needs different request settings
or a narrowed tool set:

```swift
let answer = try await AI.generateText(
    model: model,
    prompt: "Plan the day.",
    executableTools: [weather],
    maxSteps: 3,
    prepareStep: { context in
        guard context.stepNumber == 1 else { return nil }
        var request = context.request
        request.providerOptions["openai"] = ["parallelToolCalls": false]
        request.messages.append(.user("Use the tool result and answer directly."))
        return AIPrepareStepResult(request: request)
    }
)
```

## Provider Factories

Provider factories live under `AIProviders`, including OpenAI, Azure, Anthropic,
Google, Google Vertex, Gateway, xAI, Mistral, Groq, Cohere, Voyage, Bedrock,
Replicate, fal, Deepgram, ElevenLabs, and other official `@ai-sdk/*` provider
packages.

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

The `AI` facade can resolve upstream-style string model IDs through an explicit
provider or a global default provider:

```swift
AIDefaultProvider.set(registry)
let result = try await AI.generateText(
    model: "openai:gpt-4.1-mini",
    prompt: "Write a launch checklist."
)

let embedding = try await AI.embed(
    model: "openai:text-embedding-3-small",
    value: "SwiftAISDK"
)
```

Registries can also apply middleware to routed language and image models:

```swift
let tunedRegistry = createProviderRegistry(
    ["openai": try AIProviders.openAI()],
    languageModelMiddleware: defaultSettingsMiddleware(settings: AIDefaultLanguageModelSettings(
        temperature: 0.3
    )),
    imageModelMiddleware: AIImageModelMiddleware(transformRequest: { context in
        var request = context.request
        request.count = request.count ?? 1
        return request
    })
)
```

Language, image, and embedding models can be wrapped with middleware, mirroring
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

let tunedEmbeddings = wrapEmbeddingModel(
    embeddingModel,
    middleware: defaultEmbeddingSettingsMiddleware(settings: AIDefaultEmbeddingModelSettings(
        providerOptions: ["openai": ["encodingFormat": "float"]]
    ))
)

let jsonReady = wrapLanguageModel(model, middleware: extractJsonMiddleware())
let reasoningReady = wrapLanguageModel(model, middleware: extractReasoningMiddleware(tagName: "think"))
let simulatedStream = wrapLanguageModel(model, middleware: simulateStreamingMiddleware())
```

Use `AIProviderCapabilities.all` for a machine-readable provider/capability
matrix, or read [Docs/ProviderCapabilityMatrix.md](Docs/ProviderCapabilityMatrix.md)
for the generated human table. Optional live smoke tests are available with real
keys:

```sh
LIVE_AI_TESTS=1 swift test --filter LiveProviderSmoke
```

See [Docs/UpstreamSync.md](Docs/UpstreamSync.md) for the upstream porting
workflow and [Docs/ProductGapAudit.md](Docs/ProductGapAudit.md) for remaining
product-level gaps.
