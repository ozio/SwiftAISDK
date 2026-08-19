import Foundation

public let gmiCloudProviderVersion = "3.0.2"

public func createGMICloud(settings: ProviderSettings = ProviderSettings()) throws -> GMICloudProvider {
    try GMICloudProvider(settings: settings)
}

/// GMI Cloud chat completions over its OpenAI-compatible API.
public final class GMICloudProvider: AIProvider, @unchecked Sendable {
    public let providerID = "gmicloud"
    public let supportedCapabilities: Set<ModelCapability> = [.language]

    private let config: ModelHTTPConfig

    public init(settings: ProviderSettings = ProviderSettings()) throws {
        let headers = try gmiCloudHeaders(settings: settings)
        config = ModelHTTPConfig(
            providerID: "gmicloud.chat",
            baseURL: settings.baseURL ?? "https://api.gmi-serving.com/v1",
            modelURL: settings.modelURL,
            headers: headers,
            transport: settings.transport,
            includeUsage: true,
            queryParams: settings.queryParams,
            supportsStructuredOutputs: settings.supportsStructuredOutputs,
            maxEmbeddingsPerCall: settings.maxEmbeddingsPerCall,
            transformRequestBody: settings.transformRequestBody
        )
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        OpenAICompatibleChatModel(modelID: modelID, config: config)
    }

    public func callAsFunction(_ modelID: String) throws -> any LanguageModel {
        try languageModel(modelID)
    }

    public func chatModel(_ modelID: String) throws -> any LanguageModel {
        try languageModel(modelID)
    }

    public func chat(_ modelID: String) throws -> any LanguageModel {
        try languageModel(modelID)
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

private func gmiCloudHeaders(settings: ProviderSettings) throws -> [String: String] {
    let apiKey = settings.apiKey ?? settings.environmentValue(["GMI_CLOUD_APIKEY"])
    guard let apiKey else {
        throw AIError.missingAPIKey(provider: "gmicloud", environmentVariables: ["GMI_CLOUD_APIKEY"])
    }

    var headers = settings.headers
    if !headers.keys.contains(where: { $0.caseInsensitiveCompare("authorization") == .orderedSame }) {
        headers["Authorization"] = "Bearer \(apiKey)"
    }
    return withUserAgentSuffix(headers, "ai-sdk/gmicloud/\(gmiCloudProviderVersion)")
}

/// GMI's edge stores the backend engine diagnostic as JSON inside
/// `error.details`; prefer that message over the generic outer banner.
func gmiCloudErrorMessage(from data: Data) -> String? {
    guard let response = try? decodeJSONBody(data),
          let outerMessage = response["error"]?["message"]?.stringValue else {
        return nil
    }
    guard let details = response["error"]?["details"]?.stringValue,
          !details.isEmpty,
          let nested = try? secureJSONParse(details),
          let nestedMessage = nested["error"]?["message"]?.stringValue,
          !nestedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return outerMessage
    }
    return nestedMessage
}
