import Foundation
import Testing
@testable import SwiftAISDK

@Test func fishAudioSpeechSendsRequiredRequestAndReturnsBinaryMetadata() async throws {
    let controller = AIAbortController()
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        headers: [
            "content-type": "audio/mpeg",
            "x-request-id": "fish-speech-request"
        ],
        body: Data([0, 1, 2, 3])
    ))
    let model = try createFishAudio(settings: ProviderSettings(
        apiKey: "fish-key",
        environment: [:],
        transport: transport
    )).speech("s2.1-pro")

    let result = try await model.speak(SpeechRequest(
        text: "Hello, world!",
        headers: ["X-Request": "request-value"],
        abortSignal: controller.signal
    ))

    #expect(result.audio == Data([0, 1, 2, 3]))
    #expect(result.contentType == "audio/mpeg")
    #expect(result.warnings.isEmpty)
    #expect(result.requestMetadata.body == [
        "text": "Hello, world!",
        "format": "mp3"
    ])
    #expect(result.responseMetadata.modelID == "s2.1-pro")
    #expect(result.responseMetadata.headers["x-request-id"] == "fish-speech-request")
    #expect(result.responseMetadata.timestamp != nil)

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.fish.audio/v1/tts")
    #expect(request.headers["authorization"] == "Bearer fish-key")
    #expect(request.headers["model"] == "s2.1-pro")
    #expect(request.headers["user-agent"] == "ai-sdk/fish-audio/3.0.5")
    #expect(request.headers["X-Request"] == "request-value")
    #expect(request.abortSignal === controller.signal)
    #expect(try decodeJSONBody(try #require(request.body)) == result.requestMetadata.body)
}

@Test func fishAudioSpeechMapsVoiceFormatsAndAllProviderOptions() async throws {
    let response = AIHTTPResponse(statusCode: 200, body: Data("audio".utf8))
    let transport = RecordingTransport(responses: Array(repeating: response, count: 5))
    let provider = try createFishAudio(settings: ProviderSettings(
        apiKey: "fish-key",
        environment: [:],
        transport: transport
    ))

    for format in ["wav", "pcm", "mp3", "opus"] {
        let result = try await provider.speech("s2-pro").speak(SpeechRequest(
            text: format,
            format: format.uppercased()
        ))
        #expect(result.warnings.isEmpty)
    }

    _ = try await provider.speech("s2-pro").speak(SpeechRequest(
        text: "<|speaker:0|>Hello<|speaker:1|>Hi",
        voice: "ignored-voice",
        speed: 1.2,
        providerOptions: [
            "fishAudio": [
                "referenceId": ["speaker-a", "speaker-b"],
                "sampleRate": 44_100,
                "mp3Bitrate": 192,
                "latency": "balanced",
                "volume": -3,
                "normalizeLoudness": false,
                "temperature": 0.5,
                "topP": 0.9,
                "chunkLength": 200,
                "minChunkLength": 20,
                "normalize": false,
                "maxNewTokens": 2_048,
                "repetitionPenalty": 1.5,
                "conditionOnPreviousChunks": false,
                "earlyStopThreshold": 0.8,
                "features": ["quality-guard"]
            ]
        ]
    ))

    let bodies = try await transport.requests().map {
        try decodeJSONBody(try #require($0.body))
    }
    #expect(bodies[0]["format"] == "wav")
    #expect(bodies[1]["format"] == "pcm")
    #expect(bodies[2]["format"] == "mp3")
    #expect(bodies[3]["format"] == "opus")
    #expect(bodies[4] == [
        "text": "<|speaker:0|>Hello<|speaker:1|>Hi",
        "format": "mp3",
        "reference_id": ["speaker-a", "speaker-b"],
        "prosody": [
            "speed": 1.2,
            "volume": -3,
            "normalize_loudness": false
        ],
        "sample_rate": 44_100,
        "mp3_bitrate": 192,
        "latency": "balanced",
        "temperature": 0.5,
        "top_p": 0.9,
        "chunk_length": 200,
        "min_chunk_length": 20,
        "normalize": false,
        "max_new_tokens": 2_048,
        "repetition_penalty": 1.5,
        "condition_on_previous_chunks": false,
        "early_stop_threshold": 0.8,
        "features": ["quality-guard"]
    ])
}

@Test func fishAudioSpeechWarnsForUnsupportedGenericSettings() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        body: Data("audio".utf8)
    ))
    let model = try createFishAudio(settings: ProviderSettings(
        apiKey: "fish-key",
        environment: [:],
        transport: transport
    )).speech("s1")

    let result = try await model.speak(SpeechRequest(
        text: "Hello",
        format: "flac",
        speed: 3,
        language: "en",
        instructions: "Speak slowly",
        providerOptions: [
            "fishAudio": ["normalizeLoudness": true]
        ]
    ))

    #expect(result.requestMetadata.body == [
        "text": "Hello",
        "format": "mp3"
    ])
    #expect(result.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "outputFormat",
            message: "Fish Audio does not support the output format \"flac\". Falling back to mp3. Supported formats are wav, pcm, mp3, opus."
        ),
        AIWarning(
            type: "unsupported",
            feature: "speed",
            message: "Fish Audio speed must be between 0.5 and 2. The speed option was ignored."
        ),
        AIWarning(
            type: "unsupported",
            feature: "providerOptions.fishAudio.normalizeLoudness",
            message: "Fish Audio ignores normalizeLoudness on s1. It is supported by the S2 family (s2-pro, s2.1-pro)."
        ),
        AIWarning(
            type: "unsupported",
            feature: "language",
            message: "Fish Audio infers the language from the input text and the selected voice, and has no language parameter. The language option was ignored."
        ),
        AIWarning(
            type: "unsupported",
            feature: "instructions",
            message: "Fish Audio does not support instructions. The instructions option was ignored."
        )
    ])
}

@Test func fishAudioSpeechAppliesFormatSpecificBitrates() async throws {
    let response = AIHTTPResponse(statusCode: 200, body: Data("audio".utf8))
    let transport = RecordingTransport(responses: [response, response, response])
    let model = try createFishAudio(settings: ProviderSettings(
        apiKey: "fish-key",
        environment: [:],
        transport: transport
    )).speech("s2.1-pro")

    let ignoredMP3 = try await model.speak(SpeechRequest(
        text: "one",
        format: "opus",
        providerOptions: ["fishAudio": ["mp3Bitrate": 192]]
    ))
    let ignoredOpus = try await model.speak(SpeechRequest(
        text: "two",
        providerOptions: ["fishAudio": ["opusBitrate": 48_000]]
    ))
    let opus = try await model.speak(SpeechRequest(
        text: "three",
        format: "opus",
        providerOptions: ["fishAudio": ["opusBitrate": -1_000]]
    ))

    #expect(ignoredMP3.warnings == [AIWarning(
        type: "unsupported",
        feature: "providerOptions.fishAudio.mp3Bitrate",
        message: "mp3Bitrate only applies to mp3 output. The option was ignored for opus output."
    )])
    #expect(ignoredOpus.warnings == [AIWarning(
        type: "unsupported",
        feature: "providerOptions.fishAudio.opusBitrate",
        message: "opusBitrate only applies to opus output. The option was ignored for mp3 output."
    )])
    #expect(opus.warnings.isEmpty)
    #expect(opus.requestMetadata.body?["opus_bitrate"] == -1_000)
}

@Test func fishAudioSpeechValidatesProviderOptionsAndKeepsExtraBodyEscapeHatch() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        body: Data("audio".utf8)
    ))
    let model = try createFishAudio(settings: ProviderSettings(
        apiKey: "fish-key",
        environment: [:],
        transport: transport
    )).speech("s2-pro")

    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.fishAudio.chunkLength",
        message: "Fish Audio chunkLength must be an integer between 100 and 300."
    )) {
        _ = try await model.speak(SpeechRequest(
            text: "invalid",
            providerOptions: ["fishAudio": ["chunkLength": 99]]
        ))
    }

    let result = try await model.speak(SpeechRequest(
        text: "override",
        voice: "voice",
        providerOptions: [
            "fishAudio": [
                "sampleRate": 24_000,
                "unknownOption": "stripped"
            ]
        ],
        extraBody: [
            "format": "wav",
            "custom_backend_flag": true
        ]
    ))
    #expect(result.requestMetadata.body == [
        "text": "override",
        "format": "wav",
        "reference_id": "voice",
        "sample_rate": 24_000,
        "custom_backend_flag": true
    ])
}

@Test func fishAudioSpeechSurfacesStructuredAPIError() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 402,
        headers: ["x-request-id": "failed-request"],
        body: Data(#"{"status":402,"message":"No payment -- see charging schemes"}"#.utf8)
    ))
    let model = try createFishAudio(settings: ProviderSettings(
        apiKey: "fish-key",
        environment: [:],
        transport: transport
    )).speech("s1")

    do {
        _ = try await model.speak(SpeechRequest(text: "Hello"))
        Issue.record("Expected Fish Audio API error")
    } catch let AIError.apiCall(error) {
        #expect(error.provider == "fish-audio.speech")
        #expect(error.statusCode == 402)
        #expect(error.responseBody == "No payment -- see charging schemes")
        #expect(error.responseHeaders["x-request-id"] == "failed-request")
    }
}
