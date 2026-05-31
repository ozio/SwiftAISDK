import Foundation
import Testing
@testable import SwiftAISDK

@Test func customProviderReturnsConfiguredModelsAndClients() async throws {
    let language = CustomLanguageModel(modelID: "local-language")
    let embedding = CustomEmbeddingModel(modelID: "local-embedding")
    let image = CustomImageModel(modelID: "local-image")
    let transcription = CustomTranscriptionModel(modelID: "local-transcription")
    let speech = CustomSpeechModel(modelID: "local-speech")
    let video = CustomVideoModel(modelID: "local-video")
    let reranking = CustomRerankingModel(modelID: "local-reranking")
    let files = CustomFileClient()
    let skills = CustomSkillsClient()

    let provider = customProvider(
        providerID: "app",
        languageModels: ["chat": language],
        embeddingModels: ["embed": embedding],
        imageModels: ["image": image],
        transcriptionModels: ["transcribe": transcription],
        speechModels: ["speech": speech],
        videoModels: ["video": video],
        rerankingModels: ["rank": reranking],
        files: files,
        skills: skills
    )

    #expect(provider.providerID == "app")
    #expect(provider.supportedCapabilities == customProviderModelCapabilities)
    #expect((try provider.languageModel("chat") as? CustomLanguageModel)?.modelID == "local-language")
    #expect((try provider.embeddingModel("embed") as? CustomEmbeddingModel)?.modelID == "local-embedding")
    #expect((try provider.imageModel("image") as? CustomImageModel)?.modelID == "local-image")
    #expect((try provider.transcriptionModel("transcribe") as? CustomTranscriptionModel)?.modelID == "local-transcription")
    #expect((try provider.speechModel("speech") as? CustomSpeechModel)?.modelID == "local-speech")
    #expect((try provider.videoModel("video") as? CustomVideoModel)?.modelID == "local-video")
    #expect((try provider.rerankingModel("rank") as? CustomRerankingModel)?.modelID == "local-reranking")

    let fileResult = try await AI.uploadFile(client: try provider.files(), request: FileUploadRequest(data: Data("file".utf8), mediaType: "text/plain"))
    let skillResult = try await AI.uploadSkill(client: try provider.skills(), request: SkillUploadRequest(files: [SkillUploadFile(path: "skill.md", data: Data("skill".utf8))]))
    #expect(fileResult.providerReference["file"] == "custom-file")
    #expect(skillResult.providerReference["skill"] == "custom-skill")
}

@Test func customProviderUsesFallbackProviderForMissingModelsAndClients() async throws {
    let fallback = CustomFallbackProvider(
        language: CustomLanguageModel(modelID: "fallback-language"),
        embedding: CustomEmbeddingModel(modelID: "fallback-embedding"),
        image: CustomImageModel(modelID: "fallback-image"),
        transcription: CustomTranscriptionModel(modelID: "fallback-transcription"),
        speech: CustomSpeechModel(modelID: "fallback-speech"),
        video: CustomVideoModel(modelID: "fallback-video"),
        reranking: CustomRerankingModel(modelID: "fallback-reranking"),
        files: CustomFileClient(providerID: "fallback.files"),
        skills: CustomSkillsClient(providerID: "fallback.skills")
    )
    let provider = AIProviders.customProvider(fallbackProvider: fallback)

    #expect(provider.supportedCapabilities == customProviderModelCapabilities)
    #expect((try provider.languageModel("chat") as? CustomLanguageModel)?.modelID == "fallback-language")
    #expect((try provider.embeddingModel("embed") as? CustomEmbeddingModel)?.modelID == "fallback-embedding")
    #expect((try provider.imageModel("image") as? CustomImageModel)?.modelID == "fallback-image")
    #expect((try provider.transcriptionModel("transcribe") as? CustomTranscriptionModel)?.modelID == "fallback-transcription")
    #expect((try provider.speechModel("speech") as? CustomSpeechModel)?.modelID == "fallback-speech")
    #expect((try provider.videoModel("video") as? CustomVideoModel)?.modelID == "fallback-video")
    #expect((try provider.rerankingModel("rank") as? CustomRerankingModel)?.modelID == "fallback-reranking")

    #expect((try provider.files()).providerID == "fallback.files")
    #expect((try provider.skills()).providerID == "fallback.skills")
}

@Test func customProviderPrefersLocalModelsOverFallback() throws {
    let provider = customProvider(
        languageModels: ["chat": CustomLanguageModel(modelID: "local")],
        fallbackProvider: CustomFallbackProvider(language: CustomLanguageModel(modelID: "fallback"))
    )

    #expect((try provider.languageModel("chat") as? CustomLanguageModel)?.modelID == "local")
    #expect((try provider.languageModel("other") as? CustomLanguageModel)?.modelID == "fallback")
}

@Test func customProviderThrowsWhenModelAndFallbackAreMissing() throws {
    let provider = customProvider(providerID: "app")

    #expect(throws: AIError.unsupportedModel(provider: "app", capability: .language, modelID: "missing")) {
        _ = try provider.languageModel("missing")
    }
    #expect(throws: AIError.invalidArgument(argument: "files", message: "Provider 'app' does not support file uploads.")) {
        _ = try provider.files()
    }
    #expect(throws: AIError.invalidArgument(argument: "skills", message: "Provider 'app' does not support skills.")) {
        _ = try provider.skills()
    }
}

private final class CustomFallbackProvider: AIFileProvider, AISkillsProvider, @unchecked Sendable {
    let providerID = "fallback"
    let supportedCapabilities: Set<ModelCapability>
    private let language: (any LanguageModel)?
    private let embedding: (any EmbeddingModel)?
    private let image: (any ImageModel)?
    private let transcription: (any TranscriptionModel)?
    private let speech: (any SpeechModel)?
    private let video: (any VideoModel)?
    private let reranking: (any RerankingModel)?
    private let filesClient: (any AIFileClient)?
    private let skillsClient: (any AISkillsClient)?

    init(
        language: (any LanguageModel)? = nil,
        embedding: (any EmbeddingModel)? = nil,
        image: (any ImageModel)? = nil,
        transcription: (any TranscriptionModel)? = nil,
        speech: (any SpeechModel)? = nil,
        video: (any VideoModel)? = nil,
        reranking: (any RerankingModel)? = nil,
        files: (any AIFileClient)? = nil,
        skills: (any AISkillsClient)? = nil
    ) {
        self.language = language
        self.embedding = embedding
        self.image = image
        self.transcription = transcription
        self.speech = speech
        self.video = video
        self.reranking = reranking
        self.filesClient = files
        self.skillsClient = skills
        var capabilities: Set<ModelCapability> = []
        if language != nil { capabilities.insert(.language) }
        if embedding != nil { capabilities.insert(.embedding) }
        if image != nil { capabilities.insert(.image) }
        if transcription != nil { capabilities.insert(.transcription) }
        if speech != nil { capabilities.insert(.speech) }
        if video != nil { capabilities.insert(.video) }
        if reranking != nil { capabilities.insert(.reranking) }
        self.supportedCapabilities = capabilities
    }

    func languageModel(_ modelID: String) throws -> any LanguageModel {
        guard let language else { throw AIError.unsupportedModel(provider: providerID, capability: .language, modelID: modelID) }
        return language
    }

    func embeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        guard let embedding else { throw AIError.unsupportedModel(provider: providerID, capability: .embedding, modelID: modelID) }
        return embedding
    }

    func imageModel(_ modelID: String) throws -> any ImageModel {
        guard let image else { throw AIError.unsupportedModel(provider: providerID, capability: .image, modelID: modelID) }
        return image
    }

    func transcriptionModel(_ modelID: String) throws -> any TranscriptionModel {
        guard let transcription else { throw AIError.unsupportedModel(provider: providerID, capability: .transcription, modelID: modelID) }
        return transcription
    }

    func speechModel(_ modelID: String) throws -> any SpeechModel {
        guard let speech else { throw AIError.unsupportedModel(provider: providerID, capability: .speech, modelID: modelID) }
        return speech
    }

    func videoModel(_ modelID: String) throws -> any VideoModel {
        guard let video else { throw AIError.unsupportedModel(provider: providerID, capability: .video, modelID: modelID) }
        return video
    }

    func rerankingModel(_ modelID: String) throws -> any RerankingModel {
        guard let reranking else { throw AIError.unsupportedModel(provider: providerID, capability: .reranking, modelID: modelID) }
        return reranking
    }

    func files() throws -> any AIFileClient {
        guard let filesClient else { throw AIError.invalidArgument(argument: "files", message: "fallback has no files client.") }
        return filesClient
    }

    func skills() throws -> any AISkillsClient {
        guard let skillsClient else { throw AIError.invalidArgument(argument: "skills", message: "fallback has no skills client.") }
        return skillsClient
    }
}

private final class CustomLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "custom"
    let modelID: String

    init(modelID: String) {
        self.modelID = modelID
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        TextGenerationResult(text: modelID, rawValue: .object([:]))
    }
}

private final class CustomEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    let providerID = "custom"
    let modelID: String

    init(modelID: String) {
        self.modelID = modelID
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        EmbeddingResult(embeddings: [[1]], rawValue: .object([:]))
    }
}

private final class CustomImageModel: ImageModel, @unchecked Sendable {
    let providerID = "custom"
    let modelID: String

    init(modelID: String) {
        self.modelID = modelID
    }

    func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        ImageGenerationResult(urls: [], base64Images: [Data("image".utf8).base64EncodedString()], rawValue: .object([:]))
    }
}

private final class CustomTranscriptionModel: TranscriptionModel, @unchecked Sendable {
    let providerID = "custom"
    let modelID: String

    init(modelID: String) {
        self.modelID = modelID
    }

    func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        TranscriptionResult(text: modelID, rawValue: .object([:]))
    }
}

private final class CustomSpeechModel: SpeechModel, @unchecked Sendable {
    let providerID = "custom"
    let modelID: String

    init(modelID: String) {
        self.modelID = modelID
    }

    func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        SpeechResult(audio: Data(modelID.utf8))
    }
}

private final class CustomVideoModel: VideoModel, @unchecked Sendable {
    let providerID = "custom"
    let modelID: String

    init(modelID: String) {
        self.modelID = modelID
    }

    func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        VideoGenerationResult(urls: ["https://example.com/\(modelID).mp4"], rawValue: .object([:]))
    }
}

private final class CustomRerankingModel: RerankingModel, @unchecked Sendable {
    let providerID = "custom"
    let modelID: String

    init(modelID: String) {
        self.modelID = modelID
    }

    func rerank(_ request: RerankingRequest) async throws -> RerankingResult {
        RerankingResult(results: [RerankedDocument(index: 0, score: 1)], rawValue: .object([:]))
    }
}

private final class CustomFileClient: AIFileClient, @unchecked Sendable {
    let providerID: String

    init(providerID: String = "custom.files") {
        self.providerID = providerID
    }

    func uploadFile(_ request: FileUploadRequest) async throws -> FileUploadResult {
        FileUploadResult(providerReference: ["file": "custom-file"], rawValue: .object([:]))
    }
}

private final class CustomSkillsClient: AISkillsClient, @unchecked Sendable {
    let providerID: String

    init(providerID: String = "custom.skills") {
        self.providerID = providerID
    }

    func uploadSkill(_ request: SkillUploadRequest) async throws -> SkillUploadResult {
        SkillUploadResult(providerReference: ["skill": "custom-skill"], rawValue: .object([:]))
    }
}

private let customProviderModelCapabilities: Set<ModelCapability> = [
    .language,
    .embedding,
    .image,
    .transcription,
    .speech,
    .video,
    .reranking
]
