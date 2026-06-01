import CryptoKit
import Foundation

public struct AmazonBedrockProviderSettings: Sendable {
    public var region: String?
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

struct AWSCredentials: Sendable {
    var accessKeyID: String
    var secretAccessKey: String
    var sessionToken: String?
}

public final class AmazonBedrockProvider: AIProvider, @unchecked Sendable {
    public let providerID = "amazon-bedrock"
    public let supportedCapabilities: Set<ModelCapability> = [.language, .embedding, .image, .reranking]
    private let runtimeConfig: BedrockRuntimeConfig
    private let agentRuntimeConfig: BedrockRuntimeConfig

    public init(settings: AmazonBedrockProviderSettings = AmazonBedrockProviderSettings()) throws {
        let region = settings.region ?? environmentValue(["AWS_REGION", "AWS_DEFAULT_REGION"]) ?? "us-east-1"
        let runtimeBaseURL = settings.baseURL ?? "https://bedrock-runtime.\(region).amazonaws.com"
        let agentBaseURL = settings.baseURL ?? "https://bedrock-agent-runtime.\(region).amazonaws.com"

        let auth: BedrockAuth
        let rawAPIKey = settings.apiKey ?? environmentValue(["AWS_BEARER_TOKEN_BEDROCK"])
        if let apiKey = rawAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty {
            auth = .bearer(apiKey)
        } else {
            let accessKeyID = settings.accessKeyID ?? environmentValue(["AWS_ACCESS_KEY_ID"])
            let secretAccessKey = settings.secretAccessKey ?? environmentValue(["AWS_SECRET_ACCESS_KEY"])
            guard let accessKeyID, let secretAccessKey else {
                throw AIError.missingAPIKey(provider: providerID, environmentVariables: ["AWS_BEARER_TOKEN_BEDROCK", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"])
            }
            auth = .sigV4(AWSCredentials(
                accessKeyID: accessKeyID,
                secretAccessKey: secretAccessKey,
                sessionToken: settings.sessionToken ?? environmentValue(["AWS_SESSION_TOKEN"])
            ))
        }

        var headers = settings.headers
        headers["user-agent"] = headers["user-agent"] ?? userAgent(providerID)
        runtimeConfig = BedrockRuntimeConfig(providerID: providerID, region: region, service: "bedrock", baseURL: runtimeBaseURL, headers: headers, auth: auth, transport: settings.transport, date: settings.date)
        agentRuntimeConfig = BedrockRuntimeConfig(providerID: providerID, region: region, service: "bedrock", baseURL: agentBaseURL, headers: headers, auth: auth, transport: settings.transport, date: settings.date)
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        AmazonBedrockLanguageModel(modelID: modelID, config: runtimeConfig)
    }

    public func embeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        AmazonBedrockEmbeddingModel(modelID: modelID, config: runtimeConfig)
    }

    public func imageModel(_ modelID: String) throws -> any ImageModel {
        AmazonBedrockImageModel(modelID: modelID, config: runtimeConfig)
    }

    public func rerankingModel(_ modelID: String) throws -> any RerankingModel {
        AmazonBedrockRerankingModel(modelID: modelID, config: agentRuntimeConfig)
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
}

public final class AmazonBedrockAnthropicProvider: AIProvider, @unchecked Sendable {
    public let providerID = "bedrock.anthropic"
    public let supportedCapabilities: Set<ModelCapability> = [.language]
    private let runtimeConfig: BedrockRuntimeConfig

    public init(settings: AmazonBedrockProviderSettings = AmazonBedrockProviderSettings()) throws {
        let region = settings.region ?? environmentValue(["AWS_REGION", "AWS_DEFAULT_REGION"]) ?? "us-east-1"
        let runtimeBaseURL = settings.baseURL ?? "https://bedrock-runtime.\(region).amazonaws.com"

        let auth: BedrockAuth
        let rawAPIKey = settings.apiKey ?? environmentValue(["AWS_BEARER_TOKEN_BEDROCK"])
        if let apiKey = rawAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty {
            auth = .bearer(apiKey)
        } else {
            let accessKeyID = settings.accessKeyID ?? environmentValue(["AWS_ACCESS_KEY_ID"])
            let secretAccessKey = settings.secretAccessKey ?? environmentValue(["AWS_SECRET_ACCESS_KEY"])
            guard let accessKeyID, let secretAccessKey else {
                throw AIError.missingAPIKey(provider: providerID, environmentVariables: ["AWS_BEARER_TOKEN_BEDROCK", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"])
            }
            auth = .sigV4(AWSCredentials(
                accessKeyID: accessKeyID,
                secretAccessKey: secretAccessKey,
                sessionToken: settings.sessionToken ?? environmentValue(["AWS_SESSION_TOKEN"])
            ))
        }

        var headers = settings.headers
        headers["user-agent"] = headers["user-agent"] ?? userAgent(providerID)
        runtimeConfig = BedrockRuntimeConfig(providerID: providerID, region: region, service: "bedrock", baseURL: runtimeBaseURL, headers: headers, auth: auth, transport: settings.transport, date: settings.date)
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        AmazonBedrockAnthropicLanguageModel(modelID: modelID, config: runtimeConfig)
    }

    public func messages(_ modelID: String) throws -> any LanguageModel {
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

public final class BedrockMantleProvider: AIProvider, @unchecked Sendable {
    public let providerID = "bedrock-mantle"
    public let supportedCapabilities: Set<ModelCapability> = [.language]
    private let chatProvider: OpenAICompatibleProvider
    private let responsesProvider: OpenAICompatibleProvider

    public init(settings: AmazonBedrockProviderSettings = AmazonBedrockProviderSettings()) throws {
        let region = settings.region ?? environmentValue(["AWS_REGION", "AWS_DEFAULT_REGION"]) ?? "us-east-1"
        let baseURL = settings.baseURL ?? "https://bedrock-mantle.\(region).api.aws/v1"

        let auth: BedrockAuth
        let rawAPIKey = settings.apiKey ?? environmentValue(["AWS_BEARER_TOKEN_BEDROCK"])
        if let apiKey = rawAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty {
            auth = .bearer(apiKey)
        } else {
            let accessKeyID = settings.accessKeyID ?? environmentValue(["AWS_ACCESS_KEY_ID"])
            let secretAccessKey = settings.secretAccessKey ?? environmentValue(["AWS_SECRET_ACCESS_KEY"])
            guard let accessKeyID, let secretAccessKey else {
                throw AIError.missingAPIKey(provider: providerID, environmentVariables: ["AWS_BEARER_TOKEN_BEDROCK", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"])
            }
            auth = .sigV4(AWSCredentials(
                accessKeyID: accessKeyID,
                secretAccessKey: secretAccessKey,
                sessionToken: settings.sessionToken ?? environmentValue(["AWS_SESSION_TOKEN"])
            ))
        }

        var headers = settings.headers
        headers["user-agent"] = headers["user-agent"] ?? userAgent("amazon-bedrock")
        let transport = BedrockSigningTransport(
            region: region,
            service: "bedrock-mantle",
            auth: auth,
            transport: settings.transport,
            date: settings.date
        )
        let chatConfig = ModelHTTPConfig(
            providerID: "bedrock-mantle.chat",
            baseURL: baseURL,
            headers: headers,
            transport: transport
        )
        let responsesConfig = ModelHTTPConfig(
            providerID: "bedrock-mantle.responses",
            baseURL: baseURL,
            headers: headers,
            transport: transport
        )
        chatProvider = OpenAICompatibleProvider(providerID: "bedrock-mantle.chat", supportedCapabilities: [.language], config: chatConfig)
        responsesProvider = OpenAICompatibleProvider(providerID: "bedrock-mantle.responses", supportedCapabilities: [.language], config: responsesConfig)
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        try chat(modelID)
    }

    public func chat(_ modelID: String) throws -> any LanguageModel {
        try chatProvider.chatModel(modelID)
    }

    public func responses(_ modelID: String) throws -> any LanguageModel {
        try responsesProvider.responsesModel(modelID)
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

enum BedrockAuth: Sendable {
    case bearer(String)
    case sigV4(AWSCredentials)
}

private final class BedrockSigningTransport: AITransport, @unchecked Sendable {
    private let region: String
    private let service: String
    private let auth: BedrockAuth
    private let transport: any AITransport
    private let date: @Sendable () -> Date

    init(region: String, service: String, auth: BedrockAuth, transport: any AITransport, date: @escaping @Sendable () -> Date) {
        self.region = region
        self.service = service
        self.auth = auth
        self.transport = transport
        self.date = date
    }

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        switch auth {
        case let .bearer(apiKey):
            var signed = request
            signed.headers["Authorization"] = signed.headers["Authorization"] ?? "Bearer \(apiKey)"
            return try await transport.send(signed)
        case let .sigV4(credentials):
            let signed = try AWSSigV4.sign(
                request: request,
                body: request.body ?? Data(),
                credentials: credentials,
                region: region,
                service: service,
                date: date()
            )
            return try await transport.send(signed)
        }
    }
}

struct BedrockRuntimeConfig: @unchecked Sendable {
    var providerID: String
    var region: String
    var service: String
    var baseURL: String
    var headers: [String: String]
    var auth: BedrockAuth
    var transport: any AITransport
    var date: @Sendable () -> Date

    func sendJSON(path: String, body: JSONValue, headers requestHeaders: [String: String] = [:], abortSignal: AIAbortSignal? = nil) async throws -> JSONValue {
        try await sendJSONResponse(path: path, body: body, headers: requestHeaders, abortSignal: abortSignal).json
    }

    func sendJSONResponse(path: String, body: JSONValue, headers requestHeaders: [String: String] = [:], abortSignal: AIAbortSignal? = nil) async throws -> (json: JSONValue, response: AIHTTPResponse) {
        let response = try await transport.send(try request(path: path, body: body, headers: requestHeaders, abortSignal: abortSignal))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        return (try response.jsonValue(), response)
    }

    func request(path: String, body: JSONValue, headers requestHeaders: [String: String] = [:], abortSignal: AIAbortSignal? = nil) throws -> AIHTTPRequest {
        let bodyData = try encodeJSONBody(body)
        var mergedHeaders = headers.mergingHeaders(requestHeaders)
        mergedHeaders["content-type"] = mergedHeaders["content-type"] ?? "application/json"
        let request = AIHTTPRequest(method: "POST", url: try requireURL("\(withoutTrailingSlash(baseURL))\(path)"), headers: mergedHeaders, body: bodyData, abortSignal: abortSignal)
        switch auth {
        case let .bearer(apiKey):
            var signed = request
            signed.headers["Authorization"] = signed.headers["Authorization"] ?? "Bearer \(apiKey)"
            return signed
        case let .sigV4(credentials):
            return try AWSSigV4.sign(request: request, body: bodyData, credentials: credentials, region: region, service: service, date: date())
        }
    }
}

enum AWSSigV4 {
    static func sign(request: AIHTTPRequest, body: Data, credentials: AWSCredentials, region: String, service: String, date: Date) throws -> AIHTTPRequest {
        guard let host = request.url.host else { throw AIError.invalidURL(request.url.absoluteString) }
        let amzDate = timestampFormatter.string(from: date)
        let shortDate = dateFormatter.string(from: date)
        let payloadHash = sha256Hex(body)

        var headers = request.headers.reduce(into: [String: String]()) { partial, element in
            partial[element.key.lowercased()] = element.value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        headers["host"] = host
        headers["x-amz-date"] = amzDate
        headers["x-amz-content-sha256"] = payloadHash
        if let sessionToken = credentials.sessionToken {
            headers["x-amz-security-token"] = sessionToken
        }

        let canonicalHeaders = headers.keys.sorted().map { key in
            "\(key):\(collapseSpaces(headers[key] ?? ""))\n"
        }.joined()
        let signedHeaders = headers.keys.sorted().joined(separator: ";")
        let canonicalRequest = [
            request.method.uppercased(),
            canonicalURI(for: request.url),
            canonicalQuery(for: request.url),
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")
        let credentialScope = "\(shortDate)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            sha256Hex(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")
        let signature = hmacHex(key: signingKey(secret: credentials.secretAccessKey, date: shortDate, region: region, service: service), data: Data(stringToSign.utf8))

        headers["authorization"] = "AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyID)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        return AIHTTPRequest(method: request.method, url: request.url, headers: headers, body: request.body, abortSignal: request.abortSignal)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    private static func signingKey(secret: String, date: String, region: String, service: String) -> SymmetricKey {
        let kDate = hmacData(key: SymmetricKey(data: Data("AWS4\(secret)".utf8)), data: Data(date.utf8))
        let kRegion = hmacData(key: SymmetricKey(data: kDate), data: Data(region.utf8))
        let kService = hmacData(key: SymmetricKey(data: kRegion), data: Data(service.utf8))
        let kSigning = hmacData(key: SymmetricKey(data: kService), data: Data("aws4_request".utf8))
        return SymmetricKey(data: kSigning)
    }

    private static func hmacData(key: SymmetricKey, data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    private static func hmacHex(key: SymmetricKey, data: Data) -> String {
        hex(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    private static func sha256Hex(_ data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    private static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func canonicalURI(for url: URL) -> String {
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path
        return path.isEmpty ? "/" : path
    }

    private static func canonicalQuery(for url: URL) -> String {
        guard let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems, !queryItems.isEmpty else {
            return ""
        }
        let encodedItems: [(String, String)] = queryItems.map { item in
            (percentEncode(item.name), percentEncode(item.value ?? ""))
        }
        let sortedItems = encodedItems.sorted { lhs, rhs in
            lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
        }
        return sortedItems.map { name, value in
            "\(name)=\(value)"
        }.joined(separator: "&")
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "=&+")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func collapseSpaces(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
