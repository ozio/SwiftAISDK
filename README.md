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
    ]
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

Use `AIProviderCapabilities.all` for a machine-readable provider/capability
matrix, or read [Docs/ProviderCapabilityMatrix.md](Docs/ProviderCapabilityMatrix.md)
for the human table. Optional live smoke tests are available with real keys:

```sh
LIVE_AI_TESTS=1 swift test --filter LiveProviderSmoke
```

See [Docs/UpstreamSync.md](Docs/UpstreamSync.md) for the upstream porting
workflow and [Docs/ProductGapAudit.md](Docs/ProductGapAudit.md) for remaining
product-level gaps.
