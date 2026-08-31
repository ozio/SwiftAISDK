import Foundation

public struct MiniMaxProviderSettings: Sendable {
    public var apiKey: String?
    public var baseURL: String?
    public var videoBaseURL: String?
    public var headers: [String: String]
    public var environment: [String: String]?
    public var transport: any AITransport

    public init(
        apiKey: String? = nil,
        baseURL: String? = nil,
        videoBaseURL: String? = nil,
        headers: [String: String] = [:],
        environment: [String: String]? = nil,
        transport: any AITransport = URLSessionTransport.shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.videoBaseURL = videoBaseURL
        self.headers = headers
        self.environment = environment
        self.transport = transport
    }

    func environmentValue(_ name: String) -> String? {
        if let environment { return environment[name] }
        return SwiftAISDK.environmentValue([name])
    }
}

public final class MiniMaxProvider: AIProvider, @unchecked Sendable {
    public let providerID = "minimax"
    public let supportedCapabilities: Set<ModelCapability> = [.language, .video]

    private let config: ModelHTTPConfig
    private let videoConfig: ModelHTTPConfig

    public init(settings: MiniMaxProviderSettings = MiniMaxProviderSettings()) throws {
        let apiKey = settings.apiKey ?? settings.environmentValue("MINIMAX_API_KEY")
        guard let apiKey else {
            throw AIError.missingAPIKey(
                provider: providerID,
                environmentVariables: ["MINIMAX_API_KEY"]
            )
        }

        var languageHeaders = normalizeHeaders(settings.headers)
        languageHeaders["anthropic-version"] = languageHeaders["anthropic-version"] ?? "2023-06-01"
        languageHeaders["x-api-key"] = languageHeaders["x-api-key"] ?? apiKey
        languageHeaders = withUserAgentSuffix(languageHeaders, "ai-sdk/minimax/3.0.22")

        config = ModelHTTPConfig(
            providerID: "minimax.messages",
            baseURL: settings.baseURL ?? "https://api.minimax.io/anthropic/v1",
            headers: languageHeaders,
            transport: settings.transport
        )

        var videoHeaders = normalizeHeaders(settings.headers)
        videoHeaders["authorization"] = videoHeaders["authorization"] ?? "Bearer \(apiKey)"
        videoHeaders = withUserAgentSuffix(videoHeaders, "ai-sdk/minimax/3.0.22")
        videoConfig = ModelHTTPConfig(
            providerID: "minimax.video",
            baseURL: settings.videoBaseURL ?? "https://api.minimax.io",
            headers: videoHeaders,
            transport: settings.transport
        )
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        AnthropicLanguageModel(modelID: modelID, config: config, supportedURLs: [:])
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
        MiniMaxVideoModel(modelID: modelID, config: videoConfig)
    }

    public func rerankingModel(_ modelID: String) throws -> any RerankingModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .reranking, modelID: modelID)
    }
}
