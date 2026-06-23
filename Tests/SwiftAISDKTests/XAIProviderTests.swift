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
    #expect(imageRequest.headers["authorization"] == "Bearer xai-key")
    #expect(imageRequest.headers["user-agent"] == "ai-sdk/xai/3.0.96")
    let imageBody = try decodeJSONBody(try #require(imageRequest.body))
    #expect(imageBody["model"]?.stringValue == "grok-2-image")
    #expect(imageBody["prompt"]?.stringValue == "cat")
    #expect(imageBody["n"]?.intValue == 2)
    #expect(imageBody["aspect_ratio"]?.stringValue == "16:9")
    #expect(imageBody["response_format"]?.stringValue == "b64_json")
    #expect(imageBody["quality"]?.stringValue == "high")
    #expect(imageBody["output_format"]?.stringValue == "png")
    #expect(imageRequests[1].method == "GET")
    #expect(imageRequests[1].headers["authorization"] == nil)
    #expect(imageRequests[1].headers["user-agent"] == nil)

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
    #expect(requests[0].headers["authorization"] == "Bearer xai-key")
    #expect(requests[0].headers["user-agent"] == "ai-sdk/xai/3.0.96")
    let videoBody = try decodeJSONBody(try #require(requests[0].body))
    #expect(videoBody["model"]?.stringValue == "grok-2-video")
    #expect(videoBody["prompt"]?.stringValue == "cat running")
    #expect(videoBody["duration"]?.intValue == 6)
    #expect(videoBody["aspect_ratio"]?.stringValue == "16:9")
    #expect(videoBody["resolution"]?.stringValue == "720p")
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api.x.ai/v1/videos/vid-1")
    #expect(requests[1].headers["authorization"] == "Bearer xai-key")
    #expect(requests[1].headers["user-agent"] == "ai-sdk/xai/3.0.96")

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
    #expect(editRequests[0].headers["authorization"] == "Bearer xai-key")
    #expect(editRequests[0].headers["user-agent"] == "ai-sdk/xai/3.0.96")
    #expect(editRequests[1].headers["authorization"] == "Bearer xai-key")
    #expect(editRequests[1].headers["user-agent"] == "ai-sdk/xai/3.0.96")
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

@Test func xAIImageProviderOptionsValidateLikeUpstreamSchema() async throws {
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"image"}]}"#))))
    let model = try provider.imageModel("grok-2-image")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai", message: "xAI provider options must be an object.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["xai": "bad"]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.sync_mode", message: "xAI sync_mode must be a boolean.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["xai": ["sync_mode": "true"]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.resolution", message: "xAI resolution must be 1k or 2k.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["xai": ["resolution": "4k"]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.quality", message: "xAI quality must be low, medium, or high.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["xai": ["quality": "ultra"]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.user", message: "xAI user must be a string.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["xai": ["user": .null]]))
    }

    let stripTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"image"}]}"#))
    let stripProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: stripTransport))
    let stripModel = try stripProvider.imageModel("grok-2-image")
    _ = try await stripModel.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["xai": ["quality": "high", "unknown": "drop-me"]]))
    let body = try decodeJSONBody(try #require((await stripTransport.requests()).first?.body))
    #expect(body["quality"]?.stringValue == "high")
    #expect(body["unknown"] == nil)
}

@Test func xAIVideoProviderOptionsValidateLikeUpstreamSchema() async throws {
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"vid-1"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/video.mp4","respect_moderation":true}}"#)
    ])))
    let model = try provider.videoModel("grok-2-video")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai", message: "xAI provider options must be an object.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["xai": true]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.mode", message: "xAI mode must be edit-video, extend-video, or reference-to-video.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["xai": ["mode": "bad"]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.videoUrl", message: "xAI videoUrl must be a non-empty string.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["xai": ["videoUrl": ""]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.referenceImageUrls", message: "xAI referenceImageUrls must contain 1 to 7 non-empty strings.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["xai": .object(["referenceImageUrls": .array(Array(repeating: .string("https://example.com/ref.png"), count: 8))])]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.pollIntervalMs", message: "xAI pollIntervalMs must be a positive number or null.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["xai": ["pollIntervalMs": 0]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.resolution", message: "xAI resolution must be 480p, 720p, or null.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["xai": ["resolution": "1080p"]]))
    }
}

@Test func xAIVideoProviderOptionsPassthroughAndNullishResolutionMatchUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"vid-null"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/video.mp4","respect_moderation":true}}"#)
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.videoModel("grok-2-video")

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat",
        providerOptions: ["xai": .object(["resolution": .null, "customFlag": true, "pollIntervalMs": 1])],
        extraBody: ["xai": .object(["resolution": "720p"])]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["resolution"] == nil)
    #expect(body["customFlag"]?.boolValue == true)
}
