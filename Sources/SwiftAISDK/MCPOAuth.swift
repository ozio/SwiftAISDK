import Foundation
import CryptoKit

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
    public var grantTypesSupported: [String]
    public var tokenEndpointAuthMethodsSupported: [String]
    public var rawValue: JSONValue

    public init(
        issuer: String,
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        registrationEndpoint: URL? = nil,
        responseTypesSupported: [String],
        codeChallengeMethodsSupported: [String],
        grantTypesSupported: [String] = [],
        tokenEndpointAuthMethodsSupported: [String] = [],
        rawValue: JSONValue = .object([:])
    ) {
        self.issuer = issuer
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.registrationEndpoint = registrationEndpoint
        self.responseTypesSupported = responseTypesSupported
        self.codeChallengeMethodsSupported = codeChallengeMethodsSupported
        self.grantTypesSupported = grantTypesSupported
        self.tokenEndpointAuthMethodsSupported = tokenEndpointAuthMethodsSupported
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
            grantTypesSupported: json["grant_types_supported"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            tokenEndpointAuthMethodsSupported: json["token_endpoint_auth_methods_supported"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            rawValue: json
        )
    }
}

public struct MCPOAuthTokens: Equatable, Sendable {
    public var accessToken: String
    public var idToken: String?
    public var tokenType: String
    public var expiresIn: Int?
    public var scope: String?
    public var refreshToken: String?
    public var rawValue: JSONValue

    public init(
        accessToken: String,
        idToken: String? = nil,
        tokenType: String,
        expiresIn: Int? = nil,
        scope: String? = nil,
        refreshToken: String? = nil,
        rawValue: JSONValue = .object([:])
    ) {
        self.accessToken = accessToken
        self.idToken = idToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.scope = scope
        self.refreshToken = refreshToken
        self.rawValue = rawValue
    }

    init(json: JSONValue) throws {
        guard let accessToken = json["access_token"]?.stringValue,
              let tokenType = json["token_type"]?.stringValue else {
            throw MCPClientError(message: "Expected OAuth token response with access_token and token_type.")
        }
        self.init(
            accessToken: accessToken,
            idToken: json["id_token"]?.stringValue,
            tokenType: tokenType,
            expiresIn: json["expires_in"]?.intValue,
            scope: json["scope"]?.stringValue,
            refreshToken: json["refresh_token"]?.stringValue,
            rawValue: json
        )
    }
}

public struct MCPOAuthClientInformation: Equatable, Sendable {
    public var clientID: String
    public var clientSecret: String?
    public var clientIDIssuedAt: Int?
    public var clientSecretExpiresAt: Int?
    public var rawValue: JSONValue

    public init(
        clientID: String,
        clientSecret: String? = nil,
        clientIDIssuedAt: Int? = nil,
        clientSecretExpiresAt: Int? = nil,
        rawValue: JSONValue = .object([:])
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.clientIDIssuedAt = clientIDIssuedAt
        self.clientSecretExpiresAt = clientSecretExpiresAt
        self.rawValue = rawValue
    }

    init(json: JSONValue) throws {
        guard let clientID = json["client_id"]?.stringValue else {
            throw MCPClientError(message: "Expected OAuth client information with client_id.")
        }
        self.init(
            clientID: clientID,
            clientSecret: json["client_secret"]?.stringValue,
            clientIDIssuedAt: json["client_id_issued_at"]?.intValue,
            clientSecretExpiresAt: json["client_secret_expires_at"]?.intValue,
            rawValue: json
        )
    }
}

public struct MCPOAuthClientMetadata: Equatable, Sendable {
    public var redirectURIs: [URL]
    public var tokenEndpointAuthMethod: String?
    public var grantTypes: [String]
    public var responseTypes: [String]
    public var clientName: String?
    public var clientURI: URL?
    public var logoURI: URL?
    public var scope: String?
    public var contacts: [String]
    public var tosURI: URL?
    public var policyURI: URL?
    public var jwksURI: URL?
    public var jwks: JSONValue?
    public var softwareID: String?
    public var softwareVersion: String?
    public var softwareStatement: String?

    public init(
        redirectURIs: [URL],
        tokenEndpointAuthMethod: String? = nil,
        grantTypes: [String] = [],
        responseTypes: [String] = [],
        clientName: String? = nil,
        clientURI: URL? = nil,
        logoURI: URL? = nil,
        scope: String? = nil,
        contacts: [String] = [],
        tosURI: URL? = nil,
        policyURI: URL? = nil,
        jwksURI: URL? = nil,
        jwks: JSONValue? = nil,
        softwareID: String? = nil,
        softwareVersion: String? = nil,
        softwareStatement: String? = nil
    ) {
        self.redirectURIs = redirectURIs
        self.tokenEndpointAuthMethod = tokenEndpointAuthMethod
        self.grantTypes = grantTypes
        self.responseTypes = responseTypes
        self.clientName = clientName
        self.clientURI = clientURI
        self.logoURI = logoURI
        self.scope = scope
        self.contacts = contacts
        self.tosURI = tosURI
        self.policyURI = policyURI
        self.jwksURI = jwksURI
        self.jwks = jwks
        self.softwareID = softwareID
        self.softwareVersion = softwareVersion
        self.softwareStatement = softwareStatement
    }

    init(json: JSONValue) throws {
        let redirectURIs = try (json["redirect_uris"]?.arrayValue ?? []).map { value -> URL in
            guard let url = value.stringValue.flatMap(URL.init(string:)) else {
                throw MCPClientError(message: "Expected OAuth client metadata redirect_uris to contain URLs.")
            }
            return url
        }
        guard !redirectURIs.isEmpty else {
            throw MCPClientError(message: "Expected OAuth client metadata with redirect_uris.")
        }
        self.init(
            redirectURIs: redirectURIs,
            tokenEndpointAuthMethod: json["token_endpoint_auth_method"]?.stringValue,
            grantTypes: json["grant_types"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            responseTypes: json["response_types"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            clientName: json["client_name"]?.stringValue,
            clientURI: json["client_uri"]?.stringValue.flatMap(URL.init(string:)),
            logoURI: json["logo_uri"]?.stringValue.flatMap(URL.init(string:)),
            scope: json["scope"]?.stringValue,
            contacts: json["contacts"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            tosURI: json["tos_uri"]?.stringValue.flatMap(URL.init(string:)),
            policyURI: json["policy_uri"]?.stringValue.flatMap(URL.init(string:)),
            jwksURI: json["jwks_uri"]?.stringValue.flatMap(URL.init(string:)),
            jwks: json["jwks"],
            softwareID: json["software_id"]?.stringValue,
            softwareVersion: json["software_version"]?.stringValue,
            softwareStatement: json["software_statement"]?.stringValue
        )
    }

    public var jsonValue: JSONValue {
        .object([
            "redirect_uris": .array(redirectURIs.map(\.absoluteString)),
            "token_endpoint_auth_method": tokenEndpointAuthMethod.map(JSONValue.string),
            "grant_types": grantTypes.isEmpty ? nil : .array(grantTypes.map(JSONValue.string)),
            "response_types": responseTypes.isEmpty ? nil : .array(responseTypes.map(JSONValue.string)),
            "client_name": clientName.map(JSONValue.string),
            "client_uri": clientURI.map { .string($0.absoluteString) },
            "logo_uri": logoURI.map { .string($0.absoluteString) },
            "scope": scope.map(JSONValue.string),
            "contacts": contacts.isEmpty ? nil : .array(contacts.map(JSONValue.string)),
            "tos_uri": tosURI.map { .string($0.absoluteString) },
            "policy_uri": policyURI.map { .string($0.absoluteString) },
            "jwks_uri": jwksURI.map { .string($0.absoluteString) },
            "jwks": jwks,
            "software_id": softwareID.map(JSONValue.string),
            "software_version": softwareVersion.map(JSONValue.string),
            "software_statement": softwareStatement.map(JSONValue.string)
        ])
    }
}

public struct MCPOAuthClientInformationFull: Equatable, Sendable {
    public var clientInformation: MCPOAuthClientInformation
    public var clientMetadata: MCPOAuthClientMetadata
    public var rawValue: JSONValue

    public init(clientInformation: MCPOAuthClientInformation, clientMetadata: MCPOAuthClientMetadata, rawValue: JSONValue = .object([:])) {
        self.clientInformation = clientInformation
        self.clientMetadata = clientMetadata
        self.rawValue = rawValue
    }

    init(json: JSONValue) throws {
        self.init(
            clientInformation: try MCPOAuthClientInformation(json: json),
            clientMetadata: try MCPOAuthClientMetadata(json: json),
            rawValue: json
        )
    }
}

public struct MCPOAuthStartAuthorizationResult: Equatable, Sendable {
    public var authorizationURL: URL
    public var codeVerifier: String

    public init(authorizationURL: URL, codeVerifier: String) {
        self.authorizationURL = authorizationURL
        self.codeVerifier = codeVerifier
    }
}

public enum MCPOAuthAuthResult: String, Equatable, Sendable {
    case authorized
    case redirect
}

public enum MCPOAuthClientAuthMethod: String, Equatable, Sendable {
    case clientSecretBasic = "client_secret_basic"
    case clientSecretPost = "client_secret_post"
    case none
}

public struct MCPOAuthServerError: Error, Equatable, CustomStringConvertible, Sendable {
    public var statusCode: Int?
    public var code: String?
    public var message: String
    public var uri: String?

    public init(statusCode: Int? = nil, code: String? = nil, message: String, uri: String? = nil) {
        self.statusCode = statusCode
        self.code = code
        self.message = message
        self.uri = uri
    }

    public var description: String {
        if let code {
            return uri.map { "\(code): \(message) (\($0))" } ?? "\(code): \(message)"
        }
        return message
    }
}

public struct MCPOAuthClientAuthenticationRequest: Sendable {
    public var headers: [String: String]
    public var parameters: [URLQueryItem]
    public var tokenURL: URL
    public var authorizationServerURL: URL
    public var metadata: MCPOAuthAuthorizationServerMetadata?

    public init(
        headers: [String: String],
        parameters: [URLQueryItem],
        tokenURL: URL,
        authorizationServerURL: URL,
        metadata: MCPOAuthAuthorizationServerMetadata? = nil
    ) {
        self.headers = headers
        self.parameters = parameters
        self.tokenURL = tokenURL
        self.authorizationServerURL = authorizationServerURL
        self.metadata = metadata
    }
}

public typealias MCPOAuthClientAuthenticationHandler = @Sendable (MCPOAuthClientAuthenticationRequest) async throws -> MCPOAuthClientAuthenticationRequest?

public protocol MCPOAuthClientProvider: Sendable {
    var redirectURL: URL { get }
    var clientMetadata: MCPOAuthClientMetadata { get }

    func tokens() async throws -> MCPOAuthTokens?
    func saveTokens(_ tokens: MCPOAuthTokens) async throws
    func redirectToAuthorization(_ authorizationURL: URL) async throws
    func saveCodeVerifier(_ codeVerifier: String) async throws
    func codeVerifier() async throws -> String
    func invalidateCredentials(_ scope: MCPOAuthCredentialScope) async

    func clientInformation() async throws -> MCPOAuthClientInformation?
    func saveClientInformation(_ clientInformation: MCPOAuthClientInformation) async throws
    var supportsDynamicClientRegistration: Bool { get }

    func state() async throws -> String?
    func saveState(_ state: String) async throws
    func storedState() async throws -> String?
    func validateResourceURL(serverURL: URL, resource: URL?) async throws -> URL?
    func authenticateTokenRequest(_ request: MCPOAuthClientAuthenticationRequest) async throws -> MCPOAuthClientAuthenticationRequest?
}

public extension MCPOAuthClientProvider {
    func invalidateCredentials(_ scope: MCPOAuthCredentialScope) async {}

    func clientInformation() async throws -> MCPOAuthClientInformation? { nil }
    func saveClientInformation(_ clientInformation: MCPOAuthClientInformation) async throws {}
    var supportsDynamicClientRegistration: Bool { false }

    func state() async throws -> String? { nil }
    func saveState(_ state: String) async throws {}
    func storedState() async throws -> String? { nil }
    func validateResourceURL(serverURL: URL, resource: URL?) async throws -> URL? { nil }
    func authenticateTokenRequest(_ request: MCPOAuthClientAuthenticationRequest) async throws -> MCPOAuthClientAuthenticationRequest? { nil }
}

public enum MCPOAuth {
    public static func auth(
        provider: any MCPOAuthClientProvider,
        serverURL: URL,
        authorizationCode: String? = nil,
        callbackState: String? = nil,
        scope: String? = nil,
        resourceMetadataURL: URL? = nil,
        protocolVersion: String = MCPClient.latestProtocolVersion,
        transport: any AITransport = URLSessionTransport.shared
    ) async throws -> MCPOAuthAuthResult {
        do {
            return try await authInternal(
                provider: provider,
                serverURL: serverURL,
                authorizationCode: authorizationCode,
                callbackState: callbackState,
                scope: scope,
                resourceMetadataURL: resourceMetadataURL,
                protocolVersion: protocolVersion,
                transport: transport
            )
        } catch let error as MCPOAuthServerError {
            switch error.code {
            case "invalid_client", "unauthorized_client":
                await provider.invalidateCredentials(.all)
            case "invalid_grant":
                await provider.invalidateCredentials(.tokens)
            default:
                throw error
            }
            return try await authInternal(
                provider: provider,
                serverURL: serverURL,
                authorizationCode: authorizationCode,
                callbackState: callbackState,
                scope: scope,
                resourceMetadataURL: resourceMetadataURL,
                protocolVersion: protocolVersion,
                transport: transport
            )
        }
    }

    public static func auth(
        provider: any MCPOAuthClientProvider,
        serverURL: String,
        authorizationCode: String? = nil,
        callbackState: String? = nil,
        scope: String? = nil,
        resourceMetadataURL: String? = nil,
        protocolVersion: String = MCPClient.latestProtocolVersion,
        transport: any AITransport = URLSessionTransport.shared
    ) async throws -> MCPOAuthAuthResult {
        try await auth(
            provider: provider,
            serverURL: requireURL(serverURL),
            authorizationCode: authorizationCode,
            callbackState: callbackState,
            scope: scope,
            resourceMetadataURL: try resourceMetadataURL.map(requireURL),
            protocolVersion: protocolVersion,
            transport: transport
        )
    }

    public static func selectResourceURL(
        serverURL: URL,
        provider: any MCPOAuthClientProvider,
        resourceMetadata: MCPOAuthProtectedResourceMetadata?
    ) async throws -> URL? {
        let defaultResource = resourceURLFromServerURL(serverURL)
        if let validated = try await provider.validateResourceURL(
            serverURL: defaultResource,
            resource: resourceMetadata?.resource
        ) {
            return validated
        }
        guard let resourceMetadata else { return nil }
        guard checkResourceAllowed(requestedResource: defaultResource, configuredResource: resourceMetadata.resource) else {
            throw MCPClientError(
                message: "Protected resource \(resourceMetadata.resource.absoluteString) does not match expected \(defaultResource.absoluteString) (or origin)"
            )
        }
        return resourceMetadata.resource
    }

    public static func startAuthorization(
        authorizationServerURL: URL,
        metadata: MCPOAuthAuthorizationServerMetadata? = nil,
        clientInformation: MCPOAuthClientInformation,
        redirectURL: URL,
        scope: String? = nil,
        state: String? = nil,
        resource: URL? = nil,
        codeVerifier: String? = nil
    ) throws -> MCPOAuthStartAuthorizationResult {
        let responseType = "code"
        let codeChallengeMethod = "S256"

        let authorizationURL: URL
        if let metadata {
            guard metadata.responseTypesSupported.contains(responseType) else {
                throw MCPClientError(message: "Incompatible auth server: does not support response type \(responseType)")
            }
            guard metadata.codeChallengeMethodsSupported.contains(codeChallengeMethod) else {
                throw MCPClientError(message: "Incompatible auth server: does not support code challenge method \(codeChallengeMethod)")
            }
            authorizationURL = metadata.authorizationEndpoint
        } else {
            authorizationURL = URL(string: "/authorize", relativeTo: authorizationServerURL)?.absoluteURL ?? authorizationServerURL
        }

        let verifier = codeVerifier ?? generateCodeVerifier()
        let challenge = codeChallenge(for: verifier)
        var components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        var queryItems = components.queryItems ?? []
        queryItems.set(name: "response_type", value: responseType)
        queryItems.set(name: "client_id", value: clientInformation.clientID)
        queryItems.set(name: "code_challenge", value: challenge)
        queryItems.set(name: "code_challenge_method", value: codeChallengeMethod)
        queryItems.set(name: "redirect_uri", value: redirectURL.absoluteString)
        if let state {
            queryItems.set(name: "state", value: state)
        }
        if let scope {
            queryItems.set(name: "scope", value: scope)
            if scope.contains("offline_access") {
                queryItems.append(URLQueryItem(name: "prompt", value: "consent"))
            }
        }
        if let resource {
            queryItems.set(name: "resource", value: resourceURLStripSlash(resource))
        }
        components.queryItems = queryItems
        return MCPOAuthStartAuthorizationResult(
            authorizationURL: components.url ?? authorizationURL,
            codeVerifier: verifier
        )
    }

    public static func startAuthorization(
        authorizationServerURL: String,
        metadata: MCPOAuthAuthorizationServerMetadata? = nil,
        clientInformation: MCPOAuthClientInformation,
        redirectURL: String,
        scope: String? = nil,
        state: String? = nil,
        resource: String? = nil,
        codeVerifier: String? = nil
    ) throws -> MCPOAuthStartAuthorizationResult {
        try startAuthorization(
            authorizationServerURL: requireURL(authorizationServerURL),
            metadata: metadata,
            clientInformation: clientInformation,
            redirectURL: requireURL(redirectURL),
            scope: scope,
            state: state,
            resource: try resource.map(requireURL),
            codeVerifier: codeVerifier
        )
    }

    public static func exchangeAuthorization(
        authorizationServerURL: URL,
        metadata: MCPOAuthAuthorizationServerMetadata? = nil,
        clientInformation: MCPOAuthClientInformation,
        authorizationCode: String,
        codeVerifier: String,
        redirectURI: URL,
        resource: URL? = nil,
        clientAuthentication: MCPOAuthClientAuthenticationHandler? = nil,
        transport: any AITransport = URLSessionTransport.shared
    ) async throws -> MCPOAuthTokens {
        let grantType = "authorization_code"
        try validateGrantType(grantType, metadata: metadata)
        let tokenURL = metadata?.tokenEndpoint ?? (URL(string: "/token", relativeTo: authorizationServerURL)?.absoluteURL ?? authorizationServerURL)
        var parameters = [
            URLQueryItem(name: "grant_type", value: grantType),
            URLQueryItem(name: "code", value: authorizationCode),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString)
        ]
        if let resource {
            parameters.set(name: "resource", value: resourceURLStripSlash(resource))
        }
        let response = try await tokenRequest(
            url: tokenURL,
            authorizationServerURL: authorizationServerURL,
            clientInformation: clientInformation,
            metadata: metadata,
            parameters: parameters,
            clientAuthentication: clientAuthentication,
            transport: transport
        )
        return try MCPOAuthTokens(json: response.jsonValue())
    }

    public static func refreshAuthorization(
        authorizationServerURL: URL,
        metadata: MCPOAuthAuthorizationServerMetadata? = nil,
        clientInformation: MCPOAuthClientInformation,
        refreshToken: String,
        resource: URL? = nil,
        clientAuthentication: MCPOAuthClientAuthenticationHandler? = nil,
        transport: any AITransport = URLSessionTransport.shared
    ) async throws -> MCPOAuthTokens {
        let grantType = "refresh_token"
        try validateGrantType(grantType, metadata: metadata)
        let tokenURL = metadata?.tokenEndpoint ?? (URL(string: "/token", relativeTo: authorizationServerURL)?.absoluteURL ?? authorizationServerURL)
        var parameters = [
            URLQueryItem(name: "grant_type", value: grantType),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]
        if let resource {
            parameters.set(name: "resource", value: resourceURLStripSlash(resource))
        }
        let response = try await tokenRequest(
            url: tokenURL,
            authorizationServerURL: authorizationServerURL,
            clientInformation: clientInformation,
            metadata: metadata,
            parameters: parameters,
            clientAuthentication: clientAuthentication,
            transport: transport
        )
        var raw = try response.jsonValue()
        if raw["refresh_token"]?.stringValue == nil, var object = raw.objectValue {
            object["refresh_token"] = .string(refreshToken)
            raw = .object(object)
        }
        return try MCPOAuthTokens(json: raw)
    }

    public static func registerClient(
        authorizationServerURL: URL,
        metadata: MCPOAuthAuthorizationServerMetadata? = nil,
        clientMetadata: MCPOAuthClientMetadata,
        transport: any AITransport = URLSessionTransport.shared
    ) async throws -> MCPOAuthClientInformationFull {
        let registrationURL: URL
        if let metadata {
            guard let endpoint = metadata.registrationEndpoint else {
                throw MCPClientError(message: "Incompatible auth server: does not support dynamic client registration")
            }
            registrationURL = endpoint
        } else {
            registrationURL = URL(string: "/register", relativeTo: authorizationServerURL)?.absoluteURL ?? authorizationServerURL
        }
        let body = try JSONEncoder().encode(clientMetadata.jsonValue)
        let response = try await transport.send(AIHTTPRequest(
            method: "POST",
            url: registrationURL,
            headers: ["Content-Type": "application/json"],
            body: body
        ))
        try throwOAuthServerErrorIfNeeded(response)
        return try MCPOAuthClientInformationFull(json: response.jsonValue())
    }
}

private func authInternal(
    provider: any MCPOAuthClientProvider,
    serverURL: URL,
    authorizationCode: String?,
    callbackState: String?,
    scope: String?,
    resourceMetadataURL: URL?,
    protocolVersion: String,
    transport: any AITransport
) async throws -> MCPOAuthAuthResult {
    var resourceMetadata: MCPOAuthProtectedResourceMetadata?
    var authorizationServerURL: URL?
    do {
        resourceMetadata = try await MCPOAuthDiscovery.discoverProtectedResourceMetadata(
            serverURL: serverURL,
            protocolVersion: protocolVersion,
            resourceMetadataURL: resourceMetadataURL,
            transport: transport
        )
        authorizationServerURL = resourceMetadata?.authorizationServers.first
    } catch {}

    let resolvedAuthorizationServerURL = authorizationServerURL ?? serverURL
    let resource = try await MCPOAuth.selectResourceURL(
        serverURL: serverURL,
        provider: provider,
        resourceMetadata: resourceMetadata
    )
    let metadata = try await MCPOAuthDiscovery.discoverAuthorizationServerMetadata(
        authorizationServerURL: resolvedAuthorizationServerURL,
        protocolVersion: protocolVersion,
        transport: transport
    )

    var clientInformation = try await provider.clientInformation()
    if clientInformation == nil {
        if authorizationCode != nil {
            throw MCPClientError(message: "Existing OAuth client information is required when exchanging an authorization code")
        }
        guard provider.supportsDynamicClientRegistration else {
            throw MCPClientError(message: "OAuth client information must be saveable for dynamic registration")
        }
        let fullInformation = try await MCPOAuth.registerClient(
            authorizationServerURL: resolvedAuthorizationServerURL,
            metadata: metadata,
            clientMetadata: provider.clientMetadata,
            transport: transport
        )
        try await provider.saveClientInformation(fullInformation.clientInformation)
        clientInformation = fullInformation.clientInformation
    }
    guard let clientInformation else {
        throw MCPClientError(message: "OAuth client information is unavailable.")
    }

    if let authorizationCode {
        let expectedState = try await provider.storedState()
        if expectedState != nil, expectedState != callbackState {
            throw MCPClientError(message: "OAuth state parameter mismatch - possible CSRF attack")
        }
        let tokens = try await MCPOAuth.exchangeAuthorization(
            authorizationServerURL: resolvedAuthorizationServerURL,
            metadata: metadata,
            clientInformation: clientInformation,
            authorizationCode: authorizationCode,
            codeVerifier: try await provider.codeVerifier(),
            redirectURI: provider.redirectURL,
            resource: resource,
            clientAuthentication: { request in
                try await provider.authenticateTokenRequest(request)
            },
            transport: transport
        )
        try await provider.saveTokens(tokens)
        return .authorized
    }

    if let refreshToken = try await provider.tokens()?.refreshToken {
        do {
            let tokens = try await MCPOAuth.refreshAuthorization(
                authorizationServerURL: resolvedAuthorizationServerURL,
                metadata: metadata,
                clientInformation: clientInformation,
                refreshToken: refreshToken,
                resource: resource,
                clientAuthentication: { request in
                    try await provider.authenticateTokenRequest(request)
                },
                transport: transport
            )
            try await provider.saveTokens(tokens)
            return .authorized
        } catch let error as MCPOAuthServerError {
            if let code = error.code, code != "server_error" {
                throw error
            }
        } catch {}
    }

    let state = try await provider.state()
    if let state {
        try await provider.saveState(state)
    }
    let started = try MCPOAuth.startAuthorization(
        authorizationServerURL: resolvedAuthorizationServerURL,
        metadata: metadata,
        clientInformation: clientInformation,
        redirectURL: provider.redirectURL,
        scope: scope ?? provider.clientMetadata.scope,
        state: state,
        resource: resource
    )
    try await provider.saveCodeVerifier(started.codeVerifier)
    try await provider.redirectToAuthorization(started.authorizationURL)
    return .redirect
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
        var response = try await discoveryGETWithHeaderRetry(url: discoveryURL, protocolVersion: protocolVersion, transport: transport)

        if resourceMetadataURL == nil,
           shouldFallbackToRoot(response: response, originalURL: serverURL) {
            response = try await discoveryGETWithHeaderRetry(
                url: mcpWellKnownURL(for: serverURL, wellKnownName: "oauth-protected-resource", includePath: false),
                protocolVersion: protocolVersion,
                transport: transport
            )
        }

        guard let response else {
            throw MCPClientError(message: "Resource server does not implement OAuth 2.0 Protected Resource Metadata.")
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
            guard let response = try await discoveryGETWithHeaderRetry(
                url: discoveryURL.url,
                protocolVersion: protocolVersion,
                transport: transport
            ) else {
                continue
            }
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
        headers: protocolVersion.isEmpty ? [:] : ["MCP-Protocol-Version": protocolVersion]
    ))
}

private func discoveryGETWithHeaderRetry(
    url: URL,
    protocolVersion: String,
    transport: any AITransport
) async throws -> AIHTTPResponse? {
    do {
        return try await discoveryGET(url: url, protocolVersion: protocolVersion, transport: transport)
    } catch {
        do {
            return try await discoveryGET(url: url, protocolVersion: "", transport: transport)
        } catch {
            return nil
        }
    }
}

private func tokenRequest(
    url: URL,
    authorizationServerURL: URL,
    clientInformation: MCPOAuthClientInformation,
    metadata: MCPOAuthAuthorizationServerMetadata?,
    parameters: [URLQueryItem],
    clientAuthentication: MCPOAuthClientAuthenticationHandler?,
    transport: any AITransport
) async throws -> AIHTTPResponse {
    var headers = [
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json"
    ]
    var parameters = parameters
    if let customized = try await clientAuthentication?(MCPOAuthClientAuthenticationRequest(
        headers: headers,
        parameters: parameters,
        tokenURL: url,
        authorizationServerURL: authorizationServerURL,
        metadata: metadata
    )) {
        headers = customized.headers
        parameters = customized.parameters
    } else {
        let authMethod = selectClientAuthMethod(
            clientInformation: clientInformation,
            supportedMethods: metadata?.tokenEndpointAuthMethodsSupported ?? []
        )
        try applyClientAuthentication(
            authMethod,
            clientInformation: clientInformation,
            headers: &headers,
            parameters: &parameters
        )
    }
    let response = try await transport.send(AIHTTPRequest(
        method: "POST",
        url: url,
        headers: headers,
        body: Data(formEncoded(parameters).utf8)
    ))
    try throwOAuthServerErrorIfNeeded(response)
    return response
}

private func validateGrantType(_ grantType: String, metadata: MCPOAuthAuthorizationServerMetadata?) throws {
    guard let metadata, !metadata.grantTypesSupported.isEmpty else { return }
    guard metadata.grantTypesSupported.contains(grantType) else {
        throw MCPClientError(message: "Incompatible auth server: does not support grant type \(grantType)")
    }
}

private func selectClientAuthMethod(
    clientInformation: MCPOAuthClientInformation,
    supportedMethods: [String]
) -> MCPOAuthClientAuthMethod {
    let hasClientSecret = clientInformation.clientSecret != nil
    if supportedMethods.isEmpty {
        return hasClientSecret ? .clientSecretPost : .none
    }
    if hasClientSecret, supportedMethods.contains(MCPOAuthClientAuthMethod.clientSecretBasic.rawValue) {
        return .clientSecretBasic
    }
    if hasClientSecret, supportedMethods.contains(MCPOAuthClientAuthMethod.clientSecretPost.rawValue) {
        return .clientSecretPost
    }
    if supportedMethods.contains(MCPOAuthClientAuthMethod.none.rawValue) {
        return .none
    }
    return hasClientSecret ? .clientSecretPost : .none
}

private func applyClientAuthentication(
    _ method: MCPOAuthClientAuthMethod,
    clientInformation: MCPOAuthClientInformation,
    headers: inout [String: String],
    parameters: inout [URLQueryItem]
) throws {
    switch method {
    case .clientSecretBasic:
        guard let clientSecret = clientInformation.clientSecret else {
            throw MCPClientError(message: "client_secret_basic authentication requires a client_secret")
        }
        let credentials = Data("\(clientInformation.clientID):\(clientSecret)".utf8).base64EncodedString()
        headers["Authorization"] = "Basic \(credentials)"
    case .clientSecretPost:
        parameters.set(name: "client_id", value: clientInformation.clientID)
        if let clientSecret = clientInformation.clientSecret {
            parameters.set(name: "client_secret", value: clientSecret)
        }
    case .none:
        parameters.set(name: "client_id", value: clientInformation.clientID)
    }
}

private func throwOAuthServerErrorIfNeeded(_ response: AIHTTPResponse) throws {
    guard !(200..<300).contains(response.statusCode) else { return }
    if let raw = try? response.jsonValue(), let error = raw["error"]?.stringValue {
        throw MCPOAuthServerError(
            statusCode: response.statusCode,
            code: error,
            message: raw["error_description"]?.stringValue ?? "",
            uri: raw["error_uri"]?.stringValue
        )
    }
    throw MCPOAuthServerError(
        statusCode: response.statusCode,
        message: "HTTP \(response.statusCode): Invalid OAuth error response. Raw body: \(response.bodyText)"
    )
}

private func generateCodeVerifier() -> String {
    var bytes = [UInt8]()
    bytes.reserveCapacity(32)
    for _ in 0..<32 {
        bytes.append(UInt8.random(in: UInt8.min...UInt8.max))
    }
    return base64URL(Data(bytes))
}

private func codeChallenge(for verifier: String) -> String {
    base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func resourceURLStripSlash(_ resource: URL) -> String {
    let href = resource.absoluteString
    if resource.path == "/", href.hasSuffix("/") {
        return String(href.dropLast())
    }
    return href
}

private func resourceURLFromServerURL(_ url: URL) -> URL {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.fragment = nil
    return components?.url ?? url
}

private func checkResourceAllowed(requestedResource: URL, configuredResource: URL) -> Bool {
    guard requestedResource.scheme == configuredResource.scheme,
          requestedResource.host == configuredResource.host,
          requestedResource.port == configuredResource.port else {
        return false
    }
    let requestedPath = requestedResource.path.hasSuffix("/") ? requestedResource.path : "\(requestedResource.path)/"
    let configuredPath = configuredResource.path.hasSuffix("/") ? configuredResource.path : "\(configuredResource.path)/"
    guard requestedPath.count >= configuredPath.count else { return false }
    return requestedPath.hasPrefix(configuredPath)
}

private func formEncoded(_ items: [URLQueryItem]) -> String {
    items.map { item in
        "\(urlFormEncode(item.name))=\(urlFormEncode(item.value ?? ""))"
    }.joined(separator: "&")
}

private func urlFormEncode(_ value: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&+=")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

private func shouldFallbackToRoot(response: AIHTTPResponse?, originalURL: URL) -> Bool {
    guard originalURL.path != "" && originalURL.path != "/" else { return false }
    guard let response else { return true }
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

private extension Array where Element == URLQueryItem {
    mutating func set(name: String, value: String) {
        removeAll { $0.name == name }
        append(URLQueryItem(name: name, value: value))
    }
}
