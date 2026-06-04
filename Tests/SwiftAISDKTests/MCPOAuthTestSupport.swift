import Foundation
import Testing
@testable import SwiftAISDK

func oauthAuthorizationMetadataResponse() -> AIHTTPResponse {
    jsonResponse("""
    {
      "issuer": "https://auth.example.com",
      "authorization_endpoint": "https://auth.example.com/authorize",
      "token_endpoint": "https://auth.example.com/token",
      "registration_endpoint": "https://auth.example.com/register",
      "response_types_supported": ["code"],
      "code_challenge_methods_supported": ["S256"],
      "grant_types_supported": ["authorization_code", "refresh_token"],
      "token_endpoint_auth_methods_supported": ["none", "client_secret_post"]
    }
    """)
}
actor TestOAuthClientProvider: MCPOAuthClientProvider {
    nonisolated let redirectURL: URL
    nonisolated let clientMetadata: MCPOAuthClientMetadata
    nonisolated let supportsDynamicClientRegistration: Bool

    private var currentTokens: MCPOAuthTokens?
    private var currentClientInformation: MCPOAuthClientInformation?
    private var currentCodeVerifier: String
    private var currentState: String?
    private var currentStoredState: String?
    private var savedTokenValue: MCPOAuthTokens?
    private var savedClientInformationValue: MCPOAuthClientInformation?
    private var savedStateValue: String?
    private var savedCodeVerifierValue: String?
    private var redirectedURLValue: URL?
    private var invalidationValues: [MCPOAuthCredentialScope] = []
    private let customAuthentication: MCPOAuthClientAuthenticationHandler?

    init(
        redirectURL: URL = URL(string: "http://localhost:3000/callback")!,
        clientMetadata: MCPOAuthClientMetadata = MCPOAuthClientMetadata(
            redirectURIs: [URL(string: "http://localhost:3000/callback")!],
            clientName: "Swift MCP Test",
            scope: "default-scope"
        ),
        clientInformation: MCPOAuthClientInformation?,
        tokens: MCPOAuthTokens? = nil,
        codeVerifier: String = "stored-verifier",
        state: String? = nil,
        storedState: String? = nil,
        supportsDynamicClientRegistration: Bool = false,
        customAuthentication: MCPOAuthClientAuthenticationHandler? = nil
    ) {
        self.redirectURL = redirectURL
        self.clientMetadata = clientMetadata
        self.supportsDynamicClientRegistration = supportsDynamicClientRegistration
        self.currentClientInformation = clientInformation
        self.currentTokens = tokens
        self.currentCodeVerifier = codeVerifier
        self.currentState = state
        self.currentStoredState = storedState
        self.customAuthentication = customAuthentication
    }

    func tokens() async throws -> MCPOAuthTokens? {
        currentTokens
    }

    func saveTokens(_ tokens: MCPOAuthTokens) async throws {
        currentTokens = tokens
        savedTokenValue = tokens
    }

    func redirectToAuthorization(_ authorizationURL: URL) async throws {
        redirectedURLValue = authorizationURL
    }

    func saveCodeVerifier(_ codeVerifier: String) async throws {
        currentCodeVerifier = codeVerifier
        savedCodeVerifierValue = codeVerifier
    }

    func codeVerifier() async throws -> String {
        currentCodeVerifier
    }

    func invalidateCredentials(_ scope: MCPOAuthCredentialScope) async {
        invalidationValues.append(scope)
        if scope == .all || scope == .tokens {
            currentTokens = nil
        }
        if scope == .all || scope == .client {
            currentClientInformation = nil
        }
    }

    func clientInformation() async throws -> MCPOAuthClientInformation? {
        currentClientInformation
    }

    func saveClientInformation(_ clientInformation: MCPOAuthClientInformation) async throws {
        currentClientInformation = clientInformation
        savedClientInformationValue = clientInformation
    }

    func state() async throws -> String? {
        currentState
    }

    func saveState(_ state: String) async throws {
        currentStoredState = state
        savedStateValue = state
    }

    func storedState() async throws -> String? {
        currentStoredState
    }

    func authenticateTokenRequest(_ request: MCPOAuthClientAuthenticationRequest) async throws -> MCPOAuthClientAuthenticationRequest? {
        try await customAuthentication?(request)
    }

    func savedTokens() -> MCPOAuthTokens? {
        savedTokenValue
    }

    func savedClientInformation() -> MCPOAuthClientInformation? {
        savedClientInformationValue
    }

    func savedState() -> String? {
        savedStateValue
    }

    func savedCodeVerifier() -> String? {
        savedCodeVerifierValue
    }

    func redirectedURL() -> URL? {
        redirectedURLValue
    }

    func invalidations() -> [MCPOAuthCredentialScope] {
        invalidationValues
    }
}
enum DiscoveryTransportAction: Sendable {
    case fail
    case respond(AIHTTPResponse)
}
struct DiscoveryTransportError: Error {}
actor FailingDiscoveryTransport: AITransport {
    private var recordedRequests: [AIHTTPRequest] = []
    private var actions: [DiscoveryTransportAction]

    init(actions: [DiscoveryTransportAction]) {
        self.actions = actions
    }

    func requests() -> [AIHTTPRequest] {
        recordedRequests
    }

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        recordedRequests.append(request)
        guard !actions.isEmpty else {
            throw DiscoveryTransportError()
        }
        switch actions.removeFirst() {
        case .fail:
            throw DiscoveryTransportError()
        case let .respond(response):
            return response
        }
    }
}
func queryItems(_ url: URL) throws -> [String: String] {
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}
func formItems(_ request: AIHTTPRequest) throws -> [String: String] {
    let body = String(data: try #require(request.body), encoding: .utf8) ?? ""
    return Dictionary(uniqueKeysWithValues: body.split(separator: "&").map { pair in
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        let name = parts[0].removingPercentEncoding ?? parts[0]
        let value = parts.count > 1 ? (parts[1].removingPercentEncoding ?? parts[1]) : ""
        return (name, value)
    })
}
