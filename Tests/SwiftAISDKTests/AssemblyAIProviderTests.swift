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
    #expect(requests[0].headers["user-agent"] == "ai-sdk/assemblyai/3.0.5")
    #expect(requests[0].headers["content-type"] == "application/octet-stream")
    #expect(requests[0].body == Data("audio".utf8))

    #expect(requests[1].url.absoluteString == "https://api.assemblyai.com/v2/transcript")
    #expect(requests[1].headers["user-agent"] == "ai-sdk/assemblyai/3.0.5")
    let submitBody = try decodeJSONBody(try #require(requests[1].body))
    #expect(submitBody["speech_model"]?.stringValue == "best")
    #expect(submitBody["speech_models"] == nil)
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
    #expect(requests[2].headers["user-agent"] == "ai-sdk/assemblyai/3.0.5")
    #expect(result.warnings.contains(AIWarning(
        type: "deprecated",
        setting: "model 'best'",
        message: "The 'best' model is a legacy AssemblyAI model. Use 'universal-3-5-pro' instead. See documentation: https://www.assemblyai.com/docs/pre-recorded-audio/select-the-speech-model"
    )))
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
    #expect(submitBody["speech_models"]?[0]?.stringValue == "nano")
    #expect(submitBody["speech_model"] == nil)
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

@Test func assemblyAITranscriptionRoutesCurrentAndLegacyModelIDsLikeUpstream() async throws {
    let legacyTransport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"legacy","status":"queued"}"#),
        jsonResponse(#"{"id":"legacy","status":"completed","text":"legacy"}"#)
    ])
    let legacyProvider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: legacyTransport))
    let legacyResult = try await legacyProvider.transcriptionModel("best").transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8)))
    let legacyBody = try decodeJSONBody(try #require((await legacyTransport.requests())[1].body))
    #expect(legacyBody["speech_model"]?.stringValue == "best")
    #expect(legacyBody["speech_models"] == nil)
    #expect(legacyResult.warnings.contains { warning in
        warning.type == "deprecated" &&
        warning.setting == "model 'best'" &&
        warning.message?.contains("universal-3-5-pro") == true
    })

    let currentTransport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"current","status":"queued"}"#),
        jsonResponse(#"{"id":"current","status":"completed","text":"current"}"#)
    ])
    let currentProvider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: currentTransport))
    let currentResult = try await currentProvider.transcriptionModel("universal-3-5-pro").transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8)))
    let currentBody = try decodeJSONBody(try #require((await currentTransport.requests())[1].body))
    #expect(currentBody["speech_models"]?[0]?.stringValue == "universal-3-5-pro")
    #expect(currentBody["speech_model"] == nil)
    #expect(currentResult.warnings.isEmpty)

    let universal3Transport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"u3","status":"queued"}"#),
        jsonResponse(#"{"id":"u3","status":"completed","text":"u3"}"#)
    ])
    let universal3Provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: universal3Transport))
    let universal3Result = try await universal3Provider.transcriptionModel("universal-3-pro").transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8)))
    #expect(universal3Result.warnings.contains { warning in
        warning.type == "other" &&
        warning.message?.contains("universal-3-5-pro") == true &&
        warning.message?.contains("replace 'universal-3-pro'") == true
    })

    let universal2Transport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"u2","status":"queued"}"#),
        jsonResponse(#"{"id":"u2","status":"completed","text":"u2"}"#)
    ])
    let universal2Provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: universal2Transport))
    let universal2Result = try await universal2Provider.transcriptionModel("universal-2").transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8)))
    #expect(universal2Result.warnings.contains { warning in
        warning.type == "other" &&
        warning.message?.contains("universal-3-5-pro") == true &&
        warning.message?.contains("replace 'universal-3-pro'") == false
    })
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
    #expect(submitBody["speech_models"] == nil)
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

@Test func assemblyAITranscriptionMapsUpstreamV3ProviderOptionsAndWarnings() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"job-123","status":"queued"}"#),
        jsonResponse(#"{"id":"job-123","status":"completed","text":"new options"}"#)
    ])
    let provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: transport))
    let model = try provider.transcriptionModel("universal-3-5-pro")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        providerOptions: [
            "assemblyai": .object([
                "prompt": "This is a conversation about SwiftAISDK.",
                "keytermsPrompt": ["Vercel", "AI SDK"],
                "temperature": 0.2,
                "removeAudioTags": "speaker",
                "domain": "medical-v1",
                "wordBoost": ["legacy"],
                "boostParam": "high",
                "languageCode": "en",
                "languageDetection": true,
                "redactStaticEntities": [
                    "INTERNAL_TOOL": ["Bearclaw"]
                ],
                "redactPiiAudioOptions": [
                    "overrideAudioRedactionMethod": "silence"
                ]
            ])
        ]
    ))

    let submitBody = try decodeJSONBody(try #require((await transport.requests())[1].body))
    #expect(submitBody["speech_models"]?[0]?.stringValue == "universal-3-5-pro")
    #expect(submitBody["prompt"]?.stringValue == "This is a conversation about SwiftAISDK.")
    #expect(submitBody["keyterms_prompt"]?[0]?.stringValue == "Vercel")
    #expect(submitBody["temperature"]?.doubleValue == 0.2)
    #expect(submitBody["remove_audio_tags"]?.stringValue == "speaker")
    #expect(submitBody["domain"]?.stringValue == "medical-v1")
    #expect(submitBody["word_boost"]?[0]?.stringValue == "legacy")
    #expect(submitBody["boost_param"]?.stringValue == "high")
    #expect(submitBody["redact_static_entities"]?["INTERNAL_TOOL"]?[0]?.stringValue == "Bearclaw")
    #expect(submitBody["redact_pii_audio_options"]?["override_audio_redaction_method"]?.stringValue == "silence")
    #expect(result.warnings.contains(AIWarning(
        type: "deprecated",
        setting: "wordBoost, boostParam",
        message: "'wordBoost' and 'boostParam' are deprecated and are rejected by 'universal-3-pro' / 'universal-3-5-pro' and 'slam-1'. Use 'keytermsPrompt' instead."
    )))
    #expect(result.warnings.contains { warning in
        warning.type == "other" && warning.message?.contains("redactPii") == true
    })
    #expect(result.warnings.contains { warning in
        warning.type == "other" && warning.message?.contains("redactPiiAudio") == true
    })
    #expect(result.warnings.contains { warning in
        warning.type == "other" && warning.message?.contains("languageDetection") == true
    })
}

@Test func assemblyAITranscriptionMapsGANestedProviderOptions() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"job-123","status":"queued"}"#),
        jsonResponse(#"{"id":"job-123","status":"completed","text":"nested options"}"#)
    ])
    let provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: transport))
    let model = try provider.transcriptionModel("universal-3-5-pro")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        providerOptions: [
            "assemblyai": .object([
                "redactPii": true,
                "redactPiiAudio": true,
                "speakerOptions": [
                    "minSpeakersExpected": 1,
                    "maxSpeakersExpected": 3
                ],
                "languageDetectionOptions": [
                    "expectedLanguages": ["en", "es"],
                    "fallbackLanguage": "en",
                    "codeSwitching": true,
                    "codeSwitchingConfidenceThreshold": 0.5
                ],
                "redactPiiAudioOptions": [
                    "returnRedactedNoSpeechAudio": true,
                    "overrideAudioRedactionMethod": "silence"
                ],
                "redactPiiReturnUnredacted": true,
                "redactStaticEntities": [
                    "INTERNAL_TOOL": ["Bearclaw"]
                ]
            ])
        ]
    ))

    let submitBody = try decodeJSONBody(try #require((await transport.requests())[1].body))
    #expect(submitBody["speaker_options"]?["min_speakers_expected"]?.intValue == 1)
    #expect(submitBody["speaker_options"]?["max_speakers_expected"]?.intValue == 3)
    #expect(submitBody["language_detection_options"]?["expected_languages"]?[0]?.stringValue == "en")
    #expect(submitBody["language_detection_options"]?["fallback_language"]?.stringValue == "en")
    #expect(submitBody["language_detection_options"]?["code_switching"]?.boolValue == true)
    #expect(submitBody["language_detection_options"]?["code_switching_confidence_threshold"]?.doubleValue == 0.5)
    #expect(submitBody["redact_pii_audio_options"]?["return_redacted_no_speech_audio"]?.boolValue == true)
    #expect(submitBody["redact_pii_audio_options"]?["override_audio_redaction_method"]?.stringValue == "silence")
    #expect(submitBody["redact_pii_return_unredacted"]?.boolValue == true)
    #expect(submitBody["redact_static_entities"]?["INTERNAL_TOOL"]?[0]?.stringValue == "Bearclaw")
}

@Test func assemblyAITranscriptionSurfacesProviderMetadataAndRawBodyLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"job-123","status":"queued"}"#),
        jsonResponse("""
        {
          "id":"job-123",
          "status":"completed",
          "text":"Hello, world!",
          "words":[{"text":"Hello,","start":250,"end":650,"speaker":"speaker"}],
          "utterances":[{"text":"Hello, world!","start":250,"end":26950,"speaker":"A"}],
          "entities":[{"entity_type":"location","text":"Canada","start":2548,"end":3130}],
          "sentiment_analysis_results":[{"text":"Hello, world!","sentiment":"POSITIVE","confidence":0.9}],
          "content_safety_labels":{"status":"success"},
          "iab_categories_result":{"status":"success"},
          "auto_highlights_result":{"status":"success"},
          "chapters":[{"summary":"Hello, world!"}],
          "summary":"- Hello, world!"
        }
        """)
    ])
    let provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: transport))
    let model = try provider.transcriptionModel("universal-3-5-pro")

    let result = try await model.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8)))

    #expect(result.segments.first == TranscriptionSegment(text: "Hello,", startSecond: 0.25, endSecond: 0.65))
    #expect(result.providerMetadata["assemblyai"]?["utterances"]?[0]?["speaker"]?.stringValue == "A")
    #expect(result.providerMetadata["assemblyai"]?["entities"]?[0]?["text"]?.stringValue == "Canada")
    #expect(result.providerMetadata["assemblyai"]?["sentimentAnalysisResults"]?[0]?["sentiment"]?.stringValue == "POSITIVE")
    #expect(result.providerMetadata["assemblyai"]?["contentSafetyLabels"]?["status"]?.stringValue == "success")
    #expect(result.providerMetadata["assemblyai"]?["iabCategoriesResult"]?["status"]?.stringValue == "success")
    #expect(result.providerMetadata["assemblyai"]?["autoHighlightsResult"]?["status"]?.stringValue == "success")
    #expect(result.responseMetadata.body?["words"]?[0]?["speaker"]?.stringValue == "speaker")
    #expect(result.responseMetadata.body?["chapters"]?[0]?["summary"]?.stringValue == "Hello, world!")
    #expect(result.responseMetadata.body?["summary"]?.stringValue == "- Hello, world!")
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

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.assemblyai.temperature", message: "AssemblyAI temperature must be a number between 0 and 1.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["assemblyai": .object(["temperature": 1.2])]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.assemblyai.removeAudioTags", message: "AssemblyAI removeAudioTags must be `all` or `speaker`.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["assemblyai": .object(["removeAudioTags": "none"])]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.assemblyai.languageDetectionOptions.codeSwitchingConfidenceThreshold", message: "AssemblyAI languageDetectionOptions.codeSwitchingConfidenceThreshold must be a number between 0 and 1.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: [
                "assemblyai": .object([
                    "languageDetectionOptions": [
                        "codeSwitchingConfidenceThreshold": -0.1
                    ]
                ])
            ]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.assemblyai.redactStaticEntities.INTERNAL_TOOL", message: "AssemblyAI providerOptions.assemblyai.redactStaticEntities.INTERNAL_TOOL values must be strings.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: [
                "assemblyai": .object([
                    "redactStaticEntities": [
                        "INTERNAL_TOOL": ["Codex", 42]
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

@Test func assemblyAITranscriptionUsesUpstreamHTTPErrorMessageSchema() async throws {
    let uploadProvider = try AIProviders.assemblyAI(settings: ProviderSettings(
        apiKey: "assembly-key",
        transport: RecordingTransport(response: AIHTTPResponse(
            statusCode: 401,
            headers: ["content-type": "application/json", "x-assembly": "upload"],
            body: Data(#"{"error":{"message":"upload unauthorized","code":401}}"#.utf8)
        ))
    ))
    let uploadModel = try uploadProvider.transcriptionModel("best")

    await #expect(throws: AIError.apiCall(
        provider: "assemblyai.transcription",
        statusCode: 401,
        body: "upload unauthorized",
        headers: ["content-type": "application/json", "x-assembly": "upload"]
    )) {
        _ = try await uploadModel.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8)))
    }

    let submitProvider = try AIProviders.assemblyAI(settings: ProviderSettings(
        apiKey: "assembly-key",
        transport: RecordingTransport(responses: [
            jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
            AIHTTPResponse(
                statusCode: 400,
                headers: ["content-type": "application/json", "x-assembly": "submit"],
                body: Data(#"{"error":{"message":"submit failed","code":400}}"#.utf8)
            )
        ])
    ))
    let submitModel = try submitProvider.transcriptionModel("best")

    await #expect(throws: AIError.apiCall(
        provider: "assemblyai.transcription",
        statusCode: 400,
        body: "submit failed",
        headers: ["content-type": "application/json", "x-assembly": "submit"]
    )) {
        _ = try await submitModel.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8)))
    }

    let pollProvider = try AIProviders.assemblyAI(settings: ProviderSettings(
        apiKey: "assembly-key",
        transport: RecordingTransport(responses: [
            jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
            jsonResponse(#"{"id":"job-123","status":"queued"}"#),
            AIHTTPResponse(
                statusCode: 500,
                headers: ["content-type": "application/json", "x-assembly": "poll"],
                body: Data(#"{"error":{"message":"poll failed","code":500}}"#.utf8)
            )
        ])
    ))
    let pollModel = try pollProvider.transcriptionModel("best")

    await #expect(throws: AIError.apiCall(
        provider: "assemblyai.transcription",
        statusCode: 500,
        body: "poll failed",
        headers: ["content-type": "application/json", "x-assembly": "poll"]
    )) {
        _ = try await pollModel.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8)))
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
