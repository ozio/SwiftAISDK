import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiGenerateTextValidatesToolArgumentsAgainstSchema() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"city":42}"#)
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "",
        finishReason: "tool-calls",
        toolCalls: [toolCall],
        rawValue: .object([:])
    ))
    let capture = ToolCapture()
    let lookup = AITool(
        name: "lookup",
        parameters: [
            "type": "object",
            "properties": ["city": ["type": "string"]],
            "required": ["city"],
            "additionalProperties": false
        ]
    ) { arguments in
        await capture.record(arguments)
        return ["city": arguments["city"] ?? .null]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 1
    )

    #expect(await capture.value() == nil)
    #expect(model.requests.count == 1)
    let toolResult = try #require(result.toolResults.first)
    #expect(toolResult.toolName == "lookup")
    #expect(toolResult.toolCallID == "call-1")
    #expect(toolResult.isError)
    #expect(toolResult.result["type"]?.stringValue == "error-text")
    #expect(toolResult.result["value"]?.stringValue?.contains("Invalid input for tool lookup") == true)
    #expect(toolResult.result["value"]?.stringValue?.contains("$.city") == true)
}
@Test func aiGenerateTextReturnsTypedNoSuchToolErrorResult() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "missing", arguments: #"{}"#)
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "",
        finishReason: "tool-calls",
        toolCalls: [toolCall],
        rawValue: .object([:])
    ))
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object"]
    ) { _ in
        ["ok": true]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Use a tool.",
        executableTools: [lookup],
        maxSteps: 1
    )

    let toolResult = try #require(result.toolResults.first)
    #expect(toolResult.toolName == "missing")
    #expect(toolResult.toolCallID == "call-1")
    #expect(toolResult.isError)
    #expect(toolResult.result["type"]?.stringValue == "error-text")
    #expect(toolResult.result["value"]?.stringValue?.contains("No such tool: missing") == true)
    #expect(toolResult.result["value"]?.stringValue?.contains("lookup") == true)
}

