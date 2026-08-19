import Foundation

public enum AIRealtimeSessionError:
    Error,
    Equatable,
    CustomStringConvertible,
    Sendable {
    case closed
    case connectionEndedBeforeOpening

    public var description: String {
        switch self {
        case .closed:
            return "The realtime session is closed."
        case .connectionEndedBeforeOpening:
            return "The realtime WebSocket ended before it opened."
        }
    }
}

/// Connection lifecycle and normalized provider events from a realtime model.
public enum AIRealtimeSessionEvent: Equatable, Sendable {
    case opened(protocol: String?)
    case server(AIRealtimeServerEvent)
    case closed(AIDuplexWebSocketCloseMetadata)
}

/// A connected, provider-neutral realtime V4 session.
public final class AIRealtimeSession:
    AsyncSequence,
    @unchecked Sendable {
    public typealias Element = AIRealtimeSessionEvent
    public typealias AsyncIterator =
        AsyncThrowingStream<AIRealtimeSessionEvent, Error>.Iterator

    public let providerID: String
    public let modelID: String
    public let clientSecretExpiresAt: Int?
    public let events: AsyncThrowingStream<AIRealtimeSessionEvent, Error>

    private typealias Continuation =
        AsyncThrowingStream<AIRealtimeSessionEvent, Error>.Continuation

    private let model: any AIRealtimeModelV4
    private let configuration: AIRealtimeSessionConfiguration
    private let connection: any AIDuplexWebSocketConnection
    private let abortSignal: AIAbortSignal?
    private let continuation: Continuation
    private let readyGate = AIRealtimeReadyGate()
    private let sendQueue: AIRealtimeSendQueue

    private let lock = NSLock()
    private var eventTask: Task<Void, Never>?
    private var abortRegistration: AIAbortHandlerRegistration?
    private var opened = false
    private var completed = false

    private init(
        model: any AIRealtimeModelV4,
        configuration: AIRealtimeSessionConfiguration,
        clientSecretExpiresAt: Int?,
        connection: any AIDuplexWebSocketConnection,
        abortSignal: AIAbortSignal?
    ) {
        self.model = model
        self.providerID = model.providerID
        self.modelID = model.modelID
        self.configuration = configuration
        self.clientSecretExpiresAt = clientSecretExpiresAt
        self.connection = connection
        self.abortSignal = abortSignal

        let pair = AsyncThrowingStream<AIRealtimeSessionEvent, Error>
            .makeStream()
        self.events = pair.stream
        self.continuation = pair.continuation
        self.sendQueue = AIRealtimeSendQueue(
            model: model,
            connection: connection,
            readyGate: readyGate
        )

        pair.continuation.onTermination = { [weak self] termination in
            if case .cancelled = termination {
                self?.cancelFromConsumer()
            }
        }
        self.abortRegistration = abortSignal?.addAbortHandler {
            [weak self, weak signal = abortSignal] reason in
            self?.abort(AIAbortError(
                reason: reason,
                reasonName: signal?.reasonName
            ))
        }

        let eventTask = Task { [weak self] in
            guard let self else { return }
            await self.consumeConnectionEvents()
        }
        self.eventTask = eventTask
    }

    /// Creates an ephemeral secret and connects its provider WebSocket.
    public static func connect(
        model: any AIRealtimeModelV4,
        sessionConfiguration: AIRealtimeSessionConfiguration = .init(),
        clientSecretOptions: AIRealtimeClientSecretOptions = .init(),
        webSocketTransport: any AIDuplexWebSocketTransport =
            URLSessionDuplexWebSocketTransport.shared,
        abortSignal: AIAbortSignal? = nil
    ) async throws -> AIRealtimeSession {
        var secretOptions = clientSecretOptions
        if secretOptions.abortSignal == nil {
            secretOptions.abortSignal = abortSignal
        }
        if secretOptions.sessionConfig == nil {
            secretOptions.sessionConfig = sessionConfiguration
        }
        let clientSecret = try await model.doCreateClientSecret(secretOptions)
        return try await connect(
            model: model,
            clientSecret: clientSecret,
            sessionConfiguration: sessionConfiguration,
            webSocketTransport: webSocketTransport,
            abortSignal: abortSignal ?? clientSecretOptions.abortSignal
        )
    }

    /// Connects with an already-created ephemeral secret.
    public static func connect(
        model: any AIRealtimeModelV4,
        clientSecret: AIRealtimeClientSecretResult,
        sessionConfiguration: AIRealtimeSessionConfiguration = .init(),
        webSocketTransport: any AIDuplexWebSocketTransport =
            URLSessionDuplexWebSocketTransport.shared,
        abortSignal: AIAbortSignal? = nil
    ) async throws -> AIRealtimeSession {
        try abortSignal?.throwIfAborted()
        let socketConfig = model.getWebSocketConfig(
            token: clientSecret.token,
            url: clientSecret.url
        )
        guard let url = URL(string: socketConfig.url) else {
            throw AIError.invalidURL(socketConfig.url)
        }
        let connection = try await webSocketTransport.connect(
            AIDuplexWebSocketRequest(
                url: url,
                headers: socketConfig.headers,
                protocols: socketConfig.protocols,
                abortSignal: abortSignal
            )
        )
        return AIRealtimeSession(
            model: model,
            configuration: sessionConfiguration,
            clientSecretExpiresAt: clientSecret.expiresAt,
            connection: connection,
            abortSignal: abortSignal
        )
    }

    public func makeAsyncIterator() -> AsyncIterator {
        events.makeAsyncIterator()
    }

    /// Sends a normalized client event after the connection is ready.
    public func send(_ event: AIRealtimeClientEvent) async throws {
        try await sendQueue.send(event)
    }

    public func appendAudio(_ audio: Data) async throws {
        try await appendAudio(base64: audio.base64EncodedString())
    }

    public func appendAudio(base64: String) async throws {
        try await send(.inputAudioAppend(audio: base64))
    }

    public func commitAudio() async throws {
        try await send(.inputAudioCommit)
    }

    public func clearAudio() async throws {
        try await send(.inputAudioClear)
    }

    public func sendText(_ text: String) async throws {
        try await send(.conversationItemCreate(.textMessage(text: text)))
    }

    public func sendAudioMessage(_ audio: Data) async throws {
        try await send(.conversationItemCreate(.audioMessage(
            audio: audio.base64EncodedString()
        )))
    }

    public func sendFunctionCallOutput(
        callID: String,
        name: String? = nil,
        output: String
    ) async throws {
        try await send(.conversationItemCreate(.functionCallOutput(
            callID: callID,
            name: name,
            output: output
        )))
    }

    public func createResponse(
        options: AIRealtimeResponseOptions? = nil
    ) async throws {
        try await send(.responseCreate(options: options))
    }

    public func cancelResponse() async throws {
        try await send(.responseCancel)
    }

    /// Closes the duplex connection and completes the lifecycle stream.
    public func close(
        code: Int = AIDuplexWebSocketCloseMetadata.normalClosure.code,
        reason: String? = nil
    ) async {
        let metadata = AIDuplexWebSocketCloseMetadata(
            code: code,
            reason: reason
        )
        guard beginCompletion() else { return }
        await sendQueue.close()
        await readyGate.fail(AIRealtimeSessionError.closed)
        continuation.yield(.closed(metadata))
        continuation.finish()
        let reasonData = reason.map { Data($0.utf8) }
        await connection.close(code: code, reason: reasonData)
        cleanupAfterCompletion(cancelEventTask: true)
    }

    public func cancel(reason: String? = nil) async {
        await close(reason: reason)
    }

    private func consumeConnectionEvents() async {
        do {
            for try await event in connection.events {
                if isCompleted { return }
                switch event {
                case let .opened(selectedProtocol):
                    markOpened()
                    do {
                        try await sendSessionConfiguration()
                    } catch {
                        fail(error)
                        return
                    }
                    continuation.yield(.opened(protocol: selectedProtocol))

                case let .message(message):
                    guard let raw = parseJSON(message) else { continue }
                    do {
                        if let response = try await model
                            .getHealthCheckResponse(raw) {
                            try await sendQueue.send(response)
                        }
                    } catch {
                        fail(error)
                        return
                    }
                    for normalized in model.parseServerEvent(raw) {
                        continuation.yield(.server(normalized))
                    }

                case let .closed(metadata):
                    complete(with: metadata)
                    return
                }
            }

            if !isCompleted {
                if hasOpened {
                    complete(with: .normalClosure)
                } else {
                    fail(AIRealtimeSessionError.connectionEndedBeforeOpening)
                }
            }
        } catch {
            if let abortSignal, abortSignal.isAborted {
                fail(AIAbortError(
                    reason: abortSignal.reason,
                    reasonName: abortSignal.reasonName
                ))
            } else if !(error is CancellationError), !isCompleted {
                fail(error)
            }
        }
    }

    private func sendSessionConfiguration() async throws {
        guard let wireMessage = try await model.serializeClientEvent(
            .sessionUpdate(configuration)
        ) else {
            await readyGate.succeed()
            return
        }
        do {
            try await sendWireDirectly(wireMessage)
            await readyGate.succeed()
        } catch {
            await readyGate.fail(error)
            throw error
        }
    }

    private func sendWireDirectly(
        _ message: AIRealtimeWireMessage
    ) async throws {
        switch message {
        case let .json(raw):
            let data = try JSONEncoder().encode(raw)
            guard let text = String(data: data, encoding: .utf8) else {
                throw AIError.invalidArgument(
                    argument: "event",
                    message: "Could not encode the realtime event as UTF-8."
                )
            }
            try await connection.send(.text(text))
        case let .text(text):
            try await connection.send(.text(text))
        case let .binary(data):
            try await connection.send(.binary(data))
        }
    }

    private func parseJSON(
        _ message: AIDuplexWebSocketMessage
    ) -> JSONValue? {
        let data: Data
        switch message {
        case let .text(text):
            data = Data(text.utf8)
        case let .binary(binary):
            data = binary
        }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func complete(with metadata: AIDuplexWebSocketCloseMetadata) {
        guard beginCompletion() else { return }
        Task {
            await sendQueue.close()
            await readyGate.fail(AIRealtimeSessionError.closed)
        }
        continuation.yield(.closed(metadata))
        continuation.finish()
        cleanupAfterCompletion(cancelEventTask: false)
    }

    private func fail(_ error: Error) {
        guard beginCompletion() else { return }
        Task {
            await sendQueue.close()
            await readyGate.fail(error)
            await connection.close(code: 1011, reason: nil)
        }
        continuation.finish(throwing: error)
        cleanupAfterCompletion(cancelEventTask: true)
    }

    private func abort(_ error: AIAbortError) {
        fail(error)
    }

    private func cancelFromConsumer() {
        guard beginCompletion() else { return }
        Task {
            await sendQueue.close()
            await readyGate.fail(CancellationError())
            await connection.close(code: 1000, reason: nil)
        }
        cleanupAfterCompletion(cancelEventTask: true)
    }

    private func markOpened() {
        lock.lock()
        opened = true
        lock.unlock()
    }

    private var hasOpened: Bool {
        lock.lock()
        defer { lock.unlock() }
        return opened
    }

    private var isCompleted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    private func beginCompletion() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }

    private func cleanupAfterCompletion(cancelEventTask: Bool) {
        lock.lock()
        let eventTask = self.eventTask
        self.eventTask = nil
        let registration = abortRegistration
        abortRegistration = nil
        lock.unlock()

        registration?.cancel()
        if cancelEventTask {
            eventTask?.cancel()
        }
    }
}

private actor AIRealtimeReadyGate {
    private var result: Result<Void, Error>?
    private var waiters: [CheckedContinuation<Void, Error>] = []

    func wait() async throws {
        if let result {
            return try result.get()
        }
        try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func succeed() {
        resolve(.success(()))
    }

    func fail(_ error: Error) {
        resolve(.failure(error))
    }

    private func resolve(_ result: Result<Void, Error>) {
        guard self.result == nil else { return }
        self.result = result
        let waiters = self.waiters
        self.waiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume(with: result)
        }
    }
}

private actor AIRealtimeSendQueue {
    private let model: any AIRealtimeModelV4
    private let connection: any AIDuplexWebSocketConnection
    private let readyGate: AIRealtimeReadyGate
    private var tail: Task<Void, Error>?
    private var closed = false

    init(
        model: any AIRealtimeModelV4,
        connection: any AIDuplexWebSocketConnection,
        readyGate: AIRealtimeReadyGate
    ) {
        self.model = model
        self.connection = connection
        self.readyGate = readyGate
    }

    func send(_ event: AIRealtimeClientEvent) async throws {
        guard !closed else { throw AIRealtimeSessionError.closed }
        let previous = tail
        let model = self.model
        let connection = self.connection
        let readyGate = self.readyGate
        let task = Task {
            try await readyGate.wait()
            if let previous {
                try await previous.value
            }
            if let message = try await model.serializeClientEvent(event) {
                try await sendRealtimeWireMessage(message, over: connection)
            }
        }
        tail = task
        try await task.value
    }

    func send(_ message: AIRealtimeWireMessage) async throws {
        guard !closed else { throw AIRealtimeSessionError.closed }
        let previous = tail
        let connection = self.connection
        let readyGate = self.readyGate
        let task = Task {
            try await readyGate.wait()
            if let previous {
                try await previous.value
            }
            try await sendRealtimeWireMessage(message, over: connection)
        }
        tail = task
        try await task.value
    }

    func close() {
        closed = true
        tail?.cancel()
        tail = nil
    }
}

private func sendRealtimeWireMessage(
    _ message: AIRealtimeWireMessage,
    over connection: any AIDuplexWebSocketConnection
) async throws {
    switch message {
    case let .json(raw):
        let data = try JSONEncoder().encode(raw)
        guard let text = String(data: data, encoding: .utf8) else {
            throw AIError.invalidArgument(
                argument: "event",
                message: "Could not encode the realtime event as UTF-8."
            )
        }
        try await connection.send(.text(text))
    case let .text(text):
        try await connection.send(.text(text))
    case let .binary(data):
        try await connection.send(.binary(data))
    }
}
