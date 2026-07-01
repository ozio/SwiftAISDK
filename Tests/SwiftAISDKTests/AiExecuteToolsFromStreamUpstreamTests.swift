import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiExecuteToolsFromStreamExecutesToolAfterStreamingCallLikeUpstream() async throws {
    let toolCall = streamToolCall(name: "syncTool")
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .toolCall(toolCall),
            .finish(reason: "stop", usage: streamToolUsage())
        ]]
    )
    let tool = streamTestTool(name: "syncTool")

    let streamed = try await collectStreamToolParts(
        model: model,
        tools: [tool],
        maxSteps: 1
    )

    #expect(streamed == [
        .toolCall(toolCall),
        .finish(reason: "stop", usage: streamToolUsage()),
        .toolResult(AIToolResult(
            toolCallID: "call-1",
            toolName: "syncTool",
            result: "test-syncTool-result"
        ))
    ])
    #expect(model.streamRequests.count == 1)
}

@Test func aiExecuteToolsFromStreamDoesNotExecuteProviderExecutedToolCallsLikeUpstream() async throws {
    let capture = StreamToolInvocationCapture()
    let toolCall = streamToolCall(name: "providerTool", providerExecuted: true)
    let providerResult = AIToolResult(
        toolCallID: "call-1",
        toolName: "providerTool",
        result: "example-result"
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .toolCall(toolCall),
            .toolResult(providerResult),
            .finish(reason: "stop", usage: streamToolUsage())
        ]]
    )
    let tool = streamTestTool(name: "providerTool", executeWithContext: { input, _ in
        await capture.record(input)
        return .string("\(input["value"]?.stringValue ?? "")-should-not-execute")
    })

    let streamed = try await collectStreamToolParts(
        model: model,
        tools: [tool],
        maxSteps: 1
    )

    #expect(streamed == [
        .toolCall(toolCall),
        .toolResult(providerResult),
        .finish(reason: "stop", usage: streamToolUsage())
    ])
    #expect(await capture.count() == 0)
    #expect(model.streamRequests.count == 1)
}

@Test func aiExecuteToolsFromStreamEmitsAutoApprovedApprovalPartsAndResultLikeUpstream() async throws {
    let toolCall = streamToolCall(name: "approvedTool")
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .toolCall(toolCall),
            .finish(reason: "stop", usage: streamToolUsage())
        ]]
    )
    let tool = streamTestTool(name: "approvedTool")

    let streamed = try await collectStreamToolParts(
        model: model,
        tools: [tool],
        maxSteps: 1,
        toolApproval: { context in
            #expect(context.toolCall == toolCall)
            #expect(context.arguments == ["value": "test"])
            return .approved(reason: "trusted internal tool")
        }
    )

    #expect(streamed == [
        .toolCall(toolCall),
        .finish(reason: "stop", usage: streamToolUsage()),
        .toolApprovalRequest(AIToolApprovalRequest(
            id: "approval-call-1",
            toolName: "approvedTool",
            arguments: #"{"value":"test"}"#,
            toolCallID: "call-1",
            isAutomatic: true
        )),
        .toolApprovalResponse(AIToolApprovalResponse(
            id: "approval-call-1",
            approved: true,
            reason: "trusted internal tool"
        )),
        .toolResult(AIToolResult(
            toolCallID: "call-1",
            toolName: "approvedTool",
            result: "test-approvedTool-result"
        ))
    ])
}

@Test func aiExecuteToolsFromStreamEmitsAutoDeniedApprovalPartsWithoutRunningToolLikeUpstream() async throws {
    let capture = StreamToolInvocationCapture()
    let toolCall = streamToolCall(name: "deniedTool")
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .toolCall(toolCall),
            .finish(reason: "stop", usage: streamToolUsage())
        ]]
    )
    let tool = streamTestTool(name: "deniedTool", executeWithContext: { input, _ in
        await capture.record(input)
        return .string("should-not-run")
    })

    let streamed = try await collectStreamToolParts(
        model: model,
        tools: [tool],
        maxSteps: 1,
        toolApproval: { _ in .denied(reason: "blocked by policy") }
    )

    #expect(streamed == [
        .toolCall(toolCall),
        .finish(reason: "stop", usage: streamToolUsage()),
        .toolApprovalRequest(AIToolApprovalRequest(
            id: "approval-call-1",
            toolName: "deniedTool",
            arguments: #"{"value":"test"}"#,
            toolCallID: "call-1",
            isAutomatic: true
        )),
        .toolApprovalResponse(AIToolApprovalResponse(
            id: "approval-call-1",
            approved: false,
            reason: "blocked by policy"
        )),
        .toolResult(AIToolResult(
            toolCallID: "call-1",
            toolName: "deniedTool",
            result: ["type": "execution-denied", "reason": "blocked by policy"]
        ))
    ])
    #expect(await capture.count() == 0)
}

@Test func aiExecuteToolsFromStreamValidatesContextBeforeApprovalCallbacksLikeUpstream() async throws {
    let approvalCapture = StreamToolInvocationCapture()
    let toolCapture = StreamToolInvocationCapture()
    let toolCall = streamToolCall(name: "guardedTool")
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .toolCall(toolCall),
            .finish(reason: "stop", usage: streamToolUsage())
        ]]
    )
    let tool = streamTestTool(
        name: "guardedTool",
        contextSchema: [
            "type": "object",
            "properties": ["apiKey": ["type": "string"]],
            "required": ["apiKey"]
        ],
        needsApproval: { input, _ in
            await approvalCapture.record(input)
            return true
        },
        executeWithContext: { input, _ in
            await toolCapture.record(input)
            return .string("should-not-run")
        }
    )

    do {
        _ = try await collectStreamToolParts(
            model: model,
            request: LanguageModelRequest(
                messages: [.user("Use a guarded tool.")],
                toolContexts: ["guardedTool": ["apiKey": 123]]
            ),
            tools: [tool],
            maxSteps: 1
        )
        Issue.record("expected type validation error")
    } catch let error as AITypeValidationError {
        #expect(error.value == ["apiKey": 123])
        #expect(error.context == AITypeValidationContext(field: "tool context", entityName: "guardedTool"))
    }

    #expect(await approvalCapture.count() == 0)
    #expect(await toolCapture.count() == 0)
}

@Test func aiExecuteToolsFromStreamReturnsToolExecutionErrorsAsResultsLikeUpstream() async throws {
    struct ToolFailure: Error, CustomStringConvertible {
        var description: String { "Tool execution failed!" }
    }

    let toolCall = streamToolCall(name: "failingTool")
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [[
            .toolCall(toolCall),
            .finish(reason: "stop", usage: streamToolUsage())
        ]]
    )
    let tool = streamTestTool(name: "failingTool", executeWithContext: { _, _ in
        throw ToolFailure()
    })
    let streamed = try await collectStreamToolParts(
        model: model,
        tools: [tool],
        maxSteps: 1
    )

    #expect(streamed == [
        .toolCall(toolCall),
        .finish(reason: "stop", usage: streamToolUsage()),
        .toolResult(AIToolResult(
            toolCallID: "call-1",
            toolName: "failingTool",
            result: [
                "type": "error-text",
                "value": "Error: Tool execution failed!"
            ],
            isError: true
        ))
    ])
}

private actor StreamToolInvocationCapture {
    private var inputs: [JSONValue] = []

    func record(_ input: JSONValue) {
        inputs.append(input)
    }

    func count() -> Int {
        inputs.count
    }
}

private func collectStreamToolParts(
    model: MockLanguageModel,
    request: LanguageModelRequest = LanguageModelRequest(messages: [.user("Use a tool.")]),
    tools: [AITool],
    maxSteps: Int,
    toolApproval: AIToolApproval? = nil
) async throws -> [LanguageStreamPart] {
    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        request: request,
        executableTools: tools,
        maxSteps: maxSteps,
        toolApproval: toolApproval
    ) {
        streamed.append(part)
    }
    return streamed
}

private func streamToolCall(
    name: String,
    providerExecuted: Bool = false
) -> AIToolCall {
    AIToolCall(
        id: "call-1",
        name: name,
        arguments: #"{"value":"test"}"#,
        providerExecuted: providerExecuted
    )
}

private func streamTestTool(
    name: String,
    contextSchema: JSONValue? = nil,
    needsApproval: AIToolNeedsApproval? = nil,
    executeWithContext: (@Sendable (JSONValue, AIToolExecutionContext) async throws -> JSONValue)? = nil
) -> AITool {
    let executeWithContext = executeWithContext ?? { input, _ in
        .string("\(input["value"]?.stringValue ?? "")-\(name)-result")
    }
    return AITool(
        name: name,
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ],
        contextSchema: contextSchema,
        needsApproval: needsApproval,
        executeWithContext: executeWithContext,
        execute: { input in
            .string("\(input["value"]?.stringValue ?? "")-\(name)-result")
        }
    )
}

private func streamToolUsage() -> TokenUsage {
    TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13)
}
