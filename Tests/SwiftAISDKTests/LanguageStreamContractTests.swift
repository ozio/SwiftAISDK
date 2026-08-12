import Testing
@testable import SwiftAISDK

@Test func languageModelDefaultSimulatedStreamIsCanonical() async throws {
    let usage = TokenUsage(totalTokens: 2)
    let model = GenerateOnlyContractLanguageModel(result: TextGenerationResult(
        text: "answer",
        reasoning: "thought",
        finishReason: "stop",
        usage: usage,
        rawValue: .object([:]),
        warnings: [AIWarning(type: "other", message: "warning")]
    ))

    let parts = try await collectLanguageContractParts(model.stream(
        LanguageModelRequest(messages: [.user("Hi")])
    ))

    #expect(parts == [
        .streamStart(warnings: [AIWarning(type: "other", message: "warning")]),
        .reasoningStart(id: "0"),
        .reasoningDeltaPart(id: "0", delta: "thought"),
        .reasoningEnd(id: "0"),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "answer"),
        .textEnd(id: "1"),
        .finishMetadata(reason: "stop", usage: usage, providerMetadata: [:])
    ])
}

@Test func languageStreamFacadeNormalizesLegacyOnlyChannelsWithStableIDs() async throws {
    let usage = TokenUsage(inputTokens: 1, outputTokens: 2, totalTokens: 3)
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "unused", rawValue: .object([:])),
        streamParts: [
            .textDelta("Hel"),
            .textDelta("lo"),
            .reasoningDelta("Because"),
            .finish(reason: "stop", usage: usage)
        ]
    )

    let parts = try await collectLanguageContractParts(AI.streamText(
        model: model,
        request: LanguageModelRequest(messages: [.user("Hi")]),
        retryPolicy: .none
    ))

    #expect(parts == [
        .textStart(id: "legacy-text-0"),
        .textDeltaPart(id: "legacy-text-0", delta: "Hel"),
        .textDeltaPart(id: "legacy-text-0", delta: "lo"),
        .reasoningStart(id: "legacy-reasoning-0"),
        .reasoningDeltaPart(id: "legacy-reasoning-0", delta: "Because"),
        .textEnd(id: "legacy-text-0"),
        .reasoningEnd(id: "legacy-reasoning-0"),
        .finishMetadata(reason: "stop", usage: usage, providerMetadata: [:])
    ])
}

@Test func languageStreamNormalizerRejectsEqualMixedDeltasInsteadOfValueDeduplicating() async throws {
    let stream = canonicalLanguageStream(languageContractStream([
        .textStart(id: "canonical"),
        .textDeltaPart(id: "canonical", delta: "same"),
        .textDelta("same")
    ]), providerID: "custom")
    var received: [LanguageStreamPart] = []

    await #expect(throws: AIError.invalidResponse(
        provider: "custom",
        message: "Language stream mixed legacy and canonical text chunks. Emit exactly one representation per channel."
    )) {
        for try await part in stream {
            received.append(part)
        }
    }

    #expect(received == [
        .textStart(id: "canonical"),
        .textDeltaPart(id: "canonical", delta: "same"),
        .textEnd(id: "canonical")
    ])
}

@Test func languageStreamNormalizerAllowsMultipleCanonicalLogicalResponses() async throws {
    let firstUsage = TokenUsage(totalTokens: 1)
    let secondUsage = TokenUsage(totalTokens: 2)
    let parts = try await collectLanguageContractParts(canonicalLanguageStream(languageContractStream([
        .responseMetadata(AIResponseMetadata(id: "response-1")),
        .textStart(id: "text-1"),
        .textDeltaPart(id: "text-1", delta: "one"),
        .textEnd(id: "text-1"),
        .finishMetadata(reason: "stop", usage: firstUsage, providerMetadata: [:]),
        .responseMetadata(AIResponseMetadata(id: "response-2")),
        .textStart(id: "text-2"),
        .textDeltaPart(id: "text-2", delta: "two"),
        .textEnd(id: "text-2"),
        .finishMetadata(reason: "length", usage: secondUsage, providerMetadata: [:])
    ]), providerID: "openai.responses"))

    #expect(parts.filter { part in
        if case .finishMetadata = part { return true }
        return false
    }.count == 2)
}

@Test func languageStreamNormalizerResetsLegacyRepresentationsForANewLogicalResponse() async throws {
    let parts = try await collectLanguageContractParts(canonicalLanguageStream(languageContractStream([
        .streamStart(warnings: []),
        .textDelta("one"),
        .finish(reason: "stop", usage: nil),
        .responseMetadata(AIResponseMetadata(id: "response-2")),
        .textDelta("two"),
        .finish(reason: "stop", usage: nil)
    ]), providerID: "custom"))

    #expect(parts == [
        .streamStart(warnings: []),
        .textStart(id: "legacy-text-0"),
        .textDeltaPart(id: "legacy-text-0", delta: "one"),
        .textEnd(id: "legacy-text-0"),
        .finishMetadata(reason: "stop", usage: nil, providerMetadata: [:]),
        .responseMetadata(AIResponseMetadata(id: "response-2")),
        .textStart(id: "legacy-text-1"),
        .textDeltaPart(id: "legacy-text-1", delta: "two"),
        .textEnd(id: "legacy-text-1"),
        .finishMetadata(reason: "stop", usage: nil, providerMetadata: [:])
    ])
}

@Test func languageStreamNormalizerResetsForLegacyDeltaImmediatelyAfterTerminal() async throws {
    let parts = try await collectLanguageContractParts(canonicalLanguageStream(languageContractStream([
        .textDelta("first"),
        .finish(reason: "stop", usage: nil),
        .textDelta("second"),
        .finish(reason: "stop", usage: nil)
    ]), providerID: "legacy-multi-response"))

    #expect(parts == [
        .textStart(id: "legacy-text-0"),
        .textDeltaPart(id: "legacy-text-0", delta: "first"),
        .textEnd(id: "legacy-text-0"),
        .finishMetadata(reason: "stop", usage: nil, providerMetadata: [:]),
        .textStart(id: "legacy-text-1"),
        .textDeltaPart(id: "legacy-text-1", delta: "second"),
        .textEnd(id: "legacy-text-1"),
        .finishMetadata(reason: "stop", usage: nil, providerMetadata: [:])
    ])
}

@Test func languageStreamNormalizerRejectsDuplicateTerminalWithoutLifecycleBoundary() async throws {
    let stream = canonicalLanguageStream(languageContractStream([
        .finishMetadata(reason: "stop", usage: nil, providerMetadata: [:]),
        .finishMetadata(reason: "stop", usage: nil, providerMetadata: [:])
    ]), providerID: "custom")

    await #expect(throws: AIError.invalidResponse(
        provider: "custom",
        message: "Language stream emitted more than one terminal chunk for a single logical response."
    )) {
        for try await _ in stream {}
    }
}

@Test func languageStreamFacadeForwardsRepeatedErrorsAndSynthesizesOneErrorTerminal() async throws {
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "unused", rawValue: .object([:])),
        streamParts: [
            .error(message: "boom", rawValue: ["code": "first"]),
            .error(message: "boom", rawValue: ["code": "first"])
        ]
    )

    let parts = try await collectLanguageContractParts(AI.streamText(
        model: model,
        request: LanguageModelRequest(messages: [.user("Hi")]),
        retryPolicy: AIRetryPolicy(maxRetries: 2, initialDelayNanoseconds: 0)
    ))

    #expect(parts == [
        .error(message: "boom", rawValue: ["code": "first"]),
        .error(message: "boom", rawValue: ["code": "first"]),
        .finishMetadata(reason: "error", usage: nil, providerMetadata: [:])
    ])
    #expect(model.streamRequests.count == 1)
}

@Test func languageStreamFacadeClosesCanonicalPartsBeforeSynthesizedErrorTerminal() async throws {
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "unused", rawValue: .object([:])),
        streamParts: [
            .textStart(id: "text"),
            .textDeltaPart(id: "text", delta: "partial"),
            .toolInputStart(id: "tool", name: "lookup"),
            .toolInputDelta(id: "tool", delta: "{"),
            .error(message: "stream failed")
        ]
    )

    let parts = try await collectLanguageContractParts(AI.streamText(
        model: model,
        request: LanguageModelRequest(messages: [.user("Hi")]),
        retryPolicy: .none
    ))

    #expect(parts.suffix(3) == [
        .textEnd(id: "text"),
        .toolInputEnd(id: "tool"),
        .finishMetadata(reason: "error", usage: nil, providerMetadata: [:])
    ])
}

@Test func languageStreamFacadeRewritesNilTerminalReasonAfterInBandError() async throws {
    let usage = TokenUsage(totalTokens: 3)
    let metadata: [String: JSONValue] = ["provider": ["requestId": "request-1"]]
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "unused", rawValue: .object([:])),
        streamParts: [
            .error(message: "provider warning"),
            .finishMetadata(reason: nil, usage: usage, providerMetadata: metadata)
        ]
    )

    let parts = try await collectLanguageContractParts(AI.streamText(
        model: model,
        request: LanguageModelRequest(messages: [.user("Hi")]),
        retryPolicy: .none
    ))

    #expect(parts == [
        .error(message: "provider warning"),
        .finishMetadata(reason: "error", usage: usage, providerMetadata: metadata)
    ])
}

@Test func languageStreamFacadeDoesNotSynthesizeTerminalAfterProviderTerminal() async throws {
    let usage = TokenUsage(totalTokens: 4)
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "unused", rawValue: .object([:])),
        streamParts: [
            .error(message: "recoverable event"),
            .finishMetadata(reason: "stop", usage: usage, providerMetadata: ["provider": true])
        ]
    )

    let parts = try await collectLanguageContractParts(AI.streamText(
        model: model,
        request: LanguageModelRequest(messages: [.user("Hi")]),
        retryPolicy: .none
    ))

    #expect(parts == [
        .error(message: "recoverable event"),
        .finishMetadata(reason: "stop", usage: usage, providerMetadata: ["provider": true])
    ])
}

@Test func languageStreamFacadeDoesNotSynthesizeErrorTerminalWhenTheStreamThrows() async throws {
    let model = ThrowingAfterErrorContractLanguageModel()
    var received: [LanguageStreamPart] = []

    await #expect(throws: AIError.invalidResponse(provider: "custom", message: "stream failed")) {
        for try await part in AI.streamText(
            model: model,
            request: LanguageModelRequest(messages: [.user("Hi")]),
            retryPolicy: AIRetryPolicy(maxRetries: 2, initialDelayNanoseconds: 0)
        ) {
            received.append(part)
        }
    }

    #expect(received == [.error(message: "visible")])
    #expect(model.streamCalls == 1)
}

@Test func languageTextStreamNormalizesLegacyTextAndIgnoresInBandErrors() async throws {
    let stream = toTextStream(languageContractStream([
        .error(message: "first"),
        .textDelta("A"),
        .error(message: "second"),
        .textDelta("B"),
        .finish(reason: "error", usage: nil)
    ]))
    var chunks: [String] = []
    for try await chunk in stream {
        chunks.append(chunk)
    }

    #expect(chunks == ["A", "B"])
}

@Test func smoothStreamCanonicalizesLegacyChunksWithoutDuplicatingText() async throws {
    let parts = try await collectLanguageContractParts(smoothStream(languageContractStream([
        .textDelta("Hello "),
        .textDelta("world"),
        .finish(reason: "stop", usage: nil)
    ]), delayNanoseconds: nil))

    #expect(parts == [
        .textStart(id: "legacy-text-0"),
        .textDeltaPart(id: "legacy-text-0", delta: "Hello "),
        .textDeltaPart(id: "legacy-text-0", delta: "world"),
        .textEnd(id: "legacy-text-0"),
        .finishMetadata(reason: "stop", usage: nil, providerMetadata: [:])
    ])
}

@Test func streamMiddlewaresPreserveMetadataOnlyCanonicalDeltas() async throws {
    let metadata: [String: JSONValue] = ["anthropic": ["signature": "sig"]]

    let smoothed = try await collectLanguageContractParts(smoothStream(languageContractStream([
        .reasoningStart(id: "reasoning"),
        .reasoningDeltaPart(id: "reasoning", delta: "done "),
        .reasoningDeltaPart(id: "reasoning", delta: "", providerMetadata: metadata),
        .reasoningEnd(id: "reasoning")
    ]), delayNanoseconds: nil))
    let transformed = try await collectLanguageContractParts(transformTextStream(
        languageContractStream([
            .textStart(id: "json"),
            .textDeltaPart(id: "json", delta: "value", providerMetadata: metadata),
            .textEnd(id: "json")
        ]),
        transform: { $0 }
    ))
    let extracted = try await collectLanguageContractParts(extractReasoningStream(
        languageContractStream([
            .textStart(id: "answer"),
            .textDeltaPart(
                id: "answer",
                delta: "<think>why</think>yes",
                providerMetadata: metadata
            ),
            .textEnd(id: "answer")
        ]),
        tagName: "think",
        separator: "\n",
        startWithReasoning: false
    ))

    #expect(smoothed.contains(.reasoningDeltaPart(
        id: "reasoning",
        delta: "",
        providerMetadata: metadata
    )))
    #expect(transformed.contains(.textDeltaPart(
        id: "json",
        delta: "value",
        providerMetadata: metadata
    )))
    #expect(extracted.contains { part in
        switch part {
        case let .textDeltaPart(_, _, providerMetadata),
             let .reasoningDeltaPart(_, _, providerMetadata):
            return providerMetadata == metadata
        default:
            return false
        }
    })
}

@Test func extractionMiddlewareFlushesBufferedTextAtCanonicalTerminal() async throws {
    let usage = TokenUsage(totalTokens: 1)
    let jsonParts = try await collectLanguageContractParts(transformTextStream(
        languageContractStream([
            .textStart(id: "json"),
            .textDeltaPart(id: "json", delta: "```json\n{\"ok\":true}\n```"),
            .finishMetadata(reason: "stop", usage: usage, providerMetadata: [:])
        ]),
        transform: defaultExtractJSONTransform
    ))
    let reasoningParts = try await collectLanguageContractParts(extractReasoningStream(
        languageContractStream([
            .textStart(id: "answer"),
            .textDeltaPart(id: "answer", delta: "<think>why</think>yes"),
            .finishMetadata(reason: "stop", usage: usage, providerMetadata: [:])
        ]),
        tagName: "think",
        separator: "\n",
        startWithReasoning: false
    ))

    #expect(jsonParts == [
        .textStart(id: "json"),
        .textDeltaPart(id: "json", delta: "{\"ok\":true}"),
        .textEnd(id: "json"),
        .finishMetadata(reason: "stop", usage: usage, providerMetadata: [:])
    ])
    #expect(reasoningParts == [
        .reasoningStart(id: "reasoning-0"),
        .reasoningDeltaPart(id: "reasoning-0", delta: "why"),
        .reasoningEnd(id: "reasoning-0"),
        .textStart(id: "answer"),
        .textDeltaPart(id: "answer", delta: "yes"),
        .textEnd(id: "answer"),
        .finishMetadata(reason: "stop", usage: usage, providerMetadata: [:])
    ])
}

@Test func uiReducerNormalizesLegacyStreamAndAccumulatesTextOnce() async throws {
    let snapshots = AIUIMessageStreamReducer.snapshots(from: languageContractStream([
        .textDelta("hel"),
        .textDelta("lo"),
        .finish(reason: "stop", usage: nil)
    ]), messageID: "message")
    var finalMessage: AIUIMessage?
    for try await snapshot in snapshots {
        finalMessage = snapshot
    }

    let text = finalMessage?.parts.compactMap { part -> String? in
        if case let .text(textPart) = part { return textPart.text }
        return nil
    }.joined()
    #expect(text == "hello")
    #expect(finalMessage?.metadata["finishReason"] == .string("stop"))
}

@Test func outputTextAndToolStepAccumulateCanonicalDeltaOnce() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "unused", rawValue: .object([:])),
        streamParts: [
            .textDelta("hello"),
            .finish(reason: "stop", usage: nil)
        ]
    )
    var output: AIOutputGenerationResult<String>?
    for try await part in AI.streamText(model: model, prompt: "Hi", output: Output.text()) {
        if case let .output(result) = part {
            output = result
        }
    }

    var step = LanguageStreamToolStep()
    step.record(.textStart(id: "text"))
    step.record(.textDeltaPart(id: "text", delta: "hello"))
    step.record(.textEnd(id: "text"))
    step.record(.error(message: "visible"))
    let toolStep = step.toolStep(
        index: 0,
        toolResults: [],
        approvalRequests: [],
        approvalResponses: []
    )

    #expect(output?.text == "hello")
    #expect(step.text == "hello")
    #expect(step.finishReason == "error")
    #expect(step.hasUnterminatedInBandError)
    #expect(toolStep.text == "hello")
    #expect(toolStep.finishReason == "error")
}

private func languageContractStream(
    _ parts: [LanguageStreamPart]
) -> AsyncThrowingStream<LanguageStreamPart, Error> {
    AsyncThrowingStream { continuation in
        for part in parts {
            continuation.yield(part)
        }
        continuation.finish()
    }
}

private func collectLanguageContractParts(
    _ stream: AsyncThrowingStream<LanguageStreamPart, Error>
) async throws -> [LanguageStreamPart] {
    var parts: [LanguageStreamPart] = []
    for try await part in stream {
        parts.append(part)
    }
    return parts
}

private final class GenerateOnlyContractLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "generate-only"
    let modelID = "generate-only"
    private let result: TextGenerationResult

    init(result: TextGenerationResult) {
        self.result = result
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        result
    }
}

private final class ThrowingAfterErrorContractLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "custom"
    let modelID = "throwing-after-error"
    var streamCalls = 0

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        TextGenerationResult(text: "unused", rawValue: .object([:]))
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamCalls += 1
        return AsyncThrowingStream { continuation in
            continuation.yield(.error(message: "visible"))
            continuation.finish(throwing: AIError.invalidResponse(provider: providerID, message: "stream failed"))
        }
    }
}
