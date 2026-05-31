import Foundation
import Testing
@testable import SwiftAISDK

@Test func wrapLanguageModelOverridesProviderAndModelIDs() throws {
    let model = MiddlewareLanguageModel(providerID: "base-provider", modelID: "base-model")
    let wrapped = wrapLanguageModel(
        model,
        middleware: AILanguageModelMiddleware(
            overrideProviderID: { _ in "middleware-provider" },
            overrideModelID: { _ in "middleware-model" }
        )
    )
    let explicit = wrapLanguageModel(
        model,
        middleware: AILanguageModelMiddleware(),
        modelID: "explicit-model",
        providerID: "explicit-provider"
    )

    #expect(wrapped.providerID == "middleware-provider")
    #expect(wrapped.modelID == "middleware-model")
    #expect(explicit.providerID == "explicit-provider")
    #expect(explicit.modelID == "explicit-model")
}

@Test func wrapLanguageModelTransformsGenerateAndStreamRequestsInOrder() async throws {
    let model = MiddlewareLanguageModel()
    let first = AILanguageModelMiddleware(transformRequest: { context in
        var request = context.request
        request.providerOptions["order"] = ["first": .string(context.type.rawValue)]
        return request
    })
    let second = AILanguageModelMiddleware(transformRequest: { context in
        var request = context.request
        var order = request.providerOptions["order"]?.objectValue ?? [:]
        order["second"] = .string(context.type.rawValue)
        request.providerOptions["order"] = .object(order)
        request.headers["x-second"] = context.model.modelID
        return request
    })
    let wrapped = wrapLanguageModel(model, middleware: [first, second])

    _ = try await wrapped.generate(LanguageModelRequest(messages: [.user("Generate")]))
    var streamed: [LanguageStreamPart] = []
    for try await part in wrapped.stream(LanguageModelRequest(messages: [.user("Stream")])) {
        streamed.append(part)
    }

    #expect(streamed == [.textDelta("stream"), .finish(reason: "stop", usage: nil)])
    #expect(model.generateRequests.count == 1)
    #expect(model.streamRequests.count == 1)
    #expect(model.generateRequests[0].providerOptions["order"]?["first"]?.stringValue == "generate")
    #expect(model.generateRequests[0].providerOptions["order"]?["second"]?.stringValue == "generate")
    #expect(model.streamRequests[0].providerOptions["order"]?["first"]?.stringValue == "stream")
    #expect(model.streamRequests[0].providerOptions["order"]?["second"]?.stringValue == "stream")
    #expect(model.generateRequests[0].headers["x-second"] == "middleware-model")
}

@Test func wrapLanguageModelWrapsGenerateAndStreamInUpstreamOrder() async throws {
    let model = MiddlewareLanguageModel(result: TextGenerationResult(text: "base", rawValue: .object([:])))
    let first = AILanguageModelMiddleware(
        wrapGenerate: { context in
            var result = try await context.doGenerate()
            result.text = "first(\(result.text))"
            return result
        },
        wrapStream: { context in
            AsyncThrowingStream { continuation in
                let task = Task {
                    continuation.yield(.textDelta("first("))
                    for try await part in context.doStream() {
                        continuation.yield(part)
                    }
                    continuation.yield(.textDelta(")"))
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    )
    let second = AILanguageModelMiddleware(
        wrapGenerate: { context in
            var result = try await context.doGenerate()
            result.text = "second(\(result.text))"
            return result
        },
        wrapStream: { context in
            AsyncThrowingStream { continuation in
                let task = Task {
                    continuation.yield(.textDelta("second("))
                    for try await part in context.doStream() {
                        continuation.yield(part)
                    }
                    continuation.yield(.textDelta(")"))
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    )
    let wrapped = wrapLanguageModel(model, middleware: [first, second])

    let generated = try await wrapped.generate(LanguageModelRequest(messages: [.user("Hi")]))
    var streamParts: [LanguageStreamPart] = []
    for try await part in wrapped.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        streamParts.append(part)
    }

    #expect(generated.text == "first(second(base))")
    #expect(streamParts == [
        .textDelta("first("),
        .textDelta("second("),
        .textDelta("stream"),
        .finish(reason: "stop", usage: nil),
        .textDelta(")"),
        .textDelta(")")
    ])
}

@Test func defaultSettingsMiddlewareAppliesDefaultsAndPreservesUserValues() async throws {
    let model = MiddlewareLanguageModel()
    let wrapped = wrapLanguageModel(
        model,
        middleware: defaultSettingsMiddleware(settings: AIDefaultLanguageModelSettings(
            temperature: 0.7,
            topP: 0.9,
            maxOutputTokens: 100,
            stopSequences: ["stop"],
            providerOptions: [
                "anthropic": [
                    "cacheControl": ["type": "ephemeral"],
                    "tools": [
                        "retrieval": ["enabled": true],
                        "math": ["enabled": true]
                    ]
                ],
                "openai": ["logitBias": ["50256": -100]]
            ],
            headers: ["X-Default": "default", "X-Override": "default"]
        ))
    )

    _ = try await wrapped.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        temperature: 0.2,
        providerOptions: [
            "anthropic": [
                "tools": [
                    "retrieval": ["enabled": false],
                    "code": ["enabled": true]
                ]
            ]
        ],
        headers: ["X-Override": "request"]
    ))

    let request = try #require(model.generateRequests.first)
    #expect(request.temperature == 0.2)
    #expect(request.topP == 0.9)
    #expect(request.maxOutputTokens == 100)
    #expect(request.stopSequences == ["stop"])
    #expect(request.providerOptions["anthropic"]?["cacheControl"]?["type"]?.stringValue == "ephemeral")
    #expect(request.providerOptions["anthropic"]?["tools"]?["retrieval"]?["enabled"]?.boolValue == false)
    #expect(request.providerOptions["anthropic"]?["tools"]?["math"]?["enabled"]?.boolValue == true)
    #expect(request.providerOptions["anthropic"]?["tools"]?["code"]?["enabled"]?.boolValue == true)
    #expect(request.providerOptions["openai"]?["logitBias"]?["50256"]?.intValue == -100)
    #expect(request.headers["X-Default"] == "default")
    #expect(request.headers["X-Override"] == "request")
}

@Test func wrapImageModelTransformsAndWrapsGenerateInUpstreamOrder() async throws {
    let model = MiddlewareImageModel(result: ImageGenerationResult(urls: ["base"], rawValue: .object([:])))
    let first = AIImageModelMiddleware(
        overrideProviderID: { _ in "image-provider" },
        overrideModelID: { _ in "image-model" },
        transformRequest: { context in
            var request = context.request
            request.prompt += "|first"
            request.headers["x-first"] = context.model.modelID
            return request
        },
        wrapGenerate: { context in
            var result = try await context.doGenerate()
            result.urls = result.urls.map { "first(\($0))" }
            return result
        }
    )
    let second = AIImageModelMiddleware(
        transformRequest: { context in
            var request = context.request
            request.prompt += "|second"
            request.providerOptions["second"] = .string(context.model.providerID)
            return request
        },
        wrapGenerate: { context in
            var result = try await context.doGenerate()
            result.urls = result.urls.map { "second(\($0))" }
            return result
        }
    )
    let wrapped = wrapImageModel(model, middleware: [first, second])

    let result = try await wrapped.generateImage(ImageGenerationRequest(prompt: "base"))

    #expect(wrapped.providerID == "image-provider")
    #expect(wrapped.modelID == "image-model")
    #expect(result.urls == ["first(second(base))"])
    #expect(model.requests.first?.prompt == "base|first|second")
    #expect(model.requests.first?.headers["x-first"] == "image")
    #expect(model.requests.first?.providerOptions["second"]?.stringValue == "middleware-image")
}

@Test func wrapEmbeddingModelTransformsAndWrapsEmbedInUpstreamOrder() async throws {
    let model = MiddlewareEmbeddingModel(result: EmbeddingResult(embeddings: [[1]], rawValue: .object([:])))
    let first = AIEmbeddingModelMiddleware(
        overrideProviderID: { _ in "embedding-provider" },
        overrideModelID: { _ in "embedding-model" },
        transformRequest: { context in
            var request = context.request
            request.values.append("first")
            request.headers["x-first"] = context.model.modelID
            return request
        },
        wrapEmbed: { context in
            var result = try await context.doEmbed()
            result.embeddings.append([3])
            return result
        }
    )
    let second = AIEmbeddingModelMiddleware(
        transformRequest: { context in
            var request = context.request
            request.values.append("second")
            request.providerOptions["second"] = .string(context.model.providerID)
            return request
        },
        wrapEmbed: { context in
            var result = try await context.doEmbed()
            result.embeddings.append([2])
            return result
        }
    )
    let wrapped = wrapEmbeddingModel(model, middleware: [first, second])

    let result = try await wrapped.embed(EmbeddingRequest(values: ["base"]))

    #expect(wrapped.providerID == "embedding-provider")
    #expect(wrapped.modelID == "embedding-model")
    #expect(result.embeddings == [[1], [2], [3]])
    #expect(model.requests.first?.values == ["base", "first", "second"])
    #expect(model.requests.first?.headers["x-first"] == "embedding")
    #expect(model.requests.first?.providerOptions["second"]?.stringValue == "middleware-embedding")
}

@Test func wrapProviderAppliesMiddlewareToLanguageImageAndEmbeddingModels() async throws {
    let language = MiddlewareLanguageModel()
    let embedding = MiddlewareEmbeddingModel()
    let image = MiddlewareImageModel()
    let provider = MiddlewareProvider(language: language, embedding: embedding, image: image)
    let wrapped = wrapProvider(
        provider,
        languageModelMiddleware: defaultSettingsMiddleware(settings: AIDefaultLanguageModelSettings(temperature: 0.4)),
        imageModelMiddleware: [
            AIImageModelMiddleware(transformRequest: { context in
                var request = context.request
                request.prompt += " with image middleware"
                return request
            })
        ],
        embeddingModelMiddleware: [
            AIEmbeddingModelMiddleware(transformRequest: { context in
                var request = context.request
                request.dimensions = 64
                return request
            })
        ]
    )

    _ = try await wrapped.languageModel("chat").generate(LanguageModelRequest(messages: [.user("Hi")]))
    _ = try await wrapped.embeddingModel("embed").embed(EmbeddingRequest(values: ["a"]))
    _ = try await wrapped.imageModel("image").generateImage(ImageGenerationRequest(prompt: "draw"))

    #expect(language.generateRequests.first?.temperature == 0.4)
    #expect(embedding.requests.first?.values == ["a"])
    #expect(embedding.requests.first?.dimensions == 64)
    #expect(image.requests.first?.prompt == "draw with image middleware")
}

@Test func providerRegistryAppliesLanguageMiddlewareToRoutedModels() async throws {
    let language = MiddlewareLanguageModel()
    let embedding = MiddlewareEmbeddingModel()
    let provider = MiddlewareProvider(language: language, embedding: embedding)
    let registry = createProviderRegistry(
        ["app": provider],
        languageModelMiddleware: defaultSettingsMiddleware(settings: AIDefaultLanguageModelSettings(
            temperature: 0.6,
            providerOptions: ["test": ["fromRegistry": true]]
        ))
    )

    _ = try await registry.languageModel("app:chat").generate(LanguageModelRequest(messages: [.user("Hi")]))
    _ = try await registry.embeddingModel("app:embed").embed(EmbeddingRequest(values: ["b"]))

    #expect(language.generateRequests.first?.temperature == 0.6)
    #expect(language.generateRequests.first?.providerOptions["test"]?["fromRegistry"]?.boolValue == true)
    #expect(embedding.requests.first?.values == ["b"])
}

@Test func providerRegistryAppliesMultipleLanguageMiddlewaresInOrder() async throws {
    let language = MiddlewareLanguageModel()
    let provider = MiddlewareProvider(language: language, embedding: MiddlewareEmbeddingModel())
    let registry = AIProviders.providerRegistry(
        ["app": provider],
        languageModelMiddleware: [
            AILanguageModelMiddleware(transformRequest: { context in
                var request = context.request
                request.headers["x-first"] = context.type.rawValue
                return request
            }),
            AILanguageModelMiddleware(transformRequest: { context in
                var request = context.request
                request.headers["x-second"] = context.request.headers["x-first"]
                return request
            })
        ]
    )

    _ = try await registry.languageModel("app:chat").generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(language.generateRequests.first?.headers["x-first"] == "generate")
    #expect(language.generateRequests.first?.headers["x-second"] == "generate")
}

@Test func providerRegistryAppliesImageMiddlewareToRoutedModels() async throws {
    let image = MiddlewareImageModel()
    let provider = MiddlewareProvider(
        language: MiddlewareLanguageModel(),
        embedding: MiddlewareEmbeddingModel(),
        image: image
    )
    let registry = createProviderRegistry(
        ["app": provider],
        imageModelMiddleware: AIImageModelMiddleware(transformRequest: { context in
            var request = context.request
            request.count = 2
            request.headers["x-image-model"] = context.model.modelID
            return request
        })
    )

    _ = try await registry.imageModel("app:image").generateImage(ImageGenerationRequest(prompt: "Hi"))

    #expect(image.requests.first?.count == 2)
    #expect(image.requests.first?.headers["x-image-model"] == "image")
}

private final class MiddlewareLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID: String
    let modelID: String
    var generateRequests: [LanguageModelRequest] = []
    var streamRequests: [LanguageModelRequest] = []
    private var result: TextGenerationResult

    init(
        providerID: String = "middleware-provider",
        modelID: String = "middleware-model",
        result: TextGenerationResult = TextGenerationResult(text: "generate", rawValue: .object([:]))
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.result = result
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        generateRequests.append(request)
        return result
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamRequests.append(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(.textDelta("stream"))
            continuation.yield(.finish(reason: "stop", usage: nil))
            continuation.finish()
        }
    }
}

private final class MiddlewareEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    let providerID: String
    let modelID: String
    var requests: [EmbeddingRequest] = []
    private let result: EmbeddingResult

    init(
        providerID: String = "middleware-embedding",
        modelID: String = "embedding",
        result: EmbeddingResult = EmbeddingResult(embeddings: [[1]], rawValue: .object([:]))
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.result = result
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        requests.append(request)
        return result
    }
}

private final class MiddlewareImageModel: ImageModel, @unchecked Sendable {
    let providerID: String
    let modelID: String
    var requests: [ImageGenerationRequest] = []
    private let result: ImageGenerationResult

    init(
        providerID: String = "middleware-image",
        modelID: String = "image",
        result: ImageGenerationResult = ImageGenerationResult(urls: ["image"], rawValue: .object([:]))
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.result = result
    }

    func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        requests.append(request)
        return result
    }
}

private final class MiddlewareProvider: AIProvider, @unchecked Sendable {
    let providerID = "middleware-provider"
    let supportedCapabilities: Set<ModelCapability> = [.language, .embedding, .image]
    private let language: MiddlewareLanguageModel
    private let embedding: MiddlewareEmbeddingModel
    private let image: MiddlewareImageModel

    init(
        language: MiddlewareLanguageModel,
        embedding: MiddlewareEmbeddingModel,
        image: MiddlewareImageModel = MiddlewareImageModel()
    ) {
        self.language = language
        self.embedding = embedding
        self.image = image
    }

    func languageModel(_ modelID: String) throws -> any LanguageModel {
        language
    }

    func embeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        embedding
    }

    func imageModel(_ modelID: String) throws -> any ImageModel {
        image
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
