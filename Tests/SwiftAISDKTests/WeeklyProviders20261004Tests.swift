import Foundation
import Testing
@testable import SwiftAISDK

@Test func Weekly20261004AnthropicSonnet55UsesBetweenToolsThinkingAndRestrictsSampling() async throws {
    let transport = RecordingTransport(response: jsonResponse("{\"content\":[],\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":1,\"output_tokens\":0}}"))
    let model = try AIProviders.anthropic(settings: .init(apiKey: "key", transport: transport)).languageModel("claude-sonnet-5-5")
    let result = try await model.generate(.init(messages: [.user("test")], temperature: 0.2, providerOptions: ["anthropic": ["thinking": ["type": "disabled"]]]))
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["thinking"]?["type"] == "between_tools")
    #expect(body["temperature"] == nil)
    #expect(result.warnings.contains { $0.feature == "temperature" })
}

@Test func Weekly20261004AnthropicFallbackMarkerSurvivesGenerateReplayAndStreaming() async throws {
    let marker: JSONValue = ["type": "fallback", "from": ["model": "claude-sonnet-5-5"], "to": ["model": "claude-haiku-4-5"]]
    let transport = RecordingTransport(response: jsonResponse("{\"content\":[{\"type\":\"fallback\",\"from\":{\"model\":\"claude-sonnet-5-5\"},\"to\":{\"model\":\"claude-haiku-4-5\"}},{\"type\":\"text\",\"text\":\"done\"}],\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}"))
    let model = try AIProviders.anthropic(settings: .init(apiKey: "key", transport: transport)).languageModel("claude-sonnet-5-5")
    let result = try await model.generate(.init(messages: [.user("test")]))
    guard case let .custom(value, metadata) = try #require(result.content.first) else { Issue.record("Missing fallback marker"); return }
    #expect(value["kind"] == "anthropic.fallback")
    #expect(metadata["anthropic"] == marker)
    _ = try await model.generate(.init(messages: [.user("first"), .init(role: .assistant, content: [.custom(value, providerMetadata: metadata)]), .user("continue")]))
    let body = try decodeJSONBody(try #require(await transport.requests().last?.body))
    #expect(body["messages"]?[1]?["content"]?[0] == marker)
    var streaming = AnthropicStreamingContentBlocks(providerID: "custom-anthropic.messages")
    let parts = streaming.apply(event: ["type": "content_block_start", "index": 0, "content_block": marker])
    guard case let .custom(_, streamMetadata) = try #require(parts.first) else { Issue.record("Missing streamed fallback"); return }
    #expect(streamMetadata["anthropic"] == marker)
}

@Test(arguments: [
    #"{"type":"fallback"}"#,
    #"{"type":"fallback","from":{"model":1},"to":{"model":"target"}}"#,
    #"{"type":"fallback","from":{"model":"source"},"to":null}"#
]) func Weekly20261004AnthropicRejectsMalformedFallbackInGenerateAndStream(block: String) async throws {
    let transport = RecordingTransport(response: jsonResponse("{\"content\":[\(block),{\"type\":\"text\",\"text\":\"answer\"}],\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}"))
    let model = try AIProviders.anthropic(settings: .init(apiKey: "key", transport: transport)).languageModel("claude-sonnet-5-5")
    await #expect(throws: AIError.self) { try await model.generate(.init(messages: [.user("test")])) }
    let streamingTransport = RecordingTransport(response: sseResponse("event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":\(block)}\n\n"))
    let streamingModel = try AIProviders.anthropic(settings: .init(apiKey: "key", transport: streamingTransport)).languageModel("claude-sonnet-5-5")
    await #expect(throws: AIError.self) {
        for try await _ in streamingModel.stream(.init(messages: [.user("test")])) {}
    }
}

@Test func Weekly20261004AnthropicFallbackStripsUnknownMetadataFields() {
    #expect(anthropicFallbackMetadata(["type": "fallback", "from": ["model": "source", "extra": true], "to": ["model": "target"], "extra": 1]) == ["type": "fallback", "from": ["model": "source"], "to": ["model": "target"]])
}

@Test func Weekly20261004BedrockNovaHighThinkingDropsMaxTokensAndPassesRequestMetadata() async throws {
    let transport = RecordingTransport(response: jsonResponse("{\"output\":{\"message\":{\"content\":[{\"text\":\"ok\"}]}},\"stopReason\":\"end_turn\",\"usage\":{\"inputTokens\":1,\"outputTokens\":1}}"))
    let model = try AIProviders.amazonBedrock(settings: .init(region: "us-east-1", apiKey: "key", transport: transport)).languageModel("amazon.nova-2-lite-v1:0")
    let result = try await model.generate(.init(messages: [.user("test")], maxOutputTokens: 20, providerOptions: ["bedrock": ["reasoningConfig": ["type": "enabled", "maxReasoningEffort": "high"], "requestMetadata": ["project": "weekly"]]]))
    let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
    #expect(body["inferenceConfig"]?["maxTokens"] == nil)
    #expect(body["requestMetadata"] == ["project": "weekly"])
    #expect(result.warnings.contains { $0.feature == "maxOutputTokens" })
    await #expect(throws: AIError.self) { try await model.generate(.init(messages: [.user("test")], providerOptions: ["bedrock": ["requestMetadata": ["invalid": 1]]])) }
    #expect(await transport.requests().count == 1)
}

@Test func Weekly20261004DeepSeekCacheFallbackAndMistralErrorFinishMatchUpstream() {
    let usage = deepSeekUsage(from: ["usage": ["prompt_tokens": 10, "completion_tokens": 2, "prompt_tokens_details": ["cached_tokens": 6]]])
    #expect(usage?.inputTokensCacheRead == 6)
    #expect(mapMistralFinishReason("error") == "error")
}

@Test func Weekly20261004GatewayCreditsRoutesTeamInQuery() async throws {
    for (team, key) in [("team_123", "teamId"), ("example-team", "slug")] {
        let transport = RecordingTransport(response: jsonResponse("{\"balance\":\"1\",\"total_used\":\"0\"}"))
        let provider = try AIProviders.gateway(settings: .init(apiKey: "key", transport: transport), teamIDOrSlug: team)
        _ = try await provider.getCredits()
        let request = try #require(await transport.requests().first)
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.contains(.init(name: key, value: team)) == true)
    }
}

@Test func Weekly20261004CompatibleRichToolOutputsAreExplicitlyOptIn() async throws {
    let output: JSONValue = ["type": "content", "value": [["type": "text", "text": "caption"], ["type": "file", "data": ["type": "url", "url": "https://images.example/a.png"], "mediaType": "image/png"]]]
    for enabled in [false, true] {
        let transport = RecordingTransport(response: jsonResponse("{\"choices\":[{\"message\":{\"content\":\"done\"},\"finish_reason\":\"stop\"}]}"))
        let provider = try AIProviders.openAICompatible(name: "custom", baseURL: "https://compatible.example/v1", apiKey: "key", transport: transport, supportsMultiPartToolContent: enabled)
        _ = try await provider.chatModel("model").generate(.init(messages: [.toolResponses(toolResults: [.init(toolCallID: "call", toolName: "lookup", result: output)])]))
        let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
        let content = body["messages"]?[0]?["content"]
        if enabled {
            #expect(content?[0] == ["type": "text", "text": "caption"])
            #expect(content?[1] == ["type": "image_url", "image_url": ["url": "https://images.example/a.png"]])
        } else { #expect(content?.stringValue != nil) }
    }
}

@Test func Weekly20261004PerplexityIntegrationHeaderHasDefaultAndPreservesOverride() async throws {
    for integration in [nil, "custom"] as [String?] {
        let transport = RecordingTransport(response: jsonResponse("{\"id\":\"response\",\"created_at\":1710000000,\"model\":\"sonar\",\"object\":\"response\",\"status\":\"completed\",\"output\":[]}"))
        let model = try AIProviders.perplexity(settings: .init(apiKey: "key", headers: integration.map { ["x-pplx-integration": $0] } ?? [:], transport: transport)).languageModel("sonar")
        _ = try await model.generate(.init(messages: [.user("test")]))
        let request = try #require(await transport.requests().first)
        #expect(request.headers.first { $0.key.lowercased() == "x-pplx-integration" }?.value == (integration ?? "vercel-ai-sdk"))
    }
}

@Test func Weekly20261004MistralJSONFallbackIncludesTheRequestedSchema() {
    let schema: JSONValue = ["type": "object", "properties": ["value": ["type": "string"]]]
    let messages = mistralMessages([.system("Be concise"), .user("test")], responseFormat: ["type": "json", "schema": schema], structuredOutputs: false)
    #expect(messages.first?.combinedText.contains("JSON schema:\n") == true)
    #expect(messages.first?.combinedText.contains("\"value\"") == true)
    #expect(messages.first?.combinedText.contains("matches the JSON schema above") == true)
}

@Test func Weekly20261004AnthropicHistoricalCallerIsRemovedWhileActiveCallerIsPreserved() async throws {
    let transport = RecordingTransport(response: jsonResponse("{\"content\":[],\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":1,\"output_tokens\":0}}"))
    let model = try AIProviders.anthropic(settings: .init(apiKey: "key", transport: transport)).languageModel("claude-sonnet-5-5")
    let call = AIToolCall(id: "call", name: "lookup", arguments: "{}", providerMetadata: ["anthropic": ["caller": ["type": "code_execution_20260120", "toolId": "missing"]]])
    let historical = try await model.generate(.init(messages: [.user("first"), .init(role: .assistant, content: [.toolCall(call)]), .user("next")]))
    let historicalBody = try decodeJSONBody(try #require(await transport.requests().last?.body))
    #expect(historicalBody["messages"]?[1]?["content"]?[0]?["caller"] == nil)
    #expect(!historical.warnings.isEmpty)
    _ = try await model.generate(.init(messages: [.user("first"), .init(role: .assistant, content: [.toolCall(call)])]))
    let activeBody = try decodeJSONBody(try #require(await transport.requests().last?.body))
    #expect(activeBody["messages"]?[1]?["content"]?[0]?["caller"]?["tool_id"] == "missing")
}
