import Foundation

public final class GoogleGenerativeAIProvider: AIProvider, @unchecked Sendable {
    public let providerID = "google.generative-ai"
    public let supportedCapabilities: Set<ModelCapability> = [.language, .embedding, .image, .video]
    private let config: ModelHTTPConfig

    public init(settings: ProviderSettings = ProviderSettings()) throws {
        let headers = try OpenAICompatibleProvider.buildHeaders(
            providerID: providerID,
            authorization: .apiKeyHeader(name: "x-goog-api-key", environmentVariables: ["GOOGLE_GENERATIVE_AI_API_KEY", "GOOGLE_API_KEY", "GEMINI_API_KEY"]),
            settings: settings
        )
        config = ModelHTTPConfig(
            providerID: providerID,
            baseURL: settings.baseURL ?? "https://generativelanguage.googleapis.com/v1beta",
            headers: headers,
            transport: settings.transport,
            includeUsage: settings.includeUsage,
            queryParams: settings.queryParams,
            supportsStructuredOutputs: settings.supportsStructuredOutputs,
            transformRequestBody: settings.transformRequestBody
        )
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        GoogleGenerativeLanguageModel(modelID: modelID, config: config)
    }

    public func interactionsModel(_ modelID: String) -> any LanguageModel {
        GoogleInteractionsLanguageModel(modelID: modelID, agent: nil, config: config)
    }

    public func interactionsAgent(_ agentName: String) -> any LanguageModel {
        GoogleInteractionsLanguageModel(modelID: agentName, agent: agentName, config: config)
    }

    public func files() -> any AIFileClient {
        GoogleFileClient(providerID: config.providerID, config: config)
    }

    public func embeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        GoogleEmbeddingModel(modelID: modelID, config: config)
    }

    public func imageModel(_ modelID: String) throws -> any ImageModel {
        GoogleImageGenerationModel(modelID: modelID, config: config)
    }

    public func videoModel(_ modelID: String) throws -> any VideoModel {
        GoogleVideoGenerationModel(modelID: modelID, config: config)
    }

    public func transcriptionModel(_ modelID: String) throws -> any TranscriptionModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .transcription, modelID: modelID)
    }

    public func speechModel(_ modelID: String) throws -> any SpeechModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .speech, modelID: modelID)
    }

    public func rerankingModel(_ modelID: String) throws -> any RerankingModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .reranking, modelID: modelID)
    }
}
