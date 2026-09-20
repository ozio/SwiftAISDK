import Foundation

/// The published `@ai-sdk/zai` package version mirrored by this port.
public let zaiProviderVersion = "3.0.15"

/// Z.AI accepts the documented GLM identifiers as well as future model IDs.
public typealias ZAIChatModelID = String

/// Z.AI uses the standard SwiftAISDK provider settings surface. JavaScript's
/// custom `fetch` maps to ``ProviderSettings/transport``.
public typealias ZAIProviderSettings = ProviderSettings

/// Creates a Z.AI provider using the defaults from `@ai-sdk/zai`.
public func createZai(
    settings: ZAIProviderSettings = ZAIProviderSettings()
) -> ZAIProvider {
    ZAIProvider(settings: settings)
}

/// Swift acronym-cased alias for ``createZai(settings:)``.
public func createZAI(
    settings: ZAIProviderSettings = ZAIProviderSettings()
) -> ZAIProvider {
    createZai(settings: settings)
}

/// Default Z.AI provider, equivalent to upstream `zai`.
public let zai = createZai()

/// Z.AI GLM chat completions over the provider's OpenAI-compatible endpoint.
public final class ZAIProvider: AIProvider, @unchecked Sendable {
    public let providerID = "zai"
    public let supportedCapabilities: Set<ModelCapability> = [.language]

    private let config: ModelHTTPConfig
    private let resolveAPIKey: @Sendable () -> String?

    public init(settings: ZAIProviderSettings = ZAIProviderSettings()) {
        let headers = withUserAgentSuffix(
            settings.headers,
            "ai-sdk/zai/\(zaiProviderVersion)"
        )

        let explicitAPIKey = settings.apiKey
        let configuredEnvironment = settings.environment
        resolveAPIKey = {
            if let explicitAPIKey { return explicitAPIKey }
            if let configuredEnvironment { return configuredEnvironment["ZAI_API_KEY"] }
            return environmentValue(["ZAI_API_KEY"])
        }

        let callerTransform = settings.transformRequestBody
        config = ModelHTTPConfig(
            providerID: "zai.chat",
            baseURL: settings.baseURL ?? "https://api.z.ai/api/paas/v4",
            modelURL: settings.modelURL,
            headers: headers,
            transport: settings.transport,
            queryParams: settings.queryParams,
            supportsStructuredOutputs: false,
            maxEmbeddingsPerCall: settings.maxEmbeddingsPerCall,
            transformRequestBody: { body in
                let transformed = zaiTransformRequestBody(body)
                return callerTransform?(transformed) ?? transformed
            },
            usesGenericOpenAICompatibleProviderOptions: true,
            allowsEmptyTextResponse: true,
            failedResponseHandling: .openAICompatible
        )
    }

    public func languageModel(_ modelID: ZAIChatModelID) throws -> any LanguageModel {
        ZAILanguageModel(
            modelID: modelID,
            config: config,
            resolveAPIKey: resolveAPIKey
        )
    }

    public func chatModel(_ modelID: ZAIChatModelID) throws -> any LanguageModel {
        try languageModel(modelID)
    }

    public func callAsFunction(_ modelID: ZAIChatModelID) throws -> any LanguageModel {
        try languageModel(modelID)
    }

    public func chat(_ modelID: ZAIChatModelID) throws -> any LanguageModel {
        try languageModel(modelID)
    }

    public func embeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        throw AIError.unsupportedModel(
            provider: providerID,
            capability: .embedding,
            modelID: modelID
        )
    }

    public func imageModel(_ modelID: String) throws -> any ImageModel {
        throw AIError.unsupportedModel(
            provider: providerID,
            capability: .image,
            modelID: modelID
        )
    }

    public func transcriptionModel(_ modelID: String) throws -> any TranscriptionModel {
        throw AIError.unsupportedModel(
            provider: providerID,
            capability: .transcription,
            modelID: modelID
        )
    }

    public func speechModel(_ modelID: String) throws -> any SpeechModel {
        throw AIError.unsupportedModel(
            provider: providerID,
            capability: .speech,
            modelID: modelID
        )
    }

    public func videoModel(_ modelID: String) throws -> any VideoModel {
        throw AIError.unsupportedModel(
            provider: providerID,
            capability: .video,
            modelID: modelID
        )
    }

    public func rerankingModel(_ modelID: String) throws -> any RerankingModel {
        throw AIError.unsupportedModel(
            provider: providerID,
            capability: .reranking,
            modelID: modelID
        )
    }
}
