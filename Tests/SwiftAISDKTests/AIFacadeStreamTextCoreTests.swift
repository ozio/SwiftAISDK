import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiRetryPolicyRejectsInvalidTimeout() async throws {
    let model = MockLanguageModel(result: TextGenerationResult(text: "unused", rawValue: .object([:])))

    do {
        _ = try await AI.generateText(
            model: model,
            prompt: "Invalid timeout",
            retryPolicy: AIRetryPolicy(timeoutNanoseconds: 0)
        )
        Issue.record("Expected invalid timeout.")
    } catch let error as AIError {
        #expect(error == .invalidArgument(argument: "timeoutNanoseconds", message: "timeoutNanoseconds must be greater than zero."))
    }

    #expect(model.requests.isEmpty)
}
@Test func aiStreamTextForwardsRequestToModel() async throws {
    let recorder = TelemetryRecorder()
    let warning = AIWarning(type: "unsupported", feature: "seed")
    let responseMetadata = AIResponseMetadata(id: "stream-resp")
    let parts: [LanguageStreamPart] = [
        .streamStart(warnings: [warning]),
        .textDelta("hi"),
        .metadata(["mock": .object(["stream": .bool(true)])]),
        .responseMetadata(responseMetadata),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 1))
    ]
    let model = MockLanguageModel(result: TextGenerationResult(text: "", rawValue: .object([:])), streamParts: parts)

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "Stream",
        includeRawChunks: true,
        telemetry: Telemetry.Options(integrations: [recorder])
    ) {
        streamed.append(part)
    }
    let events = await recorder.events()

    #expect(streamed == [
        .streamStart(warnings: [warning]),
        .textStart(id: "legacy-text-0"),
        .textDeltaPart(id: "legacy-text-0", delta: "hi"),
        .metadata(["mock": .object(["stream": .bool(true)])]),
        .responseMetadata(responseMetadata),
        .textEnd(id: "legacy-text-0"),
        .finishMetadata(reason: "stop", usage: TokenUsage(totalTokens: 1), providerMetadata: [:])
    ])
    #expect(events.map(\.kind) == [.start, .end])
    #expect(events.allSatisfy { $0.operationID == "ai.streamText" })
    #expect(events[0].input?["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Stream")
    #expect(events[1].output?["text"]?.stringValue == "hi")
    #expect(events[1].usage == TokenUsage(totalTokens: 1))
    #expect(events[1].warnings == [warning])
    #expect(events[1].providerMetadata["mock"]?["stream"]?.boolValue == true)
    #expect(events[1].responseMetadata == responseMetadata)
    #expect(model.streamRequests.count == 1)
    #expect(model.streamRequests.first?.messages == [.user("Stream")])
    #expect(model.streamRequests.first?.includeRawChunks == true)
}

@Test func aiStreamTextExecutesModelStreamInsideTelemetryLanguageModelContextLikeUpstream() async throws {
    let probe = LanguageModelCallContextProbe()
    let model = ContextCapturingStreamLanguageModel(
        probe: probe,
        streamParts: [
            .textDelta("done"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 1))
        ]
    )

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "test-input",
        retryPolicy: .none,
        telemetry: Telemetry.Options(integrations: [
            ContextActivatingLanguageModelTelemetry(probe: probe)
        ])
    ) {
        streamed.append(part)
    }

    #expect(streamed == [
        .textStart(id: "legacy-text-0"),
        .textDeltaPart(id: "legacy-text-0", delta: "done"),
        .textEnd(id: "legacy-text-0"),
        .finishMetadata(reason: "stop", usage: TokenUsage(totalTokens: 1), providerMetadata: [:])
    ])
    #expect(probe.capturedCallID() == probe.integrationCallID())
    #expect(probe.capturedCallID() != nil)
}

@Test func aiStreamTextTelemetryCallsMultiplePerCallIntegrationsLikeUpstream() async throws {
    let log = ExecutionWrapperLog()
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta("Hello, world!"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 3))
        ]
    )

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "test-input",
        telemetry: Telemetry.Options(integrations: [
            StartEventTelemetry(name: "first", log: log),
            StartEventTelemetry(name: "second", log: log)
        ])
    ) {
        streamed.append(part)
    }

    #expect(streamed == [
        .textStart(id: "legacy-text-0"),
        .textDeltaPart(id: "legacy-text-0", delta: "Hello, world!"),
        .textEnd(id: "legacy-text-0"),
        .finishMetadata(reason: "stop", usage: TokenUsage(totalTokens: 3), providerMetadata: [:])
    ])
    #expect(await log.entries() == ["first", "second"])
}

@Test func aiStreamTextPassesHeadersToModelLikeUpstream() async throws {
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta("Hello"),
            .textDelta(", "),
            .textDelta("world!"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 3))
        ]
    )

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "test-input",
        headers: ["custom-request-header": "request-header-value"]
    ) {
        streamed.append(part)
    }

    #expect(streamed == [
        .textStart(id: "legacy-text-0"),
        .textDeltaPart(id: "legacy-text-0", delta: "Hello"),
        .textDeltaPart(id: "legacy-text-0", delta: ", "),
        .textDeltaPart(id: "legacy-text-0", delta: "world!"),
        .textEnd(id: "legacy-text-0"),
        .finishMetadata(reason: "stop", usage: TokenUsage(totalTokens: 3), providerMetadata: [:])
    ])
    #expect(model.streamRequests.count == 1)
    #expect(model.streamRequests[0].headers["custom-request-header"] == "request-header-value")
}

@Test func aiStreamTextForwardsRawChunksWhenRequestedLikeUpstream() async throws {
    let model = ConditionalRawChunkLanguageModel()

    let defaultParts = try await collectRawChunkFacadeParts(
        AI.streamText(model: model, prompt: "test prompt")
    )
    let disabledParts = try await collectRawChunkFacadeParts(
        AI.streamText(model: model, prompt: "test prompt", includeRawChunks: false)
    )
    let enabledParts = try await collectRawChunkFacadeParts(
        AI.streamText(model: model, prompt: "test prompt", includeRawChunks: true)
    )

    #expect(model.streamRequests.map(\.includeRawChunks) == [false, false, true])
    #expect(defaultParts.rawValues.isEmpty)
    #expect(defaultParts.textDeltas == ["Hello, world!"])
    #expect(disabledParts.rawValues.isEmpty)
    #expect(disabledParts.textDeltas == ["Hello, world!"])
    #expect(enabledParts.rawValues == [["type": "raw-data", "content": "should appear"]])
    #expect(enabledParts.textDeltas == ["Hello, world!"])
}

@Test func aiStreamTextPassesProviderOptionsAndReasoningToModelLikeUpstream() async throws {
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta("provider metadata test"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 3))
        ]
    )
    let providerDefaultModel = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta("provider default reasoning test"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 3))
        ]
    )

    var firstStreamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "test-input",
        reasoning: "high",
        providerOptions: ["aProvider": ["someKey": "someValue"]]
    ) {
        firstStreamed.append(part)
    }

    var secondStreamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: providerDefaultModel,
        prompt: "test-input",
        reasoning: "provider-default"
    ) {
        secondStreamed.append(part)
    }

    #expect(firstStreamed.contains(.textDeltaPart(id: "legacy-text-0", delta: "provider metadata test")))
    #expect(model.streamRequests.first?.providerOptions == ["aProvider": ["someKey": "someValue"]])
    #expect(model.streamRequests.first?.reasoning == "high")
    #expect(secondStreamed.contains(.textDeltaPart(id: "legacy-text-0", delta: "provider default reasoning test")))
    #expect(providerDefaultModel.streamRequests.first?.reasoning == "provider-default")
}
@Test func aiStreamTextEmitsAbortTelemetryWhenConsumerCancels() async throws {
    let recorder = TelemetryRecorder()
    let model = HangingStreamingLanguageModel()
    var streamed: [LanguageStreamPart] = []

    for try await part in AI.streamText(
        model: model,
        prompt: "Cancel stream",
        telemetry: Telemetry.Options(integrations: [recorder])
    ) {
        streamed.append(part)
        if case .textDeltaPart = part {
            break
        }
    }

    try await Task.sleep(nanoseconds: 20_000_000)
    let events = await recorder.events()

    #expect(streamed == [
        .textStart(id: "legacy-text-0"),
        .textDeltaPart(id: "legacy-text-0", delta: "first")
    ])
    #expect(events.map(\.kind) == [.start, .abort])
    #expect(events.allSatisfy { $0.operationID == "ai.streamText" })
    #expect(events[1].errorDescription?.contains("cancelled") == true)
}
@Test func aiStreamTextRetriesRetryableStartErrors() async throws {
    let recorder = TelemetryRecorder()
    let model = FlakyStreamingLanguageModel(outcomes: [
        .failure(AIError.apiCall(
            provider: "mock",
            statusCode: 429,
            body: "rate limited",
            headers: ["Retry-After": "0"]
        )),
        .parts([
            .textDelta("recovered"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 2))
        ])
    ])

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "Retry stream",
        retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 1_000_000_000),
        telemetry: Telemetry.Options(integrations: [recorder])
    ) {
        streamed.append(part)
    }
    let events = await recorder.events()

    #expect(streamed == [
        .textStart(id: "legacy-text-0"),
        .textDeltaPart(id: "legacy-text-0", delta: "recovered"),
        .textEnd(id: "legacy-text-0"),
        .finishMetadata(reason: "stop", usage: TokenUsage(totalTokens: 2), providerMetadata: [:])
    ])
    #expect(model.streamRequests.count == 2)
    #expect(events.map(\.kind) == [.start, .retry, .end])
    #expect(events[1].attempt == 1)
    #expect(events[1].delayNanoseconds == 0)
    #expect(events[1].errorDescription?.contains("HTTP 429") == true)
    #expect(events[2].output?["text"]?.stringValue == "recovered")
}

@Test func aiStreamTextRetriesAfterOutputWithAttemptIsolationLikeUpstream() async throws {
    let recorder = TelemetryRecorder()
    let failedCall = AIToolCall(id: "call-shared", name: "lookup", arguments: #"{"value":"failed"}"#)
    let successfulCall = AIToolCall(id: "call-shared", name: "lookup", arguments: #"{"value":"ok"}"#)
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .responseMetadata(AIResponseMetadata(id: "failed-response")),
                .textStart(id: "failed-text"),
                .textDeltaPart(id: "failed-text", delta: "partial "),
                .toolInputStart(id: "call-shared", name: "lookup"),
                .toolCall(failedCall),
                .providerError(AIStreamProviderError(
                    message: "provider error",
                    statusCode: 500
                ))
            ],
            [
                .responseMetadata(AIResponseMetadata(id: "successful-response")),
                .textStart(id: "successful-text"),
                .textDeltaPart(id: "successful-text", delta: "recovered"),
                .textEnd(id: "successful-text"),
                .toolInputStart(id: "call-shared", name: "lookup"),
                .toolInputEnd(id: "call-shared"),
                .toolCall(successfulCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ]
        ]
    )

    var parts: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "Recover",
        retryPolicy: .none,
        streamRetries: 1,
        telemetry: Telemetry.Options(integrations: [recorder])
    ) {
        parts.append(part)
    }

    #expect(model.streamRequests.count == 2)
    #expect(parts.contains(.textDeltaPart(id: "failed-text", delta: "partial ")))
    #expect(parts.contains(.textEnd(id: "failed-text")))
    #expect(parts.contains(.textDeltaPart(id: "successful-text", delta: "recovered")))
    #expect(!parts.contains(.toolCall(failedCall)))
    #expect(parts.contains(.toolCall(successfulCall)))
    #expect(!parts.contains(.error(message: "provider error")))

    let events = await recorder.events()
    #expect(events.map(\.kind) == [.start, .retry, .end])
    #expect(events[2].output?["text"]?.stringValue == "recovered")
    #expect(events[2].responseMetadata.id == "successful-response")
}

@Test func aiStreamTextDoesNotRetryNonRetryableProviderErrorsLikeUpstream() async throws {
    let recorder = TelemetryRecorder()
    let providerError = AIStreamProviderError(
        message: "invalid request",
        statusCode: 400,
        isRetryable: false
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .textStart(id: "failed-text"),
                .textDeltaPart(id: "failed-text", delta: "partial"),
                .providerError(providerError)
            ],
            [
                .textStart(id: "unused-text"),
                .textDeltaPart(id: "unused-text", delta: "unused"),
                .textEnd(id: "unused-text"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 1))
            ]
        ]
    )

    var parts: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "Do not retry",
        retryPolicy: .none,
        streamRetries: 1,
        telemetry: Telemetry.Options(integrations: [recorder])
    ) {
        parts.append(part)
    }

    #expect(model.streamRequests.count == 1)
    #expect(parts.contains { $0.streamProviderError == providerError })
    #expect(parts.contains(.finishMetadata(reason: "error", usage: nil, providerMetadata: [:])))
    #expect(await recorder.events().map(\.kind) == [.start, .end])
}

@Test func aiStreamTextRetriesResetStepStateBeforeBuildingNextPromptLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "tool-call-1", name: "lookup", arguments: "{}")
    let toolResult = AIToolResult(
        toolCallID: toolCall.id,
        toolName: toolCall.name,
        result: "tool result"
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .textStart(id: "failed-text"),
                .textDeltaPart(id: "failed-text", delta: "partial"),
                .providerError(AIStreamProviderError(message: "provider error", statusCode: 500))
            ],
            [
                .textStart(id: "recovered-text"),
                .textDeltaPart(id: "recovered-text", delta: "recovered"),
                .textEnd(id: "recovered-text"),
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .textStart(id: "final-text"),
                .textDeltaPart(id: "final-text", delta: "done"),
                .textEnd(id: "final-text"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 1))
            ]
        ]
    )
    let tool = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": [:]]
    ) { _ in
        "tool result"
    }

    var streamedText = ""
    for try await part in AI.streamText(
        model: model,
        prompt: "Recover",
        executableTools: [tool],
        maxSteps: 2,
        retryPolicy: .none,
        streamRetries: 1
    ) {
        if case let .textDeltaPart(_, delta, _) = part {
            streamedText += delta
        }
    }

    #expect(streamedText == "partialrecovereddone")
    #expect(model.streamRequests.count == 3)
    #expect(model.streamRequests[2].messages == [
        .user("Recover"),
        AIMessage(role: .assistant, content: [
            .text("recovered"),
            .toolCall(toolCall)
        ]),
        AIMessage(role: .tool, content: [.toolResult(toolResult)])
    ])
}

@Test func aiStreamTextRejectsNegativeStreamRetriesBeforeModelWork() async throws {
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: []
    )
    do {
        for try await _ in AI.streamText(
            model: model,
            prompt: "Invalid",
            retryPolicy: .none,
            streamRetries: -1
        ) {}
        Issue.record("Expected invalid streamRetries.")
    } catch let error as AIError {
        #expect(error == .invalidArgument(
            argument: "streamRetries",
            message: "streamRetries must be greater than or equal to zero."
        ))
    }
    #expect(model.streamRequests.isEmpty)
}

@Test func aiStreamTextWithZeroStreamRetriesDoesNotBufferToolInput() async throws {
    let toolInputObserved = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let releaseProvider = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let model = SuspendedToolInputLanguageModel(release: releaseProvider.stream)

    let consumer = Task { () throws -> [LanguageStreamPart] in
        var parts: [LanguageStreamPart] = []
        for try await part in AI.streamText(
            model: model,
            prompt: "Do not buffer",
            retryPolicy: .none,
            streamRetries: 0
        ) {
            parts.append(part)
            if case .toolInputStart = part {
                toolInputObserved.continuation.yield(())
                toolInputObserved.continuation.finish()
            }
        }
        return parts
    }

    #expect(await streamSignalArrives(toolInputObserved.stream))
    releaseProvider.continuation.yield(())
    releaseProvider.continuation.finish()
    let parts = try await consumer.value
    #expect(parts.contains(.toolInputStart(id: "call-1", name: "lookup")))
}

@Test func aiStreamTextRetryRejectsRecoveredStreamWithoutOutputOrFinish() async throws {
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [.providerError(AIStreamProviderError(message: "retry me", statusCode: 500))],
            []
        ]
    )

    do {
        for try await _ in AI.streamText(
            model: model,
            prompt: "Recover",
            retryPolicy: .none,
            streamRetries: 1
        ) {}
        Issue.record("Expected the empty recovered stream to fail.")
    } catch let error as AIError {
        #expect(error == .invalidResponse(
            provider: "mock",
            message: "No output generated. The model stream ended without a finish chunk."
        ))
    }
    #expect(model.streamRequests.count == 2)
}

@Test func aiStreamTextRetriesCloseEachFailedAttemptOnlyOnce() async throws {
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .textStart(id: "failed-a"),
                .textDeltaPart(id: "failed-a", delta: "a"),
                .providerError(AIStreamProviderError(message: "retry a", statusCode: 500))
            ],
            [
                .textStart(id: "failed-b"),
                .textDeltaPart(id: "failed-b", delta: "b"),
                .providerError(AIStreamProviderError(message: "retry b", statusCode: 500))
            ],
            [
                .textStart(id: "ok"),
                .textDeltaPart(id: "ok", delta: "done"),
                .textEnd(id: "ok"),
                .finish(reason: "stop", usage: nil)
            ]
        ]
    )

    var parts: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "Recover twice",
        retryPolicy: .none,
        streamRetries: 2
    ) {
        parts.append(part)
    }

    #expect(parts.filter { $0 == .textEnd(id: "failed-a") }.count == 1)
    #expect(parts.filter { $0 == .textEnd(id: "failed-b") }.count == 1)
    #expect(model.streamRequests.count == 3)
}

@Test func aiStreamTextThrowsAndRecordsTelemetryWhenProviderStreamFailsBeforeYieldingLikeUpstream() async throws {
    let recorder = TelemetryRecorder()
    let failure = AIError.apiCall(provider: "mock", statusCode: 500, body: "test error")
    let model = FlakyStreamingLanguageModel(outcomes: [.failure(failure)])
    var streamed: [LanguageStreamPart] = []

    do {
        for try await part in AI.streamText(
            model: model,
            prompt: "test-input",
            retryPolicy: .none,
            telemetry: Telemetry.Options(integrations: [recorder])
        ) {
            streamed.append(part)
        }
        Issue.record("Expected provider stream start failure.")
    } catch let error as AIError {
        #expect(error == failure)
    }

    let events = await recorder.events()
    #expect(streamed.isEmpty)
    #expect(model.streamRequests.count == 1)
    #expect(events.map(\.kind) == [.start, .error])
    #expect(events[1].operationID == "ai.streamText")
    #expect(events[1].errorDescription?.contains("HTTP 500") == true)
}

@Test func aiStreamTextPreservesRequestMessagesWhenRetryingLikeUpstream() async throws {
    let model = FlakyStreamingLanguageModel(outcomes: [
        .failure(AIError.apiCall(
            provider: "mock",
            statusCode: 500,
            body: "internal server error",
            headers: ["Retry-After": "0"]
        )),
        .parts([
            .textDelta("hello"),
            .textDelta(" "),
            .textDelta("world"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 3))
        ])
    ])
    let request = LanguageModelRequest(messages: [
        .system("INSTRUCTIONS"),
        .user("test-input")
    ])

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        request: request,
        retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 1_000_000_000)
    ) {
        streamed.append(part)
    }

    #expect(streamed == [
        .textStart(id: "legacy-text-0"),
        .textDeltaPart(id: "legacy-text-0", delta: "hello"),
        .textDeltaPart(id: "legacy-text-0", delta: " "),
        .textDeltaPart(id: "legacy-text-0", delta: "world"),
        .textEnd(id: "legacy-text-0"),
        .finishMetadata(reason: "stop", usage: TokenUsage(totalTokens: 3), providerMetadata: [:])
    ])
    #expect(model.streamRequests.count == 2)
    #expect(model.streamRequests[0].messages == request.messages)
    #expect(model.streamRequests[1].messages == request.messages)
}

@Test func aiStreamTextDoesNotRetryAfterYieldingPart() async throws {
    let model = FlakyStreamingLanguageModel(outcomes: [
        .partsThenFailure(
            [.textDelta("partial")],
            AIError.apiCall(provider: "mock", statusCode: 503, body: "interrupted")
        ),
        .parts([
            .textDelta("duplicated"),
            .finish(reason: "stop", usage: nil)
        ])
    ])

    var streamed: [LanguageStreamPart] = []
    do {
        for try await part in AI.streamText(
            model: model,
            prompt: "Do not duplicate",
            retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 0)
        ) {
            streamed.append(part)
        }
        Issue.record("Expected stream failure after first part.")
    } catch let error as AIError {
        #expect(error == .apiCall(provider: "mock", statusCode: 503, body: "interrupted"))
    }

    #expect(streamed == [
        .textStart(id: "legacy-text-0"),
        .textDeltaPart(id: "legacy-text-0", delta: "partial"),
        .textEnd(id: "legacy-text-0")
    ])
    #expect(model.streamRequests.count == 1)
}
@Test func aiStreamTextTimesOut() async throws {
    let recorder = TelemetryRecorder()
    let model = SlowStreamingLanguageModel(delayNanoseconds: 80_000_000)

    do {
        for try await _ in AI.streamText(
            model: model,
            prompt: "Too slow",
            timeoutNanoseconds: 1_000_000,
            telemetry: Telemetry.Options(integrations: [recorder])
        ) {}
        Issue.record("Expected stream timeout.")
    } catch let error as AIError {
        #expect(error == .timeout(durationNanoseconds: 1_000_000))
    }
    let events = await recorder.events(waitingForAtLeast: 2)

    #expect(events.map(\.kind) == [.start, .abort])
    #expect(events[1].operationID == "ai.streamText")
    #expect(events[1].errorDescription == "Total timeout of 1000000 nanoseconds exceeded.")
    #expect(model.streamRequests.count == 1)
}
@Test func aiStreamTextRejectsInvalidTimeout() async throws {
    let model = MockLanguageModel(result: TextGenerationResult(text: "", rawValue: .object([:])), streamParts: [])

    do {
        for try await _ in AI.streamText(
            model: model,
            prompt: "Invalid timeout",
            timeoutNanoseconds: 0
        ) {}
        Issue.record("Expected invalid timeout.")
    } catch let error as AIError {
        #expect(error == .invalidArgument(argument: "timeoutNanoseconds", message: "timeoutNanoseconds must be greater than zero."))
    }

    #expect(model.streamRequests.isEmpty)
}

private final class SuspendedToolInputLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "suspended-tool-input"
    private let release: AsyncStream<Void>

    init(release: AsyncStream<Void>) {
        self.release = release
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        TextGenerationResult(text: "", rawValue: .object([:]))
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        let release = release
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.toolInputStart(id: "call-1", name: "lookup"))
                var iterator = release.makeAsyncIterator()
                _ = await iterator.next()
                do {
                    try Task.checkCancellation()
                    continuation.yield(.toolInputEnd(id: "call-1"))
                    continuation.yield(.finish(reason: "tool-calls", usage: nil))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private func streamSignalArrives(_ stream: AsyncStream<Void>) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next() != nil
        }
        group.addTask {
            try? await Task<Never, Never>.sleep(nanoseconds: 1_000_000_000)
            return false
        }
        let result = await group.next() ?? false
        group.cancelAll()
        return result
    }
}
