import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAILiveDeclaresPortableContinuousServerWebSocket() throws {
    let model = try OpenAILiveModel(
        settings: ProviderSettings(
            apiKey: "test-key",
            baseURL: "https://example.com/proxy/v1/",
            organization: "org-test",
            project: "proj-test",
            headers: ["X-Custom": "value"],
            name: "custom"
        )
    )

    #expect(model.specificationVersion == "v4")
    #expect(model.providerID == "custom.live")
    #expect(model.modelID == "gpt-live-1")
    #expect(model.capabilities == AIRealtimeModelCapabilities(
        conversation: .continuous,
        transports: [.webSocket],
        connections: [.serverWebSocket],
        startup: .sessionStart,
        finalization: .sessionClose
    ))

    let erased: any AIRealtimeModelV4 = model
    #expect(erased.getWebSocketConfig(
        token: "ephemeral",
        url: "wss://client.example/realtime"
    ).url == "wss://client.example/realtime")
    #expect(erased.buildSessionConfig(.init())["model"]?.stringValue
        == "gpt-live-1")
    #expect(throws: AIError.self) {
        try erased.getValidatedWebSocketConfig(
            token: "ephemeral",
            url: "wss://client.example/realtime"
        )
    }
    #expect(throws: AIError.self) {
        try erased.buildValidatedSessionConfig(.init(
            turnDetection: .init(type: .disabled)
        ))
    }

    let socket = try model.getServerWebSocketConfig()
    #expect(socket.url == "wss://example.com/proxy/v1/live/sessions")
    #expect(socket.headers["authorization"] == "Bearer test-key")
    #expect(socket.headers["openai-organization"] == "org-test")
    #expect(socket.headers["openai-project"] == "proj-test")
    #expect(socket.headers["x-custom"] == "value")
    #expect(socket.headers.values.allSatisfy { !$0.isEmpty })

    let local = try OpenAILiveModel(settings: ProviderSettings(
        apiKey: "test-key",
        baseURL: "http://localhost:3000/v1"
    ))
    #expect(
        try local.getServerWebSocketConfig().url
            == "ws://localhost:3000/v1/live/sessions"
    )

    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        baseURL: "https://example.com/proxy/v1/"
    ))
    let factoryModel = try provider.experimentalRealtime("gpt-live-1")
    #expect(factoryModel is OpenAILiveModel)
    #expect(factoryModel.providerID == "openai.live")
    #expect(factoryModel.modelID == "gpt-live-1")
    #expect(
        try factoryModel.getServerWebSocketConfig().url
            == "wss://example.com/proxy/v1/live/sessions"
    )
}

@Test func openAILiveBuildsStartupHistoryFormatsAndCustomVoice() throws {
    let model = try openAILiveTestModel()
    let input: JSONValue = .array([
        [
            "type": "message",
            "role": "user",
            "content": [["type": "input_text", "text": "Hello"]]
        ],
        [
            "type": "message",
            "role": "assistant",
            "content": [["type": "output_text", "text": "Hi"]]
        ]
    ])
    let config = AIRealtimeSessionConfiguration(
        instructions: "Be concise.",
        inputAudioFormat: .init(type: "audio/pcm", rate: 16_000),
        providerOptions: [
            "openai": .object([
                "delegation": ["type": "client"],
                "input": input,
                "store": true,
                "voice": ["id": "voice-test"]
            ])
        ]
    )

    #expect(model.buildSessionConfig(config) == [
        "model": "gpt-live-1",
        "instructions": "Be concise.",
        "audio": [
            "format": ["type": "audio/pcm", "rate": 16_000],
            "output": ["voice": ["id": "voice-test"]]
        ],
        "delegation": ["type": "client"],
        "input": input,
        "store": true
    ])

    #expect(model.buildSessionConfig(.init(
        outputAudioFormat: .init(type: "audio/pcmu", rate: 8_000),
        providerOptions: ["openai": ["delegation": .null]]
    )) == [
        "model": "gpt-live-1",
        "audio": [
            "format": ["type": "audio/pcmu", "rate": 8_000],
            "output": ["voice": "marin"]
        ],
        "delegation": .null
    ])

    #expect(model.buildSessionConfig(.init(
        providerOptions: ["openai": .null]
    )) == [
        "model": "gpt-live-1",
        "audio": [
            "format": ["type": "audio/pcm", "rate": 24_000],
            "output": ["voice": "marin"]
        ]
    ])
}

@Test func openAILiveValidatesImmutableStartupConfiguration() throws {
    let model = try openAILiveTestModel()

    #expect(throws: AIError.self) {
        try model.buildValidatedSessionConfig(.init(
            inputAudioFormat: .init(type: "audio/pcm", rate: 24_000),
            outputAudioFormat: .init(type: "audio/pcm", rate: 16_000)
        ))
    }
    #expect(throws: AIError.self) {
        try model.buildValidatedSessionConfig(.init(
            voice: "marin",
            providerOptions: [
                "openai": ["voice": ["id": "voice-test"]]
            ]
        ))
    }
    #expect(throws: AIError.self) {
        try model.buildValidatedSessionConfig(.init(
            turnDetection: .init(type: .disabled)
        ))
    }
    #expect(throws: AIError.self) {
        try model.buildValidatedSessionConfig(.init(providerOptions: [
            "openai": ["delegation": ["type": "responses"]]
        ]))
    }
    #expect(throws: AIError.self) {
        try model.buildValidatedSessionConfig(.init(providerOptions: [
            "openai": ["unknown": true]
        ]))
    }
    #expect(throws: AIError.self) {
        try model.buildValidatedSessionConfig(.init(providerOptions: [
            "openai": ["client": .null]
        ]))
    }
}

@Test func openAILiveSerializesContinuousCommandsAndCorrelation() async throws {
    let model = try openAILiveTestModel()
    let started = try await model.serializeClientEvent(.sessionStart(
        .init(instructions: "Be concise.", voice: "marin"),
        eventID: "start-1"
    ))
    #expect(started == .json([
        "type": "session.start",
        "event_id": "start-1",
        "session": [
            "model": "gpt-live-1",
            "instructions": "Be concise.",
            "audio": [
                "format": ["type": "audio/pcm", "rate": 24_000],
                "output": ["voice": "marin"]
            ]
        ]
    ]))

    for channel in ["instructions", "thinking", "commentary"] {
        #expect(try await model.serializeClientEvent(.contextAppend(
            content: "Context",
            delegationID: "opaque-delegation",
            eventID: "append-1",
            providerOptions: ["openai": ["channel": .string(channel)]]
        )) == .json([
            "type": .string("session." + channel + ".append"),
            "content": "Context",
            "delegation_id": "opaque-delegation",
            "event_id": "append-1"
        ]))
    }

    #expect(try await model.serializeClientEvent(.contextAppend(
        content: "",
        delegationID: nil,
        providerOptions: ["openai": .null]
    )) == .json([
        "type": "session.thinking.append",
        "content": "",
        "delegation_id": .null
    ]))
    #expect(try await model.serializeClientEvent(
        .inputAudioAppendWithEventID(audio: "AAAA", eventID: "audio-1")
    ) == .json([
        "type": "session.input_audio.append",
        "audio": "AAAA",
        "event_id": "audio-1"
    ]))
    #expect(try await model.serializeClientEvent(
        .inputAudioMute(eventID: "mute-1")
    ) == .json([
        "type": "session.input_audio.mute",
        "event_id": "mute-1"
    ]))
    #expect(try await model.serializeClientEvent(
        .sessionClose(eventID: "close-1")
    ) == .json([
        "type": "session.close",
        "event_id": "close-1"
    ]))

    await #expect(throws: AIError.self) {
        try await model.serializeClientEvent(.sessionUpdate(.init()))
    }
    await #expect(throws: AIError.self) {
        try await model.serializeClientEvent(.responseCreate())
    }
}

@Test func openAILiveNormalizesLifecycleUsageAudioAndTranscripts() throws {
    let model = try openAILiveTestModel()
    let started: JSONValue = [
        "type": "session.started",
        "session": [
            "id": "session-1",
            "delegation": ["type": "responses"]
        ]
    ]
    #expect(model.parseServerEvent(started) == [
        .sessionStarted(
            sessionID: "session-1",
            delegationMode: .provider,
            raw: started
        )
    ])

    let usage: JSONValue = [
        "type": "session.usage.updated",
        "usage": ["seconds": 12],
        "context_window": ["usage_ratio": 0.42]
    ]
    #expect(model.parseServerEvent(usage) == [
        .sessionUsage(
            usage: .init(seconds: 12),
            contextWindowUsageRatio: 0.42,
            raw: usage
        )
    ])

    let audio: JSONValue = [
        "type": "session.output_audio.delta",
        "delta": "AAAA"
    ]
    #expect(model.parseServerEvent(audio) == [
        .audioChunk(delta: "AAAA", raw: audio)
    ])

    let transcript: JSONValue = [
        "type": "session.input_transcript.delta",
        "delta": " hello",
        "start_ms": 100,
        "end_ms": 200
    ]
    #expect(model.parseServerEvent(transcript) == [
        .transcriptFragment(
            speaker: .user,
            delta: " hello",
            startMilliseconds: 100,
            endMilliseconds: 200,
            raw: transcript
        )
    ])
}

@Test func openAILivePreservesDelegationAcknowledgementAndErrorCorrelation()
    throws {
    let model = try openAILiveTestModel()
    let delegation: JSONValue = [
        "type": "session.delegation.created",
        "offset_ms": 1_000,
        "delegation": [
            "id": "opaque-delegation",
            "target": "responses",
            "response_id": "opaque-response"
        ]
    ]
    #expect(model.parseServerEvent(delegation) == [
        .delegationCreated(
            delegationID: "opaque-delegation",
            target: .provider,
            offsetMilliseconds: 1_000,
            responseID: "opaque-response",
            raw: delegation
        )
    ])

    let acknowledged: JSONValue = [
        "type": "session.instructions.appended",
        "client_event_id": "append-1",
        "start_ms": 10,
        "end_ms": 20
    ]
    #expect(model.parseServerEvent(acknowledged) == [
        .commandAcknowledged(
            command: "session.instructions.append",
            clientEventID: "append-1",
            raw: acknowledged
        )
    ])

    let rejected: JSONValue = [
        "type": "error",
        "error": [
            "message": "Rejected",
            "code": "immutable_field_update",
            "client_event_id": "update-1"
        ]
    ]
    #expect(model.parseServerEvent(rejected) == [
        .correlatedError(
            message: "Rejected",
            code: "immutable_field_update",
            clientEventID: "update-1",
            raw: rejected
        )
    ])
}

@Test func openAILivePreservesUnknownAndRejectsMalformedKnownEvents() throws {
    let model = try openAILiveTestModel()
    let unknown: JSONValue = [
        "type": "response.event",
        "delegation_id": "opaque",
        "event": ["type": "response.completed"]
    ]
    #expect(model.parseServerEvent(unknown) == [
        .custom(rawType: "response.event", raw: unknown)
    ])

    for malformed: JSONValue in [
        ["type": "session.started", "session": ["id": ""]],
        [
            "type": "session.usage.updated",
            "usage": ["seconds": -1]
        ],
        [
            "type": "session.output_transcript.delta",
            "delta": "hi",
            "start_ms": 20,
            "end_ms": 10
        ],
        [
            "type": "session.input_audio.muted",
            "client_event_id": 123
        ]
    ] {
        let parsed = model.parseServerEvent(malformed)
        guard case let .error(_, code, raw) = parsed.first else {
            Issue.record("Expected invalid OpenAI Live server event")
            continue
        }
        #expect(code == "invalid_server_event")
        #expect(raw == malformed)
    }
}

@Test func openAILiveSessionStartsCorrelatesContextAndConfirmsClose()
    async throws {
    let model = try openAILiveTestModel()
    let webSocket = RealtimeTestWebSocketTransport()
    let session = try await AIRealtimeSession.connect(
        model: model,
        sessionConfiguration: .init(instructions: "Be concise."),
        webSocketTransport: webSocket
    )
    let eventsTask = Task { try await realtimeCollect(session.events) }

    let request = try #require(webSocket.requests().first)
    #expect(request.url.absoluteString == "wss://api.openai.com/v1/live/sessions")
    #expect(request.headers["authorization"] == "Bearer test-key")
    #expect(session.clientSecretExpiresAt == nil)

    webSocket.connection.open(protocol: "live")
    #expect(await realtimeWait {
        webSocket.connection.sentMessages().count == 1
    })
    #expect(try webSocket.connection.sentJSONMessages().first == [
        "type": "session.start",
        "session": [
            "model": "gpt-live-1",
            "instructions": "Be concise.",
            "audio": [
                "format": ["type": "audio/pcm", "rate": 24_000],
                "output": ["voice": "marin"]
            ]
        ]
    ])

    await #expect(throws: AIRealtimeSessionError.closed) {
        try await session.appendContext(
            "too soon",
            delegationID: nil
        )
    }

    let started: JSONValue = [
        "type": "session.started",
        "session": ["id": "live-1", "delegation": ["type": "client"]]
    ]
    webSocket.connection.sendJSON(started)
    var sentContext = false
    for _ in 0..<10_000 {
        do {
            try await session.appendContext(
                "Application result",
                delegationID: "d1",
                eventID: "context-1"
            )
            sentContext = true
            break
        } catch AIRealtimeSessionError.closed {
            await Task.yield()
        }
    }
    #expect(sentContext)
    #expect(await realtimeWait {
        webSocket.connection.sentMessages().count == 2
    })

    let acknowledged: JSONValue = [
        "type": "session.thinking.appended",
        "client_event_id": "context-1",
        "start_ms": 10,
        "end_ms": 20
    ]
    webSocket.connection.sendJSON(acknowledged)

    let closeTask = Task {
        await session.close(eventID: "close-1")
    }
    #expect(await realtimeWait {
        webSocket.connection.sentMessages().count == 3
    })
    #expect(try webSocket.connection.sentJSONMessages().suffix(2) == [
        [
            "type": "session.thinking.append",
            "content": "Application result",
            "delegation_id": "d1",
            "event_id": "context-1"
        ],
        ["type": "session.close", "event_id": "close-1"]
    ])

    let closed: JSONValue = [
        "type": "session.closed",
        "session": ["id": "live-1"],
        "usage": ["seconds": 5],
        "reason": "close_requested"
    ]
    webSocket.connection.sendJSON(closed)
    await closeTask.value

    let events = try await eventsTask.value
    #expect(events == [
        .opened(protocol: "live"),
        .server(.sessionStarted(
            sessionID: "live-1",
            delegationMode: .client,
            raw: started
        )),
        .server(.commandAcknowledged(
            command: "session.thinking.append",
            clientEventID: "context-1",
            raw: acknowledged
        )),
        .server(.sessionClosed(
            sessionID: "live-1",
            usage: .init(seconds: 5),
            reason: "close_requested",
            raw: closed
        )),
        .closed(.normalClosure)
    ])
    #expect(webSocket.connection.closeCalls().map(\.code) == [1000])
}

@Test func openAILiveSessionReportsAbnormalCloseBeforeFinalization()
    async throws {
    let webSocket = RealtimeTestWebSocketTransport()
    let session = try await AIRealtimeSession.connectServer(
        model: try openAILiveTestModel(),
        webSocketTransport: webSocket
    )
    let eventsTask = Task { try await realtimeCollect(session.events) }
    webSocket.connection.open()
    webSocket.connection.sendJSON([
        "type": "session.started",
        "session": ["id": "live-1"]
    ])
    #expect(await realtimeWait {
        webSocket.connection.sentMessages().count == 1
    })

    let metadata = AIDuplexWebSocketCloseMetadata(
        code: 1007,
        reason: "Request contains an invalid argument"
    )
    webSocket.connection.serverClose(
        code: metadata.code,
        reason: metadata.reason
    )
    do {
        _ = try await eventsTask.value
        Issue.record("Expected abnormal OpenAI Live close to fail")
    } catch let error as AIRealtimeSessionError {
        #expect(error == .unexpectedClosure(metadata))
        #expect(
            error.description
                == "Realtime WebSocket closed unexpectedly "
                    + "(code 1007: Request contains an invalid argument)"
        )
    }
}

private func openAILiveTestModel() throws -> OpenAILiveModel {
    try OpenAILiveModel(settings: ProviderSettings(apiKey: "test-key"))
}
