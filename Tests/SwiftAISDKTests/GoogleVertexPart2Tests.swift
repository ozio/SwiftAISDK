import Foundation
import Testing
@testable import SwiftAISDK

@Test func googleVertexLanguageSharesGenerateContentRichToolMapping() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"toolCall":{"toolType":"vertex_rag_store","id":"rag-1","args":{"query":"swift"}}},{"toolResponse":{"toolType":"vertex_rag_store","response":{"documents":[{"title":"Swift Docs"}]}}}],"role":"model"},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-3-pro")

    let result = try await model.generate(LanguageModelRequest(messages: [
        .user("Search RAG."),
        .assistant(toolCalls: [
            AIToolCall(id: "tool-call-0", name: "lookup", arguments: #"{"query":"swift"}"#)
        ])
    ]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["contents"]?[1]?["parts"]?[0]?["thoughtSignature"]?.stringValue == "skip_thought_signature_validator")
    #expect(result.warnings.contains { $0.type == "other" && ($0.message?.contains("skip_thought_signature_validator") ?? false) })
    #expect(result.finishReason == "tool-calls")
    #expect(result.toolCalls.first?.id == "rag-1")
    #expect(result.toolCalls.first?.name == "server:vertex_rag_store")
    #expect(result.toolCalls.first?.providerExecuted == true)
    #expect(result.toolResults.first?.toolCallID == "rag-1")
    #expect(result.toolResults.first?.result["documents"]?[0]?["title"]?.stringValue == "Swift Docs")
}
@Test func googleVertexAPIKeyUsesExpressModeAndPredictEmbedding() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"predictions":[{"embeddings":{"values":[0.4,0.5],"statistics":{"token_count":2}}}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        apiKey: "vertex-key",
        headers: ["x-goog-api-key": "custom-key"],
        transport: transport
    ))
    let model = try provider.embeddingModel("text-embedding-005")

    #expect(model.providerID == "google.vertex.embedding")
    let result = try await model.embed(EmbeddingRequest(
        values: ["hello"],
        dimensions: 128,
        providerOptions: [
            "googleVertex": .object([
                "taskType": "RETRIEVAL_DOCUMENT",
                "title": "Vertex Doc",
                "autoTruncate": false,
                "outputDimensionality": 256
            ])
        ]
    ))

    #expect(result.embeddings == [[0.4, 0.5]])
    #expect(result.usage?.totalTokens == 2)
    #expect(result.requestMetadata.body?["instances"]?[0]?["content"]?.stringValue == "hello")
    #expect(result.requestMetadata.body?["instances"]?[0]?["task_type"]?.stringValue == "RETRIEVAL_DOCUMENT")
    #expect(result.requestMetadata.body?["instances"]?[0]?["title"]?.stringValue == "Vertex Doc")
    #expect(result.requestMetadata.body?["parameters"]?["outputDimensionality"]?.intValue == 256)
    #expect(result.requestMetadata.body?["parameters"]?["autoTruncate"]?.boolValue == false)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://aiplatform.googleapis.com/v1/publishers/google/models/text-embedding-005:predict")
    #expect(request.headers["x-goog-api-key"] == "vertex-key")
    #expect(request.headers["user-agent"] == "ai-sdk/google-vertex/4.0.148")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["instances"]?[0]?["content"]?.stringValue == "hello")
    #expect(body["instances"]?[0]?["task_type"]?.stringValue == "RETRIEVAL_DOCUMENT")
    #expect(body["parameters"]?["outputDimensionality"]?.intValue == 256)
}

@Test func googleVertexGeminiEmbedding2UsesEmbedContentEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"embedding":{"values":[0.1,0.2,0.3]},"usageMetadata":{"promptTokenCount":5}}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        apiKey: "vertex-key",
        transport: transport
    ))
    let model = try provider.embeddingModel("gemini-embedding-2-preview")

    let result = try await model.embed(EmbeddingRequest(
        values: ["hello"],
        providerOptions: [
            "googleVertex": .object([
                "taskType": "RETRIEVAL_QUERY",
                "title": "Query",
                "autoTruncate": false,
                "outputDimensionality": 128
            ])
        ]
    ))

    #expect(result.embeddings == [[0.1, 0.2, 0.3]])
    #expect(result.usage?.totalTokens == 5)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://aiplatform.googleapis.com/v1/publishers/google/models/gemini-embedding-2-preview:embedContent")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["content"]?["parts"]?[0]?["text"]?.stringValue == "hello")
    #expect(body["embedContentConfig"]?["taskType"]?.stringValue == "RETRIEVAL_QUERY")
    #expect(body["embedContentConfig"]?["title"]?.stringValue == "Query")
    #expect(body["embedContentConfig"]?["autoTruncate"]?.boolValue == false)
    #expect(body["embedContentConfig"]?["outputDimensionality"]?.intValue == 128)

    await #expect(throws: AITooManyEmbeddingValuesForCallError.self) {
        _ = try await model.embed(EmbeddingRequest(values: ["one", "two"]))
    }
}

@Test func googleVertexTranscriptionUsesCloudSpeechRecognizeEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"results":[{"alternatives":[{"transcript":"hello world","words":[{"word":"hello","startOffset":"0.100s","endOffset":"0.400s"},{"word":"world","startOffset":"0.500s","endOffset":"0.900s"}]}],"languageCode":"en-US"}],"metadata":{"totalBilledDuration":"1.200s"}}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "us-central1",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.transcriptionModel("chirp_3")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio bytes".utf8),
        language: "en-US",
        providerOptions: [
            "googleVertex": .object([
                "region": "us",
                "enableAutomaticPunctuation": false,
                "enableWordTimeOffsets": true
            ])
        ]
    ))

    #expect(result.text == "hello world")
    #expect(result.language == "en")
    #expect(result.durationInSeconds == 1.2)
    #expect(result.segments == [
        TranscriptionSegment(text: "hello", startSecond: 0.1, endSecond: 0.4),
        TranscriptionSegment(text: "world", startSecond: 0.5, endSecond: 0.9)
    ])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://us-speech.googleapis.com/v2/projects/test-project/locations/us/recognizers/_:recognize")
    #expect(request.headers["Authorization"] == "Bearer token")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["config"]?["model"]?.stringValue == "chirp_3")
    #expect(body["config"]?["languageCodes"]?[0]?.stringValue == "en-US")
    #expect(body["config"]?["autoDecodingConfig"]?.objectValue?.isEmpty == true)
    #expect(body["config"]?["features"]?["enableAutomaticPunctuation"]?.boolValue == false)
    #expect(body["config"]?["features"]?["enableWordTimeOffsets"]?.boolValue == true)
    #expect(body["content"]?.stringValue == Data("audio bytes".utf8).base64EncodedString())
}

@Test func googleVertexAppendsVersionedUserAgentToCustomHeader() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"predictions":[{"embeddings":{"values":[0.4,0.5]}}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        apiKey: "vertex-key",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: transport
    ))
    let model = try provider.embeddingModel("text-embedding-005")

    _ = try await model.embed(EmbeddingRequest(values: ["hello"]))

    let request = try #require(await transport.requests().first)
    #expect(request.headers["x-goog-api-key"] == "vertex-key")
    #expect(request.headers["user-agent"] == "CustomApp/1.0 ai-sdk/google-vertex/4.0.148")
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

    let videoTransport = RecordingTransport(responses: [
        jsonResponse("""
        {"name":"operations/123","done":false}
        """),
        jsonResponse("""
        {"name":"operations/123","done":true,"response":{"videos":[{"gcsUri":"gs://bucket/video.mp4","mimeType":"video/mp4"},{"bytesBase64Encoded":"base64-video","mimeType":"video/mp4"}]}}
        """, headers: ["poll-header": "value"])
    ])
    let videoProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "vertex-key", baseURL: "https://api.example.com", transport: videoTransport))
    let videoModel = try videoProvider.videoModel("veo-2.0-generate-001")
    #expect(videoModel.providerID == "google.vertex.video")
    let video = try await videoModel.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        aspectRatio: "16:9",
        durationSeconds: 4,
        image: ImageInputFile(data: Data("frame".utf8), mediaType: "image/png"),
        resolution: "1920x1080",
        seed: 42,
        count: 3,
        providerOptions: [
            "googleVertex": .object([
                "negativePrompt": "rain",
                "generateAudio": true,
                "referenceImages": [
                    ["gcsUri": "gs://bucket/ref.png"]
                ],
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1_000
            ])
        ]
    ))
    #expect(video.operationID == "operations/123")
    #expect(video.urls == ["gs://bucket/video.mp4"])
    #expect(video.base64Videos == ["base64-video"])
    #expect(video.providerMetadata["google-vertex"]?["videos"]?[0]?["gcsUri"]?.stringValue == "gs://bucket/video.mp4")
    #expect(video.responseMetadata.headers["poll-header"] == "value")
    let videoRequests = await videoTransport.requests()
    #expect(videoRequests.count == 2)
    let videoRequest = try #require(videoRequests.first)
    #expect(videoRequest.url.absoluteString == "https://api.example.com/models/veo-2.0-generate-001:predictLongRunning")
    let videoBody = try decodeJSONBody(try #require(videoRequest.body))
    #expect(videoBody["instances"]?[0]?["image"]?["bytesBase64Encoded"]?.stringValue == Data("frame".utf8).base64EncodedString())
    #expect(videoBody["instances"]?[0]?["referenceImages"]?[0]?["gcsUri"]?.stringValue == "gs://bucket/ref.png")
    #expect(videoBody["parameters"]?["aspectRatio"]?.stringValue == "16:9")
    #expect(videoBody["parameters"]?["durationSeconds"]?.intValue == 4)
    #expect(videoBody["parameters"]?["resolution"]?.stringValue == "1080p")
    #expect(videoBody["parameters"]?["seed"]?.intValue == 42)
    #expect(videoBody["parameters"]?["sampleCount"]?.intValue == 3)
    #expect(videoBody["parameters"]?["negativePrompt"]?.stringValue == "rain")
    #expect(videoBody["parameters"]?["generateAudio"]?.boolValue == true)
    #expect(videoBody["parameters"]?["pollIntervalMs"] == nil)
    #expect(videoBody["parameters"]?["pollTimeoutMs"] == nil)
    let pollRequest = try #require(videoRequests.last)
    #expect(pollRequest.url.absoluteString == "https://api.example.com/models/veo-2.0-generate-001:fetchPredictOperation")
    let pollBody = try decodeJSONBody(try #require(pollRequest.body))
    #expect(pollBody["operationName"]?.stringValue == "operations/123")
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
    #expect(request.url.absoluteString == "https://us-central1-aiplatform.googleapis.com/v1/projects/test-project/locations/us-central1/endpoints/openapi/chat/completions")
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
