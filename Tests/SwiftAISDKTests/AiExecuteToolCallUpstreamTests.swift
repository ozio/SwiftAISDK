import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiExecuteToolCallReturnsToolResultWithCorrectDataLikeUpstream() async throws {
    let batch = try await executeToolCalls(
        [executeToolCall()],
        toolsByName: ["testTool": executeTestTool()],
        request: executeToolRequest(),
        toolApproval: nil
    )

    #expect(batch.results == [
        AIToolResult(
            toolCallID: "call-1",
            toolName: "testTool",
            result: "test-result"
        )
    ])
    #expect(batch.approvalRequests.isEmpty)
    #expect(batch.approvalResponses.isEmpty)
    #expect(batch.needsUserApproval == false)
}

@Test func aiExecuteToolCallPassesMessagesAbortSignalMetadataAndContextLikeUpstream() async throws {
    let capture = ExecutionContextCapture()
    let controller = AIAbortController()
    let messages = [AIMessage.user("test message")]
    let call = executeToolCall(providerMetadata: ["custom": ["key": "value"]])

    _ = try await executeToolCalls(
        [call],
        toolsByName: [
            "testTool": executeTestTool(
                contextSchema: [
                    "type": "object",
                    "properties": [
                        "key1": ["type": "string"]
                    ],
                    "required": ["key1"]
                ],
                executeWithContext: { input, context in
                    await capture.record(input: input, context: context)
                    return .string("\(input["value"]?.stringValue ?? "")-result")
                }
            )
        ],
        request: executeToolRequest(
            messages: messages,
            toolContexts: ["testTool": ["key1": "value1"]],
            abortSignal: controller.signal
        ),
        toolApproval: nil
    )

    let snapshot = try #require(await capture.snapshot())
    #expect(snapshot.input == ["value": "test"])
    #expect(snapshot.context.toolCallID == "call-1")
    #expect(snapshot.context.messages == messages)
    #expect(snapshot.context.abortSignal === controller.signal)
    #expect(snapshot.context.metadata == ["custom": ["key": "value"]])
    #expect(snapshot.context.toolContext == ["key1": "value1"])
}

@Test func aiExecuteToolCallPreservesProviderMetadataOnResultLikeUpstream() async throws {
    let batch = try await executeToolCalls(
        [executeToolCall(providerMetadata: ["custom": ["key": "value"]])],
        toolsByName: ["testTool": executeTestTool()],
        request: executeToolRequest(),
        toolApproval: nil
    )

    #expect(batch.results[0].providerMetadata == ["custom": ["key": "value"]])
}

@Test func aiExecuteToolCallThrowsTypeValidationErrorWhenToolContextFailsValidationLikeUpstream() async throws {
    let capture = ExecutionContextCapture()

    do {
        _ = try await executeToolCalls(
            [executeToolCall()],
            toolsByName: [
                "testTool": executeTestTool(
                    contextSchema: [
                        "type": "object",
                        "properties": [
                            "key1": ["type": "string"]
                        ],
                        "required": ["key1"]
                    ],
                    executeWithContext: { input, context in
                        await capture.record(input: input, context: context)
                        return .string("should-not-run")
                    }
                )
            ],
            request: executeToolRequest(toolContexts: ["testTool": ["key1": 1]]),
            toolApproval: nil
        )
        Issue.record("expected type validation error")
    } catch let error as AITypeValidationError {
        #expect(error.value == ["key1": 1])
        #expect(error.context == AITypeValidationContext(field: "tool context", entityName: "testTool"))
    }

    #expect(await capture.snapshot() == nil)
}

@Test func aiExecuteToolCallThrowsExecutionErrorLikeSwiftRuntime() async throws {
    struct ToolFailure: Error, CustomStringConvertible {
        var description: String { "execution failed" }
    }

    do {
        _ = try await executeToolCalls(
            [executeToolCall()],
            toolsByName: ["testTool": executeTestTool(execute: { _ in throw ToolFailure() })],
            request: executeToolRequest(),
            toolApproval: nil
        )
        Issue.record("expected tool execution error")
    } catch let error as ToolFailure {
        #expect(error.description == "execution failed")
    }
}

@Test func aiExecuteToolCallSetsDynamicTrueForDynamicToolResultsLikeUpstream() async throws {
    let batch = try await executeToolCalls(
        [executeToolCall(dynamic: true)],
        toolsByName: [
            "testTool": AITool.dynamic(
                name: "testTool",
                parameters: executeToolSchema(),
                execute: { _ in .string("dynamic-result") }
            )
        ],
        request: executeToolRequest(),
        toolApproval: nil
    )

    #expect(batch.results[0].dynamic)
    #expect(batch.results[0].result == "dynamic-result")
}

@Test func aiExecuteToolCallDoesNotExecuteWhenUserApprovalIsRequiredLikeUpstreamApprovalFlow() async throws {
    let capture = ExecutionContextCapture()
    let batch = try await executeToolCalls(
        [executeToolCall()],
        toolsByName: [
            "testTool": executeTestTool(
                needsApproval: { _, _ in true },
                executeWithContext: { input, context in
                    await capture.record(input: input, context: context)
                    return .string("should-not-run")
                }
            )
        ],
        request: executeToolRequest(),
        toolApproval: nil
    )

    #expect(batch.needsUserApproval)
    #expect(batch.results.isEmpty)
    #expect(batch.approvalRequests == [
        AIToolApprovalRequest(
            id: "approval-call-1",
            toolName: "testTool",
            arguments: #"{"value":"test"}"#,
            toolCallID: "call-1"
        )
    ])
    #expect(await capture.snapshot() == nil)
}

private actor ExecutionContextCapture {
    private var captured: (input: JSONValue, context: AIToolExecutionContext)?

    func record(input: JSONValue, context: AIToolExecutionContext) {
        captured = (input, context)
    }

    func snapshot() -> (input: JSONValue, context: AIToolExecutionContext)? {
        captured
    }
}

private func executeToolCall(
    dynamic: Bool = false,
    providerMetadata: [String: JSONValue] = [:]
) -> AIToolCall {
    AIToolCall(
        id: "call-1",
        name: "testTool",
        arguments: #"{"value":"test"}"#,
        dynamic: dynamic,
        providerMetadata: providerMetadata
    )
}

private func executeTestTool(
    contextSchema: JSONValue? = nil,
    needsApproval: AIToolNeedsApproval? = nil,
    executeWithContext: (@Sendable (JSONValue, AIToolExecutionContext) async throws -> JSONValue)? = nil,
    execute: @escaping @Sendable (JSONValue) async throws -> JSONValue = { input in
        .string("\(input["value"]?.stringValue ?? "")-result")
    }
) -> AITool {
    AITool(
        name: "testTool",
        parameters: executeToolSchema(),
        contextSchema: contextSchema,
        needsApproval: needsApproval,
        executeWithContext: executeWithContext,
        execute: execute
    )
}

private func executeToolSchema() -> JSONValue {
    [
        "type": "object",
        "properties": [
            "value": ["type": "string"]
        ],
        "required": ["value"]
    ]
}

private func executeToolRequest(
    messages: [AIMessage] = [],
    toolContexts: [String: JSONValue] = [:],
    abortSignal: AIAbortSignal? = nil
) -> LanguageModelRequest {
    LanguageModelRequest(
        messages: messages,
        toolContexts: toolContexts,
        abortSignal: abortSignal
    )
}
