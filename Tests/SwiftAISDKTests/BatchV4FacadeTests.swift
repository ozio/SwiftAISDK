import Foundation
import Testing
@testable import SwiftAISDK

@Test func batchRequestCountNormalizerAcceptsOnlyConsistentNonnegativeSafeIntegers() {
    let maximum = aiBatchMaximumSafeInteger

    #expect(normalizedBatchJSONInteger(.number(Double(maximum))) == maximum)
    #expect(normalizedBatchJSONInteger(.number(Double(maximum) + 1)) == nil)
    #expect(normalizedBatchJSONInteger(.number(-1)) == nil)
    #expect(normalizedBatchJSONInteger(.number(0.5)) == nil)
    #expect(normalizedBatchJSONInteger(.number(.infinity)) == nil)
    #expect(normalizedBatchJSONInteger(.string("1")) == nil)

    #expect(normalizedBatchRequestCounts(
        total: maximum,
        pending: maximum,
        completed: 0,
        failed: 0
    ) == AIBatchRequestCounts(total: maximum, pending: maximum, completed: 0, failed: 0))
    #expect(normalizedBatchRequestCounts(
        total: maximum,
        pending: maximum,
        completed: 1,
        failed: 0
    ) == nil)
    #expect(normalizedBatchRequestCounts(total: 2, pending: 0, completed: 1, failed: 0) == nil)
}

@Test func batchV4FacadeNormalizesRequestsAndForwardsOperationMetadata() async throws {
    let model = BatchFacadeMockModel()
    model.startResult = AIBatchStartResult(
        batchID: "batch-456",
        status: AIBatchStatus(
            status: .pending,
            rawStatus: "validating",
            requestCounts: AIBatchRequestCounts(total: 1, pending: 1, completed: 0, failed: 0),
            createdAt: "2026-08-03T12:00:00.000Z"
        )
    )

    let result = try await AI.startTextBatch(
        model: model,
        requests: [
            TextBatchRequest(
                id: "request-1",
                request: LanguageModelRequest(
                    messages: [.user("What is the capital of France?")],
                    temperature: 0,
                    maxOutputTokens: 100,
                    responseFormat: .json(
                        schema: ["type": "object", "properties": ["answer": ["type": "string"]]],
                        name: "answer"
                    ),
                    tools: [
                        "lookup": [
                            "type": "object",
                            "properties": ["query": ["type": "string"]]
                        ]
                    ],
                    toolChoice: ["type": "tool", "toolName": "lookup"],
                    providerOptions: ["mock": ["perRequest": true]]
                )
            )
        ],
        providerOptions: ["mock": ["batch": true]],
        headers: ["x-test": "test-value"],
        idempotencyKey: "stable-create-key",
        webhookURL: "https://example.com/batches/complete"
    )

    #expect(result.batch.reference == TextBatchReference(
        id: "batch-456",
        providerID: "mock-provider",
        modelID: "mock-model-id"
    ))
    #expect(result.batch.status.rawStatus == "validating")
    let options = try #require(model.capturedStartOptions())
    #expect(options.requests.count == 1)
    #expect(options.requests[0].id == "request-1")
    #expect(options.requests[0].request.messages == [.user("What is the capital of France?")])
    #expect(options.requests[0].request.temperature == 0)
    #expect(options.requests[0].request.maxOutputTokens == 100)
    #expect(options.requests[0].request.responseFormat == .json(
        schema: ["type": "object", "properties": ["answer": ["type": "string"]]],
        name: "answer"
    ))
    #expect(options.requests[0].request.tools["lookup"]?["properties"]?["query"]?["type"]?.stringValue == "string")
    #expect(options.requests[0].request.toolChoice?["toolName"]?.stringValue == "lookup")
    #expect(options.providerOptions == ["mock": ["batch": true]])
    #expect(options.headers["x-test"] == "test-value")
    #expect(options.headers["user-agent"] == "ai/7.0.85")
    #expect(options.headers["idempotency-key"] == "stable-create-key")
    #expect(options.idempotencyKey == "stable-create-key")
    #expect(options.webhookURL == "https://example.com/batches/complete")
}

@Test func batchV4FacadeRejectsInvalidRequestsAndIncompatibleReferences() async throws {
    let model = BatchFacadeMockModel()

    await #expect(throws: AIError.self) {
        try await AI.startTextBatch(model: model, requests: [])
    }
    await #expect(throws: AIError.self) {
        try await AI.startTextBatch(model: model, requests: [
            TextBatchRequest(id: "duplicate", request: LanguageModelRequest(messages: [.user("one")])),
            TextBatchRequest(id: "duplicate", request: LanguageModelRequest(messages: [.user("two")]))
        ])
    }
    await #expect(throws: AIError.self) {
        try await AI.getBatchStatus(
            model: model,
            batch: TextBatchReference(
                id: "batch-1",
                providerID: "mock-provider",
                modelID: "different-model"
            ),
            retryPolicy: .none
        )
    }
}

@Test func batchV4FacadeStreamsNormalizedTerminalItems() async throws {
    let model = BatchFacadeMockModel()
    model.resultItems = [
        .succeeded(
            id: "request-1",
            result: TextGenerationResult(
                text: "Paris",
                content: [.text("Par"), .text("is")],
                finishReason: "stop",
                usage: TokenUsage(inputTokens: 3, outputTokens: 5, totalTokens: 8),
                providerMetadata: ["mock": ["result": true]],
                rawValue: ["stop_reason": "end_turn"],
                responseMetadata: AIResponseMetadata(id: "response-1", modelID: "provider-model-id")
            )
        ),
        .failed(
            id: "request-2",
            error: AIBatchError(message: "request failed", code: "bad_request")
        ),
        .cancelled(id: "request-3"),
        .expired(id: "request-4")
    ]

    let stream = try AI.getBatchResults(
        model: model,
        batch: TextBatchReference(
            id: "batch-123",
            providerID: model.providerID,
            modelID: model.modelID
        ),
        retryPolicy: .none
    )
    var items: [TextBatchItemResult] = []
    for try await item in stream {
        items.append(item)
    }

    #expect(items.count == 4)
    guard case let .succeeded(id, result) = items[0] else {
        Issue.record("Expected succeeded item")
        return
    }
    #expect(id == "request-1")
    #expect(result.text == "Paris")
    #expect(result.content == [.text("Par"), .text("is")])
    #expect(result.finishReason == "stop")
    #expect(result.rawFinishReason == "end_turn")
    #expect(result.usage.totalTokens == 8)
    #expect(result.response?.id == "response-1")
    guard case let .failed(failedID, error, _) = items[1] else {
        Issue.record("Expected failed item")
        return
    }
    #expect(failedID == "request-2")
    #expect(error.code == "bad_request")
    guard case .cancelled(id: "request-3", error: nil, providerMetadata: _) = items[2] else {
        Issue.record("Expected cancelled item")
        return
    }
    guard case .expired(id: "request-4", error: nil, providerMetadata: _) = items[3] else {
        Issue.record("Expected expired item")
        return
    }
}

@Test func batchV4FacadePropagatesAnAlreadyAbortedSignalBeforeProviderWork() async throws {
    let model = BatchFacadeMockModel()
    let controller = AIAbortController()
    controller.abort(reason: "cancel batch")

    await #expect(throws: AIAbortError.self) {
        try await AI.startTextBatch(
            model: model,
            requests: [
                TextBatchRequest(id: "request-1", request: LanguageModelRequest(messages: [.user("hello")]))
            ],
            abortSignal: controller.signal
        )
    }
    #expect(model.capturedStartOptions() == nil)
}

private final class BatchFacadeMockModel: BatchLanguageModel, @unchecked Sendable {
    let providerID = "mock-provider"
    let modelID = "mock-model-id"
    var startResult = AIBatchStartResult(
        batchID: "batch-123",
        status: AIBatchStatus(status: .pending)
    )
    var statusResult = AIBatchStatus(status: .pending)
    var resultItems: [AIBatchItemResult<TextGenerationResult>] = []

    private let lock = NSLock()
    private var startOptions: AIBatchStartOptions<AILanguageModelBatchRequest>?

    func capturedStartOptions() -> AIBatchStartOptions<AILanguageModelBatchRequest>? {
        lock.withLock { startOptions }
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        throw AIError.invalidArgument(argument: "generate", message: "not used by batch tests")
    }

    func startBatch(
        _ options: AIBatchStartOptions<AILanguageModelBatchRequest>
    ) async throws -> AIBatchStartResult {
        lock.withLock { startOptions = options }
        return startResult
    }

    func getBatchStatus(_ options: AIBatchOperationOptions) async throws -> AIBatchStatus {
        statusResult
    }

    func getBatchResults(
        _ options: AIBatchOperationOptions
    ) async throws -> AsyncThrowingStream<AIBatchItemResult<TextGenerationResult>, Error> {
        let resultItems = self.resultItems
        return AsyncThrowingStream { continuation in
            for item in resultItems {
                continuation.yield(item)
            }
            continuation.finish()
        }
    }
}
