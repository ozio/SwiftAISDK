import Foundation
import Testing
@testable import SwiftAISDK

@Test func elevenLabsSpeechUsesTextToSpeechVoiceEndpoint() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("eleven-audio".utf8)))
    let provider = try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: "eleven-key", transport: transport))
    let model = try provider.speechModel("eleven_multilingual_v2")

    let result = try await model.speak(SpeechRequest(
        text: "Hello",
        voice: "voice-123",
        format: "mp3_192",
        extraBody: [
            "languageCode": "en",
            "voiceSettings": ["similarityBoost": 0.7, "useSpeakerBoost": true],
            "enableLogging": false
        ]
    ))

    #expect(result.audio == Data("eleven-audio".utf8))
    #expect(result.contentType == "audio/mpeg")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.elevenlabs.io/v1/text-to-speech/voice-123?enable_logging=false&output_format=mp3_44100_192")
    #expect(request.headers["xi-api-key"] == "eleven-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["text"]?.stringValue == "Hello")
    #expect(body["model_id"]?.stringValue == "eleven_multilingual_v2")
    #expect(body["language_code"]?.stringValue == "en")
    #expect(body["voice_settings"]?["similarity_boost"]?.doubleValue == 0.7)
    #expect(body["voice_settings"]?["use_speaker_boost"]?.boolValue == true)
}

@Test func elevenLabsSpeechMapsNestedExtraBodyOptionsAndMergesVoiceSettings() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("eleven-audio".utf8)))
    let provider = try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: "eleven-key", transport: transport))
    let model = try provider.speechModel("eleven_multilingual_v2")

    _ = try await model.speak(SpeechRequest(
        text: "Hello",
        voice: "voice-123",
        format: "mp3_128",
        extraBody: [
            "elevenlabs": .object([
                "languageCode": "ja",
                "speed": 0.85,
                "voiceSettings": [
                    "stability": 0.4,
                    "similarityBoost": 0.7,
                    "style": 0.2,
                    "useSpeakerBoost": true
                ],
                "pronunciationDictionaryLocators": [
                    ["pronunciationDictionaryId": "dict-1", "versionId": "v2"]
                ],
                "seed": 42,
                "previousText": "Before",
                "nextText": "After",
                "previousRequestIds": ["prev-1"],
                "nextRequestIds": ["next-1"],
                "applyTextNormalization": "auto",
                "applyLanguageTextNormalization": true,
                "enableLogging": false
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.elevenlabs.io/v1/text-to-speech/voice-123?enable_logging=false&output_format=mp3_44100_128")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["language_code"]?.stringValue == "ja")
    #expect(body["voice_settings"]?["speed"]?.doubleValue == 0.85)
    #expect(body["voice_settings"]?["stability"]?.doubleValue == 0.4)
    #expect(body["voice_settings"]?["similarity_boost"]?.doubleValue == 0.7)
    #expect(body["voice_settings"]?["style"]?.doubleValue == 0.2)
    #expect(body["voice_settings"]?["use_speaker_boost"]?.boolValue == true)
    #expect(body["pronunciation_dictionary_locators"]?[0]?["pronunciation_dictionary_id"]?.stringValue == "dict-1")
    #expect(body["pronunciation_dictionary_locators"]?[0]?["version_id"]?.stringValue == "v2")
    #expect(body["seed"]?.intValue == 42)
    #expect(body["previous_text"]?.stringValue == "Before")
    #expect(body["next_text"]?.stringValue == "After")
    #expect(body["previous_request_ids"]?[0]?.stringValue == "prev-1")
    #expect(body["next_request_ids"]?[0]?.stringValue == "next-1")
    #expect(body["apply_text_normalization"]?.stringValue == "auto")
    #expect(body["apply_language_text_normalization"]?.boolValue == true)
    #expect(body["elevenlabs"] == nil)
}

@Test func elevenLabsSpeechMapsProviderOptionsNamespaceAndOverridesExtraBody() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("eleven-audio".utf8)))
    let provider = try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: "eleven-key", transport: transport))
    let model = try provider.speechModel("eleven_multilingual_v2")

    _ = try await model.speak(SpeechRequest(
        text: "Hello",
        voice: "voice-123",
        format: "mp3",
        providerOptions: [
            "elevenlabs": .object([
                "languageCode": "ja",
                "voiceSettings": [
                    "stability": 0.3,
                    "similarityBoost": 0.8,
                    "style": 0.1,
                    "useSpeakerBoost": true
                ],
                "pronunciationDictionaryLocators": [
                    ["pronunciationDictionaryId": "dict-provider", "versionId": "v3"]
                ],
                "seed": 123,
                "previousText": "Provider before",
                "nextText": "Provider after",
                "previousRequestIds": ["prev-provider"],
                "nextRequestIds": ["next-provider"],
                "applyTextNormalization": "on",
                "applyLanguageTextNormalization": false,
                "enableLogging": true
            ])
        ],
        extraBody: [
            "elevenlabs": .object([
                "languageCode": "en",
                "voiceSettings": ["stability": 0.9],
                "seed": 1,
                "enableLogging": false
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.elevenlabs.io/v1/text-to-speech/voice-123?enable_logging=true&output_format=mp3_44100_128")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["language_code"]?.stringValue == "ja")
    #expect(body["voice_settings"]?["stability"]?.doubleValue == 0.3)
    #expect(body["voice_settings"]?["similarity_boost"]?.doubleValue == 0.8)
    #expect(body["voice_settings"]?["style"]?.doubleValue == 0.1)
    #expect(body["voice_settings"]?["use_speaker_boost"]?.boolValue == true)
    #expect(body["pronunciation_dictionary_locators"]?[0]?["pronunciation_dictionary_id"]?.stringValue == "dict-provider")
    #expect(body["pronunciation_dictionary_locators"]?[0]?["version_id"]?.stringValue == "v3")
    #expect(body["seed"]?.intValue == 123)
    #expect(body["previous_text"]?.stringValue == "Provider before")
    #expect(body["next_text"]?.stringValue == "Provider after")
    #expect(body["previous_request_ids"]?[0]?.stringValue == "prev-provider")
    #expect(body["next_request_ids"]?[0]?.stringValue == "next-provider")
    #expect(body["apply_text_normalization"]?.stringValue == "on")
    #expect(body["apply_language_text_normalization"]?.boolValue == false)
    #expect(body["elevenlabs"] == nil)
}

@Test func elevenLabsTranscriptionUsesSpeechToTextMultipartEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"language_code":"en","language_probability":0.99,"text":"eleven transcript","words":[{"text":"eleven","type":"word","start":0,"end":0.4}]}"#))
    let provider = try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: "eleven-key", transport: transport))
    let model = try provider.transcriptionModel("scribe_v1")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("mp3".utf8),
        fileName: "clip.mp3",
        mimeType: "audio/mpeg",
        language: "en",
        extraBody: ["tagAudioEvents": false, "timestampsGranularity": "word", "fileFormat": "other", "diarize": false]
    ))

    #expect(result.text == "eleven transcript")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.elevenlabs.io/v1/speech-to-text")
    #expect(request.headers["xi-api-key"] == "eleven-key")
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=SwiftAISDK-") == true)
    let body = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(body.contains("name=\"model_id\""))
    #expect(body.contains("scribe_v1"))
    #expect(body.contains("name=\"file\"; filename=\"clip.mp3\""))
    #expect(body.contains("name=\"diarize\""))
    #expect(body.contains("false"))
    #expect(body.contains("name=\"language_code\""))
    #expect(body.contains("en"))
    #expect(body.contains("name=\"tag_audio_events\""))
    #expect(body.contains("name=\"timestamps_granularity\""))
    #expect(body.contains("word"))
}

@Test func elevenLabsTranscriptionMapsNestedExtraBodyOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"language_code":"ja","language_probability":0.99,"text":"nested transcript"}"#))
    let provider = try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: "eleven-key", transport: transport))
    let model = try provider.transcriptionModel("scribe_v1")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("mp3".utf8),
        fileName: "clip.mp3",
        mimeType: "audio/mpeg",
        extraBody: [
            "elevenlabs": .object([
                "languageCode": "ja",
                "tagAudioEvents": true,
                "numSpeakers": 2,
                "timestampsGranularity": "character",
                "fileFormat": "mp3",
                "diarize": false
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(body.contains("name=\"language_code\""))
    #expect(body.contains("ja"))
    #expect(body.contains("name=\"tag_audio_events\""))
    #expect(body.contains("true"))
    #expect(body.contains("name=\"num_speakers\""))
    #expect(body.contains("2"))
    #expect(body.contains("name=\"timestamps_granularity\""))
    #expect(body.contains("character"))
    #expect(body.contains("name=\"file_format\""))
    #expect(body.contains("mp3"))
    #expect(body.contains("name=\"diarize\""))
    #expect(body.contains("false"))
    #expect(!body.contains("elevenlabs"))
}

@Test func elevenLabsTranscriptionMapsProviderOptionsNamespaceAndOverridesExtraBody() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"language_code":"ja","language_probability":0.99,"text":"provider transcript"}"#))
    let provider = try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: "eleven-key", transport: transport))
    let model = try provider.transcriptionModel("scribe_v1")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("mp3".utf8),
        fileName: "clip.mp3",
        mimeType: "audio/mpeg",
        providerOptions: [
            "elevenlabs": .object([
                "languageCode": "ja",
                "tagAudioEvents": false,
                "numSpeakers": 2,
                "timestampsGranularity": "character",
                "fileFormat": "pcm_s16le_16",
                "diarize": true
            ])
        ],
        extraBody: [
            "elevenlabs": .object([
                "languageCode": "en",
                "tagAudioEvents": true,
                "numSpeakers": 4,
                "timestampsGranularity": "word",
                "fileFormat": "mp3",
                "diarize": false
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(body.contains("name=\"language_code\""))
    #expect(body.contains("ja"))
    #expect(body.contains("name=\"tag_audio_events\""))
    #expect(body.contains("false"))
    #expect(body.contains("name=\"num_speakers\""))
    #expect(body.contains("2"))
    #expect(body.contains("name=\"timestamps_granularity\""))
    #expect(body.contains("character"))
    #expect(body.contains("name=\"file_format\""))
    #expect(body.contains("pcm_s16le_16"))
    #expect(body.contains("name=\"diarize\""))
    #expect(body.contains("true"))
    #expect(!body.contains("elevenlabs"))
}
