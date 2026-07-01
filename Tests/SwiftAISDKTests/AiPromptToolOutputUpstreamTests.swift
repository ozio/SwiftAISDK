import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiToolModelOutputReceivesContextAndPreservesCustomOutputLikeUpstream() async throws {
    let toolCall = AIToolCall(
        id: "2344",
        name: "process",
        arguments: #"{"number":42}"#
    )
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            finishReason: "tool-calls",
            toolCalls: [toolCall],
            rawValue: .object([:])
        ),
        TextGenerationResult(text: "Done", finishReason: "stop", rawValue: .object([:]))
    ])
    let process = AITool(
        name: "process",
        parameters: [
            "type": "object",
            "properties": ["number": ["type": "number"]]
        ],
        toModelOutput: { context in
            [
                "type": "json",
                "value": [
                    "toolCallID": .string(context.toolCallID),
                    "input": context.input,
                    "output": context.output
                ]
            ]
        }
    ) { arguments in
        [
            "processed": arguments["number"] ?? .null,
            "timestamp": "2023-01-01"
        ]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Process",
        executableTools: [process],
        maxSteps: 2
    )

    let toolResult = try #require(result.toolResults.first)
    #expect(toolResult.result["processed"]?.intValue == 42)
    #expect(toolResult.result["timestamp"]?.stringValue == "2023-01-01")
    #expect(toolResult.modelOutput?["type"]?.stringValue == "json")
    #expect(toolResult.modelOutput?["value"]?["toolCallID"]?.stringValue == "2344")
    #expect(toolResult.modelOutput?["value"]?["input"]?["number"]?.intValue == 42)
    #expect(toolResult.modelOutput?["value"]?["output"]?["processed"]?.intValue == 42)
    #expect(result.steps.first?.toolResults.first?.modelOutput == toolResult.modelOutput)
}

@Test func aiToolExecutionStoresRawJSONResultWhenNoModelOutputHookLikeSwiftRuntime() async throws {
    let calls = [
        AIToolCall(id: "call-object", name: "objectTool", arguments: #"{"ok":true}"#),
        AIToolCall(id: "call-array", name: "arrayTool", arguments: #"{}"#),
        AIToolCall(id: "call-null", name: "nullTool", arguments: #"{}"#)
    ]
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            finishReason: "tool-calls",
            toolCalls: calls,
            rawValue: .object([:])
        ),
        TextGenerationResult(text: "Done", finishReason: "stop", rawValue: .object([:]))
    ])
    let objectTool = AITool(
        name: "objectTool",
        parameters: ["type": "object"]
    ) { arguments in
        ["result": "success", "ok": arguments["ok"] ?? .bool(false)]
    }
    let arrayTool = AITool(
        name: "arrayTool",
        parameters: ["type": "object"]
    ) { _ in
        [1, 2, 3, "test"]
    }
    let nullTool = AITool(
        name: "nullTool",
        parameters: ["type": "object"]
    ) { _ in
        .null
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Run tools",
        executableTools: [objectTool, arrayTool, nullTool],
        maxSteps: 2
    )

    #expect(result.toolResults.map(\.toolName) == ["objectTool", "arrayTool", "nullTool"])
    #expect(result.toolResults[0].result["result"]?.stringValue == "success")
    #expect(result.toolResults[0].result["ok"]?.boolValue == true)
    #expect(result.toolResults[0].modelOutput == nil)
    #expect(result.toolResults[1].result == [1, 2, 3, "test"])
    #expect(result.toolResults[1].modelOutput == nil)
    #expect(result.toolResults[2].result == .null)
    #expect(result.toolResults[2].modelOutput == nil)
}
