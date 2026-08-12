import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAICompatibleChatStreamsTextAfterAzureContentFilterChunksLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"choices":[],"created":0,"id":"","model":"","object":"","prompt_filter_results":[{"prompt_index":0,"content_filter_results":{}}]}

    data: {"id":"chatcmpl-test","object":"chat.completion.chunk","created":1,"model":"gpt-4o","choices":[{"index":0,"delta":{"content":"","role":"assistant"},"finish_reason":null}]}

    data: {"id":"chatcmpl-test","object":"chat.completion.chunk","created":1,"model":"gpt-4o","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

    data: {"id":"chatcmpl-test","object":"chat.completion.chunk","created":1,"model":"gpt-4o","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

    data: {"choices":[{"content_filter_offsets":{},"content_filter_results":{},"finish_reason":null,"index":0}],"created":0,"id":"","model":"","object":""}

    data: [DONE]

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.chatModel("gpt-4o")

    var textDeltas: [String] = []
    var responseMetadata: [AIResponseMetadata] = []
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        if case let .textDeltaPart(_, delta, _) = part {
            textDeltas.append(delta)
        }
        if case let .responseMetadata(metadata) = part {
            responseMetadata.append(metadata)
        }
    }

    #expect(textDeltas == ["", "Hello"])
    #expect(responseMetadata.count == 1)
    #expect(responseMetadata.first?.id == "chatcmpl-test")
    #expect(responseMetadata.first?.modelID == "gpt-4o")
    #expect(responseMetadata.first?.timestamp == Date(timeIntervalSince1970: 1))
}

@Test func openAIChatGenerateSuppressesAzurePlaceholderTimestampLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"chatcmpl-filtered","object":"chat.completion","created":0,"model":"gpt-4o","choices":[{"index":0,"message":{"role":"assistant","content":"Hello"},"finish_reason":"stop"}]}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let result = try await provider.chatModel("gpt-4o").generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.responseMetadata.id == "chatcmpl-filtered")
    #expect(result.responseMetadata.timestamp == nil)
}
