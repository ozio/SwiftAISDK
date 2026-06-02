import Foundation
import Testing
@testable import SwiftAISDK

@Test func replicateImageUsesModelPredictionEndpoint() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-1","status":"succeeded","output":["https://replicate.example.com/image.png"]}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("replicate-png".utf8))
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/flux-schnell")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        count: 2,
        extraBody: [
            "aspectRatio": .string("3:4"),
            "guidance_scale": .number(7.5),
            "maxWaitTimeInSeconds": .number(30)
        ]
    ))

    #expect(result.urls == ["https://replicate.example.com/image.png"])
    #expect(result.base64Images == [Data("replicate-png".utf8).base64EncodedString()])
    let requests = await transport.requests()
    #expect(requests.count == 2)
    let request = try #require(requests.first)
    #expect(request.url.absoluteString == "https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions")
    #expect(request.headers["Authorization"] == "Bearer replicate-key")
    #expect(request.headers["prefer"] == "wait=30")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["input"]?["prompt"]?.stringValue == "cat")
    #expect(body["input"]?["num_outputs"]?.intValue == 2)
    #expect(body["input"]?["aspect_ratio"]?.stringValue == "3:4")
    #expect(body["input"]?["guidance_scale"]?.doubleValue == 7.5)
    #expect(body["input"]?["maxWaitTimeInSeconds"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://replicate.example.com/image.png")
}

@Test func replicateImageUsesStandardOptionsProviderOptionsAndWarnings() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-1","status":"succeeded","output":["https://replicate.example.com/image.png"]}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("replicate-png".utf8))
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/flux-schnell")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        aspectRatio: "3:4",
        seed: 123,
        count: 1,
        files: [
            ImageInputFile(url: "https://example.com/input-1.jpg"),
            ImageInputFile(url: "https://example.com/input-2.jpg")
        ],
        providerOptions: [
            "replicate": .object([
                "guidance_scale": 7.5,
                "num_inference_steps": 30,
                "maxWaitTimeInSeconds": 15
            ])
        ]
    ))

    #expect(result.warnings == [
        AIWarning(type: "other", message: "This Replicate model only supports a single input image. Additional images are ignored.")
    ])
    let request = try #require(await transport.requests().first)
    #expect(request.headers["prefer"] == "wait=15")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["input"]?["aspect_ratio"]?.stringValue == "3:4")
    #expect(body["input"]?["seed"]?.intValue == 123)
    #expect(body["input"]?["num_outputs"]?.intValue == 1)
    #expect(body["input"]?["image"]?.stringValue == "https://example.com/input-1.jpg")
    #expect(body["input"]?["guidance_scale"]?.doubleValue == 7.5)
    #expect(body["input"]?["num_inference_steps"]?.intValue == 30)
    #expect(body["input"]?["maxWaitTimeInSeconds"] == nil)
    #expect(body["input"]?["replicate"] == nil)
}

@Test func replicateImageRejectsUnsafeOutputDownloadURL() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"pred-1","status":"succeeded","output":["http://127.0.0.1/image.png"]}
    """))
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/flux-schnell")

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat"))
    }

    let requests = await transport.requests()
    #expect(requests.count == 1)
    #expect(requests[0].url.absoluteString == "https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions")
}

@Test func replicateImageMapsEditingInputsAndNestedOptions() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-1","status":"succeeded","output":"https://replicate.example.com/edited.webp"}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/webp"], body: Data("edited-webp".utf8))
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.imageModel("owner/inpaint-model")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Replace the masked area",
        count: 1,
        files: [ImageInputFile(url: "https://example.com/input.jpg")],
        mask: ImageInputFile(data: Data([0x89, 0x50, 0x4E, 0x47]), mediaType: "image/png"),
        extraBody: [
            "replicate": .object([
                "guidance_scale": .number(7.5),
                "num_inference_steps": .number(30),
                "negative_prompt": .string("blur"),
                "maxWaitTimeInSeconds": .number(45)
            ])
        ]
    ))

    let requests = await transport.requests()
    let request = try #require(requests.first)
    #expect(request.headers["prefer"] == "wait=45")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["input"]?["prompt"]?.stringValue == "Replace the masked area")
    #expect(body["input"]?["image"]?.stringValue == "https://example.com/input.jpg")
    #expect(body["input"]?["mask"]?.stringValue == "data:image/png;base64,\(Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString())")
    #expect(body["input"]?["guidance_scale"]?.doubleValue == 7.5)
    #expect(body["input"]?["num_inference_steps"]?.intValue == 30)
    #expect(body["input"]?["negative_prompt"]?.stringValue == "blur")
    #expect(body["input"]?["maxWaitTimeInSeconds"] == nil)
    #expect(body["input"]?["replicate"] == nil)
}

@Test func replicateFlux2ImageMapsMultipleInputImages() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-1","status":"succeeded","output":["https://replicate.example.com/flux.webp"]}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/webp"], body: Data("flux-webp".utf8))
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/flux-2-pro")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Use reference images",
        files: [
            ImageInputFile(url: "https://example.com/reference-1.jpg"),
            ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png"),
            ImageInputFile(url: "https://example.com/reference-3.jpg")
        ],
        mask: ImageInputFile(url: "https://example.com/mask.png")
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["input"]?["input_image"]?.stringValue == "https://example.com/reference-1.jpg")
    #expect(body["input"]?["input_image_2"]?.stringValue == "data:image/png;base64,\(Data([1, 2, 3]).base64EncodedString())")
    #expect(body["input"]?["input_image_3"]?.stringValue == "https://example.com/reference-3.jpg")
    #expect(body["input"]?["mask"] == nil)
    #expect(body["input"]?["image"] == nil)
}

@Test func replicateFlux2ImageWarningsMirrorUpstreamLimits() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-1","status":"succeeded","output":["https://replicate.example.com/flux.webp"]}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/webp"], body: Data("flux-webp".utf8))
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/flux-2-pro")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "Use many references",
        files: (1...9).map { ImageInputFile(url: "https://example.com/reference-\($0).jpg") },
        mask: ImageInputFile(url: "https://example.com/mask.png")
    ))

    #expect(result.warnings == [
        AIWarning(type: "other", message: "Flux-2 models support up to 8 input images. Additional images are ignored."),
        AIWarning(type: "other", message: "Flux-2 models do not support mask input. The mask will be ignored.")
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["input"]?["input_image_8"]?.stringValue == "https://example.com/reference-8.jpg")
    #expect(body["input"]?["input_image_9"] == nil)
    #expect(body["input"]?["mask"] == nil)
}

@Test func replicateVideoUsesPredictionEndpointAndReturnsOutputURL() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-video","status":"starting","output":null,"urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"}}
        """),
        jsonResponse("""
        {"id":"pred-video","status":"succeeded","output":"https://replicate.example.com/video.mp4","urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"}}
        """)
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.videoModel("owner/video-model")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        aspectRatio: "16:9",
        durationSeconds: 4,
        extraBody: [
            "guidance_scale": .number(7.5),
            "maxWaitTimeInSeconds": .number(30),
            "pollIntervalMs": .number(1),
            "pollTimeoutMs": .number(1_000)
        ]
    ))

    #expect(result.urls == ["https://replicate.example.com/video.mp4"])
    #expect(result.operationID == "pred-video")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    let request = try #require(requests.first)
    #expect(request.url.absoluteString == "https://api.replicate.com/v1/models/owner/video-model/predictions")
    #expect(request.headers["prefer"] == "wait=30")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["input"]?["prompt"]?.stringValue == "cat running")
    #expect(body["input"]?["aspect_ratio"]?.stringValue == "16:9")
    #expect(body["input"]?["duration"]?.intValue == 4)
    #expect(body["input"]?["guidance_scale"]?.doubleValue == 7.5)
    #expect(body["input"]?["maxWaitTimeInSeconds"] == nil)
    #expect(body["input"]?["pollIntervalMs"] == nil)
    #expect(body["input"]?["pollTimeoutMs"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api.replicate.com/v1/predictions/pred-video")
}

@Test func replicateVideoMapsNestedOptionsAndImageInput() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"pred-video","status":"succeeded","output":"https://replicate.example.com/video.mp4","urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"},"metrics":{"predict_time":25.5}}
    """))
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.videoModel("stability-ai/stable-video-diffusion:abc123")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "Animate the image",
        aspectRatio: "9:16",
        durationSeconds: 5,
        extraBody: [
            "replicate": .object([
                "resolution": .string("1920x1080"),
                "fps": .number(24),
                "seed": .number(42),
                "image": .object([
                    "data": .string("base64-image-data"),
                    "mediaType": .string("image/png")
                ]),
                "guidance_scale": .number(8),
                "motion_bucket_id": .number(127),
                "prompt_optimizer": .bool(true),
                "pollIntervalMs": .number(1),
                "pollTimeoutMs": .number(1_000),
                "maxWaitTimeInSeconds": .number(30)
            ])
        ]
    ))

    #expect(result.urls == ["https://replicate.example.com/video.mp4"])
    #expect(result.operationID == "pred-video")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.replicate.com/v1/predictions")
    #expect(request.headers["prefer"] == "wait=30")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["version"]?.stringValue == "abc123")
    #expect(body["input"]?["prompt"]?.stringValue == "Animate the image")
    #expect(body["input"]?["aspect_ratio"]?.stringValue == "9:16")
    #expect(body["input"]?["duration"]?.intValue == 5)
    #expect(body["input"]?["size"]?.stringValue == "1920x1080")
    #expect(body["input"]?["fps"]?.intValue == 24)
    #expect(body["input"]?["seed"]?.intValue == 42)
    #expect(body["input"]?["image"]?.stringValue == "data:image/png;base64,base64-image-data")
    #expect(body["input"]?["guidance_scale"]?.intValue == 8)
    #expect(body["input"]?["motion_bucket_id"]?.intValue == 127)
    #expect(body["input"]?["prompt_optimizer"]?.boolValue == true)
    #expect(body["input"]?["resolution"] == nil)
    #expect(body["input"]?["pollIntervalMs"] == nil)
    #expect(body["input"]?["pollTimeoutMs"] == nil)
    #expect(body["input"]?["maxWaitTimeInSeconds"] == nil)
    #expect(body["input"]?["replicate"] == nil)
}

@Test func replicateVideoUsesStandardFieldsProviderOptionsAndMetadata() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"pred-video","status":"succeeded","output":"https://replicate.example.com/video.mp4","urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"},"metrics":{"predict_time":25.5}}
    """))
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.videoModel("owner/video-model")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "Animate this",
        aspectRatio: "1:1",
        durationSeconds: 6,
        image: ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png"),
        resolution: "1920x1080",
        fps: 30,
        seed: 42,
        providerOptions: [
            "replicate": .object([
                "guidance_scale": 7.5,
                "num_inference_steps": 50,
                "maxWaitTimeInSeconds": 20,
                "pollIntervalMs": 1
            ])
        ]
    ))

    #expect(result.urls == ["https://replicate.example.com/video.mp4"])
    #expect(result.providerMetadata["replicate"]?["predictionId"]?.stringValue == "pred-video")
    #expect(result.providerMetadata["replicate"]?["videos"]?[0]?["url"]?.stringValue == "https://replicate.example.com/video.mp4")
    #expect(result.providerMetadata["replicate"]?["metrics"]?["predict_time"]?.doubleValue == 25.5)
    let request = try #require(await transport.requests().first)
    #expect(request.headers["prefer"] == "wait=20")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["input"]?["prompt"]?.stringValue == "Animate this")
    #expect(body["input"]?["aspect_ratio"]?.stringValue == "1:1")
    #expect(body["input"]?["duration"]?.intValue == 6)
    #expect(body["input"]?["image"]?.stringValue == "data:image/png;base64,\(Data([1, 2, 3]).base64EncodedString())")
    #expect(body["input"]?["size"]?.stringValue == "1920x1080")
    #expect(body["input"]?["fps"]?.intValue == 30)
    #expect(body["input"]?["seed"]?.intValue == 42)
    #expect(body["input"]?["guidance_scale"]?.doubleValue == 7.5)
    #expect(body["input"]?["num_inference_steps"]?.intValue == 50)
    #expect(body["input"]?["maxWaitTimeInSeconds"] == nil)
    #expect(body["input"]?["pollIntervalMs"] == nil)
    #expect(body["input"]?["replicate"] == nil)
}

@Test func replicateProviderOptionsValidateLikeUpstreamImageSchema() async throws {
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: RecordingTransport(response: jsonResponse(#"{"output":"https://replicate.example.com/image.png"}"#))))
    let model = try provider.imageModel("black-forest-labs/flux-schnell")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.replicate", message: "Replicate provider options must be an object.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["replicate": "bad"]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.replicate.maxWaitTimeInSeconds", message: "Replicate maxWaitTimeInSeconds must be greater than 0 or null.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["replicate": ["maxWaitTimeInSeconds": 0]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.replicate.output_format", message: "Replicate output_format must be png, jpg, webp, or null.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["replicate": ["output_format": "gif"]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.replicate.output_quality", message: "Replicate output_quality must be at most 100 or null.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["replicate": ["output_quality": 101]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.replicate.strength", message: "Replicate strength must be at least 0 or null.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["replicate": ["strength": -0.1]]))
    }
}

@Test func replicateProviderOptionsValidateLikeUpstreamVideoSchemaAndNullishOmit() async throws {
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: RecordingTransport(response: jsonResponse(#"{"id":"pred-video","status":"succeeded","output":"https://replicate.example.com/video.mp4","urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"}}"#))))
    let model = try provider.videoModel("owner/video-model")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.replicate", message: "Replicate provider options must be an object.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["replicate": true]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.replicate.pollIntervalMs", message: "Replicate pollIntervalMs must be greater than 0 or null.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["replicate": ["pollIntervalMs": 0]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.replicate.video_length", message: "Replicate video_length must be a string or null.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["replicate": ["video_length": 24]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.replicate.prompt_optimizer", message: "Replicate prompt_optimizer must be a boolean or null.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["replicate": ["prompt_optimizer": "true"]]))
    }

    let nullishTransport = RecordingTransport(response: jsonResponse(#"{"id":"pred-video","status":"succeeded","output":"https://replicate.example.com/video.mp4","urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"}}"#))
    let nullishProvider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: nullishTransport))
    let nullishModel = try nullishProvider.videoModel("owner/video-model")
    _ = try await nullishModel.generateVideo(VideoGenerationRequest(
        prompt: "cat",
        providerOptions: ["replicate": .object(["guidance_scale": .null, "customFlag": true])]
    ))

    let body = try decodeJSONBody(try #require((await nullishTransport.requests()).first?.body))
    #expect(body["input"]?["guidance_scale"] == nil)
    #expect(body["input"]?["customFlag"]?.boolValue == true)
}
