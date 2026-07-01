import Foundation
import Testing
@testable import SwiftAISDK

private let toolApprovalSignatureSecret = "test-secret-key-for-hmac-signing"
private let toolApprovalSignatureBaseInput: JSONValue = ["path": "/tmp/cache"]

@Test func aiToolApprovalSignatureProducesValidSignatureThatVerifiesLikeUpstream() {
    let signature = signToolApproval(
        secret: toolApprovalSignatureSecret,
        approvalID: "approval-1",
        toolCallID: "call-1",
        toolName: "deleteFile",
        input: toolApprovalSignatureBaseInput
    )

    #expect(signature == "m_3hnkZy4Mx-__NmCA7J5NTNUwAk3bhbUtXD7PDAF_k")
    #expect(verifyToolApprovalSignature(
        secret: toolApprovalSignatureSecret,
        signature: signature,
        approvalID: "approval-1",
        toolCallID: "call-1",
        toolName: "deleteFile",
        input: toolApprovalSignatureBaseInput
    ))
}

@Test func aiToolApprovalSignatureRejectsTamperedApprovalIDLikeUpstream() {
    let signature = signedBaseToolApproval()

    #expect(!verifyToolApprovalSignature(
        secret: toolApprovalSignatureSecret,
        signature: signature,
        approvalID: "tampered-id",
        toolCallID: "call-1",
        toolName: "deleteFile",
        input: toolApprovalSignatureBaseInput
    ))
}

@Test func aiToolApprovalSignatureRejectsTamperedToolCallIDLikeUpstream() {
    let signature = signedBaseToolApproval()

    #expect(!verifyToolApprovalSignature(
        secret: toolApprovalSignatureSecret,
        signature: signature,
        approvalID: "approval-1",
        toolCallID: "tampered-call",
        toolName: "deleteFile",
        input: toolApprovalSignatureBaseInput
    ))
}

@Test func aiToolApprovalSignatureRejectsTamperedToolNameLikeUpstream() {
    let signature = signedBaseToolApproval()

    #expect(!verifyToolApprovalSignature(
        secret: toolApprovalSignatureSecret,
        signature: signature,
        approvalID: "approval-1",
        toolCallID: "call-1",
        toolName: "readFile",
        input: toolApprovalSignatureBaseInput
    ))
}

@Test func aiToolApprovalSignatureRejectsTamperedInputLikeUpstream() {
    let signature = signedBaseToolApproval()

    #expect(!verifyToolApprovalSignature(
        secret: toolApprovalSignatureSecret,
        signature: signature,
        approvalID: "approval-1",
        toolCallID: "call-1",
        toolName: "deleteFile",
        input: ["path": "/app/.env"]
    ))
}

@Test func aiToolApprovalSignatureRejectsDifferentSecretLikeUpstream() {
    let signature = signedBaseToolApproval()

    #expect(!verifyToolApprovalSignature(
        secret: "different-secret",
        signature: signature,
        approvalID: "approval-1",
        toolCallID: "call-1",
        toolName: "deleteFile",
        input: toolApprovalSignatureBaseInput
    ))
}

@Test func aiToolApprovalSignatureIsStableForEquivalentInputsWithDifferentKeyOrderLikeUpstream() {
    let first = signToolApproval(
        secret: toolApprovalSignatureSecret,
        approvalID: "approval-1",
        toolCallID: "call-1",
        toolName: "deleteFile",
        input: ["path": "/tmp/cache", "mode": "delete"]
    )
    let second = signToolApproval(
        secret: toolApprovalSignatureSecret,
        approvalID: "approval-1",
        toolCallID: "call-1",
        toolName: "deleteFile",
        input: ["mode": "delete", "path": "/tmp/cache"]
    )

    #expect(first == "jTYQjiYOokGT921hYZVx6-IdS7PG1YxAgveJL6neJeI")
    #expect(first == second)
}

@Test func aiMaybeSignApprovalReturnsNilWhenSecretIsNilLikeUpstream() {
    #expect(maybeSignApproval(
        secret: nil,
        approvalID: "approval-1",
        toolCallID: "call-1",
        toolName: "deleteFile",
        input: toolApprovalSignatureBaseInput
    ) == nil)
}

private func signedBaseToolApproval() -> String {
    signToolApproval(
        secret: toolApprovalSignatureSecret,
        approvalID: "approval-1",
        toolCallID: "call-1",
        toolName: "deleteFile",
        input: toolApprovalSignatureBaseInput
    )
}
