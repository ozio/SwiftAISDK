import Foundation
import Testing
@testable import SwiftAISDK

@Test func googleToolsHelpersMirrorProviderExecutedToolFactories() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"grounded"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use Google tools.")],
        tools: [
            "google.google_search": GoogleTools.googleSearch(
                searchTypes: ["webSearch": [:], "imageSearch": [:]],
                timeRangeFilter: ["startTime": "2025-01-01T00:00:00Z", "endTime": "2025-02-01T00:00:00Z"]
            ),
            "google.enterprise_web_search": GoogleTools.enterpriseWebSearch(),
            "google.google_maps": GoogleTools.googleMaps(),
            "google.url_context": GoogleTools.urlContext(),
            "google.file_search": GoogleTools.fileSearch(
                fileSearchStoreNames: ["fileSearchStores/store-1"],
                metadataFilter: #"author="Ada""#,
                topK: 4
            ),
            "google.code_execution": GoogleTools.codeExecution()
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    let googleSearch = try #require(tools.first { $0["googleSearch"] != nil })
    #expect(googleSearch["googleSearch"]?["searchTypes"]?["webSearch"] != nil)
    #expect(googleSearch["googleSearch"]?["timeRangeFilter"]?["startTime"]?.stringValue == "2025-01-01T00:00:00Z")
    #expect(tools.contains { $0["enterpriseWebSearch"]?.objectValue?.isEmpty == true })
    #expect(tools.contains { $0["googleMaps"]?.objectValue?.isEmpty == true })
    #expect(tools.contains { $0["urlContext"]?.objectValue?.isEmpty == true })
    let fileSearch = try #require(tools.first { $0["fileSearch"] != nil })
    #expect(fileSearch["fileSearch"]?["fileSearchStoreNames"]?[0]?.stringValue == "fileSearchStores/store-1")
    #expect(fileSearch["fileSearch"]?["metadataFilter"]?.stringValue == #"author="Ada""#)
    #expect(fileSearch["fileSearch"]?["topK"]?.intValue == 4)
    #expect(tools.contains { $0["codeExecution"]?.objectValue?.isEmpty == true })
}
@Test func googleLanguageStreamStartCarriesProviderToolWarnings() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"candidates":[{"content":{"parts":[{"text":"ok"}],"role":"model"},"finishReason":"STOP","index":0}]}

    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-pro")

    var startWarnings: [AIWarning] = []
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Search.")],
        tools: ["google.google_search": GoogleTools.googleSearch()]
    )) {
        if case let .streamStart(warnings) = part {
            startWarnings = warnings
        }
    }

    #expect(startWarnings.contains {
        $0.type == "unsupported" && $0.feature == "provider-defined tool google.google_search" && $0.message == "Google Search requires Gemini 2.0 or newer."
    })
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["tools"] == nil)
}
@Test func googleLanguageParsesFunctionCalls() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"functionCall":{"name":"weather","args":{"location":"San Francisco"}},"thoughtSignature":"sig-google-tool"}],"role":"model"},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":29,"candidatesTokenCount":15,"totalTokenCount":44}}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Weather?")]))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.usage?.totalTokens == 44)
    #expect(result.toolCalls.count == 1)
    #expect(result.toolCalls[0].id == "tool-call-0")
    #expect(result.toolCalls[0].name == "weather")
    #expect(try decodeJSONBody(Data(result.toolCalls[0].arguments.utf8))["location"]?.stringValue == "San Francisco")
    #expect(result.toolCalls[0].providerMetadata["google"]?["thoughtSignature"]?.stringValue == "sig-google-tool")
}
@Test func googleGenerateContentReplaysToolCallThoughtSignature() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"done"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")
    let toolCall = AIToolCall(
        id: "tool-call-0",
        name: "weather",
        arguments: #"{"location":"Tokyo"}"#,
        providerMetadata: ["google": .object(["thoughtSignature": .string("sig-google-tool")])]
    )
    let toolResult = AIToolResult(
        toolCallID: "tool-call-0",
        toolName: "weather",
        result: ["forecast": "sunny"]
    )

    _ = try await model.generate(LanguageModelRequest(messages: [
        .user("Weather?"),
        .assistant(toolCalls: [toolCall]),
        .toolResult(toolResult)
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["contents"]?[1]?["parts"]?[0]?["functionCall"]?["name"]?.stringValue == "weather")
    #expect(body["contents"]?[1]?["parts"]?[0]?["thoughtSignature"]?.stringValue == "sig-google-tool")
}
@Test func googleGenerateContentInjectsGemini3ThoughtSignatureSentinel() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"done"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-3-pro")

    let result = try await model.generate(LanguageModelRequest(messages: [
        .user("Weather?"),
        .assistant(toolCalls: [
            AIToolCall(id: "tool-call-0", name: "weather", arguments: #"{"location":"Tokyo"}"#)
        ])
    ]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["contents"]?[1]?["parts"]?[0]?["functionCall"]?["name"]?.stringValue == "weather")
    #expect(body["contents"]?[1]?["parts"]?[0]?["thoughtSignature"]?.stringValue == "skip_thought_signature_validator")
    #expect(result.warnings.contains { $0.type == "other" && ($0.message?.contains("skip_thought_signature_validator") ?? false) })
}
@Test func googleGenerateContentParsesProviderExecutedCodeAndServerTools() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"executableCode":{"language":"PYTHON","code":"print('hi')"}},{"codeExecutionResult":{"outcome":"OUTCOME_OK","output":"hi\\n"}},{"toolCall":{"toolType":"google_search","id":"search-1","args":{"query":"swift"}},"thoughtSignature":"sig-server"},{"toolResponse":{"toolType":"google_search","response":{"results":[{"title":"Swift"}]}}}],"role":"model"},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-3-pro")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Search and run code.")]))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.toolCalls.count == 2)
    #expect(result.toolCalls[0].id == "google-code-execution-0")
    #expect(result.toolCalls[0].name == "code_execution")
    #expect(result.toolCalls[0].providerExecuted == true)
    #expect(try decodeJSONBody(Data(result.toolCalls[0].arguments.utf8))["code"]?.stringValue == "print('hi')")
    #expect(result.toolCalls[1].id == "search-1")
    #expect(result.toolCalls[1].name == "server:google_search")
    #expect(result.toolCalls[1].providerExecuted == true)
    #expect(result.toolCalls[1].dynamic == true)
    #expect(result.toolCalls[1].providerMetadata["google"]?["serverToolType"]?.stringValue == "google_search")
    #expect(result.toolCalls[1].providerMetadata["google"]?["thoughtSignature"]?.stringValue == "sig-server")
    #expect(result.toolResults.count == 2)
    #expect(result.toolResults[0].toolCallID == "google-code-execution-0")
    #expect(result.toolResults[0].result["outcome"]?.stringValue == "OUTCOME_OK")
    #expect(result.toolResults[0].result["output"]?.stringValue == "hi\n")
    #expect(result.toolResults[1].toolCallID == "search-1")
    #expect(result.toolResults[1].toolName == "server:google_search")
    #expect(result.toolResults[1].dynamic == true)
    #expect(result.toolResults[1].result["results"]?[0]?["title"]?.stringValue == "Swift")
}
@Test func googleGenerateContentStreamsProviderExecutedToolsAndInlineData() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"aW1hZ2U="},"thoughtSignature":"sig-file"},{"executableCode":{"language":"PYTHON","code":"print('hi')"}},{"codeExecutionResult":{"outcome":"OUTCOME_OK","output":"hi\\n"}},{"toolCall":{"toolType":"google_search","id":"search-1","args":{"query":"swift"}}},{"toolResponse":{"toolType":"google_search","response":{"results":[{"title":"Swift"}]}}}],"role":"model"},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":2,"totalTokenCount":3}}

    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-3-pro")

    var files: [AIStreamFile] = []
    var toolCalls: [AIToolCall] = []
    var toolResults: [AIToolResult] = []
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Search and run code.")])) {
        switch part {
        case let .file(file):
            files.append(file)
        case let .toolCall(call):
            toolCalls.append(call)
        case let .toolResult(result):
            toolResults.append(result)
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(files.count == 1)
    #expect(files[0].mediaType == "image/png")
    #expect(files[0].data == Data("image".utf8))
    #expect(files[0].providerMetadata["google"]?["thoughtSignature"]?.stringValue == "sig-file")
    #expect(toolCalls.map(\.name) == ["code_execution", "server:google_search"])
    #expect(toolCalls.map(\.providerExecuted) == [true, true])
    #expect(toolResults.map(\.toolCallID) == ["google-code-execution-1", "search-1"])
    #expect(toolResults[1].result["results"]?[0]?["title"]?.stringValue == "Swift")
    #expect(finishReason == "tool-calls")
}
@Test func googleLanguageExtractsGroundingSources() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"grounded"}]},"finishReason":"STOP","groundingMetadata":{"groundingChunks":[{"web":{"uri":"https://source.example.com","title":"Source Title"}},{"retrievedContext":{"uri":"gs://rag-corpus/document.pdf","title":"RAG Document","text":"Retrieved context"}},{"retrievedContext":{"fileSearchStore":"fileSearchStores/test-store-xyz","title":"Test Document"}},{"maps":{"uri":"https://maps.google.com/maps?cid=12345","title":"Best Restaurant"}},{"image":{"sourceUri":"https://example.com/article","imageUri":"https://example.com/image.jpg","title":"Image Result"}}]}}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Ground it.")]))

    #expect(result.text == "grounded")
    #expect(result.sources.count == 5)
    #expect(result.sources[0].id == "grounding-0")
    #expect(result.sources[0].sourceType == "url")
    #expect(result.sources[0].url == "https://source.example.com")
    #expect(result.sources[0].title == "Source Title")
    #expect(result.sources[1].sourceType == "document")
    #expect(result.sources[1].title == "RAG Document")
    #expect(result.sources[1].mediaType == "application/pdf")
    #expect(result.sources[1].filename == "document.pdf")
    #expect(result.sources[2].sourceType == "document")
    #expect(result.sources[2].title == "Test Document")
    #expect(result.sources[2].mediaType == "application/octet-stream")
    #expect(result.sources[2].filename == "test-store-xyz")
    #expect(result.sources[3].sourceType == "url")
    #expect(result.sources[3].url == "https://maps.google.com/maps?cid=12345")
    #expect(result.sources[3].title == "Best Restaurant")
    #expect(result.sources[4].sourceType == "url")
    #expect(result.sources[4].url == "https://example.com/article")
    #expect(result.sources[4].title == "Image Result")
    #expect(result.sources[4].rawValue?["image"]?["imageUri"]?.stringValue == "https://example.com/image.jpg")
}
@Test func googleLanguagePreservesGenerateContentProviderMetadata() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"metadata"}]},"finishReason":"STOP","finishMessage":"done","safetyRatings":[{"category":"HARM_CATEGORY_DANGEROUS_CONTENT","probability":"NEGLIGIBLE","blocked":false}],"groundingMetadata":{"webSearchQueries":["weather"],"groundingChunks":[{"web":{"uri":"https://source.example.com","title":"Source"}}]},"urlContextMetadata":{"urlMetadata":[{"retrievedUrl":"https://example.com/page","urlRetrievalStatus":"URL_RETRIEVAL_STATUS_SUCCESS"}]}}],"promptFeedback":{"blockReason":"SAFETY","safetyRatings":[{"category":"HARM_CATEGORY_HATE_SPEECH","probability":"NEGLIGIBLE"}]},"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":2,"totalTokenCount":3,"serviceTier":"priority"}}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Metadata?")]))
    let metadata = try #require(result.providerMetadata["google"])

    #expect(metadata["safetyRatings"]?[0]?["category"]?.stringValue == "HARM_CATEGORY_DANGEROUS_CONTENT")
    #expect(metadata["promptFeedback"]?["blockReason"]?.stringValue == "SAFETY")
    #expect(metadata["groundingMetadata"]?["webSearchQueries"]?[0]?.stringValue == "weather")
    #expect(metadata["urlContextMetadata"]?["urlMetadata"]?[0]?["retrievedUrl"]?.stringValue == "https://example.com/page")
    #expect(metadata["finishMessage"]?.stringValue == "done")
    #expect(metadata["serviceTier"]?.stringValue == "priority")
}
@Test func googleImagenUsesPredictInstancesAndParameters() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"predictions":[{"bytesBase64Encoded":"image-1"},{"bytesBase64Encoded":"image-2"}]}"#))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.imageModel("imagen-4.0-generate-001")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        aspectRatio: "16:9",
        count: 2,
        extraBody: ["negativePrompt": "blur", "personGeneration": "allow_adult"]
    ))

    #expect(result.base64Images == ["image-1", "image-2"])
    #expect(result.providerMetadata["google"]?["images"]?.arrayValue?.count == 2)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/imagen-4.0-generate-001:predict")
    #expect(request.headers["x-goog-api-key"] == "gemini-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["instances"]?[0]?["prompt"]?.stringValue == "cat")
    #expect(body["parameters"]?["sampleCount"]?.intValue == 2)
    #expect(body["parameters"]?["aspectRatio"]?.stringValue == "16:9")
    #expect(body["parameters"]?["negativePrompt"]?.stringValue == "blur")
    #expect(body["parameters"]?["personGeneration"]?.stringValue == "allow_adult")
}
@Test func googleImagenRejectsEditingAndWarnsForUnsupportedSizeSeedLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"predictions":[{"bytesBase64Encoded":"image"}]}"#))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.imageModel("imagen-4.0-generate-001")

    await #expect(throws: AIError.invalidArgument(argument: "files", message: "Google Generative AI does not support image editing with Imagen models. Use Google Vertex AI (@ai-sdk/google-vertex) for image editing capabilities.")) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "edit",
            files: [ImageInputFile(data: Data("image".utf8), mediaType: "image/png")]
        ))
    }
    await #expect(throws: AIError.invalidArgument(argument: "mask", message: "Google Generative AI does not support image editing with masks. Use Google Vertex AI (@ai-sdk/google-vertex) for image editing capabilities.")) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "edit",
            mask: ImageInputFile(data: Data("mask".utf8), mediaType: "image/png")
        ))
    }

    let result = try await model.generateImage(ImageGenerationRequest(prompt: "cat", size: "16:9", seed: 42))
    #expect(result.warnings.contains { $0.type == "unsupported" && $0.feature == "size" })
    #expect(result.warnings.contains { $0.type == "unsupported" && $0.feature == "seed" })
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["parameters"]?["aspectRatio"]?.stringValue == "1:1")
    #expect(body["parameters"]?["seed"] == nil)
}
@Test func googleGeminiImageUsesGenerateContentImageModality() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"gemini-image"}}]}}]}"#))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.imageModel("gemini-2.5-flash-image")

    #expect(model.providerID == "google.generative-ai")
    let result = try await model.generateImage(ImageGenerationRequest(prompt: "cat", size: "1:1"))

    #expect(result.base64Images == ["gemini-image"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["contents"]?[0]?["parts"]?[0]?["text"]?.stringValue == "cat")
    #expect(body["generationConfig"]?["responseModalities"]?[0]?.stringValue == "IMAGE")
    #expect(body["generationConfig"]?["imageConfig"]?["aspectRatio"]?.stringValue == "1:1")
}
@Test func googleGeminiImageMapsFilesAndGoogleSearchOptionLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"edited-image"}}]},"groundingMetadata":{"webSearchQueries":["cat"]}}]}"#))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.imageModel("gemini-2.5-flash-image")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "Make it cinematic",
        files: [
            ImageInputFile(data: Data([0x89, 0x50, 0x4E, 0x47]), mediaType: "image/*"),
            ImageInputFile(url: "https://example.com/source.png")
        ],
        providerOptions: [
            "google": [
                "googleSearch": ["searchTypes": ["webSearch": [:]]],
                "thinkingConfig": ["includeThoughts": true],
                "safetySettings": [["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_LOW_AND_ABOVE"]],
                "labels": ["scene": "edit"]
            ]
        ]
    ))

    #expect(result.base64Images == ["edited-image"])
    #expect(result.providerMetadata["google"]?["groundingMetadata"]?["webSearchQueries"]?[0]?.stringValue == "cat")
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let parts = try #require(body["contents"]?[0]?["parts"]?.arrayValue)
    #expect(parts[0]["text"]?.stringValue == "Make it cinematic")
    #expect(parts[1]["inlineData"]?["mimeType"]?.stringValue == "image/png")
    #expect(parts[2]["fileData"]?["fileUri"]?.stringValue == "https://example.com/source.png")
    #expect(body["generationConfig"]?["responseModalities"]?[0]?.stringValue == "IMAGE")
    #expect(body["generationConfig"]?["thinkingConfig"]?["includeThoughts"]?.boolValue == true)
    #expect(body["safetySettings"]?[0]?["category"]?.stringValue == "HARM_CATEGORY_DANGEROUS_CONTENT")
    #expect(body["labels"]?["scene"]?.stringValue == "edit")
    #expect(body["tools"]?[0]?["googleSearch"]?["searchTypes"]?["webSearch"] != nil)
    #expect(body["googleSearch"] == nil)
}
@Test func googleModelsForwardAbortSignalToLanguageEmbeddingAndImageRequests() async throws {
    let languageTransport = RecordingTransport(responses: [
        jsonResponse("""
        {"candidates":[{"content":{"parts":[{"text":"gemini"}]},"finishReason":"STOP"}]}
        """),
        sseResponse("""
        data: {"candidates":[{"content":{"parts":[{"text":"gem"}],"role":"model"},"finishReason":"STOP","index":0}]}

        """)
    ])
    let languageProvider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: languageTransport))
    let languageModel = try languageProvider.languageModel("gemini-2.5-flash")
    let languageController = AIAbortController()

    _ = try await languageModel.generate(LanguageModelRequest(messages: [.user("Ping")], abortSignal: languageController.signal))
    for try await _ in languageModel.stream(LanguageModelRequest(messages: [.user("Ping")], abortSignal: languageController.signal)) {}

    let languageRequests = await languageTransport.requests()
    #expect(languageRequests.count == 2)
    #expect(languageRequests[0].abortSignal === languageController.signal)
    #expect(languageRequests[1].abortSignal === languageController.signal)

    let embeddingTransport = RecordingTransport(response: jsonResponse(#"{"embedding":{"values":[0.1,0.2]}}"#))
    let embeddingProvider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: embeddingTransport))
    let embeddingModel = try embeddingProvider.embeddingModel("gemini-embedding-001")
    let embeddingController = AIAbortController()

    _ = try await embeddingModel.embed(EmbeddingRequest(values: ["hello"], abortSignal: embeddingController.signal))

    #expect((await embeddingTransport.requests()).first?.abortSignal === embeddingController.signal)

    let imageTransport = RecordingTransport(response: jsonResponse(#"{"predictions":[{"bytesBase64Encoded":"image"}]}"#))
    let imageProvider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("imagen-4.0-generate-001")
    let imageController = AIAbortController()

    _ = try await imageModel.generateImage(ImageGenerationRequest(prompt: "cat", abortSignal: imageController.signal))

    #expect((await imageTransport.requests()).first?.abortSignal === imageController.signal)
}
@Test func googleVeoCreatesLongRunningOperationAndPollsVideoURL() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"name":"operations/video-1","done":false}"#),
        jsonResponse(#"{"name":"operations/video-1","done":true,"response":{"generateVideoResponse":{"generatedSamples":[{"video":{"uri":"https://generativelanguage.googleapis.com/files/video-123.mp4?alt=media"}}]}}}"#)
    ])
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.videoModel("veo-3.1-generate-preview")

    #expect(model.providerID == "google.generative-ai")
    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        aspectRatio: "16:9",
        durationSeconds: 5,
        count: 2,
        extraBody: ["sampleCount": 1, "resolution": "1920x1080", "seed": 42, "negativePrompt": "rain", "pollIntervalMs": 0]
    ))

    #expect(result.urls == ["https://generativelanguage.googleapis.com/files/video-123.mp4?alt=media&key=gemini-key"])
    #expect(result.operationID == "operations/video-1")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/veo-3.1-generate-preview:predictLongRunning")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["instances"]?[0]?["prompt"]?.stringValue == "cat running")
    #expect(body["parameters"]?["sampleCount"]?.intValue == 2)
    #expect(body["parameters"]?["aspectRatio"]?.stringValue == "16:9")
    #expect(body["parameters"]?["durationSeconds"]?.intValue == 5)
    #expect(body["parameters"]?["resolution"]?.stringValue == "1080p")
    #expect(body["parameters"]?["seed"]?.intValue == 42)
    #expect(body["parameters"]?["negativePrompt"]?.stringValue == "rain")
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/operations/video-1")
}

@Test func googleVeoDoesNotAppendAPIKeyToForeignVideoURI() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"name":"operations/video-foreign","done":true,"response":{"generateVideoResponse":{"generatedSamples":[{"video":{"uri":"https://videos.example.com/video-foreign.mp4?alt=media"}}]}}}"#)
    ])
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.videoModel("veo-3.1-generate-preview")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        extraBody: ["pollIntervalMs": 0]
    ))

    #expect(result.urls == ["https://videos.example.com/video-foreign.mp4?alt=media"])
    #expect(result.providerMetadata["google"]?["videos"]?[0]?["uri"]?.stringValue == "https://videos.example.com/video-foreign.mp4?alt=media")
}
