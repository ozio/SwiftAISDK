import Foundation
import Testing
@testable import SwiftAISDK

@Test func azureLanguageDefaultsToResponsesV1URLAndApiKeyHeader() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"azure response","usage":{"input_tokens":2,"output_tokens":3,"total_tokens":5}}"#))
    let provider = try AIProviders.azure(resourceName: "test-resource", apiVersion: "2025-04-01-preview", settings: ProviderSettings(
        apiKey: "azure-key",
        headers: ["Custom-Provider-Header": "provider"],
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
    #expect(request.headers["Custom-Provider-Header"] == "provider")
    #expect(request.headers["Custom-Request-Header"] == "request")
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

@Test func azureProviderAliasesRouteToUpstreamEndpoints() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"azure responses"}"#),
        jsonResponse(#"{"choices":[{"message":{"content":"azure chat"},"finish_reason":"stop"}]}"#),
        jsonResponse(#"{"choices":[{"text":"azure completion","finish_reason":"stop"}]}"#)
    ])
    let provider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: transport))

    let languageModel = try provider.languageModel("responses-deployment")
    let responsesModel = try provider.responses("responses-deployment")
    let chatModel = try provider.chat("chat-deployment")
    let completionModel = try provider.completion("completion-deployment")
    let embeddingModel = try provider.embeddingModel("embedding-deployment")
    let imageModel = try provider.imageModel("image-deployment")
    let transcriptionModel = try provider.transcriptionModel("transcription-deployment")
    let speechModel = try provider.speechModel("speech-deployment")

    #expect(provider.providerID == "azure")
    #expect(languageModel.providerID == "azure.responses")
    #expect(responsesModel.providerID == "azure.responses")
    #expect(chatModel.providerID == "azure.chat")
    #expect(completionModel.providerID == "azure.completion")
    #expect(embeddingModel.providerID == "azure.embeddings")
    #expect(imageModel.providerID == "azure.image")
    #expect(transcriptionModel.providerID == "azure.transcription")
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

@Test func quiverAIImageGeneratesSVGAndForwardsOptions() async throws {
    let svg = #"<svg viewBox="0 0 10 10"><rect width="10" height="10"/></svg>"#
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"svg-gen-1","created":1713374400,"data":[{"svg":"\(svg.replacingOccurrences(of: "\"", with: "\\\""))","mime_type":"image/svg+xml"}],"usage":{"total_tokens":21,"input_tokens":12,"output_tokens":9}}
    """))
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", transport: transport))
    let model = try provider.imageModel("arrow-1")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "Draw a square icon.",
        count: 1,
        files: [
            ImageInputFile(url: "https://example.com/reference-1.png"),
            ImageInputFile(data: Data([4, 5, 6]), mediaType: "image/png")
        ],
        extraBody: [
            "instructions": "Use clean geometry.",
            "temperature": 0.4,
            "topP": 0.95,
            "presencePenalty": 0.2,
            "maxOutputTokens": 4096
        ]
    ))

    #expect(String(data: Data(base64Encoded: try #require(result.base64Images.first)) ?? Data(), encoding: .utf8) == svg)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.quiver.ai/v1/svgs/generations")
    #expect(request.headers["Authorization"] == "Bearer quiver-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "arrow-1")
    #expect(body["prompt"]?.stringValue == "Draw a square icon.")
    #expect(body["n"]?.intValue == 1)
    #expect(body["stream"]?.boolValue == false)
    #expect(body["instructions"]?.stringValue == "Use clean geometry.")
    #expect(body["temperature"]?.doubleValue == 0.4)
    #expect(body["top_p"]?.doubleValue == 0.95)
    #expect(body["presence_penalty"]?.doubleValue == 0.2)
    #expect(body["max_output_tokens"]?.intValue == 4096)
    #expect(body["references"]?[0]?["url"]?.stringValue == "https://example.com/reference-1.png")
    #expect(body["references"]?[1]?["base64"]?.stringValue == "BAUG")
    #expect(result.rawValue["usage"]?["total_tokens"]?.intValue == 21)
}

@Test func quiverAIVectorizesSingleImage() async throws {
    let svg = #"<svg viewBox="0 0 4 4"><path d="M0 0L4 4"/></svg>"#
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"svg-vec-1","created":1713374460,"data":[{"svg":"\(svg.replacingOccurrences(of: "\"", with: "\\\""))","mime_type":"image/svg+xml"}]}
    """))
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", transport: transport))
    let model = try provider.imageModel("arrow-1")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "",
        count: 1,
        files: [ImageInputFile(url: "https://example.com/logo.png")],
        extraBody: [
            "operation": "vectorize",
            "autoCrop": true,
            "targetSize": 1024
        ]
    ))

    #expect(String(data: Data(base64Encoded: try #require(result.base64Images.first)) ?? Data(), encoding: .utf8) == svg)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.quiver.ai/v1/svgs/vectorizations")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "arrow-1")
    #expect(body["image"]?["url"]?.stringValue == "https://example.com/logo.png")
    #expect(body["auto_crop"]?.boolValue == true)
    #expect(body["target_size"]?.intValue == 1024)
    #expect(body["stream"]?.boolValue == false)
}
