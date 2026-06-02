import Foundation
import Testing
@testable import SwiftAISDK

@Test func xAIImageAndVideoUseNativeEndpoints() async throws {
    let imageTransport = RecordingTransport(responses: [
        jsonResponse(#"{"data":[{"url":"https://x.ai/image.png","revised_prompt":"cat!"}],"usage":{"cost_in_usd_ticks":123}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("xai-png".utf8))
    ])
    let imageProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("grok-2-image")

    let image = try await imageModel.generateImage(ImageGenerationRequest(prompt: "cat", aspectRatio: "16:9", count: 2, extraBody: ["quality": "high", "output_format": "png"]))

    #expect(image.urls == ["https://x.ai/image.png"])
    #expect(image.base64Images == [Data("xai-png".utf8).base64EncodedString()])
    #expect(image.providerMetadata["xai"]?["images"]?[0]?["revisedPrompt"]?.stringValue == "cat!")
    #expect(image.providerMetadata["xai"]?["costInUsdTicks"]?.intValue == 123)
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

    let video = try await videoModel.generateVideo(VideoGenerationRequest(prompt: "cat running", aspectRatio: "16:9", durationSeconds: 6, resolution: "1280x720", extraBody: ["pollIntervalMs": 1]))

    #expect(video.urls == ["https://x.ai/video.mp4"])
    #expect(video.operationID == "vid-1")
    #expect(video.providerMetadata["xai"]?["requestId"]?.stringValue == "vid-1")
    #expect(video.providerMetadata["xai"]?["videoUrl"]?.stringValue == "https://x.ai/video.mp4")
    #expect(video.providerMetadata["xai"]?["duration"]?.intValue == 6)
    #expect(video.providerMetadata["xai"]?["progress"]?.intValue == 100)
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
    #expect(edit.warnings.contains(AIWarning(type: "unsupported", feature: "duration", message: "xAI video editing does not support custom duration.")))
    #expect(edit.warnings.contains(AIWarning(type: "unsupported", feature: "aspectRatio", message: "xAI video editing does not support custom aspect ratio.")))
    let editRequests = await editTransport.requests()
    #expect(editRequests[0].url.absoluteString == "https://api.x.ai/v1/videos/edits")
    let editBody = try decodeJSONBody(try #require(editRequests[0].body))
    #expect(editBody["video"]?["url"]?.stringValue == "https://x.ai/source.mp4")
    #expect(editBody["aspect_ratio"] == nil)
    #expect(editBody["duration"] == nil)
}

@Test func xAIImageAndVideoWarningsProviderOptionsAndStandardInputsMatchUpstream() async throws {
    let imageTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"xai-image","revised_prompt":"revised"}],"usage":{"cost_in_usd_ticks":321}}"#))
    let imageProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("grok-2-image")

    let image = try await imageModel.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "1024x1024",
        seed: 42,
        mask: ImageInputFile(data: Data([9, 9]), mediaType: "image/png"),
        providerOptions: ["xai": .object(["aspect_ratio": "1:1", "quality": "high"])]
    ))

    #expect(image.base64Images == ["xai-image"])
    #expect(image.warnings == [
        AIWarning(type: "unsupported", feature: "size", message: "This model does not support the `size` option. Use `aspectRatio` instead."),
        AIWarning(type: "unsupported", feature: "seed"),
        AIWarning(type: "unsupported", feature: "mask")
    ])
    #expect(image.providerMetadata["xai"]?["images"]?[0]?["revisedPrompt"]?.stringValue == "revised")
    #expect(image.providerMetadata["xai"]?["costInUsdTicks"]?.intValue == 321)
    let imageBody = try decodeJSONBody(try #require((await imageTransport.requests()).first?.body))
    #expect(imageBody["aspect_ratio"]?.stringValue == "1:1")
    #expect(imageBody["quality"]?.stringValue == "high")
    #expect(imageBody["size"] == nil)
    #expect(imageBody["seed"] == nil)
    #expect(imageBody["mask"] == nil)
    #expect(imageBody["xai"] == nil)

    let videoTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"video-opts"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/generated.mp4","duration":7,"respect_moderation":true},"usage":{"cost_in_usd_ticks":654},"progress":99}"#)
    ])
    let videoProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: videoTransport))
    let videoModel = try videoProvider.videoModel("grok-2-video")

    let video = try await videoModel.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        image: ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png"),
        resolution: "854x480",
        fps: 30,
        seed: 7,
        count: 2,
        providerOptions: ["xai": .object(["pollIntervalMs": 1, "pollTimeoutMs": 1000])]
    ))

    #expect(video.urls == ["https://x.ai/generated.mp4"])
    #expect(video.warnings == [
        AIWarning(type: "unsupported", feature: "fps", message: "xAI video models do not support custom FPS."),
        AIWarning(type: "unsupported", feature: "seed", message: "xAI video models do not support seed."),
        AIWarning(type: "unsupported", feature: "n", message: "xAI video models do not support generating multiple videos per call. Only 1 video will be generated.")
    ])
    #expect(video.providerMetadata["xai"]?["requestId"]?.stringValue == "video-opts")
    #expect(video.providerMetadata["xai"]?["videoUrl"]?.stringValue == "https://x.ai/generated.mp4")
    #expect(video.providerMetadata["xai"]?["duration"]?.intValue == 7)
    #expect(video.providerMetadata["xai"]?["costInUsdTicks"]?.intValue == 654)
    #expect(video.providerMetadata["xai"]?["progress"]?.intValue == 99)
    let videoBody = try decodeJSONBody(try #require((await videoTransport.requests()).first?.body))
    #expect(videoBody["resolution"]?.stringValue == "480p")
    #expect(videoBody["image"]?["url"]?.stringValue == "data:image/png;base64,\(Data([137, 80, 78, 71]).base64EncodedString())")
    #expect(videoBody["fps"] == nil)
    #expect(videoBody["seed"] == nil)
    #expect(videoBody["n"] == nil)
    #expect(videoBody["xai"] == nil)
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
