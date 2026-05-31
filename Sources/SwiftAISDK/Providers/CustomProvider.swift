import Foundation

public final class AICustomProvider: AIFileProvider, AISkillsProvider, @unchecked Sendable {
    public let providerID: String
    public let supportedCapabilities: Set<ModelCapability>

    private let languageModels: [String: any LanguageModel]
    private let embeddingModels: [String: any EmbeddingModel]
    private let imageModels: [String: any ImageModel]
    private let transcriptionModels: [String: any TranscriptionModel]
    private let speechModels: [String: any SpeechModel]
    private let videoModels: [String: any VideoModel]
    private let rerankingModels: [String: any RerankingModel]
    private let filesClient: (any AIFileClient)?
    private let skillsClient: (any AISkillsClient)?
    private let fallbackProvider: (any AIProvider)?

    public init(
        providerID: String = "custom",
        languageModels: [String: any LanguageModel] = [:],
        embeddingModels: [String: any EmbeddingModel] = [:],
        imageModels: [String: any ImageModel] = [:],
        transcriptionModels: [String: any TranscriptionModel] = [:],
        speechModels: [String: any SpeechModel] = [:],
        videoModels: [String: any VideoModel] = [:],
        rerankingModels: [String: any RerankingModel] = [:],
        files: (any AIFileClient)? = nil,
        skills: (any AISkillsClient)? = nil,
        fallbackProvider: (any AIProvider)? = nil
    ) {
        self.providerID = providerID
        self.languageModels = languageModels
        self.embeddingModels = embeddingModels
        self.imageModels = imageModels
        self.transcriptionModels = transcriptionModels
        self.speechModels = speechModels
        self.videoModels = videoModels
        self.rerankingModels = rerankingModels
        self.filesClient = files
        self.skillsClient = skills
        self.fallbackProvider = fallbackProvider

        var capabilities = fallbackProvider?.supportedCapabilities ?? []
        if !languageModels.isEmpty { capabilities.insert(.language) }
        if !embeddingModels.isEmpty { capabilities.insert(.embedding) }
        if !imageModels.isEmpty { capabilities.insert(.image) }
        if !transcriptionModels.isEmpty { capabilities.insert(.transcription) }
        if !speechModels.isEmpty { capabilities.insert(.speech) }
        if !videoModels.isEmpty { capabilities.insert(.video) }
        if !rerankingModels.isEmpty { capabilities.insert(.reranking) }
        self.supportedCapabilities = capabilities
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        if let model = languageModels[modelID] {
            return model
        }
        if let fallbackProvider {
            return try fallbackProvider.languageModel(modelID)
        }
        throw AIError.unsupportedModel(provider: providerID, capability: .language, modelID: modelID)
    }

    public func embeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        if let model = embeddingModels[modelID] {
            return model
        }
        if let fallbackProvider {
            return try fallbackProvider.embeddingModel(modelID)
        }
        throw AIError.unsupportedModel(provider: providerID, capability: .embedding, modelID: modelID)
    }

    public func imageModel(_ modelID: String) throws -> any ImageModel {
        if let model = imageModels[modelID] {
            return model
        }
        if let fallbackProvider {
            return try fallbackProvider.imageModel(modelID)
        }
        throw AIError.unsupportedModel(provider: providerID, capability: .image, modelID: modelID)
    }

    public func transcriptionModel(_ modelID: String) throws -> any TranscriptionModel {
        if let model = transcriptionModels[modelID] {
            return model
        }
        if let fallbackProvider {
            return try fallbackProvider.transcriptionModel(modelID)
        }
        throw AIError.unsupportedModel(provider: providerID, capability: .transcription, modelID: modelID)
    }

    public func speechModel(_ modelID: String) throws -> any SpeechModel {
        if let model = speechModels[modelID] {
            return model
        }
        if let fallbackProvider {
            return try fallbackProvider.speechModel(modelID)
        }
        throw AIError.unsupportedModel(provider: providerID, capability: .speech, modelID: modelID)
    }

    public func videoModel(_ modelID: String) throws -> any VideoModel {
        if let model = videoModels[modelID] {
            return model
        }
        if let fallbackProvider {
            return try fallbackProvider.videoModel(modelID)
        }
        throw AIError.unsupportedModel(provider: providerID, capability: .video, modelID: modelID)
    }

    public func rerankingModel(_ modelID: String) throws -> any RerankingModel {
        if let model = rerankingModels[modelID] {
            return model
        }
        if let fallbackProvider {
            return try fallbackProvider.rerankingModel(modelID)
        }
        throw AIError.unsupportedModel(provider: providerID, capability: .reranking, modelID: modelID)
    }

    public func files() throws -> any AIFileClient {
        if let filesClient {
            return filesClient
        }
        if let fallback = fallbackProvider as? any AIFileProvider {
            return try fallback.files()
        }
        throw AIError.invalidArgument(argument: "files", message: "Provider '\(providerID)' does not support file uploads.")
    }

    public func skills() throws -> any AISkillsClient {
        if let skillsClient {
            return skillsClient
        }
        if let fallback = fallbackProvider as? any AISkillsProvider {
            return try fallback.skills()
        }
        throw AIError.invalidArgument(argument: "skills", message: "Provider '\(providerID)' does not support skills.")
    }
}

public func customProvider(
    providerID: String = "custom",
    languageModels: [String: any LanguageModel] = [:],
    embeddingModels: [String: any EmbeddingModel] = [:],
    imageModels: [String: any ImageModel] = [:],
    transcriptionModels: [String: any TranscriptionModel] = [:],
    speechModels: [String: any SpeechModel] = [:],
    videoModels: [String: any VideoModel] = [:],
    rerankingModels: [String: any RerankingModel] = [:],
    files: (any AIFileClient)? = nil,
    skills: (any AISkillsClient)? = nil,
    fallbackProvider: (any AIProvider)? = nil
) -> AICustomProvider {
    AICustomProvider(
        providerID: providerID,
        languageModels: languageModels,
        embeddingModels: embeddingModels,
        imageModels: imageModels,
        transcriptionModels: transcriptionModels,
        speechModels: speechModels,
        videoModels: videoModels,
        rerankingModels: rerankingModels,
        files: files,
        skills: skills,
        fallbackProvider: fallbackProvider
    )
}

extension AIProviders {
    public static func customProvider(
        providerID: String = "custom",
        languageModels: [String: any LanguageModel] = [:],
        embeddingModels: [String: any EmbeddingModel] = [:],
        imageModels: [String: any ImageModel] = [:],
        transcriptionModels: [String: any TranscriptionModel] = [:],
        speechModels: [String: any SpeechModel] = [:],
        videoModels: [String: any VideoModel] = [:],
        rerankingModels: [String: any RerankingModel] = [:],
        files: (any AIFileClient)? = nil,
        skills: (any AISkillsClient)? = nil,
        fallbackProvider: (any AIProvider)? = nil
    ) -> AICustomProvider {
        AICustomProvider(
            providerID: providerID,
            languageModels: languageModels,
            embeddingModels: embeddingModels,
            imageModels: imageModels,
            transcriptionModels: transcriptionModels,
            speechModels: speechModels,
            videoModels: videoModels,
            rerankingModels: rerankingModels,
            files: files,
            skills: skills,
            fallbackProvider: fallbackProvider
        )
    }
}

extension OpenAICompatibleProvider: AIFileProvider, AISkillsProvider {}
extension AnthropicProvider: AIFileProvider, AISkillsProvider {}
extension AnthropicAWSProvider: AIFileProvider, AISkillsProvider {}
extension GoogleGenerativeAIProvider: AIFileProvider {}
