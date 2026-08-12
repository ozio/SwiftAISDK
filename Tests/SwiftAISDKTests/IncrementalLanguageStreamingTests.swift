import Foundation
import Network
import Testing
@testable import SwiftAISDK

@Test func openAIStreamUsesStreamingTransportInsteadOfBufferedSend() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"choices":[{"delta":{"content":"hello"},"finish_reason":"stop"}]}

    data: [DONE]

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.chatModel("gpt-4.1-mini")

    var text = ""
    var legacyTextDeltaCount = 0
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        if case let .textDeltaPart(_, delta, _) = part {
            text += delta
        } else if case .textDelta = part {
            legacyTextDeltaCount += 1
        }
    }

    #expect(text == "hello")
    #expect(legacyTextDeltaCount == 0)
    #expect(await transport.sendRequests().isEmpty)
    #expect(await transport.streamRequests().count == 1)
}

@Test func sendOnlyCustomTransportSupportsGenerateButRejectsStreaming() async throws {
    let transport = SendOnlyLanguageTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"generated"},"finish_reason":"stop"}]}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.chatModel("gpt-4.1-mini")

    let generated = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))
    #expect(generated.text == "generated")

    do {
        for try await _ in model.stream(LanguageModelRequest(messages: [.user("Hi again")])) {}
        Issue.record("Expected streaming to reject a send-only transport.")
    } catch let AIError.invalidArgument(argument, message) {
        #expect(argument == "transport")
        #expect(message.contains("AIStreamingTransport"))
    } catch {
        Issue.record("Expected AIError.invalidArgument, got \(error).")
    }

    #expect(await transport.sendCount() == 1)
}

@Test(.timeLimit(.minutes(1)))
func urlSessionLanguageStreamDeliversDeltaAndFinishesOnDoneBeforeHTTPEOF() async throws {
    let server = try await LoopbackSSEServer.start()
    defer { server.stop() }

    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        baseURL: "http://127.0.0.1:\(server.port)/v1",
        transport: URLSessionTransport(session: URLSession(configuration: .ephemeral))
    ))
    let model = try provider.chatModel("gpt-4.1-mini")
    let firstDelta = OneShot<String>()

    let streamTask = Task {
        for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
            if case let .textDeltaPart(_, delta, _) = part {
                firstDelta.signal(delta)
            }
        }
    }
    defer { streamTask.cancel() }

    let delta = try await incrementalStreamingTimeout {
        try await firstDelta.value()
    }
    #expect(delta == "hello-before-eof")
    #expect(!server.didSendHTTPBodyTerminator)

    try server.sendDoneWithoutEOF()
    _ = try await incrementalStreamingTimeout(onTimeout: { streamTask.cancel() }) {
        try await streamTask.value
    }
    _ = try await incrementalStreamingTimeout {
        try await server.waitForPeerClose()
    }
    #expect(!server.didSendHTTPBodyTerminator)
}

@Test(.timeLimit(.minutes(1)))
func cancellingLanguageStreamConsumerClosesURLSessionBodyBeforeHTTPEOF() async throws {
    let server = try await LoopbackSSEServer.start()
    defer { server.stop() }

    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        baseURL: "http://127.0.0.1:\(server.port)/v1",
        transport: URLSessionTransport(session: URLSession(configuration: .ephemeral))
    ))
    let model = try provider.chatModel("gpt-4.1-mini")
    let firstDelta = OneShot<String>()
    let streamTask = Task {
        for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
            if case let .textDeltaPart(_, delta, _) = part {
                firstDelta.signal(delta)
            }
        }
    }
    defer { streamTask.cancel() }

    #expect(try await incrementalStreamingTimeout { try await firstDelta.value() } == "hello-before-eof")
    streamTask.cancel()
    _ = try await incrementalStreamingTimeout(onTimeout: { streamTask.cancel() }) {
        do {
            try await streamTask.value
        } catch is CancellationError {
            // Expected cancellation surface.
        } catch let error as URLError where error.code == .cancelled {
            // URLSession may surface the cancelled body directly.
        }
    }
    _ = try await incrementalStreamingTimeout {
        try await server.waitForPeerClose()
    }
    #expect(!server.didSendHTTPBodyTerminator)
}

@Test(.timeLimit(.minutes(1)))
func abortingLanguageStreamAfterHeadersPreservesReasonAndClosesPeer() async throws {
    let server = try await LoopbackSSEServer.start()
    defer { server.stop() }

    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        baseURL: "http://127.0.0.1:\(server.port)/v1",
        transport: URLSessionTransport(session: URLSession(configuration: .ephemeral))
    ))
    let model = try provider.chatModel("gpt-4.1-mini")
    let controller = AIAbortController()
    let firstDelta = OneShot<String>()
    let streamTask = Task {
        for try await part in model.stream(LanguageModelRequest(
            messages: [.user("Hi")],
            abortSignal: controller.signal
        )) {
            if case let .textDeltaPart(_, delta, _) = part {
                firstDelta.signal(delta)
            }
        }
    }
    defer { streamTask.cancel() }

    #expect(try await incrementalStreamingTimeout { try await firstDelta.value() } == "hello-before-eof")
    controller.abort(reason: "stop after headers", reasonName: "AbortError")

    do {
        _ = try await incrementalStreamingTimeout(onTimeout: { streamTask.cancel() }) {
            try await streamTask.value
        }
        Issue.record("Expected the aborted response body to throw AIAbortError.")
    } catch let error as AIAbortError {
        #expect(error.reason == "stop after headers")
        #expect(error.reasonName == "AbortError")
    } catch {
        Issue.record("Expected AIAbortError, got \(error).")
    }

    _ = try await incrementalStreamingTimeout {
        try await server.waitForPeerClose()
    }
    #expect(!server.didSendHTTPBodyTerminator)
}

private actor SendOnlyLanguageTransport: AITransport {
    private let response: AIHTTPResponse
    private var count = 0

    init(response: AIHTTPResponse) {
        self.response = response
    }

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        count += 1
        return response
    }

    func sendCount() -> Int {
        count
    }
}

private final class OneShot<Value: Sendable>: @unchecked Sendable {
    private let stream: AsyncStream<Value>
    private let continuation: AsyncStream<Value>.Continuation

    init() {
        let pair = AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.stream = pair.stream
        self.continuation = pair.continuation
    }

    func signal(_ value: Value) {
        continuation.yield(value)
        continuation.finish()
    }

    func value() async throws -> Value {
        var iterator = stream.makeAsyncIterator()
        guard let value = await iterator.next() else {
            throw CancellationError()
        }
        return value
    }
}

private struct IncrementalStreamingTestTimeout: Error, Sendable {}

private func incrementalStreamingTimeout<Value: Sendable>(
    nanoseconds: UInt64 = 5_000_000_000,
    onTimeout: @escaping @Sendable () -> Void = {},
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            try await Task.sleep(nanoseconds: nanoseconds)
            onTimeout()
            throw IncrementalStreamingTestTimeout()
        }
        defer { group.cancelAll() }
        guard let value = try await group.next() else {
            throw CancellationError()
        }
        return value
    }
}

private final class LoopbackSSEServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "SwiftAISDKTests.LoopbackSSEServer")
    private let ready = OneShot<UInt16>()
    private let peerClosed = OneShot<Void>()
    private let lock = NSLock()
    private var connection: NWConnection?
    private var _didSendHTTPBodyTerminator = false
    private(set) var port: UInt16 = 0

    var didSendHTTPBodyTerminator: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _didSendHTTPBodyTerminator
    }

    private init(listener: NWListener) {
        self.listener = listener
    }

    static func start() async throws -> LoopbackSSEServer {
        let listener = try NWListener(using: .tcp, on: .any)
        let server = LoopbackSSEServer(listener: listener)
        listener.stateUpdateHandler = { [weak server] state in
            guard let server else { return }
            switch state {
            case .ready:
                server.ready.signal(listener.port?.rawValue ?? 0)
            case .failed:
                server.ready.signal(0)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak server] connection in
            server?.accept(connection)
        }
        listener.start(queue: server.queue)
        let port = try await incrementalStreamingTimeout {
            try await server.ready.value()
        }
        guard port != 0 else {
            server.stop()
            throw URLError(.cannotConnectToHost)
        }
        server.port = port
        return server
    }

    func sendDoneWithoutEOF() throws {
        lock.lock()
        let connection = self.connection
        lock.unlock()
        guard let connection else {
            throw URLError(.networkConnectionLost)
        }

        connection.send(
            content: httpChunk(Data("data: [DONE]\n\n".utf8)),
            completion: .contentProcessed { [weak self, weak connection] error in
                guard let self else { return }
                if error != nil || connection == nil {
                    self.peerClosed.signal(())
                }
            }
        )
    }

    func waitForPeerClose() async throws {
        _ = try await peerClosed.value()
    }

    func stop() {
        listener.cancel()
        lock.lock()
        let connection = self.connection
        self.connection = nil
        lock.unlock()
        connection?.cancel()
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        self.connection = connection
        lock.unlock()
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.peerClosed.signal(())
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveCompleteRequest(connection, accumulated: Data())
    }

    private func receiveCompleteRequest(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            var request = accumulated
            if let content {
                request.append(content)
            }
            if error != nil || isComplete {
                self.peerClosed.signal(())
                return
            }
            if self.isCompleteHTTPRequest(request) {
                self.sendInitialResponse(connection)
            } else {
                self.receiveCompleteRequest(connection, accumulated: request)
            }
        }
    }

    private func isCompleteHTTPRequest(_ data: Data) -> Bool {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator) else { return false }
        let headerText = String(decoding: data[..<range.lowerBound], as: UTF8.self)
        let contentLength = headerText
            .components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { line -> Int? in
                guard let colon = line.firstIndex(of: ":") else { return nil }
                let value = line[line.index(after: colon)...]
                return Int(String(value).trimmingCharacters(in: .whitespaces))
            }
            ?? 0
        return data.count >= range.upperBound + contentLength
    }

    private func sendInitialResponse(_ connection: NWConnection) {
        let event = Data("data: {\"choices\":[{\"delta\":{\"content\":\"hello-before-eof\"}}]}\n\n".utf8)
        var response = Data((
            "HTTP/1.1 200 OK\r\n"
                + "Content-Type: text/event-stream\r\n"
                + "Transfer-Encoding: chunked\r\n"
                + "Connection: close\r\n"
                + "\r\n"
        ).utf8)
        response.append(httpChunk(event))
        connection.send(content: response, completion: .contentProcessed { [weak self, weak connection] error in
            guard let self else { return }
            guard error == nil, let connection else {
                self.peerClosed.signal(())
                return
            }
            self.receiveUntilPeerCloses(connection)
        })
    }

    private func receiveUntilPeerCloses(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4 * 1024) { [weak self, weak connection] _, _, isComplete, error in
            guard let self else { return }
            if error != nil || isComplete || connection == nil {
                self.peerClosed.signal(())
            } else {
                self.receiveUntilPeerCloses(connection!)
            }
        }
    }
}

private func httpChunk(_ data: Data) -> Data {
    var chunk = Data(String(data.count, radix: 16).utf8)
    chunk.append(Data("\r\n".utf8))
    chunk.append(data)
    chunk.append(Data("\r\n".utf8))
    return chunk
}
