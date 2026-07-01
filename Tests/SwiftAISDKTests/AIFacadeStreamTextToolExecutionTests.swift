import Foundation
import Testing
@testable import SwiftAISDK

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

@Test func aiStreamTextWaitsForDelayedAsyncToolResultBeforeContinuingLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{ "value": "value" }"#)
    let responseMetadata = AIResponseMetadata(
        id: "id-0",
        timestamp: Date(timeIntervalSince1970: 0),
        modelID: "mock-model-id"
    )
    let toolResult = AIToolResult(toolCallID: "call-1", toolName: "tool1", result: .string("value-result"))
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .responseMetadata(responseMetadata),
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 13))
            ],
            [
                .textDelta("done"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 3))
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
        try await Task.sleep(nanoseconds: 20_000_000)
        return .string("\(input["value"]?.stringValue ?? "")-result")
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

    #expect(streamed == [
        .responseMetadata(responseMetadata),
        .toolCall(toolCall),
        .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 13)),
        .toolResult(toolResult),
        .textDelta("done"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 3))
    ])
    #expect(model.streamRequests.count == 2)
    #expect(model.streamRequests[1].messages == [
        .user("test-input"),
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        AIMessage(role: .tool, content: [.toolResult(toolResult)])
    ])
}

@Test func aiStreamTextAutomaticallyDeniedToolContinuesLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let approvalRequest = AIToolApprovalRequest(
        id: "approval-call-1",
        toolName: "tool1",
        arguments: #"{"value":"value"}"#,
        toolCallID: "call-1",
        isAutomatic: true
    )
    let approvalResponse = AIToolApprovalResponse(
        id: "approval-call-1",
        approved: false,
        reason: "blocked by policy"
    )
    let deniedResult = AIToolResult(
        toolCallID: "call-1",
        toolName: "tool1",
        result: ["type": "execution-denied", "reason": "blocked by policy"]
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .streamStart(warnings: []),
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .streamStart(warnings: []),
                .textStart(id: "1"),
                .textDeltaPart(id: "1", delta: "Hello, world!"),
                .textEnd(id: "1"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
            ]
        ]
    )
    let executionCapture = StreamToolExecutionInputListCapture()
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { input in
        await executionCapture.record(input)
        return .string("result1")
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 3,
        toolApproval: { _ in .denied(reason: "blocked by policy") }
    ) {
        streamed.append(part)
    }

    #expect(await executionCapture.values() == [])
    #expect(streamed == [
        .streamStart(warnings: []),
        .toolCall(toolCall),
        .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3)),
        .toolApprovalRequest(approvalRequest),
        .toolApprovalResponse(approvalResponse),
        .toolResult(deniedResult),
        .streamStart(warnings: []),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Hello, world!"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
    ])
    #expect(model.streamRequests.count == 2)
    #expect(model.streamRequests[1].messages == [
        .user("test-input"),
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        .toolResult(deniedResult)
    ])
}

@Test func aiStreamTextAutomaticallyApprovedToolContinuesLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let approvalRequest = AIToolApprovalRequest(
        id: "approval-call-1",
        toolName: "tool1",
        arguments: #"{"value":"value"}"#,
        toolCallID: "call-1",
        isAutomatic: true
    )
    let approvalResponse = AIToolApprovalResponse(
        id: "approval-call-1",
        approved: true,
        reason: "trusted internal tool"
    )
    let toolResult = AIToolResult(toolCallID: "call-1", toolName: "tool1", result: "result1")
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .streamStart(warnings: []),
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .streamStart(warnings: []),
                .textStart(id: "1"),
                .textDeltaPart(id: "1", delta: "Hello, world!"),
                .textEnd(id: "1"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
            ]
        ]
    )
    let executionCapture = StreamToolExecutionInputListCapture()
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { input in
        await executionCapture.record(input)
        return .string("result1")
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 3,
        toolApproval: { _ in .approved(reason: "trusted internal tool") }
    ) {
        streamed.append(part)
    }

    #expect(await executionCapture.values() == [["value": "value"]])
    #expect(streamed == [
        .streamStart(warnings: []),
        .toolCall(toolCall),
        .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3)),
        .toolApprovalRequest(approvalRequest),
        .toolApprovalResponse(approvalResponse),
        .toolResult(toolResult),
        .streamStart(warnings: []),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Hello, world!"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
    ])
    #expect(model.streamRequests.count == 2)
    #expect(model.streamRequests[1].messages == [
        .user("test-input"),
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        .toolResult(toolResult)
    ])
}

@Test func aiStreamTextMixedUserApprovalAndNotApplicableToolCallsLikeUpstream() async throws {
    let approvalCall = AIToolCall(
        id: "call-1",
        name: "tool1",
        arguments: #"{"value":"value-needs-approval"}"#
    )
    let executableCall = AIToolCall(
        id: "call-2",
        name: "tool1",
        arguments: #"{"value":"value-no-approval"}"#
    )
    let approvalRequest = AIToolApprovalRequest(
        id: "approval-call-1",
        toolName: "tool1",
        arguments: #"{"value":"value-needs-approval"}"#,
        toolCallID: "call-1"
    )
    let executableResult = AIToolResult(
        toolCallID: "call-2",
        toolName: "tool1",
        result: "result for value-no-approval"
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .streamStart(warnings: []),
            .toolCall(approvalCall),
            .toolCall(executableCall),
            .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
        ]]
    )
    let approvalCapture = StreamToolExecutionInputListCapture()
    let executionCapture = StreamToolExecutionInputListCapture()
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { input in
        await executionCapture.record(input)
        return .string("result for \(input["value"]?.stringValue ?? "")")
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 3,
        toolApproval: { context in
            await approvalCapture.record(context.arguments)
            return context.arguments["value"]?.stringValue == "value-needs-approval"
                ? .userApproval
                : .notApplicable
        }
    ) {
        streamed.append(part)
    }

    #expect(await approvalCapture.values() == [
        ["value": "value-needs-approval"],
        ["value": "value-no-approval"]
    ])
    #expect(await executionCapture.values() == [["value": "value-no-approval"]])
    #expect(streamed == [
        .streamStart(warnings: []),
        .toolCall(approvalCall),
        .toolCall(executableCall),
        .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3)),
        .toolApprovalRequest(approvalRequest),
        .toolResult(executableResult)
    ])
    #expect(model.streamRequests.count == 1)
}

@Test func aiStreamTextExecutesApprovedToolFromMessagesLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let approvalRequest = AIToolApprovalRequest(
        id: "approval-call-1",
        toolName: "tool1",
        arguments: #"{"value":"value"}"#,
        toolCallID: "call-1"
    )
    let approvalResponse = AIToolApprovalResponse(id: "approval-call-1", approved: true)
    let toolResult = AIToolResult(toolCallID: "call-1", toolName: "tool1", result: "result1")
    let initialMessages: [AIMessage] = [
        .user("test-input"),
        .assistant(toolCalls: [toolCall], toolApprovalRequests: [approvalRequest]),
        .toolResponses(approvalResponses: [approvalResponse])
    ]
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .streamStart(warnings: []),
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "Hello, world!"),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
        ]]
    )
    let executionCapture = StreamToolExecutionInputListCapture()
    let prepareCapture = StreamPrepareStepResponseMessagesCapture()
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { input in
        await executionCapture.record(input)
        return "result1"
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        request: LanguageModelRequest(messages: initialMessages),
        executableTools: [tool],
        maxSteps: 3,
        prepareStep: { context in
            await prepareCapture.record(context.responseMessages)
            return nil
        },
        toolApproval: { _ in .userApproval }
    ) {
        streamed.append(part)
    }

    #expect(await executionCapture.values() == [["value": "value"]])
    #expect(streamed == [
        .toolResult(toolResult),
        .streamStart(warnings: []),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Hello, world!"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
    ])
    #expect(model.streamRequests.count == 1)
    #expect(model.streamRequests[0].messages == [
        .user("test-input"),
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        .toolResult(toolResult)
    ])
    #expect(await prepareCapture.snapshots() == [[.toolResult(toolResult)]])
}

@Test func aiStreamTextSerializesApprovedToolExecutionErrorFromMessagesLikeUpstream() async throws {
    struct PluginTokenFailure: Error, CustomStringConvertible {
        var description: String { "No valid token for plugin" }
    }

    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let approvalRequest = AIToolApprovalRequest(
        id: "approval-call-1",
        toolName: "tool1",
        arguments: #"{"value":"value"}"#,
        toolCallID: "call-1"
    )
    let approvalResponse = AIToolApprovalResponse(id: "approval-call-1", approved: true)
    let errorResult = AIToolResult(
        toolCallID: "call-1",
        toolName: "tool1",
        result: [
            "type": "error-text",
            "value": "Error: No valid token for plugin"
        ],
        isError: true
    )
    let initialMessages: [AIMessage] = [
        .user("test-input"),
        .assistant(toolCalls: [toolCall], toolApprovalRequests: [approvalRequest]),
        .toolResponses(approvalResponses: [approvalResponse])
    ]
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .streamStart(warnings: []),
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "Hello, world!"),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
        ]]
    )
    let prepareCapture = StreamPrepareStepResponseMessagesCapture()
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { _ in
        throw PluginTokenFailure()
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        request: LanguageModelRequest(messages: initialMessages),
        executableTools: [tool],
        maxSteps: 3,
        prepareStep: { context in
            await prepareCapture.record(context.responseMessages)
            return nil
        },
        toolApproval: { _ in .userApproval }
    ) {
        streamed.append(part)
    }

    #expect(streamed == [
        .toolResult(errorResult),
        .streamStart(warnings: []),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Hello, world!"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
    ])
    #expect(model.streamRequests.count == 1)
    #expect(model.streamRequests[0].messages == [
        .user("test-input"),
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        .toolResult(errorResult)
    ])
    #expect(await prepareCapture.snapshots() == [[.toolResult(errorResult)]])
}

@Test func aiStreamTextContinuesWithExecutionDeniedForDeniedApprovalResponseLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let approvalRequest = AIToolApprovalRequest(
        id: "approval-call-1",
        toolName: "tool1",
        arguments: #"{"value":"value"}"#,
        toolCallID: "call-1"
    )
    let approvalResponse = AIToolApprovalResponse(id: "approval-call-1", approved: false)
    let deniedResult = AIToolResult(
        toolCallID: "call-1",
        toolName: "tool1",
        result: ["type": "execution-denied"]
    )
    let initialMessages: [AIMessage] = [
        .user("test-input"),
        .assistant(toolCalls: [toolCall], toolApprovalRequests: [approvalRequest]),
        .toolResponses(approvalResponses: [approvalResponse])
    ]
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .streamStart(warnings: []),
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "Hello, world!"),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
        ]]
    )
    let executionCapture = StreamToolExecutionInputListCapture()
    let prepareCapture = StreamPrepareStepResponseMessagesCapture()
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { input in
        await executionCapture.record(input)
        return "result1"
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        request: LanguageModelRequest(messages: initialMessages),
        executableTools: [tool],
        maxSteps: 3,
        prepareStep: { context in
            await prepareCapture.record(context.responseMessages)
            return nil
        },
        toolApproval: { _ in .userApproval }
    ) {
        streamed.append(part)
    }

    #expect(await executionCapture.values() == [])
    #expect(streamed == [
        .toolResult(deniedResult),
        .streamStart(warnings: []),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Hello, world!"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
    ])
    #expect(model.streamRequests.count == 1)
    #expect(model.streamRequests[0].messages == [
        .user("test-input"),
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        .toolResult(deniedResult)
    ])
    #expect(await prepareCapture.snapshots() == [[.toolResult(deniedResult)]])
}

@Test func aiStreamTextForwardsApprovedProviderExecutedApprovalLikeUpstream() async throws {
    let toolCall = AIToolCall(
        id: "mcp-call-1",
        name: "mcp_tool",
        arguments: #"{"query":"test"}"#,
        providerExecuted: true
    )
    let approvalRequest = AIToolApprovalRequest(
        id: "mcp-approval-1",
        toolName: "mcp_tool",
        arguments: #"{"query":"test"}"#,
        toolCallID: "mcp-call-1"
    )
    let approvalResponse = AIToolApprovalResponse(
        id: "mcp-approval-1",
        approved: true,
        providerExecuted: true
    )
    let providerResult = AIToolResult(
        toolCallID: "mcp-call-1",
        toolName: "mcp_tool",
        result: ["shortened_url": "https://short.url/abc"],
        providerExecuted: true
    )
    let initialMessages: [AIMessage] = [
        .user("Shorten this URL: https://example.com"),
        AIMessage(role: .assistant, content: [
            .toolCall(toolCall),
            .toolApprovalRequest(approvalRequest)
        ]),
        .toolResponses(approvalResponses: [approvalResponse])
    ]
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .streamStart(warnings: []),
            .toolCall(toolCall),
            .toolResult(providerResult),
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "Here is your shortened URL: https://short.url/abc"),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
        ]]
    )

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        request: LanguageModelRequest(messages: initialMessages),
        executableTools: [],
        maxSteps: 3,
        prepareStep: { _ in nil }
    ) {
        streamed.append(part)
    }

    #expect(streamed == [
        .streamStart(warnings: []),
        .toolCall(toolCall),
        .toolResult(providerResult),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Here is your shortened URL: https://short.url/abc"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
    ])
    #expect(model.streamRequests.count == 1)
    #expect(model.streamRequests[0].messages == [
        .user("Shorten this URL: https://example.com"),
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        .toolResponses(approvalResponses: [approvalResponse])
    ])
}

@Test func aiStreamTextForwardsDeniedProviderExecutedApprovalLikeUpstream() async throws {
    let providerMetadata: [String: JSONValue] = ["openai": ["approvalId": "mcp-approval-1"]]
    let toolCall = AIToolCall(
        id: "mcp-call-1",
        name: "mcp_tool",
        arguments: #"{"query":"test"}"#,
        providerExecuted: true,
        providerMetadata: providerMetadata
    )
    let approvalRequest = AIToolApprovalRequest(
        id: "mcp-approval-1",
        toolName: "mcp_tool",
        arguments: #"{"query":"test"}"#,
        toolCallID: "mcp-call-1"
    )
    let approvalResponse = AIToolApprovalResponse(
        id: "mcp-approval-1",
        approved: false,
        reason: "User denied the request",
        providerExecuted: true
    )
    let deniedResult = AIToolResult(
        toolCallID: "mcp-call-1",
        toolName: "mcp_tool",
        result: ["type": "execution-denied", "reason": "User denied the request"],
        providerExecuted: true,
        providerMetadata: providerMetadata
    )
    let initialMessages: [AIMessage] = [
        .user("Shorten this URL: https://example.com"),
        AIMessage(role: .assistant, content: [
            .toolCall(toolCall),
            .toolApprovalRequest(approvalRequest)
        ]),
        .toolResponses(approvalResponses: [approvalResponse])
    ]
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .streamStart(warnings: []),
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "I understand. The tool execution was not approved."),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
        ]]
    )

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        request: LanguageModelRequest(messages: initialMessages),
        executableTools: [],
        maxSteps: 3,
        prepareStep: { _ in nil }
    ) {
        streamed.append(part)
    }

    #expect(streamed == [
        .toolResult(deniedResult),
        .streamStart(warnings: []),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "I understand. The tool execution was not approved."),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
    ])
    #expect(model.streamRequests.count == 1)
    #expect(model.streamRequests[0].messages == [
        .user("Shorten this URL: https://example.com"),
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        .toolResponses(approvalResponses: [approvalResponse], toolResults: [deniedResult])
    ])
}

@Test func aiStreamTextReturnsInvalidToolCallErrorsAsToolResultsLikeUpstream() async throws {
    let toolCall = AIToolCall(
        id: "call-1",
        name: "cityAttractions",
        arguments: #"{"cities":"San Francisco"}"#
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .streamStart(warnings: []),
            .toolInputStart(id: "call-1", name: "cityAttractions"),
            .toolInputDelta(id: "call-1", delta: #"{"cities":"San Francisco"}"#),
            .toolInputEnd(id: "call-1"),
            .toolCall(toolCall),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 13))
        ]
    )
    let stepCapture = StreamStepContentCapture()
    let cityAttractions = AITool(
        name: "cityAttractions",
        parameters: [
            "type": "object",
            "properties": ["city": ["type": "string"]],
            "required": ["city"],
            "additionalProperties": false
        ]
    ) { _ in
        Issue.record("Invalid tool calls must not execute.")
        return "unused"
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "What are the tourist attractions in San Francisco?",
        executableTools: [cityAttractions],
        maxSteps: 3,
        stopWhen: [
            AIStopCondition { context in
                await stepCapture.record(context.steps.last?.content ?? [])
                return true
            }
        ]
    ) {
        streamed.append(part)
    }

    let toolResultPart = try #require(streamed.compactMap { part -> AIToolResult? in
        guard case let .toolResult(result) = part else { return nil }
        return result
    }.first)

    #expect(streamed.starts(with: [
        .streamStart(warnings: []),
        .toolInputStart(id: "call-1", name: "cityAttractions"),
        .toolInputDelta(id: "call-1", delta: #"{"cities":"San Francisco"}"#),
        .toolInputEnd(id: "call-1"),
        .toolCall(toolCall),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 13))
    ]))
    #expect(toolResultPart.toolCallID == "call-1")
    #expect(toolResultPart.toolName == "cityAttractions")
    #expect(toolResultPart.isError)
    #expect(toolResultPart.result["type"]?.stringValue == "error-text")
    #expect(toolResultPart.result["value"]?.stringValue?.contains("Invalid input for tool cityAttractions") == true)
    #expect(toolResultPart.result["value"]?.stringValue?.contains("$.city") == true)
    #expect(await stepCapture.content() == [
        .toolCall(toolCall),
        .toolResult(toolResultPart)
    ])
    #expect(model.streamRequests.count == 1)
}

