import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiGenerateTextStopWhenStopsAfterToolStepLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            content: [.toolCall(toolCall)],
            finishReason: "tool-calls",
            usage: TokenUsage(totalTokens: 15),
            rawValue: .object(["step": 1])
        ),
        TextGenerationResult(
            text: "This should not be generated.",
            content: [.text("This should not be generated.")],
            finishReason: "stop",
            usage: TokenUsage(totalTokens: 13),
            rawValue: .object(["step": 2])
        )
    ])
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { _ in
        "result1"
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 3,
        stopWhen: [.isStepCount(1)]
    )

    #expect(model.requests.count == 1)
    #expect(result.text == "")
    #expect(result.steps.count == 1)
    #expect(result.finalStep?.toolCalls == [toolCall])
    #expect(result.toolResults == [
        AIToolResult(toolCallID: "call-1", toolName: "tool1", result: "result1")
    ])
    #expect(result.content == [
        .toolCall(toolCall),
        .toolResult(AIToolResult(toolCallID: "call-1", toolName: "tool1", result: "result1"))
    ])
}

@Test func aiGenerateTextCallsStopConditionsWithCurrentStepsLikeUpstream() async throws {
    let capture = StopConditionCapture()
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            content: [.toolCall(toolCall)],
            finishReason: "tool-calls",
            rawValue: .object(["step": 1])
        ),
        TextGenerationResult(
            text: "This should not be generated.",
            content: [.text("This should not be generated.")],
            finishReason: "stop",
            rawValue: .object(["step": 2])
        )
    ])
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { _ in
        "result1"
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        stopWhen: [
            AIStopCondition { context in
                await capture.record(number: 0, context: context)
                return false
            },
            AIStopCondition { context in
                await capture.record(number: 1, context: context)
                return true
            }
        ]
    )

    #expect(result.steps.count == 1)
    #expect(await capture.numbers() == [0, 1])
    #expect(await capture.stepCounts() == [1, 1])
    #expect(await capture.toolCallIDs() == [["call-1"], ["call-1"]])
    #expect(await capture.toolResultIDs() == [["call-1"], ["call-1"]])
}

@Test func aiGenerateTextLoopFinishedConditionCompletesToolLoopLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            content: [.toolCall(toolCall)],
            finishReason: "tool-calls",
            rawValue: .object(["step": 1])
        ),
        TextGenerationResult(
            text: "Done!",
            content: [.text("Done!")],
            finishReason: "stop",
            rawValue: .object(["step": 2])
        )
    ])
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { _ in
        "result1"
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        stopWhen: [.isLoopFinished()]
    )

    #expect(result.text == "Done!")
    #expect(result.steps.count == 2)
    #expect(model.requests.count == 2)
}

