import Foundation
import Testing
@testable import SwiftAISDK

@Test func fishAudioProviderCreatesSpeechAndTranscriptionModels() throws {
    let provider = try createFishAudio(settings: ProviderSettings(
        apiKey: "fish-key",
        environment: [:]
    ))

    let speech = try provider.speech("s2.1-pro")
    let speechAlias = try provider.speechModel("s1")
    let transcription = try provider.transcription()
    let transcriptionAlias = try provider.transcriptionModel("custom-route")

    #expect(speech is FishAudioSpeechModel)
    #expect(speech.providerID == "fish-audio.speech")
    #expect(speech.modelID == "s2.1-pro")
    #expect(speechAlias is FishAudioSpeechModel)
    #expect(transcription is FishAudioTranscriptionModel)
    #expect(transcription.providerID == "fish-audio.transcription")
    #expect(transcription.modelID == "transcribe-1")
    #expect(transcriptionAlias.modelID == "custom-route")
    #expect(provider.providerID == "fish-audio")
    #expect(provider.supportedCapabilities == [.speech, .transcription])
    #expect(fishAudioProviderVersion == "3.0.12")
}

@Test func fishAudioProviderRejectsUnsupportedModelFamilies() throws {
    let provider = try FishAudioProvider(settings: ProviderSettings(
        apiKey: "fish-key",
        environment: [:]
    ))

    #expect(throws: AIError.unsupportedModel(
        provider: "fish-audio",
        capability: .language,
        modelID: "s1"
    )) {
        _ = try provider.languageModel("s1")
    }
    #expect(throws: AIError.unsupportedModel(
        provider: "fish-audio",
        capability: .embedding,
        modelID: "s1"
    )) {
        _ = try provider.embeddingModel("s1")
    }
    #expect(throws: AIError.unsupportedModel(
        provider: "fish-audio",
        capability: .image,
        modelID: "s1"
    )) {
        _ = try provider.imageModel("s1")
    }
    #expect(throws: AIError.unsupportedModel(
        provider: "fish-audio",
        capability: .video,
        modelID: "s1"
    )) {
        _ = try provider.videoModel("s1")
    }
    #expect(throws: AIError.unsupportedModel(
        provider: "fish-audio",
        capability: .reranking,
        modelID: "s1"
    )) {
        _ = try provider.rerankingModel("s1")
    }
}

@Test func fishAudioProviderLoadsAPIKeyFromInjectedEnvironment() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        body: Data("audio".utf8)
    ))
    let provider = try createFishAudio(settings: ProviderSettings(
        baseURL: "https://fish.example.test/",
        headers: [
            "X-Custom": "custom",
            "User-Agent": "app/1.0"
        ],
        environment: ["FISH_AUDIO_API_KEY": "environment-key"],
        transport: transport
    ))

    _ = try await provider.speech("s1").speak(SpeechRequest(text: "Hello"))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://fish.example.test/v1/tts")
    #expect(request.headers["authorization"] == "Bearer environment-key")
    #expect(request.headers["x-custom"] == "custom")
    #expect(request.headers["user-agent"] == "app/1.0 ai-sdk/fish-audio/3.0.12")
}

@Test func fishAudioProviderRequiresAPIKeyAndHonorsCustomAuthorization() async throws {
    #expect(throws: AIError.missingAPIKey(
        provider: "fish-audio",
        environmentVariables: ["FISH_AUDIO_API_KEY"]
    )) {
        _ = try createFishAudio(settings: ProviderSettings(environment: [:]))
    }

    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        body: Data("audio".utf8)
    ))
    let provider = try createFishAudio(settings: ProviderSettings(
        apiKey: "ignored-key",
        headers: ["Authorization": "Bearer custom-key"],
        environment: [:],
        transport: transport
    ))
    _ = try await provider.speechModel("s1").speak(
        SpeechRequest(text: "Hello")
    )

    let request = try #require(await transport.requests().first)
    #expect(request.headers["authorization"] == "Bearer custom-key")
}
