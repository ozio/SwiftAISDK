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

    #expect(streamed == parts)
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
        .textDelta("done"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 1))
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
        .textDelta("Hello, world!"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 3))
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
        .textDelta("Hello"),
        .textDelta(", "),
        .textDelta("world!"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 3))
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

    #expect(firstStreamed.contains(.textDelta("provider metadata test")))
    #expect(model.streamRequests.first?.providerOptions == ["aProvider": ["someKey": "someValue"]])
    #expect(model.streamRequests.first?.reasoning == "high")
    #expect(secondStreamed.contains(.textDelta("provider default reasoning test")))
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
        break
    }

    try await Task.sleep(nanoseconds: 20_000_000)
    let events = await recorder.events()

    #expect(streamed == [.textDelta("first")])
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
        .textDelta("recovered"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 2))
    ])
    #expect(model.streamRequests.count == 2)
    #expect(events.map(\.kind) == [.start, .retry, .end])
    #expect(events[1].attempt == 1)
    #expect(events[1].delayNanoseconds == 0)
    #expect(events[1].errorDescription?.contains("HTTP 429") == true)
    #expect(events[2].output?["text"]?.stringValue == "recovered")
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
        .textDelta("hello"),
        .textDelta(" "),
        .textDelta("world"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 3))
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

    #expect(streamed == [.textDelta("partial")])
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
    let events = await recorder.events()

    #expect(events.map(\.kind) == [.start, .error])
    #expect(events[1].operationID == "ai.streamText")
    #expect(events[1].errorDescription?.contains("timed out") == true)
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
