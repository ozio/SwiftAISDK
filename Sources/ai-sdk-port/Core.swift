import Foundation

public enum AIError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingAPIKey(provider: String, environmentVariables: [String])
    case unsupportedModel(provider: String, capability: ModelCapability, modelID: String)
    case invalidArgument(argument: String, message: String)
    case invalidResponse(provider: String, message: String)
    case httpStatus(provider: String, statusCode: Int, body: String)
    case invalidURL(String)

    public var description: String {
        switch self {
        case let .missingAPIKey(provider, variables):
            return "\(provider) API key is missing. Pass it in ProviderSettings or set one of: \(variables.joined(separator: ", "))."
        case let .unsupportedModel(provider, capability, modelID):
            return "\(provider) does not provide \(capability.rawValue) model '\(modelID)'."
        case let .invalidArgument(argument, message):
            return "Invalid \(argument): \(message)"
        case let .invalidResponse(provider, message):
            return "\(provider) returned an invalid response: \(message)"
        case let .httpStatus(provider, statusCode, body):
            return "\(provider) request failed with HTTP \(statusCode): \(body)"
        case let .invalidURL(url):
            return "Invalid URL: \(url)"
        }
    }
}

public enum ModelCapability: String, Hashable, Codable, CaseIterable, Sendable {
    case language
    case completion
    case embedding
    case image
    case transcription
    case speech
    case video
    case reranking
}

public enum MessageRole: String, Codable, Hashable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public enum AIContentPart: Equatable, Hashable, Sendable {
    case text(String)
    case imageURL(String)
    case data(mimeType: String, data: Data)
    case file(mimeType: String, data: Data, filename: String? = nil)

    public var text: String? {
        if case let .text(value) = self { value } else { nil }
    }

    public var filePayload: (mimeType: String, data: Data, filename: String?)? {
        switch self {
        case let .data(mimeType, data):
            return (mimeType, data, nil)
        case let .file(mimeType, data, filename):
            return (mimeType, data, filename)
        case .text, .imageURL:
            return nil
        }
    }
}

public struct AIMessage: Equatable, Hashable, Sendable {
    public var role: MessageRole
    public var content: [AIContentPart]

    public init(role: MessageRole, content: [AIContentPart]) {
        self.role = role
        self.content = content
    }

    public static func system(_ text: String) -> AIMessage {
        AIMessage(role: .system, content: [.text(text)])
    }

    public static func user(_ text: String) -> AIMessage {
        AIMessage(role: .user, content: [.text(text)])
    }

    public static func assistant(_ text: String) -> AIMessage {
        AIMessage(role: .assistant, content: [.text(text)])
    }

    public var combinedText: String {
        content.compactMap(\.text).joined(separator: "\n")
    }
}

public struct LanguageModelRequest: Sendable {
    public var messages: [AIMessage]
    public var temperature: Double?
    public var topP: Double?
    public var maxOutputTokens: Int?
    public var stopSequences: [String]
    public var tools: [String: JSONValue]
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]

    public init(
        messages: [AIMessage],
        temperature: Double? = nil,
        topP: Double? = nil,
        maxOutputTokens: Int? = nil,
        stopSequences: [String] = [],
        tools: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:]
    ) {
        self.messages = messages
        self.temperature = temperature
        self.topP = topP
        self.maxOutputTokens = maxOutputTokens
        self.stopSequences = stopSequences
        self.tools = tools
        self.extraBody = extraBody
        self.headers = headers
    }
}

public struct TextGenerationResult: Sendable {
    public var text: String
    public var reasoning: String
    public var finishReason: String?
    public var usage: TokenUsage?
    public var toolCalls: [AIToolCall]
    public var sources: [AISource]
    public var providerMetadata: [String: JSONValue]
    public var rawValue: JSONValue
    public var warnings: [AIWarning]

    public init(
        text: String,
        reasoning: String = "",
        finishReason: String? = nil,
        usage: TokenUsage? = nil,
        toolCalls: [AIToolCall] = [],
        sources: [AISource] = [],
        providerMetadata: [String: JSONValue] = [:],
        rawValue: JSONValue,
        warnings: [AIWarning] = []
    ) {
        self.text = text
        self.reasoning = reasoning
        self.finishReason = finishReason
        self.usage = usage
        self.toolCalls = toolCalls
        self.sources = sources
        self.providerMetadata = providerMetadata
        self.rawValue = rawValue
        self.warnings = warnings
    }
}

public struct AISource: Equatable, Hashable, Sendable {
    public var id: String
    public var sourceType: String
    public var url: String?
    public var title: String?
    public var mediaType: String?
    public var filename: String?
    public var providerMetadata: [String: JSONValue]
    public var rawValue: JSONValue?

    public init(
        id: String,
        sourceType: String,
        url: String? = nil,
        title: String? = nil,
        mediaType: String? = nil,
        filename: String? = nil,
        providerMetadata: [String: JSONValue] = [:],
        rawValue: JSONValue? = nil
    ) {
        self.id = id
        self.sourceType = sourceType
        self.url = url
        self.title = title
        self.mediaType = mediaType
        self.filename = filename
        self.providerMetadata = providerMetadata
        self.rawValue = rawValue
    }
}

public struct AIToolCall: Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var arguments: String
    public var providerExecuted: Bool
    public var rawValue: JSONValue?

    public init(id: String, name: String, arguments: String, providerExecuted: Bool = false, rawValue: JSONValue? = nil) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.providerExecuted = providerExecuted
        self.rawValue = rawValue
    }
}

public enum LanguageStreamPart: Equatable, Sendable {
    case textDelta(String)
    case reasoningDelta(String)
    case toolCallDelta(id: String?, name: String?, argumentsDelta: String, index: Int?)
    case toolCall(AIToolCall)
    case source(AISource)
    case metadata([String: JSONValue])
    case raw(JSONValue)
    case finish(reason: String?, usage: TokenUsage?)
}

public struct EmbeddingRequest: Sendable {
    public var values: [String]
    public var dimensions: Int?
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]

    public init(values: [String], dimensions: Int? = nil, extraBody: [String: JSONValue] = [:], headers: [String: String] = [:]) {
        self.values = values
        self.dimensions = dimensions
        self.extraBody = extraBody
        self.headers = headers
    }
}

public struct EmbeddingResult: Sendable {
    public var embeddings: [[Double]]
    public var usage: TokenUsage?
    public var rawValue: JSONValue
    public var warnings: [AIWarning]

    public init(embeddings: [[Double]], usage: TokenUsage? = nil, rawValue: JSONValue, warnings: [AIWarning] = []) {
        self.embeddings = embeddings
        self.usage = usage
        self.rawValue = rawValue
        self.warnings = warnings
    }
}

public struct ImageGenerationRequest: Sendable {
    public var prompt: String
    public var size: String?
    public var aspectRatio: String?
    public var seed: Int?
    public var count: Int?
    public var files: [ImageInputFile]
    public var mask: ImageInputFile?
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]

    public init(
        prompt: String,
        size: String? = nil,
        aspectRatio: String? = nil,
        seed: Int? = nil,
        count: Int? = nil,
        files: [ImageInputFile] = [],
        mask: ImageInputFile? = nil,
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:]
    ) {
        self.prompt = prompt
        self.size = size
        self.aspectRatio = aspectRatio
        self.seed = seed
        self.count = count
        self.files = files
        self.mask = mask
        self.extraBody = extraBody
        self.headers = headers
    }
}

public struct ImageInputFile: Sendable, Equatable {
    public var data: Data?
    public var url: String?
    public var mediaType: String?
    public var fileName: String?

    public init(data: Data, mediaType: String, fileName: String? = nil) {
        self.data = data
        self.url = nil
        self.mediaType = mediaType
        self.fileName = fileName
    }

    public init(url: String, mediaType: String? = nil, fileName: String? = nil) {
        self.data = nil
        self.url = url
        self.mediaType = mediaType
        self.fileName = fileName
    }
}

public struct ImageGenerationResult: Sendable {
    public var urls: [String]
    public var base64Images: [String]
    public var rawValue: JSONValue
    public var warnings: [AIWarning]

    public init(urls: [String], base64Images: [String] = [], rawValue: JSONValue, warnings: [AIWarning] = []) {
        self.urls = urls
        self.base64Images = base64Images
        self.rawValue = rawValue
        self.warnings = warnings
    }
}

public struct AudioTranscriptionRequest: Sendable {
    public var audio: Data
    public var fileName: String
    public var mimeType: String
    public var language: String?
    public var prompt: String?
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]

    public init(audio: Data, fileName: String = "audio.wav", mimeType: String = "audio/wav", language: String? = nil, prompt: String? = nil, extraBody: [String: JSONValue] = [:], headers: [String: String] = [:]) {
        self.audio = audio
        self.fileName = fileName
        self.mimeType = mimeType
        self.language = language
        self.prompt = prompt
        self.extraBody = extraBody
        self.headers = headers
    }
}

public struct TranscriptionResult: Sendable {
    public var text: String
    public var rawValue: JSONValue

    public init(text: String, rawValue: JSONValue) {
        self.text = text
        self.rawValue = rawValue
    }
}

public struct SpeechRequest: Sendable {
    public var text: String
    public var voice: String?
    public var format: String?
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]

    public init(text: String, voice: String? = nil, format: String? = nil, extraBody: [String: JSONValue] = [:], headers: [String: String] = [:]) {
        self.text = text
        self.voice = voice
        self.format = format
        self.extraBody = extraBody
        self.headers = headers
    }
}

public struct SpeechResult: Sendable {
    public var audio: Data
    public var contentType: String?

    public init(audio: Data, contentType: String? = nil) {
        self.audio = audio
        self.contentType = contentType
    }
}

public struct VideoGenerationRequest: Sendable {
    public var prompt: String
    public var aspectRatio: String?
    public var durationSeconds: Double?
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]

    public init(prompt: String, aspectRatio: String? = nil, durationSeconds: Double? = nil, extraBody: [String: JSONValue] = [:], headers: [String: String] = [:]) {
        self.prompt = prompt
        self.aspectRatio = aspectRatio
        self.durationSeconds = durationSeconds
        self.extraBody = extraBody
        self.headers = headers
    }
}

public struct VideoGenerationResult: Sendable {
    public var urls: [String]
    public var operationID: String?
    public var rawValue: JSONValue

    public init(urls: [String], operationID: String? = nil, rawValue: JSONValue) {
        self.urls = urls
        self.operationID = operationID
        self.rawValue = rawValue
    }
}

public struct RerankingRequest: Sendable {
    public var query: String
    public var documents: [String]
    public var topK: Int?
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]

    public init(query: String, documents: [String], topK: Int? = nil, extraBody: [String: JSONValue] = [:], headers: [String: String] = [:]) {
        self.query = query
        self.documents = documents
        self.topK = topK
        self.extraBody = extraBody
        self.headers = headers
    }
}

public struct RerankingResult: Sendable {
    public var results: [RerankedDocument]
    public var rawValue: JSONValue

    public init(results: [RerankedDocument], rawValue: JSONValue) {
        self.results = results
        self.rawValue = rawValue
    }
}

public struct RerankedDocument: Equatable, Sendable {
    public var index: Int
    public var score: Double
    public var document: String?

    public init(index: Int, score: Double, document: String? = nil) {
        self.index = index
        self.score = score
        self.document = document
    }
}

public struct FileUploadRequest: Sendable {
    public var data: Data
    public var mediaType: String
    public var filename: String?
    public var purpose: String?
    public var displayName: String?
    public var pollIntervalNanoseconds: UInt64
    public var pollTimeoutNanoseconds: UInt64
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]

    public init(
        data: Data,
        mediaType: String,
        filename: String? = nil,
        purpose: String? = nil,
        displayName: String? = nil,
        pollIntervalNanoseconds: UInt64 = 2_000_000_000,
        pollTimeoutNanoseconds: UInt64 = 300_000_000_000,
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:]
    ) {
        self.data = data
        self.mediaType = mediaType
        self.filename = filename
        self.purpose = purpose
        self.displayName = displayName
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.pollTimeoutNanoseconds = pollTimeoutNanoseconds
        self.extraBody = extraBody
        self.headers = headers
    }
}

public struct FileUploadResult: Sendable {
    public var providerReference: [String: String]
    public var filename: String?
    public var mediaType: String?
    public var metadata: [String: JSONValue]
    public var rawValue: JSONValue

    public init(providerReference: [String: String], filename: String? = nil, mediaType: String? = nil, metadata: [String: JSONValue] = [:], rawValue: JSONValue) {
        self.providerReference = providerReference
        self.filename = filename
        self.mediaType = mediaType
        self.metadata = metadata
        self.rawValue = rawValue
    }
}

public struct SkillUploadFile: Equatable, Sendable {
    public var path: String
    public var data: Data
    public var mediaType: String

    public init(path: String, data: Data, mediaType: String = "application/octet-stream") {
        self.path = path
        self.data = data
        self.mediaType = mediaType
    }
}

public struct SkillUploadRequest: Sendable {
    public var files: [SkillUploadFile]
    public var displayTitle: String?
    public var headers: [String: String]

    public init(files: [SkillUploadFile], displayTitle: String? = nil, headers: [String: String] = [:]) {
        self.files = files
        self.displayTitle = displayTitle
        self.headers = headers
    }
}

public struct AIWarning: Equatable, Sendable {
    public var type: String
    public var feature: String?
    public var setting: String?
    public var message: String?

    public init(type: String, feature: String? = nil, setting: String? = nil, message: String? = nil) {
        self.type = type
        self.feature = feature
        self.setting = setting
        self.message = message
    }
}

public struct SkillUploadResult: Sendable {
    public var providerReference: [String: String]
    public var displayTitle: String?
    public var name: String?
    public var description: String?
    public var latestVersion: String?
    public var providerMetadata: [String: JSONValue]
    public var warnings: [AIWarning]
    public var rawValue: JSONValue

    public init(
        providerReference: [String: String],
        displayTitle: String? = nil,
        name: String? = nil,
        description: String? = nil,
        latestVersion: String? = nil,
        providerMetadata: [String: JSONValue] = [:],
        warnings: [AIWarning] = [],
        rawValue: JSONValue
    ) {
        self.providerReference = providerReference
        self.displayTitle = displayTitle
        self.name = name
        self.description = description
        self.latestVersion = latestVersion
        self.providerMetadata = providerMetadata
        self.warnings = warnings
        self.rawValue = rawValue
    }
}

public struct TokenUsage: Equatable, Codable, Sendable {
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var totalTokens: Int?

    public init(inputTokens: Int? = nil, outputTokens: Int? = nil, totalTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}

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
