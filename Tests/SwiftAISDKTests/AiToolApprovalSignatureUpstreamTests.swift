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

    #expect(signature == "KhhdqErvPwq9PCD-YYlVKgPDJ_tby36fpqptjJpmYhE")
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

    #expect(first == "WQDC7CJ6huTJ9SVQ4ZCNxD2Kciv6eD1qO3EBYOKXujk")
    #expect(first == second)
}

@Test func aiToolApprovalSignatureMatchesJavaScriptNumberSerializationVectors() {
    // Generated with the published ai@7.0.37 canonical hashing and signing
    // algorithm under Node.js.
    let vectors: [(value: Double, signature: String)] = [
        (1e-7, "5H9kx1_JTCfjbEuGyDT0Cc0cF6YJio-zFvxnKtOFnZs"),
        (1e-6, "RngDVBNurf7lvnftLQ_p0eozsUYtIoXxzvBUFkRC0WE"),
        (1e20, "5uS9GdgpiHhtxa2zOlwKKXW17whsk688zrGtp6rhFms"),
        (1e21, "iutiANa5lMDQg0PpVxoD5q1xoGpci84Su9ITSxG96Xc"),
        (-0.0, "J5tgBzIFg4BuQEEkYO608I0Oik46knR0KH4fX65UohE"),
        (1.2345678901234567, "VeK5gRT6ndouuZ14b-s5MDRw62eEytDBmQYW3roQQrs")
    ]

    for vector in vectors {
        #expect(signToolApproval(
            secret: toolApprovalSignatureSecret,
            approvalID: "approval-1",
            toolCallID: "call-1",
            toolName: "calculate",
            input: ["value": .number(vector.value)]
        ) == vector.signature)
    }
}

@Test func aiToolApprovalSignatureMatchesJavaScriptUTF16KeyOrdering() {
    // JavaScript's default Array.sort compares UTF-16 code units. That places
    // the surrogate pair for U+1F600 before the BMP private-use U+E000 scalar,
    // unlike Swift's native String ordering.
    #expect(signToolApproval(
        secret: toolApprovalSignatureSecret,
        approvalID: "approval-1",
        toolCallID: "call-1",
        toolName: "unicodeKeys",
        input: [
            "\u{E000}": "bmp/path",
            "😀": "astral/path"
        ]
    ) == "2XtL0LmI4XOyS_2G6WQW5qmGQRR703FXpf9ekRG8aFg")
}

@Test func aiToolApprovalSignatureDoesNotCollideWhenNewlineIsRetupledLikeUpstream() {
    let signedToolName = "searchDocs\ndeleteFile"
    let retupledToolCallID = "call-1\nsearchDocs"
    let input: JSONValue = ["path": "/tmp/target"]

    let signature = signToolApproval(
        secret: toolApprovalSignatureSecret,
        approvalID: "approval-1",
        toolCallID: "call-1",
        toolName: signedToolName,
        input: input
    )
    let retupledSignature = signToolApproval(
        secret: toolApprovalSignatureSecret,
        approvalID: "approval-1",
        toolCallID: retupledToolCallID,
        toolName: "deleteFile",
        input: input
    )

    #expect(signature != retupledSignature)
    #expect(verifyToolApprovalSignature(
        secret: toolApprovalSignatureSecret,
        signature: signature,
        approvalID: "approval-1",
        toolCallID: "call-1",
        toolName: signedToolName,
        input: input
    ))
    #expect(!verifyToolApprovalSignature(
        secret: toolApprovalSignatureSecret,
        signature: signature,
        approvalID: "approval-1",
        toolCallID: retupledToolCallID,
        toolName: "deleteFile",
        input: input
    ))
}

@Test func aiToolApprovalSignatureSeparatesControlAndJSONCharactersLikeUpstream() {
    let input: JSONValue = ["path": "/tmp/target"]
    for delimiter in ["\n", "\r", "\t", "\0", "\"", "\\"] {
        let signature = signToolApproval(
            secret: toolApprovalSignatureSecret,
            approvalID: "approval-1",
            toolCallID: "call-1",
            toolName: "alpha\(delimiter)beta",
            input: input
        )

        #expect(!verifyToolApprovalSignature(
            secret: toolApprovalSignatureSecret,
            signature: signature,
            approvalID: "approval-1",
            toolCallID: "call-1\(delimiter)alpha",
            toolName: "beta",
            input: input
        ))
    }
}

@Test func aiToolApprovalSignatureAcceptsSafeLegacyPayloadLikeUpstream() {
    #expect(verifyToolApprovalSignature(
        secret: toolApprovalSignatureSecret,
        signature: "m_3hnkZy4Mx-__NmCA7J5NTNUwAk3bhbUtXD7PDAF_k",
        approvalID: "approval-1",
        toolCallID: "call-1",
        toolName: "deleteFile",
        input: toolApprovalSignatureBaseInput
    ))
}

@Test func aiToolApprovalSignatureRejectsLegacyNewlineRetuplingLikeUpstream() {
    #expect(!verifyToolApprovalSignature(
        secret: toolApprovalSignatureSecret,
        signature: "liwG5e28wvAcJBngpKBpHSbMbIJXmKKcHXvhsABe-Z8",
        approvalID: "approval-1",
        toolCallID: "call-1\nsearchDocs",
        toolName: "deleteFile",
        input: ["path": "/tmp/target"]
    ))
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
