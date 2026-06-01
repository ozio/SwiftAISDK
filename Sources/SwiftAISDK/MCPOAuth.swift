import Foundation

public struct MCPOAuthProtectedResourceMetadata: Equatable, Sendable {
    public var resource: URL
    public var authorizationServers: [URL]
    public var scopesSupported: [String]
    public var rawValue: JSONValue

    public init(resource: URL, authorizationServers: [URL] = [], scopesSupported: [String] = [], rawValue: JSONValue = .object([:])) {
        self.resource = resource
        self.authorizationServers = authorizationServers
        self.scopesSupported = scopesSupported
        self.rawValue = rawValue
    }

    init(json: JSONValue) throws {
        guard let resource = json["resource"]?.stringValue.flatMap(URL.init(string:)) else {
            throw MCPClientError(message: "Expected OAuth protected resource metadata with resource URL.")
        }
        let authorizationServers = try (json["authorization_servers"]?.arrayValue ?? []).map { value -> URL in
            guard let url = value.stringValue.flatMap(URL.init(string:)) else {
                throw MCPClientError(message: "Expected OAuth protected resource authorization server URL.")
            }
            return url
        }
        self.init(
            resource: resource,
            authorizationServers: authorizationServers,
            scopesSupported: json["scopes_supported"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            rawValue: json
        )
    }
}

public struct MCPOAuthAuthorizationServerMetadata: Equatable, Sendable {
    public var issuer: String
    public var authorizationEndpoint: URL
    public var tokenEndpoint: URL
    public var registrationEndpoint: URL?
    public var responseTypesSupported: [String]
    public var codeChallengeMethodsSupported: [String]
    public var rawValue: JSONValue

    public init(
        issuer: String,
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        registrationEndpoint: URL? = nil,
        responseTypesSupported: [String],
        codeChallengeMethodsSupported: [String],
        rawValue: JSONValue = .object([:])
    ) {
        self.issuer = issuer
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.registrationEndpoint = registrationEndpoint
        self.responseTypesSupported = responseTypesSupported
        self.codeChallengeMethodsSupported = codeChallengeMethodsSupported
        self.rawValue = rawValue
    }

    fileprivate init(json: JSONValue, sourceURL: URL, sourceType: MCPOAuthDiscoveryURL.Kind) throws {
        guard let issuer = json["issuer"]?.stringValue,
              let authorizationEndpoint = json["authorization_endpoint"]?.stringValue.flatMap(URL.init(string:)),
              let tokenEndpoint = json["token_endpoint"]?.stringValue.flatMap(URL.init(string:)) else {
            throw MCPClientError(message: "Expected OAuth authorization server metadata with issuer, authorization_endpoint, and token_endpoint.")
        }
        let codeChallengeMethods = json["code_challenge_methods_supported"]?.arrayValue?.compactMap(\.stringValue) ?? []
        if sourceType == .oidc, !codeChallengeMethods.contains("S256") {
            throw MCPClientError(
                message: "Incompatible OIDC provider at \(sourceURL.absoluteString): does not support S256 code challenge method required by MCP specification"
            )
        }
        self.init(
            issuer: issuer,
            authorizationEndpoint: authorizationEndpoint,
            tokenEndpoint: tokenEndpoint,
            registrationEndpoint: json["registration_endpoint"]?.stringValue.flatMap(URL.init(string:)),
            responseTypesSupported: json["response_types_supported"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            codeChallengeMethodsSupported: codeChallengeMethods,
            rawValue: json
        )
    }
}

public struct MCPOAuthDiscovery {
    public static func discoverProtectedResourceMetadata(
        serverURL: URL,
        protocolVersion: String = MCPClient.latestProtocolVersion,
        resourceMetadataURL: URL? = nil,
        transport: any AITransport = URLSessionTransport.shared
    ) async throws -> MCPOAuthProtectedResourceMetadata {
        let discoveryURL = resourceMetadataURL ?? mcpWellKnownURL(
            for: serverURL,
            wellKnownName: "oauth-protected-resource",
            includePath: true
        )
        var response = try await discoveryGET(url: discoveryURL, protocolVersion: protocolVersion, transport: transport)

        if resourceMetadataURL == nil,
           shouldFallbackToRoot(response: response, originalURL: serverURL) {
            response = try await discoveryGET(
                url: mcpWellKnownURL(for: serverURL, wellKnownName: "oauth-protected-resource", includePath: false),
                protocolVersion: protocolVersion,
                transport: transport
            )
        }

        if response.statusCode == 404 {
            throw MCPClientError(message: "Resource server does not implement OAuth 2.0 Protected Resource Metadata.")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw MCPClientError(message: "HTTP \(response.statusCode) trying to load well-known OAuth protected resource metadata.")
        }
        return try MCPOAuthProtectedResourceMetadata(json: response.jsonValue())
    }

    public static func discoverProtectedResourceMetadata(
        serverURL: String,
        protocolVersion: String = MCPClient.latestProtocolVersion,
        resourceMetadataURL: String? = nil,
        transport: any AITransport = URLSessionTransport.shared
    ) async throws -> MCPOAuthProtectedResourceMetadata {
        try await discoverProtectedResourceMetadata(
            serverURL: requireURL(serverURL),
            protocolVersion: protocolVersion,
            resourceMetadataURL: try resourceMetadataURL.map(requireURL),
            transport: transport
        )
    }

    public static func buildAuthorizationServerDiscoveryURLs(_ authorizationServerURL: URL) -> [URL] {
        mcpAuthorizationServerDiscoveryURLs(authorizationServerURL).map(\.url)
    }

    public static func discoverAuthorizationServerMetadata(
        authorizationServerURL: URL,
        protocolVersion: String = MCPClient.latestProtocolVersion,
        transport: any AITransport = URLSessionTransport.shared
    ) async throws -> MCPOAuthAuthorizationServerMetadata? {
        for discoveryURL in mcpAuthorizationServerDiscoveryURLs(authorizationServerURL) {
            let response = try await discoveryGET(url: discoveryURL.url, protocolVersion: protocolVersion, transport: transport)
            guard (200..<300).contains(response.statusCode) else {
                if (400..<500).contains(response.statusCode) {
                    continue
                }
                throw MCPClientError(
                    message: "HTTP \(response.statusCode) trying to load \(discoveryURL.kind == .oauth ? "OAuth" : "OpenID provider") metadata from \(discoveryURL.url.absoluteString)"
                )
            }
            return try MCPOAuthAuthorizationServerMetadata(
                json: response.jsonValue(),
                sourceURL: discoveryURL.url,
                sourceType: discoveryURL.kind
            )
        }
        return nil
    }

    public static func discoverAuthorizationServerMetadata(
        authorizationServerURL: String,
        protocolVersion: String = MCPClient.latestProtocolVersion,
        transport: any AITransport = URLSessionTransport.shared
    ) async throws -> MCPOAuthAuthorizationServerMetadata? {
        try await discoverAuthorizationServerMetadata(
            authorizationServerURL: requireURL(authorizationServerURL),
            protocolVersion: protocolVersion,
            transport: transport
        )
    }
}

private struct MCPOAuthDiscoveryURL {
    enum Kind {
        case oauth
        case oidc
    }

    var url: URL
    var kind: Kind
}

private func discoveryGET(url: URL, protocolVersion: String, transport: any AITransport) async throws -> AIHTTPResponse {
    try await transport.send(AIHTTPRequest(
        method: "GET",
        url: url,
        headers: ["MCP-Protocol-Version": protocolVersion]
    ))
}

private func shouldFallbackToRoot(response: AIHTTPResponse, originalURL: URL) -> Bool {
    guard originalURL.path != "" && originalURL.path != "/" else { return false }
    return (400..<500).contains(response.statusCode)
}

private func mcpWellKnownURL(for url: URL, wellKnownName: String, includePath: Bool) -> URL {
    var components = URLComponents()
    components.scheme = url.scheme
    components.host = url.host
    components.port = url.port
    let path = includePath ? url.path.trimmedTrailingSlashForOAuthDiscovery : ""
    components.path = "/.well-known/\(wellKnownName)\(path)"
    if includePath {
        components.query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.query
    }
    return components.url ?? url
}

private func mcpAuthorizationServerDiscoveryURLs(_ url: URL) -> [MCPOAuthDiscoveryURL] {
    let path = url.path.trimmedTrailingSlashForOAuthDiscovery
    guard !path.isEmpty else {
        return [
            MCPOAuthDiscoveryURL(url: mcpURL(origin: url, path: "/.well-known/oauth-authorization-server"), kind: .oauth),
            MCPOAuthDiscoveryURL(url: mcpURL(origin: url, path: "/.well-known/openid-configuration"), kind: .oidc)
        ]
    }
    return [
        MCPOAuthDiscoveryURL(url: mcpURL(origin: url, path: "/.well-known/oauth-authorization-server\(path)"), kind: .oauth),
        MCPOAuthDiscoveryURL(url: mcpURL(origin: url, path: "/.well-known/oauth-authorization-server"), kind: .oauth),
        MCPOAuthDiscoveryURL(url: mcpURL(origin: url, path: "/.well-known/openid-configuration\(path)"), kind: .oidc),
        MCPOAuthDiscoveryURL(url: mcpURL(origin: url, path: "\(path)/.well-known/openid-configuration"), kind: .oidc)
    ]
}

private func mcpURL(origin: URL, path: String) -> URL {
    var components = URLComponents()
    components.scheme = origin.scheme
    components.host = origin.host
    components.port = origin.port
    components.path = path
    return components.url ?? origin
}

private extension String {
    var trimmedTrailingSlashForOAuthDiscovery: String {
        var value = self == "/" ? "" : self
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
