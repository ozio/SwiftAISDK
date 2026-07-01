import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiWrapLanguageModelPassesThroughSupportedURLsLikeUpstream() {
    let model = UpstreamWrapLanguageModel(
        supportedURLs: [
            "image/*": [AISupportedURLPattern { $0.hasPrefix("https://images.example.com/") }]
        ]
    )
    let wrapped = wrapLanguageModel(model, middleware: AILanguageModelMiddleware())

    #expect(wrapped.supportedURLs["image/*"]?.first?.test("https://images.example.com/cat.png") == true)
    #expect(wrapped.supportedURLs["image/*"]?.first?.test("https://other.example.com/cat.png") == false)
}

@Test func aiWrapLanguageModelModelAndProviderOverridesMatchUpstreamPrecedence() {
    let model = UpstreamWrapLanguageModel(providerID: "test-provider", modelID: "test-model")
    let middlewareWrapped = wrapLanguageModel(
        model,
        middleware: AILanguageModelMiddleware(
            overrideProviderID: { _ in "middleware-provider" },
            overrideModelID: { _ in "middleware-model" }
        )
    )
    let explicitWrapped = wrapLanguageModel(
        model,
        middleware: AILanguageModelMiddleware(
            overrideProviderID: { _ in "middleware-provider" },
            overrideModelID: { _ in "middleware-model" }
        ),
        modelID: "explicit-model",
        providerID: "explicit-provider"
    )

    #expect(middlewareWrapped.providerID == "middleware-provider")
    #expect(middlewareWrapped.modelID == "middleware-model")
    #expect(explicitWrapped.providerID == "explicit-provider")
    #expect(explicitWrapped.modelID == "explicit-model")
}

@Test func aiWrapModelMiddlewareArraysAreNotMutatedLikeUpstream() async throws {
    let languageMiddlewares = [
        AILanguageModelMiddleware(transformRequest: { context in
            var request = context.request
            request.headers["x-first"] = context.type.rawValue
            return request
        }),
        AILanguageModelMiddleware(transformRequest: { context in
            var request = context.request
            request.headers["x-second"] = context.type.rawValue
            return request
        })
    ]
    let imageMiddlewares = [
        AIImageModelMiddleware(transformRequest: { context in
            var request = context.request
            request.headers["x-first"] = context.model.modelID
            return request
        }),
        AIImageModelMiddleware(transformRequest: { context in
            var request = context.request
            request.headers["x-second"] = context.model.modelID
            return request
        })
    ]
    let embeddingMiddlewares = [
        AIEmbeddingModelMiddleware(transformRequest: { context in
            var request = context.request
            request.headers["x-first"] = context.model.modelID
            return request
        }),
        AIEmbeddingModelMiddleware(transformRequest: { context in
            var request = context.request
            request.headers["x-second"] = context.model.modelID
            return request
        })
    ]

    _ = wrapLanguageModel(UpstreamWrapLanguageModel(), middleware: languageMiddlewares)
    _ = wrapImageModel(UpstreamWrapImageModel(), middleware: imageMiddlewares)
    _ = wrapEmbeddingModel(UpstreamWrapEmbeddingModel(), middleware: embeddingMiddlewares)

    #expect(languageMiddlewares.count == 2)
    #expect(imageMiddlewares.count == 2)
    #expect(embeddingMiddlewares.count == 2)
}

@Test func aiWrapProviderWrapsEveryRequestedModelFamilyLikeUpstream() async throws {
    let language1 = UpstreamWrapLanguageModel(modelID: "language-1")
    let language2 = UpstreamWrapLanguageModel(modelID: "language-2")
    let image1 = UpstreamWrapImageModel(modelID: "image-1")
    let image2 = UpstreamWrapImageModel(modelID: "image-2")
    let embedding1 = UpstreamWrapEmbeddingModel(modelID: "embedding-1")
    let embedding2 = UpstreamWrapEmbeddingModel(modelID: "embedding-2")
    let provider = UpstreamWrapProvider(
        languageModels: ["language-1": language1, "language-2": language2],
        imageModels: ["image-1": image1, "image-2": image2],
        embeddingModels: ["embedding-1": embedding1, "embedding-2": embedding2]
    )
    let wrapped = wrapProvider(
        provider,
        languageModelMiddleware: [AILanguageModelMiddleware(overrideModelID: { "wrapped-\($0.modelID)" })],
        imageModelMiddleware: [AIImageModelMiddleware(overrideModelID: { "wrapped-\($0.modelID)" })],
        embeddingModelMiddleware: [AIEmbeddingModelMiddleware(overrideModelID: { "wrapped-\($0.modelID)" })]
    )

    #expect(try wrapped.languageModel("language-1").modelID == "wrapped-language-1")
    #expect(try wrapped.languageModel("language-2").modelID == "wrapped-language-2")
    #expect(try wrapped.imageModel("image-1").modelID == "wrapped-image-1")
    #expect(try wrapped.imageModel("image-2").modelID == "wrapped-image-2")
    #expect(try wrapped.embeddingModel("embedding-1").modelID == "wrapped-embedding-1")
    #expect(try wrapped.embeddingModel("embedding-2").modelID == "wrapped-embedding-2")
}

private final class UpstreamWrapLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID: String
    let modelID: String
    let supportedURLs: [String: [AISupportedURLPattern]]

    init(
        providerID: String = "test-provider",
        modelID: String = "test-model",
        supportedURLs: [String: [AISupportedURLPattern]] = [:]
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.supportedURLs = supportedURLs
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        TextGenerationResult(text: "ok", rawValue: .object([:]))
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.finish(reason: "stop", usage: nil))
            continuation.finish()
        }
    }
}

private final class UpstreamWrapImageModel: ImageModel, @unchecked Sendable {
    let providerID: String
    let modelID: String

    init(providerID: String = "test-provider", modelID: String = "test-model") {
        self.providerID = providerID
        self.modelID = modelID
    }

    func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        ImageGenerationResult(urls: ["ok"], rawValue: .object([:]))
    }
}

private final class UpstreamWrapEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    let providerID: String
    let modelID: String

    init(providerID: String = "test-provider", modelID: String = "test-model") {
        self.providerID = providerID
        self.modelID = modelID
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        EmbeddingResult(embeddings: [[1]], rawValue: .object([:]))
    }
}

private final class UpstreamWrapProvider: AIProvider, @unchecked Sendable {
    let providerID = "test-provider"
    let supportedCapabilities: Set<ModelCapability> = [.language, .image, .embedding]
    private let languageModels: [String: UpstreamWrapLanguageModel]
    private let imageModels: [String: UpstreamWrapImageModel]
    private let embeddingModels: [String: UpstreamWrapEmbeddingModel]

    init(
        languageModels: [String: UpstreamWrapLanguageModel],
        imageModels: [String: UpstreamWrapImageModel],
        embeddingModels: [String: UpstreamWrapEmbeddingModel]
    ) {
        self.languageModels = languageModels
        self.imageModels = imageModels
        self.embeddingModels = embeddingModels
    }

    func languageModel(_ modelID: String) throws -> any LanguageModel {
        guard let model = languageModels[modelID] else {
            throw AIError.unsupportedModel(provider: providerID, capability: .language, modelID: modelID)
        }
        return model
    }

    func embeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        guard let model = embeddingModels[modelID] else {
            throw AIError.unsupportedModel(provider: providerID, capability: .embedding, modelID: modelID)
        }
        return model
    }

    func imageModel(_ modelID: String) throws -> any ImageModel {
        guard let model = imageModels[modelID] else {
            throw AIError.unsupportedModel(provider: providerID, capability: .image, modelID: modelID)
        }
        return model
    }

    func transcriptionModel(_ modelID: String) throws -> any TranscriptionModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .transcription, modelID: modelID)
    }

    func speechModel(_ modelID: String) throws -> any SpeechModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .speech, modelID: modelID)
    }

    func videoModel(_ modelID: String) throws -> any VideoModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .video, modelID: modelID)
    }

    func rerankingModel(_ modelID: String) throws -> any RerankingModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .reranking, modelID: modelID)
    }
}
