import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiSimulateStreamingMiddlewareStreamsTextReasoningAndWarningsLikeUpstream() async throws {
    let warning = AIWarning(type: "other", message: "Test warning")
    let model = SimulateStreamingUpstreamLanguageModel(result: TextGenerationResult(
        text: "This is a test response",
        reasoning: "This is the reasoning process",
        finishReason: "stop",
        usage: testSimulateStreamingUsage,
        rawValue: .object([:]),
        warnings: [warning]
    ))
    let wrapped = wrapLanguageModel(model, middleware: simulateStreamingMiddleware())

    #expect(try await collectSimulatedStream(wrapped.stream(LanguageModelRequest(messages: [.user("Test prompt")]))) == [
        .streamStart(warnings: [warning]),
        .reasoningStart(id: "0"),
        .reasoningDeltaPart(id: "0", delta: "This is the reasoning process"),
        .reasoningEnd(id: "0"),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "This is a test response"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: testSimulateStreamingUsage)
    ])
    #expect(model.generateRequests.count == 1)
    #expect(model.streamRequests.isEmpty)
}

@Test func aiSimulateStreamingMiddlewareStreamsToolAndApprovalPartsLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "tool-1", name: "calculator", arguments: #"{"expression":"2+2"}"#)
    let toolResult = AIToolResult(toolCallID: "tool-1", toolName: "calculator", result: ["value": 4])
    let approvalRequest = AIToolApprovalRequest(
        id: "approval-1",
        toolName: "calculator",
        arguments: #"{"expression":"2+2"}"#,
        toolCallID: "tool-1"
    )
    let approvalResponse = AIToolApprovalResponse(id: "approval-1", approved: true)
    let model = SimulateStreamingUpstreamLanguageModel(result: TextGenerationResult(
        text: "This is a test response",
        finishReason: "tool-calls",
        usage: testSimulateStreamingUsage,
        toolCalls: [toolCall],
        toolResults: [toolResult],
        toolApprovalRequests: [approvalRequest],
        toolApprovalResponses: [approvalResponse],
        rawValue: .object([:])
    ))
    let wrapped = wrapLanguageModel(model, middleware: simulateStreamingMiddleware())

    #expect(try await collectSimulatedStream(wrapped.stream(LanguageModelRequest(messages: [.user("Test prompt")]))) == [
        .streamStart(warnings: []),
        .textStart(id: "0"),
        .textDeltaPart(id: "0", delta: "This is a test response"),
        .textEnd(id: "0"),
        .toolCall(toolCall),
        .toolApprovalRequest(approvalRequest),
        .toolApprovalResponse(approvalResponse),
        .toolResult(toolResult),
        .finish(reason: "tool-calls", usage: testSimulateStreamingUsage)
    ])
}

@Test func aiSimulateStreamingMiddlewarePreservesProviderMetadataLikeUpstream() async throws {
    let providerMetadata: [String: JSONValue] = ["custom": ["key": "value"]]
    let model = SimulateStreamingUpstreamLanguageModel(result: TextGenerationResult(
        text: "This is a test response",
        finishReason: "stop",
        usage: testSimulateStreamingUsage,
        providerMetadata: providerMetadata,
        rawValue: .object([:])
    ))
    let wrapped = wrapLanguageModel(model, middleware: simulateStreamingMiddleware())

    #expect(try await collectSimulatedStream(wrapped.stream(LanguageModelRequest(messages: [.user("Test prompt")]))) == [
        .streamStart(warnings: []),
        .textStart(id: "0"),
        .textDeltaPart(id: "0", delta: "This is a test response"),
        .textEnd(id: "0"),
        .finishMetadata(reason: "stop", usage: testSimulateStreamingUsage, providerMetadata: providerMetadata)
    ])
}

@Test func aiSimulateStreamingMiddlewareSkipsEmptyTextLikeUpstream() async throws {
    let model = SimulateStreamingUpstreamLanguageModel(result: TextGenerationResult(
        text: "",
        finishReason: "stop",
        usage: testSimulateStreamingUsage,
        rawValue: .object([:])
    ))
    let wrapped = wrapLanguageModel(model, middleware: simulateStreamingMiddleware())

    #expect(try await collectSimulatedStream(wrapped.stream(LanguageModelRequest(messages: [.user("Test prompt")]))) == [
        .streamStart(warnings: []),
        .finish(reason: "stop", usage: testSimulateStreamingUsage)
    ])
}

private let testSimulateStreamingUsage = TokenUsage(
    inputTokens: 5,
    outputTokens: 10,
    totalTokens: 15,
    inputTokensNoCache: 5,
    inputTokensCacheRead: 0,
    inputTokensCacheWrite: 0,
    outputTextTokens: 10,
    outputReasoningTokens: 3
)

private final class SimulateStreamingUpstreamLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-model-id"
    var generateRequests: [LanguageModelRequest] = []
    var streamRequests: [LanguageModelRequest] = []
    private let result: TextGenerationResult

    init(result: TextGenerationResult) {
        self.result = result
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        generateRequests.append(request)
        return result
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamRequests.append(request)
        return AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private func collectSimulatedStream(
    _ stream: AsyncThrowingStream<LanguageStreamPart, Error>
) async throws -> [LanguageStreamPart] {
    var parts: [LanguageStreamPart] = []
    for try await part in stream {
        parts.append(part)
    }
    return parts
}
