import Foundation
import Testing
@testable import SwiftAISDK

@Test func lmntSpeechUsesBytesEndpointAndVoiceBody() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/aac"], body: Data("lmnt".utf8)))
    let provider = try AIProviders.lmnt(settings: ProviderSettings(apiKey: "lmnt-key", transport: transport))
    let model = try provider.speechModel("aurora")

    let result = try await model.speak(SpeechRequest(
        text: "Hi",
        voice: "ava",
        format: "aac",
        extraBody: [
            "sampleRate": .number(16000),
            "topP": .number(0.8),
            "temperature": .number(0.6),
            "seed": .number(42),
            "conversational": .bool(true),
            "length": .number(20),
            "format": .string("wav"),
            "model": .string("ignored")
        ]
    ))

    #expect(result.audio == Data("lmnt".utf8))
    #expect(result.warnings == [])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.lmnt.com/v1/ai/speech/bytes")
    #expect(request.headers["X-API-Key"] == "lmnt-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "aurora")
    #expect(body["text"]?.stringValue == "Hi")
    #expect(body["voice"]?.stringValue == "ava")
    #expect(body["response_format"]?.stringValue == "aac")
    #expect(body["sample_rate"]?.intValue == 16000)
    #expect(body["top_p"]?.doubleValue == 0.8)
    #expect(body["temperature"]?.doubleValue == 0.6)
    #expect(body["seed"]?.intValue == 42)
    #expect(body["conversational"]?.boolValue == true)
    #expect(body["length"]?.intValue == 20)
    #expect(body["sampleRate"] == nil)
    #expect(body["topP"] == nil)
    #expect(body["format"] == nil)
}

@Test func lmntSpeechMapsStandardSpeedAndLanguage() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mp3"], body: Data("lmnt".utf8)))
    let provider = try AIProviders.lmnt(settings: ProviderSettings(apiKey: "lmnt-key", transport: transport))
    let model = try provider.speechModel("aurora")

    _ = try await model.speak(SpeechRequest(
        text: "Bonjour",
        voice: "ava",
        speed: 1.5,
        language: "fr"
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["speed"]?.doubleValue == 1.5)
    #expect(body["language"]?.stringValue == "fr")
}

@Test func lmntSpeechMapsNestedExtraBodyOptions() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/wav"], body: Data("lmnt".utf8)))
    let provider = try AIProviders.lmnt(settings: ProviderSettings(apiKey: "lmnt-key", transport: transport))
    let model = try provider.speechModel("aurora")

    _ = try await model.speak(SpeechRequest(
        text: "Hi",
        voice: "ava",
        format: "wav",
        extraBody: [
            "lmnt": .object([
                "sampleRate": 24000,
                "topP": 0.7,
                "temperature": 0.5,
                "speed": 1.2,
                "seed": 77,
                "conversational": true,
                "length": 12,
                "format": "mp3",
                "model": "ignored"
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?.stringValue == "wav")
    #expect(body["sample_rate"]?.intValue == 24000)
    #expect(body["top_p"]?.doubleValue == 0.7)
    #expect(body["temperature"]?.doubleValue == 0.5)
    #expect(body["speed"]?.doubleValue == 1.2)
    #expect(body["seed"]?.intValue == 77)
    #expect(body["conversational"]?.boolValue == true)
    #expect(body["length"]?.intValue == 12)
    #expect(body["lmnt"] == nil)
    #expect(body["sampleRate"] == nil)
    #expect(body["format"] == nil)
}

@Test func lmntSpeechMapsProviderOptionsNamespaceAndOverridesExtraBody() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mulaw"], body: Data("lmnt".utf8)))
    let provider = try AIProviders.lmnt(settings: ProviderSettings(apiKey: "lmnt-key", transport: transport))
    let model = try provider.speechModel("aurora")

    _ = try await model.speak(SpeechRequest(
        text: "Hi",
        voice: "nova",
        format: "mulaw",
        providerOptions: [
            "lmnt": .object([
                "sampleRate": 8000,
                "topP": 0.6,
                "temperature": 0.4,
                "speed": 1.4,
                "seed": 88,
                "conversational": true,
                "length": 11,
                "format": "wav",
                "model": "ignored-provider",
                "unsupportedProperty": "drop-me"
            ]),
            "openai": .object(["voice": "alloy"])
        ],
        extraBody: [
            "lmnt": .object([
                "sampleRate": 24000,
                "topP": 0.9,
                "temperature": 0.9,
                "speed": 0.8,
                "seed": 1,
                "conversational": false,
                "length": 99,
                "format": "mp3",
                "model": "ignored-extra"
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "aurora")
    #expect(body["voice"]?.stringValue == "nova")
    #expect(body["response_format"]?.stringValue == "mulaw")
    #expect(body["sample_rate"]?.intValue == 8000)
    #expect(body["top_p"]?.doubleValue == 0.6)
    #expect(body["temperature"]?.doubleValue == 0.4)
    #expect(body["speed"]?.doubleValue == 1.4)
    #expect(body["seed"]?.intValue == 88)
    #expect(body["conversational"]?.boolValue == true)
    #expect(body["length"]?.intValue == 11)
    #expect(body["lmnt"] == nil)
    #expect(body["openai"] == nil)
    #expect(body["unsupportedProperty"] == nil)
    #expect(body["sampleRate"] == nil)
    #expect(body["format"] == nil)
}

@Test func lmntSpeechAppliesUpstreamProviderOptionDefaults() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mp3"], body: Data("lmnt".utf8)))
    let provider = try AIProviders.lmnt(settings: ProviderSettings(apiKey: "lmnt-key", transport: transport))
    let model = try provider.speechModel("aurora")

    _ = try await model.speak(SpeechRequest(
        text: "Hi",
        voice: "ava",
        speed: 1.5,
        providerOptions: ["lmnt": .object([:])],
        extraBody: [
            "lmnt": .object([
                "sampleRate": 8000,
                "topP": 0.5,
                "temperature": 0.5,
                "speed": 0.75,
                "conversational": true
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["sample_rate"]?.intValue == 24000)
    #expect(body["top_p"]?.intValue == 1)
    #expect(body["temperature"]?.intValue == 1)
    #expect(body["speed"]?.intValue == 1)
    #expect(body["conversational"]?.boolValue == false)
    #expect(body["model"]?.stringValue == "aurora")
    #expect(body["voice"]?.stringValue == "ava")
    #expect(body["response_format"]?.stringValue == "mp3")
}

@Test func lmntSpeechProviderOptionsNullishFieldsOmitDefaultsAndExtraBody() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/wav"], body: Data("lmnt".utf8)))
    let provider = try AIProviders.lmnt(settings: ProviderSettings(apiKey: "lmnt-key", transport: transport))
    let model = try provider.speechModel("aurora")

    _ = try await model.speak(SpeechRequest(
        text: "Hi",
        voice: "ava",
        format: "wav",
        speed: 1.5,
        providerOptions: [
            "lmnt": .object([
                "sampleRate": .null,
                "speed": .null,
                "topP": .null,
                "temperature": .null,
                "conversational": .null,
                "length": .null,
                "seed": .null,
                "format": .null,
                "model": .null
            ])
        ],
        extraBody: [
            "lmnt": .object([
                "sampleRate": 8000,
                "topP": 0.5,
                "temperature": 0.5,
                "speed": 0.75,
                "seed": 1,
                "conversational": true,
                "length": 20
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?.stringValue == "wav")
    #expect(body["speed"]?.doubleValue == 1.5)
    #expect(body["sample_rate"] == nil)
    #expect(body["top_p"] == nil)
    #expect(body["temperature"] == nil)
    #expect(body["conversational"] == nil)
    #expect(body["length"] == nil)
    #expect(body["seed"] == nil)
    #expect(body["sampleRate"] == nil)
}

@Test func lmntSpeechProviderOptionsRejectInvalidSchemaFields() async throws {
    let provider = try AIProviders.lmnt(settings: ProviderSettings(apiKey: "lmnt-key", transport: RecordingTransport(response: AIHTTPResponse(statusCode: 200, body: Data()))))
    let model = try provider.speechModel("aurora")

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hi",
            providerOptions: ["lmnt": .string("invalid")]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hi",
            providerOptions: ["lmnt": .object(["model": .number(1)])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hi",
            providerOptions: ["lmnt": .object(["format": .string("flac")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hi",
            providerOptions: ["lmnt": .object(["sampleRate": .number(44_100)])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hi",
            providerOptions: ["lmnt": .object(["speed": .number(0.1)])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hi",
            providerOptions: ["lmnt": .object(["seed": .number(1.5)])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hi",
            providerOptions: ["lmnt": .object(["conversational": .string("true")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hi",
            providerOptions: ["lmnt": .object(["length": .number(301)])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hi",
            providerOptions: ["lmnt": .object(["topP": .number(1.5)])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(
            text: "Hi",
            providerOptions: ["lmnt": .object(["temperature": .number(-0.1)])]
        ))
    }
}

@Test func lmntSpeechWarnsAndFallsBackForUnsupportedOutputFormat() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("lmnt".utf8)))
    let provider = try AIProviders.lmnt(settings: ProviderSettings(apiKey: "lmnt-key", transport: transport))
    let model = try provider.speechModel("aurora")

    let result = try await model.speak(SpeechRequest(text: "Hi", format: "flac"))

    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "outputFormat", message: "Unsupported output format: flac. Using mp3 instead.")
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?.stringValue == "mp3")
}
