import Foundation
import Testing
@testable import SwiftAISDK

@Test func cartesiaSpeechSendsRequiredBodyHeadersAndMetadata() async throws {
    let controller = AIAbortController()
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        headers: [
            "content-type": "audio/mpeg",
            "x-request-id": "speech-request"
        ],
        body: Data("cartesia-audio".utf8)
    ))
    let provider = try AIProviders.cartesia(settings: CartesiaProviderSettings(
        apiKey: "cartesia-key",
        version: "2026-04-01",
        headers: ["Custom-Provider-Header": "provider-value"],
        environment: [:],
        transport: transport
    ))
    let model = try provider.speechModel("sonic-3.5")

    let result = try await model.speak(SpeechRequest(
        text: "Hello, world!",
        voice: "voice-id",
        headers: ["Custom-Request-Header": "request-value"],
        abortSignal: controller.signal
    ))

    #expect(result.audio == Data("cartesia-audio".utf8))
    #expect(result.contentType == "audio/mpeg")
    #expect(result.responseMetadata.modelID == "sonic-3.5")
    #expect(result.responseMetadata.headers["x-request-id"] == "speech-request")
    #expect(result.requestMetadata.body == .object([
        "model_id": "sonic-3.5",
        "transcript": "Hello, world!",
        "voice": [
            "mode": "id",
            "id": "voice-id"
        ],
        "output_format": [
            "container": "mp3",
            "sample_rate": 44_100,
            "bit_rate": 128_000
        ]
    ]))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.cartesia.ai/tts/bytes")
    #expect(request.headers["authorization"] == "Bearer cartesia-key")
    #expect(request.headers["cartesia-version"] == "2026-04-01")
    #expect(request.headers["custom-provider-header"] == "provider-value")
    #expect(request.headers["Custom-Request-Header"] == "request-value")
    #expect(request.headers["user-agent"] == "ai-sdk/cartesia/3.0.10")
    #expect(request.abortSignal === controller.signal)
    #expect(try decodeJSONBody(try #require(request.body)) == result.requestMetadata.body)
}

@Test func cartesiaSpeechRequiresVoiceBeforeSendingRequest() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200))
    let provider = try AIProviders.cartesia(settings: CartesiaProviderSettings(
        apiKey: "cartesia-key",
        environment: [:],
        transport: transport
    ))
    let model = try provider.speechModel("sonic-3.5")

    await #expect(throws: AIError.invalidArgument(
        argument: "voice",
        message: "Cartesia speech models require a `voice` to be set."
    )) {
        _ = try await model.speak(SpeechRequest(text: "Hello"))
    }
    #expect(await transport.requests().isEmpty)
}

@Test func cartesiaSpeechMapsOutputFormatsAndSampleRatesLikeUpstream() async throws {
    let response = AIHTTPResponse(
        statusCode: 200,
        headers: ["content-type": "audio/wav"],
        body: Data("audio".utf8)
    )
    let transport = RecordingTransport(responses: Array(repeating: response, count: 6))
    let provider = try AIProviders.cartesia(settings: CartesiaProviderSettings(
        apiKey: "cartesia-key",
        environment: [:],
        transport: transport
    ))
    let model = try provider.speechModel("sonic-3.5")

    _ = try await model.speak(SpeechRequest(text: "a", voice: "voice", format: "wav"))
    _ = try await model.speak(SpeechRequest(text: "b", voice: "voice", format: "pcm_24000"))
    _ = try await model.speak(SpeechRequest(text: "c", voice: "voice", format: "alaw"))
    _ = try await model.speak(SpeechRequest(text: "d", voice: "voice", format: "mulaw_16000"))
    let invalidSuffix = try await model.speak(SpeechRequest(text: "e", voice: "voice", format: "wav_12345"))
    let unknown = try await model.speak(SpeechRequest(text: "f", voice: "voice", format: "flac"))

    let bodies = try await transport.requests().map {
        try decodeJSONBody(try #require($0.body))
    }
    #expect(bodies[0]["output_format"] == [
        "container": "wav",
        "encoding": "pcm_s16le",
        "sample_rate": 44_100
    ])
    #expect(bodies[1]["output_format"] == [
        "container": "raw",
        "encoding": "pcm_f32le",
        "sample_rate": 24_000
    ])
    #expect(bodies[2]["output_format"] == [
        "container": "raw",
        "encoding": "pcm_alaw",
        "sample_rate": 8_000
    ])
    #expect(bodies[3]["output_format"] == [
        "container": "raw",
        "encoding": "pcm_mulaw",
        "sample_rate": 16_000
    ])
    #expect(invalidSuffix.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "outputFormat",
            message: "Unsupported Cartesia sample rate in output format \"wav_12345\". Using 44100 Hz instead."
        )
    ])
    #expect(unknown.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "outputFormat",
            message: "Unknown output format \"flac\". Falling back to mp3. Use providerOptions.cartesia to configure container, encoding, and sampleRate directly."
        )
    ])
}

@Test func cartesiaSpeechProviderOptionsOverrideGenericOptions() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        headers: ["content-type": "audio/wav"],
        body: Data("audio".utf8)
    ))
    let provider = try AIProviders.cartesia(settings: CartesiaProviderSettings(
        apiKey: "cartesia-key",
        environment: [:],
        transport: transport
    ))
    let model = try provider.speechModel("sonic-3.5")

    let result = try await model.speak(SpeechRequest(
        text: "Hola",
        voice: "voice",
        format: "mp3",
        speed: 1.4,
        language: "en",
        instructions: "Whisper",
        providerOptions: [
            "cartesia": [
                "container": "wav",
                "encoding": "pcm_s16le",
                "sampleRate": 24_000,
                "speed": 0.8,
                "language": "es"
            ]
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["language"] == "es")
    #expect(body["generation_config"] == ["speed": 0.8])
    #expect(body["output_format"] == [
        "container": "wav",
        "encoding": "pcm_s16le",
        "sample_rate": 24_000
    ])
    #expect(result.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "instructions",
            message: "Cartesia speech models do not support instructions. Instructions parameter was ignored."
        )
    ])
}

@Test func cartesiaSpeechIgnoresEmptyGenericLanguageAndInstructions() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        body: Data("audio".utf8)
    ))
    let provider = try AIProviders.cartesia(settings: CartesiaProviderSettings(
        apiKey: "cartesia-key",
        environment: [:],
        transport: transport
    ))
    let model = try provider.speechModel("sonic-3.5")

    let result = try await model.speak(SpeechRequest(
        text: "Hello",
        voice: "voice",
        language: "",
        instructions: ""
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["language"] == nil)
    #expect(result.warnings.isEmpty)
}

@Test func cartesiaSpeechWarnsWhenContainerRejectsEncodingOrBitRate() async throws {
    let response = AIHTTPResponse(statusCode: 200, body: Data("audio".utf8))
    let transport = RecordingTransport(responses: [response, response])
    let provider = try AIProviders.cartesia(settings: CartesiaProviderSettings(
        apiKey: "cartesia-key",
        environment: [:],
        transport: transport
    ))
    let model = try provider.speechModel("sonic-3.5")

    let mp3 = try await model.speak(SpeechRequest(
        text: "mp3",
        voice: "voice",
        providerOptions: ["cartesia": ["encoding": "pcm_s16le"]]
    ))
    let raw = try await model.speak(SpeechRequest(
        text: "raw",
        voice: "voice",
        providerOptions: [
            "cartesia": [
                "container": "raw",
                "bitRate": 64_000
            ]
        ]
    ))

    #expect(mp3.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "providerOptions.cartesia.encoding",
            message: "Cartesia MP3 output does not accept an encoding. The encoding option was ignored."
        )
    ])
    #expect(raw.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "providerOptions.cartesia.bitRate",
            message: "Cartesia raw and WAV output do not accept a bit rate. The bitRate option was ignored."
        )
    ])
}

@Test func cartesiaSpeechValidatesProviderOptionsAndWarnsForGenericSpeed() async throws {
    let response = AIHTTPResponse(statusCode: 200, body: Data("audio".utf8))
    let transport = RecordingTransport(response: response)
    let provider = try AIProviders.cartesia(settings: CartesiaProviderSettings(
        apiKey: "cartesia-key",
        environment: [:],
        transport: transport
    ))
    let model = try provider.speechModel("sonic-3.5")

    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.cartesia.sampleRate",
        message: "Cartesia sampleRate must be one of 8000, 16000, 22050, 24000, 44100, 48000."
    )) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            voice: "voice",
            providerOptions: ["cartesia": ["sampleRate": 12_345]]
        ))
    }

    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.cartesia.sampleRate",
        message: "Cartesia sampleRate must be one of 8000, 16000, 22050, 24000, 44100, 48000."
    )) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            voice: "voice",
            providerOptions: ["cartesia": ["sampleRate": .number(1e300)]]
        ))
    }

    let result = try await model.speak(SpeechRequest(
        text: "Hello",
        voice: "voice",
        speed: 2
    ))
    #expect(result.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "speed",
            message: "Cartesia speed must be between 0.6 and 1.5. The speed option was ignored."
        )
    ])
}

@Test func cartesiaSpeechUsesStructuredErrorMessage() async throws {
    let headers = ["content-type": "application/json", "x-request-id": "error"]
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 401,
        headers: headers,
        body: Data("""
        {"error_code":"authentication_failed","title":"Authentication failed","message":"Invalid API key.","request_id":"request-id"}
        """.utf8)
    ))
    let provider = try AIProviders.cartesia(settings: CartesiaProviderSettings(
        apiKey: "bad-key",
        environment: [:],
        transport: transport
    ))
    let model = try provider.speechModel("sonic-3.5")

    await #expect(throws: AIError.apiCall(
        provider: "cartesia.speech",
        statusCode: 401,
        body: "Authentication failed: Invalid API key.",
        headers: headers
    )) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            voice: "voice"
        ))
    }
}

@Test func cartesiaSpeechFallsBackToRawErrorWhenSchemaIsInvalid() async throws {
    let rawBody = #"{"title":"Bad request","message":"Invalid.","request_id":"request-id","doc_url":null}"#
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 400,
        headers: ["content-type": "application/json"],
        body: Data(rawBody.utf8)
    ))
    let provider = try AIProviders.cartesia(settings: CartesiaProviderSettings(
        apiKey: "cartesia-key",
        environment: [:],
        transport: transport
    ))
    let model = try provider.speechModel("sonic-3.5")

    await #expect(throws: AIError.apiCall(
        provider: "cartesia.speech",
        statusCode: 400,
        body: rawBody,
        headers: ["content-type": "application/json"]
    )) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            voice: "voice"
        ))
    }
}
