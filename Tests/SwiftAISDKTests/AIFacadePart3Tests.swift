import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiGenerateTextWrapsToolArgumentRefinementFailures() async throws {
    struct RefinementFailure: Error, CustomStringConvertible {
        var description: String { "could not repair input" }
    }

    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"city":42}"#)
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "",
        finishReason: "tool-calls",
        toolCalls: [toolCall],
        rawValue: .object([:])
    ))
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object"],
        refineArguments: { _ in throw RefinementFailure() }
    ) { _ in
        ["ok": true]
    }

    do {
        _ = try await AI.generateText(
            model: model,
            prompt: "Use a tool.",
            executableTools: [lookup]
        )
        Issue.record("Expected tool repair error.")
    } catch let error as AIToolCallRepairError {
        #expect(error.toolName == "lookup")
        #expect(error.toolCallID == "call-1")
        #expect(error.originalError == "could not repair input")
    }
}
@Test func aiGenerateTextValidatesToolArgumentsAfterRefinement() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"city":42}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object(["step": 1])),
        TextGenerationResult(text: "done", finishReason: "stop", rawValue: .object(["step": 2]))
    ])
    let capture = ToolCapture()
    let lookup = AITool(
        name: "lookup",
        parameters: [
            "type": "object",
            "properties": ["city": ["type": "string"]],
            "required": ["city"]
        ],
        refineArguments: { _ in ["city": "Tokyo"] }
    ) { arguments in
        await capture.record(arguments)
        return ["city": arguments["city"] ?? .null]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 2
    )

    #expect(result.text == "done")
    #expect(await capture.value()?["city"]?.stringValue == "Tokyo")
    #expect(result.toolResults.first?.result["city"]?.stringValue == "Tokyo")
}
@Test func aiStreamTextMarksDynamicToolPartsAndResults() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "runtimeSearch", arguments: #"{"query":"docs"}"#)
    let dynamicToolCall = AIToolCall(id: "call-1", name: "runtimeSearch", arguments: #"{"query":"docs"}"#, dynamic: true)
    let dynamicResult = AIToolResult(
        toolCallID: "call-1",
        toolName: "runtimeSearch",
        result: ["items": ["one"]],
        dynamic: true
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .toolInputStart(id: "call-1", name: "runtimeSearch"),
                .toolInputDelta(id: "call-1", delta: #"{"query":"docs"}"#),
                .toolInputEnd(id: "call-1"),
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 4))
            ],
            [
                .textDelta("done"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 8))
            ]
        ]
    )
    let runtimeSearch = AITool.dynamic(
        name: "runtimeSearch",
        description: "Runtime-discovered search tool.",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]]
    ) { _ in
        ["items": ["one"]]
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "Search runtime docs.",
        executableTools: [runtimeSearch],
        maxSteps: 2
    ) {
        streamed.append(part)
    }

    #expect(streamed.contains(.toolInputStart(id: "call-1", name: "runtimeSearch", dynamic: true)))
    #expect(streamed.contains(.toolCall(dynamicToolCall)))
    #expect(streamed.contains(.toolResult(dynamicResult)))
    #expect(model.streamRequests[0].tools["runtimeSearch"]?["description"]?.stringValue == "Runtime-discovered search tool.")
    #expect(model.streamRequests[0].tools["runtimeSearch"]?["dynamic"] == nil)
    #expect(model.streamRequests[1].messages[1].content == [.toolCall(dynamicToolCall)])
    #expect(model.streamRequests[1].messages[2].content == [.toolResult(dynamicResult)])
}
@Test func aiStreamTextStopsForUserApprovalRequest() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "deleteFile", arguments: #"{"path":"/tmp/a.txt"}"#)
    let approvalRequest = AIToolApprovalRequest(
        id: "approval-call-1",
        toolName: "deleteFile",
        arguments: #"{"path":"/tmp/a.txt"}"#,
        toolCallID: "call-1"
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .textDelta("This should not stream."),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 8))
            ]
        ]
    )
    let deleteFile = AITool(
        name: "deleteFile",
        parameters: ["type": "object", "properties": ["path": ["type": "string"]]]
    ) { _ in
        Issue.record("Tool should not execute before user approval.")
        return ["deleted": true]
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "Delete the file.",
        executableTools: [deleteFile],
        maxSteps: 2,
        toolApproval: { context in
            #expect(context.toolCall == toolCall)
            #expect(context.arguments["path"]?.stringValue == "/tmp/a.txt")
            return .userApproval
        }
    ) {
        streamed.append(part)
    }

    #expect(model.streamRequests.count == 1)
    #expect(streamed == [
        .toolCall(toolCall),
        .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3)),
        .toolApprovalRequest(approvalRequest)
    ])
}
@Test func aiGenerateTextExecutesTypedToolsAndContinuesUntilFinalText() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"query":"weather"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object(["step": 1])),
        TextGenerationResult(text: "It is sunny.", finishReason: "stop", rawValue: .object(["step": 2]))
    ])
    let capture = ToolCapture()
    let lookup = AITool(
        name: "lookup",
        description: "Look up a value.",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]]
    ) { arguments in
        await capture.record(arguments)
        return ["forecast": "sunny"]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 3
    )

    #expect(result.text == "It is sunny.")
    let executedArguments = await capture.value()
    #expect(executedArguments?["query"]?.stringValue == "weather")
    #expect(result.toolResults.count == 1)
    #expect(result.toolResults[0].toolCallID == "call-1")
    #expect(result.toolResults[0].result["forecast"]?.stringValue == "sunny")
    #expect(result.steps.count == 2)
    #expect(result.steps[0].toolCalls == [toolCall])
    #expect(result.steps[0].toolResults.count == 1)
    #expect(result.steps[1].text == "It is sunny.")

    #expect(model.requests.count == 2)
    #expect(model.requests[0].tools["lookup"]?["description"]?.stringValue == "Look up a value.")
    #expect(model.requests[1].messages.count == 3)
    #expect(model.requests[1].messages[1].content == [.toolCall(toolCall)])
    guard case let .toolResult(toolResult) = model.requests[1].messages[2].content.first else {
        Issue.record("Expected a tool result message.")
        return
    }
    #expect(toolResult.toolName == "lookup")
    #expect(toolResult.result["forecast"]?.stringValue == "sunny")
}
@Test func aiGenerateTextStopsWhenToolLoopConditionMatches() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "finalAnswer", arguments: #"{"value":"done"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object(["step": 1])),
        TextGenerationResult(text: "This should not be requested.", finishReason: "stop", rawValue: .object(["step": 2]))
    ])
    let finalAnswer = AITool(
        name: "finalAnswer",
        parameters: ["type": "object", "properties": ["value": ["type": "string"]]]
    ) { arguments in
        ["value": arguments["value"] ?? .string("missing")]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Stop after final answer tool.",
        executableTools: [finalAnswer],
        maxSteps: 3,
        stopWhen: [.hasToolCall("finalAnswer")]
    )

    #expect(model.requests.count == 1)
    #expect(result.text == "")
    #expect(result.toolResults == [
        AIToolResult(toolCallID: "call-1", toolName: "finalAnswer", result: ["value": "done"])
    ])
    #expect(result.steps.count == 1)
    #expect(result.steps[0].toolCalls == [toolCall])
    #expect(result.steps[0].toolResults.count == 1)
}
@Test func aiGenerateTextPrepareStepOverridesRequestAndReceivesResponseMessages() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"query":"weather"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object(["step": 1])),
        TextGenerationResult(text: "prepared answer", finishReason: "stop", rawValue: .object(["step": 2]))
    ])
    let capture = PrepareStepCapture()
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]]
    ) { _ in
        ["forecast": "sunny"]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 3,
        prepareStep: { context in
            await capture.record(context)
            guard context.stepNumber == 1 else { return nil }
            var request = context.request
            request.messages.append(.user("prepared follow-up"))
            request.toolChoice = ["type": "tool", "toolName": "lookup"]
            request.providerOptions["test"] = ["step": 2]
            return AIPrepareStepResult(request: request)
        }
    )

    #expect(result.text == "prepared answer")
    #expect(model.requests.count == 2)
    #expect(model.requests[1].messages.last == .user("prepared follow-up"))
    #expect(model.requests[1].toolChoice?["toolName"]?.stringValue == "lookup")
    #expect(model.requests[1].providerOptions["test"]?["step"]?.intValue == 2)
    #expect(await capture.stepNumbers() == [0, 1])
    #expect(await capture.stepCounts() == [0, 1])
    #expect(await capture.responseMessageCounts() == [0, 2])
}
@Test func aiGenerateTextRefinesToolArgumentsBeforeExecution() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"city":" tokyo "}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object(["step": 1])),
        TextGenerationResult(text: "done", finishReason: "stop", rawValue: .object(["step": 2]))
    ])
    let capture = ToolCapture()
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": ["city": ["type": "string"]]],
        refineArguments: { arguments in
            guard let city = arguments["city"]?.stringValue else {
                throw AIError.invalidArgument(argument: "city", message: "city is required.")
            }
            return ["city": .string(city.trimmingCharacters(in: .whitespacesAndNewlines).capitalized)]
        }
    ) { arguments in
        await capture.record(arguments)
        return ["city": arguments["city"] ?? .string("missing")]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 2
    )

    #expect(result.text == "done")
    #expect(await capture.value()?["city"]?.stringValue == "Tokyo")
    #expect(result.toolResults.first?.result["city"]?.stringValue == "Tokyo")
}
@Test func aiGenerateTextPassesAbortSignalToToolExecutionContext() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"query":"weather"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object([:])),
        TextGenerationResult(text: "done", finishReason: "stop", rawValue: .object([:]))
    ])
    let capture = ToolExecutionContextCapture()
    let controller = AIAbortController()
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]],
        executeWithContext: { arguments, context in
            await capture.record(arguments: arguments, context: context)
            return ["forecast": "sunny"]
        },
        execute: { _ in
            Issue.record("Expected contextual execute closure to be used.")
            return [:]
        }
    )

    _ = try await AI.generateText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 3,
        abortSignal: controller.signal
    )

    let snapshot = await capture.snapshot()
    #expect(snapshot.arguments?["query"]?.stringValue == "weather")
    #expect(snapshot.context?.toolCallID == "call-1")
    #expect(snapshot.context?.abortSignal === controller.signal)
    #expect(snapshot.context?.messages == [.user("Weather?")])
}
@Test func aiGenerateTextMarksDynamicToolCallsResultsAndMessages() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "runtimeSearch", arguments: #"{"query":"docs"}"#)
    let dynamicToolCall = AIToolCall(id: "call-1", name: "runtimeSearch", arguments: #"{"query":"docs"}"#, dynamic: true)
    let dynamicResult = AIToolResult(
        toolCallID: "call-1",
        toolName: "runtimeSearch",
        result: ["items": ["one"]],
        dynamic: true
    )
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object(["step": 1])),
        TextGenerationResult(text: "done", finishReason: "stop", rawValue: .object(["step": 2]))
    ])
    let runtimeSearch = AITool.dynamic(
        name: "runtimeSearch",
        description: "Runtime-discovered search tool.",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]]
    ) { _ in
        ["items": ["one"]]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Search runtime docs.",
        executableTools: [runtimeSearch],
        maxSteps: 2
    )

    #expect(result.text == "done")
    #expect(result.toolResults == [dynamicResult])
    #expect(result.steps[0].toolCalls == [dynamicToolCall])
    #expect(result.steps[0].toolResults == [dynamicResult])
    #expect(model.requests[0].tools["runtimeSearch"]?["description"]?.stringValue == "Runtime-discovered search tool.")
    #expect(model.requests[0].tools["runtimeSearch"]?["dynamic"] == nil)
    #expect(model.requests[1].messages[1].content == [.toolCall(dynamicToolCall)])
    #expect(model.requests[1].messages[2].content == [.toolResult(dynamicResult)])
}
@Test func aiGenerateTextAddsDeniedApprovalResultAndContinues() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "deleteFile", arguments: #"{"path":"/tmp/a.txt"}"#)
    let approvalRequest = AIToolApprovalRequest(
        id: "approval-call-1",
        toolName: "deleteFile",
        arguments: #"{"path":"/tmp/a.txt"}"#,
        toolCallID: "call-1",
        isAutomatic: true
    )
    let approvalResponse = AIToolApprovalResponse(
        id: "approval-call-1",
        approved: false,
        reason: "User denied access"
    )
    let deniedResult = AIToolResult(
        toolCallID: "call-1",
        toolName: "deleteFile",
        result: ["type": "execution-denied", "reason": "User denied access"]
    )
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object(["step": 1])),
        TextGenerationResult(text: "Skipped deletion.", finishReason: "stop", rawValue: .object(["step": 2]))
    ])
    let deleteFile = AITool(
        name: "deleteFile",
        parameters: ["type": "object", "properties": ["path": ["type": "string"]]]
    ) { _ in
        Issue.record("Denied tool should not execute.")
        return ["deleted": true]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Delete the file.",
        executableTools: [deleteFile],
        maxSteps: 2,
        toolApproval: { context in
            #expect(context.toolCall == toolCall)
            #expect(context.arguments["path"]?.stringValue == "/tmp/a.txt")
            return .denied(reason: "User denied access")
        }
    )

    #expect(result.text == "Skipped deletion.")
    #expect(result.toolApprovalRequests == [approvalRequest])
    #expect(result.toolApprovalResponses == [approvalResponse])
    #expect(result.toolResults == [deniedResult])
    #expect(result.steps[0].toolApprovalRequests == [approvalRequest])
    #expect(result.steps[0].toolApprovalResponses == [approvalResponse])
    #expect(result.steps[0].toolResults == [deniedResult])
    #expect(model.requests.count == 2)
    #expect(model.requests[1].messages[1].content == [
        .toolCall(toolCall),
        .toolApprovalRequest(approvalRequest)
    ])
    #expect(model.requests[1].messages[2].content == [
        .toolApprovalResponse(approvalResponse),
        .toolResult(deniedResult)
    ])
}
