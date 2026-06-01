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
