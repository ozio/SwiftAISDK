import Foundation
import Testing
@testable import SwiftAISDK

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

@Test func aiStreamTextStreamsWarningsFromAllToolLoopStepsLikeUpstream() async throws {
    let warning0 = AIWarning(type: "other", message: "step 0 warning")
    let warning1 = AIWarning(type: "other", message: "step 1 warning")
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: "{}")
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .streamStart(warnings: [warning0]),
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .streamStart(warnings: [warning1]),
                .textDelta("Done."),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
            ]
        ]
    )
    let tool = AITool(
        name: "tool1",
        parameters: ["type": "object", "properties": [:]]
    ) { _ in
        .string("result1")
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 3
    ) {
        streamed.append(part)
    }

    #expect(streamed == [
        .streamStart(warnings: [warning0]),
        .toolCall(toolCall),
        .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3)),
        .toolResult(AIToolResult(toolCallID: "call-1", toolName: "tool1", result: .string("result1"))),
        .streamStart(warnings: [warning1]),
        .textDelta("Done."),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
    ])
}

@Test func aiStreamTextStreamsSourcesAndFilesFromAllToolLoopStepsLikeUpstream() async throws {
    let source0 = AISource(id: "source-0", sourceType: "url", url: "https://example.com/0", title: "Source 0")
    let source1 = AISource(id: "source-1", sourceType: "url", url: "https://example.com/1", title: "Source 1")
    let file0 = AIStreamFile(mediaType: "text/plain", data: Data("step-0".utf8))
    let file1 = AIStreamFile(mediaType: "text/plain", data: Data("step-1".utf8))
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: "{}")
    let toolResult = AIToolResult(toolCallID: "call-1", toolName: "tool1", result: .string("result1"))
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .source(source0),
                .file(file0),
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .source(source1),
                .file(file1),
                .textDelta("Done."),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
            ]
        ]
    )
    let tool = AITool(
        name: "tool1",
        parameters: ["type": "object", "properties": [:]]
    ) { _ in
        .string("result1")
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 3
    ) {
        streamed.append(part)
    }

    #expect(streamed == [
        .source(source0),
        .file(file0),
        .toolCall(toolCall),
        .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3)),
        .toolResult(toolResult),
        .source(source1),
        .file(file1),
        .textDelta("Done."),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
    ])
    #expect(model.streamRequests.count == 2)
    #expect(model.streamRequests[1].messages == [
        .user("test-input"),
        AIMessage(role: .assistant, content: [
            .file(mimeType: file0.mediaType, data: file0.data ?? Data(), filename: file0.filename),
            .toolCall(toolCall)
        ]),
        .toolResponses(toolResults: [toolResult])
    ])
}

@Test func aiStreamTextStreamsToolCallsAndResultsFromAllToolLoopStepsLikeUpstream() async throws {
    let call1 = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value-1"}"#)
    let call2 = AIToolCall(id: "call-2", name: "dynamicTool", arguments: #"{"value":"value-2"}"#)
    let result1 = AIToolResult(toolCallID: "call-1", toolName: "tool1", result: .string("value-1-result"))
    let result2 = AIToolResult(
        toolCallID: "call-2",
        toolName: "dynamicTool",
        result: .string("value-2-result"),
        dynamic: true
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .toolCall(call1),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .toolCall(call2),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .textStart(id: "1"),
                .textDeltaPart(id: "1", delta: "done"),
                .textEnd(id: "1"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
            ]
        ]
    )
    let staticTool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { input in
        .string("\(input["value"]?.stringValue ?? "")-result")
    }
    let dynamicTool = AITool.dynamic(
        name: "dynamicTool",
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
        prompt: "test-input",
        executableTools: [staticTool, dynamicTool],
        maxSteps: 4
    ) {
        streamed.append(part)
    }

    #expect(streamed == [
        .toolCall(call1),
        .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3)),
        .toolResult(result1),
        .toolCall(AIToolCall(id: "call-2", name: "dynamicTool", arguments: #"{"value":"value-2"}"#, dynamic: true)),
        .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3)),
        .toolResult(result2),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "done"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
    ])
    #expect(model.streamRequests.count == 3)
}

@Test func aiStreamTextEvaluatesStopConditionsInOrderWithCompletedStepLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let toolResult = AIToolResult(toolCallID: "call-1", toolName: "tool1", result: .string("result1"))
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .reasoningDelta("thinking"),
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .textDelta("This should not stream."),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
            ]
        ]
    )
    let capture = StreamStopConditionCapture()
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { _ in
        .string("result1")
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 3,
        stopWhen: [
            AIStopCondition { context in
                await capture.record(number: 0, context: context)
                return false
            },
            AIStopCondition { context in
                await capture.record(number: 1, context: context)
                return true
            }
        ]
    ) {
        streamed.append(part)
    }

    #expect(streamed == [
        .reasoningDelta("thinking"),
        .toolCall(toolCall),
        .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3)),
        .toolResult(toolResult)
    ])
    #expect(model.streamRequests.count == 1)
    #expect(await capture.numbers() == [0, 1])
    #expect(await capture.stepCounts() == [1, 1])
    #expect(await capture.toolCallIDs() == [["call-1"], ["call-1"]])
    #expect(await capture.toolResultIDs() == [["call-1"], ["call-1"]])
}

@Test func aiStreamTextCompletesToolLoopWithIsLoopFinishedLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let toolResult = AIToolResult(toolCallID: "call-1", toolName: "tool1", result: .string("result1"))
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .responseMetadata(AIResponseMetadata(id: "id-0", timestamp: Date(timeIntervalSince1970: 0), modelID: "mock-model-id")),
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .responseMetadata(AIResponseMetadata(id: "id-1", timestamp: Date(timeIntervalSince1970: 1), modelID: "mock-model-id")),
                .textStart(id: "1"),
                .textDeltaPart(id: "1", delta: "Done!"),
                .textEnd(id: "1"),
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
    ) { _ in
        .string("result1")
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 3,
        stopWhen: [.isLoopFinished()]
    ) {
        streamed.append(part)
    }

    #expect(streamed == [
        .responseMetadata(AIResponseMetadata(id: "id-0", timestamp: Date(timeIntervalSince1970: 0), modelID: "mock-model-id")),
        .toolCall(toolCall),
        .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3)),
        .toolResult(toolResult),
        .responseMetadata(AIResponseMetadata(id: "id-1", timestamp: Date(timeIntervalSince1970: 1), modelID: "mock-model-id")),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Done!"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
    ])
    #expect(model.streamRequests.count == 2)
}

@Test func aiStreamTextForwardsReasoningAndToolResultsToNextStepLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let toolResult = AIToolResult(toolCallID: "call-1", toolName: "tool1", result: .string("result1"))
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .reasoningDelta("thinking"),
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .textDelta("done"),
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
    ) { _ in
        .string("result1")
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 2
    ) {
        streamed.append(part)
    }

    #expect(streamed.contains(.toolResult(toolResult)))
    #expect(model.streamRequests.count == 2)
    #expect(model.streamRequests[1].messages == [
        .user("test-input"),
        AIMessage(role: .assistant, content: [
            .reasoning("thinking"),
            .toolCall(toolCall)
        ]),
        .toolResponses(toolResults: [toolResult])
    ])
}

@Test func aiStreamTextPreservesInterleavedTextAndReasoningContentOrderLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let toolResult = AIToolResult(toolCallID: "call-1", toolName: "tool1", result: .string("result1"))
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .streamStart(warnings: []),
                .reasoningStart(id: "0"),
                .textStart(id: "1"),
                .reasoningDeltaPart(id: "0", delta: "Thinking..."),
                .textDeltaPart(id: "1", delta: "Hello"),
                .textDeltaPart(id: "1", delta: ", "),
                .textStart(id: "2"),
                .textDeltaPart(id: "2", delta: "This "),
                .textDeltaPart(id: "2", delta: "is "),
                .reasoningStart(id: "3"),
                .reasoningDeltaPart(id: "0", delta: "I'm thinking..."),
                .reasoningDeltaPart(id: "3", delta: "Separate thoughts"),
                .textDeltaPart(id: "2", delta: "a"),
                .textDeltaPart(id: "1", delta: "world!"),
                .reasoningEnd(id: "0"),
                .textDeltaPart(id: "2", delta: " test."),
                .textEnd(id: "2"),
                .reasoningEnd(id: "3"),
                .textEnd(id: "1"),
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 13))
            ],
            [
                .textDelta("done"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
            ]
        ]
    )
    let capture = StreamStepContentCapture()
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { _ in
        .string("result1")
    }

    for try await _ in AI.streamText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 2,
        prepareStep: { context in
            if context.stepNumber == 1 {
                await capture.record(context.steps.first?.content ?? [])
            }
            return nil
        }
    ) {}

    #expect(await capture.content() == [
        .reasoning("Thinking...I'm thinking..."),
        .text("Hello, world!"),
        .text("This is a test."),
        .reasoning("Separate thoughts"),
        .toolCall(toolCall),
        .toolResult(toolResult)
    ])
}

@Test func aiStreamTextReplaysProviderExecutedToolResultsWithMetadataLikeUpstream() async throws {
    let providerCall = AIToolCall(
        id: "tool-search-call-1",
        name: "toolSearch",
        arguments: #"{"arguments":{"paths":["get_weather"]},"call_id":null}"#,
        providerExecuted: true,
        providerMetadata: ["openai": ["itemId": "tsc_123"]]
    )
    let providerResult = AIToolResult(
        toolCallID: "tool-search-call-1",
        toolName: "toolSearch",
        result: [
            "tools": [
                [
                    "type": "function",
                    "name": "get_weather",
                    "description": "Get the current weather at a specific location",
                    "parameters": [
                        "type": "object",
                        "properties": ["location": ["type": "string"]],
                        "required": ["location"]
                    ]
                ]
            ]
        ],
        providerExecuted: true,
        providerMetadata: ["openai": ["itemId": "tso_123"]]
    )
    let localCall = AIToolCall(
        id: "call-2",
        name: "get_weather",
        arguments: #"{"location":"San Francisco, CA"}"#
    )
    let localResult = AIToolResult(toolCallID: "call-2", toolName: "get_weather", result: .string("sunny"))
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .toolCall(providerCall),
                .toolResult(providerResult),
                .toolCall(localCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .textDelta("Sunny."),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
            ]
        ]
    )
    let weather = AITool(
        name: "get_weather",
        parameters: [
            "type": "object",
            "properties": ["location": ["type": "string"]],
            "required": ["location"]
        ]
    ) { _ in
        .string("sunny")
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "test-input",
        executableTools: [weather],
        maxSteps: 2
    ) {
        streamed.append(part)
    }

    #expect(streamed.contains(.toolResult(providerResult)))
    #expect(streamed.contains(.toolResult(localResult)))
    #expect(model.streamRequests.count == 2)
    #expect(model.streamRequests[1].messages == [
        .user("test-input"),
        AIMessage(role: .assistant, content: [
            .toolCall(providerCall),
            .toolResult(providerResult),
            .toolCall(localCall)
        ]),
        .toolResponses(toolResults: [localResult])
    ])
}

@Test func aiStreamTextForwardsProviderExecutedToolInputResultsAndErrorsLikeUpstream() async throws {
    let resultMetadata: [String: JSONValue] = ["provider": ["itemId": "result-1"]]
    let errorMetadata: [String: JSONValue] = ["provider": ["itemId": "error-1"]]
    let firstCall = AIToolCall(
        id: "call-1",
        name: "web_search",
        arguments: #"{"value":"value"}"#,
        providerExecuted: true
    )
    let firstResult = AIToolResult(
        toolCallID: "call-1",
        toolName: "web_search",
        result: .string(#"{"value":"result1"}"#),
        providerExecuted: true,
        providerMetadata: resultMetadata
    )
    let secondCall = AIToolCall(
        id: "call-2",
        name: "web_fetch",
        arguments: #"{"url":"https://example.com"}"#,
        providerExecuted: true
    )
    let structuredError = AIToolResult(
        toolCallID: "call-2",
        toolName: "web_fetch",
        result: [
            "type": "web_fetch_tool_result_error",
            "errorCode": "url_not_accessible"
        ],
        isError: true,
        providerExecuted: true,
        providerMetadata: errorMetadata
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .toolInputStart(id: "call-1", name: "web_search", providerExecuted: true),
            .toolInputDelta(id: "call-1", delta: #"{"value":"value"}"#),
            .toolInputEnd(id: "call-1"),
            .toolCall(firstCall),
            .toolResult(firstResult),
            .toolCall(secondCall),
            .toolResult(structuredError),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 13))
        ]]
    )

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        request: LanguageModelRequest(
            messages: [.user("Use provider tools.")],
            tools: [
                "web_search": ["type": "provider", "id": "test.web_search"],
                "web_fetch": ["type": "provider", "id": "test.web_fetch"]
            ]
        ),
        executableTools: [],
        maxSteps: 4
    ) {
        streamed.append(part)
    }

    #expect(streamed == [
        .toolInputStart(id: "call-1", name: "web_search", providerExecuted: true),
        .toolInputDelta(id: "call-1", delta: #"{"value":"value"}"#),
        .toolInputEnd(id: "call-1"),
        .toolCall(firstCall),
        .toolResult(firstResult),
        .toolCall(secondCall),
        .toolResult(structuredError),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 13))
    ])
    #expect(model.streamRequests.count == 1)
}

@Test func aiStreamTextResolvesDeferredProviderToolErrorInSameStepLikeUpstream() async throws {
    let providerCall = AIToolCall(
        id: "call-1",
        name: "deferred_tool",
        arguments: #"{ "value": "test" }"#,
        providerExecuted: true
    )
    let providerError = AIToolResult(
        toolCallID: "call-1",
        toolName: "deferred_tool",
        result: .string("ERROR"),
        isError: true,
        providerExecuted: true
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .responseMetadata(AIResponseMetadata(id: "msg-1", timestamp: Date(timeIntervalSince1970: 0), modelID: "mock-model-id")),
            .toolCall(providerCall),
            .toolResult(providerError),
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "Final response"),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 3))
        ]]
    )
    let capture = PrepareStepCapture()

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        request: deferredProviderToolRequest(),
        executableTools: [],
        maxSteps: 2,
        prepareStep: { context in
            await capture.record(context)
            return nil
        }
    ) {
        streamed.append(part)
    }

    #expect(streamed == [
        .responseMetadata(AIResponseMetadata(id: "msg-1", timestamp: Date(timeIntervalSince1970: 0), modelID: "mock-model-id")),
        .toolCall(providerCall),
        .toolResult(providerError),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Final response"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 3))
    ])
    #expect(model.streamRequests.count == 1)
    #expect(await capture.stepNumbers() == [0])
}

@Test func aiStreamTextResolvesDeferredProviderToolErrorInLaterStepLikeUpstream() async throws {
    let providerCall = AIToolCall(
        id: "call-1",
        name: "deferred_tool",
        arguments: #"{ "value": "test" }"#,
        providerExecuted: true
    )
    let providerError = AIToolResult(
        toolCallID: "call-1",
        toolName: "deferred_tool",
        result: .string("ERROR"),
        isError: true,
        providerExecuted: true
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .responseMetadata(AIResponseMetadata(id: "msg-1", timestamp: Date(timeIntervalSince1970: 0), modelID: "mock-model-id")),
                .toolCall(providerCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .responseMetadata(AIResponseMetadata(id: "msg-2", timestamp: Date(timeIntervalSince1970: 1), modelID: "mock-model-id")),
                .toolResult(providerError),
                .textStart(id: "1"),
                .textDeltaPart(id: "1", delta: "Final response"),
                .textEnd(id: "1"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
            ]
        ]
    )
    let capture = PrepareStepCapture()

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        request: deferredProviderToolRequest(),
        executableTools: [],
        maxSteps: 3,
        prepareStep: { context in
            await capture.record(context)
            return nil
        }
    ) {
        streamed.append(part)
    }

    #expect(streamed == [
        .responseMetadata(AIResponseMetadata(id: "msg-1", timestamp: Date(timeIntervalSince1970: 0), modelID: "mock-model-id")),
        .toolCall(providerCall),
        .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3)),
        .responseMetadata(AIResponseMetadata(id: "msg-2", timestamp: Date(timeIntervalSince1970: 1), modelID: "mock-model-id")),
        .toolResult(providerError),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Final response"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
    ])
    #expect(model.streamRequests.count == 2)
    #expect(model.streamRequests[1].messages == [
        .user("test-input"),
        AIMessage(role: .assistant, content: [
            .toolCall(providerCall)
        ])
    ])
    #expect(await capture.stepNumbers() == [0, 1])
    #expect(await capture.stepCounts() == [0, 1])
    #expect(await capture.responseMessageCounts() == [0, 1])
}
