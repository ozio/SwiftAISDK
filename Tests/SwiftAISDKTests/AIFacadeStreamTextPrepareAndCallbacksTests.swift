import Foundation
import Testing
@testable import SwiftAISDK

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

@Test func aiStreamTextPrepareStepCanDisableToolsForNextStepLikeUpstreamActiveTools() async throws {
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
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]]
    ) { _ in
        ["forecast": "sunny"]
    }

    for try await _ in AI.streamText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 3,
        prepareStep: { context in
            guard context.stepNumber == 1 else { return nil }
            return AIPrepareStepResult(executableTools: [])
        }
    ) {}

    #expect(model.streamRequests.count == 2)
    #expect(model.streamRequests[0].tools.keys.sorted() == ["lookup"])
    #expect(model.streamRequests[1].tools.isEmpty)
}
@Test func aiStreamTextPrepareStepUpdatesToolContextsForExecutionLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"query":"weather"}"#)
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
    let prepareCapture = PrepareStepToolContextCapture()
    let toolCapture = ToolExecutionContextCapture()
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]],
        contextSchema: [
            "type": "object",
            "properties": ["label": ["type": "string"]],
            "required": ["label"]
        ],
        executeWithContext: { arguments, context in
            await toolCapture.record(arguments: arguments, context: context)
            return ["label": context.toolContext?["label"] ?? .null]
        }
    ) { _ in
        .null
    }
    let request = LanguageModelRequest(
        messages: [.user("Weather?")],
        toolContexts: ["lookup": ["label": "initial"]]
    )

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        request: request,
        executableTools: [lookup],
        maxSteps: 3,
        prepareStep: { context in
            await prepareCapture.record(context.request.toolContexts)
            guard context.stepNumber == 0 else { return nil }
            var request = context.request
            request.toolContexts["lookup"] = ["label": "updated"]
            return AIPrepareStepResult(request: request)
        }
    ) {
        streamed.append(part)
    }

    let toolSnapshot = await toolCapture.snapshot()
    #expect(await prepareCapture.values() == [
        ["lookup": ["label": "initial"]],
        ["lookup": ["label": "updated"]]
    ])
    #expect(toolSnapshot.arguments?["query"]?.stringValue == "weather")
    #expect(toolSnapshot.context?.toolContext == ["label": "updated"])
    #expect(model.streamRequests.map(\.toolContexts) == [
        ["lookup": ["label": "updated"]],
        ["lookup": ["label": "updated"]]
    ])
    #expect(streamed.contains(.toolResult(AIToolResult(
        toolCallID: "call-1",
        toolName: "lookup",
        result: ["label": "updated"]
    ))))
}

@Test func aiStreamTextPassesAbortSignalToToolExecutionContextLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
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
    let capture = ToolExecutionContextCapture()
    let abortController = AIAbortController()
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ],
        executeWithContext: { arguments, context in
            await capture.record(arguments: arguments, context: context)
            return .string("tool result")
        },
        execute: { _ in
            Issue.record("Expected contextual tool execution.")
            return .null
        }
    )

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 2,
        abortSignal: abortController.signal
    ) {
        streamed.append(part)
    }

    let snapshot = await capture.snapshot()
    #expect(streamed.contains(.toolResult(AIToolResult(toolCallID: "call-1", toolName: "tool1", result: .string("tool result")))))
    #expect(snapshot.arguments == ["value": "value"])
    #expect(snapshot.context?.toolCallID == "call-1")
    #expect(snapshot.context?.messages == [.user("test-input")])
    #expect(snapshot.context?.abortSignal === abortController.signal)
}

@Test func aiStreamTextInvokesToolInputCallbacksInOrderLikeUpstream() async throws {
    let toolCallID = "call_O17Uplv4lJvD6DVdIvFFeRMw"
    let inputDeltas = [
        #"{"#,
        "value",
        #"":""#,
        "Spark",
        "le",
        " Day",
        #""}"#
    ]
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .responseMetadata(AIResponseMetadata(id: "id-0", timestamp: Date(timeIntervalSince1970: 0), modelID: "mock-model-id")),
            .toolInputStart(id: toolCallID, name: "test-tool"),
            .toolInputDelta(id: toolCallID, delta: inputDeltas[0]),
            .toolInputDelta(id: toolCallID, delta: inputDeltas[1]),
            .toolInputDelta(id: toolCallID, delta: inputDeltas[2]),
            .toolInputDelta(id: toolCallID, delta: inputDeltas[3]),
            .toolInputDelta(id: toolCallID, delta: inputDeltas[4]),
            .toolInputDelta(id: toolCallID, delta: inputDeltas[5]),
            .toolInputDelta(id: toolCallID, delta: inputDeltas[6]),
            .toolInputEnd(id: toolCallID),
            .toolCall(AIToolCall(id: toolCallID, name: "test-tool", arguments: #"{"value":"Sparkle Day"}"#)),
            .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
        ]
    )
    let recorder = StreamToolInputCallbackRecorder()
    let tool = AITool(
        name: "test-tool",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"],
            "additionalProperties": false
        ],
        onInputStart: { context in
            await recorder.record(.start(
                toolCallID: context.toolCallID,
                messages: context.messages,
                abortSignalIsNil: context.abortSignal == nil
            ))
        },
        onInputDelta: { context in
            await recorder.record(.delta(
                toolCallID: context.toolCallID,
                inputTextDelta: context.inputTextDelta,
                messages: context.messages,
                abortSignalIsNil: context.abortSignal == nil
            ))
        },
        onInputAvailable: { context in
            await recorder.record(.available(
                toolCallID: context.toolCallID,
                input: context.input,
                messages: context.messages,
                abortSignalIsNil: context.abortSignal == nil
            ))
        },
        execute: { _ in
            .string("unused")
        }
    )

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 1
    ) {
        streamed.append(part)
    }

    #expect(streamed.contains(.toolCall(AIToolCall(id: toolCallID, name: "test-tool", arguments: #"{"value":"Sparkle Day"}"#))))
    #expect(await recorder.events() == [
        .start(
            toolCallID: toolCallID,
            messages: [.user("test-input")],
            abortSignalIsNil: true
        ),
        .delta(
            toolCallID: toolCallID,
            inputTextDelta: inputDeltas[0],
            messages: [.user("test-input")],
            abortSignalIsNil: true
        ),
        .delta(
            toolCallID: toolCallID,
            inputTextDelta: inputDeltas[1],
            messages: [.user("test-input")],
            abortSignalIsNil: true
        ),
        .delta(
            toolCallID: toolCallID,
            inputTextDelta: inputDeltas[2],
            messages: [.user("test-input")],
            abortSignalIsNil: true
        ),
        .delta(
            toolCallID: toolCallID,
            inputTextDelta: inputDeltas[3],
            messages: [.user("test-input")],
            abortSignalIsNil: true
        ),
        .delta(
            toolCallID: toolCallID,
            inputTextDelta: inputDeltas[4],
            messages: [.user("test-input")],
            abortSignalIsNil: true
        ),
        .delta(
            toolCallID: toolCallID,
            inputTextDelta: inputDeltas[5],
            messages: [.user("test-input")],
            abortSignalIsNil: true
        ),
        .delta(
            toolCallID: toolCallID,
            inputTextDelta: inputDeltas[6],
            messages: [.user("test-input")],
            abortSignalIsNil: true
        ),
        .available(
            toolCallID: toolCallID,
            input: ["value": "Sparkle Day"],
            messages: [.user("test-input")],
            abortSignalIsNil: true
        )
    ])
}

@Test func aiStreamTextSendsCustomSchemaToolCallsLikeUpstream() async throws {
    let schema: JSONValue = [
        "type": "object",
        "properties": ["value": ["type": "string"]],
        "required": ["value"],
        "additionalProperties": false
    ]
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{ "value": "value" }"#)
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .responseMetadata(AIResponseMetadata(id: "id-0", timestamp: Date(timeIntervalSince1970: 0), modelID: "mock-model-id")),
            .toolCall(toolCall),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 13))
        ]
    )

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "test-input",
        tools: ["tool1": schema],
        toolChoice: "required"
    ) {
        streamed.append(part)
    }

    let request = try #require(model.streamRequests.first)
    let preparedTool = try #require(prepareTools(tools: request.tools)?.first)
    #expect(request.messages == [.user("test-input")])
    #expect(request.toolChoice == "required")
    #expect(preparedTool == [
        "type": "function",
        "name": "tool1",
        "inputSchema": schema
    ])
    #expect(streamed == [
        .responseMetadata(AIResponseMetadata(id: "id-0", timestamp: Date(timeIntervalSince1970: 0), modelID: "mock-model-id")),
        .toolCall(toolCall),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 13))
    ])
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

@Test func aiStreamTextToolTelemetryFiresForEachToolCallLikeUpstreamCallbacks() async throws {
    let recorder = TelemetryRecorder()
    let call1 = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"a"}"#)
    let call2 = AIToolCall(id: "call-2", name: "tool1", arguments: #"{"value":"b"}"#)
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .toolCall(call1),
                .toolCall(call2),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .textDelta("Done."),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
            ]
        ]
    )
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { input in
        .string("\(input["value"]?.stringValue ?? "")-result")
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "prompt",
        executableTools: [tool],
        maxSteps: 2,
        telemetry: Telemetry.Options(integrations: [recorder])
    ) {
        streamed.append(part)
    }

    let toolEvents = await recorder.events().filter { $0.operationID == "ai.streamText.tool" }
    #expect(streamed.contains(.toolResult(AIToolResult(toolCallID: "call-1", toolName: "tool1", result: .string("a-result")))))
    #expect(streamed.contains(.toolResult(AIToolResult(toolCallID: "call-2", toolName: "tool1", result: .string("b-result")))))
    #expect(toolEvents.map(\.kind) == [.toolStart, .toolEnd, .toolStart, .toolEnd])
    #expect(toolEvents[0].input?["toolCall"]?["id"]?.stringValue == "call-1")
    #expect(toolEvents[0].input?["toolCall"]?["arguments"]?.stringValue == #"{"value":"a"}"#)
    #expect(toolEvents[1].output?["status"]?.stringValue == "executed")
    #expect(toolEvents[1].output?["arguments"]?["value"]?.stringValue == "a")
    #expect(toolEvents[1].output?["result"]?["result"]?.stringValue == "a-result")
    #expect(toolEvents[2].input?["toolCall"]?["id"]?.stringValue == "call-2")
    #expect(toolEvents[3].output?["arguments"]?["value"]?.stringValue == "b")
    #expect(toolEvents[3].output?["result"]?["result"]?.stringValue == "b-result")
}

@Test func aiStreamTextReturnsToolExecutionErrorsAsToolResultsLikeUpstream() async throws {
    struct ToolFailure: Error, CustomStringConvertible {
        var description: String { "tool execution failed" }
    }

    let recorder = TelemetryRecorder()
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"test"}"#)
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ]
        ]
    )
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { _ in
        throw ToolFailure()
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "prompt",
        executableTools: [tool],
        maxSteps: 1,
        telemetry: Telemetry.Options(integrations: [recorder])
    ) {
        streamed.append(part)
    }

    let errorResult = AIToolResult(
        toolCallID: "call-1",
        toolName: "tool1",
        result: [
            "type": "error-text",
            "value": "Error: tool execution failed"
        ],
        isError: true
    )
    let toolEvents = await recorder.events().filter { $0.operationID == "ai.streamText.tool" }
    #expect(streamed == [
        .toolCall(toolCall),
        .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3)),
        .toolResult(errorResult)
    ])
    #expect(toolEvents.map(\.kind) == [.toolStart, .toolError])
    #expect(toolEvents[0].input?["toolCall"]?["id"]?.stringValue == "call-1")
    #expect(toolEvents[1].input?["toolCall"]?["id"]?.stringValue == "call-1")
    #expect(toolEvents[1].errorDescription == "tool execution failed")
}
