import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiStreamLanguageModelCallRefinesToolInputBeforeEmittingToolCallLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"city":" kyoto "}"#)
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .textDelta("done"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 8))
            ]
        ]
    )
    let callbackCapture = ToolCapture()
    let executionCapture = ToolCapture()
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": ["city": ["type": "string"]]],
        onInputAvailable: { context in
            await callbackCapture.record(context.input)
        },
        refineArguments: { arguments in
            guard let city = arguments["city"]?.stringValue else {
                throw AIError.invalidArgument(argument: "city", message: "city is required.")
            }
            return ["city": .string(city.trimmingCharacters(in: .whitespacesAndNewlines).capitalized)]
        }
    ) { arguments in
        await executionCapture.record(arguments)
        return ["city": arguments["city"] ?? .string("missing")]
    }

    var streamedToolCall: AIToolCall?
    for try await part in AI.streamText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 2
    ) {
        if case let .toolCall(call) = part {
            streamedToolCall = call
        }
    }

    #expect(streamedToolCall?.arguments == #"{"city":"Kyoto"}"#)
    #expect(await callbackCapture.value()?["city"]?.stringValue == "Kyoto")
    #expect(await executionCapture.value()?["city"]?.stringValue == "Kyoto")
}

@Test func aiStreamLanguageModelCallRepairsUnknownToolNameLikeUpstream() async throws {
    let unknownCall = AIToolCall(
        id: "call-1",
        name: "unknownTool",
        arguments: #"{ "value": "test" }"#
    )
    let repairedCall = AIToolCall(
        id: "call-1",
        name: "correctTool",
        arguments: #"{ "value": "test" }"#
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .toolCall(unknownCall),
            .finish(reason: "stop", usage: streamLanguageModelCallUsage())
        ]]
    )
    let correctTool = AITool(
        name: "correctTool",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { arguments in
        .string("\(arguments["value"]?.stringValue ?? "")-result")
    }

    let streamed = try await collectStreamLanguageModelCallParts(
        model: model,
        executableTools: [correctTool],
        repairToolCall: { context in
            #expect(context.toolCall == unknownCall)
            #expect((context.error as? AINoSuchToolError)?.toolName == "unknownTool")
            #expect((context.error as? AINoSuchToolError)?.availableToolNames == ["correctTool"])
            var repaired = context.toolCall
            repaired.name = "correctTool"
            return repaired
        }
    )

    #expect(streamed == [
        .toolCall(repairedCall),
        .finish(reason: "stop", usage: streamLanguageModelCallUsage()),
        .toolResult(AIToolResult(
            toolCallID: "call-1",
            toolName: "correctTool",
            result: "test-result"
        ))
    ])
}

@Test func aiStreamLanguageModelCallForwardsStreamStartAndTextPartsLikeUpstream() async throws {
    let warnings = [
        AIWarning(type: "compatibility", feature: "tool-approval", message: "approval fallback is being used"),
        AIWarning(type: "other", message: "custom warning")
    ]
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .streamStart(warnings: warnings),
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "text"),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: streamLanguageModelCallUsage())
        ]]
    )

    let streamed = try await collectStreamLanguageModelCallParts(model: model)

    #expect(streamed == [
        .streamStart(warnings: warnings),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "text"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: streamLanguageModelCallUsage())
    ])
}

@Test func aiStreamLanguageModelCallForwardsToolInputProviderMetadataLikeUpstream() async throws {
    let providerMetadata: [String: JSONValue] = [
        "testProvider": ["someKey": "someValue"]
    ]
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .toolInputStart(id: "call-1", name: "test-tool", providerMetadata: providerMetadata),
            .toolInputDelta(id: "call-1", delta: #"{"value":"test"}"#),
            .toolInputEnd(id: "call-1"),
            .finish(reason: "tool-calls", usage: streamLanguageModelCallUsage())
        ]]
    )

    let streamed = try await collectStreamLanguageModelCallParts(model: model)

    #expect(streamed == [
        .toolInputStart(id: "call-1", name: "test-tool", providerMetadata: providerMetadata),
        .toolInputDelta(id: "call-1", delta: #"{"value":"test"}"#),
        .toolInputEnd(id: "call-1"),
        .finish(reason: "tool-calls", usage: streamLanguageModelCallUsage())
    ])
}

@Test func aiStreamLanguageModelCallForwardsReasoningFileAndCustomPartsLikeUpstream() async throws {
    let file = AIStreamFile(
        mediaType: "text/plain",
        data: Data("Hello World".utf8),
        providerMetadata: ["testProvider": ["signature": "test-signature"]]
    )
    let reasoningFile = AIStreamFile(
        mediaType: "text/plain",
        data: Data("reasoning".utf8)
    )
    let custom: JSONValue = [
        "kind": "openai.compaction"
    ]
    let customMetadata: [String: JSONValue] = [
        "openai": ["itemId": "cmp_123"]
    ]
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .reasoningStart(id: "1"),
            .reasoningDeltaPart(id: "1", delta: "text"),
            .reasoningEnd(id: "1"),
            .file(file),
            .reasoningFile(reasoningFile),
            .custom(custom, providerMetadata: customMetadata),
            .finish(reason: "stop", usage: streamLanguageModelCallUsage())
        ]]
    )

    let streamed = try await collectStreamLanguageModelCallParts(model: model)

    #expect(streamed == [
        .reasoningStart(id: "1"),
        .reasoningDeltaPart(id: "1", delta: "text"),
        .reasoningEnd(id: "1"),
        .file(file),
        .reasoningFile(reasoningFile),
        .custom(custom, providerMetadata: customMetadata),
        .finish(reason: "stop", usage: streamLanguageModelCallUsage())
    ])
}

@Test func aiStreamLanguageModelCallRecordsTelemetryStartAndEndLikeUpstreamCallbacks() async throws {
    let recorder = TelemetryRecorder()
    let responseMetadata = AIResponseMetadata(
        id: "response-1",
        timestamp: Date(timeIntervalSince1970: 1_735_689_600),
        modelID: "response-model"
    )
    let toolCall = AIToolCall(
        id: "call-1",
        name: "testTool",
        arguments: #"{ "value": "hello" }"#
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .responseMetadata(responseMetadata),
            .textStart(id: "text-1"),
            .textDeltaPart(id: "text-1", delta: "Hello "),
            .textDeltaPart(id: "text-1", delta: "world"),
            .textEnd(id: "text-1"),
            .toolCall(toolCall),
            .finish(reason: "tool-calls", usage: streamLanguageModelCallUsage())
        ]]
    )

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "test prompt",
        telemetry: Telemetry.Options(integrations: [recorder])
    ) {
        streamed.append(part)
    }
    let events = await recorder.events()

    #expect(streamed.contains(.toolCall(toolCall)))
    #expect(events.map(\.kind) == [.start, .end])
    #expect(events[0].callID == events[1].callID)
    #expect(events[0].operationID == "ai.streamText")
    #expect(events[0].input?["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "test prompt")
    #expect(events[1].output?["text"]?.stringValue == "Hello world")
    #expect(events[1].output?["finishReason"]?.stringValue == "tool-calls")
    #expect(events[1].output?["toolCallCount"]?.intValue == 1)
    #expect(events[1].usage == streamLanguageModelCallUsage())
    #expect(events[1].responseMetadata == responseMetadata)
}

@Test func aiStreamLanguageModelCallThrowsWhenApprovalRequestToolCallIsMissingLikeUpstream() async throws {
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .toolApprovalRequest(AIToolApprovalRequest(
                id: "mcp-approval-1",
                toolName: "mcp_tool",
                arguments: #"{}"#,
                toolCallID: "non-existent-call"
            )),
            .finish(reason: "stop", usage: streamLanguageModelCallUsage())
        ]]
    )

    do {
        _ = try await collectStreamLanguageModelCallParts(model: model)
        Issue.record("Expected missing tool call for approval request to throw.")
    } catch let error as AIToolCallNotFoundForApprovalError {
        #expect(error == AIToolCallNotFoundForApprovalError(
            toolCallID: "non-existent-call",
            approvalID: "mcp-approval-1"
        ))
    }
}

@Test func aiStreamLanguageModelCallForwardsProviderApprovalRequestWithMatchingToolCallLikeUpstream() async throws {
    let toolCall = AIToolCall(
        id: "mcp-call-1",
        name: "mcp_tool",
        arguments: #"{ "query": "test" }"#,
        providerExecuted: true
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .toolCall(toolCall),
            .toolApprovalRequest(AIToolApprovalRequest(
                id: "mcp-approval-1",
                toolName: "placeholder",
                arguments: #"{}"#,
                toolCallID: "mcp-call-1"
            )),
            .finish(reason: "tool-calls", usage: streamLanguageModelCallUsage())
        ]]
    )

    let streamed = try await collectStreamLanguageModelCallParts(model: model)

    #expect(streamed == [
        .toolCall(toolCall),
        .toolApprovalRequest(AIToolApprovalRequest(
            id: "mcp-approval-1",
            toolName: "mcp_tool",
            arguments: #"{ "query": "test" }"#,
            toolCallID: "mcp-call-1"
        )),
        .finish(reason: "tool-calls", usage: streamLanguageModelCallUsage())
    ])
}

@Test func aiStreamLanguageModelCallHandlesMultipleProviderApprovalRequestsLikeUpstream() async throws {
    let searchCall = AIToolCall(
        id: "mcp-call-1",
        name: "mcp_search",
        arguments: #"{ "query": "first" }"#,
        providerExecuted: true
    )
    let executeCall = AIToolCall(
        id: "mcp-call-2",
        name: "mcp_execute",
        arguments: #"{ "command": "ls" }"#,
        providerExecuted: true
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .toolCall(searchCall),
            .toolCall(executeCall),
            .toolApprovalRequest(AIToolApprovalRequest(
                id: "approval-1",
                toolName: "placeholder",
                arguments: #"{}"#,
                toolCallID: "mcp-call-1"
            )),
            .toolApprovalRequest(AIToolApprovalRequest(
                id: "approval-2",
                toolName: "placeholder",
                arguments: #"{}"#,
                toolCallID: "mcp-call-2"
            )),
            .finish(reason: "tool-calls", usage: streamLanguageModelCallUsage())
        ]]
    )

    let streamed = try await collectStreamLanguageModelCallParts(model: model)

    #expect(streamed == [
        .toolCall(searchCall),
        .toolCall(executeCall),
        .toolApprovalRequest(AIToolApprovalRequest(
            id: "approval-1",
            toolName: "mcp_search",
            arguments: #"{ "query": "first" }"#,
            toolCallID: "mcp-call-1"
        )),
        .toolApprovalRequest(AIToolApprovalRequest(
            id: "approval-2",
            toolName: "mcp_execute",
            arguments: #"{ "command": "ls" }"#,
            toolCallID: "mcp-call-2"
        )),
        .finish(reason: "tool-calls", usage: streamLanguageModelCallUsage())
    ])
}

@Test func aiStreamLanguageModelCallForwardsProviderExecutedDynamicToolPartsLikeUpstream() async throws {
    let providerMetadata: [String: JSONValue] = ["anthropic": ["serverName": "echo"]]
    let toolCall = AIToolCall(
        id: "call-1",
        name: "cityAttractions",
        arguments: #"{"city":"San Francisco"}"#,
        providerExecuted: true,
        dynamic: true,
        providerMetadata: providerMetadata
    )
    let toolResult = AIToolResult(
        toolCallID: "call-1",
        toolName: "cityAttractions",
        result: [
            "status": "success",
            "text": "The weather in San Francisco is 72F"
        ],
        dynamic: true,
        providerExecuted: true,
        providerMetadata: providerMetadata
    )
    let chunks: [LanguageStreamPart] = [
        .streamStart(warnings: []),
        .toolInputStart(
            id: "call-1",
            name: "cityAttractions",
            providerExecuted: true,
            dynamic: true,
            providerMetadata: providerMetadata
        ),
        .toolInputDelta(id: "call-1", delta: #"{"city":"San Francisco"}"#),
        .toolInputEnd(id: "call-1"),
        .toolCall(toolCall),
        .toolResult(toolResult),
        .finish(reason: "stop", usage: streamLanguageModelCallUsage())
    ]

    let result = try await collectForwardedLanguageStream(chunks)
    let completedStep = result.step.toolStep(
        index: 0,
        toolResults: [],
        approvalRequests: [],
        approvalResponses: []
    )

    #expect(result.streamed == chunks)
    #expect(completedStep.content == [
        .toolCall(toolCall),
        .toolResult(toolResult)
    ])
    #expect(completedStep.toolCalls == [toolCall])
    #expect(completedStep.toolResults == [toolResult])
}

private func collectStreamLanguageModelCallParts(
    model: MockLanguageModel,
    executableTools: [AITool] = [],
    repairToolCall: AIToolCallRepair? = nil
) async throws -> [LanguageStreamPart] {
    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        request: LanguageModelRequest(messages: [.user("Use a provider tool.")]),
        executableTools: executableTools,
        maxSteps: 1,
        repairToolCall: repairToolCall
    ) {
        streamed.append(part)
    }
    return streamed
}

private struct ForwardedLanguageStreamResult {
    var streamed: [LanguageStreamPart]
    var step: LanguageStreamToolStep
}

private actor ForwardedLanguageStepCapture {
    private var recordedStep: LanguageStreamToolStep?

    func record(_ step: LanguageStreamToolStep) {
        recordedStep = step
    }

    func step() -> LanguageStreamToolStep? {
        recordedStep
    }
}

private func collectForwardedLanguageStream(
    _ chunks: [LanguageStreamPart]
) async throws -> ForwardedLanguageStreamResult {
    let inputStream = AsyncThrowingStream<LanguageStreamPart, Error> { continuation in
        for chunk in chunks {
            continuation.yield(chunk)
        }
        continuation.finish()
    }
    let stepCapture = ForwardedLanguageStepCapture()
    let outputStream = AsyncThrowingStream<LanguageStreamPart, Error> { continuation in
        let task = Task {
            do {
                let step = try await forwardLanguageStream(inputStream, to: continuation)
                await stepCapture.record(step)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in outputStream {
        streamed.append(part)
    }
    let step = try #require(await stepCapture.step())
    return ForwardedLanguageStreamResult(streamed: streamed, step: step)
}

private func streamLanguageModelCallUsage() -> TokenUsage {
    TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13)
}
