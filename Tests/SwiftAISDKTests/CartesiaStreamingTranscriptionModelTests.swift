import Foundation
import Testing
@testable import SwiftAISDK

@Test func cartesiaInk2StreamsTurnDetectedTranscription() async throws {
    let http = RecordingTransport(response: jsonResponse(
        #"{"token":"test-access-token"}"#
    ))
    let webSocket = TestDuplexWebSocketTransport()
    let provider = try CartesiaProvider(settings: CartesiaProviderSettings(
        apiKey: "test-api-key",
        version: "2026-03-01",
        headers: ["Custom-Provider-Header": "provider-value"],
        environment: [:],
        transport: http,
        webSocketTransport: webSocket
    ))
    let model = try provider.streamingTranscription("ink-2")
    let audio = AIStreamingAudioInput.chunks([Data([1, 2, 3])])

    let result = try await model.stream(StreamingTranscriptionRequest(
        audio: audio,
        inputAudioFormat: AIStreamingAudioFormat(
            mediaType: "audio/pcm",
            sampleRate: 16_000
        ),
        providerOptions: [
            "cartesia": .object(["language": .string("en")])
        ],
        headers: ["Custom-Request-Header": "request-value"]
    ))

    let partsTask = Task { try await collect(result.stream) }
    webSocket.connection.open()
    #expect(await waitForCondition {
        webSocket.connection.sentMessages().count >= 2
    })

    #expect(webSocket.connection.sentMessages() == [
        .binary(Data([1, 2, 3])),
        .text(#"{"type":"close"}"#)
    ])

    webSocket.connection.sendJSON(.object([
        "type": .string("turn.update"),
        "request_id": .string("turn-1"),
        "transcript": .string("Hello")
    ]))
    webSocket.connection.sendJSON(.object([
        "type": .string("turn.end"),
        "request_id": .string("turn-1"),
        "transcript": .string("Hello world")
    ]))
    webSocket.connection.sendJSON(.object([
        "type": .string("turn.end"),
        "request_id": .string("turn-2"),
        "transcript": .string("How are you?")
    ]))
    webSocket.connection.serverClose(code: 1001, reason: "server-finished")

    let parts = try await partsTask.value
    #expect(parts == [
        .streamStart(warnings: []),
        .transcriptPartial(id: "turn-1", text: "Hello"),
        .transcriptFinal(id: "turn-1", text: "Hello world"),
        .transcriptFinal(id: "turn-2", text: "How are you?"),
        .finish(StreamingTranscriptionFinish(
            text: "Hello world How are you?",
            language: "en",
            closeMetadata: AIDuplexWebSocketCloseMetadata(
                code: 1001,
                reason: "server-finished"
            )
        ))
    ])

    let httpRequests = await http.requests()
    #expect(httpRequests.count == 1)
    let tokenRequest = try #require(httpRequests.first)
    #expect(tokenRequest.url.absoluteString == "https://api.cartesia.ai/access-token")
    #expect(requestHeader(tokenRequest, "authorization") == "Bearer test-api-key")
    #expect(requestHeader(tokenRequest, "cartesia-version") == "2026-03-01")
    #expect(requestHeader(tokenRequest, "custom-provider-header") == "provider-value")
    #expect(requestHeader(tokenRequest, "custom-request-header") == "request-value")
    #expect(requestHeader(tokenRequest, "user-agent")?.contains("ai-sdk/cartesia/3.0.29") == true)
    #expect(try tokenRequestBody(tokenRequest) == .object([
        "grants": .object(["stt": .bool(true)])
    ]))

    let socketRequest = try #require(webSocket.requests().first)
    #expect(socketRequest.url.absoluteString == "wss://api.cartesia.ai/stt/turns/websocket?model=ink-2&encoding=pcm_s16le&sample_rate=16000&cartesia_version=2026-03-01&access_token=test-access-token")
    #expect(socketRequest.headers.isEmpty)
    #expect(result.requestMetadata.body == .string(
        "wss://api.cartesia.ai/stt/turns/websocket?model=ink-2&encoding=pcm_s16le&sample_rate=16000&cartesia_version=2026-03-01"
    ))
    #expect(result.responseMetadata.modelID == "ink-2")
    #expect(result.responseMetadata.timestamp != nil)
}

@Test func cartesiaInk2SupportsManualFinalization() async throws {
    let http = RecordingTransport(response: jsonResponse(
        #"{"token":"manual-token"}"#
    ))
    let webSocket = TestDuplexWebSocketTransport()
    let provider = try CartesiaProvider(settings: CartesiaProviderSettings(
        apiKey: "test-api-key",
        environment: [:],
        transport: http,
        webSocketTransport: webSocket
    ))
    let model = try provider.streamingTranscriptionModel("ink-2")
    let result = try await model.stream(StreamingTranscriptionRequest(
        audio: .chunks([Data([9])]),
        inputAudioFormat: AIStreamingAudioFormat(
            mediaType: "audio/pcmu",
            sampleRate: 8_000
        ),
        providerOptions: [
            "cartesia": .object([
                "language": .string("en"),
                "streaming": .object(["turnDetection": .bool(false)])
            ])
        ]
    ))

    let partsTask = Task { try await collect(result.stream) }
    webSocket.connection.open()
    #expect(await waitForCondition {
        webSocket.connection.sentMessages().count >= 2
    })
    #expect(webSocket.connection.sentMessages()[1] == .text("finalize"))

    let socketURL = try #require(webSocket.requests().first?.url)
    #expect(socketURL.path == "/stt/websocket")
    #expect(socketURL.queryValue("encoding") == "pcm_mulaw")
    #expect(socketURL.queryValue("sample_rate") == "8000")
    #expect(socketURL.queryValue("language") == "en")

    webSocket.connection.sendJSON(.object([
        "type": .string("transcript"),
        "request_id": .string("request-1"),
        "text": .string("Hello "),
        "is_final": .bool(true),
        "duration": .number(0.5)
    ]))
    webSocket.connection.sendJSON(.object([
        "type": .string("transcript"),
        "request_id": .string("request-1"),
        "text": .string("world"),
        "is_final": .bool(true),
        "duration": .number(0.4)
    ]))
    webSocket.connection.sendJSON(.object([
        "type": .string("flush_done"),
        "request_id": .string("request-1")
    ]))
    #expect(await waitForCondition {
        webSocket.connection.sentMessages().count >= 3
    })
    #expect(webSocket.connection.sentMessages()[2] == .text("close"))
    webSocket.connection.sendJSON(.object([
        "type": .string("done"),
        "request_id": .string("request-1")
    ]))

    let parts = try await partsTask.value
    let finish = try #require(parts.compactMap { part in
        if case let .finish(finish) = part { return finish }
        return nil
    }.last)
    #expect(finish.text == "Hello world")
    #expect(abs((finish.durationInSeconds ?? 0) - 0.9) < 0.000_001)
    #expect(finish.language == "en")
    #expect(finish.closeMetadata == .normalClosure)
    #expect(await waitForCondition {
        webSocket.connection.closeCalls().contains { $0.code == 1000 }
    })
}

@Test func cartesiaInk2SurfacesWarningsRawChunksAndProviderErrors() async throws {
    let http = RecordingTransport(response: jsonResponse(
        #"{"token":"warning-token"}"#
    ))
    let webSocket = TestDuplexWebSocketTransport()
    let provider = try CartesiaProvider(settings: CartesiaProviderSettings(
        apiKey: "test-api-key",
        environment: [:],
        transport: http,
        webSocketTransport: webSocket
    ))
    let model = try provider.streamingTranscription("ink-2")
    let result = try await model.stream(StreamingTranscriptionRequest(
        audio: .chunks([]),
        inputAudioFormat: AIStreamingAudioFormat(
            mediaType: "audio/pcmu",
            sampleRate: 8_000
        ),
        providerOptions: [
            "cartesia": .object([
                "timestampGranularities": .array([.string("word")]),
                "streaming": .object(["encoding": .string("pcm_f32le")])
            ])
        ],
        includeRawChunks: true
    ))

    var iterator = result.stream.makeAsyncIterator()
    webSocket.connection.open()
    let start = try await iterator.next()
    #expect(start == .streamStart(warnings: [
        AIWarning(
            type: "unsupported",
            feature: "providerOptions.cartesia.timestampGranularities",
            message: "Cartesia streaming transcription does not support timestamp granularities."
        ),
        AIWarning(
            type: "other",
            message: "providerOptions.cartesia.streaming.encoding 'pcm_f32le' contradicts inputAudioFormat.type 'audio/pcmu' (inferred 'pcm_mulaw'); sending 'pcm_f32le'."
        )
    ]))
    #expect(webSocket.requests().first?.url.queryValue("encoding") == "pcm_f32le")

    let rawError: JSONValue = .object([
        "type": .string("error"),
        "error_code": .string("bad_audio"),
        "message": .string("Audio could not be decoded")
    ])
    webSocket.connection.sendJSON(rawError)
    #expect(try await iterator.next() == .raw(rawError))
    do {
        _ = try await iterator.next()
        Issue.record("Expected the Cartesia provider error")
    } catch let error as AIStreamingTranscriptionError {
        #expect(error.provider == "cartesia.transcription")
        #expect(error.code == "bad_audio")
        #expect(error.message == "Audio could not be decoded")
        #expect(error.rawValue == rawError)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func cartesiaInk2ValidatesModelLanguageFormatAndOptionsBeforeNetwork() async {
    let http = RecordingTransport(response: jsonResponse(
        #"{"token":"unused"}"#
    ))
    let webSocket = TestDuplexWebSocketTransport()
    let provider: CartesiaProvider
    do {
        provider = try CartesiaProvider(settings: CartesiaProviderSettings(
            apiKey: "test-api-key",
            environment: [:],
            transport: http,
            webSocketTransport: webSocket
        ))
    } catch {
        Issue.record("Unexpected provider error: \(error)")
        return
    }

    do {
        let model = try provider.streamingTranscription("ink-whisper")
        _ = try await model.stream(StreamingTranscriptionRequest(
            audio: .chunks([]),
            inputAudioFormat: AIStreamingAudioFormat(mediaType: "audio/pcm")
        ))
        Issue.record("Expected an unsupported model error")
    } catch let AIError.invalidArgument(argument, message) {
        #expect(argument == "modelID")
        #expect(message.contains("does not support streaming transcription"))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    do {
        let model = try provider.streamingTranscription("ink-2")
        _ = try await model.stream(StreamingTranscriptionRequest(
            audio: .chunks([]),
            inputAudioFormat: AIStreamingAudioFormat(mediaType: "audio/pcm"),
            providerOptions: [
                "cartesia": .object(["language": .string("es")])
            ]
        ))
        Issue.record("Expected an unsupported language error")
    } catch let AIError.invalidArgument(_, message) {
        #expect(message == "Cartesia Ink 2 currently supports English only.")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    do {
        let model = try provider.streamingTranscription("ink-2")
        _ = try await model.stream(StreamingTranscriptionRequest(
            audio: .chunks([]),
            inputAudioFormat: AIStreamingAudioFormat(mediaType: "audio/mpeg"),
            providerOptions: [
                "cartesia": .object([
                    "streaming": .object(["encoding": .string("pcm_s16le")])
                ])
            ]
        ))
        Issue.record("Expected an unsupported media type error")
    } catch let AIError.invalidArgument(argument, message) {
        #expect(argument == "inputAudioFormat")
        #expect(message.contains("audio/mpeg"))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await http.requests().isEmpty)
    #expect(webSocket.requests().isEmpty)
}

@Test func cartesiaInk2CancellationStopsInputAndClosesSocket() async throws {
    let http = RecordingTransport(response: jsonResponse(
        #"{"token":"cancel-token"}"#
    ))
    let webSocket = TestDuplexWebSocketTransport()
    let provider = try CartesiaProvider(settings: CartesiaProviderSettings(
        apiKey: "test-api-key",
        environment: [:],
        transport: http,
        webSocketTransport: webSocket
    ))
    let model = try provider.streamingTranscription("ink-2")
    let pipe = AIStreamingAudioInput.makeStream()
    let result = try await model.stream(StreamingTranscriptionRequest(
        audio: pipe.input,
        inputAudioFormat: AIStreamingAudioFormat(
            mediaType: "audio/pcm",
            sampleRate: 16_000
        )
    ))

    var iterator = result.stream.makeAsyncIterator()
    webSocket.connection.open()
    #expect(try await iterator.next() == .streamStart(warnings: []))
    #expect(pipe.writer.send(Data([1])) == .enqueued)

    result.cancel()

    #expect(try await iterator.next() == nil)
    #expect(pipe.writer.send(Data([2])) == .terminated)
    #expect(await waitForCondition {
        webSocket.connection.closeCalls().contains { $0.code == 1000 }
    })
}

@Test func cartesiaInk2CancelsInputWhenWebSocketConnectionFails() async throws {
    let http = RecordingTransport(response: jsonResponse(
        #"{"token":"connect-token"}"#
    ))
    let webSocket = TestDuplexWebSocketTransport(
        connectError: TestWebSocketError.connectionFailed
    )
    let provider = try CartesiaProvider(settings: CartesiaProviderSettings(
        apiKey: "test-api-key",
        environment: [:],
        transport: http,
        webSocketTransport: webSocket
    ))
    let model = try provider.streamingTranscription("ink-2")
    let pipe = AIStreamingAudioInput.makeStream()

    do {
        _ = try await model.stream(StreamingTranscriptionRequest(
            audio: pipe.input,
            inputAudioFormat: AIStreamingAudioFormat(mediaType: "audio/pcm")
        ))
        Issue.record("Expected the connection failure")
    } catch let error as TestWebSocketError {
        #expect(error == .connectionFailed)
    }

    #expect(pipe.writer.send(Data([1])) == .terminated)
}

@Test func cartesiaInk2UsesStructuredAccessTokenErrors() async throws {
    let errorBody = #"{"title":"Invalid API key","message":"Authentication failed","request_id":"req-1","error_code":"unauthorized","doc_url":"https://docs.cartesia.ai"}"#
    let http = RecordingTransport(response: AIHTTPResponse(
        statusCode: 401,
        headers: ["x-request-id": "req-1"],
        body: Data(errorBody.utf8)
    ))
    let webSocket = TestDuplexWebSocketTransport()
    let provider = try CartesiaProvider(settings: CartesiaProviderSettings(
        apiKey: "bad-key",
        environment: [:],
        transport: http,
        webSocketTransport: webSocket
    ))
    let model = try provider.streamingTranscription("ink-2")

    do {
        _ = try await model.stream(StreamingTranscriptionRequest(
            audio: .chunks([]),
            inputAudioFormat: AIStreamingAudioFormat(mediaType: "audio/pcm")
        ))
        Issue.record("Expected the access-token API error")
    } catch let AIError.apiCall(error) {
        #expect(error.statusCode == 401)
        #expect(error.responseBody == "Invalid API key: Authentication failed")
        #expect(error.responseHeaders["x-request-id"] == "req-1")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(webSocket.requests().isEmpty)
}

private func collect(
    _ stream: AsyncThrowingStream<StreamingTranscriptionPart, Error>
) async throws -> [StreamingTranscriptionPart] {
    var parts: [StreamingTranscriptionPart] = []
    for try await part in stream {
        parts.append(part)
    }
    return parts
}

private func tokenRequestBody(_ request: AIHTTPRequest) throws -> JSONValue {
    try JSONDecoder().decode(
        JSONValue.self,
        from: try #require(request.body)
    )
}

private func requestHeader(
    _ request: AIHTTPRequest,
    _ name: String
) -> String? {
    request.headers.first {
        $0.key.caseInsensitiveCompare(name) == .orderedSame
    }?.value
}

private func waitForCondition(
    _ condition: @escaping @Sendable () -> Bool
) async -> Bool {
    for _ in 0..<10_000 {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}

private extension URL {
    func queryValue(_ name: String) -> String? {
        URLComponents(
            url: self,
            resolvingAgainstBaseURL: false
        )?.queryItems?.first { $0.name == name }?.value
    }
}

private enum TestWebSocketError: Error, Equatable, Sendable {
    case connectionFailed
}

private final class TestDuplexWebSocketTransport:
    AIDuplexWebSocketTransport,
    @unchecked Sendable {
    let connection = TestDuplexWebSocketConnection()

    private let lock = NSLock()
    private let connectError: TestWebSocketError?
    private var recordedRequests: [AIDuplexWebSocketRequest] = []

    init(connectError: TestWebSocketError? = nil) {
        self.connectError = connectError
    }

    func connect(
        _ request: AIDuplexWebSocketRequest
    ) async throws -> any AIDuplexWebSocketConnection {
        record(request)
        if let connectError { throw connectError }
        return connection
    }

    func requests() -> [AIDuplexWebSocketRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    private func record(_ request: AIDuplexWebSocketRequest) {
        lock.lock()
        recordedRequests.append(request)
        lock.unlock()
    }
}

private final class TestDuplexWebSocketConnection:
    AIDuplexWebSocketConnection,
    @unchecked Sendable {
    let events: AsyncThrowingStream<AIDuplexWebSocketEvent, Error>

    private let continuation:
        AsyncThrowingStream<AIDuplexWebSocketEvent, Error>.Continuation
    private let lock = NSLock()
    private var sent: [AIDuplexWebSocketMessage] = []
    private var closes: [(code: Int, reason: Data?)] = []

    init() {
        let pair = AsyncThrowingStream<AIDuplexWebSocketEvent, Error>
            .makeStream()
        events = pair.stream
        continuation = pair.continuation
    }

    func send(_ message: AIDuplexWebSocketMessage) async throws {
        record(message)
    }

    func close(code: Int, reason: Data?) async {
        recordClose(code: code, reason: reason)
        continuation.finish()
    }

    func open(protocol: String? = nil) {
        continuation.yield(.opened(protocol: `protocol`))
    }

    func sendJSON(_ value: JSONValue) {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else {
            Issue.record("Could not encode fake WebSocket JSON")
            return
        }
        continuation.yield(.message(.text(text)))
    }

    func serverClose(code: Int, reason: String? = nil) {
        continuation.yield(.closed(AIDuplexWebSocketCloseMetadata(
            code: code,
            reason: reason
        )))
        continuation.finish()
    }

    func sentMessages() -> [AIDuplexWebSocketMessage] {
        lock.lock()
        defer { lock.unlock() }
        return sent
    }

    func closeCalls() -> [(code: Int, reason: Data?)] {
        lock.lock()
        defer { lock.unlock() }
        return closes
    }

    private func record(_ message: AIDuplexWebSocketMessage) {
        lock.lock()
        sent.append(message)
        lock.unlock()
    }

    private func recordClose(code: Int, reason: Data?) {
        lock.lock()
        closes.append((code, reason))
        lock.unlock()
    }
}
