import Foundation
import Testing
@testable import SwiftAISDK

@Test func xaiRealtimeCreatesEphemeralSecretWithModelURLAndExpiry() async throws {
    let transport = RecordingTransport(response: jsonResponse(
        #"{"value":"ephemeral-secret","expires_at":123456}"#
    ))
    let provider = try AIProviders.xAI(settings: ProviderSettings(
        apiKey: "xai-test-key",
        headers: ["X-Custom": "custom-value"],
        environment: [:],
        transport: transport
    ))
    let model = try provider.realtime("grok voice/latest")

    let result = try await model.doCreateClientSecret(
        AIRealtimeClientSecretOptions(expiresAfterSeconds: 90)
    )

    #expect(model.specificationVersion == "v4")
    #expect(model.provider == "xai.realtime")
    #expect(model.modelID == "grok voice/latest")
    #expect(result == AIRealtimeClientSecretResult(
        token: "ephemeral-secret",
        url: "wss://api.x.ai/v1/realtime?model=grok%20voice%2Flatest",
        expiresAt: 123_456
    ))
    #expect(model.getWebSocketConfig(
        token: result.token,
        url: result.url
    ) == AIRealtimeWebSocketConfiguration(
        url: result.url,
        protocols: ["xai-client-secret.ephemeral-secret"]
    ))

    let requests = await transport.requests()
    let request = try #require(requests.first)
    #expect(requests.count == 1)
    #expect(request.url.absoluteString ==
        "https://api.x.ai/v1/realtime/client_secrets")
    #expect(xaiRealtimeHeader(request, "authorization") ==
        "Bearer xai-test-key")
    #expect(xaiRealtimeHeader(request, "content-type") ==
        "application/json")
    #expect(xaiRealtimeHeader(request, "x-custom") == "custom-value")
    #expect(xaiRealtimeHeader(request, "user-agent")?.contains(
        "ai-sdk/xai/4.0.40"
    ) == true)
    #expect(try xaiRealtimeRequestJSON(request) == [
        "expires_after": .object(["seconds": 90])
    ])
}

@Test func xaiRealtimeUsesCustomBaseHostButCanonicalV1WebSocketPath() async throws {
    let transport = RecordingTransport(response: jsonResponse(
        #"{"value":"custom-secret"}"#
    ))
    let provider = try AIProviders.xAI(settings: ProviderSettings(
        apiKey: "key",
        baseURL: "https://gateway.example:8443/custom/v1",
        environment: [:],
        transport: transport
    ))
    let model = try provider.realtimeModel("grok-voice-latest")

    let result = try await model.createClientSecret()

    #expect(result.url ==
        "wss://gateway.example:8443/v1/realtime?model=grok-voice-latest")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString ==
        "https://gateway.example:8443/custom/v1/realtime/client_secrets")
    #expect(try xaiRealtimeRequestJSON(request) == .object([:]))
}

@Test func xaiRealtimeSurfacesStructuredSecretHTTPAndSchemaErrors() async throws {
    let failedTransport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 401,
        headers: ["x-request-id": "request-1"],
        body: Data(#"{"error":"unauthorized"}"#.utf8)
    ))
    let failedProvider = try AIProviders.xAI(settings: ProviderSettings(
        apiKey: "bad-key",
        environment: [:],
        transport: failedTransport
    ))

    do {
        _ = try await failedProvider.realtime("grok-voice-latest")
            .createClientSecret()
        Issue.record("Expected an xAI client-secret API error")
    } catch let AIError.apiCall(error) {
        #expect(error.provider == "xai.realtime")
        #expect(error.statusCode == 401)
        #expect(error.responseHeaders["x-request-id"] == "request-1")
        #expect(error.responseBody ==
            #"xAI realtime client secret request failed: 401 {"error":"unauthorized"}"#)
        #expect(error.requestBody == .object([:]))
    }

    let invalidTransport = RecordingTransport(response: jsonResponse(
        #"{"expires_at":123}"#
    ))
    let invalidProvider = try AIProviders.xAI(settings: ProviderSettings(
        apiKey: "key",
        environment: [:],
        transport: invalidTransport
    ))
    do {
        _ = try await invalidProvider.realtime("grok-voice-latest")
            .createClientSecret()
        Issue.record("Expected an invalid secret response error")
    } catch let AIError.invalidResponse(provider, message) {
        #expect(provider == "xai.realtime")
        #expect(message == "Client secret response is missing value.")
    }
}

@Test func xaiRealtimeBuildsNativeSessionConfigAndMergesProviderOptions() throws {
    let model = try xaiRealtimeTestModel()
    let config = AIRealtimeSessionConfiguration(
        instructions: "You are helpful",
        voice: "Ara",
        outputModalities: [.audio],
        inputAudioFormat: AIRealtimeAudioFormat(
            type: "audio/pcm",
            rate: 24_000
        ),
        inputAudioTranscription: AIRealtimeAudioTranscriptionConfiguration(
            model: "whisper-1",
            language: "en"
        ),
        outputAudioTranscription: AIRealtimeAudioTranscriptionConfiguration(
            model: "transcribe-output"
        ),
        outputAudioFormat: AIRealtimeAudioFormat(type: "audio/pcmu"),
        turnDetection: AIRealtimeTurnDetectionConfiguration(
            type: .semanticVAD,
            threshold: 0.7,
            silenceDurationMilliseconds: 600,
            prefixPaddingMilliseconds: 250
        ),
        tools: [AIRealtimeToolDefinition(
            name: "weather",
            description: "Read weather",
            parameters: [
                "type": "object",
                "properties": .object(["city": ["type": "string"]])
            ]
        )],
        providerOptions: [
            "modalities": .array(["audio"]),
            "temperature": 0.4,
            "tools": .array([["type": "mcp", "server_label": "docs"]])
        ]
    )

    let result = model.buildSessionConfig(config)

    let expected: JSONValue = .object([
        "instructions": "You are helpful",
        "voice": "Ara",
        "audio": .object([
            "input": .object([
                "format": .object([
                    "type": "audio/pcm",
                    "rate": 24_000
                ])
            ]),
            "output": .object([
                "format": .object(["type": "audio/pcmu"])
            ])
        ]),
        "turn_detection": .object([
            "type": "server_vad",
            "threshold": 0.7,
            "silence_duration_ms": 600,
            "prefix_padding_ms": 250
        ]),
        "tools": .array([
            .object([
                "type": "function",
                "name": "weather",
                "description": "Read weather",
                "parameters": .object([
                    "type": "object",
                    "properties": .object([
                        "city": .object(["type": "string"])
                    ])
                ])
            ]),
            .object(["type": "mcp", "server_label": "docs"])
        ]),
        "modalities": .array(["audio"]),
        "temperature": 0.4
    ])
    #expect(result == expected)

    // These normalized fields are intentionally not mapped by upstream xAI.
    #expect(result["output_modalities"] == nil)
    #expect(result["input_audio_transcription"] == nil)
    #expect(result["output_audio_transcription"] == nil)
    #expect(model.buildSessionConfig(AIRealtimeSessionConfiguration(
        turnDetection: AIRealtimeTurnDetectionConfiguration(type: .disabled)
    )) == ["turn_detection": nil])
}

@Test func xaiRealtimeSerializesEveryClientEventAndDropsTruncate() async throws {
    let model = try xaiRealtimeTestModel()

    #expect(try await model.serializeClientEvent(.inputAudioAppend(
        audio: "AQID"
    )) == .json([
        "type": "input_audio_buffer.append",
        "audio": "AQID"
    ]))
    #expect(try await model.serializeClientEvent(.inputAudioCommit) ==
        .json(["type": "input_audio_buffer.commit"]))
    #expect(try await model.serializeClientEvent(.inputAudioClear) ==
        .json(["type": "input_audio_buffer.clear"]))
    #expect(try await model.serializeClientEvent(.conversationItemCreate(
        .textMessage(text: "Hello")
    )) == .json([
        "type": "conversation.item.create",
        "item": .object([
            "type": "message",
            "role": "user",
            "content": .array([["type": "input_text", "text": "Hello"]])
        ])
    ]))
    #expect(try await model.serializeClientEvent(.conversationItemCreate(
        .audioMessage(audio: "audio-base64")
    )) == .json([
        "type": "conversation.item.create",
        "item": .object([
            "type": "message",
            "role": "user",
            "content": .array([[
                "type": "input_audio",
                "audio": "audio-base64"
            ]])
        ])
    ]))
    #expect(try await model.serializeClientEvent(.conversationItemCreate(
        .functionCallOutput(
            callID: "call-1",
            name: "ignored-by-xai",
            output: #"{"temperature":20}"#
        )
    )) == .json([
        "type": "conversation.item.create",
        "item": .object([
            "type": "function_call_output",
            "call_id": "call-1",
            "output": #"{"temperature":20}"#
        ])
    ]))
    #expect(try await model.serializeClientEvent(.conversationItemTruncate(
        itemID: "item-1",
        contentIndex: 0,
        audioEndMilliseconds: 100
    )) == nil)
    #expect(try await model.serializeClientEvent(.responseCreate(
        options: AIRealtimeResponseOptions(
            modalities: ["audio", "text"],
            instructions: "Answer",
            metadata: ["ignored": true]
        )
    )) == .json([
        "type": "response.create",
        "response": .object([
            "modalities": .array(["audio", "text"]),
            "instructions": "Answer"
        ])
    ]))
    #expect(try await model.serializeClientEvent(.responseCancel) ==
        .json(["type": "response.cancel"]))
}

@Test func xaiRealtimeMapsNormalizedServerLifecycleAndProviderErrors() throws {
    let model = try xaiRealtimeTestModel()

    let sessionRaw: JSONValue = [
        "type": "session.created",
        "session": .object(["id": "session-1"])
    ]
    #expect(model.parseServerEvent(sessionRaw) == [
        .sessionCreated(sessionID: "session-1", raw: sessionRaw)
    ])

    let speechRaw: JSONValue = [
        "type": "input_audio_buffer.speech_started",
        "item_id": "item-user"
    ]
    #expect(model.parseServerEvent(speechRaw) == [
        .speechStarted(itemID: "item-user", raw: speechRaw)
    ])

    let committedRaw: JSONValue = [
        "type": "input_audio_buffer.committed",
        "item_id": "item-user",
        "previous_item_id": "item-before"
    ]
    #expect(model.parseServerEvent(committedRaw) == [
        .audioCommitted(
            itemID: "item-user",
            previousItemID: "item-before",
            raw: committedRaw
        )
    ])

    let itemRaw: JSONValue = [
        "type": "conversation.item.added",
        "item": .object(["id": "item-assistant", "role": "assistant"])
    ]
    #expect(model.parseServerEvent(itemRaw) == [
        .conversationItemAdded(
            itemID: "item-assistant",
            item: itemRaw["item"] ?? .null,
            raw: itemRaw
        )
    ])

    let transcriptionRaw: JSONValue = [
        "type": "conversation.item.input_audio_transcription.completed",
        "item_id": "item-user",
        "transcript": "Hello"
    ]
    #expect(model.parseServerEvent(transcriptionRaw) == [
        .inputTranscriptionCompleted(
            itemID: "item-user",
            transcript: "Hello",
            raw: transcriptionRaw
        )
    ])

    let responseRaw: JSONValue = [
        "type": "response.done",
        "response": .object(["id": "response-1", "status": "completed"])
    ]
    #expect(model.parseServerEvent(responseRaw) == [
        .responseDone(
            responseID: "response-1",
            status: "completed",
            raw: responseRaw
        )
    ])

    let audioRaw: JSONValue = [
        "type": "response.output_audio.delta",
        "response_id": "response-1",
        "item_id": "item-assistant",
        "delta": "AQID"
    ]
    #expect(model.parseServerEvent(audioRaw) == [
        .audioDelta(
            responseID: "response-1",
            itemID: "item-assistant",
            delta: "AQID",
            raw: audioRaw
        )
    ])

    let transcriptRaw: JSONValue = [
        "type": "response.output_audio_transcript.done",
        "response_id": "response-1",
        "item_id": "item-assistant",
        "transcript": "Hi"
    ]
    #expect(model.parseServerEvent(transcriptRaw) == [
        .audioTranscriptDone(
            responseID: "response-1",
            itemID: "item-assistant",
            transcript: "Hi",
            raw: transcriptRaw
        )
    ])

    let textRaw: JSONValue = [
        "type": "response.text.delta",
        "response_id": "response-1",
        "item_id": "item-assistant",
        "delta": "Hello"
    ]
    #expect(model.parseServerEvent(textRaw) == [
        .textDelta(
            responseID: "response-1",
            itemID: "item-assistant",
            delta: "Hello",
            raw: textRaw
        )
    ])

    let toolRaw: JSONValue = [
        "type": "response.function_call_arguments.done",
        "response_id": "response-1",
        "item_id": "item-tool",
        "call_id": "call-1",
        "name": "weather",
        "arguments": #"{"city":"Tokyo"}"#
    ]
    #expect(model.parseServerEvent(toolRaw) == [
        .functionCallArgumentsDone(
            responseID: "response-1",
            itemID: "item-tool",
            callID: "call-1",
            name: "weather",
            arguments: #"{"city":"Tokyo"}"#,
            raw: toolRaw
        )
    ])

    let customRaw: JSONValue = ["type": "mcp_list_tools.completed"]
    #expect(model.parseServerEvent(customRaw) == [
        .custom(rawType: "mcp_list_tools.completed", raw: customRaw)
    ])

    let errorRaw: JSONValue = [
        "type": "error",
        "error": .object(["message": "Bad audio", "code": "bad_audio"])
    ]
    #expect(model.parseServerEvent(errorRaw) == [
        .error(message: "Bad audio", code: "bad_audio", raw: errorRaw)
    ])
}

@Test func xaiRealtimeRunsOverInjectedDuplexSession() async throws {
    let model = try xaiRealtimeTestModel()
    let webSocket = RealtimeTestWebSocketTransport()
    let session = try await AIRealtimeSession.connect(
        model: model,
        clientSecret: AIRealtimeClientSecretResult(
            token: "browser-secret",
            url: "wss://api.x.ai/v1/realtime?model=grok-voice-latest",
            expiresAt: 999
        ),
        sessionConfiguration: AIRealtimeSessionConfiguration(
            instructions: "Speak briefly",
            voice: "Ara"
        ),
        webSocketTransport: webSocket
    )
    let eventsTask = Task { try await realtimeCollect(session.events) }

    let sendTask = Task {
        try await session.appendAudio(Data([1, 2, 3]))
        try await session.commitAudio()
        try await session.sendText("Hello")
        try await session.createResponse()
    }
    webSocket.connection.open(protocol: "xai-client-secret.browser-secret")
    try await sendTask.value

    let deltaRaw: JSONValue = [
        "type": "response.text.delta",
        "response_id": "response-1",
        "item_id": "item-1",
        "delta": "Hi"
    ]
    webSocket.connection.sendJSON(deltaRaw)
    webSocket.connection.serverClose(code: 1000)

    #expect(try await eventsTask.value == [
        .opened(protocol: "xai-client-secret.browser-secret"),
        .server(.textDelta(
            responseID: "response-1",
            itemID: "item-1",
            delta: "Hi",
            raw: deltaRaw
        )),
        .closed(.normalClosure)
    ])
    #expect(session.clientSecretExpiresAt == 999)

    let request = try #require(webSocket.requests().first)
    #expect(request.url.absoluteString ==
        "wss://api.x.ai/v1/realtime?model=grok-voice-latest")
    #expect(request.protocols == ["xai-client-secret.browser-secret"])
    #expect(request.headers.isEmpty)

    let sent = try webSocket.connection.sentJSONMessages()
    #expect(sent == [
        [
            "type": "session.update",
            "session": .object([
                "instructions": "Speak briefly",
                "voice": "Ara"
            ])
        ],
        ["type": "input_audio_buffer.append", "audio": "AQID"],
        ["type": "input_audio_buffer.commit"],
        [
            "type": "conversation.item.create",
            "item": .object([
                "type": "message",
                "role": "user",
                "content": .array([[
                    "type": "input_text",
                    "text": "Hello"
                ]])
            ])
        ],
        ["type": "response.create"]
    ])
}

private func xaiRealtimeTestModel() throws -> XAIRealtimeModel {
    let provider = try AIProviders.xAI(settings: ProviderSettings(
        apiKey: "xai-test-key",
        environment: [:],
        transport: RecordingTransport(response: jsonResponse("{}"))
    ))
    return try provider.realtime("grok-voice-latest")
}

private func xaiRealtimeHeader(
    _ request: AIHTTPRequest,
    _ name: String
) -> String? {
    request.headers.first {
        $0.key.caseInsensitiveCompare(name) == .orderedSame
    }?.value
}

private func xaiRealtimeRequestJSON(
    _ request: AIHTTPRequest
) throws -> JSONValue {
    try JSONDecoder().decode(
        JSONValue.self,
        from: try #require(request.body)
    )
}
