import CryptoKit
import Foundation

public struct KlingAIProviderSettings: Sendable {
    public var apiKey: String?
    public var accessKey: String?
    public var secretKey: String?
    public var baseURL: String?
    public var headers: [String: String]
    public var environment: [String: String]?
    public var transport: any AITransport
    var currentDate: @Sendable () -> Date

    public init(
        apiKey: String? = nil,
        accessKey: String? = nil,
        secretKey: String? = nil,
        baseURL: String? = nil,
        headers: [String: String] = [:],
        environment: [String: String]? = nil,
        transport: any AITransport = URLSessionTransport.shared
    ) {
        self.apiKey = apiKey
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.baseURL = baseURL
        self.headers = headers
        self.environment = environment
        self.transport = transport
        self.currentDate = { Date() }
    }

    func environmentValue(_ name: String) -> String? {
        if let environment { return environment[name] }
        return SwiftAISDK.environmentValue([name])
    }
}

enum KlingAIResolvedAuth: Equatable, Sendable {
    case bearerToken(String)
    case legacy(accessKey: String, secretKey: String)
}

func resolveKlingAIAuth(settings: KlingAIProviderSettings) throws -> KlingAIResolvedAuth {
    if let apiKey = klingAITrimmedSetting(settings.apiKey) {
        return .bearerToken(apiKey)
    }

    if settings.accessKey != nil, settings.secretKey != nil {
        return .legacy(
            accessKey: try klingAIRequiredLegacySetting(settings.accessKey, name: "accessKey", environmentVariable: "KLINGAI_ACCESS_KEY"),
            secretKey: try klingAIRequiredLegacySetting(settings.secretKey, name: "secretKey", environmentVariable: "KLINGAI_SECRET_KEY")
        )
    }

    if let apiKey = klingAITrimmedSetting(settings.environmentValue("KLINGAI_API_KEY")) {
        return .bearerToken(apiKey)
    }

    let accessKey = klingAITrimmedSetting(settings.accessKey) ?? klingAITrimmedSetting(settings.environmentValue("KLINGAI_ACCESS_KEY"))
    let secretKey = klingAITrimmedSetting(settings.secretKey) ?? klingAITrimmedSetting(settings.environmentValue("KLINGAI_SECRET_KEY"))
    if accessKey == nil, secretKey == nil {
        throw AIError.missingAPIKey(
            provider: "klingai",
            environmentVariables: ["KLINGAI_API_KEY", "KLINGAI_ACCESS_KEY", "KLINGAI_SECRET_KEY"]
        )
    }
    guard let accessKey else {
        throw AIError.missingAPIKey(provider: "klingai", environmentVariables: ["KLINGAI_ACCESS_KEY"])
    }
    guard let secretKey else {
        throw AIError.missingAPIKey(provider: "klingai", environmentVariables: ["KLINGAI_SECRET_KEY"])
    }
    return .legacy(accessKey: accessKey, secretKey: secretKey)
}

func resolveKlingAIAuthToken(settings: KlingAIProviderSettings, now: Date = Date()) throws -> String {
    switch try resolveKlingAIAuth(settings: settings) {
    case let .bearerToken(token):
        return token
    case let .legacy(accessKey, secretKey):
        return try klingAIJWT(accessKey: accessKey, secretKey: secretKey, now: now)
    }
}

struct KlingAILegacyAuthTransport: AIStreamingTransport {
    let transport: any AITransport
    let accessKey: String
    let secretKey: String
    let currentDate: @Sendable () -> Date

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        try await transport.send(authenticatedRequest(request))
    }

    func stream(_ request: AIHTTPRequest) async throws -> AIHTTPStreamResponse {
        let streamingTransport = try requireStreamingTransport(transport, providerID: "klingai")
        return try await streamingTransport.stream(authenticatedRequest(request))
    }

    private func authenticatedRequest(_ request: AIHTTPRequest) throws -> AIHTTPRequest {
        var request = request
        if !request.headers.keys.contains(where: { $0.caseInsensitiveCompare("Authorization") == .orderedSame }) {
            request.headers["authorization"] = "Bearer \(try klingAIJWT(accessKey: accessKey, secretKey: secretKey, now: currentDate()))"
        }
        return request
    }
}

private func klingAITrimmedSetting(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    return value
}

private func klingAIRequiredLegacySetting(_ value: String?, name: String, environmentVariable: String) throws -> String {
    guard let value = klingAITrimmedSetting(value) else {
        throw AIError.missingAPIKey(provider: "klingai.\(name)", environmentVariables: [environmentVariable])
    }
    return value
}

private func klingAIJWT(accessKey: String, secretKey: String, now: Date) throws -> String {
    let issuedAt = Int(now.timeIntervalSince1970)
    let header: JSONValue = .object(["alg": .string("HS256"), "typ": .string("JWT")])
    let payload: JSONValue = .object([
        "iss": .string(accessKey),
        "exp": .number(Double(issuedAt + 1800)),
        "nbf": .number(Double(issuedAt - 5))
    ])
    let signingInput = "\(klingAIBase64URL(try encodeJSONBody(header))).\(klingAIBase64URL(try encodeJSONBody(payload)))"
    let signature = HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: SymmetricKey(data: Data(secretKey.utf8)))
    return "\(signingInput).\(klingAIBase64URL(Data(signature)))"
}

private func klingAIBase64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
