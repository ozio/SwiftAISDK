import Foundation

public typealias AzureOpenAITokenProvider = @Sendable () async throws -> String

public final class AzureOpenAIProvider: AIProvider, @unchecked Sendable {
    public let providerID = "azure"
    public let supportedCapabilities: Set<ModelCapability> = [.language, .completion, .embedding, .image, .transcription, .speech]
    private let provider: OpenAICompatibleProvider
    private let config: ModelHTTPConfig

    public init(
        resourceName: String? = nil,
        apiVersion: String = "v1",
        useDeploymentBasedURLs: Bool = false,
        tokenProvider: AzureOpenAITokenProvider? = nil,
        settings: ProviderSettings = ProviderSettings()
    ) throws {
        if settings.apiKey != nil, tokenProvider != nil {
            throw AIError.invalidArgument(argument: "apiKey/tokenProvider", message: "Both apiKey and tokenProvider were provided. Please use only one authentication method.")
        }
        let resolvedResourceName = resourceName ?? ProcessInfo.processInfo.environment["AZURE_RESOURCE_NAME"]
        let basePrefix = settings.baseURL ?? resolvedResourceName.map { "https://\($0).openai.azure.com/openai" }
        guard let basePrefix else {
            throw AIError.invalidURL("Azure requires ProviderSettings.baseURL or AZURE_RESOURCE_NAME/resourceName.")
        }
        var headers = settings.headers
        if tokenProvider == nil {
            let key = settings.apiKey ?? environmentValue(["AZURE_API_KEY"])
            guard let key else {
                throw AIError.missingAPIKey(provider: providerID, environmentVariables: ["AZURE_API_KEY"])
            }
            headers["api-key"] = headers["api-key"] ?? key
        }
        headers = withUserAgentSuffix(headers, "ai-sdk/azure/3.0.74")
        let baseURL = withoutTrailingSlash(basePrefix)
        let transport = tokenProvider.map { AzureOpenAITokenProviderTransport(base: settings.transport, tokenProvider: $0) } ?? settings.transport
        let config = ModelHTTPConfig(providerID: providerID, baseURL: baseURL, headers: headers, transport: transport, includeUsage: settings.includeUsage, queryParams: settings.queryParams, supportsStructuredOutputs: settings.supportsStructuredOutputs, maxEmbeddingsPerCall: settings.maxEmbeddingsPerCall, transformRequestBody: settings.transformRequestBody) { modelID, path in
            let urlString = useDeploymentBasedURLs
                ? "\(baseURL)/deployments/\(modelID)\(path)"
                : "\(baseURL)/v1\(path)"
            guard var components = URLComponents(string: urlString) else { throw AIError.invalidURL(urlString) }
            components.queryItems = [URLQueryItem(name: "api-version", value: apiVersion)]
            guard let url = components.url else { throw AIError.invalidURL(urlString) }
            return url
        }
        self.config = config
        provider = OpenAICompatibleProvider(providerID: providerID, supportedCapabilities: supportedCapabilities, config: config)
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel { try provider.responsesModel(modelID) }
    public func chatModel(_ modelID: String) throws -> any LanguageModel { try provider.chatModel(modelID) }
    public func chat(_ modelID: String) throws -> any LanguageModel { try chatModel(modelID) }
    public func deepseek(_ modelID: String) throws -> any LanguageModel {
        DeepSeekLanguageModel(modelID: modelID, config: config.withProviderID("azure.deepseek").withDeepSeekSupportsThinking(false))
    }
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

struct AzureOpenAITokenProviderTransport: AITransport {
    var base: any AITransport
    var tokenProvider: AzureOpenAITokenProvider

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        var request = request
        if !request.headers.keys.contains(where: { $0.caseInsensitiveCompare("authorization") == .orderedSame }) {
            request.headers["authorization"] = "Bearer \(try await tokenProvider())"
        }
        return try await base.send(request)
    }
}
