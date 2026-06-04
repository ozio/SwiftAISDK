import Foundation
import Testing
@testable import SwiftAISDK

private struct LiveSmokeJSONResult: Decodable, Sendable {
    var ok: Bool
}

@Test func liveProviderSmokeOpenAIGenerateText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.openAIProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_OPENAI_MODEL", defaultValue: "gpt-4.1-mini"))
    let result = try await AI.generateText(
        model: model,
        prompt: "Reply with two short words.",
        temperature: 0,
        maxOutputTokens: 24,
        retryPolicy: .none
    )

    #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func liveProviderSmokeOpenAIStreamText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.openAIProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_OPENAI_MODEL", defaultValue: "gpt-4.1-mini"))
    let text = try await LiveProviderSmoke.collectText(
        from: AI.streamText(
            model: model,
            prompt: "Reply with two short words.",
            temperature: 0,
            maxOutputTokens: 24,
            retryPolicy: .none
        )
    )

    #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func liveProviderSmokeOpenAIEmbedding() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.openAIProvider()
    let model = try provider.embeddingModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_OPENAI_EMBEDDING_MODEL", defaultValue: "text-embedding-3-small"))
    let result = try await AI.embed(model: model, value: "live embedding smoke", retryPolicy: .none)

    #expect(result.embeddings.count == 1)
    #expect(result.embeddings.first?.isEmpty == false)
}

@Test func liveProviderSmokeOpenAIToolLoop() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.openAIProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_OPENAI_MODEL", defaultValue: "gpt-4.1-mini"))
    try await LiveProviderSmoke.assertToolLoop(model: model, maxOutputTokens: 64)
}

@Test func liveProviderSmokeOpenAIStreamToolLoop() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.openAIProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_OPENAI_MODEL", defaultValue: "gpt-4.1-mini"))
    try await LiveProviderSmoke.assertStreamToolLoop(model: model, maxOutputTokens: 64, expectsToolInputLifecycle: true)
}

@Test func liveProviderSmokeAnthropicGenerateText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.anthropicProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_ANTHROPIC_MODEL", defaultValue: "claude-haiku-4-5-20251001"))
    let result = try await AI.generateText(
        model: model,
        prompt: "Reply with two short words.",
        temperature: 0,
        maxOutputTokens: 24,
        retryPolicy: .none
    )

    #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func liveProviderSmokeAnthropicStreamText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.anthropicProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_ANTHROPIC_MODEL", defaultValue: "claude-haiku-4-5-20251001"))
    let text = try await LiveProviderSmoke.collectText(
        from: AI.streamText(
            model: model,
            prompt: "Reply with two short words.",
            temperature: 0,
            maxOutputTokens: 24,
            retryPolicy: .none
        )
    )

    #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func liveProviderSmokeAnthropicToolLoop() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.anthropicProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_ANTHROPIC_MODEL", defaultValue: "claude-haiku-4-5-20251001"))
    try await LiveProviderSmoke.assertToolLoop(model: model, maxOutputTokens: 96)
}

@Test func liveProviderSmokeAnthropicStreamToolLoop() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.anthropicProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_ANTHROPIC_MODEL", defaultValue: "claude-haiku-4-5-20251001"))
    try await LiveProviderSmoke.assertStreamToolLoop(model: model, maxOutputTokens: 96, expectsToolInputLifecycle: true)
}

@Test func liveProviderSmokeGoogleGenerateText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.googleProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_GOOGLE_MODEL", defaultValue: "gemini-flash-lite-latest"))
    let result = try await AI.generateText(
        model: model,
        prompt: "Reply with two short words.",
        temperature: 0,
        maxOutputTokens: 64,
        retryPolicy: .none
    )

    #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func liveProviderSmokeGoogleStreamText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.googleProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_GOOGLE_MODEL", defaultValue: "gemini-flash-lite-latest"))
    let text = try await LiveProviderSmoke.collectText(
        from: AI.streamText(
            model: model,
            prompt: "Reply with two short words.",
            temperature: 0,
            maxOutputTokens: 64,
            retryPolicy: .none
        )
    )

    #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func liveProviderSmokeGoogleEmbedding() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.googleProvider()
    let model = try provider.embeddingModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_GOOGLE_EMBEDDING_MODEL", defaultValue: "gemini-embedding-001"))
    let result = try await AI.embed(model: model, value: "live embedding smoke", retryPolicy: .none)

    #expect(result.embeddings.count == 1)
    #expect(result.embeddings.first?.isEmpty == false)
}

@Test func liveProviderSmokeGoogleToolLoop() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.googleProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_GOOGLE_MODEL", defaultValue: "gemini-flash-lite-latest"))
    try await LiveProviderSmoke.assertToolLoop(model: model, maxOutputTokens: 96)
}

@Test func liveProviderSmokeGoogleStreamToolLoop() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.googleProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_GOOGLE_MODEL", defaultValue: "gemini-flash-lite-latest"))
    try await LiveProviderSmoke.assertStreamToolLoop(model: model, maxOutputTokens: 96, expectsToolInputLifecycle: true)
}

@Test func liveProviderSmokeDeepSeekGenerateText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.deepSeekProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_DEEPSEEK_MODEL", defaultValue: "deepseek-chat"))
    let result = try await AI.generateText(
        model: model,
        prompt: "Reply with two short words.",
        temperature: 0,
        maxOutputTokens: 24,
        retryPolicy: .none
    )

    #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func liveProviderSmokeDeepSeekStreamText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.deepSeekProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_DEEPSEEK_MODEL", defaultValue: "deepseek-chat"))
    let text = try await LiveProviderSmoke.collectText(
        from: AI.streamText(
            model: model,
            prompt: "Reply with two short words.",
            temperature: 0,
            maxOutputTokens: 24,
            retryPolicy: .none
        )
    )

    #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func liveProviderSmokeDeepSeekToolLoop() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.deepSeekProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_DEEPSEEK_MODEL", defaultValue: "deepseek-chat"))
    try await LiveProviderSmoke.assertToolLoop(model: model, maxOutputTokens: 96)
}

@Test func liveProviderSmokeDeepSeekStreamToolLoop() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.deepSeekProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_DEEPSEEK_MODEL", defaultValue: "deepseek-chat"))
    try await LiveProviderSmoke.assertStreamToolLoop(model: model, maxOutputTokens: 96, expectsToolInputLifecycle: true)
}

@Test func liveProviderSmokeAssemblyAITranscription() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.assemblyAIProvider()
    let model = try provider.transcriptionModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_ASSEMBLYAI_MODEL", defaultValue: "universal-2"))
    do {
        let result = try await model.transcribe(AudioTranscriptionRequest(
            audio: LiveProviderSmoke.generatedWAVAudio(),
            fileName: "live-smoke.wav",
            mimeType: "audio/wav",
            language: "en"
        ))

        #expect(result.responseMetadata.id != nil)
        #expect(result.responseMetadata.modelID == model.modelID)
    } catch let error as AIError where LiveProviderSmoke.isExpectedLiveAccountLimitation(error) {
        return
    }
}

@Test func liveProviderSmokeElevenLabsSpeech() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.elevenLabsProvider()
    let model = try provider.speechModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_ELEVENLABS_SPEECH_MODEL", defaultValue: "eleven_multilingual_v2"))
    let result: SpeechResult
    do {
        result = try await model.speak(SpeechRequest(
            text: "Swift AI smoke test one two three.",
            voice: LiveProviderSmoke.modelID(environmentVariable: "LIVE_ELEVENLABS_VOICE", defaultValue: "21m00Tcm4TlvDq8ikWAM"),
            format: "mp3_64",
            providerOptions: [
                "elevenlabs": .object([
                    "languageCode": "en",
                    "voiceSettings": [
                        "stability": 0.5,
                        "similarityBoost": 0.75,
                        "useSpeakerBoost": true
                    ],
                    "enableLogging": false
                ])
            ]
        ))
    } catch let error as AIError where LiveProviderSmoke.isExpectedLiveAccountLimitation(error) {
        return
    }

    #expect(!result.audio.isEmpty)
    #expect(result.contentType?.contains("audio") == true)
    #expect(result.responseMetadata.modelID == model.modelID)
}

@Test func liveProviderSmokeElevenLabsTranscription() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.elevenLabsProvider()
    let speechModel = try provider.speechModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_ELEVENLABS_SPEECH_MODEL", defaultValue: "eleven_multilingual_v2"))
    let audio = try await speechModel.speak(SpeechRequest(
        text: "Swift AI smoke test one two three.",
        voice: LiveProviderSmoke.modelID(environmentVariable: "LIVE_ELEVENLABS_VOICE", defaultValue: "21m00Tcm4TlvDq8ikWAM"),
        format: "mp3_64",
        providerOptions: [
            "elevenlabs": .object([
                "languageCode": "en",
                "enableLogging": false
            ])
        ]
    ))
    let transcriptionModel = try provider.transcriptionModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_ELEVENLABS_TRANSCRIPTION_MODEL", defaultValue: "scribe_v1"))
    let result = try await transcriptionModel.transcribe(AudioTranscriptionRequest(
        audio: audio.audio,
        fileName: "live-smoke.mp3",
        mimeType: audio.contentType ?? "audio/mpeg",
        providerOptions: [
            "elevenlabs": .object([
                "languageCode": "en",
                "tagAudioEvents": false,
                "diarize": false,
                "timestampsGranularity": "word",
                "fileFormat": "other"
            ])
        ]
    ))

    #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    #expect(result.responseMetadata.id != nil)
    #expect(result.responseMetadata.modelID == transcriptionModel.modelID)
}

@Test func liveProviderSmokeElevenLabsSoundEffects() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.elevenLabsProvider()
    let model = try provider.soundEffectsModel()
    do {
        let result = try await AI.generateAudio(
            model: model,
            request: AudioGenerationRequest(
                prompt: "A single soft interface click.",
                durationSeconds: 0.5,
                format: "mp3_32",
                providerOptions: ["elevenlabs": .object(["promptInfluence": 0.3])]
            ),
            retryPolicy: .none
        )
        #expect(!result.audio.isEmpty)
        #expect(result.contentType?.contains("audio") == true)
    } catch let error as AIError where LiveProviderSmoke.isExpectedLiveAccountLimitation(error) {
        return
    }
}

@Test func liveProviderSmokeElevenLabsMusic() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.elevenLabsProvider()
    let model = try provider.musicModel()
    do {
        let result = try await AI.generateAudio(
            model: model,
            request: AudioGenerationRequest(
                prompt: "Three seconds of quiet instrumental piano, no vocals.",
                durationSeconds: 3,
                format: "mp3_32",
                providerOptions: ["elevenlabs": .object(["forceInstrumental": true])]
            ),
            retryPolicy: .none
        )
        #expect(!result.audio.isEmpty)
        #expect(result.contentType?.contains("audio") == true)
    } catch let error as AIError where LiveProviderSmoke.isExpectedLiveAccountLimitation(error) {
        return
    }
}

@Test func liveProviderSmokeElevenLabsVoiceChangerAndIsolator() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.elevenLabsProvider()
    let speechModel = try provider.speechModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_ELEVENLABS_SPEECH_MODEL", defaultValue: "eleven_multilingual_v2"))
    let source = try await speechModel.speak(SpeechRequest(
        text: "Swift AI voice tools smoke test. This sentence is intentionally a little longer so the isolation endpoint receives enough audio.",
        voice: LiveProviderSmoke.modelID(environmentVariable: "LIVE_ELEVENLABS_VOICE", defaultValue: "21m00Tcm4TlvDq8ikWAM"),
        format: "mp3_32",
        providerOptions: ["elevenlabs": .object(["languageCode": "en", "enableLogging": false])]
    ))

    do {
        let changer = try provider.voiceChangerModel()
        let changed = try await AI.transformAudio(
            model: changer,
            request: AudioTransformationRequest(
                audio: source.audio,
                fileName: "voice.mp3",
                mimeType: source.contentType ?? "audio/mpeg",
                voice: LiveProviderSmoke.modelID(environmentVariable: "LIVE_ELEVENLABS_VOICE", defaultValue: "21m00Tcm4TlvDq8ikWAM"),
                format: "mp3_32",
                providerOptions: ["elevenlabs": .object(["enableLogging": false, "fileFormat": "other"])]
            ),
            retryPolicy: .none
        )
        #expect(!changed.audio.isEmpty)
        #expect(changed.contentType?.contains("audio") == true)
    } catch let error as AIError where LiveProviderSmoke.isExpectedLiveAccountLimitation(error) {
        return
    }

    do {
        let isolator = try provider.voiceIsolatorModel()
        let isolated = try await AI.transformAudio(
            model: isolator,
            request: AudioTransformationRequest(
                audio: source.audio,
                fileName: "voice.mp3",
                mimeType: source.contentType ?? "audio/mpeg",
                providerOptions: ["elevenlabs": .object(["fileFormat": "other"])]
            ),
            retryPolicy: .none
        )
        #expect(!isolated.audio.isEmpty)
        #expect(isolated.contentType?.contains("audio") == true)
    } catch let error as AIError where LiveProviderSmoke.isExpectedLiveAccountLimitation(error) {
        return
    }
}

@Test func liveProviderSmokeElevenLabsDubbing() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.elevenLabsProvider()
    let speechModel = try provider.speechModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_ELEVENLABS_SPEECH_MODEL", defaultValue: "eleven_multilingual_v2"))
    let source = try await speechModel.speak(SpeechRequest(
        text: "Hello from Swift AI.",
        voice: LiveProviderSmoke.modelID(environmentVariable: "LIVE_ELEVENLABS_VOICE", defaultValue: "21m00Tcm4TlvDq8ikWAM"),
        format: "mp3_32",
        providerOptions: ["elevenlabs": .object(["languageCode": "en", "enableLogging": false])]
    ))

    do {
        let client = try provider.dubbing()
        let created = try await client.create(DubbingCreateRequest(
            file: source.audio,
            fileName: "dubbing-smoke.mp3",
            mimeType: source.contentType ?? "audio/mpeg",
            name: "SwiftAISDK live smoke",
            sourceLanguage: "en",
            targetLanguage: "es",
            numSpeakers: 1,
            watermark: true,
            extraBody: ["disableVoiceCloning": true, "dropBackgroundAudio": true]
        ))
        #expect(!created.dubbingID.isEmpty)
        let status = try await client.get(created.dubbingID)
        #expect(status.dubbingID == created.dubbingID)
        #expect(!status.status.isEmpty)
    } catch let error as AIError where LiveProviderSmoke.isExpectedLiveAccountLimitation(error) {
        return
    }
}

@Test func liveProviderSmokeOpenAICompatibleGenerateText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.openAICompatibleProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_OPENAI_COMPATIBLE_MODEL", defaultValue: "llama"))
    let result = try await AI.generateText(
        model: model,
        prompt: "Reply with two short words.",
        temperature: 0,
        maxOutputTokens: 24,
        retryPolicy: .none
    )

    #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func liveProviderSmokeOpenAICompatibleStreamText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.openAICompatibleProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_OPENAI_COMPATIBLE_MODEL", defaultValue: "llama"))
    let text = try await LiveProviderSmoke.collectText(
        from: AI.streamText(
            model: model,
            prompt: "Reply with two short words.",
            temperature: 0,
            maxOutputTokens: 24,
            retryPolicy: .none
        )
    )

    #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func liveProviderSmokeOpenAICompatibleCompletionGenerateText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.openAICompatibleProvider()
    let model = try provider.completionModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_OPENAI_COMPATIBLE_MODEL", defaultValue: "llama"))
    let result = try await AI.generateText(
        model: model,
        prompt: "Complete with two short words.",
        temperature: 0,
        maxOutputTokens: 24,
        retryPolicy: .none
    )

    #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func liveProviderSmokeOpenAICompatibleToolLoop() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.openAICompatibleProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_OPENAI_COMPATIBLE_MODEL", defaultValue: "llama"))
    try await LiveProviderSmoke.assertToolLoop(model: model, maxOutputTokens: 96)
}

@Test func liveProviderSmokeOpenAICompatibleStreamToolLoop() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.openAICompatibleProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_OPENAI_COMPATIBLE_MODEL", defaultValue: "llama"))
    try await LiveProviderSmoke.assertStreamToolLoop(model: model, maxOutputTokens: 96, expectsToolInputLifecycle: true)
}

@Test func liveProviderSmokeOpenAICompatibleGenerateObject() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.openAICompatibleProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_OPENAI_COMPATIBLE_MODEL", defaultValue: "llama"))
    let schema = AIJSONSchema<LiveSmokeJSONResult>(
        [
            "type": "object",
            "properties": [
                "ok": ["type": "boolean"]
            ],
            "required": ["ok"]
        ],
        name: "live_smoke_json_result"
    )
    let result = try await AI.generateObject(
        model: model,
        prompt: "Return JSON with ok set to true.",
        schema: schema,
        temperature: 0,
        maxOutputTokens: 64,
        retryPolicy: .none
    )

    #expect(result.object.ok == true)
}

private enum LiveProviderSmoke {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["LIVE_AI_TESTS"] == "1"
    }

    static func openAIProvider() throws -> OpenAICompatibleProvider {
        let apiKey = try apiKey(environmentVariable: "OPENAI_API_KEY")
        return try AIProviders.openAI(settings: ProviderSettings(apiKey: apiKey))
    }

    static func anthropicProvider() throws -> AnthropicProvider {
        let apiKey = try apiKey(environmentVariable: "ANTHROPIC_API_KEY")
        return try AIProviders.anthropic(settings: ProviderSettings(apiKey: apiKey))
    }

    static func googleProvider() throws -> GoogleGenerativeAIProvider {
        let apiKey = try apiKey(environmentVariable: "GEMINI_API_KEY")
        return try AIProviders.google(settings: ProviderSettings(apiKey: apiKey))
    }

    static func deepSeekProvider() throws -> OpenAICompatibleProvider {
        let apiKey = try apiKey(environmentVariable: "DEEPSEEK_API_KEY")
        return try AIProviders.deepSeek(settings: ProviderSettings(apiKey: apiKey))
    }

    static func assemblyAIProvider() throws -> OpenAICompatibleProvider {
        let apiKey = try apiKey(environmentVariable: "ASSEMBLYAI_API_KEY")
        return try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: apiKey))
    }

    static func elevenLabsProvider() throws -> OpenAICompatibleProvider {
        let apiKey = try apiKey(environmentVariable: "ELEVENLABS_API_KEY")
        return try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: apiKey))
    }

    static func openAICompatibleProvider() throws -> OpenAICompatibleProvider {
        let apiKey = try apiKey(environmentVariable: "OPENAI_COMPATIBLE_API_KEY")
        let baseURL = modelID(environmentVariable: "LIVE_OPENAI_COMPATIBLE_BASE_URL", defaultValue: "https://evo.ozio.io/llama/v1")
        return try AIProviders.openAICompatible(name: "openai-compatible-live", baseURL: baseURL, apiKey: apiKey)
    }

    static func collectText(from stream: AsyncThrowingStream<LanguageStreamPart, Error>) async throws -> String {
        var text = ""
        for try await part in stream {
            switch part {
            case let .textDelta(delta):
                text += delta
            case let .textDeltaPart(_, delta, _):
                text += delta
            default:
                break
            }
        }
        return text
    }

    static func assertToolLoop(model: any LanguageModel, maxOutputTokens: Int) async throws {
        let tracker = LiveToolTracker()
        let tool = weatherTool(tracker: tracker)

        let result = try await AI.generateText(
            model: model,
            prompt: "Use the lookup_weather tool exactly once for Tokyo. Then reply with the forecast word only.",
            temperature: 0,
            maxOutputTokens: maxOutputTokens,
            executableTools: [tool],
            maxSteps: 2,
            retryPolicy: .none
        )

        let toolCallCount = await tracker.count()
        #expect(toolCallCount == 1)
        #expect(result.toolResults.count == 1)
        #expect(result.toolResults.first?.result["forecast"]?.stringValue == "sunny")
        #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    static func assertStreamToolLoop(model: any LanguageModel, maxOutputTokens: Int, expectsToolInputLifecycle: Bool) async throws {
        let tracker = LiveToolTracker()
        let tool = weatherTool(tracker: tracker)

        var text = ""
        var toolResults: [AIToolResult] = []
        var toolInputStarts = 0
        var toolInputEnds = 0
        for try await part in AI.streamText(
            model: model,
            prompt: "Use the lookup_weather tool exactly once for Tokyo. Then reply with the forecast word only.",
            temperature: 0,
            maxOutputTokens: maxOutputTokens,
            executableTools: [tool],
            maxSteps: 2,
            retryPolicy: .none
        ) {
            switch part {
            case let .textDelta(delta):
                text += delta
            case let .textDeltaPart(_, delta, _):
                text += delta
            case let .toolResult(result):
                toolResults.append(result)
            case .toolInputStart(_, _, _, _, _, _):
                toolInputStarts += 1
            case .toolInputEnd(_, _):
                toolInputEnds += 1
            default:
                break
            }
        }

        let toolCallCount = await tracker.count()
        #expect(toolCallCount == 1)
        #expect(toolResults.count == 1)
        #expect(toolResults.first?.result["forecast"]?.stringValue == "sunny")
        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if expectsToolInputLifecycle {
            #expect(toolInputStarts >= 1)
            #expect(toolInputEnds >= 1)
        }
    }

    static func weatherTool(tracker: LiveToolTracker) -> AITool {
        AITool(
            name: "lookup_weather",
            description: "Looks up a deterministic weather forecast for a city.",
            parameters: [
                "type": "object",
                "properties": [
                    "city": [
                        "type": "string",
                        "description": "City name to look up."
                    ]
                ],
                "required": ["city"]
            ]
        ) { arguments in
            await tracker.record(city: arguments["city"]?.stringValue)
        }
    }

    static func modelID(environmentVariable: String, defaultValue: String) -> String {
        let rawValue = ProcessInfo.processInfo.environment[environmentVariable] ?? defaultValue
        return rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func apiKey(environmentVariable: String) throws -> String {
        if let value = ProcessInfo.processInfo.environment[environmentVariable]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }

        throw AIError.missingAPIKey(provider: "live-smoke", environmentVariables: [environmentVariable])
    }

    static func generatedWAVAudio() -> Data {
        let sampleRate = 16_000
        let durationSeconds = 2
        let sampleCount = sampleRate * durationSeconds
        let channelCount = 1
        let bitsPerSample = 16
        let blockAlign = channelCount * bitsPerSample / 8
        let byteRate = sampleRate * blockAlign
        let dataByteCount = sampleCount * blockAlign

        var data = Data()
        data.reserveCapacity(44 + dataByteCount)
        data.appendASCII("RIFF")
        data.appendUInt32LE(UInt32(36 + dataByteCount))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(UInt16(channelCount))
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(UInt32(byteRate))
        data.appendUInt16LE(UInt16(blockAlign))
        data.appendUInt16LE(UInt16(bitsPerSample))
        data.appendASCII("data")
        data.appendUInt32LE(UInt32(dataByteCount))

        for sampleIndex in 0..<sampleCount {
            let seconds = Double(sampleIndex) / Double(sampleRate)
            let envelope = min(1, min(seconds * 8, (Double(durationSeconds) - seconds) * 8))
            let value = Int16(sin(2 * Double.pi * 440 * seconds) * 10_000 * envelope)
            data.appendUInt16LE(UInt16(bitPattern: value))
        }

        return data
    }

    static func isExpectedLiveAccountLimitation(_ error: AIError) -> Bool {
        let description = error.description.lowercased()
        let markers = ["billing", "balance", "credit", "credits", "funds", "insufficient", "payment", "quota", "permission", "permissions", "scope", "subscription", "plan", "not available", "not allowed"]
        if let apiError = error.apiCallError {
            return [402, 403, 429].contains(apiError.statusCode) || markers.contains { description.contains($0) }
        }
        return markers.contains { description.contains($0) }
    }
}

private actor LiveToolTracker {
    private var toolCallCount = 0

    func record(city: String?) -> JSONValue {
        toolCallCount += 1
        return .object([
            "city": .string(city ?? "missing"),
            "forecast": .string("sunny")
        ])
    }

    func count() -> Int {
        toolCallCount
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
