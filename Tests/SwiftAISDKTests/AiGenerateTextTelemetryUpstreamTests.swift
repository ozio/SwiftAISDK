import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiGenerateTextStepStartTelemetryReflectsPrepareStepModelAndMessagesLikeUpstream() async throws {
    let recorder = TelemetryRecorder()
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"test"}"#)
    let primaryModel = ConfiguredGenerateTextLanguageModel(
        providerID: "test-provider",
        modelID: "test-model",
        results: [
            TextGenerationResult(
                text: "",
                content: [.toolCall(toolCall)],
                finishReason: "tool-calls",
                rawValue: .object([:])
            )
        ]
    )
    let alternateModel = ConfiguredGenerateTextLanguageModel(
        providerID: "alternate-provider",
        modelID: "alternate-model",
        results: [
            TextGenerationResult(
                text: "Final answer.",
                content: [.text("Final answer.")],
                finishReason: "stop",
                rawValue: .object([:])
            )
        ]
    )
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { input in
        .string("\(input["value"]?.stringValue ?? "")-result")
    }

    let result = try await AI.generateText(
        model: primaryModel,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 2,
        prepareStep: { context in
            guard context.stepNumber == 1 else { return nil }
            return AIPrepareStepResult(model: alternateModel)
        },
        telemetry: Telemetry.Options(functionID: "unit.generateTextStepStart", integrations: [recorder])
    )

    let stepStartEvents = await recorder.events().filter {
        $0.operationID == "ai.generateText.step" && $0.kind == .stepStart
    }
    let secondStepMessages = stepStartEvents[1].input?["request"]?["messages"]?.arrayValue

    #expect(result.text == "Final answer.")
    #expect(stepStartEvents.count == 2)
    #expect(stepStartEvents.map(\.providerID) == ["test-provider", "alternate-provider"])
    #expect(stepStartEvents.map(\.modelID) == ["test-model", "alternate-model"])
    #expect(stepStartEvents.map { $0.input?["stepNumber"]?.intValue } == [0, 1])
    #expect(stepStartEvents[0].input?["request"]?["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "test-input")
    #expect(secondStepMessages?.map { $0["role"]?.stringValue } == ["user", "assistant", "tool"])
    #expect(secondStepMessages?[1]["content"]?[0]?["name"]?.stringValue == "tool1")
    #expect(secondStepMessages?[2]["content"]?[0]?["toolName"]?.stringValue == "tool1")
    #expect(secondStepMessages?[2]["content"]?[0]?["result"]?.stringValue == "test-result")
    #expect(primaryModel.requests.count == 1)
    #expect(alternateModel.requests.count == 1)
}

@Test func aiGenerateTextPrepareStepCanDisableToolsForNextStepLikeUpstreamActiveTools() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            content: [.toolCall(toolCall)],
            finishReason: "tool-calls",
            rawValue: .object([:])
        ),
        TextGenerationResult(
            text: "done",
            content: [.text("done")],
            finishReason: "stop",
            rawValue: .object([:])
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
        .string("result1")
    }

    _ = try await AI.generateText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 2,
        prepareStep: { context in
            guard context.stepNumber == 1 else { return nil }
            return AIPrepareStepResult(executableTools: [])
        }
    )

    #expect(model.requests.count == 2)
    #expect(model.requests[0].tools.keys.sorted() == ["tool1"])
    #expect(model.requests[1].tools.isEmpty)
}

@Test func aiGenerateTextToolTelemetryFiresForEachToolCallLikeUpstreamCallbacks() async throws {
    let recorder = TelemetryRecorder()
    let call1 = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"a"}"#)
    let call2 = AIToolCall(id: "call-2", name: "tool1", arguments: #"{"value":"b"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            content: [.toolCall(call1), .toolCall(call2)],
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
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { input in
        .string("\(input["value"]?.stringValue ?? "")-result")
    }

    _ = try await AI.generateText(
        model: model,
        prompt: "prompt",
        executableTools: [tool],
        maxSteps: 2,
        telemetry: Telemetry.Options(integrations: [recorder])
    )

    let toolEvents = await recorder.events().filter { $0.operationID == "ai.generateText.tool" }
    #expect(toolEvents.map(\.kind) == [.toolStart, .toolEnd, .toolStart, .toolEnd])
    #expect(toolEvents[0].input?["toolCall"]?["id"]?.stringValue == "call-1")
    #expect(toolEvents[0].input?["toolCall"]?["arguments"]?.stringValue == #"{"value":"a"}"#)
    #expect(toolEvents[1].output?["status"]?.stringValue == "executed")
    #expect(toolEvents[1].output?["arguments"]?["value"]?.stringValue == "a")
    #expect(toolEvents[1].output?["result"]?["result"]?.stringValue == "a-result")
    #expect(toolEvents[2].input?["toolCall"]?["id"]?.stringValue == "call-2")
    #expect(toolEvents[3].output?["arguments"]?["value"]?.stringValue == "b")
    #expect(toolEvents[3].output?["result"]?["result"]?.stringValue == "b-result")
}

@Test func aiGenerateTextToolTelemetryRecordsToolExecutionErrorsLikeUpstreamCallbacks() async throws {
    struct ToolFailure: Error, CustomStringConvertible {
        var description: String { "tool execution failed" }
    }

    let recorder = TelemetryRecorder()
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"test"}"#)
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
        prompt: "prompt",
        executableTools: [tool],
        maxSteps: 1,
        telemetry: Telemetry.Options(integrations: [recorder])
    )

    #expect(result.toolResults == [
        AIToolResult(
            toolCallID: "call-1",
            toolName: "tool1",
            result: [
                "type": "error-text",
                "value": "Error: tool execution failed"
            ],
            isError: true
        )
    ])

    let toolEvents = await recorder.events().filter { $0.operationID == "ai.generateText.tool" }
    #expect(toolEvents.map(\.kind) == [.toolStart, .toolError])
    #expect(toolEvents[0].input?["toolCall"]?["id"]?.stringValue == "call-1")
    #expect(toolEvents[1].input?["toolCall"]?["id"]?.stringValue == "call-1")
    #expect(toolEvents[1].errorDescription == "tool execution failed")
}

@Test func aiGenerateTextLifecycleTelemetryOrdersModelToolAndStepEventsLikeUpstreamCallbacks() async throws {
    let log = ExecutionWrapperLog()
    let telemetry = GenerateTextLifecycleTelemetry(log: log)
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"test"}"#)
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
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { input in
        await log.append("tool-execute:\(input["value"]?.stringValue ?? "")")
        return .string("\(input["value"]?.stringValue ?? "")-result")
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "prompt",
        executableTools: [tool],
        maxSteps: 2,
        telemetry: Telemetry.Options(integrations: [telemetry])
    )

    let entries = await log.entries()
    #expect(result.text == "Done.")
    #expect(entries.contains("event:stepStart:ai.generateText.step:0"))
    #expect(entries.contains("event:stepEnd:ai.generateText.step:0"))
    #expect(entries.contains("event:toolStart:ai.generateText.tool:0"))
    #expect(entries.contains("event:toolEnd:ai.generateText.tool:0"))
    #expect(entries.contains("language-start:ai.generateText:mock-language"))
    #expect(entries.contains("language-end:ai.generateText"))
    #expect(entries.contains("tool-start:call-1:tool1"))
    #expect(entries.contains("tool-execute:test"))
    #expect(entries.contains("tool-end:call-1:tool1"))
    #expect(entries.firstIndex(of: "event:stepStart:ai.generateText.step:0")! < entries.firstIndex(of: "language-start:ai.generateText:mock-language")!)
    #expect(entries.firstIndex(of: "language-end:ai.generateText")! < entries.firstIndex(of: "event:toolStart:ai.generateText.tool:0")!)
    #expect(entries.firstIndex(of: "event:toolStart:ai.generateText.tool:0")! < entries.firstIndex(of: "tool-start:call-1:tool1")!)
    #expect(entries.firstIndex(of: "tool-start:call-1:tool1")! < entries.firstIndex(of: "tool-execute:test")!)
    #expect(entries.firstIndex(of: "tool-execute:test")! < entries.firstIndex(of: "tool-end:call-1:tool1")!)
    #expect(entries.firstIndex(of: "tool-end:call-1:tool1")! < entries.firstIndex(of: "event:toolEnd:ai.generateText.tool:0")!)
    #expect(entries.firstIndex(of: "event:toolEnd:ai.generateText.tool:0")! < entries.firstIndex(of: "event:stepEnd:ai.generateText.step:0")!)
}

@Test func aiGenerateTextToolExecutionContextCarriesAccumulatedMessagesAcrossStepsLikeUpstreamCallbacks() async throws {
    let firstCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"step0"}"#)
    let secondCall = AIToolCall(id: "call-2", name: "tool1", arguments: #"{"value":"step1"}"#)
    let firstResult = AIToolResult(toolCallID: "call-1", toolName: "tool1", result: "step0-result")
    let secondResult = AIToolResult(toolCallID: "call-2", toolName: "tool1", result: "step1-result")
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            content: [.toolCall(firstCall)],
            finishReason: "tool-calls",
            rawValue: .object(["step": 1])
        ),
        TextGenerationResult(
            text: "",
            content: [.toolCall(secondCall)],
            finishReason: "tool-calls",
            rawValue: .object(["step": 2])
        ),
        TextGenerationResult(
            text: "Done.",
            content: [.text("Done.")],
            finishReason: "stop",
            rawValue: .object(["step": 3])
        )
    ])
    let capture = ToolExecutionContextListCapture()
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ],
        executeWithContext: { input, context in
            await capture.record(arguments: input, context: context)
            return .string("\(input["value"]?.stringValue ?? "")-result")
        }
    ) { _ in
        .null
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "prompt",
        executableTools: [tool],
        maxSteps: 3
    )

    let calls = await capture.calls()
    #expect(result.text == "Done.")
    #expect(result.toolResults == [firstResult, secondResult])
    #expect(calls.map(\.toolCallID) == ["call-1", "call-2"])
    #expect(calls.map(\.arguments) == [["value": "step0"], ["value": "step1"]])
    #expect(calls[0].messages == [.user("prompt")])
    #expect(calls[1].messages == [
        .user("prompt"),
        AIMessage(role: .assistant, content: [.toolCall(firstCall)]),
        AIMessage(role: .tool, content: [.toolResult(firstResult)])
    ])
    #expect(model.requests[2].messages == [
        .user("prompt"),
        AIMessage(role: .assistant, content: [.toolCall(firstCall)]),
        AIMessage(role: .tool, content: [.toolResult(firstResult)]),
        AIMessage(role: .assistant, content: [.toolCall(secondCall)]),
        AIMessage(role: .tool, content: [.toolResult(secondResult)])
    ])
}

