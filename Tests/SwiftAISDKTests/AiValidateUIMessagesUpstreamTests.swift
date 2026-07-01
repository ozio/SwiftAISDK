import Testing
@testable import SwiftAISDK

@Test func aiValidateUIMessagesAcceptsMessageMetadataWithoutSchemaLikeUpstream() throws {
    let message = AIUIMessage(
        id: "1",
        role: .user,
        parts: [
            .text(AIUITextPart(text: "Hello, world!"))
        ],
        metadata: [
            "foo": "bar",
            "count": 1
        ]
    )

    let result = try validateUIMessages([message])

    #expect(result == [message])
    #expect(safeValidateUIMessages([message]).isValid)
}

@Test func aiValidateUIMessagesAcceptsCustomAssistantPartLikeUpstream() throws {
    let custom: JSONValue = [
        "kind": "test-provider.compaction"
    ]
    let providerMetadata: [String: JSONValue] = [
        "openai": [
            "itemId": "cmp_123"
        ]
    ]
    let message = AIUIMessage(
        id: "1",
        role: .assistant,
        parts: [
            .custom(custom, providerMetadata: providerMetadata)
        ]
    )

    let result = try validateUIMessages([message])

    #expect(result == [message])
    let safeResult = safeValidateUIMessages([message])
    #expect(safeResult.isValid)
    #expect(safeResult.messages == [message])
    #expect(safeResult.issues.isEmpty)
}

@Test func aiValidateUIMessagesAcceptsCustomAssistantPartWithoutProviderMetadataLikeUpstream() throws {
    let message = AIUIMessage(
        id: "1",
        role: .assistant,
        parts: [
            .custom(["kind": "openai.compaction"])
        ]
    )

    let result = try validateUIMessages([message])

    #expect(result == [message])
    #expect(safeValidateUIMessages([message]).isValid)
}

@Test func aiValidateUIMessagesAcceptsReasoningPartLikeUpstream() throws {
    let message = AIUIMessage(
        id: "1",
        role: .assistant,
        parts: [
            .reasoning(AIUIReasoningPart(text: "Hello, world!"))
        ]
    )

    let result = try validateUIMessages([message])

    #expect(result == [message])
    #expect(safeValidateUIMessages([message]).isValid)
}

@Test func aiValidateUIMessagesAcceptsSourceURLPartLikeUpstream() throws {
    let source = AISource(
        id: "1",
        sourceType: "url",
        url: "https://example.com",
        title: "Example"
    )
    let message = AIUIMessage(
        id: "1",
        role: .assistant,
        parts: [.source(source)]
    )

    let result = try validateUIMessages([message])

    #expect(result == [message])
    #expect(safeValidateUIMessages([message]).isValid)
}

@Test func aiValidateUIMessagesAcceptsSourceDocumentPartLikeUpstream() throws {
    let source = AISource(
        id: "1",
        sourceType: "document",
        title: "Example",
        mediaType: "text/plain",
        filename: "example.txt"
    )
    let message = AIUIMessage(
        id: "1",
        role: .assistant,
        parts: [.source(source)]
    )

    let result = try validateUIMessages([message])

    #expect(result == [message])
    #expect(safeValidateUIMessages([message]).isValid)
}

@Test func aiValidateUIMessagesAcceptsFilePartLikeUpstream() throws {
    let file = AIStreamFile(
        mediaType: "text/plain",
        url: "https://example.com"
    )
    let message = AIUIMessage(
        id: "1",
        role: .assistant,
        parts: [.file(file)]
    )

    let result = try validateUIMessages([message])

    #expect(result == [message])
    #expect(safeValidateUIMessages([message]).isValid)
}

@Test func aiValidateUIMessagesPreservesProviderReferenceOnFilePartLikeUpstream() throws {
    let file = AIStreamFile(
        mediaType: "application/pdf",
        url: "data:application/pdf;base64,abc",
        filename: "document.pdf",
        providerReference: ["openai": "file-abc123"]
    )
    let message = AIUIMessage(
        id: "1",
        role: .assistant,
        parts: [.file(file)]
    )

    let result = try validateUIMessages([message])

    #expect(result == [message])
    #expect(safeValidateUIMessages([message]).messages.first?.parts == [.file(file)])
}

@Test func aiValidateUIMessagesAcceptsDataPartsLikeUpstream() throws {
    let message = AIUIMessage(
        id: "1",
        role: .assistant,
        parts: [
            .data(AIUIDataPart(id: "foo", value: ["foo": "bar"])),
            .data(AIUIDataPart(id: "bar", value: ["bar": 123]))
        ]
    )

    let result = try validateUIMessages([message])

    #expect(result == [message])
    #expect(safeValidateUIMessages([message]).isValid)
}
