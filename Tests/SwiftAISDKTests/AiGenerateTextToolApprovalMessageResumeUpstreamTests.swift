import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiGenerateTextExecutesApprovedToolFromMessagesLikeUpstream() async throws {
    let toolCall = AIToolCall(
        id: "call-1",
        name: "tool1",
        arguments: #"{"value":"value"}"#
    )
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
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "Hello, world!",
        content: [.text("Hello, world!")],
        finishReason: "stop",
        rawValue: .object([:])
    ))
    let executionCapture = ToolExecutionInputListCapture()
    let contextCapture = ToolExecutionContextCapture()
    let prepareCapture = PrepareStepSnapshotCapture()
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ],
        executeWithContext: { input, context in
            await executionCapture.record(input)
            await contextCapture.record(arguments: input, context: context)
            return "result1"
        }
    ) { input in
        await executionCapture.record(input)
        return "result1"
    }

    let result = try await AI.generateText(
        model: model,
        request: LanguageModelRequest(messages: initialMessages),
        executableTools: [tool],
        maxSteps: 3,
        prepareStep: { context in
            await prepareCapture.record(context)
            return nil
        },
        toolApproval: { _ in .userApproval }
    )

    #expect(await executionCapture.values() == [["value": "value"]])
    let executionSnapshot = await contextCapture.snapshot()
    #expect(executionSnapshot.arguments == ["value": "value"])
    #expect(executionSnapshot.context?.toolCallID == "call-1")
    #expect(executionSnapshot.context?.messages == initialMessages)
    #expect(executionSnapshot.context?.abortSignal == nil)
    #expect(model.requests.count == 1)
    #expect(model.requests[0].messages == [
        .user("test-input"),
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        .toolResult(toolResult)
    ])
    #expect(result.responseMessages == [
        .toolResult(toolResult),
        .assistant("Hello, world!")
    ])
    let prepareSnapshots = await prepareCapture.snapshots()
    #expect(prepareSnapshots.count == 1)
    #expect(prepareSnapshots[0].responseMessages == [.toolResult(toolResult)])
}

@Test func aiGenerateTextExecutesTwoApprovedToolCallsFromMessagesLikeUpstream() async throws {
    let toolCall1 = AIToolCall(
        id: "call-1",
        name: "tool1",
        arguments: #"{"value":"value1"}"#
    )
    let approvalRequest1 = AIToolApprovalRequest(
        id: "approval-call-1",
        toolName: "tool1",
        arguments: #"{"value":"value1"}"#,
        toolCallID: "call-1"
    )
    let approvalResponse1 = AIToolApprovalResponse(id: "approval-call-1", approved: true)
    let toolResult1 = AIToolResult(toolCallID: "call-1", toolName: "tool1", result: "result1")
    let toolCall2 = AIToolCall(
        id: "call-2",
        name: "tool1",
        arguments: #"{"value":"value2"}"#
    )
    let approvalRequest2 = AIToolApprovalRequest(
        id: "approval-call-2",
        toolName: "tool1",
        arguments: #"{"value":"value2"}"#,
        toolCallID: "call-2"
    )
    let approvalResponse2 = AIToolApprovalResponse(id: "approval-call-2", approved: true)
    let toolResult2 = AIToolResult(toolCallID: "call-2", toolName: "tool1", result: "result1")
    let initialMessages: [AIMessage] = [
        .user("test-input"),
        AIMessage(role: .assistant, content: [
            .toolCall(toolCall1),
            .toolApprovalRequest(approvalRequest1),
            .toolCall(toolCall2),
            .toolApprovalRequest(approvalRequest2)
        ]),
        .toolResponses(approvalResponses: [approvalResponse1, approvalResponse2])
    ]
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "Hello, world!",
        content: [.text("Hello, world!")],
        finishReason: "tool-calls",
        rawValue: .object([:])
    ))
    let executionCapture = ToolExecutionInputListCapture()
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

    let result = try await AI.generateText(
        model: model,
        request: LanguageModelRequest(messages: initialMessages),
        executableTools: [tool],
        maxSteps: 3,
        toolApproval: { _ in .userApproval }
    )

    #expect(await executionCapture.values() == [["value": "value1"], ["value": "value2"]])
    #expect(result.text == "Hello, world!")
    #expect(result.steps.count == 1)
    #expect(model.requests.count == 1)
    #expect(model.requests[0].messages == [
        .user("test-input"),
        AIMessage(role: .assistant, content: [
            .toolCall(toolCall1),
            .toolCall(toolCall2)
        ]),
        .toolResponses(toolResults: [toolResult1, toolResult2])
    ])
    #expect(result.responseMessages == [
        .toolResponses(toolResults: [toolResult1, toolResult2]),
        .assistant("Hello, world!")
    ])
}

@Test func aiGenerateTextReturnsProviderExecutedToolApprovalRequestLikeUpstream() async throws {
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
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "",
        content: [
            .toolCall(toolCall),
            .toolApprovalRequest(approvalRequest)
        ],
        finishReason: "tool-calls",
        rawValue: .object([:])
    ))

    let result = try await AI.generateText(
        model: model,
        prompt: "test-input",
        maxSteps: 3
    )

    #expect(result.steps.count == 1)
    #expect(result.finishReason == "tool-calls")
    #expect(result.content == [
        .toolCall(toolCall),
        .toolApprovalRequest(approvalRequest)
    ])
    #expect(result.responseMessages == [
        AIMessage(role: .assistant, content: [
            .toolCall(toolCall),
            .toolApprovalRequest(approvalRequest)
        ])
    ])
}

@Test func aiGenerateTextForwardsApprovedProviderExecutedApprovalLikeUpstream() async throws {
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
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "Here is your shortened URL: https://short.url/abc",
        content: [
            .toolCall(toolCall),
            .toolResult(providerResult),
            .text("Here is your shortened URL: https://short.url/abc")
        ],
        finishReason: "stop",
        rawValue: .object([:])
    ))

    let result = try await AI.generateText(
        model: model,
        request: LanguageModelRequest(messages: initialMessages),
        executableTools: [],
        maxSteps: 3,
        prepareStep: { _ in nil }
    )

    #expect(model.requests.count == 1)
    #expect(model.requests[0].messages == [
        .user("Shorten this URL: https://example.com"),
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        .toolResponses(approvalResponses: [approvalResponse])
    ])
    #expect(result.content == [
        .toolCall(toolCall),
        .toolResult(providerResult),
        .text("Here is your shortened URL: https://short.url/abc")
    ])
    #expect(result.steps.count == 1)
    #expect(result.finishReason == "stop")
}

@Test func aiGenerateTextForwardsDeniedProviderExecutedApprovalLikeUpstream() async throws {
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
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "I understand. The tool execution was not approved.",
        content: [.text("I understand. The tool execution was not approved.")],
        finishReason: "stop",
        rawValue: .object([:])
    ))

    let result = try await AI.generateText(
        model: model,
        request: LanguageModelRequest(messages: initialMessages),
        executableTools: [],
        maxSteps: 3,
        prepareStep: { _ in nil }
    )

    #expect(model.requests.count == 1)
    #expect(model.requests[0].messages == [
        .user("Shorten this URL: https://example.com"),
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        .toolResponses(approvalResponses: [approvalResponse], toolResults: [deniedResult])
    ])
    #expect(result.content == [.text("I understand. The tool execution was not approved.")])
    #expect(result.steps.count == 1)
    #expect(result.finishReason == "stop")
}
