import Foundation
import Testing
@testable import SwiftAISDK

@Test func openResponsesStrictInputUsesEasyMessageWithoutSyntheticID() throws {
    let prepared = openResponsesInput(
        from: [.assistant("Hello from assistant")],
        providerID: "test-provider.responses",
        providerOptionsName: "test-provider",
        strictResponseInput: true
    )

    #expect(prepared.input == [[
        "type": "message",
        "role": "assistant",
        "content": "Hello from assistant"
    ]])
}

@Test func openResponsesStrictInputPreservesGenuineCompletedItemID() throws {
    let message = AIMessage(role: .assistant, content: [
        .text("Hello from assistant", providerMetadata: [
            "test-provider": ["itemId": "msg_123"]
        ])
    ])
    let prepared = openResponsesInput(
        from: [message],
        providerID: "test-provider.responses",
        providerOptionsName: "test-provider",
        strictResponseInput: true
    )

    #expect(prepared.input == [[
        "id": "msg_123",
        "type": "message",
        "status": "completed",
        "role": "assistant",
        "content": [[
            "type": "output_text",
            "text": "Hello from assistant",
            "annotations": [],
            "logprobs": []
        ]]
    ]])
}

@Test func openResponsesProviderPropagatesStrictInputSetting() async throws {
    let transport = RecordingTransport(response: jsonResponse(
        #"{"id":"resp-1","status":"completed","output_text":"ok"}"#
    ))
    let provider = try AIProviders.openResponses(
        name: "test-provider",
        url: "https://responses.example.com/v1/responses",
        settings: ProviderSettings(
            apiKey: "test-key",
            transport: transport,
            strictResponseInput: true
        )
    )

    _ = try await provider.languageModel("model").generate(
        LanguageModelRequest(messages: [.assistant("Prior answer")])
    )

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["input"]?[0] == [
        "type": "message",
        "role": "assistant",
        "content": "Prior answer"
    ])
}

@Test func generateTextRejectsRequiredToolChoiceWithoutMatchingCall() async throws {
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "No tool call.",
        content: [.reasoning("I will not call it."), .text("No tool call.")],
        finishReason: "stop",
        rawValue: .object([:])
    ))
    let tool = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": [:]]
    ) { _ in ["ok": true] }

    do {
        _ = try await AI.generateText(
            model: model,
            request: LanguageModelRequest(
                messages: [.user("Look it up")],
                toolChoice: "required"
            ),
            executableTools: [tool],
            maxSteps: 1
        )
        Issue.record("Expected required tool choice to be enforced.")
    } catch let error as AIToolChoiceViolationError {
        #expect(error.toolChoice["type"]?.stringValue == "required")
        #expect(error.finishReason == "stop")
        #expect(error.providerID == "mock")
        #expect(error.modelID == "mock-language")
        #expect(error.content == [.reasoning("I will not call it."), .text("No tool call.")])
    }
}

@Test func generateTextRejectsDifferentForcedToolCall() async throws {
    let wrongCall = AIToolCall(id: "call-1", name: "other", arguments: "{}")
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "",
        finishReason: "tool-calls",
        toolCalls: [wrongCall],
        rawValue: .object([:])
    ))
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": [:]]
    ) { _ in ["ok": true] }
    let other = AITool(
        name: "other",
        parameters: ["type": "object", "properties": [:]]
    ) { _ in ["ok": true] }

    do {
        _ = try await AI.generateText(
            model: model,
            request: LanguageModelRequest(
                messages: [.user("Look it up")],
                toolChoice: ["type": "tool", "toolName": "lookup"]
            ),
            executableTools: [lookup, other],
            maxSteps: 1
        )
        Issue.record("Expected forced tool name to be enforced.")
    } catch let error as AIToolChoiceViolationError {
        #expect(error.description.contains("required tool 'lookup'"))
        #expect(error.content.contains(.toolCall(wrongCall)))
    }
}
