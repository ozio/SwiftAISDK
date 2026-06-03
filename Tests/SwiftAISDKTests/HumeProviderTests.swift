import Foundation
import Testing
@testable import SwiftAISDK

@Test func humeSpeechUsesTTSFileEndpointWithUtterances() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("hume".utf8)))
    let provider = try AIProviders.hume(settings: ProviderSettings(apiKey: "hume-key", transport: transport))
    let model = try provider.speechModel("")

    let result = try await model.speak(SpeechRequest(
        text: "Hello",
        voice: "voice-id",
        format: "wav",
        extraBody: [
            "context": .object([
                "utterances": .array([
                    .object([
                        "text": .string("Earlier line"),
                        "description": .string("warm"),
                        "speed": .number(0.9),
                        "trailingSilence": .number(0.25),
                        "voice": .object(["id": .string("prior-voice"), "provider": .string("HUME_AI")])
                    ])
                ])
            ])
        ]
    ))

    #expect(result.audio == Data("hume".utf8))
    #expect(result.warnings == [])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.hume.ai/v0/tts/file")
    #expect(request.headers["x-hume-api-key"] == "hume-key")
    #expect(request.headers["user-agent"] == "ai-sdk/hume/2.0.33")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["utterances"]?[0]?["text"]?.stringValue == "Hello")
    #expect(body["utterances"]?[0]?["voice"]?["id"]?.stringValue == "voice-id")
    #expect(body["utterances"]?[0]?["voice"]?["provider"]?.stringValue == "HUME_AI")
    #expect(body["format"]?["type"]?.stringValue == "wav")
    #expect(body["context"]?["utterances"]?[0]?["trailing_silence"]?.doubleValue == 0.25)
    #expect(body["context"]?["utterances"]?[0]?["trailingSilence"] == nil)
    #expect(body["context"]?["utterances"]?[0]?["voice"]?["id"]?.stringValue == "prior-voice")
}

@Test func humeSpeechNoArgFactoryAndCustomUserAgentMirrorUpstream() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("hume".utf8)))
    let provider = try AIProviders.hume(settings: ProviderSettings(
        apiKey: "hume-key",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: transport
    ))
    let model = try provider.speech()

    let result = try await model.speak(SpeechRequest(text: "Hello"))

    #expect(model.modelID == "")
    #expect(result.responseMetadata.modelID == "")
    let request = try #require(await transport.requests().first)
    #expect(request.headers["user-agent"] == "CustomApp/1.0 ai-sdk/hume/2.0.33")
}

@Test func humeSpeechIgnoresModelIDLikeUpstreamNoArgFactory() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("hume".utf8)))
    let provider = try AIProviders.hume(settings: ProviderSettings(apiKey: "hume-key", transport: transport))
    let model = try provider.speechModel("ignored-by-upstream")

    let result = try await model.speak(SpeechRequest(text: "Hello"))

    #expect(result.responseMetadata.modelID == "")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.hume.ai/v0/tts/file")
}

@Test func humeSpeechMapsNestedExtraBodyOptionsAndUtteranceFields() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("hume".utf8)))
    let provider = try AIProviders.hume(settings: ProviderSettings(apiKey: "hume-key", transport: transport))
    let model = try provider.speechModel("")

    _ = try await model.speak(SpeechRequest(
        text: "Hello",
        voice: "voice-id",
        format: "mp3",
        extraBody: [
            "hume": .object([
                "speed": 0.8,
                "description": "calm",
                "context": [
                    "generationId": "gen-123"
                ]
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["utterances"]?[0]?["text"]?.stringValue == "Hello")
    #expect(body["utterances"]?[0]?["speed"]?.doubleValue == 0.8)
    #expect(body["utterances"]?[0]?["description"]?.stringValue == "calm")
    #expect(body["context"]?["generation_id"]?.stringValue == "gen-123")
    #expect(body["hume"] == nil)
    #expect(body["speed"] == nil)
    #expect(body["description"] == nil)
    #expect(body["context"]?["generationId"] == nil)
}

@Test func humeSpeechMapsProviderOptionsNamespaceAndOverridesExtraBody() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/pcm"], body: Data("hume".utf8)))
    let provider = try AIProviders.hume(settings: ProviderSettings(apiKey: "hume-key", transport: transport))
    let model = try provider.speechModel("")

    _ = try await model.speak(SpeechRequest(
        text: "Hello",
        voice: "voice-id",
        format: "pcm",
        speed: 1.1,
        instructions: "bright",
        providerOptions: [
            "hume": .object([
                "context": [
                    "utterances": [
                        [
                            "text": "Provider line",
                            "description": "firm",
                            "speed": 1.2,
                            "trailingSilence": 0.35,
                            "voice": ["name": "Ivy", "provider": "CUSTOM_VOICE"]
                        ]
                    ]
                ],
                "speed": 2.0,
                "description": "drop-me",
                "unsupportedProperty": "drop-me"
            ]),
            "openai": .object(["voice": "alloy"])
        ],
        extraBody: [
            "hume": .object([
                "context": ["generationId": "ignored-generation"]
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["utterances"]?[0]?["speed"]?.doubleValue == 1.1)
    #expect(body["utterances"]?[0]?["description"]?.stringValue == "bright")
    #expect(body["format"]?["type"]?.stringValue == "pcm")
    #expect(body["context"]?["utterances"]?[0]?["text"]?.stringValue == "Provider line")
    #expect(body["context"]?["utterances"]?[0]?["description"]?.stringValue == "firm")
    #expect(body["context"]?["utterances"]?[0]?["speed"]?.doubleValue == 1.2)
    #expect(body["context"]?["utterances"]?[0]?["trailing_silence"]?.doubleValue == 0.35)
    #expect(body["context"]?["utterances"]?[0]?["voice"]?["name"]?.stringValue == "Ivy")
    #expect(body["context"]?["generation_id"] == nil)
    #expect(body["context"]?["generationId"] == nil)
    #expect(body["hume"] == nil)
    #expect(body["openai"] == nil)
    #expect(body["unsupportedProperty"] == nil)
}

@Test func humeSpeechTreatsNullProviderOptionsNamespaceAsNoop() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mp3"], body: Data("hume".utf8)))
    let provider = try AIProviders.hume(settings: ProviderSettings(apiKey: "hume-key", transport: transport))
    let model = try provider.speechModel("")

    _ = try await model.speak(SpeechRequest(
        text: "Hello",
        voice: "voice-id",
        providerOptions: ["hume": .null],
        extraBody: [
            "hume": .object([
                "speed": 0.8,
                "description": "calm",
                "context": ["generationId": "gen-123"]
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["utterances"]?[0]?["speed"]?.doubleValue == 0.8)
    #expect(body["utterances"]?[0]?["description"]?.stringValue == "calm")
    #expect(body["context"]?["generation_id"]?.stringValue == "gen-123")
}

@Test func humeSpeechScopesContextLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/wav"], body: Data("hume".utf8)))
    let provider = try AIProviders.hume(settings: ProviderSettings(apiKey: "hume-key", transport: transport))
    let model = try provider.speechModel("")

    _ = try await model.speak(SpeechRequest(
        text: "Hello",
        providerOptions: ["hume": .object(["context": .null])],
        extraBody: ["hume": .object(["context": ["generationId": "legacy-generation"]])]
    ))

    var body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["context"] == nil)

    _ = try await model.speak(SpeechRequest(
        text: "Hello",
        providerOptions: [
            "hume": .object([
                "context": [
                    "utterances": [
                        [
                            "text": "Provider line",
                            "description": "calm",
                            "speed": 0.85,
                            "trailingSilence": 0.2,
                            "unsupportedUtterance": "drop-me",
                            "voice": [
                                "id": "voice-id",
                                "name": "drop-name",
                                "provider": "HUME_AI",
                                "unsupportedVoice": "drop-me"
                            ]
                        ]
                    ]
                ]
            ])
        ]
    ))

    body = try decodeJSONBody(try #require((await transport.requests()).last?.body))
    let utterance = try #require(body["context"]?["utterances"]?[0])
    #expect(utterance["text"]?.stringValue == "Provider line")
    #expect(utterance["description"]?.stringValue == "calm")
    #expect(utterance["speed"]?.doubleValue == 0.85)
    #expect(utterance["trailing_silence"]?.doubleValue == 0.2)
    #expect(utterance["trailingSilence"] == nil)
    #expect(utterance["unsupportedUtterance"] == nil)
    #expect(utterance["voice"]?["id"]?.stringValue == "voice-id")
    #expect(utterance["voice"]?["name"] == nil)
    #expect(utterance["voice"]?["provider"]?.stringValue == "HUME_AI")
    #expect(utterance["voice"]?["unsupportedVoice"] == nil)
}

@Test func humeSpeechProviderOptionsRejectInvalidSchemaFields() async throws {
    let provider = try AIProviders.hume(settings: ProviderSettings(apiKey: "hume-key", transport: RecordingTransport(response: AIHTTPResponse(statusCode: 200, body: Data()))))
    let model = try provider.speechModel("")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.hume", message: "Hume provider options must be an object.")) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            providerOptions: ["hume": .string("invalid")]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            providerOptions: ["hume": .object(["context": .string("invalid")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            providerOptions: ["hume": .object(["context": .object([:])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            providerOptions: ["hume": .object(["context": .object(["generationId": .number(123)])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            providerOptions: ["hume": .object(["context": .object(["utterances": .string("invalid")])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            providerOptions: ["hume": .object(["context": .object(["utterances": .array([.object(["description": .string("missing text")])])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            providerOptions: ["hume": .object(["context": .object(["utterances": .array([.object(["text": .string("Line"), "speed": .string("fast")])])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            providerOptions: ["hume": .object(["context": .object(["utterances": .array([.object(["text": .string("Line"), "voice": .object(["provider": .string("HUME_AI")])])])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hello",
            providerOptions: ["hume": .object(["context": .object(["utterances": .array([.object(["text": .string("Line"), "voice": .object(["id": .string("voice-id"), "provider": .string("OTHER")])])])])])]
        ))
    }
}

@Test func humeSpeechMapsStandardSpeedInstructionsAndWarnsForLanguage() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("hume".utf8)))
    let provider = try AIProviders.hume(settings: ProviderSettings(apiKey: "hume-key", transport: transport))
    let model = try provider.speechModel("")

    let result = try await model.speak(SpeechRequest(
        text: "Bonjour",
        voice: "voice-id",
        speed: 1.4,
        language: "fr",
        instructions: "speak warmly"
    ))

    #expect(result.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "language",
            message: "Hume speech models do not support language selection. Language parameter \"fr\" was ignored."
        )
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["utterances"]?[0]?["speed"]?.doubleValue == 1.4)
    #expect(body["utterances"]?[0]?["description"]?.stringValue == "speak warmly")
    #expect(body["language"] == nil)
}

@Test func humeSpeechTreatsOutputFormatCaseSensitivelyLikeUpstream() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("hume".utf8)))
    let provider = try AIProviders.hume(settings: ProviderSettings(apiKey: "hume-key", transport: transport))
    let model = try provider.speechModel("")

    let result = try await model.speak(SpeechRequest(text: "Hello", format: "WAV"))

    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "outputFormat", message: "Unsupported output format: WAV. Using mp3 instead.")
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["format"]?["type"]?.stringValue == "mp3")
}

@Test func humeSpeechWarnsAndFallsBackForUnsupportedOutputFormat() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("hume".utf8)))
    let provider = try AIProviders.hume(settings: ProviderSettings(apiKey: "hume-key", transport: transport))
    let model = try provider.speechModel("")

    let result = try await model.speak(SpeechRequest(text: "Hello", format: "aac"))

    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "outputFormat", message: "Unsupported output format: aac. Using mp3 instead.")
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["format"]?["type"]?.stringValue == "mp3")
}
