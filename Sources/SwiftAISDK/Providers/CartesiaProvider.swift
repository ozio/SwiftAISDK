import Foundation

public struct CartesiaProviderSettings: Sendable {
    public var apiKey: String?
    public var version: String
    public var baseURL: String?
    public var headers: [String: String]
    public var environment: [String: String]?
    public var transport: any AITransport

    public init(
        apiKey: String? = nil,
        version: String = CartesiaProvider.defaultAPIVersion,
        baseURL: String? = nil,
        headers: [String: String] = [:],
        environment: [String: String]? = nil,
        transport: any AITransport = URLSessionTransport.shared
    ) {
        self.apiKey = apiKey
        self.version = version
        self.baseURL = baseURL
        self.headers = headers
        self.environment = environment
        self.transport = transport
    }
}

public final class CartesiaProvider: AIProvider, @unchecked Sendable {
    public static let defaultAPIVersion = "2026-03-01"

    public let providerID = "cartesia"
    public let supportedCapabilities: Set<ModelCapability> = [.speech, .transcription]

    private let config: ModelHTTPConfig

    public init(settings: CartesiaProviderSettings = CartesiaProviderSettings()) throws {
        let apiKey: String?
        if let environment = settings.environment {
            apiKey = settings.apiKey ?? environment["CARTESIA_API_KEY"]
        } else {
            apiKey = settings.apiKey ?? environmentValue(["CARTESIA_API_KEY"])
        }
        guard let apiKey else {
            throw AIError.missingAPIKey(
                provider: providerID,
                environmentVariables: ["CARTESIA_API_KEY"]
            )
        }

        var headers = withUserAgentSuffix(
            settings.headers,
            "ai-sdk/cartesia/3.0.10"
        )
        headers["authorization"] = headers["authorization"] ?? "Bearer \(apiKey)"
        headers["cartesia-version"] = headers["cartesia-version"] ?? settings.version

        config = ModelHTTPConfig(
            providerID: providerID,
            baseURL: settings.baseURL ?? "https://api.cartesia.ai",
            headers: headers,
            transport: settings.transport
        )
    }

    public func speechModel(_ modelID: String) throws -> any SpeechModel {
        CartesiaSpeechModel(
            modelID: modelID,
            config: config.withProviderID("cartesia.speech")
        )
    }

    public func transcriptionModel(_ modelID: String) throws -> any TranscriptionModel {
        CartesiaTranscriptionModel(
            modelID: modelID,
            config: config.withProviderID("cartesia.transcription")
        )
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        throw AIError.unsupportedModel(
            provider: providerID,
            capability: .language,
            modelID: modelID
        )
    }

    public func embeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        throw AIError.unsupportedModel(
            provider: providerID,
            capability: .embedding,
            modelID: modelID
        )
    }

    public func imageModel(_ modelID: String) throws -> any ImageModel {
        throw AIError.unsupportedModel(
            provider: providerID,
            capability: .image,
            modelID: modelID
        )
    }

    public func videoModel(_ modelID: String) throws -> any VideoModel {
        throw AIError.unsupportedModel(
            provider: providerID,
            capability: .video,
            modelID: modelID
        )
    }

    public func rerankingModel(_ modelID: String) throws -> any RerankingModel {
        throw AIError.unsupportedModel(
            provider: providerID,
            capability: .reranking,
            modelID: modelID
        )
    }
}

func cartesiaHTTPStatusError(
    provider: String,
    response: AIHTTPResponse
) -> AIError {
    let body: String
    if let raw = try? response.jsonValue(),
       let title = raw["title"]?.stringValue,
       let message = raw["message"]?.stringValue,
       raw["request_id"]?.stringValue != nil,
       cartesiaNullishString(raw["error_code"]),
       cartesiaOptionalString(raw["doc_url"]) {
        body = "\(title): \(message)"
    } else {
        body = response.bodyText
    }
    return apiCallError(
        provider: provider,
        statusCode: response.statusCode,
        body: body,
        headers: response.headers
    )
}

private func cartesiaNullishString(_ value: JSONValue?) -> Bool {
    value == nil || value == .null || value?.stringValue != nil
}

private func cartesiaOptionalString(_ value: JSONValue?) -> Bool {
    value == nil || value?.stringValue != nil
}
