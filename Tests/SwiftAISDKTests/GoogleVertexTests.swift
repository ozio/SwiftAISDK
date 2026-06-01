import Foundation
import Testing
@testable import SwiftAISDK

@Test func googleVertexAnthropicToolsHelpersExposeSupportedSubset() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"vertex anthropic tools"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
    """))
    let provider = try AIProviders.googleVertexAnthropic(
        project: "test-project",
        location: "us-central1",
        settings: ProviderSettings(apiKey: "vertex-token", transport: transport)
    )
    let model = try provider.languageModel("claude-sonnet-4@20250514")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use Vertex Anthropic tools.")],
        tools: [
            "bash": GoogleVertexAnthropicTools.bash_20241022(),
            "search": GoogleVertexAnthropicTools.webSearch_20250305(maxUses: 2),
            "bm25": GoogleVertexAnthropicTools.toolSearchBm25_20251119()
        ]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString.contains("/claude-sonnet-4@20250514:rawPredict"))
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["anthropic_version"]?.stringValue == "vertex-2023-10-16")
    #expect(body["model"] == nil)
    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.contains { $0["type"]?.stringValue == "bash_20241022" && $0["name"]?.stringValue == "bash" })
    #expect(tools.contains { $0["type"]?.stringValue == "web_search_20250305" && $0["max_uses"]?.intValue == 2 })
    #expect(tools.contains { $0["type"]?.stringValue == "tool_search_tool_bm25_20251119" && $0["name"]?.stringValue == "tool_search_tool_bm25" })
}

@Test func googleVertexOAuthBuildsRegionalPublisherURL() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"vertex"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":2,"candidatesTokenCount":1,"totalTokenCount":3}}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "us-central1",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    #expect(model.providerID == "google.vertex.chat")
    let result = try await model.generate(LanguageModelRequest(messages: [.system("Brief"), .user("Hi")], maxOutputTokens: 32))

    #expect(result.text == "vertex")
    #expect(result.usage?.totalTokens == 3)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://us-central1-aiplatform.googleapis.com/v1beta1/projects/test-project/locations/us-central1/publishers/google/models/gemini-2.5-pro:generateContent")
    #expect(request.headers["Authorization"] == "Bearer token")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["systemInstruction"]?["parts"]?[0]?["text"]?.stringValue == "Brief")
    #expect(body["contents"]?[0]?["parts"]?[0]?["text"]?.stringValue == "Hi")
}

@Test func googleVertexLanguageExtractsGroundingSources() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"vertex grounded"}]},"finishReason":"STOP","groundingMetadata":{"groundingChunks":[{"retrievedContext":{"uri":"https://external-rag-source.com/page","title":"External RAG Source"}},{"retrievedContext":{"uri":"gs://bucket/notes.md"}}]}}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Ground it.")]))

    #expect(result.text == "vertex grounded")
    #expect(result.sources.count == 2)
    #expect(result.sources[0].sourceType == "url")
    #expect(result.sources[0].url == "https://external-rag-source.com/page")
    #expect(result.sources[0].title == "External RAG Source")
    #expect(result.sources[1].sourceType == "document")
    #expect(result.sources[1].title == "Unknown Document")
    #expect(result.sources[1].mediaType == "text/markdown")
    #expect(result.sources[1].filename == "notes.md")
}

@Test func googleVertexLanguageMapsStandardStructuredResponseFormat() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"{\\"answer\\":\\"vertex\\"}"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Answer.")],
        responseFormat: .json(schema: [
            "type": "object",
            "properties": [
                "answer": ["type": "string"],
                "count": ["type": "integer"]
            ],
            "required": ["answer"],
            "additionalProperties": false
        ])
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["generationConfig"]?["responseMimeType"]?.stringValue == "application/json")
    #expect(body["generationConfig"]?["responseSchema"]?["type"]?.stringValue == "object")
    #expect(body["generationConfig"]?["responseSchema"]?["properties"]?["answer"]?["type"]?.stringValue == "string")
    #expect(body["generationConfig"]?["responseSchema"]?["properties"]?["count"]?["type"]?.stringValue == "integer")
    #expect(body["generationConfig"]?["responseSchema"]?["required"]?[0]?.stringValue == "answer")
    #expect(body["generationConfig"]?["responseSchema"]?["additionalProperties"] == nil)
    #expect(body["responseFormat"] == nil)
}

@Test func googleVertexLanguageMapsFunctionToolsAndToolChoice() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"vertex tools"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Use lookup.")],
        tools: [
            "lookup": [
                "type": "object",
                "properties": ["query": ["type": "string"]],
                "required": ["query"]
            ]
        ],
        extraBody: ["toolChoice": "required"]
    ))

    #expect(result.text == "vertex tools")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["tools"]?[0]?["functionDeclarations"]?[0]?["name"]?.stringValue == "lookup")
    #expect(body["toolConfig"]?["functionCallingConfig"]?["mode"]?.stringValue == "ANY")
    #expect(body["toolChoice"] == nil)
}

@Test func googleVertexToolsHelpersMirrorProviderExecutedToolFactories() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"vertex grounded"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use Vertex tools.")],
        tools: [
            "google.google_search": GoogleVertexTools.googleSearch(),
            "google.vertex_rag_store": GoogleVertexTools.vertexRagStore(
                ragCorpus: "projects/test-project/locations/us-central1/ragCorpora/rag-1",
                topK: 3
            )
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.contains { $0["googleSearch"]?.objectValue?.isEmpty == true })
    let retrieval = try #require(tools.first { $0["retrieval"] != nil })
    #expect(retrieval["retrieval"]?["vertex_rag_store"]?["rag_resources"]?["rag_corpus"]?.stringValue == "projects/test-project/locations/us-central1/ragCorpora/rag-1")
    #expect(retrieval["retrieval"]?["vertex_rag_store"]?["similarity_top_k"]?.intValue == 3)
}

@Test func googleVertexLanguageStreamsGenerateContentEvents() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"candidates":[{"content":{"parts":[{"text":"ver"}],"role":"model"},"index":0}]}

    data: {"candidates":[{"content":{"parts":[{"text":"tex"}],"role":"model"},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":2,"candidatesTokenCount":2,"totalTokenCount":4}}

    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    var deltas: [String] = []
    var usage: TokenUsage?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textDelta(delta):
            deltas.append(delta)
        case let .finish(_, value):
            usage = value
        default:
            break
        }
    }

    #expect(deltas == ["ver", "tex"])
    #expect(usage?.totalTokens == 4)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://aiplatform.googleapis.com/v1beta1/projects/test-project/locations/global/publishers/google/models/gemini-2.5-pro:streamGenerateContent?alt=sse")
    #expect(request.headers["Authorization"] == "Bearer token")
}

@Test func googleVertexLanguageParsesAndStreamsFunctionCalls() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"functionCall":{"name":"weather","args":{"location":"Boston"}}}],"role":"model"},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":20,"candidatesTokenCount":8,"totalTokenCount":28}}
    """))
    let generateProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: generateTransport
    ))
    let generateModel = try generateProvider.languageModel("gemini-2.5-pro")

    let result = try await generateModel.generate(LanguageModelRequest(messages: [.user("Weather?")]))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.toolCalls.first?.name == "weather")
    #expect(try decodeJSONBody(Data((try #require(result.toolCalls.first)).arguments.utf8))["location"]?.stringValue == "Boston")

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"weather","args":{"location":"Boston"}}}]},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":20,"candidatesTokenCount":8,"totalTokenCount":28}}

    """))
    let streamProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: streamTransport
    ))
    let streamModel = try streamProvider.languageModel("gemini-2.5-pro")

    var finalCall: AIToolCall?
    var finishReason: String?
    for try await part in streamModel.stream(LanguageModelRequest(messages: [.user("Weather?")])) {
        switch part {
        case let .toolCall(call):
            finalCall = call
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(finalCall?.name == "weather")
    #expect(try decodeJSONBody(Data((try #require(finalCall)).arguments.utf8))["location"]?.stringValue == "Boston")
    #expect(finishReason == "tool-calls")
}

@Test func googleVertexAPIKeyUsesExpressModeAndPredictEmbedding() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"predictions":[{"embeddings":{"values":[0.4,0.5],"statistics":{"token_count":2}}}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "vertex-key", transport: transport))
    let model = try provider.embeddingModel("text-embedding-005")

    #expect(model.providerID == "google.vertex.embedding")
    let result = try await model.embed(EmbeddingRequest(values: ["hello"], dimensions: 128))

    #expect(result.embeddings == [[0.4, 0.5]])
    #expect(result.requestMetadata.body?["instances"]?[0]?["content"]?.stringValue == "hello")
    #expect(result.requestMetadata.body?["parameters"]?["outputDimensionality"]?.intValue == 128)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://aiplatform.googleapis.com/v1/publishers/google/models/text-embedding-005:predict")
    #expect(request.headers["x-goog-api-key"] == "vertex-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["instances"]?[0]?["content"]?.stringValue == "hello")
    #expect(body["parameters"]?["outputDimensionality"]?.intValue == 128)
}

@Test func googleVertexImageAndVideoUsePredictEndpoints() async throws {
    let imageTransport = RecordingTransport(response: jsonResponse("""
    {"predictions":[{"bytesBase64Encoded":"abc"}]}
    """))
    let imageProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "vertex-key", baseURL: "https://api.example.com", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("imagen-3.0-generate-002")
    #expect(imageModel.providerID == "google.vertex.image")
    let image = try await imageModel.generateImage(ImageGenerationRequest(prompt: "cat", count: 2))
    #expect(image.base64Images == ["abc"])
    let imageRequest = try #require(await imageTransport.requests().first)
    #expect(imageRequest.url.absoluteString == "https://api.example.com/models/imagen-3.0-generate-002:predict")
    let imageBody = try decodeJSONBody(try #require(imageRequest.body))
    #expect(imageBody["instances"]?[0]?["prompt"]?.stringValue == "cat")
    #expect(imageBody["parameters"]?["sampleCount"]?.intValue == 2)

    let videoTransport = RecordingTransport(response: jsonResponse("""
    {"name":"operations/123"}
    """))
    let videoProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "vertex-key", baseURL: "https://api.example.com", transport: videoTransport))
    let videoModel = try videoProvider.videoModel("veo-2.0-generate-001")
    #expect(videoModel.providerID == "google.vertex.video")
    let video = try await videoModel.generateVideo(VideoGenerationRequest(prompt: "cat running", aspectRatio: "16:9", durationSeconds: 4))
    #expect(video.operationID == "operations/123")
    let videoRequest = try #require(await videoTransport.requests().first)
    #expect(videoRequest.url.absoluteString == "https://api.example.com/models/veo-2.0-generate-001:predictLongRunning")
    let videoBody = try decodeJSONBody(try #require(videoRequest.body))
    #expect(videoBody["parameters"]?["aspectRatio"]?.stringValue == "16:9")
    #expect(videoBody["parameters"]?["durationSeconds"]?.intValue == 4)
}

@Test func googleVertexImagenEditUsesReferenceImagesAndMaskOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"predictions":[{"bytesBase64Encoded":"edited-image","mimeType":"image/png"}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "vertex-key", baseURL: "https://api.example.com", transport: transport))
    let model = try provider.imageModel("imagen-3.0-generate-002")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "Remove the object",
        count: 1,
        files: [ImageInputFile(data: Data("source".utf8), mediaType: "image/png")],
        mask: ImageInputFile(data: Data("mask".utf8), mediaType: "image/png"),
        extraBody: [
            "googleVertex": [
                "negativePrompt": "blur",
                "edit": [
                    "mode": "EDIT_MODE_INPAINT_REMOVAL",
                    "baseSteps": 50,
                    "maskMode": "MASK_MODE_USER_PROVIDED",
                    "maskDilation": 0.01
                ]
            ]
        ]
    ))

    #expect(result.base64Images == ["edited-image"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.example.com/models/imagen-3.0-generate-002:predict")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["instances"]?[0]?["prompt"]?.stringValue == "Remove the object")
    #expect(body["instances"]?[0]?["referenceImages"]?[0]?["referenceType"]?.stringValue == "REFERENCE_TYPE_RAW")
    #expect(body["instances"]?[0]?["referenceImages"]?[0]?["referenceId"]?.intValue == 1)
    #expect(body["instances"]?[0]?["referenceImages"]?[0]?["referenceImage"]?["bytesBase64Encoded"]?.stringValue == Data("source".utf8).base64EncodedString())
    #expect(body["instances"]?[0]?["referenceImages"]?[1]?["referenceType"]?.stringValue == "REFERENCE_TYPE_MASK")
    #expect(body["instances"]?[0]?["referenceImages"]?[1]?["referenceId"]?.intValue == 2)
    #expect(body["instances"]?[0]?["referenceImages"]?[1]?["referenceImage"]?["bytesBase64Encoded"]?.stringValue == Data("mask".utf8).base64EncodedString())
    #expect(body["instances"]?[0]?["referenceImages"]?[1]?["maskImageConfig"]?["maskMode"]?.stringValue == "MASK_MODE_USER_PROVIDED")
    #expect(body["instances"]?[0]?["referenceImages"]?[1]?["maskImageConfig"]?["dilation"]?.doubleValue == 0.01)
    #expect(body["parameters"]?["sampleCount"]?.intValue == 1)
    #expect(body["parameters"]?["negativePrompt"]?.stringValue == "blur")
    #expect(body["parameters"]?["editMode"]?.stringValue == "EDIT_MODE_INPAINT_REMOVAL")
    #expect(body["parameters"]?["editConfig"]?["baseSteps"]?.intValue == 50)
    #expect(body["parameters"]?["edit"] == nil)
    #expect(body["parameters"]?["googleVertex"] == nil)
}

@Test func googleVertexImagenEditRejectsURLFilesLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"predictions":[]}"#))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "vertex-key", baseURL: "https://api.example.com", transport: transport))
    let model = try provider.imageModel("imagen-3.0-generate-002")

    await #expect(throws: AIError.invalidArgument(argument: "files", message: "URL-based images are not supported for Google Vertex image editing. Provide image data directly.")) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "Edit this image",
            files: [ImageInputFile(url: "https://example.com/source.png")]
        ))
    }
    #expect(await transport.requests().isEmpty)
}

@Test func googleVertexMaaSUsesOpenAICompatibleEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"maas"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}
    """))
    let provider = try AIProviders.googleVertexMaaS(project: "test-project", location: "us-central1", settings: ProviderSettings(apiKey: "vertex-token", transport: transport))
    let model = try provider.languageModel("meta/llama-3.1-405b-instruct-maas")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "maas")
    #expect(result.usage?.totalTokens == 3)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://aiplatform.googleapis.com/v1/projects/test-project/locations/us-central1/endpoints/openapi/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer vertex-token")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "meta/llama-3.1-405b-instruct-maas")
    #expect(body["messages"]?[0]?["content"]?.stringValue == "Hi")
}

@Test func googleVertexXAIStripsReasoningEffort() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"grok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":663,"completion_tokens":50,"completion_tokens_details":{"reasoning_tokens":124}}}
    """))
    let provider = try AIProviders.googleVertexXAI(project: "test-project", settings: ProviderSettings(apiKey: "vertex-token", transport: transport))
    let model = try provider.languageModel("xai/grok-4.1-fast-reasoning")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], extraBody: ["reasoning_effort": "high"]))

    #expect(result.text == "grok")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://aiplatform.googleapis.com/v1/projects/test-project/locations/global/endpoints/openapi/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer vertex-token")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "xai/grok-4.1-fast-reasoning")
    #expect(body["reasoning_effort"] == nil)
}

@Test func googleVertexAnthropicUsesRawPredictShape() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"vertex claude"}],"stop_reason":"end_turn","usage":{"input_tokens":2,"output_tokens":3}}
    """))
    let provider = try AIProviders.googleVertexAnthropic(project: "test-project", location: "us-east5", settings: ProviderSettings(apiKey: "vertex-token", transport: transport))
    let model = try provider.languageModel("claude-3-5-sonnet-v2@20241022")

    let result = try await model.generate(LanguageModelRequest(messages: [.system("Brief"), .user("Hi")], maxOutputTokens: 32))

    #expect(result.text == "vertex claude")
    #expect(result.usage?.inputTokens == 2)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://us-east5-aiplatform.googleapis.com/v1/projects/test-project/locations/us-east5/publishers/anthropic/models/claude-3-5-sonnet-v2@20241022:rawPredict")
    #expect(request.headers["Authorization"] == "Bearer vertex-token")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"] == nil)
    #expect(body["anthropic_version"]?.stringValue == "vertex-2023-10-16")
    #expect(body["system"]?.stringValue == "Brief")
    #expect(body["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
}
