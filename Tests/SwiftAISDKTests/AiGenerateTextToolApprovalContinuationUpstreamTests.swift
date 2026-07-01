import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiGenerateTextSerializesApprovedToolExecutionErrorLikeUpstream() async throws {
    struct PluginTokenFailure: Error, CustomStringConvertible {
        var description: String { "No valid token for plugin" }
    }

    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let approvalRequest = AIToolApprovalRequest(
        id: "approval-1",
        toolName: "tool1",
        arguments: #"{"value":"value"}"#,
        toolCallID: "call-1"
    )
    let approvalResponse = AIToolApprovalResponse(id: "approval-1", approved: true)
    let errorResult = AIToolResult(
        toolCallID: "call-1",
        toolName: "tool1",
        result: [
            "type": "error-text",
            "value": "Error: No valid token for plugin"
        ],
        isError: true
    )
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "Hello, world!",
        content: [.text("Hello, world!")],
        finishReason: "stop",
        rawValue: .object([:])
    ))
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

    let result = try await AI.generateText(
        model: model,
        request: LanguageModelRequest(messages: [
            .user("test-input"),
            .assistant(toolCalls: [toolCall], toolApprovalRequests: [approvalRequest]),
            .toolResponses(approvalResponses: [approvalResponse])
        ]),
        executableTools: [tool],
        maxSteps: 3,
        toolApproval: { _ in .userApproval }
    )

    #expect(model.requests.count == 1)
    #expect(model.requests[0].messages == [
        .user("test-input"),
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        .toolResult(errorResult)
    ])
    #expect(result.responseMessages == [
        .toolResult(errorResult),
        .assistant("Hello, world!")
    ])
}

@Test func aiGenerateTextContinuesWithExecutionDeniedForDeniedApprovalResponseLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let approvalRequest = AIToolApprovalRequest(
        id: "approval-1",
        toolName: "tool1",
        arguments: #"{"value":"value"}"#,
        toolCallID: "call-1"
    )
    let approvalResponse = AIToolApprovalResponse(id: "approval-1", approved: false)
    let deniedResult = AIToolResult(
        toolCallID: "call-1",
        toolName: "tool1",
        result: ["type": "execution-denied"]
    )
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
        request: LanguageModelRequest(messages: [
            .user("test-input"),
            .assistant(toolCalls: [toolCall], toolApprovalRequests: [approvalRequest]),
            .toolResponses(approvalResponses: [approvalResponse])
        ]),
        executableTools: [tool],
        maxSteps: 3,
        toolApproval: { _ in .userApproval }
    )

    #expect(await executionCapture.values() == [])
    #expect(model.requests.count == 1)
    #expect(model.requests[0].messages == [
        .user("test-input"),
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        .toolResult(deniedResult)
    ])
    #expect(result.responseMessages == [
        .toolResult(deniedResult),
        .assistant("Hello, world!")
    ])
}

@Test func aiGenerateTextAutomaticallyDeniedToolContinuesLikeUpstream() async throws {
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
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            content: [.toolCall(toolCall)],
            finishReason: "tool-calls",
            rawValue: .object(["step": 1])
        ),
        TextGenerationResult(
            text: "Hello, world!",
            content: [.text("Hello, world!")],
            finishReason: "stop",
            rawValue: .object(["step": 2])
        )
    ])
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
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 3,
        toolApproval: { _ in .denied(reason: "blocked by policy") }
    )

    #expect(await executionCapture.values() == [])
    #expect(result.text == "Hello, world!")
    #expect(result.steps.count == 2)
    #expect(model.requests.count == 2)
    #expect(model.requests[1].messages == [
        .user("test-input"),
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        .toolResult(deniedResult)
    ])
    #expect(result.responseMessages == [
        AIMessage(role: .assistant, content: [
            .toolCall(toolCall),
            .toolApprovalRequest(approvalRequest)
        ]),
        .toolResponses(approvalResponses: [approvalResponse], toolResults: [deniedResult]),
        .assistant("Hello, world!")
    ])
}

@Test func aiGenerateTextAutomaticallyApprovedToolContinuesLikeUpstream() async throws {
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
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            content: [.toolCall(toolCall)],
            finishReason: "tool-calls",
            rawValue: .object(["step": 1])
        ),
        TextGenerationResult(
            text: "Hello, world!",
            content: [.text("Hello, world!")],
            finishReason: "stop",
            rawValue: .object(["step": 2])
        )
    ])
    let executionCapture = ToolExecutionInputListCapture()
    let contextCapture = ToolExecutionContextCapture()
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
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 3,
        toolApproval: { _ in .approved(reason: "trusted internal tool") }
    )

    #expect(await executionCapture.values() == [["value": "value"]])
    let executionSnapshot = await contextCapture.snapshot()
    let executionContext = try #require(executionSnapshot.context)
    #expect(executionSnapshot.arguments == ["value": "value"])
    #expect(executionContext.toolCallID == "call-1")
    #expect(executionContext.messages == [.user("test-input")])
    #expect(executionContext.abortSignal == nil)
    #expect(result.text == "Hello, world!")
    #expect(result.steps.count == 2)
    #expect(model.requests.count == 2)
    #expect(model.requests[1].messages == [
        .user("test-input"),
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        .toolResult(toolResult)
    ])
    #expect(result.responseMessages == [
        AIMessage(role: .assistant, content: [
            .toolCall(toolCall),
            .toolApprovalRequest(approvalRequest)
        ]),
        .toolResponses(approvalResponses: [approvalResponse], toolResults: [toolResult]),
        .assistant("Hello, world!")
    ])
}
