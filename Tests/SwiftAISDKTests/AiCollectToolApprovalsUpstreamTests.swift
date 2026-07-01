import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiCollectToolApprovalsReturnsNoneWhenLastMessageIsNotToolLikeUpstream() throws {
    let result = try collectToolApprovals(messages: [.user("Hello, world!")])

    #expect(result == .empty)
}

@Test func aiCollectToolApprovalsIgnoresApprovalRequestWithoutResponseLikeUpstream() throws {
    let result = try collectToolApprovals(messages: [
        assistantMessageForApproval(
            toolCall: approvalToolCall(id: "call-1", value: "test-input"),
            approvalRequest: approvalRequest(id: "approval-id-1", toolCallID: "call-1")
        ),
        AIMessage(role: .tool, content: [])
    ])

    #expect(result == .empty)
}

@Test func aiCollectToolApprovalsReturnsApprovedApprovalWithApprovedResponseLikeUpstream() throws {
    let toolCall = approvalToolCall(id: "call-1", value: "test-input")
    let request = approvalRequest(id: "approval-id-1", toolCallID: "call-1")
    let response = AIToolApprovalResponse(id: "approval-id-1", approved: true)

    let result = try collectToolApprovals(messages: [
        assistantMessageForApproval(toolCall: toolCall, approvalRequest: request),
        .toolResponses(approvalResponses: [response])
    ])

    #expect(result.approvedToolApprovals == [
        AICollectedToolApproval(
            approvalRequest: request,
            approvalResponse: response,
            toolCall: toolCall
        )
    ])
    #expect(result.deniedToolApprovals == [])
}

@Test func aiCollectToolApprovalsIgnoresApprovedApprovalThatAlreadyHasToolResultLikeUpstream() throws {
    let toolCall = approvalToolCall(id: "call-1", value: "test-input")
    let request = approvalRequest(id: "approval-id-1", toolCallID: "call-1")
    let response = AIToolApprovalResponse(id: "approval-id-1", approved: true)
    let resultPart = AIToolResult(
        toolCallID: "call-1",
        toolName: "tool1",
        result: "test-output",
        modelOutput: ["type": "text", "value": "test-output"]
    )

    let result = try collectToolApprovals(messages: [
        assistantMessageForApproval(toolCall: toolCall, approvalRequest: request),
        .toolResponses(approvalResponses: [response], toolResults: [resultPart])
    ])

    #expect(result == .empty)
}

@Test func aiCollectToolApprovalsReturnsDeniedApprovalWithDeniedResponseLikeUpstream() throws {
    let toolCall = approvalToolCall(id: "call-1", value: "test-input")
    let request = approvalRequest(id: "approval-id-1", toolCallID: "call-1")
    let response = AIToolApprovalResponse(
        id: "approval-id-1",
        approved: false,
        reason: "test-reason"
    )

    let result = try collectToolApprovals(messages: [
        assistantMessageForApproval(toolCall: toolCall, approvalRequest: request),
        .toolResponses(approvalResponses: [response])
    ])

    #expect(result.approvedToolApprovals == [])
    #expect(result.deniedToolApprovals == [
        AICollectedToolApproval(
            approvalRequest: request,
            approvalResponse: response,
            toolCall: toolCall
        )
    ])
}

@Test func aiCollectToolApprovalsIgnoresDeniedApprovalThatAlreadyHasToolResultLikeUpstream() throws {
    let toolCall = approvalToolCall(id: "call-1", value: "test-input")
    let request = approvalRequest(id: "approval-id-1", toolCallID: "call-1")
    let response = AIToolApprovalResponse(
        id: "approval-id-1",
        approved: false,
        reason: "test-reason"
    )
    let resultPart = AIToolResult(
        toolCallID: "call-1",
        toolName: "tool1",
        result: ["type": "execution-denied", "reason": "test-reason"]
    )

    let result = try collectToolApprovals(messages: [
        assistantMessageForApproval(toolCall: toolCall, approvalRequest: request),
        .toolResponses(approvalResponses: [response], toolResults: [resultPart])
    ])

    #expect(result == .empty)
}

@Test func aiCollectToolApprovalsThrowsForUnknownApprovalIDLikeUpstream() {
    #expect(throws: AIInvalidToolApprovalError(approvalID: "unknown-approval-id")) {
        _ = try collectToolApprovals(messages: [
            assistantMessageForApproval(
                toolCall: approvalToolCall(id: "call-1", value: "test-input"),
                approvalRequest: approvalRequest(id: "approval-id-1", toolCallID: "call-1")
            ),
            .toolResponses(approvalResponses: [
                AIToolApprovalResponse(id: "unknown-approval-id", approved: true)
            ])
        ])
    }
}

@Test func aiCollectToolApprovalsThrowsWhenReferencedToolCallDoesNotExistLikeUpstream() {
    #expect(throws: AIToolCallNotFoundForApprovalError(
        toolCallID: "call-that-does-not-exist",
        approvalID: "approval-id-1"
    )) {
        _ = try collectToolApprovals(messages: [
            AIMessage(role: .assistant, content: [
                .toolApprovalRequest(approvalRequest(
                    id: "approval-id-1",
                    toolCallID: "call-that-does-not-exist"
                ))
            ]),
            .toolResponses(approvalResponses: [
                AIToolApprovalResponse(id: "approval-id-1", approved: true)
            ])
        ])
    }
}

@Test func aiCollectToolApprovalsHandlesMixedApprovedDeniedAndProcessedApprovalsLikeUpstream() throws {
    var assistantParts: [AIContentPart] = []
    for index in 1...6 {
        let callID = "call-approval-\(index)"
        assistantParts.append(.toolCall(approvalToolCall(id: callID, value: "test-input-\(index)")))
        assistantParts.append(.toolApprovalRequest(approvalRequest(
            id: "approval-id-\(index)",
            toolCallID: callID
        )))
    }

    let result = try collectToolApprovals(messages: [
        AIMessage(role: .assistant, content: assistantParts),
        .toolResponses(
            approvalResponses: [
                AIToolApprovalResponse(id: "approval-id-1", approved: true),
                AIToolApprovalResponse(id: "approval-id-2", approved: true),
                AIToolApprovalResponse(id: "approval-id-3", approved: false, reason: "test-reason"),
                AIToolApprovalResponse(id: "approval-id-4", approved: false),
                AIToolApprovalResponse(id: "approval-id-5", approved: true),
                AIToolApprovalResponse(id: "approval-id-6", approved: false)
            ],
            toolResults: [
                AIToolResult(toolCallID: "call-approval-5", toolName: "tool1", result: "test-output-5"),
                AIToolResult(toolCallID: "call-approval-6", toolName: "tool1", result: ["type": "execution-denied"])
            ]
        )
    ])

    #expect(result.approvedToolApprovals.map(\.approvalRequest.id) == [
        "approval-id-1",
        "approval-id-2"
    ])
    #expect(result.deniedToolApprovals.map(\.approvalRequest.id) == [
        "approval-id-3",
        "approval-id-4"
    ])
    #expect(result.approvedToolApprovals.map(\.toolCall.id) == [
        "call-approval-1",
        "call-approval-2"
    ])
    #expect(result.deniedToolApprovals.map(\.toolCall.id) == [
        "call-approval-3",
        "call-approval-4"
    ])
    #expect(result.deniedToolApprovals[0].approvalResponse.reason == "test-reason")
}

private func approvalToolCall(id: String, value: String) -> AIToolCall {
    AIToolCall(
        id: id,
        name: "tool1",
        arguments: #"{"value":"\#(value)"}"#
    )
}

private func approvalRequest(id: String, toolCallID: String) -> AIToolApprovalRequest {
    AIToolApprovalRequest(
        id: id,
        toolName: "tool1",
        arguments: "{}",
        toolCallID: toolCallID
    )
}

private func assistantMessageForApproval(
    toolCall: AIToolCall,
    approvalRequest: AIToolApprovalRequest
) -> AIMessage {
    AIMessage(role: .assistant, content: [
        .toolCall(toolCall),
        .toolApprovalRequest(approvalRequest)
    ])
}
