import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiGenerateTextHandlesProgrammaticProviderAndClientToolTurnsLikeUpstream() async throws {
    let providerCall = AIToolCall(
        id: "server-1",
        name: "code_execution",
        arguments: #"{"code":"game_loop()"}"#,
        providerExecuted: true
    )
    let firstRollCall = AIToolCall(id: "roll-1", name: "rollDie", arguments: #"{"player":"player1"}"#)
    let secondRollCall = AIToolCall(id: "roll-2", name: "rollDie", arguments: #"{"player":"player2"}"#)
    let firstRollResult = AIToolResult(toolCallID: "roll-1", toolName: "rollDie", result: 6)
    let secondRollResult = AIToolResult(toolCallID: "roll-2", toolName: "rollDie", result: 3)
    let providerResult = AIToolResult(
        toolCallID: "server-1",
        toolName: "code_execution",
        result: [
            "type": "code_execution_result",
            "stdout": "player1 wins",
            "stderr": "",
            "return_code": 0
        ],
        providerExecuted: true
    )
    let providerMetadata: [String: JSONValue] = [
        "anthropic": ["container": ["id": "container-1"]]
    ]
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "starting",
            content: [.text("starting"), .toolCall(providerCall), .toolCall(firstRollCall)],
            finishReason: "tool-calls",
            providerMetadata: providerMetadata,
            rawValue: .object(["step": 1])
        ),
        TextGenerationResult(
            text: "",
            content: [.toolCall(secondRollCall)],
            finishReason: "tool-calls",
            providerMetadata: providerMetadata,
            rawValue: .object(["step": 2])
        ),
        TextGenerationResult(
            text: "final",
            content: [.toolResult(providerResult), .text("final")],
            finishReason: "stop",
            rawValue: .object(["step": 3])
        )
    ])
    let executions = ToolExecutionInputListCapture()
    let prepareCapture = PrepareStepSnapshotCapture()
    let rollDie = AITool(
        name: "rollDie",
        description: "Roll a die and return the result.",
        parameters: [
            "type": "object",
            "properties": ["player": ["type": "string"]],
            "required": ["player"]
        ],
        providerOptions: ["anthropic": ["allowedCallers": ["code_execution_20250825"]]]
    ) { input in
        await executions.record(input)
        return input["player"]?.stringValue == "player1" ? 6 : 3
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Play a dice game.",
        tools: [
            "code_execution": [
                "type": "provider",
                "id": "anthropic.code_execution_20250825",
                "args": [:]
            ]
        ],
        executableTools: [rollDie],
        maxSteps: 3,
        prepareStep: { context in
            await prepareCapture.record(context)
            guard let containerID = context.steps.last?.providerMetadata["anthropic"]?["container"]?["id"]?.stringValue else {
                return nil
            }
            var request = context.request
            request.providerOptions = ["anthropic": ["container": ["id": .string(containerID)]]]
            return AIPrepareStepResult(request: request)
        }
    )

    #expect(await executions.values() == [
        ["player": "player1"],
        ["player": "player2"]
    ])
    #expect(result.text == "final")
    #expect(result.steps.count == 3)
    #expect(result.steps.map(\.finishReason) == ["tool-calls", "tool-calls", "stop"])
    #expect(model.requests[0].tools.keys.sorted() == ["code_execution", "rollDie"])
    #expect(model.requests[0].tools["code_execution"]?["type"]?.stringValue == "provider")
    #expect(model.requests[0].tools["code_execution"]?["id"]?.stringValue == "anthropic.code_execution_20250825")
    #expect(model.requests[0].tools["code_execution"]?["args"] == .object([:]))
    #expect(model.requests[0].tools["rollDie"]?["description"]?.stringValue == "Roll a die and return the result.")
    #expect(model.requests[0].tools["rollDie"]?["providerOptions"] == [
        "anthropic": ["allowedCallers": ["code_execution_20250825"]]
    ])
    #expect(result.toolCalls == [providerCall, firstRollCall, secondRollCall])
    #expect(result.toolResults == [firstRollResult, secondRollResult, providerResult])
    #expect(result.finalStep?.toolCalls == [])
    #expect(result.finalStep?.toolResults == [providerResult])

    let firstResponseMessages: [AIMessage] = [
        AIMessage(role: .assistant, content: [.text("starting"), .toolCall(providerCall), .toolCall(firstRollCall)]),
        AIMessage(role: .tool, content: [.toolResult(firstRollResult)])
    ]
    let secondResponseMessages: [AIMessage] = [
        AIMessage(role: .assistant, content: [.toolCall(secondRollCall)]),
        AIMessage(role: .tool, content: [.toolResult(secondRollResult)])
    ]
    #expect(model.requests[1].messages == [.user("Play a dice game.")] + firstResponseMessages)
    #expect(model.requests[2].messages == [.user("Play a dice game.")] + firstResponseMessages + secondResponseMessages)
    #expect(model.requests[1].providerOptions == ["anthropic": ["container": ["id": "container-1"]]])
    #expect(model.requests[2].providerOptions == ["anthropic": ["container": ["id": "container-1"]]])
    #expect(result.responseMessages == firstResponseMessages + secondResponseMessages + [
        AIMessage(role: .assistant, content: [.toolResult(providerResult), .text("final")])
    ])

    let snapshots = await prepareCapture.snapshots()
    #expect(snapshots.map(\.stepNumber) == [0, 1, 2])
    #expect(snapshots.map(\.requestMessages.count) == [1, 3, 5])
    #expect(snapshots.map(\.responseMessages.count) == [0, 2, 4])
}

@Test func aiGenerateTextPrepareStepReceivesInitialCurrentAndResponseMessagesLikeUpstream() async throws {
    let toolCall = AIToolCall(
        id: "call-1",
        name: "tool1",
        arguments: #"{"value":"test"}"#
    )
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
        .string("\(input["value"]?.stringValue ?? "")-result")
    }
    let capture = PrepareStepSnapshotCapture()

    let result = try await AI.generateText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 3,
        prepareStep: { context in
            await capture.record(context)
            return nil
        }
    )

    let snapshots = await capture.snapshots()
    #expect(result.text == "Done.")
    #expect(snapshots.map(\.stepNumber) == [0, 1])
    #expect(snapshots[0].initialMessages == [.user("test-input")])
    #expect(snapshots[0].requestMessages == [.user("test-input")])
    #expect(snapshots[0].responseMessages == [])
    #expect(snapshots[1].initialMessages == [.user("test-input")])
    #expect(snapshots[1].responseMessages == [
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        AIMessage(role: .tool, content: [
            .toolResult(AIToolResult(toolCallID: "call-1", toolName: "tool1", result: "test-result"))
        ])
    ])
    #expect(snapshots[1].requestMessages == snapshots[1].initialMessages + snapshots[1].responseMessages)
}

@Test func aiGenerateTextPrepareStepCanReplaceRequestMessagesLikeUpstream() async throws {
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "prepared answer",
        content: [.text("prepared answer")],
        rawValue: .object([:])
    ))
    let preparedMessages: [AIMessage] = [.user("prepared prompt")]

    let result = try await AI.generateText(
        model: model,
        prompt: "original prompt",
        executableTools: [],
        maxSteps: 1,
        prepareStep: { context in
            var request = context.request
            request.messages = preparedMessages
            return AIPrepareStepResult(request: request)
        }
    )

    #expect(result.text == "prepared answer")
    #expect(model.requests.first?.messages == preparedMessages)
}

@Test func aiGenerateTextPrepareStepCarriesPreparedMessagesForwardLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"test"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            content: [.toolCall(toolCall)],
            finishReason: "tool-calls",
            rawValue: .object([:])
        ),
        TextGenerationResult(
            text: "Done.",
            content: [.text("Done.")],
            finishReason: "stop",
            rawValue: .object([:])
        )
    ])
    let preparedMessages: [AIMessage] = [.user("prepared prompt")]
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
    let capture = PrepareStepSnapshotCapture()

    let result = try await AI.generateText(
        model: model,
        prompt: "prompt",
        executableTools: [tool],
        maxSteps: 3,
        prepareStep: { context in
            await capture.record(context)
            guard context.stepNumber == 0 else { return nil }
            var request = context.request
            request.messages = preparedMessages
            return AIPrepareStepResult(request: request)
        }
    )

    let responseMessages = [
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        AIMessage(role: .tool, content: [
            .toolResult(AIToolResult(toolCallID: "call-1", toolName: "tool1", result: "test-result"))
        ])
    ]
    let snapshots = await capture.snapshots()
    #expect(result.text == "Done.")
    #expect(model.requests.map(\.messages) == [
        preparedMessages,
        preparedMessages + responseMessages
    ])
    #expect(snapshots.map(\.requestMessages) == [
        [.user("prompt")],
        preparedMessages + responseMessages
    ])
    #expect(snapshots[1].responseMessages == responseMessages)
}

@Test func aiGenerateTextPrepareStepCanReplaceSystemInstructionMessagesLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"test"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            content: [.toolCall(toolCall)],
            finishReason: "tool-calls",
            rawValue: .object([:])
        ),
        TextGenerationResult(
            text: "Done.",
            content: [.text("Done.")],
            finishReason: "stop",
            rawValue: .object([:])
        )
    ])
    let initialMessages: [AIMessage] = [
        .system("test instructions"),
        .user("test-input")
    ]
    let preparedMessages: [AIMessage] = [
        .system("prepared instructions"),
        .user("test-input")
    ]
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
    let capture = PrepareStepSnapshotCapture()

    let result = try await AI.generateText(
        model: model,
        request: LanguageModelRequest(messages: initialMessages),
        executableTools: [tool],
        maxSteps: 2,
        prepareStep: { context in
            await capture.record(context)
            guard context.stepNumber == 0 else { return nil }
            var request = context.request
            request.messages = preparedMessages
            return AIPrepareStepResult(request: request)
        }
    )

    let responseMessages = [
        AIMessage(role: .assistant, content: [.toolCall(toolCall)]),
        AIMessage(role: .tool, content: [
            .toolResult(AIToolResult(toolCallID: "call-1", toolName: "tool1", result: "test-result"))
        ])
    ]
    let snapshots = await capture.snapshots()
    #expect(result.text == "Done.")
    #expect(model.requests.map(\.messages) == [
        preparedMessages,
        preparedMessages + responseMessages
    ])
    #expect(snapshots[0].initialMessages == initialMessages)
    #expect(snapshots[0].requestMessages == initialMessages)
    #expect(snapshots[1].initialMessages == initialMessages)
    #expect(snapshots[1].requestMessages == preparedMessages + responseMessages)
    #expect(snapshots[1].responseMessages == responseMessages)
}

@Test func aiGenerateTextPrepareStepUpdatesToolContextsForExecutionLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"query":"weather"}"#)
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
    let prepareCapture = PrepareStepToolContextCapture()
    let toolCapture = ToolExecutionContextCapture()
    let lookup = AITool(
        name: "lookup",
        parameters: [
            "type": "object",
            "properties": ["query": ["type": "string"]],
            "required": ["query"]
        ],
        contextSchema: [
            "type": "object",
            "properties": ["label": ["type": "string"]],
            "required": ["label"]
        ],
        executeWithContext: { arguments, context in
            await toolCapture.record(arguments: arguments, context: context)
            return ["label": context.toolContext?["label"] ?? .null]
        }
    ) { _ in
        .null
    }
    let request = LanguageModelRequest(
        messages: [.user("Weather?")],
        toolContexts: ["lookup": ["label": "initial"]]
    )

    let result = try await AI.generateText(
        model: model,
        request: request,
        executableTools: [lookup],
        maxSteps: 2,
        prepareStep: { context in
            await prepareCapture.record(context.request.toolContexts)
            guard context.stepNumber == 0 else { return nil }
            var request = context.request
            request.toolContexts["lookup"] = ["label": "updated"]
            return AIPrepareStepResult(request: request)
        }
    )

    let toolSnapshot = await toolCapture.snapshot()
    #expect(result.text == "done")
    #expect(await prepareCapture.values() == [
        ["lookup": ["label": "initial"]],
        ["lookup": ["label": "updated"]]
    ])
    #expect(toolSnapshot.arguments?["query"]?.stringValue == "weather")
    #expect(toolSnapshot.context?.toolContext == ["label": "updated"])
    #expect(model.requests.map(\.toolContexts) == [
        ["lookup": ["label": "updated"]],
        ["lookup": ["label": "updated"]]
    ])
    #expect(result.toolResults.first == AIToolResult(
        toolCallID: "call-1",
        toolName: "lookup",
        result: ["label": "updated"]
    ))
}

