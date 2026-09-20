import Foundation
import Testing
@testable import SwiftAISDK

private typealias SwiftAISDK170CustomProviderFactory = (
    String,
    [String: any LanguageModel],
    [String: any EmbeddingModel],
    [String: any ImageModel],
    [String: any TranscriptionModel],
    [String: any SpeechModel],
    [String: any VideoModel],
    [String: any RerankingModel],
    (any AIFileClient)?,
    (any AISkillsClient)?,
    (any AIProvider)?
) -> AICustomProvider

@Test func providerRegistryRoutesCombinedModelIDsToRegisteredProviders() throws {
    let appProvider = customProvider(
        providerID: "app",
        languageModels: ["chat": CustomLanguageModel(modelID: "app-chat")],
        embeddingModels: ["embed": CustomEmbeddingModel(modelID: "app-embed")],
        imageModels: ["image": CustomImageModel(modelID: "app-image")],
        transcriptionModels: ["transcribe": CustomTranscriptionModel(modelID: "app-transcribe")],
        speechModels: ["speech": CustomSpeechModel(modelID: "app-speech")],
        videoModels: ["video": CustomVideoModel(modelID: "app-video")],
        rerankingModels: ["rank": CustomRerankingModel(modelID: "app-rank")]
    )
    let registry = createProviderRegistry(["app": appProvider])

    #expect(registry.providerID == "provider-registry")
    #expect(registry.supportedCapabilities == customProviderModelCapabilities)
    #expect((try registry.languageModel("app:chat") as? CustomLanguageModel)?.modelID == "app-chat")
    #expect((try registry.embeddingModel("app:embed") as? CustomEmbeddingModel)?.modelID == "app-embed")
    #expect((try registry.imageModel("app:image") as? CustomImageModel)?.modelID == "app-image")
    #expect((try registry.transcriptionModel("app:transcribe") as? CustomTranscriptionModel)?.modelID == "app-transcribe")
    #expect((try registry.speechModel("app:speech") as? CustomSpeechModel)?.modelID == "app-speech")
    #expect((try registry.videoModel("app:video") as? CustomVideoModel)?.modelID == "app-video")
    #expect((try registry.rerankingModel("app:rank") as? CustomRerankingModel)?.modelID == "app-rank")
}

@Test func providerRegistrySupportsCustomSeparatorAndFactoryAlias() throws {
    let appProvider = customProvider(languageModels: ["chat:v1": CustomLanguageModel(modelID: "nested-id")])
    let registry = AIProviders.providerRegistry(["app": appProvider], separator: "/")

    #expect((try registry.languageModel("app/chat:v1") as? CustomLanguageModel)?.modelID == "nested-id")
}

@Test func providerRegistryRoutesFilesAndSkillsByProviderID() async throws {
    let appProvider = customProvider(
        files: CustomFileClient(providerID: "app.files"),
        skills: CustomSkillsClient(providerID: "app.skills")
    )
    let registry = experimentalCreateProviderRegistry(["app": appProvider])

    let file = try await AI.uploadFile(client: try registry.files("app"), request: FileUploadRequest(data: Data("file".utf8), mediaType: "text/plain"))
    let skill = try await AI.uploadSkill(client: try registry.skills("app"), request: SkillUploadRequest(files: [SkillUploadFile(path: "skill.md", data: Data("skill".utf8))]))

    #expect(file.providerReference["file"] == "custom-file")
    #expect(skill.providerReference["skill"] == "custom-skill")
}

@Test func providerRegistryReportsInvalidIDsAndMissingProviders() throws {
    let registry = createProviderRegistry(["app": RegistryLanguageOnlyProvider()])

    #expect(throws: AIProviderRegistryError.invalidModelID(modelID: "chat", modelType: "languageModel", separator: ":")) {
        _ = try registry.languageModel("chat")
    }
    #expect(throws: AIProviderRegistryError.noSuchProvider(providerID: "missing", modelType: "languageModel", availableProviders: ["app"])) {
        _ = try registry.languageModel("missing:chat")
    }
    #expect(throws: AIProviderRegistryError.unsupportedFiles(providerID: "app")) {
        _ = try registry.files("app")
    }
    #expect(throws: AIProviderRegistryError.unsupportedSkills(providerID: "app")) {
        _ = try registry.skills("app")
    }
}

@Test func providerRegistryReportsInvalidIDsForEveryModelFamilyLikeUpstream() throws {
    let registry = createProviderRegistry([:])

    #expect(throws: AIProviderRegistryError.invalidModelID(modelID: "model", modelType: "languageModel", separator: ":")) {
        _ = try registry.languageModel("model")
    }
    #expect(throws: AIProviderRegistryError.invalidModelID(modelID: "model", modelType: "embeddingModel", separator: ":")) {
        _ = try registry.embeddingModel("model")
    }
    #expect(throws: AIProviderRegistryError.invalidModelID(modelID: "model", modelType: "imageModel", separator: ":")) {
        _ = try registry.imageModel("model")
    }
    #expect(throws: AIProviderRegistryError.invalidModelID(modelID: "model", modelType: "transcriptionModel", separator: ":")) {
        _ = try registry.transcriptionModel("model")
    }
    #expect(throws: AIProviderRegistryError.invalidModelID(modelID: "model", modelType: "speechModel", separator: ":")) {
        _ = try registry.speechModel("model")
    }
    #expect(throws: AIProviderRegistryError.invalidModelID(modelID: "model", modelType: "videoModel", separator: ":")) {
        _ = try registry.videoModel("model")
    }
    #expect(throws: AIProviderRegistryError.invalidModelID(modelID: "model", modelType: "rerankingModel", separator: ":")) {
        _ = try registry.rerankingModel("model")
    }
}

@Test func providerRegistryReportsMissingProvidersForEveryModelFamilyLikeUpstream() throws {
    let registry = createProviderRegistry(["app": RegistryLanguageOnlyProvider()])
    let availableProviders = ["app"]

    #expect(throws: AIProviderRegistryError.noSuchProvider(providerID: "missing", modelType: "languageModel", availableProviders: availableProviders)) {
        _ = try registry.languageModel("missing:model")
    }
    #expect(throws: AIProviderRegistryError.noSuchProvider(providerID: "missing", modelType: "embeddingModel", availableProviders: availableProviders)) {
        _ = try registry.embeddingModel("missing:model")
    }
    #expect(throws: AIProviderRegistryError.noSuchProvider(providerID: "missing", modelType: "imageModel", availableProviders: availableProviders)) {
        _ = try registry.imageModel("missing:model")
    }
    #expect(throws: AIProviderRegistryError.noSuchProvider(providerID: "missing", modelType: "transcriptionModel", availableProviders: availableProviders)) {
        _ = try registry.transcriptionModel("missing:model")
    }
    #expect(throws: AIProviderRegistryError.noSuchProvider(providerID: "missing", modelType: "speechModel", availableProviders: availableProviders)) {
        _ = try registry.speechModel("missing:model")
    }
    #expect(throws: AIProviderRegistryError.noSuchProvider(providerID: "missing", modelType: "videoModel", availableProviders: availableProviders)) {
        _ = try registry.videoModel("missing:model")
    }
    #expect(throws: AIProviderRegistryError.noSuchProvider(providerID: "missing", modelType: "rerankingModel", availableProviders: availableProviders)) {
        _ = try registry.rerankingModel("missing:model")
    }
}

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

@Test func customProviderRetainsSwiftAISDK170FactorySignatures() throws {
    let initializer: SwiftAISDK170CustomProviderFactory = AICustomProvider.init
    let globalFactory: SwiftAISDK170CustomProviderFactory = customProvider
    let namespacedFactory: SwiftAISDK170CustomProviderFactory = AIProviders.customProvider

    func makeProvider(
        _ factory: SwiftAISDK170CustomProviderFactory,
        providerID: String,
        modelID: String
    ) -> AICustomProvider {
        factory(
            providerID,
            ["chat": CustomLanguageModel(modelID: modelID)],
            [:],
            [:],
            [:],
            [:],
            [:],
            [:],
            nil,
            nil,
            nil
        )
    }

    let providers = [
        makeProvider(initializer, providerID: "legacy-init", modelID: "init-model"),
        makeProvider(globalFactory, providerID: "legacy-global", modelID: "global-model"),
        makeProvider(namespacedFactory, providerID: "legacy-namespaced", modelID: "namespaced-model")
    ]

    #expect(providers.map(\.providerID) == ["legacy-init", "legacy-global", "legacy-namespaced"])
    #expect((try providers[0].languageModel("chat") as? CustomLanguageModel)?.modelID == "init-model")
    #expect((try providers[1].languageModel("chat") as? CustomLanguageModel)?.modelID == "global-model")
    #expect((try providers[2].languageModel("chat") as? CustomLanguageModel)?.modelID == "namespaced-model")
    for provider in providers {
        #expect(!provider.supportedCapabilities.contains(.evaluation))
        #expect(throws: AIEvaluationModelResolutionError.noSuchModel(modelID: "missing")) {
            _ = try provider.evaluationModel("missing")
        }
    }
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

@Test func customProviderThrowsWhenEveryModelFamilyAndFallbackAreMissingLikeUpstream() throws {
    let provider = customProvider(providerID: "app")

    #expect(throws: AIError.unsupportedModel(provider: "app", capability: .language, modelID: "missing")) {
        _ = try provider.languageModel("missing")
    }
    #expect(throws: AIError.unsupportedModel(provider: "app", capability: .embedding, modelID: "missing")) {
        _ = try provider.embeddingModel("missing")
    }
    #expect(throws: AIError.unsupportedModel(provider: "app", capability: .image, modelID: "missing")) {
        _ = try provider.imageModel("missing")
    }
    #expect(throws: AIError.unsupportedModel(provider: "app", capability: .transcription, modelID: "missing")) {
        _ = try provider.transcriptionModel("missing")
    }
    #expect(throws: AIError.unsupportedModel(provider: "app", capability: .speech, modelID: "missing")) {
        _ = try provider.speechModel("missing")
    }
    #expect(throws: AIError.unsupportedModel(provider: "app", capability: .video, modelID: "missing")) {
        _ = try provider.videoModel("missing")
    }
    #expect(throws: AIError.unsupportedModel(provider: "app", capability: .reranking, modelID: "missing")) {
        _ = try provider.rerankingModel("missing")
    }
}

@Suite("CustomProviderEvaluationTests", .serialized)
struct CustomProviderEvaluationTests {
    @Test func customProviderResolvesDirectAndDefaultProviderEvaluationAliases() throws {
        let model = CustomEvaluationModel(modelID: "evaluation")
        let defaultProvider = customProvider(
            evaluationModels: ["remote": .model(model)]
        )
        let provider = customProvider(
            evaluationModels: [
                "direct": .model(model),
                "alias": .modelID("remote")
            ]
        )
        let directModelProvider = customProvider(
            evaluationModels: ["plain": model]
        )

        #expect((try provider.evaluationModel("direct") as? CustomEvaluationModel) === model)
        #expect((try directModelProvider.evaluationModel("plain") as? CustomEvaluationModel) === model)
        let resolved = try AIDefaultProvider.withProvider(defaultProvider) {
            try provider.evaluationModel("alias") as? CustomEvaluationModel
        }
        #expect(resolved === model)
    }

    @Test func customProviderUsesEvaluationFallbackAndReportsMissingModels() throws {
        let model = CustomEvaluationModel(modelID: "fallback")
        let fallback = customProvider(evaluationModels: ["route": .model(model)])
        let provider = customProvider(fallbackProvider: fallback)

        #expect((try provider.evaluationModel("route") as? CustomEvaluationModel) === model)
        #expect(throws: AIEvaluationModelResolutionError.noSuchModel(modelID: "missing")) {
            _ = try provider.evaluationModel("missing")
        }
    }

    @Test func registryRoutesEvaluationModelsWithNestedIDsAndKeepsStableProviderSeparate() throws {
        let model = CustomEvaluationModel(modelID: "model:version")
        let provider = customProvider(
            evaluationModels: ["model:version": .model(model)]
        )
        let registry = createProviderRegistry(["app": provider])
        let stableProvider: any AIProvider = registry

        #expect(stableProvider.providerID == "provider-registry")
        #expect((try registry.evaluationModel("app:model:version") as? CustomEvaluationModel) === model)
        #expect((stableProvider as? any AIEvaluationProvider) != nil)
        #expect(throws: AIProviderRegistryError.invalidModelID(
            modelID: "model",
            modelType: "evaluationModel",
            separator: ":"
        )) {
            _ = try registry.evaluationModel("model")
        }
        #expect(throws: AIProviderRegistryError.noSuchProvider(
            providerID: "missing",
            modelType: "evaluationModel",
            availableProviders: ["app"]
        )) {
            _ = try registry.evaluationModel("missing:model")
        }
    }

    @Test func registryRejectsProvidersWithoutStructuralEvaluationSupport() throws {
        let registry = createProviderRegistry(["app": RegistryLanguageOnlyProvider()])

        #expect(throws: AIEvaluationModelResolutionError.noSuchModel(modelID: "app:model")) {
            _ = try registry.evaluationModel("app:model")
        }
    }

    @Test func providerWrapperPreservesFileAndSkillClients() throws {
        let files = CustomFileClient(providerID: "wrapped.files")
        let skills = CustomSkillsClient(providerID: "wrapped.skills")
        let provider = customProvider(files: files, skills: skills)
        let wrapped = wrapProvider(
            provider,
            languageModelMiddleware: [AILanguageModelMiddleware]()
        )

        let fileProvider = try #require(wrapped as? any AIFileProvider)
        let skillProvider = try #require(wrapped as? any AISkillsProvider)
        #expect((try fileProvider.files()).providerID == "wrapped.files")
        #expect((try skillProvider.skills()).providerID == "wrapped.skills")
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

private final class RegistryLanguageOnlyProvider: AIProvider, @unchecked Sendable {
    let providerID = "registry-language-only"
    let supportedCapabilities: Set<ModelCapability> = [.language]

    func languageModel(_ modelID: String) throws -> any LanguageModel {
        CustomLanguageModel(modelID: modelID)
    }

    func embeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .embedding, modelID: modelID)
    }

    func imageModel(_ modelID: String) throws -> any ImageModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .image, modelID: modelID)
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

private final class CustomEvaluationModel: AIEvaluationModelV4, @unchecked Sendable {
    let providerID = "custom.evaluation"
    let modelID: String
    let supportedQuestionTypes = AIEvaluationQuestionType.allCases

    init(modelID: String) {
        self.modelID = modelID
    }

    func doEvaluate(_ options: AIEvaluationModelV4CallOptions) async throws -> AIEvaluationModelV4Result {
        AIEvaluationModelV4Result(answers: [:], warnings: [])
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
