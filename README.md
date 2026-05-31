# SwiftAISDK

SwiftAISDK is a SwiftPM port of the provider-facing parts of Vercel AI SDK.
It exposes provider factories plus an `AI` facade for common model calls,
embeddings, media, reranking, uploads, and first-pass tool execution.

## Install

Add the package to `Package.swift`:

```swift
.package(url: "https://github.com/ozio/SwiftAISDK.git", branch: "main")
```

Then depend on the library product:

```swift
.product(name: "ai-sdk-port", package: "SwiftAISDK")
```

## Quick Start

```swift
import ai_sdk_port

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
AI SDK product-level default. Pass `retryPolicy: .none` to disable retries or a
custom `AIRetryPolicy` to tune retry count and backoff:

```swift
let text = try await AI.generateText(
    model: model,
    prompt: "Hello",
    retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 500_000_000)
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

## Tools

`AI.generateText` can execute typed Swift tools and continue the conversation
until the model returns a final answer or `maxSteps` is reached:

```swift
let weather = AITool(
    name: "weather",
    description: "Get the current weather.",
    parameters: [
        "type": "object",
        "properties": ["city": ["type": "string"]]
    ]
) { arguments in
    ["forecast": "sunny in \(arguments["city"]?.stringValue ?? "unknown")"]
}

let answer = try await AI.generateText(
    model: model,
    prompt: "What should I wear in Tokyo?",
    executableTools: [weather],
    maxSteps: 3
)

print(answer.text)
print(answer.steps.count)
```

## Provider Factories

Provider factories live under `AIProviders`, including OpenAI, Azure, Anthropic,
Google, Google Vertex, Gateway, xAI, Mistral, Groq, Cohere, Voyage, Bedrock,
Replicate, fal, Deepgram, ElevenLabs, and other official `@ai-sdk/*` provider
packages.

See [Docs/UpstreamSync.md](Docs/UpstreamSync.md) for the upstream porting
workflow and [Docs/ProductGapAudit.md](Docs/ProductGapAudit.md) for remaining
product-level gaps.
