import Foundation

public struct GatewayModelEntry: Equatable, Sendable {
    public var id: String
    public var name: String?
    public var modelType: String?
    public var provider: String?
    public var modelID: String?

    public init(id: String, name: String? = nil, modelType: String? = nil, provider: String? = nil, modelID: String? = nil) {
        self.id = id
        self.name = name
        self.modelType = modelType
        self.provider = provider
        self.modelID = modelID
    }
}

public struct GatewayCredits: Equatable, Sendable {
    public var balance: String
    public var totalUsed: String

    public init(balance: String, totalUsed: String) {
        self.balance = balance
        self.totalUsed = totalUsed
    }
}

public struct GatewaySpendReportParams: Equatable, Sendable {
    public var startDate: String
    public var endDate: String
    public var groupBy: String?
    public var datePart: String?
    public var userID: String?
    public var model: String?
    public var provider: String?
    public var credentialType: String?
    public var tags: [String]

    public init(
        startDate: String,
        endDate: String,
        groupBy: String? = nil,
        datePart: String? = nil,
        userID: String? = nil,
        model: String? = nil,
        provider: String? = nil,
        credentialType: String? = nil,
        tags: [String] = []
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.groupBy = groupBy
        self.datePart = datePart
        self.userID = userID
        self.model = model
        self.provider = provider
        self.credentialType = credentialType
        self.tags = tags
    }
}

public struct GatewaySpendReportRow: Equatable, Sendable {
    public var day: String?
    public var hour: String?
    public var user: String?
    public var model: String?
    public var tag: String?
    public var provider: String?
    public var credentialType: String?
    public var totalCost: Double
    public var marketCost: Double?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cachedInputTokens: Int?
    public var cacheCreationInputTokens: Int?
    public var reasoningTokens: Int?
    public var requestCount: Int?
}

public struct GatewaySpendReportResponse: Equatable, Sendable {
    public var results: [GatewaySpendReportRow]
}

public struct GatewayGenerationInfo: Equatable, Sendable {
    public var id: String
    public var totalCost: Double
    public var upstreamInferenceCost: Double
    public var usage: Double
    public var createdAt: String
    public var model: String
    public var isByok: Bool
    public var providerName: String
    public var streamed: Bool
    public var finishReason: String
    public var latency: Double
    public var generationTime: Double
    public var promptTokens: Int
    public var completionTokens: Int
    public var reasoningTokens: Int
    public var cachedTokens: Int
    public var cacheCreationTokens: Int
    public var billableWebSearchCalls: Int
}

public final class GatewayProvider: AIProvider, @unchecked Sendable {
    public let providerID = "gateway"
    public let supportedCapabilities: Set<ModelCapability> = Set(ModelCapability.allCases)
    private let config: ModelHTTPConfig

    public init(settings: ProviderSettings = ProviderSettings(), teamIDOrSlug: String? = nil) throws {
        var settings = settings
        if let teamIDOrSlug {
            settings.headers["x-vercel-ai-gateway-team"] = teamIDOrSlug
        }
        settings.headers["ai-gateway-protocol-version"] = settings.headers["ai-gateway-protocol-version"] ?? "0.0.1"
        settings.headers["ai-gateway-auth-method"] = settings.headers["ai-gateway-auth-method"] ?? "api-key"
        let headers = try OpenAICompatibleProvider.buildHeaders(providerID: providerID, authorization: .bearer(environmentVariables: ["AI_GATEWAY_API_KEY"]), settings: settings)
        config = ModelHTTPConfig(
            providerID: providerID,
            baseURL: settings.baseURL ?? "https://ai-gateway.vercel.sh/v4/ai",
            headers: headers,
            transport: settings.transport,
            includeUsage: settings.includeUsage,
            queryParams: settings.queryParams,
            supportsStructuredOutputs: settings.supportsStructuredOutputs,
            maxEmbeddingsPerCall: settings.maxEmbeddingsPerCall,
            transformRequestBody: settings.transformRequestBody
        )
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        GatewayLanguageModel(modelID: modelID, config: config)
    }

    public func embeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        GatewayEmbeddingModel(modelID: modelID, config: config)
    }

    public func imageModel(_ modelID: String) throws -> any ImageModel {
        GatewayImageModel(modelID: modelID, config: config)
    }

    public func transcriptionModel(_ modelID: String) throws -> any TranscriptionModel {
        GatewayTranscriptionModel(modelID: modelID, config: config)
    }

    public func speechModel(_ modelID: String) throws -> any SpeechModel {
        GatewaySpeechModel(modelID: modelID, config: config)
    }

    public func videoModel(_ modelID: String) throws -> any VideoModel {
        GatewayVideoModel(modelID: modelID, config: config)
    }

    public func rerankingModel(_ modelID: String) throws -> any RerankingModel {
        GatewayRerankingModel(modelID: modelID, config: config)
    }

    public func availableModels() async throws -> [GatewayModelEntry] {
        let response = try await config.transport.send(AIHTTPRequest(method: "GET", url: try requireURL("\(config.baseURL)/config"), headers: config.headers))
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
        }
        let raw = try response.jsonValue()
        return raw["models"]?.arrayValue?.compactMap { item in
            guard let id = item["id"]?.stringValue else { return nil }
            return GatewayModelEntry(
                id: id,
                name: item["name"]?.stringValue,
                modelType: item["modelType"]?.stringValue ?? item["model_type"]?.stringValue,
                provider: item["specification"]?["provider"]?.stringValue,
                modelID: item["specification"]?["modelId"]?.stringValue
            )
        } ?? []
    }

    public func getAvailableModels() async throws -> [GatewayModelEntry] {
        try await availableModels()
    }

    public func credits() async throws -> GatewayCredits {
        let response = try await config.transport.send(AIHTTPRequest(method: "GET", url: try gatewayOriginURL(baseURL: config.baseURL, path: "/v1/credits"), headers: config.headers))
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
        }
        let raw = try response.jsonValue()
        return GatewayCredits(balance: raw["balance"]?.stringValue ?? "", totalUsed: raw["total_used"]?.stringValue ?? raw["totalUsed"]?.stringValue ?? "")
    }

    public func getCredits() async throws -> GatewayCredits {
        try await credits()
    }

    public func getSpendReport(_ params: GatewaySpendReportParams) async throws -> GatewaySpendReportResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "start_date", value: params.startDate),
            URLQueryItem(name: "end_date", value: params.endDate)
        ]
        appendQueryItem("group_by", params.groupBy, to: &queryItems)
        appendQueryItem("date_part", params.datePart, to: &queryItems)
        appendQueryItem("user_id", params.userID, to: &queryItems)
        appendQueryItem("model", params.model, to: &queryItems)
        appendQueryItem("provider", params.provider, to: &queryItems)
        appendQueryItem("credential_type", params.credentialType, to: &queryItems)
        if !params.tags.isEmpty {
            queryItems.append(URLQueryItem(name: "tags", value: params.tags.joined(separator: ",")))
        }

        let response = try await config.transport.send(AIHTTPRequest(
            method: "GET",
            url: try gatewayOriginURL(baseURL: config.baseURL, path: "/v1/report", queryItems: queryItems),
            headers: config.headers
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
        }
        let raw = try response.jsonValue()
        return GatewaySpendReportResponse(results: raw["results"]?.arrayValue?.map(gatewaySpendReportRow) ?? [])
    }

    public func getGenerationInfo(id: String) async throws -> GatewayGenerationInfo {
        let response = try await config.transport.send(AIHTTPRequest(
            method: "GET",
            url: try gatewayOriginURL(baseURL: config.baseURL, path: "/v1/generation", queryItems: [URLQueryItem(name: "id", value: id)]),
            headers: config.headers
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
        }
        let data = try response.jsonValue()["data"] ?? .object([:])
        return GatewayGenerationInfo(
            id: data["id"]?.stringValue ?? "",
            totalCost: data["total_cost"]?.doubleValue ?? 0,
            upstreamInferenceCost: data["upstream_inference_cost"]?.doubleValue ?? 0,
            usage: data["usage"]?.doubleValue ?? 0,
            createdAt: data["created_at"]?.stringValue ?? "",
            model: data["model"]?.stringValue ?? "",
            isByok: data["is_byok"]?.boolValue ?? false,
            providerName: data["provider_name"]?.stringValue ?? "",
            streamed: data["streamed"]?.boolValue ?? false,
            finishReason: data["finish_reason"]?.stringValue ?? "",
            latency: data["latency"]?.doubleValue ?? 0,
            generationTime: data["generation_time"]?.doubleValue ?? 0,
            promptTokens: data["native_tokens_prompt"]?.intValue ?? 0,
            completionTokens: data["native_tokens_completion"]?.intValue ?? 0,
            reasoningTokens: data["native_tokens_reasoning"]?.intValue ?? 0,
            cachedTokens: data["native_tokens_cached"]?.intValue ?? 0,
            cacheCreationTokens: data["native_tokens_cache_creation"]?.intValue ?? 0,
            billableWebSearchCalls: data["billable_web_search_calls"]?.intValue ?? 0
        )
    }
}

private func gatewaySpendReportRow(_ raw: JSONValue) -> GatewaySpendReportRow {
    GatewaySpendReportRow(
        day: raw["day"]?.stringValue,
        hour: raw["hour"]?.stringValue,
        user: raw["user"]?.stringValue,
        model: raw["model"]?.stringValue,
        tag: raw["tag"]?.stringValue,
        provider: raw["provider"]?.stringValue,
        credentialType: raw["credential_type"]?.stringValue,
        totalCost: raw["total_cost"]?.doubleValue ?? raw["totalCost"]?.doubleValue ?? 0,
        marketCost: raw["market_cost"]?.doubleValue ?? raw["marketCost"]?.doubleValue,
        inputTokens: raw["input_tokens"]?.intValue ?? raw["inputTokens"]?.intValue,
        outputTokens: raw["output_tokens"]?.intValue ?? raw["outputTokens"]?.intValue,
        cachedInputTokens: raw["cached_input_tokens"]?.intValue ?? raw["cachedInputTokens"]?.intValue,
        cacheCreationInputTokens: raw["cache_creation_input_tokens"]?.intValue ?? raw["cacheCreationInputTokens"]?.intValue,
        reasoningTokens: raw["reasoning_tokens"]?.intValue ?? raw["reasoningTokens"]?.intValue,
        requestCount: raw["request_count"]?.intValue ?? raw["requestCount"]?.intValue
    )
}

private func gatewayOriginURL(baseURL: String, path: String, queryItems: [URLQueryItem] = []) throws -> URL {
    guard let base = URL(string: baseURL), let scheme = base.scheme, let host = base.host else {
        throw AIError.invalidURL(baseURL)
    }
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.port = base.port
    components.path = path
    components.queryItems = queryItems.isEmpty ? nil : queryItems
    guard let url = components.url else {
        throw AIError.invalidURL("\(scheme)://\(host)\(path)")
    }
    return url
}

private func appendQueryItem(_ name: String, _ value: String?, to queryItems: inout [URLQueryItem]) {
    if let value {
        queryItems.append(URLQueryItem(name: name, value: value))
    }
}
