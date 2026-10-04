import Foundation
import Testing
@testable import SwiftAISDK

@Test func Weekly20261004ToolSearchCustomRankingCannotDiscoverUnknownOrDuplicateTools() async throws {
    var weather = AITool(name: "weather", description: "Weather", parameters: ["type": "object"], execute: { _ in .null })
    weather.deferLoading = true
    var calendar = AITool(name: "calendar", parameters: ["type": "object"], execute: { _ in .null })
    calendar.deferLoading = true
    let search = try toolSearch(maxResults: 1) { query, tools in
        #expect(query == "query")
        #expect(tools.map(\.name) == ["weather", "calendar"])
        return ["unknown", "calendar", "calendar", "weather"]
    }
    let discovery = AIToolDiscoveryState()
    let before = try await discovery.prepare(tools: [search, weather, calendar], routing: [:])
    #expect(before.modelTools.map(\.name) == ["toolSearch"])
    let execute = try #require(before.executionTools.first?.execute)
    #expect(try await execute(["query": "query"]) == ["tools": [["name": "calendar"]]])
    let after = try await discovery.prepare(tools: [search, weather, calendar], routing: [:])
    #expect(after.modelTools.map(\.name) == ["toolSearch", "calendar"])
    #expect(throws: AIError.self) { try toolSearch(maxResults: 0) }
}

@Test func Weekly20261004UnaryAudioUsageReachesResultsAndTelemetry() async throws {
    let recorder = TelemetryRecorder()
    let transport = RecordingTransport(response: jsonResponse("{\"text\":\"Hello\",\"usage\":{\"type\":\"tokens\",\"total_tokens\":5,\"input_tokens\":3,\"output_tokens\":2}}"))
    let model = try AIProviders.openAI(settings: .init(apiKey: "key", transport: transport)).transcriptionModel("gpt-4o-transcribe")
    let result = try await AI.transcribe(model: model, request: .init(audio: Data([1, 2]), mimeType: "audio/wav"), retryPolicy: .none, telemetry: .init(integrations: [recorder]))
    #expect(result.usage?["total_tokens"] == 5)
    let events = await recorder.events()
    #expect(events.map(\.kind) == [.start, .end])
    #expect(events.last?.providerUsage == result.usage)
    #expect(events.last?.output?["usage"]?["type"] == "tokens")
    #expect(events.first?.input?["audio"] == nil)
}

private struct WeeklyConsumedAudioModel: StreamingTranscriptionModel {
    let providerID = "test.transcription"
    let modelID = "test"
    func stream(_ request: StreamingTranscriptionRequest) async throws -> StreamingTranscriptionResult {
        let pair = AsyncThrowingStream<StreamingTranscriptionPart, Error>.makeStream()
        let task = Task {
            do {
                var iterator = request.audio.makeAsyncIterator()
                _ = try await iterator.next() // Deliberately consumes only the first chunk.
                pair.continuation.yield(.finish(.init(text: "Hello", usage: ["seconds": 1])))
                pair.continuation.finish()
            } catch { pair.continuation.finish(throwing: error) }
        }
        return StreamingTranscriptionResult(stream: pair.stream, cancel: { task.cancel() })
    }
}

@Test func Weekly20261004StreamingAudioTelemetryCountsConsumedBytesWithoutDrainingInput() async throws {
    let recorder = TelemetryRecorder()
    let result = try await AI.streamTranscribe(model: WeeklyConsumedAudioModel(), request: .init(audio: .chunks([Data([1, 2, 3]), Data(repeating: 4, count: 100)]), inputAudioFormat: .init(mediaType: "audio/pcm", sampleRate: 24_000)), telemetry: .init(integrations: [recorder]))
    _ = try await realtimeCollect(result.stream)
    let events = await recorder.events()
    #expect(events.map(\.kind) == [.start, .end])
    #expect(events.last?.output?["byteLength"] == 3)
    #expect(events.last?.providerUsage == ["seconds": 1])
    #expect(events.first?.input?["byteLength"] == nil)
}

private actor WeeklyOAuthStore: MCPOAuthClientProvider {
    nonisolated let redirectURL = URL(string: "http://localhost:3000/callback")!
    nonisolated let clientMetadata = MCPOAuthClientMetadata(redirectURIs: [URL(string: "http://localhost:3000/callback")!])
    var current: MCPOAuthTokens
    let client: MCPOAuthClientInformation
    var information: MCPOAuthAuthorizationServerInformation?
    var snapshots: [MCPOAuthTokens] = []
    init() throws { current = try oauthTokens(accessToken: "old", refreshToken: "old-refresh"); client = try oauthClientInformation() }
    func tokens() -> MCPOAuthTokens? { current }
    func saveTokens(_ tokens: MCPOAuthTokens) { current = tokens }
    func clientInformation() -> MCPOAuthClientInformation? { client }
    func authorizationServerInformation() -> MCPOAuthAuthorizationServerInformation? { information }
    func saveAuthorizationServerInformation(_ information: MCPOAuthAuthorizationServerInformation) { self.information = information }
    func codeVerifier() -> String { "verifier" }
    func saveCodeVerifier(_ codeVerifier: String) {}
    func redirectToAuthorization(_ url: URL) {}
    func invalidateCredentials(_ scope: MCPOAuthCredentialScope, context: MCPOAuthCredentialInvalidationContext?) {
        if let context { snapshots.append(context.tokens) }
        // A concurrent refresh has already installed a different generation.
        #expect(context?.tokens.accessToken != current.accessToken)
    }
    func capturedSnapshots() -> [MCPOAuthTokens] { snapshots }
}

private actor WeeklyConcurrentRefreshTransport: AITransport {
    let store: WeeklyOAuthStore
    var refreshes: [String] = []
    init(store: WeeklyOAuthStore) { self.store = store }
    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        if request.url.path == "/token" {
            refreshes.append(String(decoding: request.body ?? Data(), as: UTF8.self))
            if refreshes.count == 1 {
                await store.saveTokens(try oauthTokens(accessToken: "concurrent", refreshToken: "concurrent-refresh"))
                return AIHTTPResponse(statusCode: 400, headers: ["content-type": "application/json"], body: Data("{\"error\":\"invalid_grant\"}".utf8))
            }
            return jsonResponse("{\"access_token\":\"final\",\"token_type\":\"Bearer\"}")
        }
        if request.url.path.contains("oauth-protected-resource") {
            return jsonResponse("{\"resource\":\"https://resource.example.com/mcp\",\"authorization_servers\":[\"https://auth.example.com\"]}")
        }
        return oauthAuthorizationMetadataResponse()
    }
    func refreshRequests() -> [String] { refreshes }
}

@Test func Weekly20261004MCPInvalidGrantIdentifiesTheFailedTokenGeneration() async throws {
    let store = try WeeklyOAuthStore()
    let transport = WeeklyConcurrentRefreshTransport(store: store)
    let result = try await MCPOAuth.auth(provider: store, serverURL: "https://resource.example.com/mcp/rpc", transport: transport)
    #expect(result == .authorized)
    #expect(await store.capturedSnapshots().map(\.accessToken) == ["old"])
    let requests = await transport.refreshRequests()
    #expect(requests.count == 2)
    #expect(requests[0].contains("refresh_token=old-refresh"))
    #expect(requests[1].contains("refresh_token=concurrent-refresh"))
}

@Test func Weekly20261004MCPAuthorizationServerMismatchIsTypedAndDoesNotInvalidate() async throws {
    var client = try oauthClientInformation()
    client.tokenEndpoint = try requireURL("https://auth.example.com/old-token")
    var tokens = try oauthTokens(accessToken: "old", refreshToken: "refresh")
    tokens.tokenEndpoint = client.tokenEndpoint
    let provider = TestOAuthClientProvider(clientInformation: client, tokens: tokens)
    let transport = RecordingTransport(responses: [jsonResponse("{\"resource\":\"https://resource.example.com/mcp\",\"authorization_servers\":[\"https://auth.example.com\"]}"), oauthAuthorizationMetadataResponse()])
    do {
        _ = try await MCPOAuth.auth(provider: provider, serverURL: "https://resource.example.com/mcp/rpc", transport: transport)
        Issue.record("Expected mismatch")
    } catch let error as MCPOAuthAuthorizationServerMismatchError {
        #expect(error.code == "authorization_server_mismatch")
    }
    #expect(await provider.invalidations().isEmpty)
    #expect(await transport.requests().count == 2)
}
