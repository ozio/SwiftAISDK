import Foundation
import Testing
@testable import SwiftAISDK

@Test func gladiaTranscriptionUploadsInitiatesAndPollsResultURL() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
        jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-123"}"#),
        jsonResponse(#"{"status":"done","result":{"metadata":{"audio_duration":2.4},"transcription":{"full_transcript":"gladia text","languages":["en"],"utterances":[{"start":0,"end":2.4,"text":"gladia text"}]}}}"#)
    ])
    let provider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "gladia-key", transport: transport))
    let model = try provider.transcriptionModel("default")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        fileName: "clip.wav",
        mimeType: "audio/wav",
        language: "en",
        extraBody: [
            "contextPrompt": .string("Names include Codex."),
            "detectLanguage": .bool(false),
            "enableCodeSwitching": .bool(true),
            "codeSwitchingConfig": .object(["languages": .array([.string("en"), .string("ja")])]),
            "subtitles": .bool(true),
            "subtitlesConfig": .object([
                "formats": .array([.string("srt")]),
                "minimumDuration": .number(1),
                "maximumCharactersPerRow": .number(42)
            ]),
            "diarization": .bool(true),
            "diarizationConfig": .object([
                "numberOfSpeakers": .number(2),
                "enhanced": .bool(true)
            ]),
            "translation": .bool(true),
            "translationConfig": .object([
                "targetLanguages": .array([.string("fr")]),
                "matchOriginalUtterances": .bool(true)
            ]),
            "namedEntityRecognition": .bool(true),
            "customSpellingConfig": .object(["spellingDictionary": .object(["Codex": .array([.string("code ex")])])]),
            "structuredDataExtraction": .bool(true),
            "sentimentAnalysis": .bool(true),
            "audioToLlmConfig": .object(["prompts": .array([.string("summarize")])]),
            "displayMode": .bool(true),
            "punctuationEnhanced": .bool(true)
        ]
    ))

    #expect(result.text == "gladia text")
    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].url.absoluteString == "https://api.gladia.io/v2/upload")
    #expect(requests[0].headers["x-gladia-key"] == "gladia-key")
    #expect(requests[0].headers["content-type"]?.hasPrefix("multipart/form-data; boundary=SwiftAISDK-") == true)
    let uploadBody = String(data: try #require(requests[0].body), encoding: .utf8) ?? ""
    #expect(uploadBody.contains("name=\"audio\"; filename=\"audio.wav\""))

    #expect(requests[1].url.absoluteString == "https://api.gladia.io/v2/pre-recorded")
    let initBody = try decodeJSONBody(try #require(requests[1].body))
    #expect(initBody["audio_url"]?.stringValue == "https://audio.example.com/file.wav")
    #expect(initBody["language"]?.stringValue == "en")
    #expect(initBody["context_prompt"]?.stringValue == "Names include Codex.")
    #expect(initBody["detect_language"]?.boolValue == false)
    #expect(initBody["enable_code_switching"]?.boolValue == true)
    #expect(initBody["code_switching_config"]?["languages"]?[1]?.stringValue == "ja")
    #expect(initBody["subtitles_config"]?["minimum_duration"]?.intValue == 1)
    #expect(initBody["subtitles_config"]?["maximum_characters_per_row"]?.intValue == 42)
    #expect(initBody["diarization_config"]?["number_of_speakers"]?.intValue == 2)
    #expect(initBody["diarization_config"]?["enhanced"]?.boolValue == true)
    #expect(initBody["translation_config"]?["target_languages"]?[0]?.stringValue == "fr")
    #expect(initBody["translation_config"]?["match_original_utterances"]?.boolValue == true)
    #expect(initBody["named_entity_recognition"]?.boolValue == true)
    #expect(initBody["custom_spelling_config"]?["spelling_dictionary"]?["Codex"]?[0]?.stringValue == "code ex")
    #expect(initBody["structured_data_extraction"]?.boolValue == true)
    #expect(initBody["sentiment_analysis"]?.boolValue == true)
    #expect(initBody["audio_to_llm_config"]?["prompts"]?[0]?.stringValue == "summarize")
    #expect(initBody["display_mode"]?.boolValue == true)
    #expect(initBody["punctuation_enhanced"]?.boolValue == true)
    #expect(initBody["contextPrompt"] == nil)
    #expect(initBody["diarizationConfig"] == nil)

    #expect(requests[2].method == "GET")
    #expect(requests[2].url.absoluteString == "https://api.gladia.io/v2/pre-recorded/result/job-123")
}

@Test func gladiaTranscriptionMapsNestedExtraBodyOptions() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
        jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-123"}"#),
        jsonResponse(#"{"status":"done","result":{"metadata":{"audio_duration":1.0},"transcription":{"full_transcript":"gladia nested","languages":["ja"],"utterances":[{"start":0,"end":1.0,"text":"gladia nested"}]}}}"#)
    ])
    let provider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "gladia-key", transport: transport))
    let model = try provider.transcriptionModel("default")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        extraBody: [
            "gladia": .object([
                "language": "ja",
                "callback": true,
                "callbackConfig": ["url": "https://example.com/hook", "method": "POST"],
                "subtitles": true,
                "diarization": true,
                "translation": true,
                "summarization": true,
                "moderation": true,
                "chapterization": true,
                "sentences": true,
                "summarizationConfig": ["type": "concise"]
            ])
        ]
    ))

    let requests = await transport.requests()
    let initBody = try decodeJSONBody(try #require(requests[1].body))
    #expect(initBody["language"]?.stringValue == "ja")
    #expect(initBody["callback"]?.boolValue == true)
    #expect(initBody["callback_config"]?["url"]?.stringValue == "https://example.com/hook")
    #expect(initBody["callback_config"]?["method"]?.stringValue == "POST")
    #expect(initBody["subtitles"]?.boolValue == true)
    #expect(initBody["diarization"]?.boolValue == true)
    #expect(initBody["translation"]?.boolValue == true)
    #expect(initBody["summarization"]?.boolValue == true)
    #expect(initBody["moderation"]?.boolValue == true)
    #expect(initBody["chapterization"]?.boolValue == true)
    #expect(initBody["sentences"]?.boolValue == true)
    #expect(initBody["summarization_config"]?["type"]?.stringValue == "concise")
    #expect(initBody["gladia"] == nil)
    #expect(initBody["callbackConfig"] == nil)
}

@Test func gladiaTranscriptionTreatsNullProviderOptionsNamespaceAsNoop() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
        jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-123"}"#),
        jsonResponse(#"{"status":"done","result":{"metadata":{"audio_duration":1.0},"transcription":{"full_transcript":"null namespace","languages":["fr"],"utterances":[{"start":0,"end":1.0,"text":"null namespace"}]}}}"#)
    ])
    let provider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "gladia-key", transport: transport))
    let model = try provider.transcriptionModel("default")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        providerOptions: ["gladia": .null],
        extraBody: [
            "gladia": .object([
                "contextPrompt": "extra prompt",
                "language": "fr",
                "callback": true
            ])
        ]
    ))

    let initBody = try decodeJSONBody(try #require((await transport.requests())[1].body))
    #expect(initBody["context_prompt"]?.stringValue == "extra prompt")
    #expect(initBody["language"]?.stringValue == "fr")
    #expect(initBody["callback"]?.boolValue == true)
}

@Test func gladiaTranscriptionMapsProviderOptionsNamespaceAndOverridesExtraBody() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://audio.example.com/file.mp3"}"#),
        jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-123"}"#),
        jsonResponse(#"{"status":"done","result":{"metadata":{"audio_duration":1.5},"transcription":{"full_transcript":"provider","languages":["ja"],"utterances":[{"start":0,"end":1.5,"text":"provider"}]}}}"#)
    ])
    let provider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "gladia-key", transport: transport))
    let model = try provider.transcriptionModel("default")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        fileName: "clip.wav",
        mimeType: "audio/mpeg",
        providerOptions: [
            "gladia": .object([
                "contextPrompt": "Provider prompt",
                "customVocabulary": .array([.string("SwiftAISDK"), .string("Gladia")]),
                "customVocabularyConfig": .object([
                    "vocabulary": .array([
                        .string("Codex"),
                        .object([
                            "value": "SwiftAISDK",
                            "intensity": 0.8,
                            "pronunciations": .array([.string("swift ai sdk")]),
                            "language": "en"
                        ])
                    ]),
                    "defaultIntensity": 0.5
                ]),
                "detectLanguage": false,
                "enableCodeSwitching": true,
                "codeSwitchingConfig": ["languages": ["en", "ja"]],
                "language": "ja",
                "callback": true,
                "callbackConfig": ["url": "https://example.com/hook", "method": "PUT"],
                "subtitles": true,
                "subtitlesConfig": [
                    "formats": ["srt", "vtt"],
                    "minimumDuration": 1,
                    "maximumDuration": 3,
                    "maximumCharactersPerRow": 42,
                    "maximumRowsPerCaption": 2,
                    "style": "compliance"
                ],
                "diarization": true,
                "diarizationConfig": [
                    "numberOfSpeakers": 2,
                    "minSpeakers": 1,
                    "maxSpeakers": 3,
                    "enhanced": true
                ],
                "translation": true,
                "translationConfig": [
                    "targetLanguages": ["en"],
                    "model": "enhanced",
                    "matchOriginalUtterances": true
                ],
                "summarization": true,
                "summarizationConfig": ["type": "bullet_points"],
                "moderation": true,
                "namedEntityRecognition": true,
                "chapterization": true,
                "nameConsistency": true,
                "customSpelling": true,
                "customSpellingConfig": ["spellingDictionary": ["Codex": ["code ex"]]],
                "structuredDataExtraction": true,
                "structuredDataExtractionConfig": ["classes": ["person", "product"]],
                "sentimentAnalysis": true,
                "audioToLlm": true,
                "audioToLlmConfig": ["prompts": ["summarize"]],
                "customMetadata": ["case": "provider"],
                "sentences": true,
                "displayMode": true,
                "punctuationEnhanced": true,
                "unsupportedProperty": "drop-me"
            ]),
            "openai": .object(["timestampGranularities": ["word"]])
        ],
        extraBody: [
            "gladia": .object([
                "contextPrompt": "Extra prompt",
                "language": "en",
                "callback": false
            ])
        ]
    ))

    let requests = await transport.requests()
    let uploadBody = String(data: try #require(requests[0].body), encoding: .utf8) ?? ""
    #expect(uploadBody.contains("name=\"audio\"; filename=\"audio.mp3\""))

    let initBody = try decodeJSONBody(try #require(requests[1].body))
    #expect(initBody["audio_url"]?.stringValue == "https://audio.example.com/file.mp3")
    #expect(initBody["context_prompt"]?.stringValue == "Provider prompt")
    #expect(initBody["custom_vocabulary"]?[0]?.stringValue == "SwiftAISDK")
    #expect(initBody["custom_vocabulary_config"]?["vocabulary"]?[0]?.stringValue == "Codex")
    #expect(initBody["custom_vocabulary_config"]?["vocabulary"]?[1]?["value"]?.stringValue == "SwiftAISDK")
    #expect(initBody["custom_vocabulary_config"]?["default_intensity"]?.doubleValue == 0.5)
    #expect(initBody["detect_language"]?.boolValue == false)
    #expect(initBody["enable_code_switching"]?.boolValue == true)
    #expect(initBody["code_switching_config"]?["languages"]?[1]?.stringValue == "ja")
    #expect(initBody["language"]?.stringValue == "ja")
    #expect(initBody["callback"]?.boolValue == true)
    #expect(initBody["callback_config"]?["method"]?.stringValue == "PUT")
    #expect(initBody["subtitles"]?.boolValue == true)
    #expect(initBody["subtitles_config"]?["maximum_duration"]?.intValue == 3)
    #expect(initBody["subtitles_config"]?["maximum_rows_per_caption"]?.intValue == 2)
    #expect(initBody["subtitles_config"]?["style"]?.stringValue == "compliance")
    #expect(initBody["diarization"]?.boolValue == true)
    #expect(initBody["diarization_config"]?["min_speakers"]?.intValue == 1)
    #expect(initBody["diarization_config"]?["max_speakers"]?.intValue == 3)
    #expect(initBody["translation"]?.boolValue == true)
    #expect(initBody["translation_config"]?["model"]?.stringValue == "enhanced")
    #expect(initBody["translation_config"]?["match_original_utterances"]?.boolValue == true)
    #expect(initBody["summarization"]?.boolValue == true)
    #expect(initBody["summarization_config"]?["type"]?.stringValue == "bullet_points")
    #expect(initBody["moderation"]?.boolValue == true)
    #expect(initBody["named_entity_recognition"]?.boolValue == true)
    #expect(initBody["chapterization"]?.boolValue == true)
    #expect(initBody["name_consistency"]?.boolValue == true)
    #expect(initBody["custom_spelling"]?.boolValue == true)
    #expect(initBody["custom_spelling_config"]?["spelling_dictionary"]?["Codex"]?[0]?.stringValue == "code ex")
    #expect(initBody["structured_data_extraction"]?.boolValue == true)
    #expect(initBody["structured_data_extraction_config"]?["classes"]?[1]?.stringValue == "product")
    #expect(initBody["sentiment_analysis"]?.boolValue == true)
    #expect(initBody["audio_to_llm"]?.boolValue == true)
    #expect(initBody["audio_to_llm_config"]?["prompts"]?[0]?.stringValue == "summarize")
    #expect(initBody["custom_metadata"]?["case"]?.stringValue == "provider")
    #expect(initBody["sentences"]?.boolValue == true)
    #expect(initBody["display_mode"]?.boolValue == true)
    #expect(initBody["punctuation_enhanced"]?.boolValue == true)
    #expect(initBody["gladia"] == nil)
    #expect(initBody["openai"] == nil)
    #expect(initBody["unsupportedProperty"] == nil)
    #expect(initBody["contextPrompt"] == nil)
    #expect(initBody["callbackConfig"] == nil)
}

@Test func gladiaTranscriptionScopesProviderOptionsLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
        jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-123"}"#),
        jsonResponse(#"{"status":"done","result":{"metadata":{"audio_duration":0.8},"transcription":{"full_transcript":"scoped","languages":["en"],"utterances":[{"start":0,"end":0.8,"text":"scoped"}]}}}"#)
    ])
    let provider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "gladia-key", transport: transport))
    let model = try provider.transcriptionModel("default")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        mimeType: "audio/wav",
        providerOptions: [
            "gladia": .object([
                "contextPrompt": .null,
                "language": .null,
                "callback": .null,
                "customVocabularyConfig": [
                    "vocabulary": [
                        [
                            "value": "SwiftAISDK",
                            "intensity": .null,
                            "pronunciations": ["swift ai sdk"],
                            "language": "en",
                            "unsupportedTerm": "drop-me"
                        ]
                    ],
                    "defaultIntensity": .null,
                    "unsupportedConfig": "drop-me"
                ],
                "callbackConfig": [
                    "url": "https://example.com/hook",
                    "method": .null,
                    "unsupportedConfig": "drop-me"
                ],
                "subtitlesConfig": [
                    "formats": ["srt"],
                    "maximumRowsPerCaption": .null,
                    "style": "default",
                    "unsupportedConfig": "drop-me"
                ],
                "diarizationConfig": [
                    "numberOfSpeakers": 2,
                    "enhanced": .null,
                    "unsupportedConfig": "drop-me"
                ],
                "translationConfig": [
                    "targetLanguages": ["de"],
                    "model": .null,
                    "matchOriginalUtterances": true,
                    "unsupportedConfig": "drop-me"
                ],
                "summarizationConfig": [
                    "type": .null,
                    "unsupportedConfig": "drop-me"
                ],
                "structuredDataExtractionConfig": [
                    "classes": ["person"],
                    "unsupportedConfig": "drop-me"
                ],
                "audioToLlmConfig": [
                    "prompts": ["summarize"],
                    "unsupportedConfig": "drop-me"
                ]
            ])
        ],
        extraBody: [
            "gladia": .object([
                "contextPrompt": "legacy prompt",
                "language": "ja",
                "callback": true
            ])
        ]
    ))

    let initBody = try decodeJSONBody(try #require((await transport.requests())[1].body))
    #expect(initBody["context_prompt"] == nil)
    #expect(initBody["language"] == nil)
    #expect(initBody["callback"] == nil)
    #expect(initBody["custom_vocabulary_config"]?["vocabulary"]?[0]?["value"]?.stringValue == "SwiftAISDK")
    #expect(initBody["custom_vocabulary_config"]?["vocabulary"]?[0]?["intensity"] == nil)
    #expect(initBody["custom_vocabulary_config"]?["vocabulary"]?[0]?["unsupportedTerm"] == nil)
    #expect(initBody["custom_vocabulary_config"]?["default_intensity"] == nil)
    #expect(initBody["custom_vocabulary_config"]?["unsupportedConfig"] == nil)
    #expect(initBody["callback_config"]?["url"]?.stringValue == "https://example.com/hook")
    #expect(initBody["callback_config"]?["method"] == nil)
    #expect(initBody["callback_config"]?["unsupportedConfig"] == nil)
    #expect(initBody["subtitles_config"]?["formats"]?[0]?.stringValue == "srt")
    #expect(initBody["subtitles_config"]?["maximum_rows_per_caption"] == nil)
    #expect(initBody["subtitles_config"]?["unsupportedConfig"] == nil)
    #expect(initBody["diarization_config"]?["number_of_speakers"]?.intValue == 2)
    #expect(initBody["diarization_config"]?["enhanced"] == nil)
    #expect(initBody["translation_config"]?["target_languages"]?[0]?.stringValue == "de")
    #expect(initBody["translation_config"]?["model"] == nil)
    #expect(initBody["translation_config"]?["match_original_utterances"]?.boolValue == true)
    #expect(initBody["summarization_config"]?["type"] == nil)
    #expect(initBody["summarization_config"]?["unsupportedConfig"] == nil)
    #expect(initBody["structured_data_extraction_config"]?["classes"]?[0]?.stringValue == "person")
    #expect(initBody["structured_data_extraction_config"]?["unsupportedConfig"] == nil)
    #expect(initBody["audio_to_llm_config"]?["prompts"]?[0]?.stringValue == "summarize")
    #expect(initBody["audio_to_llm_config"]?["unsupportedConfig"] == nil)
}

@Test func gladiaTranscriptionProviderOptionsRejectInvalidSchemaFields() async throws {
    let provider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "gladia-key", transport: RecordingTransport(response: jsonResponse(#"{}"#))))
    let model = try provider.transcriptionModel("default")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.gladia", message: "Gladia provider options must be an object.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .string("invalid")]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["contextPrompt": .number(1)])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["customVocabulary": .string("term")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["customVocabularyConfig": .object(["defaultIntensity": .number(0.5)])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["customVocabularyConfig": .object(["vocabulary": .array([.object(["intensity": .number(0.5)])])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["detectLanguage": .string("true")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["codeSwitchingConfig": .object(["languages": .array([.number(1)])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["callbackConfig": .object(["method": .string("PATCH")])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["subtitlesConfig": .object(["formats": .array([.string("ass")])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["diarizationConfig": .object(["enhanced": .string("true")])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["translationConfig": .object(["model": .string("enhanced")])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["translationConfig": .object(["targetLanguages": .array([.string("en")]), "model": .string("premium")])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["summarizationConfig": .object(["type": .string("paragraph")])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["customSpellingConfig": .object(["spellingDictionary": .object(["Codex": .array([.number(1)])])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["structuredDataExtractionConfig": .object([:])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["audioToLlmConfig": .object(["prompts": .array([.number(1)])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["customMetadata": .string("invalid")])]
        ))
    }
}

@Test func gladiaTranscriptionRejectsUnknownPollingStatusLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
        jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-123"}"#),
        jsonResponse(#"{"status":"paused"}"#)
    ])
    let provider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "gladia-key", transport: transport))
    let model = try provider.transcriptionModel("default")

    await #expect(throws: AIError.invalidResponse(provider: "gladia.transcription", message: "Gladia transcription status is invalid.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), mimeType: "audio/wav"))
    }
}

@Test func gladiaTranscriptionRejectsInvalidDoneResultLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
        jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-123"}"#),
        jsonResponse(#"{"status":"done","result":{"transcription":{"full_transcript":"missing metadata"}}}"#)
    ])
    let provider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "gladia-key", transport: transport))
    let model = try provider.transcriptionModel("default")

    await #expect(throws: AIError.invalidResponse(provider: "gladia.transcription", message: "Gladia transcription result is invalid.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), mimeType: "audio/wav"))
    }
}

@Test func gladiaTranscriptionThrowsWhenDoneResultIsEmpty() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
        jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-123"}"#),
        jsonResponse(#"{"status":"done"}"#)
    ])
    let provider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "gladia-key", transport: transport))
    let model = try provider.transcriptionModel("default")

    await #expect(throws: AIError.invalidResponse(provider: "gladia.transcription", message: "Gladia transcription result is empty.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), mimeType: "audio/wav"))
    }
}
