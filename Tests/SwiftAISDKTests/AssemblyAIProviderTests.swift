import Foundation
import Testing
@testable import SwiftAISDK

@Test func assemblyAITranscriptionUploadsSubmitsAndPolls() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"job-123","status":"queued"}"#),
        jsonResponse(#"{"id":"job-123","status":"completed","text":"assembled text","language_code":"en"}"#)
    ])
    let provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: transport))
    let model = try provider.transcriptionModel("best")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        mimeType: "audio/wav",
        language: "en",
        extraBody: [
            "autoChapters": .bool(true),
            "contentSafetyConfidence": .number(75),
            "entityDetection": .bool(true),
            "filterProfanity": .bool(true),
            "languageDetection": .bool(true),
            "redactPiiPolicies": .array([.string("person_name")]),
            "speakerLabels": .bool(true),
            "speakersExpected": .number(2),
            "webhookUrl": .string("https://example.com/assembly"),
            "wordBoost": .array([.string("Codex")])
        ]
    ))

    #expect(result.text == "assembled text")
    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].url.absoluteString == "https://api.assemblyai.com/v2/upload")
    #expect(requests[0].method == "POST")
    #expect(requests[0].headers["authorization"] == "assembly-key")
    #expect(requests[0].headers["content-type"] == "application/octet-stream")
    #expect(requests[0].body == Data("audio".utf8))

    #expect(requests[1].url.absoluteString == "https://api.assemblyai.com/v2/transcript")
    let submitBody = try decodeJSONBody(try #require(requests[1].body))
    #expect(submitBody["speech_model"]?.stringValue == "best")
    #expect(submitBody["audio_url"]?.stringValue == "https://cdn.example.com/audio.wav")
    #expect(submitBody["language_code"]?.stringValue == "en")
    #expect(submitBody["auto_chapters"]?.boolValue == true)
    #expect(submitBody["content_safety_confidence"]?.intValue == 75)
    #expect(submitBody["entity_detection"]?.boolValue == true)
    #expect(submitBody["filter_profanity"]?.boolValue == true)
    #expect(submitBody["language_detection"]?.boolValue == true)
    #expect(submitBody["redact_pii_policies"]?[0]?.stringValue == "person_name")
    #expect(submitBody["speaker_labels"]?.boolValue == true)
    #expect(submitBody["speakers_expected"]?.intValue == 2)
    #expect(submitBody["webhook_url"]?.stringValue == "https://example.com/assembly")
    #expect(submitBody["word_boost"]?[0]?.stringValue == "Codex")
    #expect(submitBody["autoChapters"] == nil)
    #expect(submitBody["speakerLabels"] == nil)

    #expect(requests[2].method == "GET")
    #expect(requests[2].url.absoluteString == "https://api.assemblyai.com/v2/transcript/job-123")
}

@Test func assemblyAITranscriptionMapsNestedExtraBodyOptions() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"job-123","status":"queued"}"#),
        jsonResponse(#"{"id":"job-123","status":"completed","text":"assembled nested"}"#)
    ])
    let provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: transport))
    let model = try provider.transcriptionModel("nano")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        extraBody: [
            "assemblyai": .object([
                "disfluencies": true,
                "multichannel": true,
                "punctuate": false,
                "summarization": true,
                "summaryModel": "informative",
                "summaryType": "bullets",
                "speechThreshold": 0.6
            ])
        ]
    ))

    let requests = await transport.requests()
    let submitBody = try decodeJSONBody(try #require(requests[1].body))
    #expect(submitBody["speech_model"]?.stringValue == "nano")
    #expect(submitBody["disfluencies"]?.boolValue == true)
    #expect(submitBody["multichannel"]?.boolValue == true)
    #expect(submitBody["punctuate"]?.boolValue == false)
    #expect(submitBody["summarization"]?.boolValue == true)
    #expect(submitBody["summary_model"]?.stringValue == "informative")
    #expect(submitBody["summary_type"]?.stringValue == "bullets")
    #expect(submitBody["speech_threshold"]?.doubleValue == 0.6)
    #expect(submitBody["assemblyai"] == nil)
    #expect(submitBody["summaryModel"] == nil)
}

@Test func assemblyAITranscriptionTreatsNullProviderOptionsNamespaceAsNoop() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"job-123","status":"queued"}"#),
        jsonResponse(#"{"id":"job-123","status":"completed","text":"null namespace"}"#)
    ])
    let provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: transport))
    let model = try provider.transcriptionModel("best")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        providerOptions: ["assemblyai": .null],
        extraBody: [
            "assemblyai": .object([
                "languageCode": "it",
                "autoHighlights": true,
                "wordBoost": ["SwiftAISDK"]
            ])
        ]
    ))

    let submitBody = try decodeJSONBody(try #require((await transport.requests())[1].body))
    #expect(submitBody["language_code"]?.stringValue == "it")
    #expect(submitBody["auto_highlights"]?.boolValue == true)
    #expect(submitBody["word_boost"]?[0]?.stringValue == "SwiftAISDK")
}

@Test func assemblyAITranscriptionMapsProviderOptionsNamespaceAndOverridesExtraBody() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"job-123","status":"queued"}"#),
        jsonResponse(#"{"id":"job-123","status":"completed","text":"assembled provider"}"#)
    ])
    let provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: transport))
    let model = try provider.transcriptionModel("best")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        providerOptions: [
            "assemblyai": .object([
                "audioEndAt": 10_000,
                "audioStartFrom": 250,
                "autoHighlights": true,
                "boostParam": "high",
                "contentSafety": true,
                "customSpelling": [
                    ["from": ["swift", "sdk"], "to": "Swift SDK"]
                ],
                "formatText": false,
                "languageCode": "es",
                "languageConfidenceThreshold": 0.7,
                "redactPii": true,
                "redactPiiAudio": true,
                "redactPiiAudioQuality": "mp3",
                "redactPiiSub": "hash",
                "sentimentAnalysis": true,
                "webhookAuthHeaderName": "X-Assembly-Secret",
                "webhookAuthHeaderValue": "secret",
                "wordBoost": ["SwiftAISDK"],
                "unsupportedProperty": "drop-me"
            ]),
            "openai": .object(["timestampGranularities": ["word"]])
        ],
        extraBody: [
            "assemblyai": .object([
                "languageCode": "en",
                "autoHighlights": false,
                "wordBoost": ["ignored"]
            ])
        ]
    ))

    let requests = await transport.requests()
    let submitBody = try decodeJSONBody(try #require(requests[1].body))
    #expect(submitBody["speech_model"]?.stringValue == "best")
    #expect(submitBody["audio_end_at"]?.intValue == 10_000)
    #expect(submitBody["audio_start_from"]?.intValue == 250)
    #expect(submitBody["auto_highlights"]?.boolValue == true)
    #expect(submitBody["boost_param"]?.stringValue == "high")
    #expect(submitBody["content_safety"]?.boolValue == true)
    #expect(submitBody["custom_spelling"]?[0]?["from"]?[0]?.stringValue == "swift")
    #expect(submitBody["custom_spelling"]?[0]?["to"]?.stringValue == "Swift SDK")
    #expect(submitBody["format_text"]?.boolValue == false)
    #expect(submitBody["language_code"]?.stringValue == "es")
    #expect(submitBody["language_confidence_threshold"]?.doubleValue == 0.7)
    #expect(submitBody["redact_pii"]?.boolValue == true)
    #expect(submitBody["redact_pii_audio"]?.boolValue == true)
    #expect(submitBody["redact_pii_audio_quality"]?.stringValue == "mp3")
    #expect(submitBody["redact_pii_sub"]?.stringValue == "hash")
    #expect(submitBody["sentiment_analysis"]?.boolValue == true)
    #expect(submitBody["webhook_auth_header_name"]?.stringValue == "X-Assembly-Secret")
    #expect(submitBody["webhook_auth_header_value"]?.stringValue == "secret")
    #expect(submitBody["word_boost"]?[0]?.stringValue == "SwiftAISDK")
    #expect(submitBody["assemblyai"] == nil)
    #expect(submitBody["openai"] == nil)
    #expect(submitBody["unsupportedProperty"] == nil)
    #expect(submitBody["audioEndAt"] == nil)
    #expect(submitBody["languageCode"] == nil)
}

@Test func assemblyAITranscriptionScopesProviderOptionsLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"job-123","status":"queued"}"#),
        jsonResponse(#"{"id":"job-123","status":"completed","text":"scoped"}"#)
    ])
    let provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: transport))
    let model = try provider.transcriptionModel("best")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        providerOptions: [
            "assemblyai": .object([
                "languageCode": .null,
                "autoHighlights": .null,
                "wordBoost": .null,
                "customSpelling": [
                    [
                        "from": ["swift", "sdk"],
                        "to": "Swift SDK",
                        "unsupported": "drop-me"
                    ],
                    [
                        "from": ["codex"],
                        "to": "Codex",
                        "unsupported": "drop-me"
                    ]
                ]
            ])
        ],
        extraBody: [
            "assemblyai": .object([
                "languageCode": "ja",
                "autoHighlights": true,
                "wordBoost": ["legacy"]
            ])
        ]
    ))

    let submitBody = try decodeJSONBody(try #require((await transport.requests())[1].body))
    #expect(submitBody["language_code"] == nil)
    #expect(submitBody["auto_highlights"] == nil)
    #expect(submitBody["word_boost"] == nil)
    #expect(submitBody["custom_spelling"]?[0]?["from"]?[0]?.stringValue == "swift")
    #expect(submitBody["custom_spelling"]?[0]?["to"]?.stringValue == "Swift SDK")
    #expect(submitBody["custom_spelling"]?[0]?["unsupported"] == nil)
    #expect(submitBody["custom_spelling"]?[1]?["from"]?[0]?.stringValue == "codex")
    #expect(submitBody["custom_spelling"]?[1]?["to"]?.stringValue == "Codex")
    #expect(submitBody["custom_spelling"]?[1]?["unsupported"] == nil)
}

@Test func assemblyAITranscriptionValidatesProviderOptionsNamespaceObject() async throws {
    let provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: RecordingTransport(responses: [])))
    let model = try provider.transcriptionModel("best")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.assemblyai", message: "AssemblyAI provider options must be an object.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["assemblyai": "not-an-object"]
        ))
    }
}

@Test func assemblyAITranscriptionValidatesProviderOptionsSchema() async throws {
    let provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: RecordingTransport(responses: [])))
    let model = try provider.transcriptionModel("best")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.assemblyai.autoChapters", message: "AssemblyAI autoChapters must be a boolean.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["assemblyai": .object(["autoChapters": "true"])]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.assemblyai.audioEndAt", message: "AssemblyAI audioEndAt must be an integer.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["assemblyai": .object(["audioEndAt": 12.5])]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.assemblyai.contentSafetyConfidence", message: "AssemblyAI contentSafetyConfidence must be an integer between 25 and 100.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["assemblyai": .object(["contentSafetyConfidence": 101])]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.assemblyai.speechThreshold", message: "AssemblyAI speechThreshold must be a number between 0 and 1.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["assemblyai": .object(["speechThreshold": 1.2])]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.assemblyai.wordBoost", message: "AssemblyAI providerOptions.assemblyai.wordBoost values must be strings.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["assemblyai": .object(["wordBoost": ["SwiftAISDK", 42]])]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.assemblyai.customSpelling[0].to", message: "AssemblyAI customSpelling to must be a string.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: [
                "assemblyai": .object([
                    "customSpelling": [
                        ["from": ["swift"], "to": .null]
                    ]
                ])
            ]
        ))
    }
}

@Test func assemblyAITranscriptionErrorMessageMatchesUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"job-123","status":"queued"}"#),
        jsonResponse(#"{"id":"job-123","status":"error","error":"bad audio"}"#)
    ])
    let provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: transport))
    let model = try provider.transcriptionModel("best")

    await #expect(throws: AIError.invalidResponse(provider: "assemblyai.transcription", message: "Transcription failed: bad audio")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8)))
    }
}

@Test func assemblyAITranscriptionRejectsInvalidSubmitStatusLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"job-123","status":"paused"}"#)
    ])
    let provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: transport))
    let model = try provider.transcriptionModel("best")

    await #expect(throws: AIError.invalidResponse(provider: "assemblyai.transcription", message: "AssemblyAI submit response status is invalid.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8)))
    }
}

@Test func assemblyAITranscriptionRejectsInvalidPollingStatusLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"job-123","status":"queued"}"#),
        jsonResponse(#"{"id":"job-123","status":"paused"}"#)
    ])
    let provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: transport))
    let model = try provider.transcriptionModel("best")

    await #expect(throws: AIError.invalidResponse(provider: "assemblyai.transcription", message: "AssemblyAI transcription status is invalid.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8)))
    }
}

@Test func assemblyAITranscriptionRejectsInvalidFinalResultLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"job-123","status":"queued"}"#),
        jsonResponse(#"{"id":"job-123","status":"completed","words":[{"text":"missing timing","start":0}]}"#)
    ])
    let provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: transport))
    let model = try provider.transcriptionModel("best")

    await #expect(throws: AIError.invalidResponse(provider: "assemblyai.transcription", message: "AssemblyAI transcription result is invalid.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8)))
    }
}
