import Foundation
import Testing
@testable import SwiftAISDK

private let approvalSignatureSecret = "test-secret-for-signature"

@Test func aiValidateApprovedToolApprovalsKeepsInputMatchingToolSchemaLikeUpstream() async throws {
    let result = try await validateApprovedToolApprovals(
        approvedToolApprovals: [toolApproval(arguments: ["value": "test"])],
        toolsByName: ["tool1": tool1()],
        request: approvalValidationRequest(),
        toolApproval: nil
    )

    #expect(result.approvedToolApprovals.count == 1)
    #expect(result.deniedToolApprovals.isEmpty)
}

@Test func aiValidateApprovedToolApprovalsThrowsInvalidToolInputForSchemaMismatchLikeUpstream() async {
    do {
        _ = try await validateApprovedToolApprovals(
            approvedToolApprovals: [toolApproval(arguments: ["value": 42])],
            toolsByName: ["tool1": tool1()],
            request: approvalValidationRequest(),
            toolApproval: nil
        )
        Issue.record("expected invalid tool input error")
    } catch let error as AIInvalidToolInputError {
        #expect(error.toolName == "tool1")
        #expect(error.toolCallID == "call-1")
        #expect(error.input == ["value": 42])
        #expect(error.description.contains("Invalid input for tool tool1"))
    } catch {
        Issue.record("expected AIInvalidToolInputError, got \(error)")
    }
}

@Test func aiValidateApprovedToolApprovalsThrowsForForgedStrictPropertyLikeUpstream() async {
    do {
        _ = try await validateApprovedToolApprovals(
            approvedToolApprovals: [toolApproval(
                toolName: "deleteFile",
                arguments: ["path": "/app/.env", "extra": "forged"]
            )],
            toolsByName: ["deleteFile": deleteFileTool()],
            request: approvalValidationRequest(),
            toolApproval: nil
        )
        Issue.record("expected invalid tool input error")
    } catch let error as AIInvalidToolInputError {
        #expect(error.toolName == "deleteFile")
        #expect(error.input == ["path": "/app/.env", "extra": "forged"])
    } catch {
        Issue.record("expected AIInvalidToolInputError, got \(error)")
    }
}

@Test func aiValidateApprovedToolApprovalsMovesApprovedApprovalToDeniedWhenPolicyDeniesLikeUpstream() async throws {
    let result = try await validateApprovedToolApprovals(
        approvedToolApprovals: [toolApproval(arguments: ["value": "test"])],
        toolsByName: ["tool1": tool1()],
        request: approvalValidationRequest(),
        toolApproval: { _ in .denied(reason: nil) }
    )

    #expect(result.approvedToolApprovals.isEmpty)
    #expect(result.deniedToolApprovals.count == 1)
    #expect(result.deniedToolApprovals[0].approvalResponse.approved == false)
}

@Test func aiValidateApprovedToolApprovalsCarriesPolicyReasonIntoDenialResponseLikeUpstream() async throws {
    let result = try await validateApprovedToolApprovals(
        approvedToolApprovals: [toolApproval(
            arguments: ["value": "test"],
            responseReason: "client reason"
        )],
        toolsByName: ["tool1": tool1()],
        request: approvalValidationRequest(),
        toolApproval: { _ in .denied(reason: "policy changed") }
    )

    #expect(result.deniedToolApprovals.count == 1)
    #expect(result.deniedToolApprovals[0].approvalResponse.approved == false)
    #expect(result.deniedToolApprovals[0].approvalResponse.reason == "policy changed")
}

@Test func aiValidateApprovedToolApprovalsKeepsExistingReasonWhenPolicyDeniesWithoutReasonLikeUpstream() async throws {
    let result = try await validateApprovedToolApprovals(
        approvedToolApprovals: [toolApproval(
            arguments: ["value": "test"],
            responseReason: "client reason"
        )],
        toolsByName: ["tool1": tool1()],
        request: approvalValidationRequest(),
        toolApproval: { _ in .denied(reason: nil) }
    )

    #expect(result.deniedToolApprovals[0].approvalResponse.reason == "client reason")
}

@Test func aiValidateApprovedToolApprovalsReRunsFunctionPolicyOnApprovedInputLikeUpstream() async throws {
    let spy = ApprovalValidationSpy()
    let result = try await validateApprovedToolApprovals(
        approvedToolApprovals: [toolApproval(arguments: ["value": "test"])],
        toolsByName: ["tool1": tool1()],
        request: approvalValidationRequest(messages: [.user("hello")]),
        toolApproval: { context in
            await spy.record(context)
            return .denied(reason: nil)
        }
    )

    let captured = try #require(await spy.lastContext)
    #expect(captured.arguments == ["value": "test"])
    #expect(captured.toolCall.id == "call-1")
    #expect(captured.request.messages == [.user("hello")])
    #expect(result.approvedToolApprovals.isEmpty)
    #expect(result.deniedToolApprovals.count == 1)
}

@Test func aiValidateApprovedToolApprovalsPassesWhenSignatureIsValidLikeUpstream() async throws {
    let arguments: JSONValue = ["value": "test"]
    let signature = signToolApproval(
        secret: approvalSignatureSecret,
        approvalID: "approval-signed",
        toolCallID: "call-1",
        toolName: "tool1",
        input: arguments
    )

    let result = try await validateApprovedToolApprovals(
        approvedToolApprovals: [toolApproval(
            approvalID: "approval-signed",
            arguments: arguments,
            signature: signature
        )],
        toolsByName: ["tool1": tool1()],
        request: approvalValidationRequest(),
        toolApproval: nil,
        toolApprovalSecret: approvalSignatureSecret
    )

    #expect(result.approvedToolApprovals.count == 1)
}

@Test func aiValidateApprovedToolApprovalsThrowsWhenSignatureMissingLikeUpstream() async {
    do {
        _ = try await validateApprovedToolApprovals(
            approvedToolApprovals: [toolApproval(arguments: ["value": "test"])],
            toolsByName: ["tool1": tool1()],
            request: approvalValidationRequest(),
            toolApproval: nil,
            toolApprovalSecret: approvalSignatureSecret
        )
        Issue.record("expected invalid tool approval signature error")
    } catch let error as AIInvalidToolApprovalSignatureError {
        #expect(error.approvalID == "approval-1")
        #expect(error.toolCallID == "call-1")
        #expect(error.reason == "missing signature")
    } catch {
        Issue.record("expected AIInvalidToolApprovalSignatureError, got \(error)")
    }
}

@Test func aiValidateApprovedToolApprovalsThrowsWhenSignatureInvalidForTamperedInputLikeUpstream() async {
    let signature = signToolApproval(
        secret: approvalSignatureSecret,
        approvalID: "approval-1",
        toolCallID: "call-1",
        toolName: "tool1",
        input: ["value": "original"]
    )

    do {
        _ = try await validateApprovedToolApprovals(
            approvedToolApprovals: [toolApproval(
                arguments: ["value": "tampered"],
                signature: signature
            )],
            toolsByName: ["tool1": tool1()],
            request: approvalValidationRequest(),
            toolApproval: nil,
            toolApprovalSecret: approvalSignatureSecret
        )
        Issue.record("expected invalid tool approval signature error")
    } catch let error as AIInvalidToolApprovalSignatureError {
        #expect(error.approvalID == "approval-1")
        #expect(error.toolCallID == "call-1")
        #expect(error.reason == "invalid signature")
    } catch {
        Issue.record("expected AIInvalidToolApprovalSignatureError, got \(error)")
    }
}

@Test func aiValidateApprovedToolApprovalsIgnoresSignatureWhenNoSecretConfiguredLikeUpstream() async throws {
    let result = try await validateApprovedToolApprovals(
        approvedToolApprovals: [toolApproval(
            arguments: ["value": "test"],
            signature: "some-random-signature"
        )],
        toolsByName: ["tool1": tool1()],
        request: approvalValidationRequest(),
        toolApproval: nil
    )

    #expect(result.approvedToolApprovals.count == 1)
}

private actor ApprovalValidationSpy {
    private var contexts: [AIToolApprovalContext] = []

    var lastContext: AIToolApprovalContext? {
        contexts.last
    }

    func record(_ context: AIToolApprovalContext) {
        contexts.append(context)
    }
}

private func toolApproval(
    approvalID: String = "approval-1",
    toolCallID: String = "call-1",
    toolName: String = "tool1",
    arguments: JSONValue,
    responseReason: String? = nil,
    signature: String? = nil
) -> AICollectedToolApproval {
    let encodedArguments = String(data: try! JSONEncoder().encode(arguments), encoding: .utf8)!
    var providerMetadata: [String: JSONValue] = [:]
    if let signature {
        providerMetadata["signature"] = .string(signature)
    }
    return AICollectedToolApproval(
        approvalRequest: AIToolApprovalRequest(
            id: approvalID,
            toolName: toolName,
            arguments: encodedArguments,
            toolCallID: toolCallID,
            providerMetadata: providerMetadata
        ),
        approvalResponse: AIToolApprovalResponse(
            id: approvalID,
            approved: true,
            reason: responseReason
        ),
        toolCall: AIToolCall(
            id: toolCallID,
            name: toolName,
            arguments: encodedArguments
        )
    )
}

private func tool1() -> AITool {
    AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": [
                "value": ["type": "string"]
            ],
            "required": ["value"]
        ],
        execute: { _ in "ok" }
    )
}

private func deleteFileTool() -> AITool {
    AITool(
        name: "deleteFile",
        parameters: [
            "type": "object",
            "properties": [
                "path": ["type": "string"]
            ],
            "required": ["path"],
            "additionalProperties": false
        ],
        execute: { _ in "deleted" }
    )
}

private func approvalValidationRequest(messages: [AIMessage] = []) -> LanguageModelRequest {
    LanguageModelRequest(messages: messages)
}
