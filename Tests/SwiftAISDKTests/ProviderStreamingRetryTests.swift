import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIProviderRetriesChunkedHTTPErrorBeforeFirstStreamPart() async throws {
    let transport = SequencedStreamingTransport(responses: [
        incrementalHTTPResponse(
            statusCode: 429,
            headers: ["retry-after": "0", "content-type": "application/json"],
            chunks: [
                Data("{\"error\":{\"message\":\"rate ".utf8),
                Data("limited\",\"type\":\"rate_limit_error\"}}".utf8)
            ]
        ),
        incrementalHTTPResponse(
            chunks: [Data("""
            data: {"choices":[{"delta":{"content":"recovered"},"finish_reason":"stop"}]}

            data: [DONE]

            """.utf8)]
        )
    ])
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.chatModel("gpt-4.1-mini")

    var deltas: [String] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "Retry the request",
        retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 0)
    ) {
        if case let .textDelta(delta) = part {
            deltas.append(delta)
        }
    }

    #expect(deltas == ["recovered"])
    #expect(await transport.streamRequestCount() == 2)
    #expect(await transport.sendRequestCount() == 0)
}

@Test func openAIProviderDoesNotRetryMidstreamFailureAfterFirstPart() async throws {
    let failure = AIError.apiCall(
        provider: "openai.chat",
        statusCode: 503,
        body: "interrupted"
    )
    let failureGate = StreamingFailureGate()
    let transport = SequencedStreamingTransport(responses: [
        incrementalHTTPResponse(
            chunks: [Data("data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n".utf8)],
            terminalError: failure,
            failureGate: failureGate
        ),
        incrementalHTTPResponse(
            chunks: [Data("""
            data: {"choices":[{"delta":{"content":"duplicate"},"finish_reason":"stop"}]}

            data: [DONE]

            """.utf8)]
        )
    ])
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.chatModel("gpt-4.1-mini")

    var deltas: [String] = []
    do {
        for try await part in AI.streamText(
            model: model,
            prompt: "Do not duplicate",
            retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 0)
        ) {
            if case let .textDelta(delta) = part {
                deltas.append(delta)
                failureGate.open()
            }
        }
        Issue.record("Expected the provider body to fail after its first delta.")
    } catch let error as AIError {
        #expect(error == failure)
    }

    #expect(deltas == ["partial"])
    #expect(await transport.streamRequestCount() == 1)
    #expect(await transport.sendRequestCount() == 0)
}

private actor SequencedStreamingTransport: AIStreamingTransport {
    private var responses: [AIHTTPStreamResponse]
    private var streamRequests: [AIHTTPRequest] = []
    private var sendRequests: [AIHTTPRequest] = []

    init(responses: [AIHTTPStreamResponse]) {
        self.responses = responses
    }

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        sendRequests.append(request)
        throw SequencedStreamingTransportError.unexpectedBufferedSend
    }

    func stream(_ request: AIHTTPRequest) async throws -> AIHTTPStreamResponse {
        streamRequests.append(request)
        guard !responses.isEmpty else {
            throw SequencedStreamingTransportError.missingResponse
        }
        return responses.removeFirst()
    }

    func streamRequestCount() -> Int {
        streamRequests.count
    }

    func sendRequestCount() -> Int {
        sendRequests.count
    }
}

private enum SequencedStreamingTransportError: Error {
    case unexpectedBufferedSend
    case missingResponse
}

private final class StreamingFailureGate: @unchecked Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        stream = pair.stream
        continuation = pair.continuation
    }

    func open() {
        continuation.yield(())
        continuation.finish()
    }

    func wait() async {
        for await _ in stream {
            return
        }
    }
}

private func incrementalHTTPResponse(
    statusCode: Int = 200,
    headers: [String: String] = ["content-type": "text/event-stream"],
    chunks: [Data],
    terminalError: AIError? = nil,
    failureGate: StreamingFailureGate? = nil
) -> AIHTTPStreamResponse {
    AIHTTPStreamResponse(
        statusCode: statusCode,
        headers: headers,
        body: AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            if let terminalError {
                Task {
                    if let failureGate {
                        await failureGate.wait()
                    }
                    continuation.finish(throwing: terminalError)
                }
            } else {
                continuation.finish()
            }
        }
    )
}
