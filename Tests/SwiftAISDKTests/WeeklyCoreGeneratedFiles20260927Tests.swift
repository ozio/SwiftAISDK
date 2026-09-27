import Foundation
import Testing
@testable import SwiftAISDK

@Suite("WeeklyCoreGeneratedFiles20260927Tests")
struct WeeklyCoreGeneratedFiles20260927Tests {
    @Test func generateAndStreamTextMaterializeDataURLFiles() async throws {
        let generatedFile = AIStreamFile(
            id: "file-1",
            mediaType: "application/octet-stream",
            url: "data:application/octet-stream;base64,AQID"
        )
        let generateModel = MockLanguageModel(result: TextGenerationResult(
            text: "",
            content: [.file(generatedFile)],
            finishReason: "stop",
            rawValue: [:]
        ))

        let generated = try await AI.generateText(
            model: generateModel,
            request: LanguageModelRequest(messages: [.user("generate a file")]),
            retryPolicy: .none
        )
        guard case let .file(materialized)? = generated.content.first else {
            Issue.record("Expected a materialized generated file.")
            return
        }
        #expect(materialized.data == Data([1, 2, 3]))
        #expect(materialized.url == nil)

        let streamModel = MockLanguageModel(
            result: TextGenerationResult(text: "", rawValue: [:]),
            streamParts: [
                .file(generatedFile),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 1))
            ]
        )
        var streamedFile: AIStreamFile?
        for try await part in AI.streamText(
            model: streamModel,
            request: LanguageModelRequest(messages: [.user("stream a file")]),
            retryPolicy: .none
        ) {
            if case let .file(file) = part {
                streamedFile = file
            }
        }
        #expect(streamedFile?.data == Data([1, 2, 3]))
        #expect(streamedFile?.url == nil)
    }

    @Test func providerBatchMaterializesDataURLFiles() async throws {
        let provider = Weekly20260927GeneratedFileBatchProvider()
        let stream = try AI.getBatchResults(
            provider: provider,
            batch: AIBatchReference(id: "batch-1", providerID: provider.providerID),
            retryPolicy: .none
        )

        var materialized: AIStreamFile?
        for try await item in stream {
            guard case let .text(.succeeded(_, result)) = item else {
                Issue.record("Expected a successful text batch item.")
                continue
            }
            if case let .file(file)? = result.content.first {
                materialized = file
            }
        }

        #expect(materialized?.data == Data([1, 2, 3]))
        #expect(materialized?.url == nil)
    }

    @Test func uiStreamConsumerCancellationEndsOnceAsCancelledUnknown() async throws {
        let source = AsyncThrowingStream<LanguageStreamPart, Error>.makeStream()
        let capture = Weekly20260927CancellationEndCapture()
        let snapshots = AIUIMessageStreamReducer.snapshots(
            from: source.stream,
            messageID: "cancelled-message",
            onEnd: { await capture.record($0) }
        )
        let consumer = Task {
            do {
                for try await _ in snapshots {}
            } catch {
                Issue.record("Consumer cancellation should not surface as a stream error: \(error)")
            }
        }

        source.continuation.yield(.textStart(id: "answer"))
        await Task.yield()
        consumer.cancel()
        _ = await consumer.result
        #expect(await weekly20260927WaitForEndEvent(capture))

        let events = await capture.events()
        #expect(events.count == 1)
        #expect(events.first?.outcome == .unknown)
        #expect(events.first?.isCancelled == true)
        #expect(events.first?.isAborted == false)
        source.continuation.finish()
    }

    @MainActor
    @Test func successfulApprovalContinuationIsNotResumedTwice() async {
        let toolCall = AIToolCall(id: "call-1", name: "weather", arguments: #"{"city":"Tokyo"}"#)
        let approval = AIToolApprovalRequest(
            id: "approval-1",
            toolName: "weather",
            arguments: toolCall.arguments,
            toolCallID: toolCall.id
        )
        let transport = Weekly20260927ApprovalChatTransport(
            completedMessage: .assistant(
                id: "assistant-approval",
                parts: [
                    .toolCall(toolCall),
                    .toolApprovalRequest(approval),
                    .toolResult(AIToolResult(
                        toolCallID: toolCall.id,
                        toolName: toolCall.name,
                        result: ["temperature": 22]
                    ))
                ]
            )
        )
        let ids = Weekly20260927MessageIDGenerator()
        let session = AIChatSession(
            transport: transport,
            messages: [
                .user("Weather?", id: "user-1"),
                .assistant(
                    id: "assistant-approval",
                    parts: [.toolCall(toolCall), .toolApprovalRequest(approval)]
                )
            ],
            generateMessageID: { ids.next() }
        )

        session.addToolApprovalResponse(AIToolApprovalResponse(id: approval.id, approved: true))
        await session.sendMessage().value
        await session.sendMessage().value

        let requests = transport.requests()
        #expect(requests.count == 2)
        #expect(requests[0].messageID == "assistant-approval")
        #expect(requests[1].messageID == "generated-1")
    }
}

private actor Weekly20260927GeneratedFileBatchProvider: AIBatchProvider {
    nonisolated let providerID = "weekly.generated-file-batch"

    func startBatch(_ options: AIBatchStartOptions<AIBatchRequest>) async throws -> AIBatchStartResult {
        AIBatchStartResult(batchID: "batch-1", status: AIBatchStatus(status: .pending))
    }

    func getBatchStatus(_ options: AIBatchOperationOptions) async throws -> AIBatchStatus {
        AIBatchStatus(status: .completed)
    }

    func getBatchResults(
        _ options: AIBatchOperationOptions
    ) async throws -> AsyncThrowingStream<AIBatchV4ItemResult, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.text(.succeeded(
                id: "item-1",
                result: TextGenerationResult(
                    text: "",
                    content: [.file(AIStreamFile(
                        mediaType: "application/octet-stream",
                        url: "data:application/octet-stream;base64,AQID"
                    ))],
                    finishReason: "stop",
                    rawValue: [:]
                )
            )))
            continuation.finish()
        }
    }
}

private actor Weekly20260927CancellationEndCapture {
    private var values: [AIUIMessageStreamEndEvent] = []

    func record(_ event: AIUIMessageStreamEndEvent) {
        values.append(event)
    }

    func events() -> [AIUIMessageStreamEndEvent] {
        values
    }
}

private func weekly20260927WaitForEndEvent(
    _ capture: Weekly20260927CancellationEndCapture,
    attempts: Int = 200
) async -> Bool {
    for _ in 0..<attempts {
        if await !capture.events().isEmpty {
            return true
        }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return await !capture.events().isEmpty
}

private final class Weekly20260927ApprovalChatTransport: AIChatTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let completedMessage: AIUIMessage
    private var recordedRequests: [AIChatTransportRequest] = []

    init(completedMessage: AIUIMessage) {
        self.completedMessage = completedMessage
    }

    func sendMessages(
        _ request: AIChatTransportRequest
    ) throws -> AsyncThrowingStream<AIUIMessage, Error> {
        let shouldYieldCompletedMessage = lock.withLock { () -> Bool in
            recordedRequests.append(request)
            return recordedRequests.count == 1
        }
        return AsyncThrowingStream { continuation in
            if shouldYieldCompletedMessage {
                continuation.yield(completedMessage)
            }
            continuation.finish()
        }
    }

    func requests() -> [AIChatTransportRequest] {
        lock.withLock { recordedRequests }
    }
}

private final class Weekly20260927MessageIDGenerator: @unchecked Sendable {
    private let lock = NSLock()
    private var nextValue = 1

    func next() -> String {
        lock.withLock {
            defer { nextValue += 1 }
            return "generated-\(nextValue)"
        }
    }
}
