import Foundation
import Testing
@testable import SwiftAISDK

@Test func nativeTranscriptionsMapSegmentsLanguageAndDuration() async throws {
    let deepgramTransport = RecordingTransport(response: jsonResponse("""
    {"results":{"channels":[{"detected_language":"en","alternatives":[{"transcript":"hello world","words":[{"word":"hello","start":0.1,"end":0.4},{"word":"world","start":0.5,"end":0.9}]}]}]},"metadata":{"duration":1.2}}
    """))
    let deepgram = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: deepgramTransport))
    let deepgramResult = try await deepgram.transcriptionModel("nova-3").transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8)))

    #expect(deepgramResult.text == "hello world")
    #expect(deepgramResult.segments == [
        TranscriptionSegment(text: "hello", startSecond: 0.1, endSecond: 0.4),
        TranscriptionSegment(text: "world", startSecond: 0.5, endSecond: 0.9)
    ])
    #expect(deepgramResult.language == "en")
    #expect(deepgramResult.durationInSeconds == 1.2)

    let elevenTransport = RecordingTransport(response: jsonResponse("""
    {"text":"eleven text","language_code":"de","words":[{"text":"eleven","start":0,"end":0.5},{"text":"text","start":0.6,"end":1.1}]}
    """))
    let eleven = try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: "eleven-key", transport: elevenTransport))
    let elevenResult = try await eleven.transcriptionModel("scribe_v1").transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8)))

    #expect(elevenResult.segments.last == TranscriptionSegment(text: "text", startSecond: 0.6, endSecond: 1.1))
    #expect(elevenResult.language == "de")
    #expect(elevenResult.durationInSeconds == 1.1)

    let groqTransport = RecordingTransport(response: jsonResponse("""
    {"text":"groq text","language":"es","duration":2.4,"segments":[{"text":"groq","start":0,"end":1.0},{"text":"text","start":1.1,"end":2.4}]}
    """))
    let groq = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: groqTransport))
    let groqResult = try await groq.transcriptionModel("whisper-large-v3").transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8)))

    #expect(groqResult.segments.count == 2)
    #expect(groqResult.language == "es")
    #expect(groqResult.durationInSeconds == 2.4)
}

@Test func asyncNativeTranscriptionsMapFinalResultDetails() async throws {
    let assemblyTransport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"assembly-job","status":"queued"}"#),
        jsonResponse(#"{"id":"assembly-job","status":"completed","text":"assembly text","language_code":"fr","audio_duration":3.2,"words":[{"text":"assembly","start":0.2,"end":1.4},{"text":"text","start":1.5,"end":3.2}]}"#)
    ])
    let assembly = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: assemblyTransport))
    let assemblyResult = try await assembly.transcriptionModel("best").transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8)))

    #expect(assemblyResult.segments.first == TranscriptionSegment(text: "assembly", startSecond: 0.2, endSecond: 1.4))
    #expect(assemblyResult.language == "fr")
    #expect(assemblyResult.durationInSeconds == 3.2)

    let revTransport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"rev-job","status":"transcribed","language":"it"}"#),
        jsonResponse(#"{"monologues":[{"elements":[{"type":"text","value":"ciao","ts":0.1,"end_ts":0.4},{"type":"punct","value":" "},{"type":"text","value":"rev","ts":0.5,"end_ts":0.9}]}]}"#)
    ])
    let rev = try AIProviders.revAI(settings: ProviderSettings(apiKey: "rev-key", transport: revTransport))
    let revResult = try await rev.transcriptionModel("machine").transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8)))

    #expect(revResult.text == "ciao rev")
    #expect(revResult.segments == [
        TranscriptionSegment(text: "ciao", startSecond: 0.1, endSecond: 0.4),
        TranscriptionSegment(text: "rev", startSecond: 0.5, endSecond: 0.9)
    ])
    #expect(revResult.language == "it")
    #expect(revResult.durationInSeconds == 0.9)

    let gladiaTransport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://gladia.example.com/audio.wav"}"#),
        jsonResponse(#"{"result_url":"https://gladia.example.com/result"}"#),
        jsonResponse(#"{"status":"done","result":{"metadata":{"audio_duration":4.5},"transcription":{"full_transcript":"gladia text","languages":["pt"],"utterances":[{"text":"gladia","start":0,"end":2.0},{"text":"text","start":2.1,"end":4.5}]}}}"#)
    ])
    let gladia = try AIProviders.gladia(settings: ProviderSettings(apiKey: "gladia-key", transport: gladiaTransport))
    let gladiaResult = try await gladia.transcriptionModel("default").transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8)))

    #expect(gladiaResult.segments.last == TranscriptionSegment(text: "text", startSecond: 2.1, endSecond: 4.5))
    #expect(gladiaResult.language == "pt")
    #expect(gladiaResult.durationInSeconds == 4.5)
}

@Test func gatewayModelsPreserveResponseMetadataAcrossJSONSurfaces() async throws {
    let languageTransport = RecordingTransport(response: jsonResponse("""
    {"id":"gateway-language","content":[{"type":"text","text":"hello"}],"finishReason":"stop"}
    """, headers: ["gateway-header": "language"]))
    let languageProvider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: languageTransport))
    let language = try await languageProvider.languageModel("openai/gpt-4.1-mini").generate(LanguageModelRequest(messages: [.user("hi")]))

    #expect(language.responseMetadata.id == "gateway-language")
    #expect(language.responseMetadata.headers["gateway-header"] == "language")
    #expect(language.responseMetadata.body?["content"]?[0]?["text"]?.stringValue == "hello")

    let imageTransport = RecordingTransport(response: jsonResponse("""
    {"id":"gateway-image","images":[{"data":"image-data"}]}
    """, headers: ["gateway-header": "image"]))
    let imageProvider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: imageTransport))
    let image = try await imageProvider.imageModel("openai/gpt-image-1").generateImage(ImageGenerationRequest(prompt: "cat"))

    #expect(image.responseMetadata.id == "gateway-image")
    #expect(image.responseMetadata.headers["gateway-header"] == "image")
    #expect(image.responseMetadata.body?["images"]?[0]?["data"]?.stringValue == "image-data")

    let speechTransport = RecordingTransport(response: jsonResponse("""
    {"id":"gateway-speech","audio":"YXVkaW8="}
    """, headers: ["gateway-header": "speech"]))
    let speechProvider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: speechTransport))
    let speech = try await speechProvider.speechModel("openai/tts-1").speak(SpeechRequest(text: "hello"))

    #expect(speech.audio == Data("audio".utf8))
    #expect(speech.responseMetadata.id == "gateway-speech")
    #expect(speech.responseMetadata.headers["gateway-header"] == "speech")

    let transcriptionTransport = RecordingTransport(response: jsonResponse("""
    {"id":"gateway-transcription","text":"gateway text","language":"en","duration":1.5,"segments":[{"text":"gateway","start":0,"end":0.7},{"text":"text","start":0.8,"end":1.5}]}
    """, headers: ["gateway-header": "transcription"]))
    let transcriptionProvider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: transcriptionTransport))
    let transcription = try await transcriptionProvider.transcriptionModel("openai/whisper-1").transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8)))

    #expect(transcription.responseMetadata.id == "gateway-transcription")
    #expect(transcription.responseMetadata.headers["gateway-header"] == "transcription")
    #expect(transcription.language == "en")
    #expect(transcription.durationInSeconds == 1.5)
    #expect(transcription.segments.last == TranscriptionSegment(text: "text", startSecond: 0.8, endSecond: 1.5))
}
