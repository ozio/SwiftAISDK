import Foundation
import Testing
@testable import SwiftAISDK

@Test func realtimeSessionQueuesUntilOpenAndNormalizesLifecycle() async throws {
    let model = RealtimeFoundationTestModel()
    let webSocket = RealtimeTestWebSocketTransport()
    let configuration = AIRealtimeSessionConfiguration(
        instructions: "Be concise",
        voice: "test-voice"
    )
    let session = try await AIRealtimeSession.connect(
        model: model,
        sessionConfiguration: configuration,
        clientSecretOptions: AIRealtimeClientSecretOptions(
            expiresAfterSeconds: 60
        ),
        webSocketTransport: webSocket
    )

    #expect(session.providerID == "test.realtime")
    #expect(session.modelID == "test-model")
    #expect(session.clientSecretExpiresAt == 1_234)
    #expect(webSocket.connection.sentMessages().isEmpty)

    let eventsTask = Task { try await realtimeCollect(session.events) }
    let sendTask = Task { try await session.sendText("hello") }
    await Task.yield()
    #expect(webSocket.connection.sentMessages().isEmpty)

    webSocket.connection.open(protocol: "test-protocol")
    try await sendTask.value
    #expect(await realtimeWait {
        webSocket.connection.sentMessages().count == 2
    })

    let sent = try webSocket.connection.sentJSONMessages()
    #expect(sent == [
        .object([
            "type": .string("session.update"),
            "session": .object([
                "instructions": .string("Be concise"),
                "voice": .string("test-voice")
            ])
        ]),
        .object([
            "type": .string("conversation.item.create"),
            "text": .string("hello")
        ])
    ])

    webSocket.connection.sendJSON([
        "type": "ping",
        "request_id": "ping-1"
    ])
    #expect(await realtimeWait {
        webSocket.connection.sentMessages().count == 3
    })
    #expect(try webSocket.connection.sentJSONMessages().last == [
        "type": "pong",
        "request_id": "ping-1"
    ])

    let multiRaw: JSONValue = [
        "type": "multi",
        "response_id": "response-1",
        "item_id": "item-1"
    ]
    webSocket.connection.sendJSON(multiRaw)
    webSocket.connection.serverClose(code: 1001, reason: "finished")

    let events = try await eventsTask.value
    #expect(events == [
        .opened(protocol: "test-protocol"),
        .server(.custom(rawType: "ping", raw: [
            "type": "ping",
            "request_id": "ping-1"
        ])),
        .server(.textDelta(
            responseID: "response-1",
            itemID: "item-1",
            delta: "A",
            raw: multiRaw
        )),
        .server(.textDone(
            responseID: "response-1",
            itemID: "item-1",
            text: "A",
            raw: multiRaw
        )),
        .closed(AIDuplexWebSocketCloseMetadata(
            code: 1001,
            reason: "finished"
        ))
    ])

    let socketRequest = try #require(webSocket.requests().first)
    #expect(socketRequest.url.absoluteString == "wss://example.test/realtime")
    #expect(socketRequest.protocols == ["test-secret.secret-value"])
    #expect(socketRequest.headers == ["x-test": "header-value"])
    #expect(model.secretOptions()?.expiresAfterSeconds == 60)
    #expect(model.secretOptions()?.sessionConfig == configuration)
}

@Test func realtimeSessionPreservesExplicitClientSecretSessionConfiguration() async throws {
    let model = RealtimeFoundationTestModel()
    let webSocket = RealtimeTestWebSocketTransport()
    let socketConfiguration = AIRealtimeSessionConfiguration(
        instructions: "Socket configuration"
    )
    let secretConfiguration = AIRealtimeSessionConfiguration(
        instructions: "Secret override"
    )

    let session = try await AIRealtimeSession.connect(
        model: model,
        sessionConfiguration: socketConfiguration,
        clientSecretOptions: AIRealtimeClientSecretOptions(
            sessionConfig: secretConfiguration
        ),
        webSocketTransport: webSocket
    )

    #expect(model.secretOptions()?.sessionConfig == secretConfiguration)
    await session.cancel(reason: "test-complete")
}

@Test func realtimeSessionConveniencesSendAudioCommitCancelAndClose() async throws {
    let model = RealtimeFoundationTestModel()
    let webSocket = RealtimeTestWebSocketTransport()
    let session = try await AIRealtimeSession.connect(
        model: model,
        clientSecret: AIRealtimeClientSecretResult(
            token: "direct-secret",
            url: "wss://example.test/direct"
        ),
        webSocketTransport: webSocket
    )
    let eventsTask = Task { try await realtimeCollect(session.events) }
    webSocket.connection.open()
    #expect(await realtimeWait {
        webSocket.connection.sentMessages().count == 1
    })

    try await session.appendAudio(Data([1, 2, 3]))
    try await session.commitAudio()
    try await session.clearAudio()
    try await session.createResponse(options: AIRealtimeResponseOptions(
        modalities: ["audio"],
        instructions: "Answer"
    ))
    try await session.cancelResponse()
    await session.cancel(reason: "client-finished")

    let sent = try webSocket.connection.sentJSONMessages()
    #expect(sent.dropFirst() == [
        ["type": "input_audio_buffer.append", "audio": "AQID"],
        ["type": "input_audio_buffer.commit"],
        ["type": "input_audio_buffer.clear"],
        [
            "type": "response.create",
            "modalities": .array(["audio"]),
            "instructions": "Answer"
        ],
        ["type": "response.cancel"]
    ])
    #expect(webSocket.connection.closeCalls().map { $0.code } == [1000])
    #expect(webSocket.connection.closeCalls().first?.reason == Data(
        "client-finished".utf8
    ))
    #expect(try await eventsTask.value == [
        .opened(protocol: nil),
        .closed(AIDuplexWebSocketCloseMetadata(
            code: 1000,
            reason: "client-finished"
        ))
    ])
}

@Test func realtimeSessionPropagatesAbortAndRejectsPostCloseSends() async throws {
    let model = RealtimeFoundationTestModel()
    let webSocket = RealtimeTestWebSocketTransport()
    let controller = AIAbortController()
    let session = try await AIRealtimeSession.connect(
        model: model,
        clientSecret: AIRealtimeClientSecretResult(
            token: "secret",
            url: "wss://example.test/realtime"
        ),
        webSocketTransport: webSocket,
        abortSignal: controller.signal
    )

    let eventsTask = Task { try await realtimeCollect(session.events) }
    controller.abort(reason: "microphone stopped", reasonName: "AbortError")
    do {
        _ = try await eventsTask.value
        Issue.record("Expected abort to fail the realtime stream")
    } catch let error as AIAbortError {
        #expect(error.reason == "microphone stopped")
        #expect(error.reasonName == "AbortError")
    }
    #expect(await realtimeWait {
        webSocket.connection.closeCalls().contains { $0.code == 1011 }
    })

    do {
        try await session.sendText("late")
        Issue.record("Expected a closed-session error")
    } catch let error as AIRealtimeSessionError {
        #expect(error == .closed)
    }
}

final class RealtimeFoundationTestModel:
    AIRealtimeModelV4,
    @unchecked Sendable {
    let providerID = "test.realtime"
    let modelID = "test-model"

    private let lock = NSLock()
    private var recordedSecretOptions: AIRealtimeClientSecretOptions?

    func doCreateClientSecret(
        _ options: AIRealtimeClientSecretOptions
    ) async throws -> AIRealtimeClientSecretResult {
        recordSecretOptions(options)
        return AIRealtimeClientSecretResult(
            token: "secret-value",
            url: "wss://example.test/realtime",
            expiresAt: 1_234
        )
    }

    private func recordSecretOptions(
        _ options: AIRealtimeClientSecretOptions
    ) {
        lock.lock()
        recordedSecretOptions = options
        lock.unlock()
    }

    func getWebSocketConfig(
        token: String,
        url: String
    ) -> AIRealtimeWebSocketConfiguration {
        AIRealtimeWebSocketConfiguration(
            url: url,
            protocols: ["test-secret.\(token)"],
            headers: ["x-test": "header-value"]
        )
    }

    func parseServerEvent(_ raw: JSONValue) -> [AIRealtimeServerEvent] {
        guard raw["type"]?.stringValue == "multi" else {
            return [.custom(
                rawType: raw["type"]?.stringValue ?? "",
                raw: raw
            )]
        }
        let responseID = raw["response_id"]?.stringValue ?? ""
        let itemID = raw["item_id"]?.stringValue ?? ""
        return [
            .textDelta(
                responseID: responseID,
                itemID: itemID,
                delta: "A",
                raw: raw
            ),
            .textDone(
                responseID: responseID,
                itemID: itemID,
                text: "A",
                raw: raw
            )
        ]
    }

    func serializeClientEvent(
        _ event: AIRealtimeClientEvent
    ) async throws -> AIRealtimeWireMessage? {
        switch event {
        case let .sessionUpdate(config):
            return .json([
                "type": "session.update",
                "session": buildSessionConfig(config)
            ])
        case let .inputAudioAppend(audio):
            return .json([
                "type": "input_audio_buffer.append",
                "audio": .string(audio)
            ])
        case .inputAudioCommit:
            return .json(["type": "input_audio_buffer.commit"])
        case .inputAudioClear:
            return .json(["type": "input_audio_buffer.clear"])
        case let .conversationItemCreate(.textMessage(text)):
            return .json([
                "type": "conversation.item.create",
                "text": .string(text)
            ])
        case .conversationItemCreate:
            return nil
        case .conversationItemTruncate:
            return nil
        case let .responseCreate(options):
            return .json(.object([
                "type": .string("response.create"),
                "modalities": options?.modalities.map {
                    .array($0.map(JSONValue.string))
                },
                "instructions": options?.instructions.map(JSONValue.string)
            ]))
        case .responseCancel:
            return .json(["type": "response.cancel"])
        }
    }

    func buildSessionConfig(
        _ config: AIRealtimeSessionConfiguration
    ) -> JSONValue {
        .object([
            "instructions": config.instructions.map(JSONValue.string),
            "voice": config.voice.map(JSONValue.string)
        ])
    }

    func getHealthCheckResponse(
        _ raw: JSONValue
    ) async throws -> AIRealtimeWireMessage? {
        guard raw["type"]?.stringValue == "ping" else { return nil }
        return .json([
            "type": "pong",
            "request_id": raw["request_id"] ?? .null
        ])
    }

    func secretOptions() -> AIRealtimeClientSecretOptions? {
        lock.lock()
        defer { lock.unlock() }
        return recordedSecretOptions
    }
}

final class RealtimeTestWebSocketTransport:
    AIDuplexWebSocketTransport,
    @unchecked Sendable {
    let connection = RealtimeTestWebSocketConnection()

    private let lock = NSLock()
    private var recordedRequests: [AIDuplexWebSocketRequest] = []

    func connect(
        _ request: AIDuplexWebSocketRequest
    ) async throws -> any AIDuplexWebSocketConnection {
        record(request)
        return connection
    }

    private func record(_ request: AIDuplexWebSocketRequest) {
        lock.lock()
        recordedRequests.append(request)
        lock.unlock()
    }

    func requests() -> [AIDuplexWebSocketRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }
}

final class RealtimeTestWebSocketConnection:
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

    private func record(_ message: AIDuplexWebSocketMessage) {
        lock.lock()
        sent.append(message)
        lock.unlock()
    }

    func close(code: Int, reason: Data?) async {
        recordClose(code: code, reason: reason)
        continuation.finish()
    }

    private func recordClose(code: Int, reason: Data?) {
        lock.lock()
        closes.append((code, reason))
        lock.unlock()
    }

    func open(protocol: String? = nil) {
        continuation.yield(.opened(protocol: `protocol`))
    }

    func sendJSON(_ value: JSONValue) {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else {
            Issue.record("Could not encode realtime test JSON")
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

    func sentJSONMessages() throws -> [JSONValue] {
        try sentMessages().map { message in
            let data: Data
            switch message {
            case let .text(text):
                data = Data(text.utf8)
            case let .binary(binary):
                data = binary
            }
            return try JSONDecoder().decode(JSONValue.self, from: data)
        }
    }

    func closeCalls() -> [(code: Int, reason: Data?)] {
        lock.lock()
        defer { lock.unlock() }
        return closes
    }
}

func realtimeWait(
    _ condition: @escaping @Sendable () -> Bool
) async -> Bool {
    for _ in 0..<10_000 {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}

func realtimeCollect<T: Sendable>(
    _ stream: AsyncThrowingStream<T, Error>
) async throws -> [T] {
    var values: [T] = []
    for try await value in stream {
        values.append(value)
    }
    return values
}
