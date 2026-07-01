import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiGenerateTextPassesHeadersToModelLikeUpstream() async throws {
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "Hello, world!",
        content: [.text("Hello, world!")],
        rawValue: .object([:])
    ))

    let result = try await AI.generateText(
        model: model,
        prompt: "test-input",
        headers: ["custom-request-header": "request-header-value"]
    )

    #expect(result.text == "Hello, world!")
    #expect(model.requests.first?.headers["custom-request-header"] == "request-header-value")
}

@Test func aiGenerateTextPassesProviderOptionsToModelLikeUpstream() async throws {
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "provider metadata test",
        content: [.text("provider metadata test")],
        rawValue: .object([:])
    ))

    let result = try await AI.generateText(
        model: model,
        prompt: "test-input",
        providerOptions: ["aProvider": ["someKey": "someValue"]]
    )

    #expect(result.text == "provider metadata test")
    #expect(model.requests.first?.providerOptions == ["aProvider": ["someKey": "someValue"]])
}

@Test func aiGenerateTextPassesReasoningToModelLikeUpstream() async throws {
    let highModel = MockLanguageModel(result: TextGenerationResult(text: "test", rawValue: .object([:])))
    _ = try await AI.generateText(
        model: highModel,
        prompt: "test-input",
        reasoning: "high"
    )

    let providerDefaultModel = MockLanguageModel(result: TextGenerationResult(text: "test", rawValue: .object([:])))
    _ = try await AI.generateText(
        model: providerDefaultModel,
        prompt: "test-input",
        reasoning: "provider-default"
    )

    #expect(highModel.requests.first?.reasoning == "high")
    #expect(providerDefaultModel.requests.first?.reasoning == "provider-default")
}

@Test func aiGenerateTextForwardsAbortSignalToToolExecutionLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            content: [.toolCall(toolCall)],
            finishReason: "tool-calls",
            rawValue: .object(["step": 1])
        ),
        TextGenerationResult(
            text: "Done.",
            content: [.text("Done.")],
            finishReason: "stop",
            rawValue: .object(["step": 2])
        )
    ])
    let abortController = AIAbortController()
    let capture = ToolExecutionContextCapture()
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ],
        executeWithContext: { input, context in
            await capture.record(arguments: input, context: context)
            return "tool result"
        },
        execute: { _ in
            Issue.record("Expected contextual tool execution.")
            return "unused"
        }
    )

    _ = try await AI.generateText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 2,
        abortSignal: abortController.signal
    )

    let snapshot = await capture.snapshot()
    #expect(snapshot.arguments == ["value": "value"])
    #expect(snapshot.context?.toolCallID == "call-1")
    #expect(snapshot.context?.messages == [.user("test-input")])
    #expect(snapshot.context?.abortSignal === abortController.signal)
}

@Test func aiGenerateTextInvokesToolInputAvailableCallbackLikeUpstream() async throws {
    let recorder = GenerateToolInputAvailableRecorder()
    let abortController = AIAbortController()
    let toolCall = AIToolCall(id: "call-1", name: "test-tool", arguments: #"{"value":"value"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            content: [.toolCall(toolCall)],
            finishReason: "tool-calls",
            rawValue: .object(["step": 1])
        ),
        TextGenerationResult(
            text: "Done.",
            content: [.text("Done.")],
            finishReason: "stop",
            rawValue: .object(["step": 2])
        )
    ])
    let tool = AITool(
        name: "test-tool",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"],
            "additionalProperties": false
        ],
        onInputAvailable: { context in
            await recorder.record(
                toolCallID: context.toolCallID,
                input: context.input,
                messages: context.messages,
                abortSignalMatches: context.abortSignal === abortController.signal
            )
        },
        execute: { _ in
            "tool result"
        }
    )

    _ = try await AI.generateText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 2,
        toolChoice: "required",
        abortSignal: abortController.signal
    )

    #expect(await recorder.events() == [
        GenerateToolInputAvailableEvent(
            toolCallID: "call-1",
            input: ["value": "value"],
            messages: [.user("test-input")],
            abortSignalMatches: true
        )
    ])
}

