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
