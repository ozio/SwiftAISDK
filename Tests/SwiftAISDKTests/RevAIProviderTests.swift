import Foundation
import Testing
@testable import SwiftAISDK

@Test func revAITranscriptionSubmitsMultipartJobAndFetchesTranscript() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"job-123","status":"transcribed","language":"en"}"#),
        jsonResponse(#"{"monologues":[{"elements":[{"type":"text","value":"hello","ts":0,"end_ts":0.4},{"type":"punct","value":" "},{"type":"text","value":"rev","ts":0.5,"end_ts":0.9}]}]}"#)
    ])
    let provider = try AIProviders.revAI(settings: ProviderSettings(apiKey: "rev-key", transport: transport))
    let model = try provider.transcriptionModel("machine")

    let result = try await model.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), fileName: "clip.wav", mimeType: "audio/wav", language: "en"))

    #expect(result.text == "hello rev")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].url.absoluteString == "https://api.rev.ai/speechtotext/v1/jobs")
    #expect(requests[0].headers["authorization"] == "Bearer rev-key")
    #expect(requests[0].headers["user-agent"] == "ai-sdk/revai/2.0.33")
    #expect(requests[0].headers["content-type"]?.hasPrefix("multipart/form-data; boundary=SwiftAISDK-") == true)
    let form = String(data: try #require(requests[0].body), encoding: .utf8) ?? ""
    #expect(form.contains("name=\"media\"; filename=\"audio.wav\""))
    #expect(form.contains("name=\"config\""))
    #expect(form.contains("\"transcriber\":\"machine\""))
    #expect(form.contains("\"language\":\"en\""))

    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api.rev.ai/speechtotext/v1/jobs/job-123/transcript")
}

@Test func revAITranscriptionAppendsVersionedUserAgentToCustomHeader() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"job-123","status":"transcribed","language":"en"}"#),
        jsonResponse(#"{"monologues":[{"elements":[{"type":"text","value":"custom","ts":0,"end_ts":0.5}]}]}"#)
    ])
    let provider = try AIProviders.revAI(settings: ProviderSettings(
        apiKey: "rev-key",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: transport
    ))
    let model = try provider.transcription("machine")

    _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), mimeType: "audio/wav"))

    let requests = await transport.requests()
    #expect(requests[0].headers["authorization"] == "Bearer rev-key")
    #expect(requests[0].headers["user-agent"] == "CustomApp/1.0 ai-sdk/revai/2.0.33")
    #expect(requests[1].headers["user-agent"] == "CustomApp/1.0 ai-sdk/revai/2.0.33")
}

@Test func revAITranscriptionMapsNestedExtraBodyOptions() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"job-123","status":"transcribed","language":"ja"}"#),
        jsonResponse(#"{"monologues":[{"elements":[{"type":"text","value":"nested","ts":0,"end_ts":0.5}]}]}"#)
    ])
    let provider = try AIProviders.revAI(settings: ProviderSettings(apiKey: "rev-key", transport: transport))
    let model = try provider.transcriptionModel("machine")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        fileName: "clip.wav",
        mimeType: "audio/wav",
        extraBody: [
            "revai": .object([
                "metadata": "case-1",
                "language": "ja",
                "verbatim": true,
                "skip_diarization": true,
                "speaker_channels_count": 2,
                "summarization_config": ["model": "standard", "type": "bullets"],
                "translation_config": ["target_languages": [["language": "en"]], "model": "standard"],
                "forced_alignment": true
            ])
        ]
    ))

    let form = String(data: try #require((await transport.requests()).first?.body), encoding: .utf8) ?? ""
    #expect(form.contains("\"transcriber\":\"machine\""))
    #expect(form.contains("\"metadata\":\"case-1\""))
    #expect(form.contains("\"language\":\"ja\""))
    #expect(form.contains("\"verbatim\":true"))
    #expect(form.contains("\"skip_diarization\":true"))
    #expect(form.contains("\"speaker_channels_count\":2"))
    #expect(form.contains("\"summarization_config\""))
    #expect(form.contains("\"translation_config\""))
    #expect(form.contains("\"forced_alignment\":true"))
    #expect(!form.contains("\"revai\""))
}

@Test func revAITranscriptionMapsProviderOptionsNamespaceAndOverridesExtraBody() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"job-123","status":"transcribed","language":"ja"}"#),
        jsonResponse(#"{"monologues":[{"elements":[{"type":"text","value":"provider","ts":0,"end_ts":0.5}]}]}"#)
    ])
    let provider = try AIProviders.revAI(settings: ProviderSettings(apiKey: "rev-key", transport: transport))
    let model = try provider.transcriptionModel("machine")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        fileName: "clip.wav",
        mimeType: "audio/wav",
        providerOptions: [
            "revai": .object([
                "metadata": "provider-case",
                "notification_config": [
                    "url": "https://example.com/rev",
                    "auth_headers": ["Authorization": "Bearer hook"]
                ],
                "delete_after_seconds": 60,
                "verbatim": true,
                "rush": true,
                "test_mode": true,
                "segments_to_transcribe": [["start": 0, "end": 3.5]],
                "speaker_names": [["display_name": "Oz"]],
                "skip_diarization": true,
                "skip_postprocessing": true,
                "skip_punctuation": true,
                "remove_disfluencies": true,
                "remove_atmospherics": true,
                "filter_profanity": true,
                "speaker_channels_count": 2,
                "speakers_count": 3,
                "diarization_type": "premium",
                "custom_vocabulary_id": "vocab-1",
                "custom_vocabularies": [["phrases": ["ProviderPhrase"]]],
                "strict_custom_vocabulary": true,
                "summarization_config": ["model": "premium", "type": "bullets", "prompt": "short"],
                "translation_config": ["target_languages": [["language": "en"]], "model": "premium"],
                "language": "ja",
                "forced_alignment": true,
                "unsupportedProperty": "drop-me"
            ]),
            "openai": .object(["timestampGranularities": ["word"]])
        ],
        extraBody: [
            "revai": .object([
                "metadata": "extra-case",
                "language": "en",
                "rush": false
            ])
        ]
    ))

    let form = String(data: try #require((await transport.requests()).first?.body), encoding: .utf8) ?? ""
    #expect(form.contains("\"transcriber\":\"machine\""))
    #expect(form.contains("\"metadata\":\"provider-case\""))
    #expect(form.contains("\"language\":\"ja\""))
    #expect(form.contains("\"notification_config\""))
    #expect(form.contains("\"delete_after_seconds\":60"))
    #expect(form.contains("\"verbatim\":true"))
    #expect(form.contains("\"rush\":true"))
    #expect(form.contains("\"test_mode\":true"))
    #expect(form.contains("\"segments_to_transcribe\""))
    #expect(form.contains("\"speaker_names\""))
    #expect(form.contains("\"skip_diarization\":true"))
    #expect(form.contains("\"skip_postprocessing\":true"))
    #expect(form.contains("\"skip_punctuation\":true"))
    #expect(form.contains("\"remove_disfluencies\":true"))
    #expect(form.contains("\"remove_atmospherics\":true"))
    #expect(form.contains("\"filter_profanity\":true"))
    #expect(form.contains("\"speaker_channels_count\":2"))
    #expect(form.contains("\"speakers_count\":3"))
    #expect(form.contains("\"diarization_type\":\"premium\""))
    #expect(form.contains("\"custom_vocabulary_id\":\"vocab-1\""))
    #expect(form.contains("\"custom_vocabularies\""))
    #expect(!form.contains("ProviderPhrase"))
    #expect(form.contains("\"strict_custom_vocabulary\":true"))
    #expect(form.contains("\"summarization_config\""))
    #expect(form.contains("\"translation_config\""))
    #expect(form.contains("\"forced_alignment\":true"))
    #expect(!form.contains("\"revai\""))
    #expect(!form.contains("\"openai\""))
    #expect(!form.contains("\"unsupportedProperty\""))
    #expect(!form.contains("drop-me"))
    #expect(!form.contains("extra-case"))
    #expect(!form.contains("\"rush\":false"))
}

@Test func revAITranscriptionTreatsNullProviderOptionsNamespaceAsNoop() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"job-123","status":"transcribed","language":"ja"}"#),
        jsonResponse(#"{"monologues":[{"elements":[{"type":"text","value":"null namespace","ts":0,"end_ts":0.5}]}]}"#)
    ])
    let provider = try AIProviders.revAI(settings: ProviderSettings(apiKey: "rev-key", transport: transport))
    let model = try provider.transcriptionModel("machine")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        fileName: "clip.wav",
        mimeType: "audio/wav",
        providerOptions: ["revai": .null],
        extraBody: [
            "revai": .object([
                "metadata": "extra-case",
                "language": "ja",
                "rush": true
            ])
        ]
    ))

    let form = String(data: try #require((await transport.requests()).first?.body), encoding: .utf8) ?? ""
    #expect(form.contains("\"metadata\":\"extra-case\""))
    #expect(form.contains("\"language\":\"ja\""))
    #expect(form.contains("\"rush\":true"))
    #expect(!form.contains("\"test_mode\":false"))
    #expect(!form.contains("\"forced_alignment\":false"))
}

@Test func revAITranscriptionAppliesUpstreamProviderOptionDefaults() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"job-123","status":"transcribed","language":"en"}"#),
        jsonResponse(#"{"monologues":[{"elements":[{"type":"text","value":"defaults","ts":0,"end_ts":0.5}]}]}"#),
        jsonResponse(#"{"id":"job-456","status":"transcribed","language":"en"}"#),
        jsonResponse(#"{"monologues":[{"elements":[{"type":"text","value":"nested","ts":0,"end_ts":0.5}]}]}"#)
    ])
    let provider = try AIProviders.revAI(settings: ProviderSettings(apiKey: "rev-key", transport: transport))
    let model = try provider.transcriptionModel("fusion")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        fileName: "caller-name.mp3",
        mimeType: "audio/mpeg",
        providerOptions: ["revai": .object([:])],
        extraBody: [
            "revai": .object([
                "language": "ja",
                "rush": true,
                "forced_alignment": true
            ])
        ]
    ))

    var form = String(data: try #require((await transport.requests()).first?.body), encoding: .utf8) ?? ""
    #expect(form.contains("name=\"media\"; filename=\"audio.mp3\""))
    #expect(form.contains("\"transcriber\":\"fusion\""))
    #expect(form.contains("\"rush\":false"))
    #expect(form.contains("\"test_mode\":false"))
    #expect(form.contains("\"skip_diarization\":false"))
    #expect(form.contains("\"skip_postprocessing\":false"))
    #expect(form.contains("\"skip_punctuation\":false"))
    #expect(form.contains("\"remove_disfluencies\":false"))
    #expect(form.contains("\"remove_atmospherics\":false"))
    #expect(form.contains("\"filter_profanity\":false"))
    #expect(form.contains("\"diarization_type\":\"standard\""))
    #expect(form.contains("\"language\":\"en\""))
    #expect(form.contains("\"forced_alignment\":false"))
    #expect(!form.contains("\"language\":\"ja\""))
    #expect(!form.contains("\"rush\":true"))

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        mimeType: "audio/wav",
        providerOptions: [
            "revai": .object([
                "rush": .null,
                "summarization_config": [
                    "prompt": "short"
                ],
                "translation_config": [
                    "target_languages": [["language": "de"]]
                ]
            ])
        ]
    ))

    form = String(data: try #require((await transport.requests())[2].body), encoding: .utf8) ?? ""
    #expect(!form.contains("\"rush\""))
    #expect(form.contains("\"summarization_config\""))
    #expect(form.contains("\"model\":\"standard\""))
    #expect(form.contains("\"type\":\"paragraph\""))
    #expect(form.contains("\"prompt\":\"short\""))
    #expect(form.contains("\"translation_config\""))
    #expect(form.contains("\"target_languages\""))
    #expect(form.contains("\"language\":\"de\""))
}

@Test func revAITranscriptionKeepsSubmissionLanguageAndZeroDurationLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"job-123","status":"in_progress","language":"en"}"#),
        jsonResponse(#"{"id":"job-123","status":"transcribed"}"#),
        jsonResponse(#"{"monologues":[{"elements":[{"type":"punct","value":"."}]}]}"#)
    ])
    let provider = try AIProviders.revAI(settings: ProviderSettings(apiKey: "rev-key", transport: transport))
    let model = try provider.transcriptionModel("machine")

    let result = try await model.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), mimeType: "audio/wav"))

    #expect(result.text == ".")
    #expect(result.segments.isEmpty)
    #expect(result.language == "en")
    #expect(result.durationInSeconds == 0)
    let requests = await transport.requests()
    #expect(requests.map(\.url.path) == [
        "/speechtotext/v1/jobs",
        "/speechtotext/v1/jobs/job-123",
        "/speechtotext/v1/jobs/job-123/transcript"
    ])
}

@Test func revAITranscriptionProviderOptionsRejectInvalidSchemaFields() async throws {
    let provider = try AIProviders.revAI(settings: ProviderSettings(apiKey: "rev-key", transport: RecordingTransport(response: jsonResponse(#"{}"#))))
    let model = try provider.transcriptionModel("machine")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.revai", message: "Rev.ai provider options must be an object.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .string("invalid")]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .object(["metadata": .number(1)])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .object(["notification_config": .object(["auth_headers": .object(["Authorization": .string("Bearer hook")])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .object(["notification_config": .object(["url": .string("https://example.com"), "auth_headers": .object(["Authorization": .number(1)])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .object(["delete_after_seconds": .string("60")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .object(["verbatim": .null])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .object(["rush": .string("true")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .object(["segments_to_transcribe": .array([.object(["start": .number(0)])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .object(["speaker_names": .array([.object(["display_name": .number(1)])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .object(["diarization_type": .string("basic")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .object(["custom_vocabularies": .null])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .object(["custom_vocabularies": .array([.string("invalid")])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .object(["strict_custom_vocabulary": .null])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .object(["summarization_config": .object(["model": .string("fast")])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .object(["summarization_config": .object(["prompt": .number(1)])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .object(["translation_config": .object(["model": .string("standard")])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .object(["translation_config": .object(["target_languages": .array([.object(["language": .string("xx")])])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .object(["language": .number(1)])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["revai": .object(["forced_alignment": .string("true")])]
        ))
    }
}

@Test func revAITranscriptionRejectsInvalidJobResponseShapeLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"job-123","status":1}"#))
    let provider = try AIProviders.revAI(settings: ProviderSettings(apiKey: "rev-key", transport: transport))
    let model = try provider.transcriptionModel("machine")

    await #expect(throws: AIError.invalidResponse(provider: "revai.transcription", message: "Rev.ai job response is invalid.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            fileName: "clip.wav",
            mimeType: "audio/wav"
        ))
    }
}

@Test func revAITranscriptionRejectsInvalidTranscriptResponseShapeLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"job-123","status":"transcribed","language":"en"}"#),
        jsonResponse(#"{"monologues":[{"elements":[{"type":"text","value":1,"ts":0,"end_ts":1}]}]}"#)
    ])
    let provider = try AIProviders.revAI(settings: ProviderSettings(apiKey: "rev-key", transport: transport))
    let model = try provider.transcriptionModel("machine")

    await #expect(throws: AIError.invalidResponse(provider: "revai.transcription", message: "Rev.ai transcription response is invalid.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            fileName: "clip.wav",
            mimeType: "audio/wav"
        ))
    }
}

@Test func revAITranscriptionThrowsForFailedSubmissionBeforeMissingID() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"status":"failed"}"#))
    let provider = try AIProviders.revAI(settings: ProviderSettings(apiKey: "rev-key", transport: transport))
    let model = try provider.transcriptionModel("machine")

    await #expect(throws: AIError.invalidResponse(provider: "revai.transcription", message: "Rev.ai transcription job submission failed.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            fileName: "clip.wav",
            mimeType: "audio/wav"
        ))
    }
}
