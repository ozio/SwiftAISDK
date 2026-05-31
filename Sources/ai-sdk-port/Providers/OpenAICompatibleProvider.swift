import Foundation

public final class OpenAICompatibleProvider: AIProvider, @unchecked Sendable {
    public let providerID: String
    public let supportedCapabilities: Set<ModelCapability>
    private let config: ModelHTTPConfig

    public init(
        providerID: String,
        defaultBaseURL: String,
        authorization: AuthorizationStyle,
        supportedCapabilities: Set<ModelCapability> = [.language],
        settings: ProviderSettings = ProviderSettings()
    ) throws {
        self.providerID = providerID
        self.supportedCapabilities = supportedCapabilities
        let headers = try Self.buildHeaders(providerID: providerID, authorization: authorization, settings: settings)
        self.config = ModelHTTPConfig(
            providerID: providerID,
            baseURL: settings.baseURL ?? defaultBaseURL,
            headers: headers,
            transport: settings.transport,
            includeUsage: settings.includeUsage,
            queryParams: settings.queryParams,
            supportsStructuredOutputs: settings.supportsStructuredOutputs,
            maxEmbeddingsPerCall: settings.maxEmbeddingsPerCall,
            transformRequestBody: settings.transformRequestBody
        )
    }

    init(providerID: String, supportedCapabilities: Set<ModelCapability>, config: ModelHTTPConfig) {
        self.providerID = providerID
        self.supportedCapabilities = supportedCapabilities
        self.config = config
    }

    private func modelConfig(surface: String) -> ModelHTTPConfig {
        switch providerID {
        case "openai":
            return config.withProviderID("openai.\(surface)")
        case "azure":
            let suffix = surface == "embedding" ? "embeddings" : surface
            return config.withProviderID("azure.\(suffix)")
        default:
            return config
        }
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        guard supportedCapabilities.contains(.language) else {
            throw AIError.unsupportedModel(provider: providerID, capability: .language, modelID: modelID)
        }
        if providerID == "openai" {
            return OpenAICompatibleResponsesModel(modelID: modelID, config: modelConfig(surface: "responses"))
        }
        if providerID == "xai" {
            return OpenAICompatibleResponsesModel(modelID: modelID, config: config)
        }
        if providerID == "huggingface" {
            return HuggingFaceResponsesLanguageModel(modelID: modelID, config: config)
        }
        if providerID.hasSuffix(".responses") {
            return OpenAICompatibleResponsesModel(modelID: modelID, config: config)
        }
        if providerID == "perplexity" {
            return PerplexityLanguageModel(modelID: modelID, config: config)
        }
        if providerID == "groq" {
            return GroqLanguageModel(modelID: modelID, config: config)
        }
        if providerID == "deepseek" {
            return DeepSeekLanguageModel(modelID: modelID, config: config)
        }
        if providerID == "cerebras" {
            return CerebrasLanguageModel(modelID: modelID, config: config)
        }
        if providerID == "alibaba" {
            return AlibabaLanguageModel(modelID: modelID, config: config)
        }
        if providerID == "baseten", config.baseURL.contains("/predict") {
            throw AIError.unsupportedModel(provider: providerID, capability: .language, modelID: modelID)
        }
        if providerID == "mistral" {
            return MistralLanguageModel(modelID: modelID, config: config)
        }
        if providerID == "cohere" {
            return CohereLanguageModel(modelID: modelID, config: config)
        }
        if providerID == "prodia" {
            return ProdiaLanguageModel(modelID: modelID, config: config)
        }
        if providerID == "googleVertex.anthropic" {
            return AnthropicLanguageModel(
                modelID: modelID,
                config: ModelHTTPConfig(
                    providerID: "googleVertex.anthropic.messages",
                    baseURL: config.baseURL,
                    headers: config.headers,
                    transport: config.transport,
                    includeUsage: config.includeUsage,
                    queryParams: config.queryParams,
                    supportsStructuredOutputs: config.supportsStructuredOutputs,
                    maxEmbeddingsPerCall: config.maxEmbeddingsPerCall,
                    transformRequestBody: config.transformRequestBody
                )
            )
        }
        return OpenAICompatibleChatModel(modelID: modelID, config: modelConfig(surface: "chat"))
    }

    public func chatModel(_ modelID: String) throws -> any LanguageModel {
        guard supportedCapabilities.contains(.language) else {
            throw AIError.unsupportedModel(provider: providerID, capability: .language, modelID: modelID)
        }
        switch providerID {
        case "perplexity", "groq", "deepseek", "cerebras", "alibaba", "mistral", "cohere", "prodia":
            return try languageModel(modelID)
        default:
            break
        }
        return OpenAICompatibleChatModel(modelID: modelID, config: modelConfig(surface: "chat"))
    }

    public func chat(_ modelID: String) throws -> any LanguageModel {
        try chatModel(modelID)
    }

    public func completionModel(_ modelID: String) throws -> any LanguageModel {
        guard supportedCapabilities.contains(.completion) else {
            throw AIError.unsupportedModel(provider: providerID, capability: .completion, modelID: modelID)
        }
        return OpenAICompatibleCompletionModel(modelID: modelID, config: modelConfig(surface: "completion"))
    }

    public func completion(_ modelID: String) throws -> any LanguageModel {
        try completionModel(modelID)
    }

    public func responsesModel(_ modelID: String) throws -> any LanguageModel {
        guard supportedCapabilities.contains(.language) else {
            throw AIError.unsupportedModel(provider: providerID, capability: .language, modelID: modelID)
        }
        return OpenAICompatibleResponsesModel(modelID: modelID, config: modelConfig(surface: "responses"))
    }

    public func responses(_ modelID: String) throws -> any LanguageModel {
        try responsesModel(modelID)
    }

    public func embeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        guard supportedCapabilities.contains(.embedding) else {
            throw AIError.unsupportedModel(provider: providerID, capability: .embedding, modelID: modelID)
        }
        if providerID == "cohere" {
            return CohereEmbeddingModel(modelID: modelID, config: config)
        }
        if providerID == "baseten" {
            guard let basetenConfig = config.basetenEmbeddingConfig else {
                throw AIError.unsupportedModel(provider: providerID, capability: .embedding, modelID: modelID)
            }
            return BasetenEmbeddingModel(modelID: modelID, config: basetenConfig)
        }
        if providerID == "mistral" {
            return MistralEmbeddingModel(modelID: modelID, config: config)
        }
        if providerID == "voyage" {
            return VoyageEmbeddingModel(modelID: modelID, config: config)
        }
        return OpenAICompatibleEmbeddingModel(modelID: modelID, config: modelConfig(surface: "embedding"))
    }

    public func imageModel(_ modelID: String) throws -> any ImageModel {
        guard supportedCapabilities.contains(.image) else {
            throw AIError.unsupportedModel(provider: providerID, capability: .image, modelID: modelID)
        }
        if providerID == "replicate" {
            return ReplicateImageModel(modelID: modelID, config: config)
        }
        if providerID == "fireworks" {
            return FireworksImageModel(modelID: modelID, config: config)
        }
        if providerID == "deepinfra" {
            return DeepInfraImageModel(modelID: modelID, config: config)
        }
        if providerID == "xai" {
            return XAIImageModel(modelID: modelID, config: config)
        }
        if providerID == "fal" {
            return FalImageModel(modelID: modelID, config: config)
        }
        if providerID == "prodia" {
            return ProdiaImageModel(modelID: modelID, config: config)
        }
        if providerID == "togetherai" {
            return TogetherAIImageModel(modelID: modelID, config: config)
        }
        if providerID == "black-forest-labs" {
            return BlackForestLabsImageModel(modelID: modelID, config: config)
        }
        if providerID == "luma" {
            return LumaImageModel(modelID: modelID, config: config)
        }
        if providerID == "quiverai" {
            return QuiverAIImageModel(modelID: modelID, config: config)
        }
        return OpenAICompatibleImageModel(modelID: modelID, config: modelConfig(surface: "image"))
    }

    public func transcriptionModel(_ modelID: String) throws -> any TranscriptionModel {
        guard supportedCapabilities.contains(.transcription) else {
            throw AIError.unsupportedModel(provider: providerID, capability: .transcription, modelID: modelID)
        }
        if providerID == "deepgram" {
            return DeepgramTranscriptionModel(modelID: modelID, config: config)
        }
        if providerID == "groq" {
            return GroqTranscriptionModel(modelID: modelID, config: config)
        }
        if providerID == "fal" {
            return FalTranscriptionModel(modelID: modelID, config: config)
        }
        if providerID == "assemblyai" {
            return AssemblyAITranscriptionModel(modelID: modelID, config: config)
        }
        if providerID == "revai" {
            return RevAITranscriptionModel(modelID: modelID, config: config)
        }
        if providerID == "gladia" {
            return GladiaTranscriptionModel(modelID: modelID, config: config)
        }
        if providerID == "elevenlabs" {
            return ElevenLabsTranscriptionModel(modelID: modelID, config: config)
        }
        return OpenAICompatibleTranscriptionModel(modelID: modelID, config: modelConfig(surface: "transcription"))
    }

    public func speechModel(_ modelID: String) throws -> any SpeechModel {
        guard supportedCapabilities.contains(.speech) else {
            throw AIError.unsupportedModel(provider: providerID, capability: .speech, modelID: modelID)
        }
        if providerID == "deepgram" {
            return DeepgramSpeechModel(modelID: modelID, config: config)
        }
        if providerID == "fal" {
            return FalSpeechModel(modelID: modelID, config: config)
        }
        if providerID == "lmnt" {
            return LMNTSpeechModel(modelID: modelID, config: config)
        }
        if providerID == "hume" {
            return HumeSpeechModel(modelID: modelID, config: config)
        }
        if providerID == "elevenlabs" {
            return ElevenLabsSpeechModel(modelID: modelID, config: config)
        }
        return OpenAICompatibleSpeechModel(modelID: modelID, config: modelConfig(surface: "speech"))
    }

    public func videoModel(_ modelID: String) throws -> any VideoModel {
        guard supportedCapabilities.contains(.video) else {
            throw AIError.unsupportedModel(provider: providerID, capability: .video, modelID: modelID)
        }
        if providerID == "replicate" {
            return ReplicateVideoModel(modelID: modelID, config: config)
        }
        if providerID == "xai" {
            return XAIVideoModel(modelID: modelID, config: config)
        }
        if providerID == "fal" {
            return FalVideoModel(modelID: modelID, config: config)
        }
        if providerID == "klingai" {
            return KlingAIVideoModel(modelID: modelID, config: config)
        }
        if providerID == "bytedance" {
            return ByteDanceVideoModel(modelID: modelID, config: config)
        }
        if providerID == "alibaba" {
            return AlibabaVideoModel(modelID: modelID, config: config)
        }
        if providerID == "prodia" {
            return ProdiaVideoModel(modelID: modelID, config: config)
        }
        return JSONVideoModel(modelID: modelID, path: "/videos/generations", config: config)
    }

    public func rerankingModel(_ modelID: String) throws -> any RerankingModel {
        guard supportedCapabilities.contains(.reranking) else {
            throw AIError.unsupportedModel(provider: providerID, capability: .reranking, modelID: modelID)
        }
        if providerID == "cohere" {
            return CohereRerankingModel(modelID: modelID, config: config)
        }
        if providerID == "voyage" {
            return VoyageRerankingModel(modelID: modelID, config: config)
        }
        if providerID == "togetherai" {
            return TogetherAIRerankingModel(modelID: modelID, config: config)
        }
        return JSONRerankingModel(modelID: modelID, path: "/rerank", config: config)
    }

    public func files() -> any AIFileClient {
        MultipartFileClient(
            providerID: "\(providerID).files",
            providerReferenceKey: providerID == "xai" ? "xai" : providerID,
            config: config,
            includePurpose: providerID == "openai" || providerID == "xai"
        )
    }

    public func skills() throws -> any AISkillsClient {
        guard providerID == "openai" else {
            throw AIError.invalidArgument(argument: "providerID", message: "Skills upload is only supported by the OpenAI provider.")
        }
        return OpenAISkillsClient(providerID: "openai.skills", providerReferenceKey: "openai", config: config)
    }

    static func buildHeaders(providerID: String, authorization: AuthorizationStyle, settings: ProviderSettings) throws -> [String: String] {
        var headers = settings.headers
        switch authorization {
        case let .bearer(environmentVariables):
            let key = settings.apiKey ?? environmentValue(environmentVariables)
            guard let key else { throw AIError.missingAPIKey(provider: providerID, environmentVariables: environmentVariables) }
            headers["Authorization"] = headers["Authorization"] ?? "Bearer \(key)"
        case let .token(environmentVariables):
            let key = settings.apiKey ?? environmentValue(environmentVariables)
            guard let key else { throw AIError.missingAPIKey(provider: providerID, environmentVariables: environmentVariables) }
            headers["authorization"] = headers["authorization"] ?? "Token \(key)"
        case let .apiKeyHeader(name, prefix, environmentVariables):
            let key = settings.apiKey ?? environmentValue(environmentVariables)
            guard let key else { throw AIError.missingAPIKey(provider: providerID, environmentVariables: environmentVariables) }
            headers[name] = headers[name] ?? "\(prefix.map { "\($0) " } ?? "")\(key)"
        case .none:
            break
        }
        headers["user-agent"] = headers["user-agent"] ?? userAgent(providerID)
        return headers
    }
}

public final class AnthropicProvider: AIProvider, @unchecked Sendable {
    public let providerID = "anthropic"
    public let supportedCapabilities: Set<ModelCapability> = [.language]
    private let config: ModelHTTPConfig

    public init(settings: ProviderSettings = ProviderSettings()) throws {
        var headers = try OpenAICompatibleProvider.buildHeaders(
            providerID: providerID,
            authorization: .apiKeyHeader(name: "x-api-key", environmentVariables: ["ANTHROPIC_API_KEY"]),
            settings: settings
        )
        headers["anthropic-version"] = headers["anthropic-version"] ?? "2023-06-01"
        config = ModelHTTPConfig(
            providerID: providerID,
            baseURL: settings.baseURL ?? "https://api.anthropic.com/v1",
            headers: headers,
            transport: settings.transport,
            includeUsage: settings.includeUsage,
            queryParams: settings.queryParams,
            supportsStructuredOutputs: settings.supportsStructuredOutputs,
            transformRequestBody: settings.transformRequestBody
        )
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        AnthropicLanguageModel(modelID: modelID, config: config)
    }

    public func messages(_ modelID: String) throws -> any LanguageModel {
        try languageModel(modelID)
    }

    public func files() -> any AIFileClient {
        MultipartFileClient(
            providerID: "anthropic.files",
            providerReferenceKey: "anthropic",
            config: config,
            betaHeader: ("anthropic-beta", "files-api-2025-04-14")
        )
    }

    public func skills() -> any AISkillsClient {
        AnthropicSkillsClient(providerID: "anthropic.skills", config: config)
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
        GoogleFileClient(providerID: "google.files", config: config)
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

public final class AzureOpenAIProvider: AIProvider, @unchecked Sendable {
    public let providerID = "azure"
    public let supportedCapabilities: Set<ModelCapability> = [.language, .completion, .embedding, .image, .transcription, .speech]
    private let provider: OpenAICompatibleProvider

    public init(
        resourceName: String? = nil,
        apiVersion: String = "v1",
        useDeploymentBasedURLs: Bool = false,
        settings: ProviderSettings = ProviderSettings()
    ) throws {
        let resolvedResourceName = resourceName ?? ProcessInfo.processInfo.environment["AZURE_RESOURCE_NAME"]
        let basePrefix = settings.baseURL ?? resolvedResourceName.map { "https://\($0).openai.azure.com/openai" }
        guard let basePrefix else {
            throw AIError.invalidURL("Azure requires ProviderSettings.baseURL or AZURE_RESOURCE_NAME/resourceName.")
        }
        let headers = try OpenAICompatibleProvider.buildHeaders(
            providerID: providerID,
            authorization: .apiKeyHeader(name: "api-key", environmentVariables: ["AZURE_API_KEY"]),
            settings: settings
        )
        let baseURL = withoutTrailingSlash(basePrefix)
        let config = ModelHTTPConfig(providerID: providerID, baseURL: baseURL, headers: headers, transport: settings.transport, includeUsage: settings.includeUsage, queryParams: settings.queryParams, supportsStructuredOutputs: settings.supportsStructuredOutputs, maxEmbeddingsPerCall: settings.maxEmbeddingsPerCall, transformRequestBody: settings.transformRequestBody) { modelID, path in
            let urlString = useDeploymentBasedURLs
                ? "\(baseURL)/deployments/\(modelID)\(path)"
                : "\(baseURL)/v1\(path)"
            guard var components = URLComponents(string: urlString) else { throw AIError.invalidURL(urlString) }
            components.queryItems = [URLQueryItem(name: "api-version", value: apiVersion)]
            guard let url = components.url else { throw AIError.invalidURL(urlString) }
            return url
        }
        provider = OpenAICompatibleProvider(providerID: providerID, supportedCapabilities: supportedCapabilities, config: config)
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel { try provider.responsesModel(modelID) }
    public func chatModel(_ modelID: String) throws -> any LanguageModel { try provider.chatModel(modelID) }
    public func chat(_ modelID: String) throws -> any LanguageModel { try chatModel(modelID) }
    public func completionModel(_ modelID: String) throws -> any LanguageModel { try provider.completionModel(modelID) }
    public func completion(_ modelID: String) throws -> any LanguageModel { try completionModel(modelID) }
    public func responses(_ modelID: String) throws -> any LanguageModel { try languageModel(modelID) }
    public func embeddingModel(_ modelID: String) throws -> any EmbeddingModel { try provider.embeddingModel(modelID) }
    public func imageModel(_ modelID: String) throws -> any ImageModel { try provider.imageModel(modelID) }
    public func transcriptionModel(_ modelID: String) throws -> any TranscriptionModel { try provider.transcriptionModel(modelID) }
    public func speechModel(_ modelID: String) throws -> any SpeechModel { try provider.speechModel(modelID) }
    public func videoModel(_ modelID: String) throws -> any VideoModel { try provider.videoModel(modelID) }
    public func rerankingModel(_ modelID: String) throws -> any RerankingModel { try provider.rerankingModel(modelID) }
}
