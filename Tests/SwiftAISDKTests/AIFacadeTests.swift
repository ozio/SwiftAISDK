import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiGenerateTextPromptBuildsLanguageRequest() async throws {
    let model = MockLanguageModel(result: TextGenerationResult(text: "done", rawValue: .object([:])))

    let result = try await AI.generateText(
        model: model,
        prompt: "Hello",
        temperature: 0.2,
        topK: 20,
        seed: 7,
        responseFormat: .json(name: "Answer"),
        reasoning: "low",
        providerOptions: ["openai": .object(["parallelToolCalls": .bool(false)])],
        extraBody: ["user": .string("user-1")]
    )

    #expect(result.text == "done")
    #expect(model.requests.count == 1)
    let request = try #require(model.requests.first)
    #expect(request.messages == [.user("Hello")])
    #expect(request.temperature == 0.2)
    #expect(request.topK == 20)
    #expect(request.seed == 7)
    #expect(request.responseFormat == .json(name: "Answer"))
    #expect(request.reasoning == "low")
    #expect(request.providerOptions["openai"]?["parallelToolCalls"]?.boolValue == false)
    #expect(request.extraBody["user"]?.stringValue == "user-1")
}

@Test func aiGenerateTextRetriesRetryableErrors() async throws {
    let model = FlakyLanguageModel(failures: [
        AIError.httpStatus(provider: "mock", statusCode: 500, body: "temporary")
    ], result: TextGenerationResult(text: "recovered", rawValue: .object([:])))

    let result = try await AI.generateText(
        model: model,
        prompt: "Retry",
        retryPolicy: AIRetryPolicy(maxRetries: 2, initialDelayNanoseconds: 0)
    )

    #expect(result.text == "recovered")
    #expect(model.requests.count == 2)
}

@Test func aiGenerateTextHonorsRetryAfterHeader() async throws {
    let model = FlakyLanguageModel(failures: [
        AIError.httpStatusWithHeaders(
            provider: "mock",
            statusCode: 429,
            body: "rate limited",
            headers: ["Retry-After": "0"]
        )
    ], result: TextGenerationResult(text: "recovered", rawValue: .object([:])))

    let started = DispatchTime.now().uptimeNanoseconds
    let result = try await AI.generateText(
        model: model,
        prompt: "Retry after",
        retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 2_000_000_000)
    )
    let elapsed = DispatchTime.now().uptimeNanoseconds - started

    #expect(result.text == "recovered")
    #expect(model.requests.count == 2)
    #expect(elapsed < 1_000_000_000)
}

@Test func aiGenerateTextEmitsTelemetryLifecycleAndRetryEvents() async throws {
    let recorder = TelemetryRecorder()
    let model = FlakyLanguageModel(failures: [
        AIError.httpStatus(provider: "mock", statusCode: 503, body: "try again")
    ], result: TextGenerationResult(
        text: "recovered",
        finishReason: "stop",
        usage: TokenUsage(inputTokens: 1, outputTokens: 2, totalTokens: 3),
        rawValue: .object(["ok": .bool(true)])
    ))

    let result = try await AI.generateText(
        model: model,
        prompt: "Telemetry",
        retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 0),
        telemetry: AITelemetryOptions(
            functionID: "unit.generateText",
            metadata: ["tenant": .string("test")],
            integrations: [recorder]
        )
    )

    let events = await recorder.events()
    #expect(result.text == "recovered")
    #expect(events.map(\.kind) == [.start, .retry, .end])
    #expect(Set(events.map(\.callID)).count == 1)
    #expect(events.allSatisfy { $0.operationID == "ai.generateText" })
    #expect(events.allSatisfy { $0.providerID == "mock" })
    #expect(events.allSatisfy { $0.modelID == "flaky-language" })
    #expect(events.allSatisfy { $0.functionID == "unit.generateText" })
    #expect(events.allSatisfy { $0.metadata["tenant"] == .string("test") })
    #expect(events[0].input?["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Telemetry")
    #expect(events[1].attempt == 1)
    #expect(events[1].maxRetries == 1)
    #expect(events[1].delayNanoseconds == 0)
    #expect(events[1].errorDescription?.contains("HTTP 503") == true)
    #expect(events[2].output?["text"]?.stringValue == "recovered")
    #expect(events[2].usage == TokenUsage(inputTokens: 1, outputTokens: 2, totalTokens: 3))
}

@Test func aiGenerateTextTelemetryRecordsErrorsAndRespectsOutputFlag() async throws {
    let recorder = TelemetryRecorder()
    let model = FlakyLanguageModel(failures: [
        AIError.httpStatus(provider: "mock", statusCode: 400, body: "bad request")
    ], result: TextGenerationResult(text: "unused", rawValue: .object([:])))

    do {
        _ = try await AI.generateText(
            model: model,
            prompt: "Telemetry error",
            retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 0),
            telemetry: AITelemetryOptions(recordOutputs: false, integrations: [recorder])
        )
        Issue.record("Expected telemetry error path.")
    } catch {
        let events = await recorder.events()
        #expect(events.map(\.kind) == [.start, .error])
        #expect(events[0].input?["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Telemetry error")
        #expect(events[1].output == nil)
        #expect(events[1].errorDescription?.contains("HTTP 400") == true)
    }
}

@Test func httpStatusErrorPreservesResponseHeaders() throws {
    let response = AIHTTPResponse(
        statusCode: 429,
        headers: ["Retry-After": "0"],
        body: Data("rate limited".utf8)
    )

    #expect(httpStatusError(provider: "mock", response: response) == .httpStatusWithHeaders(
        provider: "mock",
        statusCode: 429,
        body: "rate limited",
        headers: ["Retry-After": "0"]
    ))
}

@Test func aiGenerateTextDoesNotRetryNonRetryableErrors() async throws {
    let model = FlakyLanguageModel(failures: [
        AIError.httpStatus(provider: "mock", statusCode: 400, body: "bad request")
    ], result: TextGenerationResult(text: "unused", rawValue: .object([:])))

    do {
        _ = try await AI.generateText(
            model: model,
            prompt: "No retry",
            retryPolicy: AIRetryPolicy(maxRetries: 2, initialDelayNanoseconds: 0)
        )
        Issue.record("Expected non-retryable HTTP error.")
    } catch let error as AIError {
        #expect(error == AIError.httpStatus(provider: "mock", statusCode: 400, body: "bad request"))
    }

    #expect(model.requests.count == 1)
}

@Test func aiGenerateTextWrapsWhenMaxRetriesExceeded() async throws {
    let model = FlakyLanguageModel(failures: [
        AIError.httpStatus(provider: "mock", statusCode: 503, body: "one"),
        AIError.httpStatus(provider: "mock", statusCode: 503, body: "two")
    ], result: TextGenerationResult(text: "unused", rawValue: .object([:])))

    do {
        _ = try await AI.generateText(
            model: model,
            prompt: "Retry once",
            retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 0)
        )
        Issue.record("Expected retry exhaustion.")
    } catch let error as AIRetryError {
        #expect(error.reason == .maxRetriesExceeded)
        #expect(error.attempts == 2)
    }

    #expect(model.requests.count == 2)
}

@Test func aiGenerateTextTimesOutThroughRetryPolicy() async throws {
    let model = SlowLanguageModel(delayNanoseconds: 80_000_000)

    do {
        _ = try await AI.generateText(
            model: model,
            prompt: "Too slow",
            retryPolicy: AIRetryPolicy(
                maxRetries: 2,
                initialDelayNanoseconds: 0,
                timeoutNanoseconds: 1_000_000
            )
        )
        Issue.record("Expected timeout.")
    } catch let error as AIError {
        #expect(error == .timeout(durationNanoseconds: 1_000_000))
    }

    #expect(model.requests.count == 1)
}

@Test func aiFacadeTimeoutAppliesToNonLanguageCalls() async throws {
    let model = SlowEmbeddingModel(delayNanoseconds: 80_000_000)

    do {
        _ = try await AI.embed(
            model: model,
            value: "slow",
            retryPolicy: AIRetryPolicy(timeoutNanoseconds: 1_000_000)
        )
        Issue.record("Expected timeout.")
    } catch let error as AIError {
        #expect(error == .timeout(durationNanoseconds: 1_000_000))
    }

    #expect(model.requests.count == 1)
}

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
        telemetry: AITelemetryOptions(integrations: [recorder])
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

@Test func aiStreamTextTimesOut() async throws {
    let recorder = TelemetryRecorder()
    let model = SlowStreamingLanguageModel(delayNanoseconds: 80_000_000)

    do {
        for try await _ in AI.streamText(
            model: model,
            prompt: "Too slow",
            timeoutNanoseconds: 1_000_000,
            telemetry: AITelemetryOptions(integrations: [recorder])
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
    } catch let error as AIError {
        #expect(error.description.contains("Tool call arguments do not match tool schema"))
        #expect(error.description.contains("$.city"))
        #expect(error.description.contains("expected string"))
    }

    #expect(await capture.value() == nil)
    #expect(model.requests.count == 1)
}

@Test func aiGenerateTextValidatesToolArgumentsAfterRefinement() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"city":42}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object(["step": 1])),
        TextGenerationResult(text: "done", finishReason: "stop", rawValue: .object(["step": 2]))
    ])
    let capture = ToolCapture()
    let lookup = AITool(
        name: "lookup",
        parameters: [
            "type": "object",
            "properties": ["city": ["type": "string"]],
            "required": ["city"]
        ],
        refineArguments: { _ in ["city": "Tokyo"] }
    ) { arguments in
        await capture.record(arguments)
        return ["city": arguments["city"] ?? .null]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 2
    )

    #expect(result.text == "done")
    #expect(await capture.value()?["city"]?.stringValue == "Tokyo")
    #expect(result.toolResults.first?.result["city"]?.stringValue == "Tokyo")
}

@Test func aiStreamTextMarksDynamicToolPartsAndResults() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "runtimeSearch", arguments: #"{"query":"docs"}"#)
    let dynamicToolCall = AIToolCall(id: "call-1", name: "runtimeSearch", arguments: #"{"query":"docs"}"#, dynamic: true)
    let dynamicResult = AIToolResult(
        toolCallID: "call-1",
        toolName: "runtimeSearch",
        result: ["items": ["one"]],
        dynamic: true
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .toolInputStart(id: "call-1", name: "runtimeSearch"),
                .toolInputDelta(id: "call-1", delta: #"{"query":"docs"}"#),
                .toolInputEnd(id: "call-1"),
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 4))
            ],
            [
                .textDelta("done"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 8))
            ]
        ]
    )
    let runtimeSearch = AITool.dynamic(
        name: "runtimeSearch",
        description: "Runtime-discovered search tool.",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]]
    ) { _ in
        ["items": ["one"]]
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "Search runtime docs.",
        executableTools: [runtimeSearch],
        maxSteps: 2
    ) {
        streamed.append(part)
    }

    #expect(streamed.contains(.toolInputStart(id: "call-1", name: "runtimeSearch", dynamic: true)))
    #expect(streamed.contains(.toolCall(dynamicToolCall)))
    #expect(streamed.contains(.toolResult(dynamicResult)))
    #expect(model.streamRequests[0].tools["runtimeSearch"]?["description"]?.stringValue == "Runtime-discovered search tool.")
    #expect(model.streamRequests[0].tools["runtimeSearch"]?["dynamic"] == nil)
    #expect(model.streamRequests[1].messages[1].content == [.toolCall(dynamicToolCall)])
    #expect(model.streamRequests[1].messages[2].content == [.toolResult(dynamicResult)])
}

@Test func aiStreamTextStopsForUserApprovalRequest() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "deleteFile", arguments: #"{"path":"/tmp/a.txt"}"#)
    let approvalRequest = AIToolApprovalRequest(
        id: "approval-call-1",
        toolName: "deleteFile",
        arguments: #"{"path":"/tmp/a.txt"}"#,
        toolCallID: "call-1"
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .textDelta("This should not stream."),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 8))
            ]
        ]
    )
    let deleteFile = AITool(
        name: "deleteFile",
        parameters: ["type": "object", "properties": ["path": ["type": "string"]]]
    ) { _ in
        Issue.record("Tool should not execute before user approval.")
        return ["deleted": true]
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "Delete the file.",
        executableTools: [deleteFile],
        maxSteps: 2,
        toolApproval: { context in
            #expect(context.toolCall == toolCall)
            #expect(context.arguments["path"]?.stringValue == "/tmp/a.txt")
            return .userApproval
        }
    ) {
        streamed.append(part)
    }

    #expect(model.streamRequests.count == 1)
    #expect(streamed == [
        .toolCall(toolCall),
        .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3)),
        .toolApprovalRequest(approvalRequest)
    ])
}

@Test func aiGenerateTextExecutesTypedToolsAndContinuesUntilFinalText() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"query":"weather"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object(["step": 1])),
        TextGenerationResult(text: "It is sunny.", finishReason: "stop", rawValue: .object(["step": 2]))
    ])
    let capture = ToolCapture()
    let lookup = AITool(
        name: "lookup",
        description: "Look up a value.",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]]
    ) { arguments in
        await capture.record(arguments)
        return ["forecast": "sunny"]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 3
    )

    #expect(result.text == "It is sunny.")
    let executedArguments = await capture.value()
    #expect(executedArguments?["query"]?.stringValue == "weather")
    #expect(result.toolResults.count == 1)
    #expect(result.toolResults[0].toolCallID == "call-1")
    #expect(result.toolResults[0].result["forecast"]?.stringValue == "sunny")
    #expect(result.steps.count == 2)
    #expect(result.steps[0].toolCalls == [toolCall])
    #expect(result.steps[0].toolResults.count == 1)
    #expect(result.steps[1].text == "It is sunny.")

    #expect(model.requests.count == 2)
    #expect(model.requests[0].tools["lookup"]?["description"]?.stringValue == "Look up a value.")
    #expect(model.requests[1].messages.count == 3)
    #expect(model.requests[1].messages[1].content == [.toolCall(toolCall)])
    guard case let .toolResult(toolResult) = model.requests[1].messages[2].content.first else {
        Issue.record("Expected a tool result message.")
        return
    }
    #expect(toolResult.toolName == "lookup")
    #expect(toolResult.result["forecast"]?.stringValue == "sunny")
}

@Test func aiGenerateTextStopsWhenToolLoopConditionMatches() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "finalAnswer", arguments: #"{"value":"done"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object(["step": 1])),
        TextGenerationResult(text: "This should not be requested.", finishReason: "stop", rawValue: .object(["step": 2]))
    ])
    let finalAnswer = AITool(
        name: "finalAnswer",
        parameters: ["type": "object", "properties": ["value": ["type": "string"]]]
    ) { arguments in
        ["value": arguments["value"] ?? .string("missing")]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Stop after final answer tool.",
        executableTools: [finalAnswer],
        maxSteps: 3,
        stopWhen: [.hasToolCall("finalAnswer")]
    )

    #expect(model.requests.count == 1)
    #expect(result.text == "")
    #expect(result.toolResults == [
        AIToolResult(toolCallID: "call-1", toolName: "finalAnswer", result: ["value": "done"])
    ])
    #expect(result.steps.count == 1)
    #expect(result.steps[0].toolCalls == [toolCall])
    #expect(result.steps[0].toolResults.count == 1)
}

@Test func aiGenerateTextPrepareStepOverridesRequestAndReceivesResponseMessages() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"query":"weather"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object(["step": 1])),
        TextGenerationResult(text: "prepared answer", finishReason: "stop", rawValue: .object(["step": 2]))
    ])
    let capture = PrepareStepCapture()
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]]
    ) { _ in
        ["forecast": "sunny"]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 3,
        prepareStep: { context in
            await capture.record(context)
            guard context.stepNumber == 1 else { return nil }
            var request = context.request
            request.messages.append(.user("prepared follow-up"))
            request.toolChoice = ["type": "tool", "toolName": "lookup"]
            request.providerOptions["test"] = ["step": 2]
            return AIPrepareStepResult(request: request)
        }
    )

    #expect(result.text == "prepared answer")
    #expect(model.requests.count == 2)
    #expect(model.requests[1].messages.last == .user("prepared follow-up"))
    #expect(model.requests[1].toolChoice?["toolName"]?.stringValue == "lookup")
    #expect(model.requests[1].providerOptions["test"]?["step"]?.intValue == 2)
    #expect(await capture.stepNumbers() == [0, 1])
    #expect(await capture.stepCounts() == [0, 1])
    #expect(await capture.responseMessageCounts() == [0, 2])
}

@Test func aiGenerateTextRefinesToolArgumentsBeforeExecution() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"city":" tokyo "}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object(["step": 1])),
        TextGenerationResult(text: "done", finishReason: "stop", rawValue: .object(["step": 2]))
    ])
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

    let result = try await AI.generateText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 2
    )

    #expect(result.text == "done")
    #expect(await capture.value()?["city"]?.stringValue == "Tokyo")
    #expect(result.toolResults.first?.result["city"]?.stringValue == "Tokyo")
}

@Test func aiGenerateTextMarksDynamicToolCallsResultsAndMessages() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "runtimeSearch", arguments: #"{"query":"docs"}"#)
    let dynamicToolCall = AIToolCall(id: "call-1", name: "runtimeSearch", arguments: #"{"query":"docs"}"#, dynamic: true)
    let dynamicResult = AIToolResult(
        toolCallID: "call-1",
        toolName: "runtimeSearch",
        result: ["items": ["one"]],
        dynamic: true
    )
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object(["step": 1])),
        TextGenerationResult(text: "done", finishReason: "stop", rawValue: .object(["step": 2]))
    ])
    let runtimeSearch = AITool.dynamic(
        name: "runtimeSearch",
        description: "Runtime-discovered search tool.",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]]
    ) { _ in
        ["items": ["one"]]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Search runtime docs.",
        executableTools: [runtimeSearch],
        maxSteps: 2
    )

    #expect(result.text == "done")
    #expect(result.toolResults == [dynamicResult])
    #expect(result.steps[0].toolCalls == [dynamicToolCall])
    #expect(result.steps[0].toolResults == [dynamicResult])
    #expect(model.requests[0].tools["runtimeSearch"]?["description"]?.stringValue == "Runtime-discovered search tool.")
    #expect(model.requests[0].tools["runtimeSearch"]?["dynamic"] == nil)
    #expect(model.requests[1].messages[1].content == [.toolCall(dynamicToolCall)])
    #expect(model.requests[1].messages[2].content == [.toolResult(dynamicResult)])
}

@Test func aiGenerateTextAddsDeniedApprovalResultAndContinues() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "deleteFile", arguments: #"{"path":"/tmp/a.txt"}"#)
    let approvalRequest = AIToolApprovalRequest(
        id: "approval-call-1",
        toolName: "deleteFile",
        arguments: #"{"path":"/tmp/a.txt"}"#,
        toolCallID: "call-1",
        isAutomatic: true
    )
    let approvalResponse = AIToolApprovalResponse(
        id: "approval-call-1",
        approved: false,
        reason: "User denied access"
    )
    let deniedResult = AIToolResult(
        toolCallID: "call-1",
        toolName: "deleteFile",
        result: ["type": "execution-denied", "reason": "User denied access"]
    )
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object(["step": 1])),
        TextGenerationResult(text: "Skipped deletion.", finishReason: "stop", rawValue: .object(["step": 2]))
    ])
    let deleteFile = AITool(
        name: "deleteFile",
        parameters: ["type": "object", "properties": ["path": ["type": "string"]]]
    ) { _ in
        Issue.record("Denied tool should not execute.")
        return ["deleted": true]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Delete the file.",
        executableTools: [deleteFile],
        maxSteps: 2,
        toolApproval: { context in
            #expect(context.toolCall == toolCall)
            #expect(context.arguments["path"]?.stringValue == "/tmp/a.txt")
            return .denied(reason: "User denied access")
        }
    )

    #expect(result.text == "Skipped deletion.")
    #expect(result.toolApprovalRequests == [approvalRequest])
    #expect(result.toolApprovalResponses == [approvalResponse])
    #expect(result.toolResults == [deniedResult])
    #expect(result.steps[0].toolApprovalRequests == [approvalRequest])
    #expect(result.steps[0].toolApprovalResponses == [approvalResponse])
    #expect(result.steps[0].toolResults == [deniedResult])
    #expect(model.requests.count == 2)
    #expect(model.requests[1].messages[1].content == [
        .toolCall(toolCall),
        .toolApprovalRequest(approvalRequest)
    ])
    #expect(model.requests[1].messages[2].content == [
        .toolApprovalResponse(approvalResponse),
        .toolResult(deniedResult)
    ])
}

@Test func aiStopConditionsMatchUpstreamStepHelpers() async throws {
    let searchStep = AIToolStep(
        index: 0,
        text: "",
        toolCalls: [AIToolCall(id: "call-1", name: "search", arguments: "{}")]
    )
    let finalStep = AIToolStep(
        index: 1,
        text: "",
        toolCalls: [AIToolCall(id: "call-2", name: "finalAnswer", arguments: "{}")]
    )
    let context = AIStopConditionContext(steps: [searchStep, finalStep])

    #expect(try await AIStopCondition.isStepCount(2).evaluate(context))
    #expect(try await !AIStopCondition.isStepCount(1).evaluate(context))
    #expect(try await !AIStopCondition.isLoopFinished().evaluate(context))
    #expect(try await AIStopCondition.hasToolCall("finalAnswer").evaluate(context))
    #expect(try await AIStopCondition.hasToolCall("search", "finalAnswer").evaluate(context))
    #expect(try await !AIStopCondition.hasToolCall("search").evaluate(context))
}

private actor ToolCapture {
    private var arguments: JSONValue?

    func record(_ arguments: JSONValue) {
        self.arguments = arguments
    }

    func value() -> JSONValue? {
        arguments
    }
}

private actor PrepareStepCapture {
    private var numbers: [Int] = []
    private var steps: [Int] = []
    private var responseMessages: [Int] = []

    func record(_ context: AIPrepareStepContext) {
        numbers.append(context.stepNumber)
        steps.append(context.steps.count)
        responseMessages.append(context.responseMessages.count)
    }

    func stepNumbers() -> [Int] {
        numbers
    }

    func stepCounts() -> [Int] {
        steps
    }

    func responseMessageCounts() -> [Int] {
        responseMessages
    }
}

@Test func aiEmbedManyChunksAndAggregatesResults() async throws {
    let recorder = TelemetryRecorder()
    let model = MockEmbeddingModel(results: [
        EmbeddingResult(
            embeddings: [[0.1], [0.2]],
            usage: TokenUsage(inputTokens: 2, totalTokens: 2),
            rawValue: .object(["chunk": .number(1)]),
            warnings: [AIWarning(type: "unsupported", feature: "seed")],
            providerMetadata: ["provider": .object(["first": .bool(true)])],
            responseMetadata: AIResponseMetadata(id: "resp-1")
        ),
        EmbeddingResult(
            embeddings: [[0.3]],
            usage: TokenUsage(inputTokens: 1, totalTokens: 1),
            rawValue: .object(["chunk": .number(2)]),
            providerMetadata: ["provider": .object(["second": .bool(true)])]
        )
    ])

    let result = try await AI.embedMany(
        model: model,
        values: ["a", "b", "c"],
        dimensions: 64,
        chunkSize: 2,
        providerOptions: ["test": .object(["flag": .bool(true)])],
        telemetry: AITelemetryOptions(integrations: [recorder])
    )
    let events = await recorder.events()

    #expect(model.requests.map(\.values) == [["a", "b"], ["c"]])
    #expect(model.requests.allSatisfy { $0.dimensions == 64 })
    #expect(model.requests.allSatisfy { $0.providerOptions["test"]?["flag"]?.boolValue == true })
    #expect(events.map(\.kind) == [.start, .end])
    #expect(events.allSatisfy { $0.operationID == "ai.embedMany" })
    #expect(events[0].input?["values"]?[2]?.stringValue == "c")
    #expect(events[1].output?["embeddings"]?[2]?[0]?.doubleValue == 0.3)
    #expect(events[1].usage == TokenUsage(inputTokens: 3, totalTokens: 3))
    #expect(result.embeddings == [[0.1], [0.2], [0.3]])
    #expect(result.usage == TokenUsage(inputTokens: 3, totalTokens: 3))
    #expect(result.rawValue[0]?["chunk"]?.intValue == 1)
    #expect(result.rawValue[1]?["chunk"]?.intValue == 2)
    #expect(result.warnings == [AIWarning(type: "unsupported", feature: "seed")])
    #expect(result.providerMetadata["provider"]?["second"]?.boolValue == true)
    #expect(result.responseMetadata.id == "resp-1")
}

@Test func aiFacadeForwardsMediaRerankAndUploadRequests() async throws {
    let imageModel = MockImageModel(result: ImageGenerationResult(urls: ["https://example.com/image.png"], rawValue: .object([:])))
    let image = try await AI.generateImage(model: imageModel, prompt: "cat", size: "1024x1024", providerOptions: ["image": .object(["quality": .string("high")])])
    #expect(image.urls == ["https://example.com/image.png"])
    #expect(imageModel.requests.first?.prompt == "cat")
    #expect(imageModel.requests.first?.providerOptions["image"]?["quality"]?.stringValue == "high")

    let transcriptionModel = MockTranscriptionModel(result: TranscriptionResult(text: "hello", rawValue: .object([:])))
    let transcription = try await AI.transcribe(model: transcriptionModel, request: AudioTranscriptionRequest(audio: Data("wav".utf8), language: "en"))
    #expect(transcription.text == "hello")
    #expect(transcriptionModel.requests.first?.language == "en")

    let speechModel = MockSpeechModel(result: SpeechResult(audio: Data("audio".utf8)))
    let speech = try await AI.generateSpeech(model: speechModel, request: SpeechRequest(text: "hello", voice: "alloy"))
    #expect(String(data: speech.audio, encoding: .utf8) == "audio")
    #expect(speechModel.requests.first?.voice == "alloy")

    let videoModel = MockVideoModel(result: VideoGenerationResult(urls: ["https://example.com/video.mp4"], rawValue: .object([:])))
    let video = try await AI.generateVideo(model: videoModel, request: VideoGenerationRequest(prompt: "clip"))
    #expect(video.urls == ["https://example.com/video.mp4"])
    #expect(videoModel.requests.first?.prompt == "clip")

    let rerankingModel = MockRerankingModel(result: RerankingResult(results: [RerankedDocument(index: 1, score: 0.9)], rawValue: .object([:])))
    let ranking = try await AI.rerank(model: rerankingModel, request: RerankingRequest(query: "q", documents: ["a", "b"], topK: 1))
    #expect(ranking.results.first?.index == 1)
    #expect(rerankingModel.requests.first?.topK == 1)

    let fileClient = MockFileClient(result: FileUploadResult(providerReference: ["file": "file-1"], rawValue: .object([:])))
    let file = try await AI.uploadFile(client: fileClient, request: FileUploadRequest(data: Data("file".utf8), mediaType: "text/plain", filename: "a.txt"))
    #expect(file.providerReference["file"] == "file-1")
    #expect(fileClient.requests.first?.filename == "a.txt")

    let skillClient = MockSkillsClient(result: SkillUploadResult(providerReference: ["skill": "skill-1"], rawValue: .object([:])))
    let skill = try await AI.uploadSkill(client: skillClient, request: SkillUploadRequest(files: [SkillUploadFile(path: "skill.md", data: Data("skill".utf8))]))
    #expect(skill.providerReference["skill"] == "skill-1")
    #expect(skillClient.requests.first?.files.first?.path == "skill.md")
}

private final class MockLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-language"
    var requests: [LanguageModelRequest] = []
    var streamRequests: [LanguageModelRequest] = []
    private var results: [TextGenerationResult]
    private var streamSequences: [[LanguageStreamPart]]

    init(result: TextGenerationResult, streamParts: [LanguageStreamPart] = []) {
        self.results = [result]
        self.streamSequences = [streamParts]
    }

    init(results: [TextGenerationResult], streamParts: [LanguageStreamPart] = []) {
        self.results = results
        self.streamSequences = [streamParts]
    }

    init(result: TextGenerationResult, streamSequences: [[LanguageStreamPart]]) {
        self.results = [result]
        self.streamSequences = streamSequences
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        requests.append(request)
        return results.count > 1 ? results.removeFirst() : results[0]
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamRequests.append(request)
        let parts = streamSequences.count > 1 ? streamSequences.removeFirst() : streamSequences[0]
        return AsyncThrowingStream { continuation in
            for part in parts {
                continuation.yield(part)
            }
            continuation.finish()
        }
    }
}

private final class FlakyLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "flaky-language"
    var requests: [LanguageModelRequest] = []
    private var failures: [Error]
    private let result: TextGenerationResult

    init(failures: [Error], result: TextGenerationResult) {
        self.failures = failures
        self.result = result
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        requests.append(request)
        if !failures.isEmpty {
            throw failures.removeFirst()
        }
        return result
    }
}

private actor TelemetryRecorder: AITelemetryIntegration {
    private var recordedEvents: [AITelemetryEvent] = []

    func record(_ event: AITelemetryEvent) {
        recordedEvents.append(event)
    }

    func events() -> [AITelemetryEvent] {
        recordedEvents
    }
}

private final class SlowLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "slow-language"
    var requests: [LanguageModelRequest] = []
    let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        requests.append(request)
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return TextGenerationResult(text: "late", rawValue: .object([:]))
    }
}

private final class SlowStreamingLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "slow-stream-language"
    var requests: [LanguageModelRequest] = []
    var streamRequests: [LanguageModelRequest] = []
    let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        requests.append(request)
        return TextGenerationResult(text: "", rawValue: .object([:]))
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamRequests.append(request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                    continuation.yield(.textDelta("late"))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private final class MockEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-embedding"
    var requests: [EmbeddingRequest] = []
    private var results: [EmbeddingResult]

    init(results: [EmbeddingResult]) {
        self.results = results
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        requests.append(request)
        return results.count > 1 ? results.removeFirst() : results[0]
    }
}

private final class SlowEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "slow-embedding"
    var requests: [EmbeddingRequest] = []
    let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        requests.append(request)
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return EmbeddingResult(embeddings: [[0.1]], rawValue: .object([:]))
    }
}

private final class MockImageModel: ImageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-image"
    var requests: [ImageGenerationRequest] = []
    let result: ImageGenerationResult

    init(result: ImageGenerationResult) { self.result = result }

    func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        requests.append(request)
        return result
    }
}

private final class MockTranscriptionModel: TranscriptionModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-transcription"
    var requests: [AudioTranscriptionRequest] = []
    let result: TranscriptionResult

    init(result: TranscriptionResult) { self.result = result }

    func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        requests.append(request)
        return result
    }
}

private final class MockSpeechModel: SpeechModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-speech"
    var requests: [SpeechRequest] = []
    let result: SpeechResult

    init(result: SpeechResult) { self.result = result }

    func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        requests.append(request)
        return result
    }
}

private final class MockVideoModel: VideoModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-video"
    var requests: [VideoGenerationRequest] = []
    let result: VideoGenerationResult

    init(result: VideoGenerationResult) { self.result = result }

    func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        requests.append(request)
        return result
    }
}

private final class MockRerankingModel: RerankingModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-reranking"
    var requests: [RerankingRequest] = []
    let result: RerankingResult

    init(result: RerankingResult) { self.result = result }

    func rerank(_ request: RerankingRequest) async throws -> RerankingResult {
        requests.append(request)
        return result
    }
}

private final class MockFileClient: AIFileClient, @unchecked Sendable {
    let providerID = "mock.files"
    var requests: [FileUploadRequest] = []
    let result: FileUploadResult

    init(result: FileUploadResult) { self.result = result }

    func uploadFile(_ request: FileUploadRequest) async throws -> FileUploadResult {
        requests.append(request)
        return result
    }
}

private final class MockSkillsClient: AISkillsClient, @unchecked Sendable {
    let providerID = "mock.skills"
    var requests: [SkillUploadRequest] = []
    let result: SkillUploadResult

    init(result: SkillUploadResult) { self.result = result }

    func uploadSkill(_ request: SkillUploadRequest) async throws -> SkillUploadResult {
        requests.append(request)
        return result
    }
}
