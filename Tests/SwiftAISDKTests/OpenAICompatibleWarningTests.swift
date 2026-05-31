import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAICompatibleChatWarnsForDeprecatedProviderOptionsKeys() async throws {
    let compatibilityTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"hello"},"finish_reason":"stop"}]}
    """))
    let compatibilityProvider = try openAICompatibleWarningProvider(transport: compatibilityTransport)

    let compatibilityResult = try await compatibilityProvider.chatModel("chat-model").generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: ["openai-compatible": .object(["user": .string("deprecated-user")])]
    ))

    #expect(compatibilityResult.warnings == [
        AIWarning(type: "deprecated", setting: "providerOptions key 'openai-compatible'", message: "Use 'openaiCompatible' instead.")
    ])
    let compatibilityBody = try await firstRecordedBody(compatibilityTransport)
    #expect(compatibilityBody["user"]?.stringValue == "deprecated-user")
    #expect(compatibilityBody["openai-compatible"] == nil)

    let rawTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"hello"},"finish_reason":"stop"}]}
    """))
    let rawProvider = try openAICompatibleWarningProvider(transport: rawTransport)

    let rawResult = try await rawProvider.chatModel("chat-model").generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: ["test-provider": .object(["reasoningEffort": .string("high")])]
    ))

    #expect(rawResult.warnings == [
        AIWarning(type: "deprecated", setting: "providerOptions key 'test-provider'", message: "Use 'testProvider' instead.")
    ])
    let rawBody = try await firstRecordedBody(rawTransport)
    #expect(rawBody["reasoning_effort"]?.stringValue == "high")
    #expect(rawBody["test-provider"] == nil)

    let camelTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"hello"},"finish_reason":"stop"}]}
    """))
    let camelProvider = try openAICompatibleWarningProvider(transport: camelTransport)

    let camelResult = try await camelProvider.chatModel("chat-model").generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: ["testProvider": .object(["reasoningEffort": .string("low")])]
    ))

    #expect(camelResult.warnings.isEmpty)
    let camelBody = try await firstRecordedBody(camelTransport)
    #expect(camelBody["reasoning_effort"]?.stringValue == "low")
    #expect(camelBody["testProvider"] == nil)
}

@Test func openAICompatibleCompletionWarnsForDeprecatedProviderOptionsKeys() async throws {
    let rawTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"text":"done","finish_reason":"stop"}]}
    """))
    let rawProvider = try openAICompatibleWarningProvider(transport: rawTransport)

    let rawResult = try await rawProvider.completionModel("completion-model").generate(LanguageModelRequest(
        messages: [.user("Finish")],
        extraBody: ["test-provider": .object(["suffix": .string("raw")])]
    ))

    #expect(rawResult.warnings == [
        AIWarning(type: "deprecated", setting: "providerOptions key 'test-provider'", message: "Use 'testProvider' instead.")
    ])
    let rawBody = try await firstRecordedBody(rawTransport)
    #expect(rawBody["suffix"]?.stringValue == "raw")
    #expect(rawBody["test-provider"] == nil)

    let camelTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"text":"done","finish_reason":"stop"}]}
    """))
    let camelProvider = try openAICompatibleWarningProvider(transport: camelTransport)

    let camelResult = try await camelProvider.completionModel("completion-model").generate(LanguageModelRequest(
        messages: [.user("Finish")],
        extraBody: ["testProvider": .object(["suffix": .string("camel")])]
    ))

    #expect(camelResult.warnings.isEmpty)
    let camelBody = try await firstRecordedBody(camelTransport)
    #expect(camelBody["suffix"]?.stringValue == "camel")
    #expect(camelBody["testProvider"] == nil)
}

@Test func openAICompatibleEmbeddingWarnsForDeprecatedProviderOptionsKeys() async throws {
    let compatibilityTransport = RecordingTransport(response: jsonResponse("""
    {"data":[{"embedding":[0.1,0.2]}]}
    """))
    let compatibilityProvider = try openAICompatibleWarningProvider(transport: compatibilityTransport)

    let compatibilityResult = try await compatibilityProvider.embeddingModel("embedding-model").embed(EmbeddingRequest(
        values: ["hello"],
        extraBody: ["openai-compatible": .object(["dimensions": .number(64)])]
    ))

    #expect(compatibilityResult.warnings == [
        AIWarning(type: "deprecated", setting: "providerOptions key 'openai-compatible'", message: "Use 'openaiCompatible' instead.")
    ])
    let compatibilityBody = try await firstRecordedBody(compatibilityTransport)
    #expect(compatibilityBody["dimensions"]?.intValue == 64)
    #expect(compatibilityBody["openai-compatible"] == nil)

    let rawTransport = RecordingTransport(response: jsonResponse("""
    {"data":[{"embedding":[0.1,0.2]}]}
    """))
    let rawProvider = try openAICompatibleWarningProvider(transport: rawTransport)

    let rawResult = try await rawProvider.embeddingModel("embedding-model").embed(EmbeddingRequest(
        values: ["hello"],
        extraBody: ["test-provider": .object(["dimensions": .number(32)])]
    ))

    #expect(rawResult.warnings == [
        AIWarning(type: "deprecated", setting: "providerOptions key 'test-provider'", message: "Use 'testProvider' instead.")
    ])
    let rawBody = try await firstRecordedBody(rawTransport)
    #expect(rawBody["dimensions"]?.intValue == 32)
    #expect(rawBody["test-provider"] == nil)

    let camelTransport = RecordingTransport(response: jsonResponse("""
    {"data":[{"embedding":[0.1,0.2]}]}
    """))
    let camelProvider = try openAICompatibleWarningProvider(transport: camelTransport)

    let camelResult = try await camelProvider.embeddingModel("embedding-model").embed(EmbeddingRequest(
        values: ["hello"],
        extraBody: ["testProvider": .object(["dimensions": .number(16)])]
    ))

    #expect(camelResult.warnings.isEmpty)
    let camelBody = try await firstRecordedBody(camelTransport)
    #expect(camelBody["dimensions"]?.intValue == 16)
    #expect(camelBody["testProvider"] == nil)
}

@Test func openAICompatibleImageReturnsWarningsForUnsupportedSettings() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"image-data"}]}"#))
    let provider = try openAICompatibleWarningProvider(transport: transport)

    let result = try await provider.imageModel("image-model").generateImage(ImageGenerationRequest(
        prompt: "cat",
        aspectRatio: "16:9",
        seed: 123
    ))

    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "aspectRatio", message: "This model does not support aspect ratio. Use `size` instead."),
        AIWarning(type: "unsupported", feature: "seed")
    ])
    let body = try await firstRecordedBody(transport)
    #expect(body["aspectRatio"] == nil)
    #expect(body["aspect_ratio"] == nil)
    #expect(body["seed"] == nil)
}

@Test func openAICompatibleImageWarnsForDeprecatedRawProviderOptionsKey() async throws {
    let rawTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"raw-image"}]}"#))
    let rawProvider = try openAICompatibleWarningProvider(transport: rawTransport)

    let rawResult = try await rawProvider.imageModel("image-model").generateImage(ImageGenerationRequest(
        prompt: "cat",
        extraBody: ["test-provider": .object(["quality": .string("hd")])]
    ))

    #expect(rawResult.warnings == [
        AIWarning(type: "deprecated", setting: "providerOptions key 'test-provider'", message: "Use 'testProvider' instead.")
    ])
    let rawBody = try await firstRecordedBody(rawTransport)
    #expect(rawBody["quality"]?.stringValue == "hd")
    #expect(rawBody["test-provider"] == nil)

    let camelTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"camel-image"}]}"#))
    let camelProvider = try openAICompatibleWarningProvider(transport: camelTransport)

    let camelResult = try await camelProvider.imageModel("image-model").generateImage(ImageGenerationRequest(
        prompt: "cat",
        extraBody: ["testProvider": .object(["quality": .string("standard")])]
    ))

    #expect(camelResult.warnings.isEmpty)
    let camelBody = try await firstRecordedBody(camelTransport)
    #expect(camelBody["quality"]?.stringValue == "standard")
    #expect(camelBody["testProvider"] == nil)
}

private func openAICompatibleWarningProvider(transport: RecordingTransport) throws -> OpenAICompatibleProvider {
    try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: transport
    )
}

private func firstRecordedBody(_ transport: RecordingTransport) async throws -> JSONValue {
    try decodeJSONBody(try #require((await transport.requests()).first?.body))
}
