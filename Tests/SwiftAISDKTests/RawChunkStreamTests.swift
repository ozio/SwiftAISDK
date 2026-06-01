import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAICompatibleStreamsRawChunksOnlyWhenRequested() async throws {
    let response = sseResponse("""
    data: {"choices":[{"delta":{"content":"hel"}}]}

    data: {"choices":[{"delta":{"content":"lo"},"finish_reason":"stop"}]}

    data: [DONE]

    """)

    let defaultProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: RecordingTransport(response: response)))
    let defaultModel = try defaultProvider.chatModel("gpt-4.1-mini")
    let defaultParts = try await collectStreamParts(defaultModel.stream(LanguageModelRequest(messages: [.user("Hi")])))
    #expect(defaultParts.rawValues.isEmpty)
    #expect(defaultParts.textDeltas == ["hel", "lo"])

    let rawProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: RecordingTransport(response: response)))
    let rawModel = try rawProvider.chatModel("gpt-4.1-mini")
    let rawParts = try await collectStreamParts(rawModel.stream(LanguageModelRequest(messages: [.user("Hi")], includeRawChunks: true)))
    #expect(rawParts.rawValues.count == 2)
    #expect(rawParts.textDeltas == ["hel", "lo"])
}

@Test func googleGenerateContentStreamsRawChunksOnlyWhenRequested() async throws {
    let response = sseResponse("""
    data: {"candidates":[{"content":{"parts":[{"text":"goo"}],"role":"model"},"index":0}]}

    data: {"candidates":[{"content":{"parts":[{"text":"gle"}],"role":"model"},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":2,"candidatesTokenCount":2,"totalTokenCount":4}}

    """)

    let defaultProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: RecordingTransport(response: response)
    ))
    let defaultModel = try defaultProvider.languageModel("gemini-2.5-pro")
    let defaultParts = try await collectStreamParts(defaultModel.stream(LanguageModelRequest(messages: [.user("Hi")])))
    #expect(defaultParts.rawValues.isEmpty)
    #expect(defaultParts.textDeltas == ["goo", "gle"])

    let rawProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: RecordingTransport(response: response)
    ))
    let rawModel = try rawProvider.languageModel("gemini-2.5-pro")
    let rawParts = try await collectStreamParts(rawModel.stream(LanguageModelRequest(messages: [.user("Hi")], includeRawChunks: true)))
    #expect(rawParts.rawValues.count == 2)
    #expect(rawParts.textDeltas == ["goo", "gle"])
}

@Test func bedrockStreamsRawChunksOnlyWhenRequested() async throws {
    let response = amazonEventStreamResponse([
        ("contentBlockDelta", #"{"delta":{"text":"bed"}}"#),
        ("contentBlockDelta", #"{"delta":{"text":"rock"}}"#),
        ("messageStop", #"{"stopReason":"end_turn"}"#)
    ])

    let defaultProvider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: RecordingTransport(response: response)
    ))
    let defaultModel = try defaultProvider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")
    let defaultParts = try await collectStreamParts(defaultModel.stream(LanguageModelRequest(messages: [.user("Hi")])))
    #expect(defaultParts.rawValues.isEmpty)
    #expect(defaultParts.textDeltas == ["bed", "rock"])

    let rawProvider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: RecordingTransport(response: response)
    ))
    let rawModel = try rawProvider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")
    let rawParts = try await collectStreamParts(rawModel.stream(LanguageModelRequest(messages: [.user("Hi")], includeRawChunks: true)))
    #expect(rawParts.rawValues.count == 3)
    #expect(rawParts.textDeltas == ["bed", "rock"])
}

@Test func gatewayNestedRawEventsHonorIncludeRawChunks() async throws {
    let response = sseResponse("""
    data: {"type":"raw","rawValue":{"provider":"chunk"}}

    data: {"type":"text-delta","delta":"gate"}

    data: {"type":"finish","finishReason":"stop","usage":{"totalTokens":2}}

    """)

    let defaultProvider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: RecordingTransport(response: response)))
    let defaultModel = try defaultProvider.languageModel("openai/gpt-4.1-mini")
    let defaultParts = try await collectStreamParts(defaultModel.stream(LanguageModelRequest(messages: [.user("Hi")])))
    #expect(defaultParts.rawValues.isEmpty)
    #expect(defaultParts.textDeltas == ["gate"])

    let rawProvider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: RecordingTransport(response: response)))
    let rawModel = try rawProvider.languageModel("openai/gpt-4.1-mini")
    let rawParts = try await collectStreamParts(rawModel.stream(LanguageModelRequest(messages: [.user("Hi")], includeRawChunks: true)))
    #expect(rawParts.rawValues.count == 4)
    #expect(rawParts.textDeltas == ["gate"])
}

private struct CollectedStreamParts {
    var rawValues: [JSONValue] = []
    var textDeltas: [String] = []
}

private func collectStreamParts(_ stream: AsyncThrowingStream<LanguageStreamPart, Error>) async throws -> CollectedStreamParts {
    var result = CollectedStreamParts()
    for try await part in stream {
        switch part {
        case let .raw(value):
            result.rawValues.append(value)
        case let .textDelta(delta):
            result.textDeltas.append(delta)
        default:
            break
        }
    }
    return result
}
