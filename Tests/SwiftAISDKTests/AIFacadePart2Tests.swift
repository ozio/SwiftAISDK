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
@Test func aiStreamTextExecutesTypedToolsAndContinuesUntilFinalStream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"query":"weather"}"#)
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .streamStart(warnings: []),
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .textDelta("It "),
                .textDelta("is sunny."),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 8))
            ]
        ]
    )
    let capture = ToolCapture()
    let lookup = AITool(
        name: "lookup",
        description: "Look up a value.",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]]
    ) { arguments in
        await capture.record(arguments)
        return ["forecast": "sunny"]
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 3
    ) {
        streamed.append(part)
    }

    #expect(streamed == [
        .streamStart(warnings: []),
        .toolCall(toolCall),
        .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3)),
        .toolResult(AIToolResult(toolCallID: "call-1", toolName: "lookup", result: ["forecast": "sunny"])),
        .textDelta("It "),
        .textDelta("is sunny."),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 8))
    ])
    #expect(await capture.value()?["query"]?.stringValue == "weather")
    #expect(model.streamRequests.count == 2)
    #expect(model.streamRequests[0].tools["lookup"]?["description"]?.stringValue == "Look up a value.")
    #expect(model.streamRequests[1].messages.count == 3)
    #expect(model.streamRequests[1].messages[1].content == [.toolCall(toolCall)])
    guard case let .toolResult(toolResult) = model.streamRequests[1].messages[2].content.first else {
        Issue.record("Expected a tool result message.")
        return
    }
    #expect(toolResult.toolName == "lookup")
    #expect(toolResult.result["forecast"]?.stringValue == "sunny")
}
@Test func aiStreamTextStopsWhenToolLoopConditionMatches() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"query":"weather"}"#)
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .textDelta("This should not stream."),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
            ]
        ]
    )
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]]
    ) { arguments in
        ["forecast": "sunny", "query": arguments["query"] ?? .string("")]
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 3,
        stopWhen: [.isStepCount(1)]
    ) {
        streamed.append(part)
    }

    #expect(model.streamRequests.count == 1)
    #expect(streamed == [
        .toolCall(toolCall),
        .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3)),
        .toolResult(AIToolResult(toolCallID: "call-1", toolName: "lookup", result: ["forecast": "sunny", "query": "weather"]))
    ])
}
@Test func aiStreamTextPrepareStepOverridesRequestAndReceivesResponseMessages() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"query":"weather"}"#)
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .textDelta("prepared stream"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 8))
            ]
        ]
    )
    let capture = PrepareStepCapture()
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]]
    ) { _ in
        ["forecast": "sunny"]
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 3,
        prepareStep: { context in
            await capture.record(context)
            guard context.stepNumber == 1 else { return nil }
            var request = context.request
            request.messages.append(.user("prepared follow-up"))
            request.providerOptions["test"] = ["step": 2]
            return AIPrepareStepResult(request: request)
        }
    ) {
        streamed.append(part)
    }

    #expect(streamed.contains(.textDelta("prepared stream")))
    #expect(model.streamRequests.count == 2)
    #expect(model.streamRequests[1].messages.last == .user("prepared follow-up"))
    #expect(model.streamRequests[1].providerOptions["test"]?["step"]?.intValue == 2)
    #expect(await capture.stepNumbers() == [0, 1])
    #expect(await capture.stepCounts() == [0, 1])
    #expect(await capture.responseMessageCounts() == [0, 2])
}
@Test func aiStreamTextRefinesToolArgumentsBeforeExecution() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"city":" kyoto "}"#)
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .textDelta("done"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 8))
            ]
        ]
    )
    let capture = ToolCapture()
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": ["city": ["type": "string"]]],
        refineArguments: { arguments in
            guard let city = arguments["city"]?.stringValue else {
                throw AIError.invalidArgument(argument: "city", message: "city is required.")
            }
            return ["city": .string(city.trimmingCharacters(in: .whitespacesAndNewlines).capitalized)]
        }
    ) { arguments in
        await capture.record(arguments)
        return ["city": arguments["city"] ?? .string("missing")]
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 2
    ) {
        streamed.append(part)
    }

    #expect(await capture.value()?["city"]?.stringValue == "Kyoto")
    #expect(streamed.contains(.toolResult(AIToolResult(toolCallID: "call-1", toolName: "lookup", result: ["city": "Kyoto"]))))
}
@Test func aiGenerateTextValidatesToolArgumentsAgainstSchema() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"city":42}"#)
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "",
        finishReason: "tool-calls",
        toolCalls: [toolCall],
        rawValue: .object([:])
    ))
    let capture = ToolCapture()
    let lookup = AITool(
        name: "lookup",
        parameters: [
            "type": "object",
            "properties": ["city": ["type": "string"]],
            "required": ["city"],
            "additionalProperties": false
        ]
    ) { arguments in
        await capture.record(arguments)
        return ["city": arguments["city"] ?? .null]
    }

    do {
        _ = try await AI.generateText(
            model: model,
            prompt: "Weather?",
            executableTools: [lookup]
        )
        Issue.record("Expected invalid tool arguments to fail schema validation.")
    } catch let error as AIInvalidToolInputError {
        #expect(error.toolName == "lookup")
        #expect(error.toolCallID == "call-1")
        #expect(error.description.contains("Tool call arguments do not match tool schema"))
        #expect(error.validationError?.path == "$.city")
        #expect(error.validationError?.message.contains("expected string") == true)
    }

    #expect(await capture.value() == nil)
    #expect(model.requests.count == 1)
}
@Test func aiGenerateTextThrowsTypedNoSuchToolError() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "missing", arguments: #"{}"#)
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "",
        finishReason: "tool-calls",
        toolCalls: [toolCall],
        rawValue: .object([:])
    ))
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object"]
    ) { _ in
        ["ok": true]
    }

    do {
        _ = try await AI.generateText(
            model: model,
            prompt: "Use a tool.",
            executableTools: [lookup]
        )
        Issue.record("Expected missing tool error.")
    } catch let error as AINoSuchToolError {
        #expect(error.toolName == "missing")
        #expect(error.availableToolNames == ["lookup"])
    }
}
