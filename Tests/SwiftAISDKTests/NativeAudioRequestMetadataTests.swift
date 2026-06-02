import Foundation
import Testing
@testable import SwiftAISDK

@Test func nativeSpeechModelsPreserveRequestMetadataBodies() async throws {
    let deepgramTransport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/wav"], body: Data("deepgram-audio".utf8)))
    let deepgram = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: deepgramTransport))
    let deepgramSpeech = try await deepgram.speechModel("aura-2-helena-en").speak(SpeechRequest(text: "hello", headers: ["x-user": "1"]))

    #expect(deepgramSpeech.requestMetadata.body?["text"]?.stringValue == "hello")
    #expect(deepgramSpeech.requestMetadata.headers["x-user"] == "1")
    #expect(deepgramSpeech.requestMetadata.headers["authorization"] == nil)

    let elevenTransport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("eleven-audio".utf8)))
    let eleven = try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: "eleven-key", transport: elevenTransport))
    let elevenSpeech = try await eleven.speechModel("eleven_multilingual_v2").speak(SpeechRequest(text: "bonjour", voice: "voice-1", format: "mp3_44100_128"))

    #expect(elevenSpeech.requestMetadata.body?["text"]?.stringValue == "bonjour")
    #expect(elevenSpeech.requestMetadata.body?["model_id"]?.stringValue == "eleven_multilingual_v2")
    #expect(elevenSpeech.requestMetadata.body?["voice_settings"] == nil)

    let lmntTransport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/wav"], body: Data("lmnt-audio".utf8)))
    let lmnt = try AIProviders.lmnt(settings: ProviderSettings(apiKey: "lmnt-key", transport: lmntTransport))
    let lmntSpeech = try await lmnt.speechModel("blizzard").speak(SpeechRequest(text: "lmnt", voice: "ava", format: "wav"))

    #expect(lmntSpeech.requestMetadata.body?["model"]?.stringValue == "blizzard")
    #expect(lmntSpeech.requestMetadata.body?["text"]?.stringValue == "lmnt")
    #expect(lmntSpeech.requestMetadata.body?["voice"]?.stringValue == "ava")

    let humeTransport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/wav"], body: Data("hume-audio".utf8)))
    let hume = try AIProviders.hume(settings: ProviderSettings(apiKey: "hume-key", transport: humeTransport))
    let humeSpeech = try await hume.speechModel("hume").speak(SpeechRequest(text: "hume", voice: "voice-id", format: "wav"))

    #expect(humeSpeech.requestMetadata.body?["utterances"]?[0]?["text"]?.stringValue == "hume")
    #expect(humeSpeech.requestMetadata.body?["utterances"]?[0]?["voice"]?["id"]?.stringValue == "voice-id")

    let falTransport = RecordingTransport(responses: [
        jsonResponse(#"{"audio":{"url":"https://fal.example.com/audio.mp3"},"request_id":"speech-job"}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("fal-audio".utf8))
    ])
    let fal = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: falTransport))
    let falSpeech = try await fal.speechModel("fal-ai/minimax/speech-02-hd").speak(SpeechRequest(text: "fal", voice: "Announcer", format: "url"))

    #expect(falSpeech.requestMetadata.body?["text"]?.stringValue == "fal")
    #expect(falSpeech.requestMetadata.body?["voice"]?.stringValue == "Announcer")
    #expect(falSpeech.requestMetadata.body?["output_format"]?.stringValue == "url")
}

@Test func compatibleGatewayAndGenericAudioModelsPreserveRequestMetadata() async throws {
    let openAISpeechTransport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("openai-audio".utf8)))
    let openAI = try AIProviders.openAI(settings: ProviderSettings(apiKey: "openai-key", transport: openAISpeechTransport))
    let openAISpeech = try await openAI.speechModel("tts-1").speak(SpeechRequest(text: "openai", voice: "alloy", format: "mp3"))

    #expect(openAISpeech.requestMetadata.body?["model"]?.stringValue == "tts-1")
    #expect(openAISpeech.requestMetadata.body?["input"]?.stringValue == "openai")
    #expect(openAISpeech.requestMetadata.body?["voice"]?.stringValue == "alloy")

    let gatewaySpeechTransport = RecordingTransport(response: jsonResponse(#"{"audio":"Z2F0ZXdheS1hdWRpbw=="}"#))
    let gateway = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: gatewaySpeechTransport))
    let gatewaySpeech = try await gateway.speechModel("openai/tts-1").speak(SpeechRequest(text: "gateway", format: "mp3"))

    #expect(gatewaySpeech.requestMetadata.body?["text"]?.stringValue == "gateway")
    #expect(gatewaySpeech.requestMetadata.body?["outputFormat"]?.stringValue == "mp3")

    let genericTransport = RecordingTransport(response: jsonResponse(#"{"audio":"Z2VuZXJpYy1hdWRpbw==","mime_type":"audio/mpeg"}"#))
    let genericConfig = ModelHTTPConfig(providerID: "generic", baseURL: "https://api.example.com", headers: [:], transport: genericTransport)
    let genericSpeech = JSONSpeechModel(modelID: "speech-model", path: "/speech", config: genericConfig)
    let generic = try await genericSpeech.speak(SpeechRequest(text: "generic", voice: "voice", format: "mp3"))

    #expect(generic.requestMetadata.body?["model"]?.stringValue == "speech-model")
    #expect(generic.requestMetadata.body?["text"]?.stringValue == "generic")
    #expect(generic.requestMetadata.body?["voice"]?.stringValue == "voice")
}

@Test func transcriptionModelsPreserveSafeRequestMetadataFields() async throws {
    let openAITransport = RecordingTransport(response: jsonResponse("""
    {"text":"openai transcript","language":"en","duration":1.0,"segments":[{"text":"openai","start":0,"end":1.0}]}
    """))
    let openAI = try AIProviders.openAI(settings: ProviderSettings(apiKey: "openai-key", transport: openAITransport))
    let openAITranscript = try await openAI.transcriptionModel("whisper-1").transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        fileName: "clip.wav",
        mimeType: "audio/wav",
        language: "en",
        prompt: "Names"
    ))

    #expect(openAITranscript.requestMetadata.body?["model"]?.stringValue == "whisper-1")
    #expect(openAITranscript.requestMetadata.body?["filename"]?.stringValue == "clip.wav")
    #expect(openAITranscript.requestMetadata.body?["mime_type"]?.stringValue == "audio/wav")
    #expect(openAITranscript.requestMetadata.body?["language"]?.stringValue == "en")
    #expect(openAITranscript.requestMetadata.body?["prompt"]?.stringValue == "Names")
    #expect(openAITranscript.requestMetadata.body?["audio"] == nil)

    let groqTransport = RecordingTransport(response: jsonResponse("""
    {"text":"groq transcript","x_groq":{"id":"groq-request"},"language":"en","segments":[{"id":0,"seek":0,"start":0,"end":0.5,"text":"groq","tokens":[1],"temperature":0,"avg_logprob":-0.1,"compression_ratio":1,"no_speech_prob":0}]}
    """))
    let groq = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: groqTransport))
    let groqTranscript = try await groq.transcriptionModel("whisper-large-v3").transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        fileName: "clip.wav",
        mimeType: "audio/wav",
        extraBody: ["timestampGranularities": .array(["segment"])]
    ))

    #expect(groqTranscript.requestMetadata.body?["model"]?.stringValue == "whisper-large-v3")
    #expect(groqTranscript.requestMetadata.body?["filename"]?.stringValue == "audio.wav")
    #expect(groqTranscript.requestMetadata.body?["timestamp_granularities"]?[0]?.stringValue == "segment")
    #expect(groqTranscript.requestMetadata.body?["audio"] == nil)

    let gatewayTransport = RecordingTransport(response: jsonResponse(#"{"text":"gateway transcript"}"#))
    let gateway = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: gatewayTransport))
    let gatewayTranscript = try await gateway.transcriptionModel("openai/whisper-1").transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8), mimeType: "audio/wav"))

    #expect(gatewayTranscript.requestMetadata.body?["mediaType"]?.stringValue == "audio/wav")
    #expect(gatewayTranscript.requestMetadata.body?["audio"]?.stringValue == Data("wav".utf8).base64EncodedString())

    let genericTransport = RecordingTransport(response: jsonResponse(#"{"text":"generic transcript"}"#))
    let genericConfig = ModelHTTPConfig(providerID: "generic", baseURL: "https://api.example.com", headers: [:], transport: genericTransport)
    let genericModel = JSONTranscriptionModel(modelID: "transcribe", path: "/transcribe", config: genericConfig)
    let genericTranscript = try await genericModel.transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8), fileName: "clip.wav", mimeType: "audio/wav"))

    #expect(genericTranscript.requestMetadata.body?["model"]?.stringValue == "transcribe")
    #expect(genericTranscript.requestMetadata.body?["filename"]?.stringValue == "clip.wav")
    #expect(genericTranscript.requestMetadata.body?["audio"]?.stringValue == Data("wav".utf8).base64EncodedString())
}
