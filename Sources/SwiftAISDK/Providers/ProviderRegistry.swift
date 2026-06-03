import CryptoKit
import Foundation

public enum AIProviders {
    public static func openAI(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        var settings = settings
        settings.baseURL = settings.baseURL ?? environmentValue(["OPENAI_BASE_URL"])
        let providerID = settings.name ?? "openai"
        if let organization = settings.organization {
            settings.headers["OpenAI-Organization"] = settings.headers["OpenAI-Organization"] ?? organization
        }
        if let project = settings.project {
            settings.headers["OpenAI-Project"] = settings.headers["OpenAI-Project"] ?? project
        }
        return try OpenAICompatibleProvider(providerID: providerID, defaultBaseURL: "https://api.openai.com/v1", authorization: .bearer(environmentVariables: ["OPENAI_API_KEY"]), supportedCapabilities: [.language, .completion, .embedding, .image, .transcription, .speech], settings: settings, routesLikeOpenAI: true, userAgentSuffix: "ai-sdk/openai/3.0.67")
    }

    public static func openai(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try openAI(settings: settings)
    }

    public static func anthropic(settings: ProviderSettings = ProviderSettings()) throws -> AnthropicProvider {
        try AnthropicProvider(settings: settings)
    }

    public static func anthropicAWS(settings: AnthropicAWSProviderSettings = AnthropicAWSProviderSettings()) throws -> AnthropicAWSProvider {
        try AnthropicAWSProvider(settings: settings)
    }

    public static func anthropicAws(settings: AnthropicAWSProviderSettings = AnthropicAWSProviderSettings()) throws -> AnthropicAWSProvider {
        try anthropicAWS(settings: settings)
    }

    public static func google(settings: ProviderSettings = ProviderSettings()) throws -> GoogleGenerativeAIProvider {
        try GoogleGenerativeAIProvider(settings: settings)
    }

    public static func googleVertex(settings: GoogleVertexProviderSettings = GoogleVertexProviderSettings()) throws -> GoogleVertexProvider {
        try GoogleVertexProvider(settings: settings)
    }

    public static func googleVertexMaaS(project: String? = nil, location: String? = nil, settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(
            providerID: "googleVertex.maas",
            defaultBaseURL: googleVertexOpenAIBaseURL(project: project, location: location),
            authorization: .bearer(environmentVariables: ["GOOGLE_VERTEX_ACCESS_TOKEN", "GOOGLE_ACCESS_TOKEN"]),
            supportedCapabilities: [.language, .completion, .embedding, .image],
            settings: settings
        )
    }

    public static func googleVertexXAI(project: String? = nil, location: String? = nil, settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(
            providerID: "googleVertex.xai",
            defaultBaseURL: googleVertexOpenAIBaseURL(project: project, location: location),
            authorization: .bearer(environmentVariables: ["GOOGLE_VERTEX_ACCESS_TOKEN", "GOOGLE_ACCESS_TOKEN"]),
            supportedCapabilities: [.language],
            settings: settings
        )
    }

    public static func googleVertexAnthropic(project: String? = nil, location: String? = nil, settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(
            providerID: "googleVertex.anthropic",
            defaultBaseURL: googleVertexAnthropicBaseURL(project: project, location: location),
            authorization: .bearer(environmentVariables: ["GOOGLE_VERTEX_ACCESS_TOKEN", "GOOGLE_ACCESS_TOKEN"]),
            supportedCapabilities: [.language],
            settings: settings
        )
    }

    public static func azure(resourceName: String? = nil, apiVersion: String = "v1", useDeploymentBasedURLs: Bool = false, tokenProvider: AzureOpenAITokenProvider? = nil, settings: ProviderSettings = ProviderSettings()) throws -> AzureOpenAIProvider {
        try AzureOpenAIProvider(resourceName: resourceName, apiVersion: apiVersion, useDeploymentBasedURLs: useDeploymentBasedURLs, tokenProvider: tokenProvider, settings: settings)
    }

    public static func azureOpenAI(resourceName: String? = nil, apiVersion: String = "v1", useDeploymentBasedURLs: Bool = false, tokenProvider: AzureOpenAITokenProvider? = nil, settings: ProviderSettings = ProviderSettings()) throws -> AzureOpenAIProvider {
        try azure(resourceName: resourceName, apiVersion: apiVersion, useDeploymentBasedURLs: useDeploymentBasedURLs, tokenProvider: tokenProvider, settings: settings)
    }

    public static func azureOpenai(resourceName: String? = nil, apiVersion: String = "v1", useDeploymentBasedURLs: Bool = false, tokenProvider: AzureOpenAITokenProvider? = nil, settings: ProviderSettings = ProviderSettings()) throws -> AzureOpenAIProvider {
        try azureOpenAI(resourceName: resourceName, apiVersion: apiVersion, useDeploymentBasedURLs: useDeploymentBasedURLs, tokenProvider: tokenProvider, settings: settings)
    }

    public static func gateway(settings: ProviderSettings = ProviderSettings(), teamIDOrSlug: String? = nil) throws -> GatewayProvider {
        try GatewayProvider(settings: settings, teamIDOrSlug: teamIDOrSlug)
    }

    public static func openAICompatible(
        name: String,
        baseURL: String,
        apiKey: String? = nil,
        headers: [String: String] = [:],
        queryParams: [String: String] = [:],
        transport: any AITransport = URLSessionTransport.shared,
        includeUsage: Bool = false,
        supportsStructuredOutputs: Bool = false,
        maxEmbeddingsPerCall: Int? = nil,
        transformRequestBody: (@Sendable ([String: JSONValue]) -> [String: JSONValue])? = nil
    ) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(
            providerID: name,
            defaultBaseURL: baseURL,
            authorization: apiKey == nil ? .none : .bearer(environmentVariables: []),
            supportedCapabilities: [.language, .completion, .embedding, .image],
            settings: ProviderSettings(
                apiKey: apiKey,
                headers: headers,
                queryParams: queryParams,
                transport: transport,
                includeUsage: includeUsage,
                supportsStructuredOutputs: supportsStructuredOutputs,
                maxEmbeddingsPerCall: maxEmbeddingsPerCall,
                transformRequestBody: transformRequestBody
            ),
            userAgentSuffix: "ai-sdk/openai-compatible/2.0.48",
            usesOpenAICompatibleSurfaceIDs: true
        )
    }

    public static func openaiCompatible(
        name: String,
        baseURL: String,
        apiKey: String? = nil,
        headers: [String: String] = [:],
        queryParams: [String: String] = [:],
        transport: any AITransport = URLSessionTransport.shared,
        includeUsage: Bool = false,
        supportsStructuredOutputs: Bool = false,
        maxEmbeddingsPerCall: Int? = nil,
        transformRequestBody: (@Sendable ([String: JSONValue]) -> [String: JSONValue])? = nil
    ) throws -> OpenAICompatibleProvider {
        try openAICompatible(
            name: name,
            baseURL: baseURL,
            apiKey: apiKey,
            headers: headers,
            queryParams: queryParams,
            transport: transport,
            includeUsage: includeUsage,
            supportsStructuredOutputs: supportsStructuredOutputs,
            maxEmbeddingsPerCall: maxEmbeddingsPerCall,
            transformRequestBody: transformRequestBody
        )
    }

    public static func mistral(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "mistral", defaultBaseURL: "https://api.mistral.ai/v1", authorization: .bearer(environmentVariables: ["MISTRAL_API_KEY"]), supportedCapabilities: [.language, .embedding], settings: settings)
    }

    public static func xAI(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "xai", defaultBaseURL: "https://api.x.ai/v1", authorization: .bearer(environmentVariables: ["XAI_API_KEY"]), supportedCapabilities: [.language, .image, .video], settings: settings)
    }

    public static func xai(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try xAI(settings: settings)
    }

    public static func deepSeek(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "deepseek", defaultBaseURL: "https://api.deepseek.com", authorization: .bearer(environmentVariables: ["DEEPSEEK_API_KEY"]), supportedCapabilities: [.language], settings: settings)
    }

    public static func deepseek(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try deepSeek(settings: settings)
    }

    public static func togetherAI(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "togetherai", defaultBaseURL: "https://api.together.xyz/v1", authorization: .bearer(environmentVariables: ["TOGETHER_API_KEY", "TOGETHER_AI_API_KEY"]), supportedCapabilities: [.language, .completion, .embedding, .image, .reranking], settings: settings)
    }

    public static func togetherai(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try togetherAI(settings: settings)
    }

    public static func cohere(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "cohere", defaultBaseURL: "https://api.cohere.com/v2", authorization: .bearer(environmentVariables: ["COHERE_API_KEY"]), supportedCapabilities: [.language, .embedding, .reranking], settings: settings)
    }

    public static func amazonBedrock(settings: AmazonBedrockProviderSettings = AmazonBedrockProviderSettings()) throws -> AmazonBedrockProvider {
        try AmazonBedrockProvider(settings: settings)
    }

    public static func amazonBedrockAnthropic(settings: AmazonBedrockProviderSettings = AmazonBedrockProviderSettings()) throws -> AmazonBedrockAnthropicProvider {
        try AmazonBedrockAnthropicProvider(settings: settings)
    }

    public static func bedrockMantle(settings: AmazonBedrockProviderSettings = AmazonBedrockProviderSettings()) throws -> BedrockMantleProvider {
        try BedrockMantleProvider(settings: settings)
    }

    public static func amazonBedrockMantle(settings: AmazonBedrockProviderSettings = AmazonBedrockProviderSettings()) throws -> BedrockMantleProvider {
        try bedrockMantle(settings: settings)
    }

    public static func groq(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "groq", defaultBaseURL: "https://api.groq.com/openai/v1", authorization: .bearer(environmentVariables: ["GROQ_API_KEY"]), supportedCapabilities: [.language, .transcription], settings: settings)
    }

    public static func perplexity(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        let headers = try perplexityHeaders(settings: settings)
        let config = ModelHTTPConfig(
            providerID: "perplexity",
            baseURL: settings.baseURL ?? "https://api.perplexity.ai",
            modelURL: settings.modelURL,
            headers: headers,
            transport: settings.transport,
            includeUsage: settings.includeUsage,
            queryParams: settings.queryParams,
            supportsStructuredOutputs: settings.supportsStructuredOutputs,
            maxEmbeddingsPerCall: settings.maxEmbeddingsPerCall,
            transformRequestBody: settings.transformRequestBody
        )
        return OpenAICompatibleProvider(providerID: "perplexity", supportedCapabilities: [.language], config: config)
    }

    public static func fireworks(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "fireworks", defaultBaseURL: "https://api.fireworks.ai/inference/v1", authorization: .bearer(environmentVariables: ["FIREWORKS_API_KEY"]), supportedCapabilities: [.language, .completion, .embedding, .image], settings: settings)
    }

    public static func deepInfra(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "deepinfra", defaultBaseURL: "https://api.deepinfra.com/v1", authorization: .bearer(environmentVariables: ["DEEPINFRA_API_KEY"]), supportedCapabilities: [.language, .completion, .embedding, .image], settings: settings)
    }

    public static func deepinfra(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try deepInfra(settings: settings)
    }

    public static func baseten(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "baseten", defaultBaseURL: "https://inference.baseten.co/v1", authorization: .bearer(environmentVariables: ["BASETEN_API_KEY"]), supportedCapabilities: [.language, .embedding], settings: settings)
    }

    public static func cerebras(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "cerebras", defaultBaseURL: "https://api.cerebras.ai/v1", authorization: .bearer(environmentVariables: ["CEREBRAS_API_KEY"]), supportedCapabilities: [.language], settings: settings)
    }

    public static func vercel(settings: ProviderSettings = ProviderSettings()) throws -> VercelProvider {
        try VercelProvider(settings: settings)
    }

    public static func alibaba(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "alibaba", defaultBaseURL: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", authorization: .bearer(environmentVariables: ["ALIBABA_API_KEY", "DASHSCOPE_API_KEY"]), supportedCapabilities: [.language, .video], settings: settings)
    }

    public static func moonshotAI(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        var moonshotSettings = settings
        moonshotSettings.includeUsage = true
        return try OpenAICompatibleProvider(providerID: "moonshotai", defaultBaseURL: "https://api.moonshot.ai/v1", authorization: .bearer(environmentVariables: ["MOONSHOT_API_KEY"]), supportedCapabilities: [.language], settings: moonshotSettings)
    }

    public static func moonshotai(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try moonshotAI(settings: settings)
    }

    public static func huggingFace(settings: ProviderSettings = ProviderSettings()) throws -> HuggingFaceProvider {
        try HuggingFaceProvider(settings: settings)
    }

    public static func huggingface(settings: ProviderSettings = ProviderSettings()) throws -> HuggingFaceProvider {
        try huggingFace(settings: settings)
    }

    public static func openResponses(name: String, url: String, settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        var headers: [String: String] = [:]
        if let apiKey = settings.apiKey {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        headers.merge(settings.headers) { _, custom in custom }
        headers = withUserAgentSuffix(headers, "ai-sdk/open-responses/1.0.16")
        let endpoint = try requireURL(url)
        let base = "\(endpoint.scheme ?? "https")://\(endpoint.host ?? "")"
        let config = ModelHTTPConfig(providerID: "\(name).responses", baseURL: base, headers: headers, transport: settings.transport, includeUsage: settings.includeUsage, queryParams: settings.queryParams, supportsStructuredOutputs: settings.supportsStructuredOutputs, maxEmbeddingsPerCall: settings.maxEmbeddingsPerCall, transformRequestBody: settings.transformRequestBody, responsesRequestMode: .openResponses(providerOptionsName: name)) { _, _ in endpoint }
        return OpenAICompatibleProvider(providerID: "\(name).responses", supportedCapabilities: [.language], config: config)
    }

    public static func replicate(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "replicate", defaultBaseURL: "https://api.replicate.com/v1", authorization: .bearer(environmentVariables: ["REPLICATE_API_TOKEN"]), supportedCapabilities: [.image, .video], settings: settings)
    }

    public static func fal(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "fal", defaultBaseURL: "https://fal.run", authorization: .apiKeyHeader(name: "Authorization", prefix: "Key", environmentVariables: ["FAL_API_KEY", "FAL_KEY"]), supportedCapabilities: [.image, .transcription, .speech, .video], settings: settings)
    }

    public static func deepgram(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "deepgram", defaultBaseURL: "https://api.deepgram.com", authorization: .token(environmentVariables: ["DEEPGRAM_API_KEY"]), supportedCapabilities: [.transcription, .speech], settings: settings)
    }

    public static func assemblyAI(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "assemblyai", defaultBaseURL: "https://api.assemblyai.com", authorization: .apiKeyHeader(name: "authorization", environmentVariables: ["ASSEMBLYAI_API_KEY"]), supportedCapabilities: [.transcription], settings: settings)
    }

    public static func assemblyai(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try assemblyAI(settings: settings)
    }

    public static func elevenLabs(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "elevenlabs", defaultBaseURL: "https://api.elevenlabs.io", authorization: .apiKeyHeader(name: "xi-api-key", environmentVariables: ["ELEVENLABS_API_KEY"]), supportedCapabilities: [.transcription, .speech], settings: settings)
    }

    public static func elevenlabs(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try elevenLabs(settings: settings)
    }

    public static func revAI(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "revai", defaultBaseURL: "https://api.rev.ai", authorization: .bearer(environmentVariables: ["REVAI_API_KEY"]), supportedCapabilities: [.transcription], settings: settings)
    }

    public static func revai(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try revAI(settings: settings)
    }

    public static func gladia(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "gladia", defaultBaseURL: "https://api.gladia.io", authorization: .apiKeyHeader(name: "x-gladia-key", environmentVariables: ["GLADIA_API_KEY"]), supportedCapabilities: [.transcription], settings: settings)
    }

    public static func hume(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "hume", defaultBaseURL: "https://api.hume.ai", authorization: .apiKeyHeader(name: "X-Hume-Api-Key", environmentVariables: ["HUME_API_KEY"]), supportedCapabilities: [.speech], settings: settings)
    }

    public static func lmnt(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "lmnt", defaultBaseURL: "https://api.lmnt.com", authorization: .apiKeyHeader(name: "x-api-key", environmentVariables: ["LMNT_API_KEY"]), supportedCapabilities: [.speech], settings: settings)
    }

    public static func blackForestLabs(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "black-forest-labs", defaultBaseURL: "https://api.bfl.ai/v1", authorization: .apiKeyHeader(name: "x-key", environmentVariables: ["BFL_API_KEY", "BLACK_FOREST_LABS_API_KEY"]), supportedCapabilities: [.image], settings: settings)
    }

    public static func prodia(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "prodia", defaultBaseURL: "https://inference.prodia.com/v2", authorization: .bearer(environmentVariables: ["PRODIA_TOKEN", "PRODIA_API_KEY"]), supportedCapabilities: [.language, .image, .video], settings: settings)
    }

    public static func luma(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "luma", defaultBaseURL: "https://api.lumalabs.ai", authorization: .bearer(environmentVariables: ["LUMA_API_KEY"]), supportedCapabilities: [.image], settings: settings)
    }

    public static func klingAI(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        var headers = settings.headers
        if headers["Authorization"] == nil {
            if let apiKey = settings.apiKey ?? environmentValue(["KLINGAI_API_KEY"]) {
                headers["Authorization"] = "Bearer \(apiKey)"
            } else if let accessKey = environmentValue(["KLINGAI_ACCESS_KEY"]),
                      let secretKey = environmentValue(["KLINGAI_SECRET_KEY"]) {
                headers["Authorization"] = "Bearer \(try klingAIJWT(accessKey: accessKey, secretKey: secretKey))"
            } else {
                throw AIError.missingAPIKey(provider: "klingai", environmentVariables: ["KLINGAI_API_KEY", "KLINGAI_ACCESS_KEY", "KLINGAI_SECRET_KEY"])
            }
        }
        return try OpenAICompatibleProvider(
            providerID: "klingai",
            defaultBaseURL: "https://api-singapore.klingai.com",
            authorization: .none,
            supportedCapabilities: [.video],
            settings: ProviderSettings(baseURL: settings.baseURL, headers: headers, transport: settings.transport)
        )
    }

    public static func klingai(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try klingAI(settings: settings)
    }

    public static func byteDance(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "bytedance", defaultBaseURL: "https://ark.ap-southeast.bytepluses.com/api/v3", authorization: .bearer(environmentVariables: ["ARK_API_KEY"]), supportedCapabilities: [.video], settings: settings)
    }

    public static func bytedance(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try byteDance(settings: settings)
    }

    public static func voyage(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(providerID: "voyage", defaultBaseURL: "https://api.voyageai.com/v1", authorization: .bearer(environmentVariables: ["VOYAGE_API_KEY"]), supportedCapabilities: [.embedding, .reranking], settings: settings)
    }

    public static func quiverAI(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        var settings = settings
        settings.baseURL = settings.baseURL ?? environmentValue(["QUIVERAI_BASE_URL"])
        return try OpenAICompatibleProvider(providerID: "quiverai", defaultBaseURL: "https://api.quiver.ai/v1", authorization: .bearer(environmentVariables: ["QUIVERAI_API_KEY"]), supportedCapabilities: [.image], settings: settings)
    }

    public static func quiverai(settings: ProviderSettings = ProviderSettings()) throws -> OpenAICompatibleProvider {
        try quiverAI(settings: settings)
    }
}

private func googleVertexOpenAIBaseURL(project: String?, location: String?) throws -> String {
    guard let project = project ?? environmentValue(["GOOGLE_VERTEX_PROJECT"]) else {
        throw AIError.invalidURL("Google Vertex OpenAI-compatible mode requires project or GOOGLE_VERTEX_PROJECT.")
    }
    let location = location ?? environmentValue(["GOOGLE_VERTEX_LOCATION"]) ?? "global"
    return "https://aiplatform.googleapis.com/v1/projects/\(project)/locations/\(location)/endpoints/openapi"
}

private func googleVertexAnthropicBaseURL(project: String?, location: String?) throws -> String {
    guard let project = project ?? environmentValue(["GOOGLE_VERTEX_PROJECT"]) else {
        throw AIError.invalidURL("Google Vertex Anthropic mode requires project or GOOGLE_VERTEX_PROJECT.")
    }
    let location = location ?? environmentValue(["GOOGLE_VERTEX_LOCATION"]) ?? "global"
    let host = googleVertexRegionalHost(location: location)
    return "https://\(host)/v1/projects/\(project)/locations/\(location)/publishers/anthropic/models"
}

private func googleVertexRegionalHost(location: String) -> String {
    if location == "global" {
        return "aiplatform.googleapis.com"
    }
    if location == "eu" || location == "us" {
        return "aiplatform.\(location).rep.googleapis.com"
    }
    return "\(location)-aiplatform.googleapis.com"
}

private func perplexityHeaders(settings: ProviderSettings) throws -> [String: String] {
    var headers = settings.headers
    let key = settings.apiKey ?? environmentValue(["PERPLEXITY_API_KEY"])
    guard let key else {
        throw AIError.missingAPIKey(provider: "perplexity", environmentVariables: ["PERPLEXITY_API_KEY"])
    }
    headers["Authorization"] = headers["Authorization"] ?? "Bearer \(key)"
    return withUserAgentSuffix(headers, "ai-sdk/perplexity/3.0.33")
}

private func klingAIJWT(accessKey: String, secretKey: String, now: Date = Date()) throws -> String {
    let issuedAt = Int(now.timeIntervalSince1970)
    let header: JSONValue = .object(["alg": .string("HS256"), "typ": .string("JWT")])
    let payload: JSONValue = .object([
        "iss": .string(accessKey),
        "exp": .number(Double(issuedAt + 1800)),
        "nbf": .number(Double(issuedAt - 5))
    ])
    let signingInput = "\(base64URL(try encodeJSONBody(header))).\(base64URL(try encodeJSONBody(payload)))"
    let signature = HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: SymmetricKey(data: Data(secretKey.utf8)))
    return "\(signingInput).\(base64URL(Data(signature)))"
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
