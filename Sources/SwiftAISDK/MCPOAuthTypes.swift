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

    init(json: JSONValue, sourceURL: URL, sourceType: MCPOAuthDiscoveryURL.Kind, expectedIssuer: String? = nil) throws {
        guard let issuer = json["issuer"]?.stringValue,
              let authorizationEndpoint = json["authorization_endpoint"]?.stringValue.flatMap(URL.init(string:)),
              let tokenEndpoint = json["token_endpoint"]?.stringValue.flatMap(URL.init(string:)) else {
            throw MCPClientError(message: "Expected OAuth authorization server metadata with issuer, authorization_endpoint, and token_endpoint.")
        }
        if let expectedIssuer, issuer != expectedIssuer {
            throw MCPClientError(
                message: "OAuth authorization server metadata issuer \(issuer) does not match expected issuer \(expectedIssuer)"
            )
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
    public var authorizationServerURL: URL?
    public var tokenEndpoint: URL?
    public var rawValue: JSONValue

    public init(
        accessToken: String,
        idToken: String? = nil,
        tokenType: String,
        expiresIn: Int? = nil,
        scope: String? = nil,
        refreshToken: String? = nil,
        authorizationServerURL: URL? = nil,
        tokenEndpoint: URL? = nil,
        rawValue: JSONValue = .object([:])
    ) {
        self.accessToken = accessToken
        self.idToken = idToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.scope = scope
        self.refreshToken = refreshToken
        self.authorizationServerURL = authorizationServerURL
        self.tokenEndpoint = tokenEndpoint
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
            authorizationServerURL: json["authorization_server"]?.stringValue.flatMap(URL.init(string:)),
            tokenEndpoint: json["token_endpoint"]?.stringValue.flatMap(URL.init(string:)),
            rawValue: json
        )
    }
}

public struct MCPOAuthClientInformation: Equatable, Sendable {
    public var clientID: String
    public var clientSecret: String?
    public var clientIDIssuedAt: Int?
    public var clientSecretExpiresAt: Int?
    public var authorizationServerURL: URL?
    public var tokenEndpoint: URL?
    public var rawValue: JSONValue

    public init(
        clientID: String,
        clientSecret: String? = nil,
        clientIDIssuedAt: Int? = nil,
        clientSecretExpiresAt: Int? = nil,
        authorizationServerURL: URL? = nil,
        tokenEndpoint: URL? = nil,
        rawValue: JSONValue = .object([:])
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.clientIDIssuedAt = clientIDIssuedAt
        self.clientSecretExpiresAt = clientSecretExpiresAt
        self.authorizationServerURL = authorizationServerURL
        self.tokenEndpoint = tokenEndpoint
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
            authorizationServerURL: json["authorization_server"]?.stringValue.flatMap(URL.init(string:)),
            tokenEndpoint: json["token_endpoint"]?.stringValue.flatMap(URL.init(string:)),
            rawValue: json
        )
    }
}

public struct MCPOAuthAuthorizationServerInformation: Equatable, Sendable {
    public var authorizationServerURL: URL
    public var tokenEndpoint: URL

    public init(authorizationServerURL: URL, tokenEndpoint: URL) {
        self.authorizationServerURL = authorizationServerURL
        self.tokenEndpoint = tokenEndpoint
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
    func authorizationServerInformation() async throws -> MCPOAuthAuthorizationServerInformation?
    func saveAuthorizationServerInformation(_ information: MCPOAuthAuthorizationServerInformation) async throws
    var supportsDynamicClientRegistration: Bool { get }

    func state() async throws -> String?
    func saveState(_ state: String) async throws
    func storedState() async throws -> String?
    func validateResourceURL(serverURL: URL, resource: URL?) async throws -> URL?
    func validateAuthorizationServerURL(serverURL: URL, authorizationServerURL: URL) async throws
    func authenticateTokenRequest(_ request: MCPOAuthClientAuthenticationRequest) async throws -> MCPOAuthClientAuthenticationRequest?
}

public extension MCPOAuthClientProvider {
    func invalidateCredentials(_ scope: MCPOAuthCredentialScope) async {}

    func clientInformation() async throws -> MCPOAuthClientInformation? { nil }
    func saveClientInformation(_ clientInformation: MCPOAuthClientInformation) async throws {}
    func authorizationServerInformation() async throws -> MCPOAuthAuthorizationServerInformation? { nil }
    func saveAuthorizationServerInformation(_ information: MCPOAuthAuthorizationServerInformation) async throws {}
    var supportsDynamicClientRegistration: Bool { false }

    func state() async throws -> String? { nil }
    func saveState(_ state: String) async throws {}
    func storedState() async throws -> String? { nil }
    func validateResourceURL(serverURL: URL, resource: URL?) async throws -> URL? { nil }
    func validateAuthorizationServerURL(serverURL: URL, authorizationServerURL: URL) async throws {}
    func authenticateTokenRequest(_ request: MCPOAuthClientAuthenticationRequest) async throws -> MCPOAuthClientAuthenticationRequest? { nil }
}
