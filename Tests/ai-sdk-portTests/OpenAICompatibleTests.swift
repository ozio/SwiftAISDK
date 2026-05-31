import Foundation
import Testing
@testable import ai_sdk_port

@Test func missingAPIKeyThrowsProviderSpecificError() throws {
    #expect(throws: AIError.self) {
        _ = try AIProviders.openAI(settings: ProviderSettings())
    }
}

@Test func openAICompatibleStreamsIncludeUsageWhenEnabled() async throws {
    let chatTransport = RecordingTransport(response: sseResponse("""
    data: {"choices":[{"delta":{"content":"hi"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}

    data: [DONE]

    """))
    let chatProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: chatTransport,
        includeUsage: true
    )
    let chatModel = try chatProvider.chatModel("chat-model")

    var chatUsage: TokenUsage?
    for try await part in chatModel.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        if case let .finish(_, usage) = part {
            chatUsage = usage
        }
    }

    #expect(chatUsage?.totalTokens == 3)
    let chatBody = try decodeJSONBody(try #require((await chatTransport.requests()).first?.body))
    #expect(chatBody["stream"] == true)
    #expect(chatBody["stream_options"]?["include_usage"]?.boolValue == true)

    let completionTransport = RecordingTransport(response: sseResponse("""
    data: {"choices":[{"text":"hel"}]}

    data: {"choices":[{"text":"lo","finish_reason":"stop"}],"usage":{"total_tokens":4}}

    data: [DONE]

    """))
    let completionProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: completionTransport,
        includeUsage: true
    )
    let completionModel = try completionProvider.completionModel("completion-model")

    var completionDeltas: [String] = []
    var completionUsage: TokenUsage?
    for try await part in completionModel.stream(LanguageModelRequest(messages: [.user("Finish")])) {
        switch part {
        case let .textDelta(delta):
            completionDeltas.append(delta)
        case let .finish(_, usage):
            completionUsage = usage
        default:
            break
        }
    }

    #expect(completionDeltas == ["hel", "lo"])
    #expect(completionUsage?.totalTokens == 4)
    let completionBody = try decodeJSONBody(try #require((await completionTransport.requests()).first?.body))
    #expect(completionBody["stream"] == true)
    #expect(completionBody["stream_options"]?["include_usage"]?.boolValue == true)
}

@Test func openAICompatibleAppendsQueryParamsToModelURLs() async throws {
    let chatTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"hello"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let chatProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com/base",
        apiKey: "test-key",
        queryParams: ["api-version": "2026-01-01", "region": "tokyo"],
        transport: chatTransport
    )
    _ = try await chatProvider.chatModel("chat-model").generate(LanguageModelRequest(messages: [.user("Hi")]))
    let chatRequest = try #require(await chatTransport.requests().first)
    #expect(chatRequest.url.absoluteString == "https://api.example.com/base/chat/completions?api-version=2026-01-01&region=tokyo")

    let completionTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"text":"done","finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let completionProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com/base",
        apiKey: "test-key",
        queryParams: ["api-version": "2026-01-01", "region": "tokyo"],
        transport: completionTransport
    )
    _ = try await completionProvider.completionModel("completion-model").generate(LanguageModelRequest(messages: [.user("Finish")]))
    let completionRequest = try #require(await completionTransport.requests().first)
    #expect(completionRequest.url.absoluteString == "https://api.example.com/base/completions?api-version=2026-01-01&region=tokyo")

    let embeddingTransport = RecordingTransport(response: jsonResponse("""
    {"data":[{"embedding":[0.1,0.2]}],"usage":{"total_tokens":2}}
    """))
    let embeddingProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com/base",
        apiKey: "test-key",
        queryParams: ["api-version": "2026-01-01", "region": "tokyo"],
        transport: embeddingTransport
    )
    _ = try await embeddingProvider.embeddingModel("embedding-model").embed(EmbeddingRequest(values: ["hello"]))
    let embeddingRequest = try #require(await embeddingTransport.requests().first)
    #expect(embeddingRequest.url.absoluteString == "https://api.example.com/base/embeddings?api-version=2026-01-01&region=tokyo")
}

@Test func openAICompatibleMapsResponseFormatForStructuredOutputs() async throws {
    let fallbackTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"{\\"value\\":\\"plain\\"}"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let fallbackProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: fallbackTransport
    )

    _ = try await fallbackProvider.chatModel("chat-model").generate(LanguageModelRequest(
        messages: [.user("JSON")],
        extraBody: [
            "responseFormat": [
                "type": "json",
                "schema": [
                    "type": "object",
                    "properties": ["value": ["type": "string"]],
                    "required": ["value"]
                ]
            ]
        ]
    ))

    let fallbackBody = try decodeJSONBody(try #require((await fallbackTransport.requests()).first?.body))
    #expect(fallbackBody["response_format"]?["type"]?.stringValue == "json_object")
    #expect(fallbackBody["response_format"]?["json_schema"] == nil)
    #expect(fallbackBody["responseFormat"] == nil)

    let structuredTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"{\\"value\\":\\"structured\\"}"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let structuredProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: structuredTransport,
        supportsStructuredOutputs: true
    )

    _ = try await structuredProvider.chatModel("chat-model").generate(LanguageModelRequest(
        messages: [.user("JSON")],
        extraBody: [
            "responseFormat": [
                "type": "json",
                "name": "answer",
                "description": "Answer schema",
                "schema": [
                    "type": "object",
                    "properties": ["value": ["type": "string"]],
                    "required": ["value"]
                ]
            ],
            "strictJsonSchema": false
        ]
    ))

    let structuredBody = try decodeJSONBody(try #require((await structuredTransport.requests()).first?.body))
    #expect(structuredBody["response_format"]?["type"]?.stringValue == "json_schema")
    #expect(structuredBody["response_format"]?["json_schema"]?["name"]?.stringValue == "answer")
    #expect(structuredBody["response_format"]?["json_schema"]?["description"]?.stringValue == "Answer schema")
    #expect(structuredBody["response_format"]?["json_schema"]?["schema"]?["type"]?.stringValue == "object")
    #expect(structuredBody["response_format"]?["json_schema"]?["strict"]?.boolValue == false)
    #expect(structuredBody["responseFormat"] == nil)
    #expect(structuredBody["strictJsonSchema"] == nil)
}

@Test func openAICompatibleTransformsChatRequestBodyForGenerateAndStream() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"hello"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let generateProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: generateTransport,
        transformRequestBody: { body in
            var body = body
            body["model_alias"] = body.removeValue(forKey: "model")
            body["proxy"] = .object(["mode": .string("generate")])
            return body
        }
    )

    _ = try await generateProvider.chatModel("chat-model").generate(LanguageModelRequest(messages: [.user("Hi")]))

    let generateBody = try decodeJSONBody(try #require((await generateTransport.requests()).first?.body))
    #expect(generateBody["model"] == nil)
    #expect(generateBody["model_alias"]?.stringValue == "chat-model")
    #expect(generateBody["proxy"]?["mode"]?.stringValue == "generate")
    #expect(generateBody["messages"]?[0]?["content"]?.stringValue == "Hi")

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"choices":[{"delta":{"content":"hi"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}

    data: [DONE]

    """))
    let streamProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: streamTransport,
        includeUsage: true,
        transformRequestBody: { body in
            var body = body
            body["proxy"] = .object([
                "sawStream": body["stream"] ?? .bool(false),
                "sawIncludeUsage": body["stream_options"]?["include_usage"] ?? .bool(false)
            ])
            body.removeValue(forKey: "stream_options")
            return body
        }
    )

    let streamModel = try streamProvider.chatModel("chat-model")
    for try await _ in streamModel.stream(LanguageModelRequest(messages: [.user("Hi")])) {}

    let streamBody = try decodeJSONBody(try #require((await streamTransport.requests()).first?.body))
    #expect(streamBody["stream"]?.boolValue == true)
    #expect(streamBody["stream_options"] == nil)
    #expect(streamBody["proxy"]?["sawStream"]?.boolValue == true)
    #expect(streamBody["proxy"]?["sawIncludeUsage"]?.boolValue == true)
}

@Test func openAICompatibleMapsNestedProviderOptionsByNamespace() async throws {
    let chatTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"hello"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let chatProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: chatTransport
    )

    _ = try await chatProvider.chatModel("chat-model").generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: [
            "direct": .string("kept"),
            "openai-compatible": .object(["user": .string("deprecated-user")]),
            "openaiCompatible": .object(["reasoningEffort": .string("low")]),
            "test-provider": .object(["custom": .string("raw")]),
            "testProvider": .object(["custom": .string("camel"), "textVerbosity": .string("high")])
        ]
    ))

    let chatBody = try decodeJSONBody(try #require((await chatTransport.requests()).first?.body))
    #expect(chatBody["direct"]?.stringValue == "kept")
    #expect(chatBody["user"]?.stringValue == "deprecated-user")
    #expect(chatBody["reasoning_effort"]?.stringValue == "low")
    #expect(chatBody["verbosity"]?.stringValue == "high")
    #expect(chatBody["custom"]?.stringValue == "camel")
    #expect(chatBody["openai-compatible"] == nil)
    #expect(chatBody["openaiCompatible"] == nil)
    #expect(chatBody["test-provider"] == nil)
    #expect(chatBody["testProvider"] == nil)

    let completionTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"text":"done","finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let completionProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: completionTransport
    )

    _ = try await completionProvider.completionModel("completion-model").generate(LanguageModelRequest(
        messages: [.user("Finish")],
        extraBody: [
            "test-provider": .object(["suffix": .string("raw")]),
            "testProvider": .object(["suffix": .string("camel"), "echo": .bool(true)])
        ]
    ))

    let completionBody = try decodeJSONBody(try #require((await completionTransport.requests()).first?.body))
    #expect(completionBody["suffix"]?.stringValue == "camel")
    #expect(completionBody["echo"]?.boolValue == true)
    #expect(completionBody["test-provider"] == nil)
    #expect(completionBody["testProvider"] == nil)

    let embeddingTransport = RecordingTransport(response: jsonResponse("""
    {"data":[{"embedding":[0.1,0.2]}],"usage":{"total_tokens":2}}
    """))
    let embeddingProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: embeddingTransport
    )

    _ = try await embeddingProvider.embeddingModel("embedding-model").embed(EmbeddingRequest(
        values: ["hello"],
        extraBody: [
            "openaiCompatible": .object(["encoding_format": .string("float")]),
            "test-provider": .object(["dimensions": .number(64)])
        ]
    ))

    let embeddingBody = try decodeJSONBody(try #require((await embeddingTransport.requests()).first?.body))
    #expect(embeddingBody["encoding_format"]?.stringValue == "float")
    #expect(embeddingBody["dimensions"]?.intValue == 64)
    #expect(embeddingBody["openaiCompatible"] == nil)
    #expect(embeddingBody["test-provider"] == nil)

    let imageTransport = RecordingTransport(response: jsonResponse("""
    {"data":[{"b64_json":"image-data"}]}
    """))
    let imageProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: imageTransport
    )

    _ = try await imageProvider.imageModel("image-model").generateImage(ImageGenerationRequest(
        prompt: "cat",
        extraBody: [
            "response_format": .string("url"),
            "test-provider": .object(["style": .string("raw")]),
            "testProvider": .object(["style": .string("camel")])
        ]
    ))

    let imageBody = try decodeJSONBody(try #require((await imageTransport.requests()).first?.body))
    #expect(imageBody["response_format"]?.stringValue == "b64_json")
    #expect(imageBody["style"]?.stringValue == "camel")
    #expect(imageBody["test-provider"] == nil)
    #expect(imageBody["testProvider"] == nil)
}

@Test func openAICompatibleChatWarnsForDeprecatedProviderOptionsKeys() async throws {
    let compatibilityTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"hello"},"finish_reason":"stop"}]}
    """))
    let compatibilityProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: compatibilityTransport
    )

    let compatibilityResult = try await compatibilityProvider.chatModel("chat-model").generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: ["openai-compatible": .object(["user": .string("deprecated-user")])]
    ))

    #expect(compatibilityResult.warnings == [
        AIWarning(type: "deprecated", setting: "providerOptions key 'openai-compatible'", message: "Use 'openaiCompatible' instead.")
    ])
    let compatibilityBody = try decodeJSONBody(try #require((await compatibilityTransport.requests()).first?.body))
    #expect(compatibilityBody["user"]?.stringValue == "deprecated-user")
    #expect(compatibilityBody["openai-compatible"] == nil)

    let rawTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"hello"},"finish_reason":"stop"}]}
    """))
    let rawProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: rawTransport
    )

    let rawResult = try await rawProvider.chatModel("chat-model").generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: ["test-provider": .object(["reasoningEffort": .string("high")])]
    ))

    #expect(rawResult.warnings == [
        AIWarning(type: "deprecated", setting: "providerOptions key 'test-provider'", message: "Use 'testProvider' instead.")
    ])
    let rawBody = try decodeJSONBody(try #require((await rawTransport.requests()).first?.body))
    #expect(rawBody["reasoning_effort"]?.stringValue == "high")
    #expect(rawBody["test-provider"] == nil)

    let camelTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"hello"},"finish_reason":"stop"}]}
    """))
    let camelProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: camelTransport
    )

    let camelResult = try await camelProvider.chatModel("chat-model").generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: ["testProvider": .object(["reasoningEffort": .string("low")])]
    ))

    #expect(camelResult.warnings.isEmpty)
    let camelBody = try decodeJSONBody(try #require((await camelTransport.requests()).first?.body))
    #expect(camelBody["reasoning_effort"]?.stringValue == "low")
    #expect(camelBody["testProvider"] == nil)
}

@Test func openAICompatibleImageRejectsMoreThanMaxImagesPerCall() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"unused"}]}"#))
    let provider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: transport
    )
    let model = try provider.imageModel("image-model")

    await #expect(throws: AIError.invalidArgument(argument: "count", message: "OpenAI-compatible image models support at most 10 image(s) per call.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", count: 11))
    }

    #expect(await transport.requests().isEmpty)
}

@Test func openAICompatibleImageReturnsWarningsForUnsupportedSettings() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"image-data"}]}"#))
    let provider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: transport
    )

    let result = try await provider.imageModel("image-model").generateImage(ImageGenerationRequest(
        prompt: "cat",
        aspectRatio: "16:9",
        seed: 123
    ))

    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "aspectRatio", message: "This model does not support aspect ratio. Use `size` instead."),
        AIWarning(type: "unsupported", feature: "seed")
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["aspectRatio"] == nil)
    #expect(body["aspect_ratio"] == nil)
    #expect(body["seed"] == nil)
}

@Test func openAICompatibleImageWarnsForDeprecatedRawProviderOptionsKey() async throws {
    let rawTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"raw-image"}]}"#))
    let rawProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: rawTransport
    )

    let rawResult = try await rawProvider.imageModel("image-model").generateImage(ImageGenerationRequest(
        prompt: "cat",
        extraBody: ["test-provider": .object(["quality": .string("hd")])]
    ))

    #expect(rawResult.warnings == [
        AIWarning(type: "deprecated", setting: "providerOptions key 'test-provider'", message: "Use 'testProvider' instead.")
    ])
    let rawBody = try decodeJSONBody(try #require((await rawTransport.requests()).first?.body))
    #expect(rawBody["quality"]?.stringValue == "hd")
    #expect(rawBody["test-provider"] == nil)

    let camelTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"camel-image"}]}"#))
    let camelProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: camelTransport
    )

    let camelResult = try await camelProvider.imageModel("image-model").generateImage(ImageGenerationRequest(
        prompt: "cat",
        extraBody: ["testProvider": .object(["quality": .string("standard")])]
    ))

    #expect(camelResult.warnings.isEmpty)
    let camelBody = try decodeJSONBody(try #require((await camelTransport.requests()).first?.body))
    #expect(camelBody["quality"]?.stringValue == "standard")
    #expect(camelBody["testProvider"] == nil)
}

@Test func openAIImageRejectsMoreThanModelSpecificMaxImagesPerCall() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"unused"}]}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.imageModel("dall-e-3")

    await #expect(throws: AIError.invalidArgument(argument: "count", message: "OpenAI-compatible image models support at most 1 image(s) per call.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", count: 2))
    }

    #expect(await transport.requests().isEmpty)
}

@Test func azureImageDeploymentRejectsMoreThanDefaultMaxImagesPerCall() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"unused"}]}"#))
    let provider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: transport))
    let model = try provider.imageModel("dalle-deployment")

    await #expect(throws: AIError.invalidArgument(argument: "count", message: "OpenAI-compatible image models support at most 1 image(s) per call.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", count: 2))
    }

    #expect(await transport.requests().isEmpty)
}

@Test func openAICompatibleEmbeddingRejectsMoreThanMaxEmbeddingsPerCall() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"embedding":[0.1,0.2]}]}"#))
    let provider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: transport,
        maxEmbeddingsPerCall: 2
    )
    let model = try provider.embeddingModel("embedding-model")

    await #expect(throws: AIError.invalidArgument(argument: "values", message: "OpenAI-compatible embedding models support at most 2 values per call.")) {
        _ = try await model.embed(EmbeddingRequest(values: ["one", "two", "three"]))
    }

    #expect(await transport.requests().isEmpty)
}
