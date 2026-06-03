import Foundation

public struct AnthropicAWSProviderSettings: Sendable {
    public var region: String?
    public var workspaceID: String?
    public var apiKey: String?
    public var accessKeyID: String?
    public var secretAccessKey: String?
    public var sessionToken: String?
    public var baseURL: String?
    public var headers: [String: String]
    public var transport: any AITransport
    public var date: @Sendable () -> Date

    public init(
        region: String? = nil,
        workspaceID: String? = nil,
        apiKey: String? = nil,
        accessKeyID: String? = nil,
        secretAccessKey: String? = nil,
        sessionToken: String? = nil,
        baseURL: String? = nil,
        headers: [String: String] = [:],
        transport: any AITransport = URLSessionTransport.shared,
        date: @escaping @Sendable () -> Date = Date.init
    ) {
        self.region = region
        self.workspaceID = workspaceID
        self.apiKey = apiKey
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.baseURL = baseURL
        self.headers = headers
        self.transport = transport
        self.date = date
    }
}

public final class AnthropicAWSProvider: AIProvider, @unchecked Sendable {
    public let providerID = "anthropic-aws"
    public let supportedCapabilities: Set<ModelCapability> = [.language]
    private let config: ModelHTTPConfig

    public init(settings: AnthropicAWSProviderSettings = AnthropicAWSProviderSettings()) throws {
        let region = settings.region ?? environmentValue(["AWS_REGION", "AWS_DEFAULT_REGION"])
        let baseURL: String
        if let configuredBaseURL = settings.baseURL {
            baseURL = configuredBaseURL
        } else {
            guard let region else {
                throw AIError.missingAPIKey(provider: providerID, environmentVariables: ["AWS_REGION"])
            }
            baseURL = "https://aws-external-anthropic.\(region).api.aws/v1"
        }

        let workspaceID = settings.workspaceID ?? environmentValue(["ANTHROPIC_AWS_WORKSPACE_ID"])
        guard let workspaceID else {
            throw AIError.missingAPIKey(provider: providerID, environmentVariables: ["ANTHROPIC_AWS_WORKSPACE_ID"])
        }

        var headers = settings.headers
        headers["anthropic-version"] = headers["anthropic-version"] ?? "2023-06-01"
        headers["anthropic-workspace-id"] = headers["anthropic-workspace-id"] ?? workspaceID
        headers = withUserAgentSuffix(headers, "ai-sdk/anthropic-aws/1.0.3")

        let transport: any AITransport
        if let apiKey = settings.apiKey ?? environmentValue(["ANTHROPIC_AWS_API_KEY"]) {
            headers["x-api-key"] = headers["x-api-key"] ?? apiKey
            transport = settings.transport
        } else {
            guard let region else {
                throw AIError.missingAPIKey(provider: providerID, environmentVariables: ["AWS_REGION"])
            }
            let accessKeyID = settings.accessKeyID ?? environmentValue(["AWS_ACCESS_KEY_ID"])
            let secretAccessKey = settings.secretAccessKey ?? environmentValue(["AWS_SECRET_ACCESS_KEY"])
            guard let accessKeyID, let secretAccessKey else {
                throw AIError.missingAPIKey(provider: providerID, environmentVariables: ["ANTHROPIC_AWS_API_KEY", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"])
            }
            transport = AnthropicAWSSigV4Transport(
                region: region,
                credentials: AWSCredentials(
                    accessKeyID: accessKeyID,
                    secretAccessKey: secretAccessKey,
                    sessionToken: settings.sessionToken ?? environmentValue(["AWS_SESSION_TOKEN"])
                ),
                date: settings.date,
                underlying: settings.transport
            )
        }

        config = ModelHTTPConfig(
            providerID: "anthropic-aws.messages",
            baseURL: baseURL,
            headers: headers,
            transport: transport
        )
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        AnthropicLanguageModel(modelID: modelID, config: config)
    }

    public func messages(_ modelID: String) throws -> any LanguageModel {
        try languageModel(modelID)
    }

    public func files() -> any AIFileClient {
        MultipartFileClient(
            providerID: "anthropic-aws.messages",
            providerReferenceKey: "anthropic-aws",
            config: config,
            betaHeader: ("anthropic-beta", "files-api-2025-04-14")
        )
    }

    public func skills() -> any AISkillsClient {
        AnthropicSkillsClient(providerID: "anthropic-aws.skills", providerReferenceKey: "anthropic-aws", config: config)
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

private final class AnthropicAWSSigV4Transport: AITransport, @unchecked Sendable {
    private let region: String
    private let credentials: AWSCredentials
    private let date: @Sendable () -> Date
    private let underlying: any AITransport

    init(region: String, credentials: AWSCredentials, date: @escaping @Sendable () -> Date, underlying: any AITransport) {
        self.region = region
        self.credentials = credentials
        self.date = date
        self.underlying = underlying
    }

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        guard request.method.uppercased() == "POST", let body = request.body else {
            return try await underlying.send(request)
        }
        let signed = try AWSSigV4.sign(
            request: request,
            body: body,
            credentials: credentials,
            region: region,
            service: "aws-external-anthropic",
            date: date()
        )
        return try await underlying.send(signed)
    }
}
