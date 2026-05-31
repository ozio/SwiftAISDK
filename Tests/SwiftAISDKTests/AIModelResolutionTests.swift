import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiResolvesStringLanguageModelsThroughExplicitProvider() async throws {
    let language = ResolutionLanguageModel()
    let registry = createProviderRegistry([
        "app": customProvider(languageModels: ["chat": language])
    ])

    let result = try await AI.generateText(
        model: "app:chat",
        provider: registry,
        prompt: "Hello",
        temperature: 0.2
    )

    #expect(result.text == "resolved")
    #expect(language.requests.count == 1)
    #expect(language.requests.first?.messages == [.user("Hello")])
    #expect(language.requests.first?.temperature == 0.2)
}

@Test func aiDefaultProviderResolvesStringModelsForFacadeCalls() async throws {
    let language = ResolutionLanguageModel()
    let embedding = ResolutionEmbeddingModel()
    let image = ResolutionImageModel()
    let registry = createProviderRegistry([
        "app": customProvider(
            languageModels: ["chat": language],
            embeddingModels: ["embed": embedding],
            imageModels: ["image": image]
        )
    ])

    let text = try await AIDefaultProvider.withProvider(registry) {
        try await AI.generateText(model: "app:chat", prompt: "Hi")
    }
    let embedded = try await AIDefaultProvider.withProvider(registry) {
        try await AI.embed(model: "app:embed", value: "value", dimensions: 3)
    }
    let generatedImage = try await AIDefaultProvider.withProvider(registry) {
        try await AI.generateImage(model: "app:image", prompt: "Draw", count: 2)
    }

    #expect(text.text == "resolved")
    #expect(embedded.embeddings == [[1, 2, 3]])
    #expect(generatedImage.urls == ["https://example.com/image.png"])
    #expect(language.requests.first?.messages == [.user("Hi")])
    #expect(embedding.requests.first?.values == ["value"])
    #expect(embedding.requests.first?.dimensions == 3)
    #expect(image.requests.first?.prompt == "Draw")
    #expect(image.requests.first?.count == 2)
    #expect(AIDefaultProvider.current() == nil)
}

@Test func aiStreamTextReturnsResolutionErrorsAsFailingStreams() async throws {
    let registry = createProviderRegistry([:])
    var iterator = AI.streamText(
        model: "missing:chat",
        provider: registry,
        prompt: "Hi"
    ).makeAsyncIterator()

    do {
        _ = try await iterator.next()
        Issue.record("Expected missing provider error.")
    } catch let error as AIProviderRegistryError {
        #expect(error == .noSuchProvider(providerID: "missing", modelType: "languageModel", availableProviders: []))
    }
}

private final class ResolutionLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "resolution"
    let modelID = "language"
    var requests: [LanguageModelRequest] = []

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        requests.append(request)
        return TextGenerationResult(text: "resolved", rawValue: .object([:]))
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        requests.append(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(.textDelta("resolved"))
            continuation.yield(.finish(reason: "stop", usage: nil))
            continuation.finish()
        }
    }
}

private final class ResolutionEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    let providerID = "resolution"
    let modelID = "embedding"
    var requests: [EmbeddingRequest] = []

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        requests.append(request)
        return EmbeddingResult(embeddings: [[1, 2, 3]], rawValue: .object([:]))
    }
}

private final class ResolutionImageModel: ImageModel, @unchecked Sendable {
    let providerID = "resolution"
    let modelID = "image"
    var requests: [ImageGenerationRequest] = []

    func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        requests.append(request)
        return ImageGenerationResult(urls: ["https://example.com/image.png"], rawValue: .object([:]))
    }
}
