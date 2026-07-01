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
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        if case let .textDelta(delta) = part {
            textDeltas.append(delta)
        }
    }

    #expect(textDeltas == ["", "Hello"])
}
