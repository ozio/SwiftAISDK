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
        headers = withUserAgentSuffix(headers, "ai-sdk/azure/4.0.63")
        let baseURL = withoutTrailingSlash(basePrefix)
        let baseURLInfo = try azureOpenAIBaseURLInfo(settings.baseURL)
        let transport = tokenProvider.map { AzureOpenAITokenProviderTransport(base: settings.transport, tokenProvider: $0) } ?? settings.transport
        let config = ModelHTTPConfig(providerID: providerID, baseURL: baseURL, headers: headers, transport: transport, includeUsage: settings.includeUsage, queryParams: settings.queryParams, supportsStructuredOutputs: settings.supportsStructuredOutputs, maxEmbeddingsPerCall: settings.maxEmbeddingsPerCall, transformRequestBody: settings.transformRequestBody) { modelID, path in
            let urlString: String
            if useDeploymentBasedURLs {
                urlString = "\(baseURL)/deployments/\(modelID)\(path)"
            } else if !baseURLInfo.isAzureOpenAI || baseURLInfo.isVersioned {
                urlString = "\(baseURL)\(path)"
            } else {
                urlString = "\(baseURL)/v1\(path)"
            }
            guard var components = URLComponents(string: urlString) else { throw AIError.invalidURL(urlString) }
            if useDeploymentBasedURLs || (
                baseURLInfo.isAzureOpenAI
                    && !baseURLInfo.isVersioned
                    && !baseURLInfo.isFoundryProject
            ) {
                components.queryItems = [URLQueryItem(name: "api-version", value: apiVersion)]
            }
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
        DeepSeekLanguageModel(
            modelID: modelID,
            config: config
                .withProviderID("azure.deepseek")
                .withDeepSeekSupportsThinking(false)
                .withSupportsStructuredOutputs(true)
        )
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

private struct AzureOpenAIBaseURLInfo {
    var isAzureOpenAI: Bool
    var isFoundryProject: Bool
    var isVersioned: Bool
}

private func azureOpenAIBaseURLInfo(_ baseURL: String?) throws -> AzureOpenAIBaseURLInfo {
    guard let baseURL else {
        return AzureOpenAIBaseURLInfo(
            isAzureOpenAI: true,
            isFoundryProject: false,
            isVersioned: false
        )
    }
    guard let components = URLComponents(string: baseURL),
          let hostname = components.host?.lowercased() else {
        throw AIError.invalidURL(baseURL)
    }
    let isFoundryHost = hostname.hasSuffix(".services.ai.azure.com")
    let isAzureOpenAI = hostname.hasSuffix(".openai.azure.com")
        || isFoundryHost
        || hostname.hasSuffix(".cognitiveservices.azure.com")
    let pathname = components.path.replacingOccurrences(
        of: #"/+$"#,
        with: "",
        options: .regularExpression
    )
    return AzureOpenAIBaseURLInfo(
        isAzureOpenAI: isAzureOpenAI,
        isFoundryProject: isFoundryHost && pathname.hasPrefix("/api/projects/"),
        isVersioned: isAzureOpenAI && pathname.lowercased().hasSuffix("/openai/v1")
    )
}

struct AzureOpenAITokenProviderTransport: AIStreamingTransport {
    var base: any AITransport
    var tokenProvider: AzureOpenAITokenProvider

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        try await base.send(authenticatedRequest(request))
    }

    func stream(_ request: AIHTTPRequest) async throws -> AIHTTPStreamResponse {
        let streamingTransport = try requireStreamingTransport(base, providerID: "azure")
        return try await streamingTransport.stream(authenticatedRequest(request))
    }

    private func authenticatedRequest(_ request: AIHTTPRequest) async throws -> AIHTTPRequest {
        var request = request
        if !request.headers.keys.contains(where: { $0.caseInsensitiveCompare("authorization") == .orderedSame }) {
            request.headers["authorization"] = "Bearer \(try await tokenProvider())"
        }
        return request
    }
}
