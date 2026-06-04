import Foundation

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

func authInternal(
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

