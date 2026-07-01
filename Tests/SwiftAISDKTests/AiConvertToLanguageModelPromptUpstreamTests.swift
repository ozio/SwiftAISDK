import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiConvertPromptPrependsSystemInstructionsLikeUpstream() throws {
    let result = try convertToLanguageModelPrompt(StandardizedPrompt(
        instructions: [
            AIMessage(
                role: .system,
                content: [.text("INSTRUCTIONS")],
                providerMetadata: ["test": ["value": "test"]]
            ),
            .system("INSTRUCTIONS 2")
        ],
        messages: [.user("Hello, world!")]
    ))

    #expect(result.map(\.role) == [.system, .system, .user])
    #expect(result[0].combinedText == "INSTRUCTIONS")
    #expect(result[0].providerMetadata["test"]?["value"]?.stringValue == "test")
    #expect(result[1].combinedText == "INSTRUCTIONS 2")
    #expect(result[2].content == [.text("Hello, world!")])
}

@Test func aiConvertLanguageModelMessageFiltersUserEmptyTextPartsLikeUpstream() {
    let message = AIMessage(role: .user, content: [
        .text(""),
        .text("hello, world!", providerMetadata: ["test": ["key": "value"]])
    ])

    let result = convertToLanguageModelMessage(message)

    #expect(result.role == .user)
    #expect(result.content.count == 1)
    #expect(result.content[0].text == "hello, world!")
    #expect(result.content[0].providerMetadata["test"]?["key"]?.stringValue == "value")
}

@Test func aiConvertLanguageModelMessagePreservesTypedUserMediaPartsLikeUpstream() {
    let imageData = Data([0, 1, 2, 3])
    let fileData = Data("Hello".utf8)
    let providerReference: AIProviderReference = [
        "openai": "file-abc123",
        "anthropic": "file-xyz789"
    ]
    let message = AIMessage(role: .user, content: [
        .imageURL("https://example.com/image.jpg"),
        .data(mimeType: "image/png", data: imageData),
        .file(mimeType: "text/plain", data: fileData, filename: "hello.txt"),
        .providerReference(mimeType: "application/pdf", reference: providerReference)
    ])

    let result = convertToLanguageModelMessage(message)

    #expect(result == message)
    #expect(result.content[1].filePayload?.mimeType == "image/png")
    #expect(result.content[2].filePayload?.filename == "hello.txt")
    guard case let .providerReference(mimeType, reference, _, _) = result.content[3] else {
        Issue.record("Expected provider reference file part.")
        return
    }
    #expect(mimeType == "application/pdf")
    #expect(reference == providerReference)
}

@Test func aiConvertPromptPreservesUserMessageProviderOptionsLikeUpstream() throws {
    let providerMetadata: [String: JSONValue] = [
        "test-provider": [
            "key-a": "test-value-1",
            "key-b": "test-value-2"
        ]
    ]

    let result = try convertToLanguageModelPrompt(StandardizedPrompt(messages: [
        AIMessage(
            role: .user,
            content: [.text("hello, world!")],
            providerMetadata: providerMetadata
        )
    ]))

    #expect(result.count == 1)
    #expect(result[0].role == .user)
    #expect(result[0].content == [.text("hello, world!")])
    #expect(result[0].providerMetadata == providerMetadata)
}

@Test func aiConvertLanguageModelMessageFiltersAssistantEmptyTextAndApprovalRequestsLikeUpstream() {
    let toolCall = AIToolCall(
        id: "toolCallId",
        name: "toolName",
        arguments: #"{}"#,
        providerExecuted: true,
        providerMetadata: ["test": ["key": "value"]]
    )
    let approvalRequest = AIToolApprovalRequest(
        id: "approvalId",
        toolName: "toolName",
        arguments: #"{}"#,
        toolCallID: "toolCallId"
    )
    let message = AIMessage(role: .assistant, content: [
        .text(""),
        .text("", providerMetadata: ["test": ["empty": true]]),
        .toolCall(toolCall),
        .toolApprovalRequest(approvalRequest)
    ])

    let result = convertToLanguageModelMessage(message)

    #expect(result.content == [
        .text("", providerMetadata: ["test": ["empty": true]]),
        .toolCall(toolCall)
    ])
    #expect(result.content[1].providerMetadata["test"]?["key"]?.stringValue == "value")
}

@Test func aiConvertLanguageModelMessagePreservesAssistantReasoningAndFilePartsLikeUpstream() {
    let providerReference: AIProviderReference = ["openai": "file-abc123"]
    let message = AIMessage(
        role: .assistant,
        content: [
            .providerReference(
                mimeType: "application/pdf",
                reference: providerReference,
                providerMetadata: ["test": ["file": true]]
            ),
            .text("hello, world!")
        ],
        reasoning: "I'm thinking\nmore thinking",
        providerMetadata: ["test": ["redacted": true]]
    )

    let result = convertToLanguageModelMessage(message)

    #expect(result == message)
    #expect(result.reasoning == "I'm thinking\nmore thinking")
    #expect(result.providerMetadata["test"]?["redacted"]?.boolValue == true)
    #expect(result.content[0].providerMetadata["test"]?["file"]?.boolValue == true)
}

@Test func aiConvertLanguageModelMessagePreservesAssistantFileDataLikeUpstream() {
    let fileData = Data("test".utf8)
    let message = AIMessage(role: .assistant, content: [
        .file(
            mimeType: "application/pdf",
            data: fileData,
            filename: "test-document.pdf",
            providerMetadata: [
                "test-provider": [
                    "key-a": "test-value-1",
                    "key-b": "test-value-2"
                ]
            ]
        )
    ])

    let result = convertToLanguageModelMessage(message)

    #expect(result == message)
    #expect(result.content[0].filePayload?.mimeType == "application/pdf")
    #expect(result.content[0].filePayload?.data == fileData)
    #expect(result.content[0].filePayload?.filename == "test-document.pdf")
    #expect(result.content[0].providerMetadata["test-provider"]?["key-a"]?.stringValue == "test-value-1")
    #expect(result.content[0].providerMetadata["test-provider"]?["key-b"]?.stringValue == "test-value-2")
}

@Test func aiConvertLanguageModelMessagePreservesAssistantToolMetadataLikeUpstream() {
    let toolCall = AIToolCall(
        id: "toolCallId",
        name: "toolName",
        arguments: #"{}"#,
        providerExecuted: true,
        providerMetadata: ["test": ["key-a": "test-value-1"]]
    )
    let toolResult = AIToolResult(
        toolCallID: "toolCallId",
        toolName: "toolName",
        result: ["some": "result"],
        providerMetadata: ["test": ["key-b": "test-value-2"]]
    )
    let message = AIMessage(role: .assistant, content: [
        .toolCall(toolCall),
        .toolResult(toolResult)
    ])

    let result = convertToLanguageModelMessage(message)

    #expect(result.content == [.toolCall(toolCall), .toolResult(toolResult)])
    guard case let .toolCall(convertedCall) = result.content[0],
          case let .toolResult(convertedResult) = result.content[1] else {
        Issue.record("Expected assistant tool call and tool result.")
        return
    }
    #expect(convertedCall.providerExecuted == true)
    #expect(convertedCall.providerMetadata["test"]?["key-a"]?.stringValue == "test-value-1")
    #expect(convertedResult.providerMetadata["test"]?["key-b"]?.stringValue == "test-value-2")
}

@Test func aiConvertLanguageModelMessagePreservesToolResultMetadataLikeUpstream() {
    let toolResult = AIToolResult(
        toolCallID: "toolCallId",
        toolName: "toolName",
        result: ["some": "result"],
        isError: true,
        providerMetadata: ["test": ["key": "value"]]
    )
    let message = AIMessage.toolResult(toolResult)

    let result = convertToLanguageModelMessage(message)

    #expect(result.role == .tool)
    #expect(result.content == [.toolResult(toolResult)])
    guard case let .toolResult(convertedResult) = result.content.first else {
        Issue.record("Expected tool result.")
        return
    }
    #expect(convertedResult.isError == true)
    #expect(convertedResult.providerMetadata["test"]?["key"]?.stringValue == "value")
}

@Test func aiConvertLanguageModelMessagePreservesNewToolResultFileContentShapeLikeUpstream() {
    let modelOutput: JSONValue = [
        "type": "content",
        "value": [
            [
                "type": "file",
                "data": ["type": "data", "data": "dGVzdA=="],
                "mediaType": "image/png",
                "filename": "image.png"
            ],
            [
                "type": "file",
                "data": ["type": "url", "url": "https://example.com/image.png"],
                "mediaType": "image/png"
            ],
            [
                "type": "file",
                "data": [
                    "type": "reference",
                    "reference": ["test-provider": "fileId"]
                ],
                "mediaType": "application/pdf"
            ],
            [
                "type": "file",
                "data": ["type": "text", "text": "inline text"],
                "mediaType": "text/plain"
            ]
        ]
    ]
    let toolResult = AIToolResult(
        toolCallID: "toolCallId",
        toolName: "toolName",
        result: ["some": "result"],
        modelOutput: modelOutput
    )
    let message = AIMessage.toolResult(toolResult)

    let result = convertToLanguageModelMessage(message)

    #expect(result.content == [.toolResult(toolResult)])
    guard case let .toolResult(convertedResult) = result.content.first else {
        Issue.record("Expected tool result.")
        return
    }
    #expect(convertedResult.modelOutput == modelOutput)
}

@Test func aiConvertPromptCombinesConsecutiveToolMessagesAndFiltersApprovalResponsesLikeUpstream() throws {
    let toolCall = AIToolCall(id: "toolCallId", name: "toolName", arguments: #"{}"#)
    let toolResultA = AIToolResult(
        toolCallID: "toolCallId",
        toolName: "toolName",
        result: ["some": "result"]
    )
    let toolResultB = AIToolResult(
        toolCallID: "providerToolCallId",
        toolName: "providerTool",
        result: ["some": "provider-result"]
    )
    let localApprovalResponse = AIToolApprovalResponse(id: "approvalId", approved: true)
    let providerApprovalResponse = AIToolApprovalResponse(
        id: "providerApprovalId",
        approved: true,
        providerExecuted: true
    )

    let result = try convertToLanguageModelPrompt(StandardizedPrompt(
        messages: [
            AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
            .toolResponses(approvalResponses: [localApprovalResponse], toolResults: [toolResultA]),
            .toolResponses(approvalResponses: [providerApprovalResponse], toolResults: [toolResultB])
        ]
    ))

    #expect(result.map(\.role) == [.assistant, .tool])
    #expect(result[1].content == [
        .toolResult(toolResultA),
        .toolApprovalResponse(providerApprovalResponse),
        .toolResult(toolResultB)
    ])
}

@Test func aiConvertPromptDropsEmptyToolMessagesLikeUpstream() throws {
    let result = try convertToLanguageModelPrompt(StandardizedPrompt(
        messages: [
            .toolResponses(approvalResponses: [
                AIToolApprovalResponse(id: "approvalId", approved: true)
            ])
        ]
    ))

    #expect(result.isEmpty)
}
