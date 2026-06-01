import Foundation
import Testing
@testable import SwiftAISDK

@Test func mcpOAuthProtectedResourceDiscoveryUsesPathAndPreservesQuery() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "resource": "https://resource.example.com",
      "authorization_servers": ["https://auth.example.com"],
      "scopes_supported": ["email", "mcp"]
    }
    """))

    let metadata = try await MCPOAuthDiscovery.discoverProtectedResourceMetadata(
        serverURL: "https://resource.example.com/path?param=value",
        transport: transport
    )

    #expect(metadata.resource.absoluteString == "https://resource.example.com")
    #expect(metadata.authorizationServers.map(\.absoluteString) == ["https://auth.example.com"])
    #expect(metadata.scopesSupported == ["email", "mcp"])

    let request = try await #require(transport.requests().first)
    #expect(request.method == "GET")
    #expect(request.url.absoluteString == "https://resource.example.com/.well-known/oauth-protected-resource/path?param=value")
    #expect(request.headers["MCP-Protocol-Version"] == MCPClient.latestProtocolVersion)
}

@Test func mcpOAuthProtectedResourceDiscoveryFallsBackToRootOnPath4xx() async throws {
    let transport = RecordingTransport(responses: [
        AIHTTPResponse(statusCode: 404),
        jsonResponse("""
        {
          "resource": "https://resource.example.com",
          "authorization_servers": ["https://auth.example.com"]
        }
        """)
    ])

    let metadata = try await MCPOAuthDiscovery.discoverProtectedResourceMetadata(
        serverURL: "https://resource.example.com/path/name",
        transport: transport
    )

    #expect(metadata.authorizationServers.first?.absoluteString == "https://auth.example.com")
    let requests = await transport.requests()
    #expect(requests.map { $0.url.absoluteString } == [
        "https://resource.example.com/.well-known/oauth-protected-resource/path/name",
        "https://resource.example.com/.well-known/oauth-protected-resource"
    ])
}

@Test func mcpOAuthProtectedResourceDiscoveryThrowsForMissingMetadata() async throws {
    let transport = RecordingTransport(responses: [
        AIHTTPResponse(statusCode: 404),
        AIHTTPResponse(statusCode: 404)
    ])

    do {
        _ = try await MCPOAuthDiscovery.discoverProtectedResourceMetadata(
            serverURL: "https://resource.example.com/path/name",
            transport: transport
        )
        Issue.record("Expected protected-resource discovery to throw.")
    } catch let error as MCPClientError {
        #expect(error.message == "Resource server does not implement OAuth 2.0 Protected Resource Metadata.")
    }
}

@Test func mcpOAuthAuthorizationServerDiscoveryTriesPathAwareThenRoot() async throws {
    let transport = RecordingTransport(responses: [
        AIHTTPResponse(statusCode: 404),
        jsonResponse("""
        {
          "issuer": "https://auth.example.com",
          "authorization_endpoint": "https://auth.example.com/authorize",
          "token_endpoint": "https://auth.example.com/token",
          "registration_endpoint": "https://auth.example.com/register",
          "response_types_supported": ["code"],
          "code_challenge_methods_supported": ["S256"]
        }
        """)
    ])

    let metadata = try await MCPOAuthDiscovery.discoverAuthorizationServerMetadata(
        authorizationServerURL: "https://auth.example.com/tenant1",
        transport: transport
    )

    #expect(metadata?.issuer == "https://auth.example.com")
    #expect(metadata?.authorizationEndpoint.absoluteString == "https://auth.example.com/authorize")
    #expect(metadata?.registrationEndpoint?.absoluteString == "https://auth.example.com/register")
    let requests = await transport.requests()
    #expect(requests.map { $0.url.absoluteString } == [
        "https://auth.example.com/.well-known/oauth-authorization-server/tenant1",
        "https://auth.example.com/.well-known/oauth-authorization-server"
    ])
}

@Test func mcpOAuthAuthorizationServerDiscoveryRejectsOIDCWithoutS256() async throws {
    let transport = RecordingTransport(responses: [
        AIHTTPResponse(statusCode: 404),
        jsonResponse("""
        {
          "issuer": "https://auth.example.com",
          "authorization_endpoint": "https://auth.example.com/authorize",
          "token_endpoint": "https://auth.example.com/token",
          "jwks_uri": "https://auth.example.com/jwks",
          "subject_types_supported": ["public"],
          "id_token_signing_alg_values_supported": ["RS256"],
          "response_types_supported": ["code"],
          "code_challenge_methods_supported": ["plain"]
        }
        """)
    ])

    do {
        _ = try await MCPOAuthDiscovery.discoverAuthorizationServerMetadata(
            authorizationServerURL: "https://auth.example.com",
            transport: transport
        )
        Issue.record("Expected OIDC metadata without S256 to throw.")
    } catch let error as MCPClientError {
        #expect(error.message.contains("does not support S256 code challenge method"))
    }
}

@Test func mcpOAuthAuthorizationServerDiscoveryReturnsNilWhenAllCandidatesAre4xx() async throws {
    let transport = RecordingTransport(responses: [
        AIHTTPResponse(statusCode: 404),
        AIHTTPResponse(statusCode: 404),
        AIHTTPResponse(statusCode: 404),
        AIHTTPResponse(statusCode: 404)
    ])

    let metadata = try await MCPOAuthDiscovery.discoverAuthorizationServerMetadata(
        authorizationServerURL: "https://auth.example.com/tenant1",
        transport: transport
    )

    #expect(metadata == nil)
    let requests = await transport.requests()
    #expect(requests.map { $0.url.absoluteString } == [
        "https://auth.example.com/.well-known/oauth-authorization-server/tenant1",
        "https://auth.example.com/.well-known/oauth-authorization-server",
        "https://auth.example.com/.well-known/openid-configuration/tenant1",
        "https://auth.example.com/tenant1/.well-known/openid-configuration"
    ])
}

@Test func mcpOAuthAuthorizationServerDiscoveryBuildsRootURLs() throws {
    let urls = MCPOAuthDiscovery.buildAuthorizationServerDiscoveryURLs(try requireURL("https://auth.example.com"))
    #expect(urls.map(\.absoluteString) == [
        "https://auth.example.com/.well-known/oauth-authorization-server",
        "https://auth.example.com/.well-known/openid-configuration"
    ])
}

@Test func mcpOAuthStartAuthorizationBuildsPKCEURL() throws {
    let metadata = MCPOAuthAuthorizationServerMetadata(
        issuer: "https://auth.example.com",
        authorizationEndpoint: try requireURL("https://auth.example.com/auth?existing=1"),
        tokenEndpoint: try requireURL("https://auth.example.com/token"),
        responseTypesSupported: ["code"],
        codeChallengeMethodsSupported: ["S256"]
    )

    let result = try MCPOAuth.startAuthorization(
        authorizationServerURL: "https://auth.example.com",
        metadata: metadata,
        clientInformation: MCPOAuthClientInformation(clientID: "client123"),
        redirectURL: "http://localhost:3000/callback",
        scope: "read offline_access",
        state: "state123",
        resource: "https://api.example.com/mcp-server",
        codeVerifier: "test_verifier"
    )

    let query = try queryItems(result.authorizationURL)
    #expect(result.codeVerifier == "test_verifier")
    #expect(result.authorizationURL.absoluteString.hasPrefix("https://auth.example.com/auth?"))
    #expect(query["existing"] == "1")
    #expect(query["response_type"] == "code")
    #expect(query["client_id"] == "client123")
    #expect(query["code_challenge"] == "0Ku4rR8EgR1w3HyHLBCxVLtPsAAks5HOlpmTEt0XhVA")
    #expect(query["code_challenge_method"] == "S256")
    #expect(query["redirect_uri"] == "http://localhost:3000/callback")
    #expect(query["scope"] == "read offline_access")
    #expect(query["state"] == "state123")
    #expect(query["prompt"] == "consent")
    #expect(query["resource"] == "https://api.example.com/mcp-server")
}

@Test func mcpOAuthStartAuthorizationValidatesMetadataCapabilities() throws {
    let metadata = MCPOAuthAuthorizationServerMetadata(
        issuer: "https://auth.example.com",
        authorizationEndpoint: try requireURL("https://auth.example.com/auth"),
        tokenEndpoint: try requireURL("https://auth.example.com/token"),
        responseTypesSupported: ["token"],
        codeChallengeMethodsSupported: ["S256"]
    )

    do {
        _ = try MCPOAuth.startAuthorization(
            authorizationServerURL: "https://auth.example.com",
            metadata: metadata,
            clientInformation: MCPOAuthClientInformation(clientID: "client123"),
            redirectURL: "http://localhost:3000/callback"
        )
        Issue.record("Expected authorization metadata validation to throw.")
    } catch let error as MCPClientError {
        #expect(error.message == "Incompatible auth server: does not support response type code")
    }
}

@Test func mcpOAuthExchangeAuthorizationPostsFormWithBasicClientAuth() async throws {
    let metadata = MCPOAuthAuthorizationServerMetadata(
        issuer: "https://auth.example.com",
        authorizationEndpoint: try requireURL("https://auth.example.com/auth"),
        tokenEndpoint: try requireURL("https://auth.example.com/token"),
        responseTypesSupported: ["code"],
        codeChallengeMethodsSupported: ["S256"],
        grantTypesSupported: ["authorization_code"],
        tokenEndpointAuthMethodsSupported: ["client_secret_basic"]
    )
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "access_token": "access-123",
      "token_type": "Bearer",
      "expires_in": 3600,
      "refresh_token": "refresh-123"
    }
    """))

    let tokens = try await MCPOAuth.exchangeAuthorization(
        authorizationServerURL: try requireURL("https://auth.example.com"),
        metadata: metadata,
        clientInformation: MCPOAuthClientInformation(clientID: "client123", clientSecret: "secret123"),
        authorizationCode: "code123",
        codeVerifier: "verifier123",
        redirectURI: try requireURL("http://localhost:3000/callback"),
        resource: try requireURL("https://api.example.com"),
        transport: transport
    )

    #expect(tokens.accessToken == "access-123")
    #expect(tokens.refreshToken == "refresh-123")
    let request = try await #require(transport.requests().first)
    #expect(request.method == "POST")
    #expect(request.url.absoluteString == "https://auth.example.com/token")
    #expect(request.headers["Content-Type"] == "application/x-www-form-urlencoded")
    #expect(request.headers["Accept"] == "application/json")
    #expect(request.headers["Authorization"] == "Basic Y2xpZW50MTIzOnNlY3JldDEyMw==")
    let form = try formItems(request)
    #expect(form["grant_type"] == "authorization_code")
    #expect(form["code"] == "code123")
    #expect(form["code_verifier"] == "verifier123")
    #expect(form["redirect_uri"] == "http://localhost:3000/callback")
    #expect(form["resource"] == "https://api.example.com")
    #expect(form["client_id"] == nil)
}

@Test func mcpOAuthExchangeAuthorizationUsesCustomClientAuthentication() async throws {
    let metadata = MCPOAuthAuthorizationServerMetadata(
        issuer: "https://auth.example.com",
        authorizationEndpoint: try requireURL("https://auth.example.com/auth"),
        tokenEndpoint: try requireURL("https://auth.example.com/token"),
        responseTypesSupported: ["code"],
        codeChallengeMethodsSupported: ["S256"],
        grantTypesSupported: ["authorization_code"],
        tokenEndpointAuthMethodsSupported: ["client_secret_basic"]
    )
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "access_token": "access-123",
      "token_type": "Bearer"
    }
    """))

    _ = try await MCPOAuth.exchangeAuthorization(
        authorizationServerURL: try requireURL("https://auth.example.com"),
        metadata: metadata,
        clientInformation: MCPOAuthClientInformation(clientID: "client123", clientSecret: "secret123"),
        authorizationCode: "code123",
        codeVerifier: "verifier123",
        redirectURI: try requireURL("http://localhost:3000/callback"),
        clientAuthentication: { request in
            var customized = request
            customized.headers["X-Client-Assertion"] = "assertion-123"
            customized.parameters.append(URLQueryItem(name: "client_assertion_type", value: "jwt-bearer"))
            customized.parameters.append(URLQueryItem(name: "client_assertion", value: "jwt-token"))
            return customized
        },
        transport: transport
    )

    let request = try await #require(transport.requests().first)
    #expect(request.headers["Authorization"] == nil)
    #expect(request.headers["X-Client-Assertion"] == "assertion-123")
    let form = try formItems(request)
    #expect(form["client_id"] == nil)
    #expect(form["client_secret"] == nil)
    #expect(form["client_assertion_type"] == "jwt-bearer")
    #expect(form["client_assertion"] == "jwt-token")
}

@Test func mcpOAuthRefreshAuthorizationPreservesRefreshTokenAndUsesPublicClientAuth() async throws {
    let metadata = MCPOAuthAuthorizationServerMetadata(
        issuer: "https://auth.example.com",
        authorizationEndpoint: try requireURL("https://auth.example.com/auth"),
        tokenEndpoint: try requireURL("https://auth.example.com/token"),
        responseTypesSupported: ["code"],
        codeChallengeMethodsSupported: ["S256"],
        grantTypesSupported: ["refresh_token"],
        tokenEndpointAuthMethodsSupported: ["none"]
    )
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "access_token": "new-access",
      "token_type": "Bearer"
    }
    """))

    let tokens = try await MCPOAuth.refreshAuthorization(
        authorizationServerURL: try requireURL("https://auth.example.com"),
        metadata: metadata,
        clientInformation: MCPOAuthClientInformation(clientID: "public-client"),
        refreshToken: "old-refresh",
        resource: try requireURL("https://api.example.com/"),
        transport: transport
    )

    #expect(tokens.accessToken == "new-access")
    #expect(tokens.refreshToken == "old-refresh")
    let request = try await #require(transport.requests().first)
    let form = try formItems(request)
    #expect(form["grant_type"] == "refresh_token")
    #expect(form["refresh_token"] == "old-refresh")
    #expect(form["client_id"] == "public-client")
    #expect(form["resource"] == "https://api.example.com")
}

@Test func mcpOAuthRegisterClientPostsMetadataAndParsesFullInformation() async throws {
    let metadata = MCPOAuthAuthorizationServerMetadata(
        issuer: "https://auth.example.com",
        authorizationEndpoint: try requireURL("https://auth.example.com/auth"),
        tokenEndpoint: try requireURL("https://auth.example.com/token"),
        registrationEndpoint: try requireURL("https://auth.example.com/register"),
        responseTypesSupported: ["code"],
        codeChallengeMethodsSupported: ["S256"]
    )
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "client_id": "registered-client",
      "client_secret": "registered-secret",
      "redirect_uris": ["http://localhost:3000/callback"],
      "client_name": "Swift MCP Client",
      "token_endpoint_auth_method": "client_secret_post"
    }
    """))

    let information = try await MCPOAuth.registerClient(
        authorizationServerURL: try requireURL("https://auth.example.com"),
        metadata: metadata,
        clientMetadata: MCPOAuthClientMetadata(
            redirectURIs: [try requireURL("http://localhost:3000/callback")],
            tokenEndpointAuthMethod: "client_secret_post",
            grantTypes: ["authorization_code", "refresh_token"],
            responseTypes: ["code"],
            clientName: "Swift MCP Client",
            scope: "read write"
        ),
        transport: transport
    )

    #expect(information.clientInformation.clientID == "registered-client")
    #expect(information.clientInformation.clientSecret == "registered-secret")
    #expect(information.clientMetadata.clientName == "Swift MCP Client")
    let request = try await #require(transport.requests().first)
    #expect(request.method == "POST")
    #expect(request.url.absoluteString == "https://auth.example.com/register")
    #expect(request.headers["Content-Type"] == "application/json")
    let body = try JSONDecoder().decode(JSONValue.self, from: try #require(request.body))
    #expect(body["redirect_uris"]?.arrayValue?.compactMap(\.stringValue) == ["http://localhost:3000/callback"])
    #expect(body["grant_types"]?.arrayValue?.compactMap(\.stringValue) == ["authorization_code", "refresh_token"])
    #expect(body["client_name"]?.stringValue == "Swift MCP Client")
    #expect(body["scope"]?.stringValue == "read write")
}

@Test func mcpOAuthTokenEndpointThrowsParsedServerErrors() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 400,
        headers: ["content-type": "application/json"],
        body: Data("""
        {
          "error": "invalid_grant",
          "error_description": "Bad code",
          "error_uri": "https://auth.example.com/errors/invalid_grant"
        }
        """.utf8)
    ))

    do {
        _ = try await MCPOAuth.exchangeAuthorization(
            authorizationServerURL: try requireURL("https://auth.example.com"),
            clientInformation: MCPOAuthClientInformation(clientID: "public-client"),
            authorizationCode: "bad-code",
            codeVerifier: "verifier",
            redirectURI: try requireURL("http://localhost:3000/callback"),
            transport: transport
        )
        Issue.record("Expected token exchange error response to throw.")
    } catch let error as MCPOAuthServerError {
        #expect(error.statusCode == 400)
        #expect(error.code == "invalid_grant")
        #expect(error.message == "Bad code")
        #expect(error.uri == "https://auth.example.com/errors/invalid_grant")
    }
}

@Test func mcpOAuthAuthRegistersClientAndRedirectsToAuthorization() async throws {
    let provider = TestOAuthClientProvider(
        clientInformation: nil,
        state: "state123",
        supportsDynamicClientRegistration: true
    )
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {
          "resource": "https://resource.example.com/mcp",
          "authorization_servers": ["https://auth.example.com"]
        }
        """),
        oauthAuthorizationMetadataResponse(),
        jsonResponse("""
        {
          "client_id": "registered-client",
          "client_secret": "registered-secret",
          "redirect_uris": ["http://localhost:3000/callback"],
          "client_name": "Swift MCP Test"
        }
        """)
    ])

    let result = try await MCPOAuth.auth(
        provider: provider,
        serverURL: "https://resource.example.com/mcp/rpc",
        scope: "read",
        transport: transport
    )

    #expect(result == .redirect)
    #expect(await provider.savedClientInformation()?.clientID == "registered-client")
    #expect(await provider.savedState() == "state123")
    #expect(await provider.savedCodeVerifier()?.isEmpty == false)
    let redirect = try await #require(provider.redirectedURL())
    let redirectQuery = try queryItems(redirect)
    #expect(redirect.absoluteString.hasPrefix("https://auth.example.com/authorize?"))
    #expect(redirectQuery["client_id"] == "registered-client")
    #expect(redirectQuery["state"] == "state123")
    #expect(redirectQuery["scope"] == "read")
    #expect(redirectQuery["resource"] == "https://resource.example.com/mcp")

    let requests = await transport.requests()
    #expect(requests.map(\.method) == ["GET", "GET", "POST"])
    #expect(requests.map { $0.url.absoluteString } == [
        "https://resource.example.com/.well-known/oauth-protected-resource/mcp/rpc",
        "https://auth.example.com/.well-known/oauth-authorization-server",
        "https://auth.example.com/register"
    ])
}

@Test func mcpOAuthAuthExchangesCallbackCodeAndValidatesState() async throws {
    let provider = TestOAuthClientProvider(
        clientInformation: MCPOAuthClientInformation(clientID: "client123"),
        codeVerifier: "verifier123",
        storedState: "state123"
    )
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {
          "resource": "https://resource.example.com/mcp",
          "authorization_servers": ["https://auth.example.com"]
        }
        """),
        oauthAuthorizationMetadataResponse(),
        jsonResponse("""
        {
          "access_token": "access-123",
          "token_type": "Bearer",
          "refresh_token": "refresh-123"
        }
        """)
    ])

    let result = try await MCPOAuth.auth(
        provider: provider,
        serverURL: "https://resource.example.com/mcp/rpc",
        authorizationCode: "code123",
        callbackState: "state123",
        transport: transport
    )

    #expect(result == .authorized)
    #expect(await provider.savedTokens()?.accessToken == "access-123")
    let request = try await #require(transport.requests().last)
    let form = try formItems(request)
    #expect(request.url.absoluteString == "https://auth.example.com/token")
    #expect(form["grant_type"] == "authorization_code")
    #expect(form["code"] == "code123")
    #expect(form["code_verifier"] == "verifier123")
    #expect(form["resource"] == "https://resource.example.com/mcp")
}

@Test func mcpOAuthAuthRejectsMismatchedCallbackState() async throws {
    let provider = TestOAuthClientProvider(
        clientInformation: MCPOAuthClientInformation(clientID: "client123"),
        codeVerifier: "verifier123",
        storedState: "expected-state"
    )
    let transport = RecordingTransport(responses: [
        AIHTTPResponse(statusCode: 404),
        oauthAuthorizationMetadataResponse()
    ])

    do {
        _ = try await MCPOAuth.auth(
            provider: provider,
            serverURL: "https://auth.example.com",
            authorizationCode: "code123",
            callbackState: "callback-state",
            transport: transport
        )
        Issue.record("Expected mismatched OAuth state to throw.")
    } catch let error as MCPClientError {
        #expect(error.message == "OAuth state parameter mismatch - possible CSRF attack")
    }
}

@Test func mcpOAuthAuthRefreshesExistingTokens() async throws {
    let provider = TestOAuthClientProvider(
        clientInformation: MCPOAuthClientInformation(clientID: "client123"),
        tokens: MCPOAuthTokens(accessToken: "old-access", tokenType: "Bearer", refreshToken: "old-refresh")
    )
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {
          "resource": "https://resource.example.com/mcp",
          "authorization_servers": ["https://auth.example.com"]
        }
        """),
        oauthAuthorizationMetadataResponse(),
        jsonResponse("""
        {
          "access_token": "new-access",
          "token_type": "Bearer"
        }
        """)
    ])

    let result = try await MCPOAuth.auth(
        provider: provider,
        serverURL: "https://resource.example.com/mcp/rpc",
        transport: transport
    )

    #expect(result == .authorized)
    #expect(await provider.savedTokens()?.accessToken == "new-access")
    #expect(await provider.savedTokens()?.refreshToken == "old-refresh")
    #expect(await provider.redirectedURL() == nil)
    let request = try await #require(transport.requests().last)
    let form = try formItems(request)
    #expect(form["grant_type"] == "refresh_token")
    #expect(form["refresh_token"] == "old-refresh")
}

@Test func mcpOAuthAuthRejectsMismatchedProtectedResource() async throws {
    let provider = TestOAuthClientProvider(clientInformation: MCPOAuthClientInformation(clientID: "client123"))
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "resource": "https://other.example.com/mcp",
      "authorization_servers": ["https://auth.example.com"]
    }
    """))

    do {
        _ = try await MCPOAuth.auth(
            provider: provider,
            serverURL: "https://resource.example.com/mcp/rpc",
            transport: transport
        )
        Issue.record("Expected protected-resource mismatch to throw.")
    } catch let error as MCPClientError {
        #expect(error.message.contains("does not match expected https://resource.example.com/mcp/rpc"))
    }
}

@Test func mcpOAuthAuthInvalidGrantInvalidatesTokensAndRetries() async throws {
    let provider = TestOAuthClientProvider(
        clientInformation: MCPOAuthClientInformation(clientID: "client123"),
        codeVerifier: "verifier123",
        storedState: "state123"
    )
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {
          "resource": "https://resource.example.com/mcp",
          "authorization_servers": ["https://auth.example.com"]
        }
        """),
        oauthAuthorizationMetadataResponse(),
        AIHTTPResponse(statusCode: 400, headers: ["content-type": "application/json"], body: Data("""
        {
          "error": "invalid_grant",
          "error_description": "Bad code"
        }
        """.utf8)),
        jsonResponse("""
        {
          "resource": "https://resource.example.com/mcp",
          "authorization_servers": ["https://auth.example.com"]
        }
        """),
        oauthAuthorizationMetadataResponse(),
        jsonResponse("""
        {
          "access_token": "access-after-retry",
          "token_type": "Bearer"
        }
        """)
    ])

    let result = try await MCPOAuth.auth(
        provider: provider,
        serverURL: "https://resource.example.com/mcp/rpc",
        authorizationCode: "code123",
        callbackState: "state123",
        transport: transport
    )

    #expect(result == .authorized)
    #expect(await provider.invalidations() == [.tokens])
    #expect(await provider.savedTokens()?.accessToken == "access-after-retry")
    #expect(await transport.requests().count == 6)
}

@Test func mcpOAuthAuthUsesProviderCustomClientAuthentication() async throws {
    let provider = TestOAuthClientProvider(
        clientInformation: MCPOAuthClientInformation(clientID: "client123", clientSecret: "secret123"),
        codeVerifier: "verifier123",
        storedState: "state123",
        customAuthentication: { request in
            var customized = request
            customized.headers["X-Provider-Auth"] = request.metadata?.issuer
            customized.parameters.append(URLQueryItem(name: "client_assertion", value: "provider-token"))
            return customized
        }
    )
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {
          "resource": "https://resource.example.com/mcp",
          "authorization_servers": ["https://auth.example.com"]
        }
        """),
        oauthAuthorizationMetadataResponse(),
        jsonResponse("""
        {
          "access_token": "access-123",
          "token_type": "Bearer"
        }
        """)
    ])

    let result = try await MCPOAuth.auth(
        provider: provider,
        serverURL: "https://resource.example.com/mcp/rpc",
        authorizationCode: "code123",
        callbackState: "state123",
        transport: transport
    )

    #expect(result == .authorized)
    let request = try await #require(transport.requests().last)
    #expect(request.headers["Authorization"] == nil)
    #expect(request.headers["X-Provider-Auth"] == "https://auth.example.com")
    let form = try formItems(request)
    #expect(form["client_assertion"] == "provider-token")
    #expect(form["client_secret"] == nil)
}

private func oauthAuthorizationMetadataResponse() -> AIHTTPResponse {
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

private actor TestOAuthClientProvider: MCPOAuthClientProvider {
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

private func queryItems(_ url: URL) throws -> [String: String] {
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private func formItems(_ request: AIHTTPRequest) throws -> [String: String] {
    let body = String(data: try #require(request.body), encoding: .utf8) ?? ""
    return Dictionary(uniqueKeysWithValues: body.split(separator: "&").map { pair in
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        let name = parts[0].removingPercentEncoding ?? parts[0]
        let value = parts.count > 1 ? (parts[1].removingPercentEncoding ?? parts[1]) : ""
        return (name, value)
    })
}
