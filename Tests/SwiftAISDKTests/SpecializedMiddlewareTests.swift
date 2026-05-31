import Foundation
import Testing
@testable import SwiftAISDK

@Test func defaultEmbeddingSettingsMiddlewareAppliesDefaultsAndPreservesRequestValues() async throws {
    let model = SpecializedEmbeddingModel()
    let wrapped = wrapEmbeddingModel(
        model,
        middleware: defaultEmbeddingSettingsMiddleware(settings: AIDefaultEmbeddingModelSettings(
            providerOptions: [
                "openai": [
                    "encodingFormat": "float",
                    "metadata": [
                        "source": "default",
                        "keep": true
                    ]
                ]
            ],
            headers: ["X-Default": "yes", "X-Override": "default"]
        ))
    )

    _ = try await wrapped.embed(EmbeddingRequest(
        values: ["one"],
        providerOptions: [
            "openai": [
                "metadata": [
                    "source": "request"
                ]
            ]
        ],
        headers: ["X-Override": "request"]
    ))

    let request = try #require(model.requests.first)
    #expect(request.providerOptions["openai"]?["encodingFormat"]?.stringValue == "float")
    #expect(request.providerOptions["openai"]?["metadata"]?["source"]?.stringValue == "request")
    #expect(request.providerOptions["openai"]?["metadata"]?["keep"]?.boolValue == true)
    #expect(request.headers["X-Default"] == "yes")
    #expect(request.headers["X-Override"] == "request")
}

@Test func extractJsonMiddlewareStripsMarkdownFencesForGenerateAndStream() async throws {
    let model = SpecializedLanguageModel(
        result: TextGenerationResult(text: "```json\n{\"ok\":true}\n```", rawValue: .object([:])),
        streamParts: [
            .textStart(id: "0"),
            .textDeltaPart(id: "0", delta: "```json\n{\"ok\":"),
            .textDeltaPart(id: "0", delta: "true}\n```"),
            .textEnd(id: "0"),
            .finish(reason: "stop", usage: nil)
        ]
    )
    let wrapped = wrapLanguageModel(model, middleware: extractJsonMiddleware())

    let generated = try await wrapped.generate(LanguageModelRequest(messages: [.user("JSON")]))
    var streamed: [LanguageStreamPart] = []
    for try await part in wrapped.stream(LanguageModelRequest(messages: [.user("JSON")])) {
        streamed.append(part)
    }

    #expect(generated.text == "{\"ok\":true}")
    #expect(streamed == [
        .textStart(id: "0"),
        .textDeltaPart(id: "0", delta: "{\"ok\":true}"),
        .textEnd(id: "0"),
        .finish(reason: "stop", usage: nil)
    ])
}

@Test func extractReasoningMiddlewareMovesTaggedTextIntoReasoning() async throws {
    let model = SpecializedLanguageModel(result: TextGenerationResult(
        text: "<think>first</think>answer<think>second</think>done",
        rawValue: .object([:])
    ))
    let wrapped = wrapLanguageModel(
        model,
        middleware: extractReasoningMiddleware(tagName: "think")
    )

    let result = try await wrapped.generate(LanguageModelRequest(messages: [.user("Think")]))

    #expect(result.reasoning == "first\nsecond")
    #expect(result.text == "answer\ndone")
}

@Test func extractReasoningMiddlewareCanStartWithReasoningForGenerateAndStream() async throws {
    let model = SpecializedLanguageModel(
        result: TextGenerationResult(text: "hidden</think>visible", rawValue: .object([:])),
        streamParts: [
            .textDelta("hidden"),
            .textDelta("</think>visible"),
            .finish(reason: "stop", usage: nil)
        ]
    )
    let wrapped = wrapLanguageModel(
        model,
        middleware: extractReasoningMiddleware(tagName: "think", startWithReasoning: true)
    )

    let generated = try await wrapped.generate(LanguageModelRequest(messages: [.user("Think")]))
    var streamed: [LanguageStreamPart] = []
    for try await part in wrapped.stream(LanguageModelRequest(messages: [.user("Think")])) {
        streamed.append(part)
    }

    #expect(generated.reasoning == "hidden")
    #expect(generated.text == "visible")
    #expect(streamed == [
        .reasoningStart(id: "reasoning-0"),
        .reasoningDeltaPart(id: "reasoning-0", delta: "hidden"),
        .reasoningEnd(id: "reasoning-0"),
        .textStart(id: "0"),
        .textDeltaPart(id: "0", delta: "visible"),
        .textEnd(id: "0"),
        .finish(reason: "stop", usage: nil)
    ])
}

@Test func simulateStreamingMiddlewareBuildsStreamFromGenerateResult() async throws {
    let source = AISource(id: "src", sourceType: "url", url: "https://example.com")
    let toolCall = AIToolCall(id: "call", name: "lookup", arguments: "{}")
    let model = SpecializedLanguageModel(result: TextGenerationResult(
        text: "answer",
        reasoning: "because",
        finishReason: "stop",
        usage: TokenUsage(inputTokens: 1, outputTokens: 2, totalTokens: 3),
        toolCalls: [toolCall],
        sources: [source],
        rawValue: .object([:]),
        warnings: [AIWarning(type: "unsupported-setting", feature: "test", setting: "mode", message: "warning")]
    ))
    let wrapped = wrapLanguageModel(model, middleware: simulateStreamingMiddleware())

    var streamed: [LanguageStreamPart] = []
    for try await part in wrapped.stream(LanguageModelRequest(messages: [.user("Stream")])) {
        streamed.append(part)
    }

    #expect(model.generateRequests.count == 1)
    #expect(model.streamRequests.isEmpty)
    #expect(streamed == [
        .streamStart(warnings: [AIWarning(type: "unsupported-setting", feature: "test", setting: "mode", message: "warning")]),
        .reasoningStart(id: "0"),
        .reasoningDeltaPart(id: "0", delta: "because"),
        .reasoningEnd(id: "0"),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "answer"),
        .textEnd(id: "1"),
        .source(source),
        .toolCall(toolCall),
        .finish(reason: "stop", usage: TokenUsage(inputTokens: 1, outputTokens: 2, totalTokens: 3))
    ])
}

@Test func addToolInputExamplesMiddlewareAppendsExamplesToToolDescriptions() async throws {
    let model = SpecializedLanguageModel()
    let wrapped = wrapLanguageModel(model, middleware: addToolInputExamplesMiddleware())
    let tool: JSONValue = [
        "type": "function",
        "description": "Look up a value.",
        "inputExamples": [
            ["input": ["city": "Tokyo"]],
            ["input": ["city": "Paris"]]
        ]
    ]

    _ = try await wrapped.generate(LanguageModelRequest(
        messages: [.user("Use tool")],
        tools: ["lookup": tool]
    ))

    let transformed = try #require(model.generateRequests.first?.tools["lookup"])
    let description = try #require(transformed["description"]?.stringValue)
    #expect(description.contains("Look up a value.\n\nInput Examples:"))
    #expect(description.contains("{\"city\":\"Tokyo\"}"))
    #expect(description.contains("{\"city\":\"Paris\"}"))
    #expect(transformed["inputExamples"] == nil)
}

private final class SpecializedLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "specialized"
    let modelID = "language"
    var generateRequests: [LanguageModelRequest] = []
    var streamRequests: [LanguageModelRequest] = []
    private let result: TextGenerationResult
    private let streamParts: [LanguageStreamPart]

    init(
        result: TextGenerationResult = TextGenerationResult(text: "ok", rawValue: .object([:])),
        streamParts: [LanguageStreamPart] = []
    ) {
        self.result = result
        self.streamParts = streamParts
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        generateRequests.append(request)
        return result
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamRequests.append(request)
        let parts = streamParts
        return AsyncThrowingStream { continuation in
            for part in parts {
                continuation.yield(part)
            }
            continuation.finish()
        }
    }
}

private final class SpecializedEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    let providerID = "specialized"
    let modelID = "embedding"
    var requests: [EmbeddingRequest] = []

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        requests.append(request)
        return EmbeddingResult(embeddings: [[1]], rawValue: .object([:]))
    }
}
