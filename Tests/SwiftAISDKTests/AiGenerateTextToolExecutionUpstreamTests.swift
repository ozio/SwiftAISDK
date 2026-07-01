import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiGenerateTextKeepsProviderExecutedToolCallsAndResultsLikeUpstream() async throws {
    let call1 = AIToolCall(
        id: "call-1",
        name: "web_search",
        arguments: #"{"value":"value"}"#,
        providerExecuted: true
    )
    let result1 = AIToolResult(
        toolCallID: "call-1",
        toolName: "web_search",
        result: #"{"value":"result1"}"#,
        providerMetadata: ["openai": ["itemId": "tool-result-1"]]
    )
    let call2 = AIToolCall(
        id: "call-2",
        name: "web_search",
        arguments: #"{"value":"value"}"#,
        providerExecuted: true
    )
    let result2 = AIToolResult(
        toolCallID: "call-2",
        toolName: "web_search",
        result: "ERROR",
        isError: true,
        providerMetadata: ["openai": ["itemId": "tool-result-2"]]
    )
    let content: [AIResultContentPart] = [
        .toolCall(call1),
        .toolResult(result1),
        .toolCall(call2),
        .toolResult(result2)
    ]
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "",
        content: content,
        finishReason: "stop",
        rawValue: .object([:])
    ))
    let providerTool = AITool(name: "web_search", parameters: [
        "type": "object",
        "properties": ["value": ["type": "string"]],
        "required": ["value"]
    ]) { _ in
        Issue.record("Provider-executed tool calls must not execute locally.")
        return "unused"
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "test-input",
        executableTools: [providerTool],
        maxSteps: 4
    )

    #expect(result.content == content)
    #expect(result.toolCalls == [call1, call2])
    #expect(result.toolResults == [result1, result2])
    #expect(result.steps.count == 1)
    #expect(result.finalStep?.content == content)
}

@Test func aiGenerateTextReturnsToolExecutionErrorsAsToolResultsLikeUpstream() async throws {
    struct ToolFailure: Error, CustomStringConvertible {
        var description: String { "test error" }
    }

    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let errorResult = AIToolResult(
        toolCallID: "call-1",
        toolName: "tool1",
        result: [
            "type": "error-text",
            "value": "Error: test error"
        ],
        isError: true
    )
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "",
        content: [.toolCall(toolCall)],
        finishReason: "tool-calls",
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
        throw ToolFailure()
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 1
    )

    #expect(result.content == [
        .toolCall(toolCall),
        .toolResult(errorResult)
    ])
    #expect(result.toolResults == [errorResult])
    #expect(result.responseMessages == [
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        AIMessage(role: .tool, content: [.toolResult(errorResult)])
    ])
}

@Test func aiGenerateTextReturnsInvalidToolCallErrorsAsToolResultsLikeUpstream() async throws {
    let toolCall = AIToolCall(
        id: "call-1",
        name: "cityAttractions",
        arguments: #"{"cities":"San Francisco"}"#
    )
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "",
        content: [.toolCall(toolCall)],
        finishReason: "tool-calls",
        rawValue: .object([:])
    ))
    let cityAttractions = AITool(
        name: "cityAttractions",
        parameters: [
            "type": "object",
            "properties": ["city": ["type": "string"]],
            "required": ["city"],
            "additionalProperties": false
        ]
    ) { _ in
        Issue.record("Invalid tool calls must not execute.")
        return "unused"
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "What are the tourist attractions in San Francisco?",
        executableTools: [cityAttractions],
        maxSteps: 1
    )

    let errorResult = try #require(result.toolResults.first)
    #expect(errorResult.toolCallID == "call-1")
    #expect(errorResult.toolName == "cityAttractions")
    #expect(errorResult.isError)
    #expect(errorResult.result["type"]?.stringValue == "error-text")
    #expect(errorResult.result["value"]?.stringValue?.contains("Invalid input for tool cityAttractions") == true)
    #expect(errorResult.result["value"]?.stringValue?.contains("$.city") == true)
    #expect(result.content == [.toolCall(toolCall), .toolResult(errorResult)])
    #expect(result.responseMessages == [
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        AIMessage(role: .tool, content: [.toolResult(errorResult)])
    ])
}

