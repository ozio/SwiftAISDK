import Foundation
import Testing
@testable import SwiftAISDK

@Test func cartesiaProviderExposesSpeechAndBatchTranscriptionEntities() throws {
    let provider = try AIProviders.cartesia(settings: CartesiaProviderSettings(
        apiKey: "cartesia-key",
        environment: [:],
        transport: RecordingTransport(response: jsonResponse("{}"))
    ))

    #expect(provider.providerID == "cartesia")
    #expect(provider.supportedCapabilities == [.speech, .transcription])
    #expect(try provider.speech("sonic-3.5").providerID == "cartesia.speech")
    #expect(try provider.speechModel("sonic-3.5").modelID == "sonic-3.5")
    #expect(try provider.transcription("ink-whisper").providerID == "cartesia.transcription")
    #expect(try provider.transcriptionModel("ink-whisper").modelID == "ink-whisper")
}

@Test func cartesiaProviderRequiresAPIKeyEvenWithCustomAuthorization() {
    #expect(throws: AIError.missingAPIKey(
        provider: "cartesia",
        environmentVariables: ["CARTESIA_API_KEY"]
    )) {
        _ = try AIProviders.cartesia(settings: CartesiaProviderSettings(
            headers: ["Authorization": "Bearer custom"],
            environment: [:]
        ))
    }
}

@Test func cartesiaProviderRejectsUnsupportedModelFamilies() throws {
    let provider = try AIProviders.cartesia(settings: CartesiaProviderSettings(
        apiKey: "cartesia-key",
        environment: [:]
    ))

    #expect(throws: AIError.unsupportedModel(
        provider: "cartesia",
        capability: .language,
        modelID: "sonic-3.5"
    )) {
        _ = try provider.languageModel("sonic-3.5")
    }
    #expect(throws: AIError.unsupportedModel(
        provider: "cartesia",
        capability: .embedding,
        modelID: "embed"
    )) {
        _ = try provider.embeddingModel("embed")
    }
    #expect(throws: AIError.unsupportedModel(
        provider: "cartesia",
        capability: .image,
        modelID: "image"
    )) {
        _ = try provider.imageModel("image")
    }
}
