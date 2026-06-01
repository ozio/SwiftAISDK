import Foundation
import Testing
@testable import SwiftAISDK

@Test func replicateAndFalMediaCarryResponseMetadata() async throws {
    let replicateImageTransport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"pred-image","status":"succeeded","output":["https://replicate.example.com/image.png"]}"#, headers: ["replicate-header": "image"]),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8))
    ])
    let replicateImageProvider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: replicateImageTransport))
    let replicateImageModel = try replicateImageProvider.imageModel("black-forest-labs/flux-schnell")

    let replicateImage = try await replicateImageModel.generateImage(ImageGenerationRequest(prompt: "cat"))

    #expect(replicateImage.responseMetadata.id == "pred-image")
    #expect(replicateImage.responseMetadata.modelID == "black-forest-labs/flux-schnell")
    #expect(replicateImage.responseMetadata.headers["replicate-header"] == "image")
    #expect(replicateImage.responseMetadata.body?["output"]?[0]?.stringValue == "https://replicate.example.com/image.png")

    let replicateVideoTransport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"pred-video","status":"starting","urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"}}"#, headers: ["replicate-header": "create"]),
        jsonResponse(#"{"id":"pred-video","status":"succeeded","output":"https://replicate.example.com/video.mp4","urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"}}"#, headers: ["replicate-header": "poll"])
    ])
    let replicateVideoProvider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: replicateVideoTransport))
    let replicateVideoModel = try replicateVideoProvider.videoModel("owner/video-model")

    let replicateVideo = try await replicateVideoModel.generateVideo(VideoGenerationRequest(prompt: "cat", extraBody: ["pollIntervalMs": 1]))

    #expect(replicateVideo.responseMetadata.id == "pred-video")
    #expect(replicateVideo.responseMetadata.modelID == "owner/video-model")
    #expect(replicateVideo.responseMetadata.headers["replicate-header"] == "poll")
    #expect(replicateVideo.responseMetadata.body?["output"]?.stringValue == "https://replicate.example.com/video.mp4")

    let falImageTransport = RecordingTransport(responses: [
        jsonResponse(#"{"images":[{"url":"https://fal.example.com/image.png"}]}"#, headers: ["fal-header": "image"]),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("fal-png".utf8))
    ])
    let falImageProvider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: falImageTransport))
    let falImageModel = try falImageProvider.imageModel("fal-ai/flux/schnell")

    let falImage = try await falImageModel.generateImage(ImageGenerationRequest(prompt: "cat"))

    #expect(falImage.responseMetadata.modelID == "fal-ai/flux/schnell")
    #expect(falImage.responseMetadata.headers["fal-header"] == "image")
    #expect(falImage.responseMetadata.body?["images"]?[0]?["url"]?.stringValue == "https://fal.example.com/image.png")

    let falVideoTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"fal-video","response_url":"https://queue.fal.run/fal-ai/video/requests/fal-video"}"#, headers: ["fal-header": "queue"]),
        jsonResponse(#"{"video":{"url":"https://fal.example.com/video.mp4"}}"#, headers: ["fal-header": "result"])
    ])
    let falVideoProvider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: falVideoTransport))
    let falVideoModel = try falVideoProvider.videoModel("fal-ai/video")

    let falVideo = try await falVideoModel.generateVideo(VideoGenerationRequest(prompt: "cat", extraBody: ["pollIntervalMs": 1]))

    #expect(falVideo.responseMetadata.modelID == "fal-ai/video")
    #expect(falVideo.responseMetadata.headers["fal-header"] == "result")
    #expect(falVideo.responseMetadata.body?["video"]?["url"]?.stringValue == "https://fal.example.com/video.mp4")
}

@Test func nativeImageProvidersCarryResponseMetadata() async throws {
    let deepInfraTransport = RecordingTransport(response: jsonResponse(
        #"{"images":["data:image/png;base64,deepinfra-image"]}"#,
        headers: ["deepinfra-header": "image"]
    ))
    let deepInfraProvider = try AIProviders.deepInfra(settings: ProviderSettings(apiKey: "deepinfra-key", transport: deepInfraTransport))
    let deepInfraModel = try deepInfraProvider.imageModel("black-forest-labs/FLUX-1-schnell")

    let deepInfra = try await deepInfraModel.generateImage(ImageGenerationRequest(prompt: "cat"))

    #expect(deepInfra.responseMetadata.modelID == "black-forest-labs/FLUX-1-schnell")
    #expect(deepInfra.responseMetadata.headers["deepinfra-header"] == "image")
    #expect(deepInfra.responseMetadata.body?["images"]?[0]?.stringValue == "data:image/png;base64,deepinfra-image")

    let togetherTransport = RecordingTransport(response: jsonResponse(
        #"{"data":[{"b64_json":"together-image"}]}"#,
        headers: ["together-header": "image"]
    ))
    let togetherProvider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: togetherTransport))
    let togetherModel = try togetherProvider.imageModel("black-forest-labs/FLUX.1-schnell-Free")

    let together = try await togetherModel.generateImage(ImageGenerationRequest(prompt: "cat"))

    #expect(together.responseMetadata.modelID == "black-forest-labs/FLUX.1-schnell-Free")
    #expect(together.responseMetadata.headers["together-header"] == "image")
    #expect(together.responseMetadata.body?["data"]?[0]?["b64_json"]?.stringValue == "together-image")

    let quiverTransport = RecordingTransport(response: jsonResponse(
        #"{"data":[{"svg":"<svg/>"}]}"#,
        headers: ["quiver-header": "image"]
    ))
    let quiverProvider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", transport: quiverTransport))
    let quiverModel = try quiverProvider.imageModel("arrow-1.1")

    let quiver = try await quiverModel.generateImage(ImageGenerationRequest(prompt: "logo"))

    #expect(quiver.responseMetadata.modelID == "arrow-1.1")
    #expect(quiver.responseMetadata.headers["quiver-header"] == "image")
    #expect(quiver.responseMetadata.body?["data"]?[0]?["svg"]?.stringValue == "<svg/>")

    let xaiTransport = RecordingTransport(response: jsonResponse(
        #"{"data":[{"b64_json":"xai-image","revised_prompt":"cat!"}]}"#,
        headers: ["xai-header": "image"]
    ))
    let xaiProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: xaiTransport))
    let xaiModel = try xaiProvider.imageModel("grok-2-image")

    let xai = try await xaiModel.generateImage(ImageGenerationRequest(prompt: "cat"))

    #expect(xai.responseMetadata.modelID == "grok-2-image")
    #expect(xai.responseMetadata.headers["xai-header"] == "image")
    #expect(xai.responseMetadata.body?["data"]?[0]?["revised_prompt"]?.stringValue == "cat!")
}

@Test func fireworksAndXAIAsyncMediaCarryResponseMetadata() async throws {
    let fireworksSyncTransport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        headers: ["content-type": "image/png", "fireworks-header": "sync"],
        body: Data("fireworks-png".utf8)
    ))
    let fireworksSyncProvider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: fireworksSyncTransport))
    let fireworksSyncModel = try fireworksSyncProvider.imageModel("accounts/fireworks/models/playground-v2-5-1024px-aesthetic")

    let fireworksSync = try await fireworksSyncModel.generateImage(ImageGenerationRequest(prompt: "cat"))

    #expect(fireworksSync.responseMetadata.modelID == "accounts/fireworks/models/playground-v2-5-1024px-aesthetic")
    #expect(fireworksSync.responseMetadata.headers["fireworks-header"] == "sync")
    #expect(fireworksSync.responseMetadata.body == nil)

    let fireworksAsyncTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"fw-job"}"#, headers: ["fireworks-header": "submit"]),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://assets.example.com/fireworks.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("fireworks-async".utf8))
    ])
    let fireworksAsyncProvider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: fireworksAsyncTransport))
    let fireworksAsyncModel = try fireworksAsyncProvider.imageModel("accounts/fireworks/models/flux-kontext-pro")

    let fireworksAsync = try await fireworksAsyncModel.generateImage(ImageGenerationRequest(prompt: "cat"))

    #expect(fireworksAsync.responseMetadata.modelID == "accounts/fireworks/models/flux-kontext-pro")
    #expect(fireworksAsync.responseMetadata.headers["fireworks-header"] == "submit")
    #expect(fireworksAsync.responseMetadata.body?["request_id"]?.stringValue == "fw-job")

    let xaiVideoTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"xai-video"}"#, headers: ["xai-header": "create"]),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/video.mp4","respect_moderation":true}}"#, headers: ["xai-header": "poll"])
    ])
    let xaiProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: xaiVideoTransport))
    let xaiVideoModel = try xaiProvider.videoModel("grok-video")

    let xaiVideo = try await xaiVideoModel.generateVideo(VideoGenerationRequest(prompt: "cat", extraBody: ["pollIntervalMs": 1]))

    #expect(xaiVideo.responseMetadata.modelID == "grok-video")
    #expect(xaiVideo.responseMetadata.headers["xai-header"] == "poll")
    #expect(xaiVideo.responseMetadata.body?["video"]?["url"]?.stringValue == "https://x.ai/video.mp4")
}

@Test func genericJSONMediaModelsCarryResponseMetadata() async throws {
    let imageTransport = RecordingTransport(response: jsonResponse(
        #"{"id":"image-1","data":[{"b64_json":"generic-image"}]}"#,
        headers: ["generic-header": "image"]
    ))
    let imageConfig = ModelHTTPConfig(
        providerID: "generic",
        baseURL: "https://api.example.com",
        headers: [:],
        transport: imageTransport
    )
    let imageModel = JSONImageModel(modelID: "image-model", path: "/images", config: imageConfig)

    let image = try await imageModel.generateImage(ImageGenerationRequest(prompt: "cat"))

    #expect(image.responseMetadata.id == "image-1")
    #expect(image.responseMetadata.modelID == "image-model")
    #expect(image.responseMetadata.headers["generic-header"] == "image")

    let videoTransport = RecordingTransport(response: jsonResponse(
        #"{"id":"video-1","videos":[{"url":"https://example.com/video.mp4"}]}"#,
        headers: ["generic-header": "video"]
    ))
    let videoConfig = ModelHTTPConfig(
        providerID: "generic",
        baseURL: "https://api.example.com",
        headers: [:],
        transport: videoTransport
    )
    let videoModel = JSONVideoModel(modelID: "video-model", path: "/videos", config: videoConfig)

    let video = try await videoModel.generateVideo(VideoGenerationRequest(prompt: "cat"))

    #expect(video.responseMetadata.id == "video-1")
    #expect(video.responseMetadata.modelID == "video-model")
    #expect(video.responseMetadata.headers["generic-header"] == "video")
}
