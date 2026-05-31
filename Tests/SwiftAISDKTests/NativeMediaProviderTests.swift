import Foundation
import Testing
@testable import SwiftAISDK

@Test func togetherAIImageAndRerankingUseNativeEndpoints() async throws {
    let imageTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"base64-image"}]}"#))
    let imageProvider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("black-forest-labs/FLUX.1-schnell-Free")

    let image = try await imageModel.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "1024x768",
        count: 2,
        files: [ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png")],
        extraBody: [
            "steps": 4,
            "guidance": 3.5,
            "negativePrompt": "low quality",
            "disableSafetyChecker": true
        ]
    ))

    #expect(image.base64Images == ["base64-image"])
    let imageRequest = try #require(await imageTransport.requests().first)
    #expect(imageRequest.url.absoluteString == "https://api.together.xyz/v1/images/generations")
    #expect(imageRequest.headers["Authorization"] == "Bearer together-key")
    let imageBody = try decodeJSONBody(try #require(imageRequest.body))
    #expect(imageBody["model"]?.stringValue == "black-forest-labs/FLUX.1-schnell-Free")
    #expect(imageBody["prompt"]?.stringValue == "cat")
    #expect(imageBody["width"]?.intValue == 1024)
    #expect(imageBody["height"]?.intValue == 768)
    #expect(imageBody["n"]?.intValue == 2)
    #expect(imageBody["response_format"]?.stringValue == "base64")
    #expect(imageBody["steps"]?.intValue == 4)
    #expect(imageBody["guidance"]?.doubleValue == 3.5)
    #expect(imageBody["negative_prompt"]?.stringValue == "low quality")
    #expect(imageBody["disable_safety_checker"]?.boolValue == true)
    #expect(imageBody["image_url"]?.stringValue?.hasPrefix("data:image/png;base64,") == true)

    let rerankTransport = RecordingTransport(response: jsonResponse(#"{"id":"rank-1","model":"Salesforce/Llama-Rank-v1","results":[{"index":1,"relevance_score":0.8},{"index":0,"relevance_score":0.2}]}"#))
    let rerankProvider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: rerankTransport))
    let rerankModel = try rerankProvider.rerankingModel("Salesforce/Llama-Rank-v1")

    let reranking = try await rerankModel.rerank(RerankingRequest(query: "q", documents: ["a", "b"], topK: 1, extraBody: ["rankFields": ["title", "text"]]))

    #expect(reranking.results.map(\.index) == [1, 0])
    let rerankRequest = try #require(await rerankTransport.requests().first)
    #expect(rerankRequest.url.absoluteString == "https://api.together.xyz/v1/rerank")
    let rerankBody = try decodeJSONBody(try #require(rerankRequest.body))
    #expect(rerankBody["top_n"]?.intValue == 1)
    #expect(rerankBody["return_documents"]?.boolValue == false)
    #expect(rerankBody["rank_fields"]?[0]?.stringValue == "title")
}

@Test func togetherAIMapsNestedProviderOptions() async throws {
    let imageTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"nested-image"}]}"#))
    let imageProvider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("black-forest-labs/FLUX.1-schnell-Free")

    _ = try await imageModel.generateImage(ImageGenerationRequest(
        prompt: "cat",
        files: [ImageInputFile(url: "https://example.com/input.png")],
        extraBody: [
            "togetherai": .object([
                "steps": 3,
                "guidance": 2.5,
                "negative_prompt": "blur",
                "disable_safety_checker": true,
                "custom": "value"
            ])
        ]
    ))

    let imageBody = try decodeJSONBody(try #require((await imageTransport.requests()).first?.body))
    #expect(imageBody["steps"]?.intValue == 3)
    #expect(imageBody["guidance"]?.doubleValue == 2.5)
    #expect(imageBody["negative_prompt"]?.stringValue == "blur")
    #expect(imageBody["disable_safety_checker"]?.boolValue == true)
    #expect(imageBody["custom"]?.stringValue == "value")
    #expect(imageBody["image_url"]?.stringValue == "https://example.com/input.png")
    #expect(imageBody["togetherai"] == nil)

    let rerankTransport = RecordingTransport(response: jsonResponse(#"{"results":[{"index":0,"relevance_score":0.9}]}"#))
    let rerankProvider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: rerankTransport))
    let rerankModel = try rerankProvider.rerankingModel("Salesforce/Llama-Rank-v1")

    _ = try await rerankModel.rerank(RerankingRequest(
        query: "q",
        documents: ["a"],
        topK: 1,
        extraBody: ["togetherai": .object(["rankFields": ["title"]])]
    ))

    let rerankBody = try decodeJSONBody(try #require((await rerankTransport.requests()).first?.body))
    #expect(rerankBody["rank_fields"]?[0]?.stringValue == "title")
    #expect(rerankBody["togetherai"] == nil)
}

@Test func xAIImageAndVideoUseNativeEndpoints() async throws {
    let imageTransport = RecordingTransport(responses: [
        jsonResponse(#"{"data":[{"url":"https://x.ai/image.png","revised_prompt":"cat!"}],"usage":{"cost_in_usd_ticks":123}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("xai-png".utf8))
    ])
    let imageProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("grok-2-image")

    let image = try await imageModel.generateImage(ImageGenerationRequest(prompt: "cat", size: "16:9", count: 2, extraBody: ["quality": "high", "output_format": "png"]))

    #expect(image.urls == ["https://x.ai/image.png"])
    #expect(image.base64Images == [Data("xai-png".utf8).base64EncodedString()])
    let imageRequests = await imageTransport.requests()
    #expect(imageRequests.count == 2)
    let imageRequest = try #require(imageRequests.first)
    #expect(imageRequest.url.absoluteString == "https://api.x.ai/v1/images/generations")
    #expect(imageRequest.headers["Authorization"] == "Bearer xai-key")
    let imageBody = try decodeJSONBody(try #require(imageRequest.body))
    #expect(imageBody["model"]?.stringValue == "grok-2-image")
    #expect(imageBody["prompt"]?.stringValue == "cat")
    #expect(imageBody["n"]?.intValue == 2)
    #expect(imageBody["aspect_ratio"]?.stringValue == "16:9")
    #expect(imageBody["response_format"]?.stringValue == "b64_json")
    #expect(imageBody["quality"]?.stringValue == "high")
    #expect(imageBody["output_format"]?.stringValue == "png")
    #expect(imageRequests[1].method == "GET")
    #expect(imageRequests[1].headers["Authorization"] == nil)

    let videoTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"vid-1"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/video.mp4","duration":6,"respect_moderation":true},"progress":100}"#)
    ])
    let videoProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: videoTransport))
    let videoModel = try videoProvider.videoModel("grok-2-video")

    let video = try await videoModel.generateVideo(VideoGenerationRequest(prompt: "cat running", aspectRatio: "16:9", durationSeconds: 6, extraBody: ["resolution": "720p", "pollIntervalMs": 1]))

    #expect(video.urls == ["https://x.ai/video.mp4"])
    #expect(video.operationID == "vid-1")
    let requests = await videoTransport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].url.absoluteString == "https://api.x.ai/v1/videos/generations")
    let videoBody = try decodeJSONBody(try #require(requests[0].body))
    #expect(videoBody["model"]?.stringValue == "grok-2-video")
    #expect(videoBody["prompt"]?.stringValue == "cat running")
    #expect(videoBody["duration"]?.intValue == 6)
    #expect(videoBody["aspect_ratio"]?.stringValue == "16:9")
    #expect(videoBody["resolution"]?.stringValue == "720p")
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api.x.ai/v1/videos/vid-1")

    let editTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"edit-1"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/edit.mp4","respect_moderation":true}}"#)
    ])
    let editProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: editTransport))
    let editModel = try editProvider.videoModel("grok-2-video")

    let edit = try await editModel.generateVideo(VideoGenerationRequest(
        prompt: "make it brighter",
        aspectRatio: "16:9",
        durationSeconds: 6,
        extraBody: ["videoUrl": "https://x.ai/source.mp4", "pollIntervalMs": 1]
    ))

    #expect(edit.urls == ["https://x.ai/edit.mp4"])
    let editRequests = await editTransport.requests()
    #expect(editRequests[0].url.absoluteString == "https://api.x.ai/v1/videos/edits")
    let editBody = try decodeJSONBody(try #require(editRequests[0].body))
    #expect(editBody["video"]?["url"]?.stringValue == "https://x.ai/source.mp4")
    #expect(editBody["aspect_ratio"] == nil)
    #expect(editBody["duration"] == nil)
}

@Test func xAIMapsNestedImageEditAndVideoOptions() async throws {
    let imageTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"edited-image"}]}"#))
    let imageProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("grok-2-image")

    let image = try await imageModel.generateImage(ImageGenerationRequest(
        prompt: "restyle",
        files: [
            ImageInputFile(url: "https://example.com/input.png"),
            ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png")
        ],
        extraBody: [
            "xai": .object([
                "aspect_ratio": "1:1",
                "output_format": "png",
                "sync_mode": true,
                "resolution": "2k",
                "quality": "high",
                "user": "user-1"
            ])
        ]
    ))

    #expect(image.base64Images == ["edited-image"])
    let imageRequest = try #require(await imageTransport.requests().first)
    #expect(imageRequest.url.absoluteString == "https://api.x.ai/v1/images/edits")
    let imageBody = try decodeJSONBody(try #require(imageRequest.body))
    #expect(imageBody["model"]?.stringValue == "grok-2-image")
    #expect(imageBody["aspect_ratio"]?.stringValue == "1:1")
    #expect(imageBody["output_format"]?.stringValue == "png")
    #expect(imageBody["sync_mode"]?.boolValue == true)
    #expect(imageBody["resolution"]?.stringValue == "2k")
    #expect(imageBody["quality"]?.stringValue == "high")
    #expect(imageBody["user"]?.stringValue == "user-1")
    #expect(imageBody["images"]?[0]?["url"]?.stringValue == "https://example.com/input.png")
    #expect(imageBody["images"]?[0]?["type"]?.stringValue == "image_url")
    #expect(imageBody["images"]?[1]?["url"]?.stringValue == "data:image/png;base64,\(Data([1, 2, 3]).base64EncodedString())")
    #expect(imageBody["xai"] == nil)

    let videoTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"r2v-1"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/r2v.mp4","respect_moderation":true}}"#)
    ])
    let videoProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: videoTransport))
    let videoModel = try videoProvider.videoModel("grok-2-video")

    _ = try await videoModel.generateVideo(VideoGenerationRequest(
        prompt: "reference scene",
        aspectRatio: "16:9",
        extraBody: [
            "xai": .object([
                "mode": "reference-to-video",
                "referenceImageUrls": ["https://example.com/ref-1.png", "https://example.com/ref-2.png"],
                "resolution": "720p",
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ]
    ))

    let videoRequests = await videoTransport.requests()
    #expect(videoRequests[0].url.absoluteString == "https://api.x.ai/v1/videos/generations")
    let videoBody = try decodeJSONBody(try #require(videoRequests[0].body))
    #expect(videoBody["reference_images"]?[0]?["url"]?.stringValue == "https://example.com/ref-1.png")
    #expect(videoBody["reference_images"]?[1]?["url"]?.stringValue == "https://example.com/ref-2.png")
    #expect(videoBody["resolution"]?.stringValue == "720p")
    #expect(videoBody["xai"] == nil)
    #expect(videoBody["pollIntervalMs"] == nil)
}

@Test func deepInfraImageUsesInferenceEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"images":["data:image/png;base64,deepinfra-image"]}"#))
    let provider = try AIProviders.deepInfra(settings: ProviderSettings(apiKey: "deepinfra-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/FLUX-1-schnell")

    let result = try await model.generateImage(ImageGenerationRequest(prompt: "cat", size: "1024x768", count: 1, extraBody: ["seed": 42]))

    #expect(result.base64Images == ["deepinfra-image"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepinfra.com/v1/inference/black-forest-labs/FLUX-1-schnell")
    #expect(request.headers["Authorization"] == "Bearer deepinfra-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?.stringValue == "cat")
    #expect(body["num_images"]?.intValue == 1)
    #expect(body["width"]?.stringValue == "1024")
    #expect(body["height"]?.stringValue == "768")
    #expect(body["seed"]?.intValue == 42)
}

@Test func deepInfraImageMapsNestedProviderOptions() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse(#"{"images":["data:image/png;base64,nested-image"]}"#))
    let generateProvider = try AIProviders.deepInfra(settings: ProviderSettings(apiKey: "deepinfra-key", transport: generateTransport))
    let generateModel = try generateProvider.imageModel("black-forest-labs/FLUX-1-schnell")

    _ = try await generateModel.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "16:9",
        count: 1,
        extraBody: [
            "deepinfra": .object([
                "seed": 42,
                "additional_param": "value"
            ])
        ]
    ))

    let generateBody = try decodeJSONBody(try #require((await generateTransport.requests()).first?.body))
    #expect(generateBody["prompt"]?.stringValue == "cat")
    #expect(generateBody["aspect_ratio"]?.stringValue == "16:9")
    #expect(generateBody["seed"]?.intValue == 42)
    #expect(generateBody["additional_param"]?.stringValue == "value")
    #expect(generateBody["deepinfra"] == nil)

    let editTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"edited-image"}]}"#))
    let editProvider = try AIProviders.deepInfra(settings: ProviderSettings(apiKey: "deepinfra-key", transport: editTransport))
    let editModel = try editProvider.imageModel("black-forest-labs/FLUX.1-Kontext-dev")

    _ = try await editModel.generateImage(ImageGenerationRequest(
        prompt: "edit",
        files: [ImageInputFile(data: Data("png".utf8), mediaType: "image/png", fileName: "input.png")],
        extraBody: [
            "deepinfra": .object([
                "guidance_scale": 2.5,
                "tags": ["a", "b"]
            ])
        ]
    ))

    let editRequest = try #require(await editTransport.requests().first)
    let bodyText = String(data: try #require(editRequest.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains(#"name="guidance_scale""#))
    #expect(bodyText.contains("2.5"))
    #expect(bodyText.contains(#"name="tags""#))
    #expect(bodyText.contains("\r\na\r\n"))
    #expect(bodyText.contains("\r\nb\r\n"))
    #expect(!bodyText.contains(#"name="deepinfra""#))
}

@Test func deepInfraImageEditUsesOpenAICompatibleMultipartEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"edited-image"}]}"#))
    let provider = try AIProviders.deepInfra(settings: ProviderSettings(apiKey: "deepinfra-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/FLUX.1-Kontext-dev")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "turn the cat into a dog",
        size: "1024x1024",
        count: 1,
        files: [ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png", fileName: "input.png")],
        mask: ImageInputFile(data: Data([255, 255, 255, 0]), mediaType: "image/png", fileName: "mask.png"),
        extraBody: ["guidance": 7.5]
    ))

    #expect(result.base64Images == ["edited-image"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepinfra.com/v1/openai/images/edits")
    #expect(request.headers["Authorization"] == "Bearer deepinfra-key")
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=SwiftAISDK-") == true)
    let body = try #require(request.body)
    #expect(body.range(of: Data(#"name="model""#.utf8)) != nil)
    #expect(body.range(of: Data("black-forest-labs/FLUX.1-Kontext-dev".utf8)) != nil)
    #expect(body.range(of: Data(#"name="prompt""#.utf8)) != nil)
    #expect(body.range(of: Data("turn the cat into a dog".utf8)) != nil)
    #expect(body.range(of: Data(#"name="image"; filename="input.png""#.utf8)) != nil)
    #expect(body.range(of: Data(#"name="mask"; filename="mask.png""#.utf8)) != nil)
    #expect(body.range(of: Data(#"name="size""#.utf8)) != nil)
    #expect(body.range(of: Data("1024x1024".utf8)) != nil)
    #expect(body.range(of: Data(#"name="guidance""#.utf8)) != nil)
    #expect(body.range(of: Data("7.5".utf8)) != nil)
}

@Test func fireworksLanguageTransformsThinkingOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"fw"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """))
    let provider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: transport))
    let model = try provider.languageModel("accounts/fireworks/models/kimi-k2-thinking")

    #expect(model.providerID == "fireworks.chat")
    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: [
            "thinking": .object(["type": "enabled", "budgetTokens": 2048]),
            "reasoningHistory": "interleaved",
            "reasoning_effort": "xhigh"
        ]
    ))

    #expect(result.text == "fw")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.fireworks.ai/inference/v1/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer fireworks-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["thinking"]?["type"]?.stringValue == "enabled")
    #expect(body["thinking"]?["budget_tokens"]?.intValue == 2048)
    #expect(body["thinking"]?["budgetTokens"] == nil)
    #expect(body["reasoning_history"]?.stringValue == "interleaved")
    #expect(body["reasoningHistory"] == nil)
    #expect(body["reasoning_effort"]?.stringValue == "high")
}

@Test func openAICompatibleNativeProviderSurfaceIDsMirrorUpstream() throws {
    let settings = ProviderSettings(apiKey: "key", baseURL: "https://api.example.com", transport: RecordingTransport(response: jsonResponse("{}")))

    let baseten = try AIProviders.baseten(settings: settings)
    #expect(try baseten.languageModel("chat").providerID == "baseten.chat")
    #expect(try baseten.chatModel("chat").providerID == "baseten.chat")

    let deepInfra = try AIProviders.deepInfra(settings: settings)
    #expect(try deepInfra.languageModel("chat").providerID == "deepinfra.chat")
    #expect(try deepInfra.chatModel("chat").providerID == "deepinfra.chat")
    #expect(try deepInfra.completionModel("completion").providerID == "deepinfra.completion")
    #expect(try deepInfra.embeddingModel("embedding").providerID == "deepinfra.embedding")
    #expect(try deepInfra.imageModel("image").providerID == "deepinfra.image")

    let fireworks = try AIProviders.fireworks(settings: settings)
    #expect(try fireworks.languageModel("chat").providerID == "fireworks.chat")
    #expect(try fireworks.chatModel("chat").providerID == "fireworks.chat")
    #expect(try fireworks.completionModel("completion").providerID == "fireworks.completion")
    #expect(try fireworks.embeddingModel("embedding").providerID == "fireworks.embedding")
    #expect(try fireworks.imageModel("image").providerID == "fireworks.image")

    let moonshot = try AIProviders.moonshotAI(settings: settings)
    #expect(try moonshot.languageModel("kimi-k2").providerID == "moonshotai.chat")
    #expect(try moonshot.chatModel("kimi-k2").providerID == "moonshotai.chat")

    let together = try AIProviders.togetherAI(settings: settings)
    #expect(try together.languageModel("chat").providerID == "togetherai.chat")
    #expect(try together.chatModel("chat").providerID == "togetherai.chat")
    #expect(try together.completionModel("completion").providerID == "togetherai.completion")
    #expect(try together.embeddingModel("embedding").providerID == "togetherai.embedding")
    #expect(try together.imageModel("image").providerID == "togetherai.image")
    #expect(try together.rerankingModel("rerank").providerID == "togetherai.reranking")
}

@Test func fireworksImageUsesWorkflowBinaryEndpoint() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8)))
    let provider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: transport))
    let model = try provider.imageModel("accounts/fireworks/models/flux-1-schnell-fp8")

    let result = try await model.generateImage(ImageGenerationRequest(prompt: "cat", size: "16:9", count: 1, extraBody: ["seed": 42]))

    #expect(result.base64Images == [Data("png".utf8).base64EncodedString()])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.fireworks.ai/inference/v1/workflows/accounts/fireworks/models/flux-1-schnell-fp8/text_to_image")
    #expect(request.headers["Authorization"] == "Bearer fireworks-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?.stringValue == "cat")
    #expect(body["samples"]?.intValue == 1)
    #expect(body["aspect_ratio"]?.stringValue == "16:9")
    #expect(body["seed"]?.intValue == 42)
}

@Test func fireworksAsyncImagePollsAndDownloadsResult() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"fw-1"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://assets.example.com/fireworks.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("async-png".utf8))
    ])
    let provider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: transport))
    let model = try provider.imageModel("accounts/fireworks/models/flux-kontext-pro")

    let result = try await model.generateImage(ImageGenerationRequest(prompt: "cat", size: "1024x768", count: 2))

    #expect(result.urls == ["https://assets.example.com/fireworks.png"])
    #expect(result.base64Images == [Data("async-png".utf8).base64EncodedString()])
    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].url.absoluteString == "https://api.fireworks.ai/inference/v1/workflows/accounts/fireworks/models/flux-kontext-pro")
    let submitBody = try decodeJSONBody(try #require(requests[0].body))
    #expect(submitBody["prompt"]?.stringValue == "cat")
    #expect(submitBody["samples"]?.intValue == 2)
    #expect(submitBody["width"]?.stringValue == "1024")
    #expect(submitBody["height"]?.stringValue == "768")
    #expect(requests[1].url.absoluteString == "https://api.fireworks.ai/inference/v1/workflows/accounts/fireworks/models/flux-kontext-pro/get_result")
    let pollBody = try decodeJSONBody(try #require(requests[1].body))
    #expect(pollBody["id"]?.stringValue == "fw-1")
    #expect(requests[2].method == "GET")
    #expect(requests[2].url.absoluteString == "https://assets.example.com/fireworks.png")
}

@Test func fireworksImageMapsNestedOptionsAndInputImage() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"fw-edit"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://assets.example.com/fireworks-edit.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("edit-png".utf8))
    ])
    let provider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: transport))
    let model = try provider.imageModel("accounts/fireworks/models/flux-kontext-pro")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "restyle",
        files: [ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png")],
        extraBody: [
            "fireworks": .object([
                "seed": 99,
                "strength": 0.7
            ])
        ]
    ))

    let submitBody = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(submitBody["prompt"]?.stringValue == "restyle")
    #expect(submitBody["input_image"]?.stringValue == "data:image/png;base64,\(Data([1, 2, 3]).base64EncodedString())")
    #expect(submitBody["seed"]?.intValue == 99)
    #expect(submitBody["strength"]?.doubleValue == 0.7)
    #expect(submitBody["fireworks"] == nil)
}
