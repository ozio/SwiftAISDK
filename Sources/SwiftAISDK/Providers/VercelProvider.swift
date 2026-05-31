import Foundation

public final class VercelProvider: AIProvider, @unchecked Sendable {
    public let providerID = "vercel"
    public let supportedCapabilities: Set<ModelCapability> = [.language]
    private let chatProvider: OpenAICompatibleProvider

    public init(settings: ProviderSettings = ProviderSettings()) throws {
        let headers = try OpenAICompatibleProvider.buildHeaders(
            providerID: providerID,
            authorization: .bearer(environmentVariables: ["VERCEL_API_KEY"]),
            settings: settings
        )
        let config = ModelHTTPConfig(
            providerID: "vercel.chat",
            baseURL: settings.baseURL ?? "https://api.v0.dev/v1",
            headers: headers,
            transport: settings.transport,
            includeUsage: settings.includeUsage,
            queryParams: settings.queryParams,
            supportsStructuredOutputs: settings.supportsStructuredOutputs,
            maxEmbeddingsPerCall: settings.maxEmbeddingsPerCall,
            transformRequestBody: settings.transformRequestBody
        )
        chatProvider = OpenAICompatibleProvider(providerID: "vercel.chat", supportedCapabilities: [.language], config: config)
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        try chatProvider.chatModel(modelID)
    }

    public func chatModel(_ modelID: String) throws -> any LanguageModel {
        try languageModel(modelID)
    }

    public func embeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .embedding, modelID: modelID)
    }

    public func imageModel(_ modelID: String) throws -> any ImageModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .image, modelID: modelID)
    }

    public func transcriptionModel(_ modelID: String) throws -> any TranscriptionModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .transcription, modelID: modelID)
    }

    public func speechModel(_ modelID: String) throws -> any SpeechModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .speech, modelID: modelID)
    }

    public func videoModel(_ modelID: String) throws -> any VideoModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .video, modelID: modelID)
    }

    public func rerankingModel(_ modelID: String) throws -> any RerankingModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .reranking, modelID: modelID)
    }
}
