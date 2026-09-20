import Foundation

/// The published `@ai-sdk/typesafe-ai` package version mirrored by this port.
public let typeSafeAIProviderVersion = "3.0.4"

/// Creates a TypeSafe AI provider using the same defaults as
/// `createTypeSafeAi` from `@ai-sdk/typesafe-ai`.
///
/// Authentication is resolved lazily when an evaluation is performed, matching
/// upstream and allowing an environment key to be installed after the provider
/// or model is created.
public func createTypeSafeAI(
    settings: ProviderSettings = ProviderSettings()
) -> TypeSafeAIProvider {
    TypeSafeAIProvider(settings: settings)
}

/// Exact-casing alias for upstream `createTypeSafeAi`.
public func createTypeSafeAi(
    settings: ProviderSettings = ProviderSettings()
) -> TypeSafeAIProvider {
    createTypeSafeAI(settings: settings)
}

/// The default TypeSafe AI provider, equivalent to upstream `typeSafeAi`.
public let typeSafeAI = TypeSafeAIProvider()

/// Exact-casing alias for upstream `typeSafeAi`.
public let typeSafeAi = typeSafeAI

/// TypeSafe AI's evaluation-only Provider V4 surface.
public final class TypeSafeAIProvider: AIProvider, AIEvaluationProvider, @unchecked Sendable {
    public let providerID = "typesafe"
    public let supportedCapabilities: Set<ModelCapability> = [.evaluation]

    private let configuration: TypeSafeAIEvaluationModelConfiguration

    public init(settings: ProviderSettings = ProviderSettings()) {
        configuration = TypeSafeAIEvaluationModelConfiguration(
            providerID: "typesafe.evaluation",
            baseURL: withoutTrailingSlash(settings.baseURL ?? "https://api.typesafe.ai/v1"),
            apiKey: settings.apiKey,
            headers: settings.headers,
            environment: settings.environment,
            transport: settings.transport
        )
    }

    public func evaluationModel(_ modelID: String) throws -> any AIEvaluationModelV4 {
        TypeSafeAIEvaluationModel(modelID: modelID, configuration: configuration)
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        throw unsupported(.language, modelID: modelID)
    }

    public func embeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        throw unsupported(.embedding, modelID: modelID)
    }

    public func imageModel(_ modelID: String) throws -> any ImageModel {
        throw unsupported(.image, modelID: modelID)
    }

    public func transcriptionModel(_ modelID: String) throws -> any TranscriptionModel {
        throw unsupported(.transcription, modelID: modelID)
    }

    public func speechModel(_ modelID: String) throws -> any SpeechModel {
        throw unsupported(.speech, modelID: modelID)
    }

    public func videoModel(_ modelID: String) throws -> any VideoModel {
        throw unsupported(.video, modelID: modelID)
    }

    public func rerankingModel(_ modelID: String) throws -> any RerankingModel {
        throw unsupported(.reranking, modelID: modelID)
    }

    private func unsupported(_ capability: ModelCapability, modelID: String) -> AIError {
        .unsupportedModel(provider: providerID, capability: capability, modelID: modelID)
    }
}
