import Foundation
import Testing
@testable import SwiftAISDK

@Test func basetenChatUsesBearerAuthAndModelAPIBase() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"baseten"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """))
    let provider = try AIProviders.baseten(settings: ProviderSettings(apiKey: "baseten-key", transport: transport))
    let model = try provider.languageModel("deepseek-ai/DeepSeek-V3-0324")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "baseten")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://inference.baseten.co/v1/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer baseten-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "deepseek-ai/DeepSeek-V3-0324")
}

@Test func basetenChatUsesModelURLAndDefaultPlaceholderModel() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"custom"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """))
    let provider = try AIProviders.baseten(settings: ProviderSettings(
        apiKey: "baseten-key",
        modelURL: "https://model-123.api.baseten.co/environments/production/sync/v1",
        transport: transport
    ))
    let model = try provider.chatModel()

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(model.modelID == "placeholder")
    #expect(result.text == "custom")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://model-123.api.baseten.co/environments/production/sync/v1/chat/completions")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "placeholder")
}

@Test func basetenChatFallsBackToModelAPIForPlainSyncModelURLLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"fallback"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """))
    let provider = try AIProviders.baseten(settings: ProviderSettings(
        apiKey: "baseten-key",
        modelURL: "https://model-123.api.baseten.co/environments/production/sync",
        transport: transport
    ))
    let model = try provider.chatModel()

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(model.modelID == "chat")
    #expect(result.text == "fallback")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://inference.baseten.co/v1/chat/completions")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "chat")
}

@Test func basetenChatRejectsPredictModelURL() throws {
    let predictProvider = try AIProviders.baseten(settings: ProviderSettings(
        apiKey: "baseten-key",
        modelURL: "https://model-123.api.baseten.co/environments/production/predict",
        transport: RecordingTransport(response: jsonResponse("{}"))
    ))

    #expect(throws: AIError.invalidArgument(argument: "modelURL", message: "Not supported. You must use a /sync/v1 endpoint for chat models.")) {
        _ = try predictProvider.chatModel()
    }
    #expect(throws: AIError.invalidArgument(argument: "modelURL", message: "Not supported. You must use a /sync/v1 endpoint for chat models.")) {
        _ = try predictProvider.languageModel("chat")
    }
}

@Test func basetenEmbeddingRequiresSyncModelURL() throws {
    let provider = try AIProviders.baseten(settings: ProviderSettings(apiKey: "baseten-key", transport: RecordingTransport(response: jsonResponse("{}"))))

    #expect(throws: AIError.invalidArgument(argument: "modelURL", message: "No model URL provided for embeddings. Please set modelURL option for embeddings.")) {
        _ = try provider.embeddingModel("embeddings")
    }
}

@Test func basetenEmbeddingUsesSyncModelURL() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"embedding":[0.1,0.2]}],"usage":{"total_tokens":3}}"#))
    let provider = try AIProviders.baseten(settings: ProviderSettings(
        apiKey: "baseten-key",
        modelURL: "https://model-123.api.baseten.co/environments/production/sync",
        transport: transport
    ))
    let model = try provider.embeddingModel()

    let result = try await model.embed(EmbeddingRequest(
        values: ["hello"],
        dimensions: 128,
        extraBody: [
            "encoding_format": .string("float"),
            "baseten": .object(["input_type": .string("query")])
        ]
    ))

    #expect(result.embeddings == [[0.1, 0.2]])
    #expect(result.usage?.totalTokens == 3)
    #expect(model.modelID == "embeddings")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://model-123.api.baseten.co/environments/production/sync/v1/embeddings")
    #expect(request.headers["Authorization"] == "Bearer baseten-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "embeddings")
    #expect(body["input"]?[0]?.stringValue == "hello")
    #expect(body["dimensions"]?.intValue == 128)
    #expect(body["encoding_format"]?.stringValue == "float")
    #expect(body["input_type"] == nil)
    #expect(body["baseten"] == nil)
}

@Test func basetenEmbeddingSupportsSyncV1ModelURLAndRejectsPredict() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"embedding":[0.3,0.4]}]}"#))
    let provider = try AIProviders.baseten(settings: ProviderSettings(
        apiKey: "baseten-key",
        modelURL: "https://model-123.api.baseten.co/environments/production/sync/v1",
        transport: transport
    ))

    _ = try await provider.embeddingModel("embed").embed(EmbeddingRequest(values: ["hello"]))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://model-123.api.baseten.co/environments/production/sync/v1/embeddings")

    let predictProvider = try AIProviders.baseten(settings: ProviderSettings(
        apiKey: "baseten-key",
        modelURL: "https://model-123.api.baseten.co/environments/production/predict",
        transport: RecordingTransport(response: jsonResponse("{}"))
    ))

    #expect(throws: AIError.invalidArgument(argument: "modelURL", message: "Not supported. You must use a /sync or /sync/v1 endpoint for embeddings.")) {
        _ = try predictProvider.embeddingModel()
    }
}
