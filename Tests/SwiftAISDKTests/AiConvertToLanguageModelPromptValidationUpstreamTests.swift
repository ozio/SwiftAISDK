import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiConvertPromptValidationPassesProviderExecutedToolsWithDeferredResultsLikeUpstream() throws {
    let toolCall = AIToolCall(
        id: "call_1",
        name: "code_interpreter",
        arguments: #"{"code":"print(\"hello\")"}"#,
        providerExecuted: true
    )
    let request = LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [.toolCall(toolCall)])
    ])

    let prepared = try prepareLanguageModelCallOptions(request)

    #expect(prepared.messages == [
        AIMessage(role: .assistant, content: [.toolCall(toolCall)])
    ])
}

@Test func aiConvertPromptValidationPassesToolApprovalResponseLikeUpstream() throws {
    let toolCall = AIToolCall(
        id: "call_to_approve",
        name: "dangerous_action",
        arguments: #"{"action":"delete_db"}"#
    )
    let approvalRequest = AIToolApprovalRequest(
        id: "approval_123",
        toolName: "dangerous_action",
        arguments: #"{"action":"delete_db"}"#,
        toolCallID: "call_to_approve"
    )
    let approvalResponse = AIToolApprovalResponse(id: "approval_123", approved: true)
    let request = LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .toolCall(toolCall),
            .toolApprovalRequest(approvalRequest)
        ]),
        .toolResponses(approvalResponses: [approvalResponse])
    ])

    let prepared = try prepareLanguageModelCallOptions(request)

    #expect(prepared.messages == [
        AIMessage(role: .assistant, content: [.toolCall(toolCall)])
    ])
}

@Test func aiConvertPromptValidationPreservesProviderExecutedToolApprovalResponseLikeUpstream() throws {
    let toolCall = AIToolCall(
        id: "call_provider_executed",
        name: "mcp_tool",
        arguments: #"{"action":"execute"}"#,
        providerExecuted: true
    )
    let approvalRequest = AIToolApprovalRequest(
        id: "approval_provider",
        toolName: "mcp_tool",
        arguments: #"{"action":"execute"}"#,
        toolCallID: "call_provider_executed"
    )
    let approvalResponse = AIToolApprovalResponse(
        id: "approval_provider",
        approved: true,
        providerExecuted: true
    )
    let request = LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .toolCall(toolCall),
            .toolApprovalRequest(approvalRequest)
        ]),
        .toolResponses(approvalResponses: [approvalResponse])
    ])

    let prepared = try prepareLanguageModelCallOptions(request)

    #expect(prepared.messages == [
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        .toolResponses(approvalResponses: [approvalResponse])
    ])
    #expect(prepared.messages[1].content == [.toolApprovalResponse(approvalResponse)])
}

@Test func aiConvertPromptValidationThrowsForActualMissingResultsLikeUpstream() throws {
    let toolCall = AIToolCall(
        id: "call_missing_result",
        name: "regular_tool",
        arguments: #"{}"#
    )

    #expect(throws: AIMissingToolResultsError(toolCallIDs: ["call_missing_result"])) {
        _ = try prepareLanguageModelCallOptions(LanguageModelRequest(messages: [
            AIMessage(role: .assistant, content: [.toolCall(toolCall)])
        ]))
    }
}
