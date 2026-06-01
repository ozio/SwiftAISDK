import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicLanguageCarriesResponseMetadataForGenerateAndStream() async throws {
    let raw = #"""
    {"id":"msg-1","model":"claude-3-5-haiku-latest","content":[{"type":"text","text":"bonjour"}],"stop_reason":"end_turn","usage":{"input_tokens":4,"output_tokens":2}}
    """#
    let generateTransport = RecordingTransport(response: jsonResponse(raw, headers: ["anthropic-header": "generate"]))
    let generateProvider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: generateTransport))
    let generateModel = try generateProvider.languageModel("claude-3-5-haiku-latest")

    let result = try await generateModel.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.responseMetadata.id == "msg-1")
    #expect(result.responseMetadata.modelID == "claude-3-5-haiku-latest")
    #expect(result.responseMetadata.headers["anthropic-header"] == "generate")
    #expect(result.responseMetadata.body?["id"]?.stringValue == "msg-1")

    let streamTransport = RecordingTransport(response: sseResponse("""
    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hel"}}

    event: message_stop
    data: {"type":"message_stop"}

    """, headers: ["anthropic-header": "stream"]))
    let streamProvider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: streamTransport))
    let streamModel = try streamProvider.languageModel("claude-3-5-haiku-latest")

    var streamMetadata: AIResponseMetadata?
    for try await part in streamModel.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        if case let .responseMetadata(metadata) = part {
            streamMetadata = metadata
        }
    }

    #expect(streamMetadata?.modelID == "claude-3-5-haiku-latest")
    #expect(streamMetadata?.headers["anthropic-header"] == "stream")
}

@Test func googleGenerativeAICarriesResponseMetadataForLanguageAndEmbedding() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"gemini"}]},"finishReason":"STOP"}],"usageMetadata":{"totalTokenCount":3}}
    """, headers: ["google-header": "generate"]))
    let generateProvider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: generateTransport))
    let generateModel = try generateProvider.languageModel("gemini-2.5-flash")

    let result = try await generateModel.generate(LanguageModelRequest(messages: [.user("Ping")]))

    #expect(result.responseMetadata.modelID == "gemini-2.5-flash")
    #expect(result.responseMetadata.headers["google-header"] == "generate")
    #expect(result.responseMetadata.body?["candidates"]?[0]?["content"]?["parts"]?[0]?["text"]?.stringValue == "gemini")

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"candidates":[{"content":{"parts":[{"text":"gem"}],"role":"model"},"index":0}]}

    """, headers: ["google-header": "stream"]))
    let streamProvider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: streamTransport))
    let streamModel = try streamProvider.languageModel("gemini-2.5-flash")

    var streamMetadata: AIResponseMetadata?
    for try await part in streamModel.stream(LanguageModelRequest(messages: [.user("Ping")])) {
        if case let .responseMetadata(metadata) = part {
            streamMetadata = metadata
        }
    }

    #expect(streamMetadata?.modelID == "gemini-2.5-flash")
    #expect(streamMetadata?.headers["google-header"] == "stream")

    let embeddingTransport = RecordingTransport(response: jsonResponse(#"{"embedding":{"values":[0.1,0.2]}}"#, headers: ["google-header": "embedding"]))
    let embeddingProvider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: embeddingTransport))
    let embeddingModel = try embeddingProvider.embeddingModel("text-embedding-004")

    let embedding = try await embeddingModel.embed(EmbeddingRequest(values: ["hello"]))

    #expect(embedding.responseMetadata.modelID == "text-embedding-004")
    #expect(embedding.responseMetadata.headers["google-header"] == "embedding")
    #expect(embedding.responseMetadata.body?["embedding"]?["values"]?[0]?.doubleValue == 0.1)
}

@Test func googleVertexCarriesResponseMetadataForLanguageAndEmbedding() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"vertex"}]},"finishReason":"STOP"}],"usageMetadata":{"totalTokenCount":3}}
    """, headers: ["vertex-header": "generate"]))
    let generateProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: generateTransport
    ))
    let generateModel = try generateProvider.languageModel("gemini-2.5-pro")

    let result = try await generateModel.generate(LanguageModelRequest(messages: [.user("Ping")]))

    #expect(result.responseMetadata.modelID == "gemini-2.5-pro")
    #expect(result.responseMetadata.headers["vertex-header"] == "generate")
    #expect(result.responseMetadata.body?["candidates"]?[0]?["content"]?["parts"]?[0]?["text"]?.stringValue == "vertex")

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"candidates":[{"content":{"parts":[{"text":"ver"}],"role":"model"},"index":0}]}

    """, headers: ["vertex-header": "stream"]))
    let streamProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: streamTransport
    ))
    let streamModel = try streamProvider.languageModel("gemini-2.5-pro")

    var streamMetadata: AIResponseMetadata?
    for try await part in streamModel.stream(LanguageModelRequest(messages: [.user("Ping")])) {
        if case let .responseMetadata(metadata) = part {
            streamMetadata = metadata
        }
    }

    #expect(streamMetadata?.modelID == "gemini-2.5-pro")
    #expect(streamMetadata?.headers["vertex-header"] == "stream")

    let embeddingTransport = RecordingTransport(response: jsonResponse(#"{"predictions":[{"embeddings":{"values":[0.3,0.4]}}]}"#, headers: ["vertex-header": "embedding"]))
    let embeddingProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: embeddingTransport
    ))
    let embeddingModel = try embeddingProvider.embeddingModel("text-embedding-004")

    let embedding = try await embeddingModel.embed(EmbeddingRequest(values: ["hello"]))

    #expect(embedding.responseMetadata.modelID == "text-embedding-004")
    #expect(embedding.responseMetadata.headers["vertex-header"] == "embedding")
    #expect(embedding.responseMetadata.body?["predictions"]?[0]?["embeddings"]?["values"]?[0]?.doubleValue == 0.3)
}
