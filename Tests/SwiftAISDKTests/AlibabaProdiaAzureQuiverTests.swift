import Foundation
import Testing
@testable import SwiftAISDK

private actor TokenStore {
    private var tokens: [String]
    private var index = 0
    var count: Int { index }

    init(tokens: [String]) {
        self.tokens = tokens
    }

    func next() -> String {
        defer { index += 1 }
        return tokens[min(index, tokens.count - 1)]
    }
}

@Test func azureLanguageDefaultsToResponsesV1URLAndApiKeyHeader() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"azure response","usage":{"input_tokens":2,"output_tokens":3,"total_tokens":5}}"#))
    let provider = try AIProviders.azure(resourceName: "test-resource", apiVersion: "2025-04-01-preview", settings: ProviderSettings(
        apiKey: "azure-key",
        headers: [
            "Custom-Provider-Header": "provider",
            "user-agent": "my-app"
        ],
        transport: transport
    ))
    let model = try provider.languageModel("gpt-4.1-deployment")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        maxOutputTokens: 32,
        extraBody: [
            "azure": .object([
                "previousResponseId": .string("resp-azure"),
                "store": .bool(true)
            ]),
            "openai": .object([
                "previousResponseId": .string("resp-old"),
                "store": .bool(false)
            ])
        ],
        headers: ["Custom-Request-Header": "request"]
    ))

    #expect(result.text == "azure response")
    #expect(result.usage?.totalTokens == 5)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/responses?api-version=2025-04-01-preview")
    #expect(request.headers["api-key"] == "azure-key")
    #expect(request.headers["custom-provider-header"] == "provider")
    #expect(request.headers["Custom-Request-Header"] == "request")
    #expect(request.headers["user-agent"] == "my-app ai-sdk/azure/3.0.77")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "gpt-4.1-deployment")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
    #expect(body["max_output_tokens"]?.intValue == 32)
    #expect(body["previous_response_id"]?.stringValue == "resp-azure")
    #expect(body["store"]?.boolValue == true)
    #expect(body["azure"] == nil)
    #expect(body["openai"] == nil)
    #expect(body["previousResponseId"] == nil)
}

@Test func azureUsesTokenProviderForBearerAuthLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"first"}"#),
        jsonResponse(#"{"id":"resp-2","status":"completed","output_text":"second"}"#)
    ])
    let tokenStore = TokenStore(tokens: ["token-one", "token-two"])
    let provider = try AIProviders.azure(
        resourceName: "test-resource",
        tokenProvider: { await tokenStore.next() },
        settings: ProviderSettings(transport: transport)
    )
    let model = try provider.responses("responses-deployment")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("One")]))
    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Two")],
        headers: ["Authorization": "Bearer caller-token"]
    ))

    let requests = await transport.requests()
    #expect(requests[0].headers["authorization"] == "Bearer token-one")
    #expect(requests[0].headers["api-key"] == nil)
    #expect(requests[1].headers["Authorization"] == "Bearer caller-token")
    #expect(requests[1].headers["authorization"] == nil)
    #expect(await tokenStore.count == 1)
}

@Test func azureRejectsAPIKeyAndTokenProviderTogetherLikeUpstream() async throws {
    #expect(throws: AIError.invalidArgument(argument: "apiKey/tokenProvider", message: "Both apiKey and tokenProvider were provided. Please use only one authentication method.")) {
        _ = try AIProviders.azure(
            resourceName: "test-resource",
            tokenProvider: { "azure-token" },
            settings: ProviderSettings(apiKey: "azure-key")
        )
    }
}

@Test func azureCompletionMapsAzureProviderOptionsOverOpenAI() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"text":"azure completion","finish_reason":"stop"}],"usage":{"total_tokens":4}}
    """))
    let provider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: transport))
    let model = try provider.completionModel("completion-deployment")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Complete")],
        extraBody: [
            "openai": .object([
                "suffix": .string("openai-tail"),
                "echo": .bool(false)
            ]),
            "azure": .object([
                "suffix": .string("azure-tail"),
                "best_of": .number(2)
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/completions?api-version=v1")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "completion-deployment")
    #expect(body["suffix"]?.stringValue == "azure-tail")
    #expect(body["echo"]?.boolValue == false)
    #expect(body["best_of"]?.intValue == 2)
    #expect(body["azure"] == nil)
    #expect(body["openai"] == nil)
}

@Test func azureChatUsesExplicitChatCompletionURL() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"azure chat"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}"#))
    let provider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: transport))
    let model = try provider.chatModel("chat-deployment")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "azure chat")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/chat/completions?api-version=v1")
    #expect(request.headers["api-key"] == "azure-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "chat-deployment")
    #expect(body["messages"]?[0]?["content"]?.stringValue == "Hi")
}

@Test func azureDeepSeekUsesChatCompletionsAndOmitsThinkingOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"azure deepseek"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}"#))
    let provider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: transport))
    let model = try provider.deepseek("deepseek-deployment")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        providerOptions: [
            "deepseek": [
                "thinking": ["type": "enabled"],
                "reasoningEffort": "xhigh"
            ]
        ]
    ))

    #expect(model.providerID == "azure.deepseek")
    #expect(result.text == "azure deepseek")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/chat/completions?api-version=v1")
    #expect(request.headers["api-key"] == "azure-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "deepseek-deployment")
    #expect(body["thinking"] == nil)
    #expect(body["reasoning_effort"]?.stringValue == "xhigh")
}

@Test func azureProviderAliasesRouteToUpstreamEndpoints() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"azure responses"}"#),
        jsonResponse(#"{"choices":[{"message":{"content":"azure chat"},"finish_reason":"stop"}]}"#),
        jsonResponse(#"{"choices":[{"text":"azure completion","finish_reason":"stop"}]}"#)
    ])
    let provider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: transport))

    let callableModel = try provider("responses-deployment")
    let languageModel = try provider.languageModel("responses-deployment")
    let responsesModel = try provider.responses("responses-deployment")
    let chatModel = try provider.chat("chat-deployment")
    let completionModel = try provider.completion("completion-deployment")
    let embeddingAlias = try provider.embedding("embedding-deployment")
    let embeddingModel = try provider.embeddingModel("embedding-deployment")
    let textEmbedding = try provider.textEmbedding("embedding-deployment")
    let textEmbeddingModel = try provider.textEmbeddingModel("embedding-deployment")
    let imageAlias = try provider.image("image-deployment")
    let imageModel = try provider.imageModel("image-deployment")
    let transcriptionAlias = try provider.transcription("transcription-deployment")
    let transcriptionModel = try provider.transcriptionModel("transcription-deployment")
    let speechAlias = try provider.speech("speech-deployment")
    let speechModel = try provider.speechModel("speech-deployment")

    #expect(provider.providerID == "azure")
    #expect(callableModel.providerID == "azure.responses")
    #expect(languageModel.providerID == "azure.responses")
    #expect(responsesModel.providerID == "azure.responses")
    #expect(chatModel.providerID == "azure.chat")
    #expect(completionModel.providerID == "azure.completion")
    #expect(embeddingAlias.providerID == "azure.embeddings")
    #expect(embeddingModel.providerID == "azure.embeddings")
    #expect(textEmbedding.providerID == "azure.embeddings")
    #expect(textEmbeddingModel.providerID == "azure.embeddings")
    #expect(imageAlias.providerID == "azure.image")
    #expect(imageModel.providerID == "azure.image")
    #expect(transcriptionAlias.providerID == "azure.transcription")
    #expect(transcriptionModel.providerID == "azure.transcription")
    #expect(speechAlias.providerID == "azure.speech")
    #expect(speechModel.providerID == "azure.speech")

    let responsesResult = try await responsesModel.generate(LanguageModelRequest(messages: [.user("Hi")]))
    let chatResult = try await chatModel.generate(LanguageModelRequest(messages: [.user("Hi")]))
    let completionResult = try await completionModel.generate(LanguageModelRequest(messages: [.user("Finish")]))

    #expect(responsesResult.text == "azure responses")
    #expect(chatResult.text == "azure chat")
    #expect(completionResult.text == "azure completion")
    let requests = await transport.requests()
    #expect(requests[0].url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/responses?api-version=v1")
    #expect(requests[1].url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/chat/completions?api-version=v1")
    #expect(requests[2].url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/completions?api-version=v1")
}

@Test func azureOpenAIToolsHelpersMirrorOpenAIHostedToolFactories() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"azure tools"}"#))
    let provider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: transport))
    let model = try provider.responses("responses-deployment")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Search docs.")],
        tools: [
            "web_search": AzureOpenAITools.webSearch(searchContextSize: "low"),
            "file_search": AzureOpenAITools.fileSearch(vectorStoreIDs: ["vs_azure"], maxNumResults: 2),
            "code_interpreter": AzureOpenAITools.codeInterpreter(),
            "image_generation": AzureOpenAITools.imageGeneration(size: "1024x1024")
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.contains { $0["type"]?.stringValue == "web_search" && $0["search_context_size"]?.stringValue == "low" })
    #expect(tools.contains { $0["type"]?.stringValue == "file_search" && $0["vector_store_ids"]?[0]?.stringValue == "vs_azure" })
    #expect(tools.contains { $0["type"]?.stringValue == "code_interpreter" && $0["container"]?["type"]?.stringValue == "auto" })
    #expect(tools.contains { $0["type"]?.stringValue == "image_generation" && $0["size"]?.stringValue == "1024x1024" })
}

@Test func azureDeploymentBasedTranscriptionURLAndProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"azure transcript"}"#))
    let provider = try AIProviders.azure(
        resourceName: "test-resource",
        useDeploymentBasedURLs: true,
        settings: ProviderSettings(apiKey: "azure-key", transport: transport)
    )
    let model = try provider.transcriptionModel("whisper-1")

    let result = try await model.transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8), mimeType: "audio/wav", extraBody: ["timestampGranularities": ["word"]]))

    #expect(result.text == "azure transcript")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://test-resource.openai.azure.com/openai/deployments/whisper-1/audio/transcriptions?api-version=v1")
    #expect(request.headers["api-key"] == "azure-key")
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("verbose_json"))
    #expect(bodyText.contains("name=\"timestamp_granularities[]\""))
    #expect(bodyText.contains("word"))
}

@Test func azureImageAndSpeechUseOpenAIOptionMapping() async throws {
    let imageTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"azure-image"}]}"#))
    let imageProvider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("dalle-deployment")

    let image = try await imageModel.generateImage(ImageGenerationRequest(prompt: "cat", extraBody: ["outputFormat": "png", "outputCompression": 70]))

    #expect(image.base64Images == ["azure-image"])
    let imageRequest = try #require(await imageTransport.requests().first)
    #expect(imageRequest.url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/images/generations?api-version=v1")
    let imageBody = try decodeJSONBody(try #require(imageRequest.body))
    #expect(imageBody["response_format"]?.stringValue == "b64_json")
    #expect(imageBody["output_format"]?.stringValue == "png")
    #expect(imageBody["output_compression"]?.intValue == 70)

    let speechTransport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("mp3".utf8)))
    let speechProvider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: speechTransport))
    let speechModel = try speechProvider.speechModel("tts-deployment")

    _ = try await speechModel.speak(SpeechRequest(text: "Hello"))

    let speechRequest = try #require(await speechTransport.requests().first)
    #expect(speechRequest.url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/audio/speech?api-version=v1")
    let speechBody = try decodeJSONBody(try #require(speechRequest.body))
    #expect(speechBody["voice"]?.stringValue == "alloy")
    #expect(speechBody["response_format"]?.stringValue == "mp3")
}

@Test func azureImageMapsNestedOpenAIProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"azure-image"}]}"#))
    let provider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: transport))
    let model = try provider.imageModel("dalle-deployment")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "1024x1024",
        count: 1,
        extraBody: [
            "openai": .object([
                "style": .string("natural"),
                "outputFormat": .string("png")
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/images/generations?api-version=v1")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "dalle-deployment")
    #expect(body["n"]?.intValue == 1)
    #expect(body["style"]?.stringValue == "natural")
    #expect(body["output_format"]?.stringValue == "png")
    #expect(body["response_format"]?.stringValue == "b64_json")
    #expect(body["openai"] == nil)
    #expect(body["outputFormat"] == nil)
}
