import Foundation

public final class OpenAICompatibleProvider: AIProvider, @unchecked Sendable {
    public let providerID: String
    public let supportedCapabilities: Set<ModelCapability>
    private let config: ModelHTTPConfig
    private let routesLikeOpenAI: Bool
    private let usesOpenAICompatibleSurfaceIDs: Bool

    public init(
        providerID: String,
        defaultBaseURL: String,
        authorization: AuthorizationStyle,
        supportedCapabilities: Set<ModelCapability> = [.language],
        settings: ProviderSettings = ProviderSettings(),
        routesLikeOpenAI: Bool = false,
        userAgentSuffix: String? = nil,
        usesOpenAICompatibleSurfaceIDs: Bool = false
    ) throws {
        self.providerID = providerID
        self.supportedCapabilities = supportedCapabilities
        self.routesLikeOpenAI = routesLikeOpenAI
        self.usesOpenAICompatibleSurfaceIDs = usesOpenAICompatibleSurfaceIDs
        let headers = try Self.buildHeaders(providerID: providerID, authorization: authorization, settings: settings, userAgentSuffix: userAgentSuffix)
        let resolvedBaseURL = settings.baseURL ?? defaultBaseURL
        let deepInfraRoot = providerID == "deepinfra" ? deepInfraRootBaseURL(resolvedBaseURL) : nil
        let urlBuilder: (@Sendable (String, String) throws -> URL)?
        if let deepInfraRoot {
            urlBuilder = { _, path in
                try deepInfraOpenAIURL(root: deepInfraRoot, path: path, queryParams: settings.queryParams)
            }
        } else {
            urlBuilder = nil
        }
        self.config = ModelHTTPConfig(
            providerID: providerID,
            baseURL: deepInfraRoot ?? resolvedBaseURL,
            modelURL: settings.modelURL,
            headers: headers,
            transport: settings.transport,
            includeUsage: settings.includeUsage || providerID == "fireworks",
            queryParams: settings.queryParams,
            supportsStructuredOutputs: settings.supportsStructuredOutputs,
            maxEmbeddingsPerCall: settings.maxEmbeddingsPerCall,
            transformRequestBody: settings.transformRequestBody,
            openAIBackedProviderRoot: routesLikeOpenAI ? providerID : nil,
            usesGenericOpenAICompatibleProviderOptions: usesOpenAICompatibleSurfaceIDs,
            url: urlBuilder
        )
    }

    init(providerID: String, supportedCapabilities: Set<ModelCapability>, config: ModelHTTPConfig, routesLikeOpenAI: Bool = false) {
        self.providerID = providerID
        self.supportedCapabilities = supportedCapabilities
        self.config = config
        self.routesLikeOpenAI = routesLikeOpenAI
        self.usesOpenAICompatibleSurfaceIDs = false
    }

    private func modelConfig(surface: String) -> ModelHTTPConfig {
        if routesLikeOpenAI {
            return config.withProviderID("\(providerID).\(surface)")
        }
        if usesOpenAICompatibleSurfaceIDs {
            return config.withProviderID("\(providerID).\(surface)")
        }
        switch providerID {
        case "openai":
            return config.withProviderID("openai.\(surface)")
        case "azure":
            let suffix = surface == "embedding" ? "embeddings" : surface
            return config.withProviderID("azure.\(suffix)")
        case "xai":
            return config.withProviderID("xai.\(surface)")
        case "baseten", "deepinfra", "fireworks", "moonshotai", "togetherai":
            return config.withProviderID("\(providerID).\(surface)")
        default:
            return config
        }
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        guard supportedCapabilities.contains(.language) else {
            throw AIError.unsupportedModel(provider: providerID, capability: .language, modelID: modelID)
        }
        if routesLikeOpenAI || providerID == "openai" {
            return OpenAICompatibleResponsesModel(modelID: modelID, config: modelConfig(surface: "responses"))
        }
        if providerID == "xai" {
            return OpenAICompatibleResponsesModel(modelID: modelID, config: modelConfig(surface: "responses"))
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
            return DeepSeekLanguageModel(modelID: modelID, config: config.withProviderID("deepseek.chat"))
        }
        if providerID == "cerebras" {
            return CerebrasLanguageModel(modelID: modelID, config: config)
        }
        if providerID == "alibaba" {
            return AlibabaLanguageModel(modelID: modelID, config: config)
        }
        if providerID == "baseten" {
            return OpenAICompatibleChatModel(modelID: modelID, config: try basetenChatConfig(from: config))
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
        case "perplexity", "groq", "deepseek", "cerebras", "alibaba", "mistral", "cohere", "prodia", "baseten":
            return try languageModel(modelID)
        default:
            break
        }
        return OpenAICompatibleChatModel(modelID: modelID, config: modelConfig(surface: "chat"))
    }

    public func languageModel() throws -> any LanguageModel {
        guard providerID == "baseten" else {
            throw AIError.invalidArgument(argument: "modelID", message: "A model ID is required for \(providerID).")
        }
        return try languageModel(basetenDefaultChatModelID(config: config))
    }

    public func chatModel() throws -> any LanguageModel {
        guard providerID == "baseten" else {
            throw AIError.invalidArgument(argument: "modelID", message: "A model ID is required for \(providerID).")
        }
        return try chatModel(basetenDefaultChatModelID(config: config))
    }

    public func callAsFunction() throws -> any LanguageModel {
        try languageModel()
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
                throw basetenEmbeddingConfigurationError(modelURL: config.modelURL)
            }
            return BasetenEmbeddingModel(modelID: modelID, config: basetenConfig)
        }
        if providerID == "mistral" {
            return MistralEmbeddingModel(modelID: modelID, config: config)
        }
        if providerID == "voyage" {
            return VoyageEmbeddingModel(modelID: modelID, config: config)
        }
        if providerID == "alibaba" {
            return AlibabaEmbeddingModel(modelID: modelID, config: config)
        }
        return OpenAICompatibleEmbeddingModel(modelID: modelID, config: modelConfig(surface: "embedding"))
    }

    public func embeddingModel() throws -> any EmbeddingModel {
        guard providerID == "baseten" else {
            throw AIError.invalidArgument(argument: "modelID", message: "A model ID is required for \(providerID).")
        }
        return try embeddingModel("embeddings")
    }

    public func textEmbeddingModel() throws -> any EmbeddingModel {
        try embeddingModel()
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

    public func transcriptionModel() throws -> any TranscriptionModel {
        guard providerID == "gladia" else {
            throw AIError.invalidArgument(argument: "modelID", message: "A model ID is required for \(providerID).")
        }
        return try transcriptionModel("default")
    }

    public func transcription() throws -> any TranscriptionModel {
        try transcriptionModel()
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
            return HumeSpeechModel(modelID: "", config: config)
        }
        if providerID == "elevenlabs" {
            return ElevenLabsSpeechModel(modelID: modelID, config: config)
        }
        return OpenAICompatibleSpeechModel(modelID: modelID, config: modelConfig(surface: "speech"))
    }

    public func speechModel() throws -> any SpeechModel {
        guard providerID == "hume" else {
            throw AIError.invalidArgument(argument: "modelID", message: "A model ID is required for \(providerID).")
        }
        return try speechModel("")
    }

    public func speech() throws -> any SpeechModel {
        try speechModel()
    }

    public func musicModel(_ modelID: String = "music_v1") throws -> any AudioGenerationModel {
        guard providerID == "elevenlabs" else {
            throw AIError.unsupportedModel(provider: providerID, capability: .audioGeneration, modelID: modelID)
        }
        return ElevenLabsMusicModel(modelID: modelID, config: config)
    }

    public func music(_ modelID: String = "music_v1") throws -> any AudioGenerationModel {
        try musicModel(modelID)
    }

    public func soundEffectsModel(_ modelID: String = "eleven_text_to_sound_v2") throws -> any AudioGenerationModel {
        guard providerID == "elevenlabs" else {
            throw AIError.unsupportedModel(provider: providerID, capability: .audioGeneration, modelID: modelID)
        }
        return ElevenLabsSoundEffectsModel(modelID: modelID, config: config)
    }

    public func soundEffects(_ modelID: String = "eleven_text_to_sound_v2") throws -> any AudioGenerationModel {
        try soundEffectsModel(modelID)
    }

    public func voiceChangerModel(_ modelID: String = "eleven_multilingual_sts_v2") throws -> any AudioTransformationModel {
        guard providerID == "elevenlabs" else {
            throw AIError.unsupportedModel(provider: providerID, capability: .audioTransformation, modelID: modelID)
        }
        return ElevenLabsVoiceChangerModel(modelID: modelID, config: config)
    }

    public func voiceChanger(_ modelID: String = "eleven_multilingual_sts_v2") throws -> any AudioTransformationModel {
        try voiceChangerModel(modelID)
    }

    public func voiceIsolatorModel(_ modelID: String = "audio-isolation") throws -> any AudioTransformationModel {
        guard providerID == "elevenlabs" else {
            throw AIError.unsupportedModel(provider: providerID, capability: .audioTransformation, modelID: modelID)
        }
        return ElevenLabsVoiceIsolatorModel(modelID: modelID, config: config)
    }

    public func voiceIsolator(_ modelID: String = "audio-isolation") throws -> any AudioTransformationModel {
        try voiceIsolatorModel(modelID)
    }

    public func dubbing() throws -> ElevenLabsDubbingClient {
        guard providerID == "elevenlabs" else {
            throw AIError.unsupportedModel(provider: providerID, capability: .dubbing, modelID: "dubbing")
        }
        return ElevenLabsDubbingClient(config: config)
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
        if providerID == "xai" {
            return XAIFileClient(config: config.withProviderID("xai.files"))
        }
        return MultipartFileClient(
            providerID: "\(providerID).files",
            providerReferenceKey: providerID == "xai" ? "xai" : providerID,
            config: config,
            includePurpose: routesLikeOpenAI || providerID == "openai" || providerID == "xai"
        )
    }

    public func skills() throws -> any AISkillsClient {
        guard routesLikeOpenAI || providerID == "openai" else {
            throw AIError.invalidArgument(argument: "providerID", message: "Skills upload is only supported by the OpenAI provider.")
        }
        return OpenAISkillsClient(providerID: "\(providerID).skills", providerReferenceKey: providerID, config: config)
    }

    static func buildHeaders(providerID: String, authorization: AuthorizationStyle, settings: ProviderSettings, userAgentSuffix: String? = nil) throws -> [String: String] {
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
        if let userAgentSuffix {
            return withUserAgentSuffix(headers, userAgentSuffix)
        }
        if providerID == "anthropic" {
            return withUserAgentSuffix(headers, "ai-sdk/anthropic/4.0.8")
        }
        if providerID == "google.generative-ai" {
            return withUserAgentSuffix(headers, "ai-sdk/google/3.0.83")
        }
        if providerID == "moonshotai" {
            return withUserAgentSuffix(headers, "ai-sdk/moonshotai/2.0.26")
        }
        if providerID == "cerebras" {
            return withUserAgentSuffix(headers, "ai-sdk/cerebras/2.0.57")
        }
        if providerID == "deepseek" {
            return withUserAgentSuffix(headers, "ai-sdk/deepseek/2.0.39")
        }
        if providerID == "groq" {
            return withUserAgentSuffix(headers, "ai-sdk/groq/3.0.42")
        }
        if providerID == "mistral" {
            return withUserAgentSuffix(headers, "ai-sdk/mistral/3.0.40")
        }
        if providerID == "cohere" {
            return withUserAgentSuffix(headers, "ai-sdk/cohere/3.0.39")
        }
        if providerID == "elevenlabs" {
            return withUserAgentSuffix(headers, "ai-sdk/elevenlabs/2.0.36")
        }
        if providerID == "assemblyai" {
            return withUserAgentSuffix(headers, "ai-sdk/assemblyai/2.0.36")
        }
        if providerID == "deepgram" {
            return withUserAgentSuffix(headers, "ai-sdk/deepgram/2.0.36")
        }
        if providerID == "lmnt" {
            return withUserAgentSuffix(headers, "ai-sdk/lmnt/2.0.36")
        }
        if providerID == "hume" {
            return withUserAgentSuffix(headers, "ai-sdk/hume/2.0.36")
        }
        if providerID == "revai" {
            return withUserAgentSuffix(headers, "ai-sdk/revai/2.0.36")
        }
        if providerID == "gladia" {
            return withUserAgentSuffix(headers, "ai-sdk/gladia/2.0.36")
        }
        if providerID == "fal" {
            return withUserAgentSuffix(headers, "ai-sdk/fal/2.0.37")
        }
        if providerID == "bytedance" {
            return withUserAgentSuffix(headers, "ai-sdk/bytedance/1.0.18")
        }
        if providerID == "alibaba" {
            return withUserAgentSuffix(headers, "ai-sdk/alibaba/1.0.29")
        }
        if providerID == "luma" {
            return withUserAgentSuffix(headers, "ai-sdk/luma/2.0.36")
        }
        if providerID == "klingai" {
            return withUserAgentSuffix(headers, "ai-sdk/klingai/3.0.21")
        }
        if providerID == "replicate" {
            return withUserAgentSuffix(headers, "ai-sdk/replicate/2.0.36")
        }
        if providerID == "black-forest-labs" {
            return withUserAgentSuffix(headers, "ai-sdk/black-forest-labs/1.0.38")
        }
        if providerID == "prodia" {
            return withUserAgentSuffix(headers, "ai-sdk/prodia/1.0.35")
        }
        if providerID == "quiverai" {
            return withUserAgentSuffix(headers, "ai-sdk/quiverai/1.0.3")
        }
        if providerID == "togetherai" {
            return withUserAgentSuffix(headers, "ai-sdk/togetherai/2.0.56")
        }
        if providerID == "fireworks" {
            return withUserAgentSuffix(headers, "ai-sdk/fireworks/2.0.57")
        }
        if providerID == "deepinfra" {
            return withUserAgentSuffix(headers, "ai-sdk/deepinfra/2.0.55")
        }
        if providerID == "xai" {
            return withUserAgentSuffix(headers, "ai-sdk/xai/3.0.96")
        }
        headers["user-agent"] = headers["user-agent"] ?? userAgent(providerID)
        return headers
    }
}
