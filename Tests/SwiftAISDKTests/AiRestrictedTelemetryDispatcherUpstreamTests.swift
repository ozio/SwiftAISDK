import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiRestrictedTelemetryExcludesInputAndOutputWhenFlagsAreDisabledLikeSwiftPrivacyGate() async throws {
    let recorder = TelemetryRecorder()
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "redacted",
        finishReason: "stop",
        usage: TokenUsage(totalTokens: 3),
        rawValue: .object([:])
    ))

    let result = try await AI.generateText(
        model: model,
        prompt: "contains sensitive input",
        telemetry: Telemetry.Options(
            includesInput: false,
            includesOutput: false,
            functionID: "unit.restricted",
            metadata: ["requestId": "request-123"],
            integrations: [recorder]
        )
    )
    let events = await recorder.events()

    #expect(result.text == "redacted")
    #expect(events.map(\.kind) == [.start, .end])
    #expect(events.allSatisfy { $0.input == nil })
    #expect(events.allSatisfy { $0.output == nil })
    #expect(events.allSatisfy { $0.includesInput == false })
    #expect(events.allSatisfy { $0.includesOutput == false })
    #expect(events.allSatisfy { $0.functionID == "unit.restricted" })
    #expect(events.allSatisfy { $0.metadata["requestId"] == "request-123" })
}

@Test func aiRestrictedTelemetryAppliesInputAndOutputFlagsToStepAndToolEventsLikeSwiftPrivacyGate() async throws {
    let recorder = TelemetryRecorder()
    let toolCall = AIToolCall(id: "call-1", name: "weather", arguments: #"{"city":"Berlin"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            finishReason: "tool-calls",
            toolCalls: [toolCall],
            rawValue: .object([:])
        ),
        TextGenerationResult(
            text: "sunny",
            finishReason: "stop",
            usage: TokenUsage(totalTokens: 5),
            rawValue: .object([:])
        )
    ])
    let weather = AITool(
        name: "weather",
        parameters: [
            "type": "object",
            "properties": ["city": ["type": "string"]],
            "required": ["city"]
        ]
    ) { input in
        ["city": input["city"] ?? .string("missing"), "forecast": "sunny"]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Weather?",
        executableTools: [weather],
        maxSteps: 2,
        telemetry: Telemetry.Options(
            includesInput: false,
            includesOutput: false,
            functionID: "unit.restricted-tool-loop",
            metadata: ["requestId": "request-123"],
            integrations: [recorder]
        )
    )
    let events = await recorder.events()
    let restrictedEvents = events.filter {
        $0.operationID == "ai.generateText"
            || $0.operationID == "ai.generateText.step"
            || $0.operationID == "ai.generateText.tool"
    }

    #expect(result.text == "sunny")
    #expect(restrictedEvents.contains { $0.kind == .toolStart })
    #expect(restrictedEvents.contains { $0.kind == .toolEnd })
    #expect(restrictedEvents.allSatisfy { $0.input == nil })
    #expect(restrictedEvents.allSatisfy { $0.output == nil })
    #expect(restrictedEvents.allSatisfy { $0.includesInput == false })
    #expect(restrictedEvents.allSatisfy { $0.includesOutput == false })
    #expect(restrictedEvents.allSatisfy { $0.functionID == "unit.restricted-tool-loop" })
    #expect(restrictedEvents.allSatisfy { $0.metadata["requestId"] == "request-123" })
}
