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
    #expect(request.url.absoluteString == "https://api.deepgram.com/v1/listen?detect_entities=true&detect_language=false&diarize=true&filler_words=true&language=en&model=nova-3&redact=ssn%2Cpci&search=Codex&smart_format=true&summarize=v2&topics=true&utt_split=0.8&utterances=true")
    #expect(request.headers["authorization"] == "Token deepgram-key")
    #expect(request.headers["content-type"] == "audio/wav")
    #expect(request.body == Data("wav".utf8))
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

@Test func deepgramAudioModelsMapNestedProviderOptions() async throws {
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

@Test func assemblyAITranscriptionMapsNestedProviderOptions() async throws {
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
    #expect(requests[0].headers["Authorization"] == "Bearer rev-key")
    #expect(requests[0].headers["content-type"]?.hasPrefix("multipart/form-data; boundary=SwiftAISDK-") == true)
    let form = String(data: try #require(requests[0].body), encoding: .utf8) ?? ""
    #expect(form.contains("name=\"media\"; filename=\"clip.wav\""))
    #expect(form.contains("name=\"config\""))
    #expect(form.contains("\"transcriber\":\"machine\""))
    #expect(form.contains("\"language\":\"en\""))

    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api.rev.ai/speechtotext/v1/jobs/job-123/transcript")
}

@Test func revAITranscriptionMapsNestedProviderOptions() async throws {
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
    #expect(uploadBody.contains("name=\"audio\"; filename=\"clip.wav\""))

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

@Test func gladiaTranscriptionMapsNestedProviderOptions() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
        jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-123"}"#),
        jsonResponse(#"{"status":"done","result":{"transcription":{"full_transcript":"gladia nested"}}}"#)
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

@Test func lmntSpeechMapsNestedProviderOptions() async throws {
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
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.hume.ai/v0/tts/file")
    #expect(request.headers["X-Hume-Api-Key"] == "hume-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["utterances"]?[0]?["text"]?.stringValue == "Hello")
    #expect(body["utterances"]?[0]?["voice"]?["id"]?.stringValue == "voice-id")
    #expect(body["utterances"]?[0]?["voice"]?["provider"]?.stringValue == "HUME_AI")
    #expect(body["format"]?["type"]?.stringValue == "wav")
    #expect(body["context"]?["utterances"]?[0]?["trailing_silence"]?.doubleValue == 0.25)
    #expect(body["context"]?["utterances"]?[0]?["trailingSilence"] == nil)
    #expect(body["context"]?["utterances"]?[0]?["voice"]?["id"]?.stringValue == "prior-voice")
}

@Test func humeSpeechMapsNestedProviderOptionsAndUtteranceFields() async throws {
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
