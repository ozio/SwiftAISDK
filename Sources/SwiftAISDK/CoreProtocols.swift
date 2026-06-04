import Foundation

public protocol LanguageModel: Sendable {
    var providerID: String { get }
    var modelID: String { get }
    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult
    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error>
}

public extension LanguageModel {
    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await generate(request)
                    if !result.text.isEmpty {
                        continuation.yield(.textDelta(result.text))
                    }
                    for toolCall in result.toolCalls {
                        continuation.yield(.toolCall(toolCall))
                    }
                    continuation.yield(.finish(reason: result.finishReason, usage: result.usage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

public protocol EmbeddingModel: Sendable {
    var providerID: String { get }
    var modelID: String { get }
    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult
}

public protocol ImageModel: Sendable {
    var providerID: String { get }
    var modelID: String { get }
    func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult
}

public protocol TranscriptionModel: Sendable {
    var providerID: String { get }
    var modelID: String { get }
    func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult
}

public protocol SpeechModel: Sendable {
    var providerID: String { get }
    var modelID: String { get }
    func speak(_ request: SpeechRequest) async throws -> SpeechResult
}

public protocol AudioGenerationModel: Sendable {
    var providerID: String { get }
    var modelID: String { get }
    func generateAudio(_ request: AudioGenerationRequest) async throws -> AudioGenerationResult
}

public protocol AudioTransformationModel: Sendable {
    var providerID: String { get }
    var modelID: String { get }
    func transformAudio(_ request: AudioTransformationRequest) async throws -> AudioTransformationResult
}

public protocol VideoModel: Sendable {
    var providerID: String { get }
    var modelID: String { get }
    func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult
}

public protocol RerankingModel: Sendable {
    var providerID: String { get }
    var modelID: String { get }
    func rerank(_ request: RerankingRequest) async throws -> RerankingResult
}

public protocol AIFileClient: Sendable {
    var providerID: String { get }
    func uploadFile(_ request: FileUploadRequest) async throws -> FileUploadResult
}

public protocol AISkillsClient: Sendable {
    var providerID: String { get }
    func uploadSkill(_ request: SkillUploadRequest) async throws -> SkillUploadResult
}

public protocol AIProvider: Sendable {
    var providerID: String { get }
    var supportedCapabilities: Set<ModelCapability> { get }
    func languageModel(_ modelID: String) throws -> any LanguageModel
    func embeddingModel(_ modelID: String) throws -> any EmbeddingModel
    func imageModel(_ modelID: String) throws -> any ImageModel
    func transcriptionModel(_ modelID: String) throws -> any TranscriptionModel
    func speechModel(_ modelID: String) throws -> any SpeechModel
    func videoModel(_ modelID: String) throws -> any VideoModel
    func rerankingModel(_ modelID: String) throws -> any RerankingModel
}

public protocol AIFileProvider: AIProvider {
    func files() throws -> any AIFileClient
}

public protocol AISkillsProvider: AIProvider {
    func skills() throws -> any AISkillsClient
}

public extension AIProvider {
    func callAsFunction(_ modelID: String) throws -> any LanguageModel {
        try languageModel(modelID)
    }

    func chat(_ modelID: String) throws -> any LanguageModel {
        try languageModel(modelID)
    }

    func embedding(_ modelID: String) throws -> any EmbeddingModel {
        try embeddingModel(modelID)
    }

    func textEmbeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        try embeddingModel(modelID)
    }

    func textEmbedding(_ modelID: String) throws -> any EmbeddingModel {
        try embeddingModel(modelID)
    }

    func image(_ modelID: String) throws -> any ImageModel {
        try imageModel(modelID)
    }

    func transcription(_ modelID: String) throws -> any TranscriptionModel {
        try transcriptionModel(modelID)
    }

    func speech(_ modelID: String) throws -> any SpeechModel {
        try speechModel(modelID)
    }

    func video(_ modelID: String) throws -> any VideoModel {
        try videoModel(modelID)
    }

    func reranking(_ modelID: String) throws -> any RerankingModel {
        try rerankingModel(modelID)
    }
}
