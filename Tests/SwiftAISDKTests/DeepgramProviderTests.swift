import Foundation
import Testing
@testable import SwiftAISDK

@Test func deepgramTranscriptionPostsRawAudioToListenEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"results":{"channels":[{"alternatives":[{"transcript":"hello world","words":[]}],"detected_language":"en"}]},"metadata":{"duration":1.2}}
    """))
    let provider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transport))
    let model = try provider.transcriptionModel("nova-3")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        fileName: "clip.wav",
        mimeType: "audio/wav",
        language: "en",
        extraBody: [
            "detectLanguage": .bool(false),
            "detectEntities": .bool(true),
            "fillerWords": .bool(true),
            "smartFormat": .bool(true),
            "summarize": .string("v2"),
            "topics": .bool(true),
            "utterances": .bool(true),
            "uttSplit": .number(0.8),
            "redact": .array([.string("ssn"), .string("pci")]),
            "search": .string("Codex")
        ]
    ))

    #expect(result.text == "hello world")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepgram.com/v1/listen?detect_entities=true&detect_language=false&diarize=true&filler_words=true&model=nova-3&redact=ssn%2Cpci&search=Codex&smart_format=true&summarize=v2&topics=true&utt_split=0.8&utterances=true")
    #expect(request.headers["authorization"] == "Token deepgram-key")
    #expect(request.headers["content-type"] == "audio/wav")
    #expect(request.body == Data("wav".utf8))
}

@Test func deepgramTranscriptionUsesProviderOptionsNamespaceAndMapsUpstreamOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"results":{"channels":[{"alternatives":[{"transcript":"hej","words":[{"word":"hej","start":0,"end":0.5}]}],"detected_language":"sv"}]},"metadata":{"duration":0.5}}
    """))
    let provider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transport))
    let model = try provider.transcriptionModel("nova-3")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        mimeType: "audio/wav",
        language: "en",
        providerOptions: [
            "deepgram": .object([
                "language": .string("sv"),
                "detectLanguage": .bool(true),
                "diarize": .bool(false),
                "paragraphs": .bool(true),
                "intents": .bool(true),
                "sentiment": .bool(true),
                "replace": .string("redacted"),
                "keyterm": .string("SwiftAISDK"),
                "smartFormat": .bool(true),
                "unsupportedProperty": .string("drop-me")
            ]),
            "openai": .string("should-not-leak")
        ]
    ))

    #expect(result.text == "hej")
    #expect(result.language == "sv")
    #expect(result.durationInSeconds == 0.5)
    #expect(result.segments == [TranscriptionSegment(text: "hej", startSecond: 0, endSecond: 0.5)])

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepgram.com/v1/listen?detect_language=true&diarize=false&language=sv&model=nova-3&smart_format=true")
    #expect(request.headers["content-type"] == "audio/wav")
    #expect(request.body == Data("wav".utf8))
}

@Test func deepgramTranscriptionProviderOptionsRejectInvalidSchemaFields() async throws {
    let provider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: RecordingTransport(response: jsonResponse(#"{}"#))))
    let model = try provider.transcriptionModel("nova-3")

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("wav".utf8),
            providerOptions: ["deepgram": .string("invalid")]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("wav".utf8),
            providerOptions: ["deepgram": .object(["detectLanguage": .string("true")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("wav".utf8),
            providerOptions: ["deepgram": .object(["summarize": .bool(true)])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("wav".utf8),
            providerOptions: ["deepgram": .object(["redact": .array([.string("ssn"), .number(123)])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("wav".utf8),
            providerOptions: ["deepgram": .object(["uttSplit": .string("0.8")])]
        ))
    }
}

@Test func deepgramTranscriptionIgnoresStandardLanguageLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"results":{"channels":[{"alternatives":[{"transcript":"hello","words":[]}]}]}}
    """))
    let provider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transport))
    let model = try provider.transcriptionModel("nova-3")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        mimeType: "audio/wav",
        language: "fr"
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepgram.com/v1/listen?diarize=true&model=nova-3")
}

@Test func deepgramAudioModelsMapNestedExtraBodyOptions() async throws {
    let transcriptionTransport = RecordingTransport(response: jsonResponse("""
    {"results":{"channels":[{"alternatives":[{"transcript":"nested","words":[]}],"detected_language":"ja"}]}}
    """))
    let transcriptionProvider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transcriptionTransport))
    let transcriptionModel = try transcriptionProvider.transcriptionModel("nova-3")

    _ = try await transcriptionModel.transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        mimeType: "audio/wav",
        language: "en",
        extraBody: [
            "deepgram": .object([
                "language": .string("ja"),
                "detectLanguage": .bool(true),
                "diarize": .bool(false),
                "smartFormat": .bool(true)
            ])
        ]
    ))

    let transcriptionRequest = try #require(await transcriptionTransport.requests().first)
    #expect(transcriptionRequest.url.absoluteString == "https://api.deepgram.com/v1/listen?detect_language=true&diarize=false&language=ja&model=nova-3&smart_format=true")

    let speechTransport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("audio".utf8)))
    let speechProvider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: speechTransport))
    let speechModel = try speechProvider.speechModel("aura-2-helena-en")

    _ = try await speechModel.speak(SpeechRequest(
        text: "Hello",
        format: "wav_24000",
        extraBody: [
            "deepgram": .object([
                "encoding": .string("mp3"),
                "bitRate": .number(48000),
                "sampleRate": .number(16000),
                "callbackMethod": .string("POST"),
                "mipOptOut": .bool(true)
            ])
        ]
    ))

    let speechRequest = try #require(await speechTransport.requests().first)
    #expect(speechRequest.url.absoluteString == "https://api.deepgram.com/v1/speak?bit_rate=48000&callback_method=POST&encoding=mp3&mip_opt_out=true&model=aura-2-helena-en")
}

@Test func deepgramSpeechUsesSpeakEndpointWithFormatQuery() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/wav"], body: Data("audio".utf8)))
    let provider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transport))
    let model = try provider.speechModel("aura-2-helena-en")

    let result = try await model.speak(SpeechRequest(
        text: "Hello",
        voice: "ignored-voice",
        format: "wav_24000",
        extraBody: [
            "callback": .string("https://example.com/hook"),
            "callbackMethod": .string("PUT"),
            "mipOptOut": .bool(true),
            "tag": .array([.string("test"), .string("swift")])
        ]
    ))

    #expect(result.audio == Data("audio".utf8))
    #expect(result.contentType == "audio/wav")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepgram.com/v1/speak?callback=https%3A%2F%2Fexample.com%2Fhook&callback_method=PUT&container=wav&encoding=linear16&mip_opt_out=true&model=aura-2-helena-en&sample_rate=24000&tag=test%2Cswift")
    #expect(request.headers["authorization"] == "Token deepgram-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["text"]?.stringValue == "Hello")
}

@Test func deepgramSpeechUsesProviderOptionsWarningsAndAbortSignal() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        headers: ["content-type": "audio/mpeg", "deepgram-header": "speech"],
        body: Data("deepgram-audio".utf8)
    ))
    let provider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transport))
    let model = try provider.speechModel("aura-2-helena-en")
    let controller = AIAbortController()

    let result = try await model.speak(SpeechRequest(
        text: "Hello",
        voice: "different-voice",
        format: "linear16_16000",
        providerOptions: [
            "deepgram": .object([
                "encoding": .string("mp3"),
                "container": .string("wav"),
                "sampleRate": .number(16000),
                "bitRate": .number(48000),
                "callback": .string("https://example.com/callback"),
                "callbackMethod": .string("POST"),
                "mipOptOut": .bool(true),
                "tag": .array([.string("tag1"), .string("tag2")]),
                "unsupportedProperty": .string("drop-me")
            ]),
            "openai": .string("should-not-leak")
        ],
        abortSignal: controller.signal
    ))

    #expect(result.audio == Data("deepgram-audio".utf8))
    #expect(result.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "providerOptions",
            message: "Encoding \"mp3\" does not support container parameter. Container \"wav\" was ignored."
        ),
        AIWarning(
            type: "unsupported",
            feature: "providerOptions",
            message: "Encoding \"mp3\" has a fixed sample rate and does not support sample_rate parameter. Sample rate 16000 was ignored."
        ),
        AIWarning(
            type: "unsupported",
            feature: "voice",
            message: "Deepgram TTS models embed the voice in the model ID. The voice parameter \"different-voice\" was ignored. Use the model ID to select a voice (e.g., \"aura-2-helena-en\")."
        )
    ])

    let request = try #require(await transport.requests().first)
    #expect(request.abortSignal === controller.signal)
    #expect(request.url.absoluteString == "https://api.deepgram.com/v1/speak?bit_rate=48000&callback=https%3A%2F%2Fexample.com%2Fcallback&callback_method=POST&encoding=mp3&mip_opt_out=true&model=aura-2-helena-en&tag=tag1%2Ctag2")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["text"]?.stringValue == "Hello")
}

@Test func deepgramSpeechProviderOptionsRejectInvalidSchemaFields() async throws {
    let provider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: RecordingTransport(response: AIHTTPResponse(statusCode: 200, body: Data()))))
    let model = try provider.speechModel("aura-2-helena-en")

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            providerOptions: ["deepgram": .number(1)]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            providerOptions: ["deepgram": .object(["bitRate": .bool(true)])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            providerOptions: ["deepgram": .object(["sampleRate": .string("24000")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            providerOptions: ["deepgram": .object(["callback": .string("not-a-url")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            providerOptions: ["deepgram": .object(["callbackMethod": .string("PATCH")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            providerOptions: ["deepgram": .object(["mipOptOut": .string("true")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            providerOptions: ["deepgram": .object(["tag": .array([.string("ok"), .object(["bad": true])])])]
        ))
    }
}

@Test func deepgramSpeechWarnsForUnsupportedStandardOptions() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("audio".utf8)))
    let provider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transport))
    let model = try provider.speechModel("aura-2-helena-en")

    let result = try await model.speak(SpeechRequest(
        text: "Hello",
        speed: 1.5,
        language: "en",
        instructions: "Speak slowly"
    ))

    #expect(result.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "speed",
            message: "Deepgram TTS REST API does not support speed adjustment. Speed parameter was ignored."
        ),
        AIWarning(
            type: "unsupported",
            feature: "language",
            message: "Deepgram TTS models are language-specific via the model ID. Language parameter \"en\" was ignored. Select a model with the appropriate language suffix (e.g., \"-en\" for English)."
        ),
        AIWarning(
            type: "unsupported",
            feature: "instructions",
            message: "Deepgram TTS REST API does not support instructions. Instructions parameter was ignored."
        )
    ])

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepgram.com/v1/speak?encoding=mp3&model=aura-2-helena-en")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["text"]?.stringValue == "Hello")
    #expect(body["speed"] == nil)
    #expect(body["language"] == nil)
    #expect(body["instructions"] == nil)
}

@Test func deepgramSpeechCleansIncompatibleParametersWhenEncodingChanges() async throws {
    let transport = RecordingTransport(responses: [
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("mp3".utf8)),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/ogg"], body: Data("ogg".utf8)),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/wav"], body: Data("wav".utf8))
    ])
    let provider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transport))
    let model = try provider.speechModel("aura-2-helena-en")

    _ = try await model.speak(SpeechRequest(
        text: "Hello",
        format: "linear16_16000",
        providerOptions: ["deepgram": .object(["encoding": .string("mp3")])]
    ))
    _ = try await model.speak(SpeechRequest(
        text: "Hello",
        format: "linear16_16000",
        providerOptions: ["deepgram": .object(["encoding": .string("opus")])]
    ))
    _ = try await model.speak(SpeechRequest(
        text: "Hello",
        format: "mp3",
        providerOptions: ["deepgram": .object(["encoding": .string("linear16"), "bitRate": .number(48000)])]
    ))

    let requests = await transport.requests()
    #expect(requests[0].url.absoluteString == "https://api.deepgram.com/v1/speak?encoding=mp3&model=aura-2-helena-en")
    #expect(requests[1].url.absoluteString == "https://api.deepgram.com/v1/speak?container=ogg&encoding=opus&model=aura-2-helena-en")
    #expect(requests[2].url.absoluteString == "https://api.deepgram.com/v1/speak?container=wav&encoding=linear16&model=aura-2-helena-en")
}

@Test func deepgramSpeechCleansIncompatibleParametersWhenContainerChangesEncoding() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/ogg"], body: Data("ogg".utf8)))
    let provider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transport))
    let model = try provider.speechModel("aura-2-helena-en")

    _ = try await model.speak(SpeechRequest(
        text: "Hello",
        format: "linear16_16000",
        providerOptions: ["deepgram": .object(["container": .string("ogg")])]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepgram.com/v1/speak?container=ogg&encoding=opus&model=aura-2-helena-en")
}
