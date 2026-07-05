import Foundation

public final class AnthropicProvider: AIProvider, @unchecked Sendable {
    public let providerID = "anthropic"
    public let supportedCapabilities: Set<ModelCapability> = [.language]
    private let config: ModelHTTPConfig
    private let languageProviderID: String
    private let skillsProviderID: String

    public init(settings: ProviderSettings = ProviderSettings()) throws {
        if settings.apiKey != nil, settings.authToken != nil {
            throw AIError.invalidArgument(argument: "apiKey/authToken", message: "Both apiKey and authToken were provided. Please use only one authentication method.")
        }
        var headers = settings.headers
        if let authToken = settings.authToken {
            headers["Authorization"] = headers["Authorization"] ?? "Bearer \(authToken)"
        } else {
            let key = settings.apiKey ?? settings.environmentValue(["ANTHROPIC_API_KEY"])
            guard let key else {
                throw AIError.missingAPIKey(provider: providerID, environmentVariables: ["ANTHROPIC_API_KEY"])
            }
            headers["x-api-key"] = headers["x-api-key"] ?? key
        }
        headers = withUserAgentSuffix(headers, "ai-sdk/anthropic/4.0.8")
        headers["anthropic-version"] = headers["anthropic-version"] ?? "2023-06-01"
        languageProviderID = settings.name ?? "anthropic.messages"
        skillsProviderID = anthropicSkillsProviderID(from: languageProviderID)
        config = ModelHTTPConfig(
            providerID: providerID,
            baseURL: anthropicNormalizedBaseURL(settings.baseURL ?? settings.environmentValue(["ANTHROPIC_BASE_URL"])),
            headers: headers,
            transport: settings.transport,
            includeUsage: settings.includeUsage,
            queryParams: settings.queryParams,
            supportsStructuredOutputs: settings.supportsStructuredOutputs,
            transformRequestBody: settings.transformRequestBody
        )
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        AnthropicLanguageModel(modelID: modelID, config: config.withProviderID(languageProviderID))
    }

    public func messages(_ modelID: String) throws -> any LanguageModel {
        try languageModel(modelID)
    }

    public func files() -> any AIFileClient {
        MultipartFileClient(
            providerID: languageProviderID,
            providerReferenceKey: "anthropic",
            config: config.withProviderID(languageProviderID),
            betaHeader: ("anthropic-beta", "files-api-2025-04-14"),
            defaultFilename: "blob"
        )
    }

    public func skills() -> any AISkillsClient {
        AnthropicSkillsClient(providerID: skillsProviderID, providerReferenceKey: "anthropic", config: config.withProviderID(skillsProviderID))
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

private func anthropicSkillsProviderID(from languageProviderID: String) -> String {
    if languageProviderID.hasSuffix(".messages") {
        return String(languageProviderID.dropLast(".messages".count)) + ".skills"
    }
    return languageProviderID + ".skills"
}

private func anthropicNormalizedBaseURL(_ baseURL: String?) -> String {
    let apiURL = "https://api.anthropic.com"
    let versionedAPIURL = "\(apiURL)/v1"
    guard let baseURL else { return versionedAPIURL }
    let normalized = withoutTrailingSlash(baseURL)
    return normalized == apiURL ? versionedAPIURL : normalized
}
