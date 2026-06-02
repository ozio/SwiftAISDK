import Foundation
import Testing
@testable import SwiftAISDK

@Test func deepgramAudioModelsCarryResponseMetadata() async throws {
    let transcriptionTransport = RecordingTransport(response: jsonResponse(
        #"{"results":{"channels":[{"alternatives":[{"transcript":"deepgram text"}]}]}}"#,
        headers: ["deepgram-header": "transcription"]
    ))
    let transcriptionProvider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transcriptionTransport))
    let transcriptionModel = try transcriptionProvider.transcriptionModel("nova-3")

    let beforeTranscription = Date()
    let transcription = try await transcriptionModel.transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8), mimeType: "audio/wav"))
    let afterTranscription = Date()

    #expect(transcription.responseMetadata.modelID == "nova-3")
    #expect(transcription.responseMetadata.headers["deepgram-header"] == "transcription")
    #expect(transcription.responseMetadata.body?["results"]?["channels"]?[0]?["alternatives"]?[0]?["transcript"]?.stringValue == "deepgram text")
    #expect(try #require(transcription.responseMetadata.timestamp) >= beforeTranscription)
    #expect(try #require(transcription.responseMetadata.timestamp) <= afterTranscription)

    let speechTransport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        headers: ["content-type": "audio/wav", "deepgram-header": "speech"],
        body: Data("audio".utf8)
    ))
    let speechProvider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: speechTransport))
    let speechModel = try speechProvider.speechModel("aura-2-helena-en")

    let speech = try await speechModel.speak(SpeechRequest(text: "hello", format: "wav_24000"))

    #expect(speech.responseMetadata.modelID == "aura-2-helena-en")
    #expect(speech.responseMetadata.headers["deepgram-header"] == "speech")
    #expect(speech.responseMetadata.body == nil)
}

@Test func elevenLabsLMNTHumeAndGroqAudioCarryResponseMetadata() async throws {
    let elevenSpeechTransport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        headers: ["content-type": "audio/mpeg", "eleven-header": "speech"],
        body: Data("eleven-audio".utf8)
    ))
    let elevenSpeechProvider = try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: "eleven-key", transport: elevenSpeechTransport))
    let elevenSpeechModel = try elevenSpeechProvider.speechModel("eleven_multilingual_v2")

    let elevenSpeech = try await elevenSpeechModel.speak(SpeechRequest(text: "hello"))

    #expect(elevenSpeech.responseMetadata.modelID == "eleven_multilingual_v2")
    #expect(elevenSpeech.responseMetadata.headers["eleven-header"] == "speech")

    let elevenTranscriptionTransport = RecordingTransport(response: jsonResponse(
        #"{"text":"eleven transcript"}"#,
        headers: ["eleven-header": "transcription"]
    ))
    let elevenTranscriptionProvider = try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: "eleven-key", transport: elevenTranscriptionTransport))
    let elevenTranscriptionModel = try elevenTranscriptionProvider.transcriptionModel("scribe_v1")

    let elevenTranscription = try await elevenTranscriptionModel.transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8), mimeType: "audio/wav"))

    #expect(elevenTranscription.responseMetadata.modelID == "scribe_v1")
    #expect(elevenTranscription.responseMetadata.headers["eleven-header"] == "transcription")
    #expect(elevenTranscription.responseMetadata.body?["text"]?.stringValue == "eleven transcript")

    let lmntTransport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        headers: ["content-type": "audio/wav", "lmnt-header": "speech"],
        body: Data("lmnt-audio".utf8)
    ))
    let lmntProvider = try AIProviders.lmnt(settings: ProviderSettings(apiKey: "lmnt-key", transport: lmntTransport))
    let lmntModel = try lmntProvider.speechModel("blizzard")

    let lmnt = try await lmntModel.speak(SpeechRequest(text: "hello"))

    #expect(lmnt.responseMetadata.modelID == "blizzard")
    #expect(lmnt.responseMetadata.headers["lmnt-header"] == "speech")

    let humeTransport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        headers: ["content-type": "audio/wav", "hume-header": "speech"],
        body: Data("hume-audio".utf8)
    ))
    let humeProvider = try AIProviders.hume(settings: ProviderSettings(apiKey: "hume-key", transport: humeTransport))
    let humeModel = try humeProvider.speechModel("hume")

    let hume = try await humeModel.speak(SpeechRequest(text: "hello"))

    #expect(hume.responseMetadata.modelID == "hume")
    #expect(hume.responseMetadata.headers["hume-header"] == "speech")

    let groqTransport = RecordingTransport(response: jsonResponse(
        #"{"text":"groq transcript","x_groq":{"id":"groq-response"}}"#,
        headers: ["groq-header": "transcription"]
    ))
    let groqProvider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: groqTransport))
    let groqModel = try groqProvider.transcriptionModel("whisper-large-v3")

    let groq = try await groqModel.transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8), mimeType: "audio/wav"))

    #expect(groq.responseMetadata.modelID == "whisper-large-v3")
    #expect(groq.responseMetadata.headers["groq-header"] == "transcription")
    #expect(groq.responseMetadata.body?["text"]?.stringValue == "groq transcript")
}

@Test func asyncTranscriptionProvidersCarryFinalResponseMetadata() async throws {
    let falTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"fal-job"}"#, headers: ["fal-header": "queue"]),
        jsonResponse(#"{"text":"fal transcript"}"#, headers: ["fal-header": "result"])
    ])
    let falProvider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: falTransport))
    let falModel = try falProvider.transcriptionModel("whisper")

    let fal = try await falModel.transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8), mimeType: "audio/wav"))

    #expect(fal.responseMetadata.modelID == "whisper")
    #expect(fal.responseMetadata.headers["fal-header"] == "result")
    #expect(fal.responseMetadata.body?["text"]?.stringValue == "fal transcript")

    let assemblyTransport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"assembly-job","status":"queued"}"#),
        jsonResponse(#"{"id":"assembly-job","status":"completed","text":"assembly transcript"}"#, headers: ["assembly-header": "result"])
    ])
    let assemblyProvider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: assemblyTransport))
    let assemblyModel = try assemblyProvider.transcriptionModel("best")

    let assembly = try await assemblyModel.transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8), mimeType: "audio/wav"))

    #expect(assembly.responseMetadata.id == "assembly-job")
    #expect(assembly.responseMetadata.modelID == "best")
    #expect(assembly.responseMetadata.headers["assembly-header"] == "result")
    #expect(assembly.responseMetadata.body?["text"]?.stringValue == "assembly transcript")

    let revTransport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"rev-job","status":"transcribed"}"#),
        jsonResponse(#"{"monologues":[{"elements":[{"type":"text","value":"rev"},{"type":"punct","value":" "},{"type":"text","value":"transcript"}]}]}"#, headers: ["rev-header": "transcript"])
    ])
    let revProvider = try AIProviders.revAI(settings: ProviderSettings(apiKey: "rev-key", transport: revTransport))
    let revModel = try revProvider.transcriptionModel("machine")

    let rev = try await revModel.transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8), mimeType: "audio/wav"))

    #expect(rev.responseMetadata.modelID == "machine")
    #expect(rev.responseMetadata.headers["rev-header"] == "transcript")
    #expect(rev.responseMetadata.body?["monologues"]?[0]?["elements"]?[0]?["value"]?.stringValue == "rev")

    let gladiaTransport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://gladia.example.com/audio.wav"}"#),
        jsonResponse(#"{"result_url":"https://gladia.example.com/result"}"#),
        jsonResponse(#"{"status":"done","result":{"metadata":{"audio_duration":1.0},"transcription":{"full_transcript":"gladia transcript","languages":["en"],"utterances":[{"start":0,"end":1.0,"text":"gladia transcript"}]}}}"#, headers: ["gladia-header": "result"])
    ])
    let gladiaProvider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "gladia-key", transport: gladiaTransport))
    let gladiaModel = try gladiaProvider.transcriptionModel("default")

    let gladia = try await gladiaModel.transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8), mimeType: "audio/wav"))

    #expect(gladia.responseMetadata.modelID == "default")
    #expect(gladia.responseMetadata.headers["gladia-header"] == "result")
    #expect(gladia.responseMetadata.body?["result"]?["transcription"]?["full_transcript"]?.stringValue == "gladia transcript")
}

@Test func falSpeechCarriesSubmissionResponseMetadata() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio":{"url":"https://fal.example.com/audio.mp3"},"request_id":"speech-job"}"#, headers: ["fal-header": "submit"]),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg", "download-header": "audio"], body: Data("fal-audio".utf8))
    ])
    let provider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transport))
    let model = try provider.speechModel("fal-ai/minimax/speech-02-hd")

    let result = try await model.speak(SpeechRequest(text: "hello"))

    #expect(result.responseMetadata.modelID == "fal-ai/minimax/speech-02-hd")
    #expect(result.responseMetadata.headers["fal-header"] == "submit")
    #expect(result.responseMetadata.headers["download-header"] == nil)
    #expect(result.responseMetadata.body?["request_id"]?.stringValue == "speech-job")
}
