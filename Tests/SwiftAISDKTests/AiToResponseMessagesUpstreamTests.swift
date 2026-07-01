import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiToResponseMessagesConvertsTextToAssistantMessageLikeUpstream() async throws {
    let messages = try await toResponseMessages(content: [
        .text("Hello, world!")
    ])

    #expect(messages == [
        AIMessage(role: .assistant, content: [.text("Hello, world!")])
    ])
}

@Test func aiToResponseMessagesSkipsEmptyTextAndEmptyContentLikeUpstream() async throws {
    let emptyMessages = try await toResponseMessages(content: [])
    let emptyTextMessages = try await toResponseMessages(content: [.text("")])

    #expect(emptyMessages == [])
    #expect(emptyTextMessages == [])
}

@Test func aiToResponseMessagesSeparatesToolResultsIntoToolMessageLikeUpstream() async throws {
    let call = responseMessageToolCall(arguments: #"{"city":"San Francisco"}"#)
    let result = AIToolResult(
        toolCallID: call.id,
        toolName: call.name,
        result: ["weather": "sunny"],
        providerMetadata: ["test": ["value": "result-metadata"]]
    )

    let messages = try await toResponseMessages(content: [
        .text("I'll check."),
        .toolCall(call),
        .toolResult(result)
    ])

    #expect(messages == [
        AIMessage(role: .assistant, content: [
            .text("I'll check."),
            .toolCall(call)
        ]),
        AIMessage(role: .tool, content: [
            .toolResult(result)
        ])
    ])
}

@Test func aiToResponseMessagesKeepsProviderExecutedToolResultsInAssistantMessageLikeUpstream() async throws {
    let call = responseMessageToolCall(
        arguments: #"{"query":"Swift"}"#,
        providerExecuted: true,
        providerMetadata: ["provider": ["itemId": "item-1"]]
    )
    let result = AIToolResult(
        toolCallID: call.id,
        toolName: call.name,
        result: ["items": ["one", "two"]]
    )

    let messages = try await toResponseMessages(content: [
        .toolCall(call),
        .toolResult(result),
        .text("Done.")
    ])

    #expect(messages == [
        AIMessage(role: .assistant, content: [
            .toolCall(call),
            .toolResult(result),
            .text("Done.")
        ])
    ])
}

@Test func aiToResponseMessagesPreservesReasoningCustomAndFilesInOrderLikeUpstream() async throws {
    let image = AIStreamFile(
        id: "file-1",
        mediaType: "image/png",
        data: Data([0x01, 0x02]),
        filename: "image.png",
        providerMetadata: ["openai": ["fileId": "file-provider-1"]]
    )
    let reasoningFile = AIStreamFile(
        id: "reasoning-file-1",
        mediaType: "application/pdf",
        data: Data([0x03, 0x04]),
        filename: "reasoning.pdf",
        providerMetadata: ["anthropic": ["signature": "sig-1"]]
    )
    let parts: [AIContentPart] = [
        .reasoning("I should inspect the input.", providerMetadata: ["test": ["reasoning": true]]),
        .file(mimeType: image.mediaType, data: image.data ?? Data(), filename: image.filename, providerMetadata: image.providerMetadata),
        .reasoningFile(reasoningFile),
        .custom(["kind": "trace", "value": 1], providerMetadata: ["test": ["custom": true]]),
        .text("Final answer.", providerMetadata: ["test": ["text": true]])
    ]

    let messages = try await toResponseMessages(content: parts)

    #expect(messages == [
        AIMessage(role: .assistant, content: parts)
    ])
}

@Test func aiToResponseMessagesAppliesToolModelOutputLikeUpstream() async throws {
    let call = responseMessageToolCall(arguments: #"{"number":42}"#)
    let result = AIToolResult(
        toolCallID: call.id,
        toolName: call.name,
        result: ["processed": 42]
    )
    let tool = AITool(
        name: call.name,
        parameters: responseMessageObjectSchema,
        toModelOutput: { context in
            [
                "type": "json",
                "value": [
                    "toolCallID": .string(context.toolCallID),
                    "input": context.input,
                    "output": context.output
                ]
            ]
        },
        execute: { _ in .null }
    )

    let messages = try await toResponseMessages(
        content: [.toolCall(call), .toolResult(result)],
        toolsByName: [tool.name: tool]
    )

    guard messages.count == 2,
          messages[1].content.count == 1,
          case let .toolResult(converted) = messages[1].content[0] else {
        Issue.record("Expected a converted tool result in a tool message.")
        return
    }
    #expect(converted.modelOutput?["type"]?.stringValue == "json")
    #expect(converted.modelOutput?["value"]?["toolCallID"]?.stringValue == call.id)
    #expect(converted.modelOutput?["value"]?["input"]?["number"]?.intValue == 42)
    #expect(converted.modelOutput?["value"]?["output"]?["processed"]?.intValue == 42)
}

@Test func aiToResponseMessagesAddsExecutionDeniedResultForDeniedApprovalLikeUpstream() async throws {
    let call = responseMessageToolCall(arguments: #"{"path":"/tmp/file"}"#)
    let request = AIToolApprovalRequest(
        id: "approval-1",
        toolName: call.name,
        arguments: call.arguments,
        toolCallID: call.id,
        providerMetadata: ["test": ["request": true]]
    )
    let response = AIToolApprovalResponse(
        id: request.id,
        approved: false,
        reason: "User denied",
        providerMetadata: ["test": ["response": true]]
    )

    let messages = try await toResponseMessages(content: [
        .toolCall(call),
        .toolApprovalRequest(request),
        .toolApprovalResponse(response)
    ])

    #expect(messages.count == 2)
    #expect(messages.first == AIMessage(role: .assistant, content: [
        .toolCall(call),
        .toolApprovalRequest(request)
    ]))
    guard messages.count == 2,
          messages[1].content.count == 2,
          case let .toolApprovalResponse(actualResponse) = messages[1].content[0],
          case let .toolResult(deniedResult) = messages[1].content[1] else {
        Issue.record("Expected approval response followed by execution-denied tool result.")
        return
    }
    #expect(actualResponse == response)
    #expect(deniedResult.toolCallID == call.id)
    #expect(deniedResult.toolName == call.name)
    #expect(deniedResult.result["type"]?.stringValue == "execution-denied")
    #expect(deniedResult.result["reason"]?.stringValue == "User denied")
    #expect(deniedResult.providerMetadata == response.providerMetadata)
}

@Test func aiToResponseMessagesSanitizesInvalidDynamicToolCallInputLikeUpstream() async throws {
    let invalidCall = responseMessageToolCall(
        arguments: "{ city: San Francisco, }",
        dynamic: true
    )
    let validCall = responseMessageToolCall(
        id: "call-valid",
        arguments: #"{"city":"Paris"}"#,
        dynamic: true
    )

    let messages = try await toResponseMessages(content: [
        .toolCall(invalidCall),
        .toolCall(validCall)
    ])

    guard messages.count == 1,
          messages[0].content.count == 2,
          case let .toolCall(sanitizedInvalidCall) = messages[0].content[0],
          case let .toolCall(preservedValidCall) = messages[0].content[1] else {
        Issue.record("Expected two tool calls in the assistant message.")
        return
    }
    #expect(sanitizedInvalidCall.arguments == "{}")
    #expect(sanitizedInvalidCall.dynamic)
    #expect(preservedValidCall.arguments == validCall.arguments)
}

private let responseMessageObjectSchema: JSONValue = [
    "type": "object",
    "properties": [:],
    "additionalProperties": true
]

private func responseMessageToolCall(
    id: String = "call-1",
    name: String = "weather",
    arguments: String,
    providerExecuted: Bool = false,
    dynamic: Bool = false,
    providerMetadata: [String: JSONValue] = [:]
) -> AIToolCall {
    AIToolCall(
        id: id,
        name: name,
        arguments: arguments,
        providerExecuted: providerExecuted,
        dynamic: dynamic,
        providerMetadata: providerMetadata
    )
}
