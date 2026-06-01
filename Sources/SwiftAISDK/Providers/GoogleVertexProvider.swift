import Foundation
import Security

public struct GoogleServiceAccountCredentials: Sendable {
    public var clientEmail: String
    public var privateKey: String
    public var privateKeyID: String?

    public init(clientEmail: String, privateKey: String, privateKeyID: String? = nil) {
        self.clientEmail = clientEmail
        self.privateKey = privateKey
        self.privateKeyID = privateKeyID
    }
}

public struct GoogleVertexProviderSettings: Sendable {
    public var project: String?
    public var location: String?
    public var apiKey: String?
    public var accessToken: String?
    public var serviceAccount: GoogleServiceAccountCredentials?
    public var baseURL: String?
    public var headers: [String: String]
    public var transport: any AITransport
    public var date: @Sendable () -> Date

    public init(
        project: String? = nil,
        location: String? = nil,
        apiKey: String? = nil,
        accessToken: String? = nil,
        serviceAccount: GoogleServiceAccountCredentials? = nil,
        baseURL: String? = nil,
        headers: [String: String] = [:],
        transport: any AITransport = URLSessionTransport.shared,
        date: @escaping @Sendable () -> Date = Date.init
    ) {
        self.project = project
        self.location = location
        self.apiKey = apiKey
        self.accessToken = accessToken
        self.serviceAccount = serviceAccount
        self.baseURL = baseURL
        self.headers = headers
        self.transport = transport
        self.date = date
    }
}

public final class GoogleVertexProvider: AIProvider, @unchecked Sendable {
    public let providerID = "google.vertex"
    public let supportedCapabilities: Set<ModelCapability> = [.language, .embedding, .image, .video]
    private let config: GoogleVertexConfig

    public init(settings: GoogleVertexProviderSettings = GoogleVertexProviderSettings()) throws {
        let apiKey = settings.apiKey ?? environmentValue(["GOOGLE_VERTEX_API_KEY"])
        let auth: GoogleVertexAuth
        if let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            auth = .apiKey(apiKey)
        } else if let accessToken = settings.accessToken ?? environmentValue(["GOOGLE_VERTEX_ACCESS_TOKEN", "GOOGLE_ACCESS_TOKEN"]) {
            auth = .accessToken(accessToken)
        } else if let serviceAccount = settings.serviceAccount ?? Self.environmentServiceAccount() {
            auth = .serviceAccount(serviceAccount)
        } else {
            throw AIError.missingAPIKey(provider: providerID, environmentVariables: ["GOOGLE_VERTEX_API_KEY", "GOOGLE_VERTEX_ACCESS_TOKEN", "GOOGLE_CLIENT_EMAIL", "GOOGLE_PRIVATE_KEY"])
        }

        let baseURL: String
        if apiKey != nil {
            baseURL = withoutTrailingSlash(settings.baseURL ?? "https://aiplatform.googleapis.com/v1/publishers/google")
        } else if let explicit = settings.baseURL {
            baseURL = withoutTrailingSlash(explicit)
        } else {
            let project = settings.project ?? environmentValue(["GOOGLE_VERTEX_PROJECT"])
            let location = settings.location ?? environmentValue(["GOOGLE_VERTEX_LOCATION"])
            guard let project, let location else {
                throw AIError.invalidURL("Google Vertex OAuth mode requires project/location or baseURL.")
            }
            let host = location == "global" ? "aiplatform.googleapis.com" : "\(location)-aiplatform.googleapis.com"
            baseURL = "https://\(host)/v1beta1/projects/\(project)/locations/\(location)/publishers/google"
        }

        var headers = settings.headers
        headers["user-agent"] = headers["user-agent"] ?? userAgent(providerID)
        config = GoogleVertexConfig(providerID: providerID, baseURL: baseURL, headers: headers, auth: auth, transport: settings.transport, date: settings.date)
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        GoogleVertexLanguageModel(modelID: modelID, config: config.withProviderID("google.vertex.chat"))
    }

    public func embeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        GoogleVertexEmbeddingModel(modelID: modelID, config: config.withProviderID("google.vertex.embedding"))
    }

    public func imageModel(_ modelID: String) throws -> any ImageModel {
        GoogleVertexImageModel(modelID: modelID, config: config.withProviderID("google.vertex.image"))
    }

    public func videoModel(_ modelID: String) throws -> any VideoModel {
        GoogleVertexVideoModel(modelID: modelID, config: config.withProviderID("google.vertex.video"))
    }

    public func transcriptionModel(_ modelID: String) throws -> any TranscriptionModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .transcription, modelID: modelID)
    }

    public func speechModel(_ modelID: String) throws -> any SpeechModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .speech, modelID: modelID)
    }

    public func rerankingModel(_ modelID: String) throws -> any RerankingModel {
        throw AIError.unsupportedModel(provider: providerID, capability: .reranking, modelID: modelID)
    }

    private static func environmentServiceAccount() -> GoogleServiceAccountCredentials? {
        guard let email = environmentValue(["GOOGLE_CLIENT_EMAIL"]),
              let key = environmentValue(["GOOGLE_PRIVATE_KEY"])?.replacingOccurrences(of: "\\n", with: "\n") else {
            return nil
        }
        return GoogleServiceAccountCredentials(clientEmail: email, privateKey: key, privateKeyID: environmentValue(["GOOGLE_PRIVATE_KEY_ID"]))
    }
}

enum GoogleVertexAuth: Sendable {
    case apiKey(String)
    case accessToken(String)
    case serviceAccount(GoogleServiceAccountCredentials)
}

struct GoogleVertexConfig: @unchecked Sendable {
    var providerID: String
    var baseURL: String
    var headers: [String: String]
    var auth: GoogleVertexAuth
    var transport: any AITransport
    var date: @Sendable () -> Date

    func sendJSON(path: String, body: JSONValue, headers requestHeaders: [String: String] = [:], abortSignal: AIAbortSignal? = nil) async throws -> JSONValue {
        try await sendJSONResponse(path: path, body: body, headers: requestHeaders, abortSignal: abortSignal).json
    }

    func sendJSONResponse(path: String, body: JSONValue, headers requestHeaders: [String: String] = [:], abortSignal: AIAbortSignal? = nil) async throws -> (json: JSONValue, response: AIHTTPResponse) {
        let response = try await transport.send(try await request(path: path, body: body, headers: requestHeaders, abortSignal: abortSignal))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        return (try response.jsonValue(), response)
    }

    func request(path: String, body: JSONValue, headers requestHeaders: [String: String] = [:], abortSignal: AIAbortSignal? = nil) async throws -> AIHTTPRequest {
        var mergedHeaders = headers.mergingHeaders(requestHeaders)
        mergedHeaders["content-type"] = mergedHeaders["content-type"] ?? "application/json"
        switch auth {
        case let .apiKey(apiKey):
            mergedHeaders["x-goog-api-key"] = mergedHeaders["x-goog-api-key"] ?? apiKey
        case let .accessToken(token):
            mergedHeaders["Authorization"] = mergedHeaders["Authorization"] ?? "Bearer \(token)"
        case let .serviceAccount(credentials):
            let token = try await GoogleServiceAccountTokenGenerator.generateAccessToken(credentials: credentials, now: date())
            mergedHeaders["Authorization"] = mergedHeaders["Authorization"] ?? "Bearer \(token)"
        }
        return AIHTTPRequest(method: "POST", url: try requireURL("\(withoutTrailingSlash(baseURL))\(path)"), headers: mergedHeaders, body: try encodeJSONBody(body), abortSignal: abortSignal)
    }

    func withProviderID(_ providerID: String) -> GoogleVertexConfig {
        GoogleVertexConfig(
            providerID: providerID,
            baseURL: baseURL,
            headers: headers,
            auth: auth,
            transport: transport,
            date: date
        )
    }
}

enum GoogleServiceAccountTokenGenerator {
    static func generateAccessToken(credentials: GoogleServiceAccountCredentials, now: Date) async throws -> String {
        let assertion = try buildJWT(credentials: credentials, now: now)
        let body = "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=\(urlFormEncode(assertion))"
        var request = URLRequest(url: try requireURL("https://oauth2.googleapis.com/token"))
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let http = response as? HTTPURLResponse
            let headers = http?.allHeaderFields.reduce(into: [String: String]()) { partial, element in
                guard let key = element.key as? String else { return }
                partial[key] = String(describing: element.value)
            } ?? [:]
            throw httpStatusError(
                provider: "google.vertex",
                statusCode: http?.statusCode ?? 0,
                body: String(data: data, encoding: .utf8) ?? "",
                headers: headers
            )
        }
        let raw = try decodeJSONBody(data)
        guard let token = raw["access_token"]?.stringValue else {
            throw AIError.invalidResponse(provider: "google.vertex", message: "OAuth token response did not contain access_token.")
        }
        return token
    }

    static func buildJWT(credentials: GoogleServiceAccountCredentials, now: Date) throws -> String {
        let issuedAt = Int(now.timeIntervalSince1970)
        var header: [String: JSONValue] = ["alg": "RS256", "typ": "JWT"]
        if let privateKeyID = credentials.privateKeyID {
            header["kid"] = .string(privateKeyID)
        }
        let payload: [String: JSONValue] = [
            "iss": .string(credentials.clientEmail),
            "scope": "https://www.googleapis.com/auth/cloud-platform",
            "aud": "https://oauth2.googleapis.com/token",
            "exp": .number(Double(issuedAt + 3600)),
            "iat": .number(Double(issuedAt))
        ]
        let signingInput = "\(base64URL(try encodeJSONBody(.object(header)))).\(base64URL(try encodeJSONBody(.object(payload))))"
        let signature = try signRS256(Data(signingInput.utf8), privateKeyPEM: credentials.privateKey)
        return "\(signingInput).\(base64URL(signature))"
    }

    private static func signRS256(_ data: Data, privateKeyPEM: String) throws -> Data {
        let pem = privateKeyPEM
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let keyData = Data(base64Encoded: pem) else {
            throw AIError.invalidResponse(provider: "google.vertex", message: "Invalid service account private key PEM.")
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            throw error?.takeRetainedValue() ?? AIError.invalidResponse(provider: "google.vertex", message: "Could not import service account private key.")
        }
        guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, &error) else {
            throw error?.takeRetainedValue() ?? AIError.invalidResponse(provider: "google.vertex", message: "Could not sign service account JWT.")
        }
        return signature as Data
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func urlFormEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
