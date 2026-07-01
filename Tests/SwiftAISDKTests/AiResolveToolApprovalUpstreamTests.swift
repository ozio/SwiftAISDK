import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiResolveToolApprovalReturnsNotApplicableWithoutUserOrToolApprovalLikeUpstream() async throws {
    let result = try await resolveToolApproval(
        toolsByName: ["weather": weatherTool()],
        toolCall: weatherToolCall(),
        arguments: ["city": "Berlin"],
        request: approvalRequest(),
        toolApproval: nil
    )

    #expect(result == .notApplicable)
}

@Test func aiResolveToolApprovalGenericCallbackOverridesToolDefinedApprovalLikeUpstream() async throws {
    let spy = ApprovalSpy()
    let result = try await resolveToolApproval(
        toolsByName: [
            "weather": weatherTool(needsApproval: { input, context in
                await spy.recordNeedsApproval(input: input, context: context, result: true)
            })
        ],
        toolCall: weatherToolCall(),
        arguments: ["city": "Berlin"],
        request: approvalRequest(),
        toolApproval: { context in
            await spy.recordGenericApproval(context: context, status: .denied(reason: nil))
        }
    )

    #expect(result == .denied(reason: nil))
    #expect(await spy.genericApprovalCount == 1)
    #expect(await spy.needsApprovalCount == 0)
}

@Test func aiResolveToolApprovalPassesContextToGenericCallbackLikeUpstream() async throws {
    let spy = ApprovalSpy()
    let request = approvalRequest(messages: [
        .user("first"),
        .assistant("second")
    ], toolContexts: ["weather": ["requestId": "req-1"]])
    let tool = weatherTool()

    _ = try await resolveToolApproval(
        toolsByName: ["weather": tool],
        toolCall: weatherToolCall(),
        arguments: ["city": "Berlin"],
        request: request,
        toolApproval: { context in
            await spy.recordGenericApproval(context: context, status: .notApplicable)
        }
    )

    let captured = try #require(await spy.lastGenericApprovalContext)
    #expect(captured.toolCall == weatherToolCall())
    #expect(captured.arguments == ["city": "Berlin"])
    #expect(captured.tool.name == "weather")
    #expect(captured.request.messages == request.messages)
    #expect(captured.toolContext == ["requestId": "req-1"])
}

@Test func aiResolveToolApprovalTreatsNilGenericResultAsNotApplicableLikeUpstream() async throws {
    let spy = ApprovalSpy()
    let result = try await resolveToolApproval(
        toolsByName: [
            "weather": weatherTool(needsApproval: { input, context in
                await spy.recordNeedsApproval(input: input, context: context, result: true)
            })
        ],
        toolCall: weatherToolCall(),
        arguments: ["city": "Berlin"],
        request: approvalRequest(),
        toolApproval: { context in
            await spy.recordGenericApproval(context: context, status: nil)
        }
    )

    #expect(result == .notApplicable)
    #expect(await spy.genericApprovalCount == 1)
    #expect(await spy.needsApprovalCount == 0)
}

@Test func aiResolveToolApprovalPassesThroughReasonStatusLikeUpstream() async throws {
    let result = try await resolveToolApproval(
        toolsByName: ["weather": weatherTool()],
        toolCall: weatherToolCall(),
        arguments: ["city": "Berlin"],
        request: approvalRequest(),
        toolApproval: { _ in .approved(reason: "trusted internal tool") }
    )

    #expect(result == .approved(reason: "trusted internal tool"))
}

@Test func aiResolveToolApprovalMapsToolDefinedBooleanApprovalLikeUpstream() async throws {
    let userApproval = try await resolveToolApproval(
        toolsByName: ["weather": weatherTool(needsApproval: { _, _ in true })],
        toolCall: weatherToolCall(),
        arguments: ["city": "Berlin"],
        request: approvalRequest(),
        toolApproval: nil
    )
    let notApplicable = try await resolveToolApproval(
        toolsByName: ["weather": weatherTool(needsApproval: { _, _ in false })],
        toolCall: weatherToolCall(),
        arguments: ["city": "Berlin"],
        request: approvalRequest(),
        toolApproval: nil
    )

    #expect(userApproval == .userApproval)
    #expect(notApplicable == .notApplicable)
}

@Test func aiResolveToolApprovalPassesToolInputAndValidatedContextToToolDefinedCallbackLikeUpstream() async throws {
    let spy = ApprovalSpy()
    let messages = [AIMessage.user("hello")]

    let result = try await resolveToolApproval(
        toolsByName: [
            "weather": weatherTool(
                contextSchema: [
                    "type": "object",
                    "properties": [
                        "apiKey": ["type": "string"]
                    ],
                    "required": ["apiKey"]
                ],
                needsApproval: { input, context in
                    await spy.recordNeedsApproval(input: input, context: context, result: true)
                }
            )
        ],
        toolCall: weatherToolCall(),
        arguments: ["city": "Berlin"],
        request: approvalRequest(messages: messages, toolContexts: ["weather": ["apiKey": "secret"]]),
        toolApproval: nil
    )

    let captured = try #require(await spy.lastNeedsApprovalContext)
    #expect(result == .userApproval)
    #expect(captured.input == ["city": "Berlin"])
    #expect(captured.context.toolCallID == "call-1")
    #expect(captured.context.messages == messages)
    #expect(captured.context.context == ["apiKey": "secret"])
}

@Test func aiResolveToolApprovalThrowsBeforeToolDefinedCallbackOnInvalidContextLikeUpstream() async throws {
    let spy = ApprovalSpy()

    do {
        _ = try await resolveToolApproval(
            toolsByName: [
                "weather": weatherTool(
                    contextSchema: [
                        "type": "object",
                        "properties": [
                            "apiKey": ["type": "string"]
                        ],
                        "required": ["apiKey"]
                    ],
                    needsApproval: { input, context in
                        await spy.recordNeedsApproval(input: input, context: context, result: true)
                    }
                )
            ],
            toolCall: weatherToolCall(),
            arguments: ["city": "Berlin"],
            request: approvalRequest(toolContexts: ["weather": ["apiKey": 123]]),
            toolApproval: nil
        )

        Issue.record("expected resolveToolApproval to throw")
    } catch let error as AITypeValidationError {
        #expect(error.value == ["apiKey": 123])
        #expect(error.context == AITypeValidationContext(field: "tool context", entityName: "weather"))
    }

    #expect(await spy.needsApprovalCount == 0)
}

@Test func aiExecuteToolCallsUsesToolDefinedApprovalBeforeExecutingToolLikeUpstream() async throws {
    let spy = ApprovalSpy()
    let batch = try await executeToolCalls(
        [weatherToolCall()],
        toolsByName: [
            "weather": weatherTool(
                needsApproval: { input, context in
                    await spy.recordNeedsApproval(input: input, context: context, result: true)
                },
                execute: { _ in
                    Issue.record("tool should not execute while waiting for user approval")
                    return "executed"
                }
            )
        ],
        request: approvalRequest(),
        toolApproval: nil
    )

    #expect(batch.needsUserApproval)
    #expect(batch.results.isEmpty)
    #expect(batch.approvalRequests == [
        AIToolApprovalRequest(
            id: "approval-call-1",
            toolName: "weather",
            arguments: #"{"city":"Berlin"}"#,
            toolCallID: "call-1"
        )
    ])
}

private actor ApprovalSpy {
    private var genericApprovalContexts: [AIToolApprovalContext] = []
    private var needsApprovalContexts: [(input: JSONValue, context: AIToolNeedsApprovalContext)] = []

    var genericApprovalCount: Int {
        genericApprovalContexts.count
    }

    var needsApprovalCount: Int {
        needsApprovalContexts.count
    }

    var lastGenericApprovalContext: AIToolApprovalContext? {
        genericApprovalContexts.last
    }

    var lastNeedsApprovalContext: (input: JSONValue, context: AIToolNeedsApprovalContext)? {
        needsApprovalContexts.last
    }

    func recordGenericApproval(
        context: AIToolApprovalContext,
        status: AIToolApprovalStatus?
    ) -> AIToolApprovalStatus? {
        genericApprovalContexts.append(context)
        return status
    }

    func recordNeedsApproval(
        input: JSONValue,
        context: AIToolNeedsApprovalContext,
        result: Bool
    ) -> Bool {
        needsApprovalContexts.append((input, context))
        return result
    }
}

private func weatherToolCall(context: JSONValue? = nil) -> AIToolCall {
    var metadata: [String: JSONValue] = [:]
    if let context {
        metadata["context"] = context
    }
    return AIToolCall(
        id: "call-1",
        name: "weather",
        arguments: #"{"city":"Berlin"}"#,
        providerMetadata: metadata
    )
}

private func weatherTool(
    contextSchema: JSONValue? = nil,
    needsApproval: AIToolNeedsApproval? = nil,
    execute: @escaping @Sendable (JSONValue) async throws -> JSONValue = { _ in "sunny" }
) -> AITool {
    AITool(
        name: "weather",
        parameters: [
            "type": "object",
            "properties": [
                "city": ["type": "string"]
            ],
            "required": ["city"]
        ],
        contextSchema: contextSchema,
        needsApproval: needsApproval,
        execute: execute
    )
}

private func approvalRequest(
    messages: [AIMessage] = [.user("hello")],
    toolContexts: [String: JSONValue] = [:]
) -> LanguageModelRequest {
    LanguageModelRequest(messages: messages, toolContexts: toolContexts)
}
