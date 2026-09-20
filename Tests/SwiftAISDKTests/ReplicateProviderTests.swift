import Foundation
import Testing
@testable import SwiftAISDK

@Test func replicateImageUsesModelPredictionEndpoint() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-1","status":"succeeded","output":["https://replicate.example.com/image.png"],"urls":{"get":"https://api.replicate.com/v1/predictions/pred-1"}}
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
    #expect(request.headers["authorization"] == "Bearer replicate-key")
    #expect(request.headers["user-agent"] == "ai-sdk/replicate/3.0.46")
    #expect(request.headers["prefer"] == "wait=30")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["input"]?["prompt"]?.stringValue == "cat")
    #expect(body["input"]?["num_outputs"]?.intValue == 2)
    #expect(body["input"]?["aspect_ratio"]?.stringValue == "3:4")
    #expect(body["input"]?["guidance_scale"]?.doubleValue == 7.5)
    #expect(body["input"]?["maxWaitTimeInSeconds"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://replicate.example.com/image.png")
    #expect(requests[1].headers["authorization"] == nil)
    #expect(requests[1].headers["user-agent"] == nil)
}

@Test func replicateImagePollsUntilOutputAfterSyncWaitExpiresLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"pending-prediction","status":"starting","output":null,"error":null,"urls":{"get":"https://api.replicate.com/v1/predictions/pending-prediction"}}"#),
        jsonResponse(#"{"id":"pending-prediction","status":"processing","output":null,"error":null,"urls":{"get":"https://api.replicate.com/v1/predictions/pending-prediction"}}"#),
        jsonResponse(#"{"id":"pending-prediction","status":"succeeded","output":["https://replicate.delivery/xezq/abc/out-0.webp"],"error":null,"urls":{"get":"https://api.replicate.com/v1/predictions/pending-prediction"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/webp"], body: Data("test-binary-content".utf8))
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/flux-schnell")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        providerOptions: [
            "replicate": .object([
                "pollIntervalMillis": 1,
                "maxPollAttempts": 100
            ])
        ]
    ))

    #expect(result.base64Images == [Data("test-binary-content".utf8).base64EncodedString()])
    let requests = await transport.requests()
    #expect(requests.map(\.method) == ["POST", "GET", "GET", "GET"])
    #expect(requests[1].url.absoluteString == "https://api.replicate.com/v1/predictions/pending-prediction")
    #expect(requests[1].headers["authorization"] == "Bearer replicate-key")
    #expect(requests[2].headers["authorization"] == "Bearer replicate-key")
    #expect(requests[3].headers["authorization"] == nil)
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["input"]?["pollIntervalMillis"] == nil)
    #expect(body["input"]?["maxPollAttempts"] == nil)
}

@Test func replicateImageStripsCredentialsFromForeignPollingOriginLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"pending-prediction","status":"starting","output":null,"urls":{"get":"https://status.example.com/predictions/pending-prediction"}}"#),
        jsonResponse(#"{"id":"pending-prediction","status":"succeeded","output":["https://replicate.delivery/xezq/abc/out-0.webp"],"urls":{"get":"https://status.example.com/predictions/pending-prediction"}}"#),
        AIHTTPResponse(statusCode: 200, body: Data("image".utf8))
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))

    _ = try await provider.imageModel("black-forest-labs/flux-schnell").generateImage(ImageGenerationRequest(
        prompt: "cat",
        providerOptions: ["replicate": ["pollIntervalMillis": 1, "maxPollAttempts": 100]]
    ))

    let requests = await transport.requests()
    #expect(requests[1].url.absoluteString == "https://status.example.com/predictions/pending-prediction")
    #expect(requests[1].headers["authorization"] == nil)
}

@Test func replicateImagePollingSurfacesTerminalFailuresLikeUpstream() async throws {
    for status in ["failed", "canceled"] {
        let transport = RecordingTransport(responses: [
            jsonResponse(#"{"id":"pending-prediction","status":"starting","output":null,"urls":{"get":"https://api.replicate.com/v1/predictions/pending-prediction"}}"#),
            jsonResponse("""
            {"id":"pending-prediction","status":"\(status)","output":null,"error":"Prediction did not complete","urls":{"get":"https://api.replicate.com/v1/predictions/pending-prediction"}}
            """)
        ])
        let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))

        await #expect(throws: AIError.invalidResponse(provider: "replicate", message: "Replicate image generation \(status): Prediction did not complete")) {
            _ = try await provider.imageModel("black-forest-labs/flux-schnell").generateImage(ImageGenerationRequest(
                prompt: "cat",
                providerOptions: ["replicate": ["pollIntervalMillis": 1, "maxPollAttempts": 100]]
            ))
        }
    }
}

@Test func replicateImageRejectsSucceededPredictionWithoutOutputLikeUpstream() async throws {
    let provider = try AIProviders.replicate(settings: ProviderSettings(
        apiKey: "replicate-key",
        transport: RecordingTransport(response: jsonResponse(#"{"id":"completed-prediction","status":"succeeded","output":null,"error":null,"urls":{"get":"https://api.replicate.com/v1/predictions/completed-prediction"}}"#))
    ))

    await #expect(throws: AIError.invalidResponse(provider: "replicate", message: "Replicate image generation completed without output.")) {
        _ = try await provider.imageModel("black-forest-labs/flux-schnell").generateImage(ImageGenerationRequest(prompt: "cat"))
    }
}

@Test func replicateImageStopsAtConfiguredMaximumPollingAttemptsLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"pending-prediction","status":"processing","output":null,"urls":{"get":"https://api.replicate.com/v1/predictions/pending-prediction"}}"#),
        jsonResponse(#"{"id":"pending-prediction","status":"processing","output":null,"urls":{"get":"https://api.replicate.com/v1/predictions/pending-prediction"}}"#)
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))

    await #expect(throws: AIError.invalidResponse(provider: "replicate", message: "Replicate image generation did not complete after 2 polling attempts.")) {
        _ = try await provider.imageModel("black-forest-labs/flux-schnell").generateImage(ImageGenerationRequest(
            prompt: "cat",
            providerOptions: ["replicate": ["pollIntervalMillis": 1, "maxPollAttempts": 2]]
        ))
    }
    #expect(await transport.requests().count == 3)
}

@Test func replicateAppendsVersionedUserAgentToCustomHeader() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-1","status":"succeeded","output":["https://replicate.example.com/image.png"],"urls":{"get":"https://api.replicate.com/v1/predictions/pred-1"}}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("replicate-png".utf8))
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(
        apiKey: "replicate-key",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: transport
    ))
    let model = try provider.imageModel("black-forest-labs/flux-schnell")

    _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat"))

    let requests = await transport.requests()
    #expect(requests[0].headers["authorization"] == "Bearer replicate-key")
    #expect(requests[0].headers["user-agent"] == "CustomApp/1.0 ai-sdk/replicate/3.0.46")
    #expect(requests[1].headers["authorization"] == nil)
    #expect(requests[1].headers["user-agent"] == nil)
}

@Test func replicateImageUsesUpstreamErrorMessageSchema() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 422,
        headers: ["x-replicate": "bad"],
        body: Data(#"{"detail":"Invalid image request"}"#.utf8)
    ))
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/flux-schnell")

    await #expect(throws: AIError.apiCall(
        provider: "replicate",
        statusCode: 422,
        body: "Invalid image request",
        headers: ["x-replicate": "bad"]
    )) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat"))
    }
}

@Test func replicateImageDownloadUsesUpstreamErrorMessageSchema() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"pred-1","status":"succeeded","output":["https://replicate.example.com/image.png"],"urls":{"get":"https://api.replicate.com/v1/predictions/pred-1"}}"#),
        AIHTTPResponse(statusCode: 500, body: Data(#"{"error":"download failed"}"#.utf8))
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/flux-schnell")

    await #expect(throws: AIError.apiCall(provider: "replicate", statusCode: 500, body: "download failed")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat"))
    }
}

@Test func replicateImageUsesStandardOptionsProviderOptionsAndWarnings() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-1","status":"succeeded","output":["https://replicate.example.com/image.png"],"urls":{"get":"https://api.replicate.com/v1/predictions/pred-1"}}
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
    {"id":"pred-1","status":"succeeded","output":["http://127.0.0.1/image.png"],"urls":{"get":"https://api.replicate.com/v1/predictions/pred-1"}}
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
        {"id":"pred-1","status":"succeeded","output":"https://replicate.example.com/edited.webp","urls":{"get":"https://api.replicate.com/v1/predictions/pred-1"}}
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
        {"id":"pred-1","status":"succeeded","output":["https://replicate.example.com/flux.webp"],"urls":{"get":"https://api.replicate.com/v1/predictions/pred-1"}}
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
        {"id":"pred-1","status":"succeeded","output":["https://replicate.example.com/flux.webp"],"urls":{"get":"https://api.replicate.com/v1/predictions/pred-1"}}
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
        ],
        headers: ["X-Request-Header": "submit-only"]
    ))

    #expect(result.urls == ["https://replicate.example.com/video.mp4"])
    #expect(result.operationID == "pred-video")
    #expect(result.mediaType == "video/mp4")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    let request = try #require(requests.first)
    #expect(request.url.absoluteString == "https://api.replicate.com/v1/models/owner/video-model/predictions")
    #expect(request.headers["authorization"] == "Bearer replicate-key")
    #expect(request.headers["user-agent"] == "ai-sdk/replicate/3.0.46")
    #expect(request.headers["prefer"] == "wait=30")
    #expect(request.headers["X-Request-Header"] == "submit-only")
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
    #expect(requests[1].headers["authorization"] == "Bearer replicate-key")
    #expect(requests[1].headers["user-agent"] == "ai-sdk/replicate/3.0.46")
    #expect(requests[1].headers["prefer"] == nil)
    #expect(requests[1].headers["X-Request-Header"] == nil)
}

@Test func replicateVideoDoesNotSendCredentialsToForeignPollingURL() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-video","status":"starting","output":null,"urls":{"get":"https://status.example.com/predictions/pred-video"}}
        """),
        jsonResponse("""
        {"id":"pred-video","status":"succeeded","output":"https://replicate.example.com/video.mp4","urls":{"get":"https://status.example.com/predictions/pred-video"}}
        """)
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.videoModel("owner/video-model")

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        extraBody: ["pollIntervalMs": .number(1), "pollTimeoutMs": .number(1_000)]
    ))

    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://status.example.com/predictions/pred-video")
    #expect(requests[1].headers["authorization"] == nil)
    #expect(requests[1].headers["user-agent"] == nil)
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
        frameImages: [
            VideoFrameImage(image: ImageInputFile(url: "https://example.com/first.png"), frameType: .firstFrame)
        ],
        inputReferences: [
            ImageInputFile(url: "https://example.com/reference.png")
        ],
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
    #expect(body["input"]?["frameImages"] == nil)
    #expect(body["input"]?["inputReferences"] == nil)
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
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.replicate.pollIntervalMillis", message: "Replicate pollIntervalMillis must be a nonnegative finite number or null.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["replicate": ["pollIntervalMillis": -1]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.replicate.maxPollAttempts", message: "Replicate maxPollAttempts must be a positive integer or null.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["replicate": ["maxPollAttempts": 1.5]]))
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

    let nullNamespaceTransport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"pred-1","status":"succeeded","output":["https://replicate.example.com/image.png"],"urls":{"get":"https://api.replicate.com/v1/predictions/pred-1"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8))
    ])
    let nullNamespaceProvider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: nullNamespaceTransport))
    let nullNamespaceModel = try nullNamespaceProvider.imageModel("black-forest-labs/flux-schnell")
    _ = try await nullNamespaceModel.generateImage(ImageGenerationRequest(
        prompt: "cat",
        providerOptions: ["replicate": .null],
        extraBody: ["replicate": ["guidance_scale": 5]]
    ))

    let body = try decodeJSONBody(try #require((await nullNamespaceTransport.requests()).first?.body))
    #expect(body["input"]?["guidance_scale"]?.intValue == 5)
}

@Test func replicateImagePollingAliasesRejectInvalidResolvedValuesWithoutTrapping() async throws {
    let transport = RecordingTransport(response: jsonResponse("{}"))
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/flux-schnell")

    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.replicate.poll_interval_millis",
        message: "Replicate poll_interval_millis must be a nonnegative finite number or null."
    )) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "cat",
            providerOptions: ["replicate": ["poll_interval_millis": -1]]
        ))
    }
    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.replicate.max_poll_attempts",
        message: "Replicate max_poll_attempts must be a positive integer or null."
    )) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "cat",
            providerOptions: ["replicate": ["max_poll_attempts": -1]]
        ))
    }
    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.replicate.max_poll_attempts",
        message: "Replicate max_poll_attempts must be a positive integer or null."
    )) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "cat",
            providerOptions: ["replicate": ["max_poll_attempts": 1.5]]
        ))
    }
    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.replicate.poll_interval_millis",
        message: "Replicate poll_interval_millis must be a nonnegative finite number or null."
    )) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "cat",
            extraBody: ["replicate": ["poll_interval_millis": -1]]
        ))
    }
    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.replicate.poll_interval_millis",
        message: "Replicate poll_interval_millis must be a nonnegative finite number or null."
    )) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "cat",
            extraBody: ["poll_interval_millis": .number(.infinity)]
        ))
    }
    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.replicate.maxPollAttempts",
        message: "Replicate maxPollAttempts must be a positive integer or null."
    )) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "cat",
            extraBody: ["maxPollAttempts": 1.5]
        ))
    }
    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.replicate.max_poll_attempts",
        message: "Replicate max_poll_attempts must be a positive integer or null."
    )) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "cat",
            extraBody: ["replicate": ["max_poll_attempts": -1]]
        ))
    }

    #expect(await transport.requests().isEmpty)
}

@Test func replicateImagePollingValidatesAfterPrecedenceAndBoundsAcceptedIntervals() async throws {
    for interval in [0.0, 0.25] {
        let transport = RecordingTransport(responses: [
            jsonResponse(#"{"id":"pred-1","status":"processing","output":null,"urls":{"get":"https://api.replicate.com/v1/predictions/pred-1"}}"#),
            jsonResponse(#"{"id":"pred-1","status":"succeeded","output":["https://replicate.example.com/image.png"],"urls":{"get":"https://api.replicate.com/v1/predictions/pred-1"}}"#),
            AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8))
        ])
        let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
        let model = try provider.imageModel("black-forest-labs/flux-schnell")

        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "cat",
            providerOptions: ["replicate": ["pollIntervalMillis": .number(interval), "maxPollAttempts": 1]],
            extraBody: ["poll_interval_millis": -1, "max_poll_attempts": -1]
        ))

        let requests = await transport.requests()
        #expect(requests.count == 3)
        let body = try decodeJSONBody(try #require(requests.first?.body))
        #expect(body["input"]?["pollIntervalMillis"] == nil)
        #expect(body["input"]?["poll_interval_millis"] == nil)
        #expect(body["input"]?["maxPollAttempts"] == nil)
        #expect(body["input"]?["max_poll_attempts"] == nil)
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

    let nullNamespaceTransport = RecordingTransport(response: jsonResponse(#"{"id":"pred-video","status":"succeeded","output":"https://replicate.example.com/video.mp4","urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"}}"#))
    let nullNamespaceProvider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: nullNamespaceTransport))
    let nullNamespaceModel = try nullNamespaceProvider.videoModel("owner/video-model")
    _ = try await nullNamespaceModel.generateVideo(VideoGenerationRequest(
        prompt: "cat",
        providerOptions: ["replicate": .null],
        extraBody: ["replicate": ["guidance_scale": 6]]
    ))

    let nullNamespaceBody = try decodeJSONBody(try #require((await nullNamespaceTransport.requests()).first?.body))
    #expect(nullNamespaceBody["input"]?["guidance_scale"]?.intValue == 6)
}

@Test func replicateVideoUsesUpstreamErrorAndFailureMessages() async throws {
    let submitTransport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 422,
        headers: ["x-replicate": "bad"],
        body: Data(#"{"error":"Invalid video request"}"#.utf8)
    ))
    let submitProvider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: submitTransport))
    let submitModel = try submitProvider.videoModel("owner/video-model")

    await #expect(throws: AIError.apiCall(
        provider: "replicate.video",
        statusCode: 422,
        body: "Invalid video request",
        headers: ["x-replicate": "bad"]
    )) {
        _ = try await submitModel.generateVideo(VideoGenerationRequest(prompt: "cat"))
    }

    let pollTransport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"pred-video","status":"starting","output":null,"urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"}}"#),
        AIHTTPResponse(statusCode: 500, body: Data(#"{"detail":"poll failed"}"#.utf8))
    ])
    let pollProvider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: pollTransport))
    let pollModel = try pollProvider.videoModel("owner/video-model")

    await #expect(throws: AIError.apiCall(provider: "replicate.video", statusCode: 500, body: "poll failed")) {
        _ = try await pollModel.generateVideo(VideoGenerationRequest(
            prompt: "cat",
            providerOptions: ["replicate": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]]
        ))
    }

    let failedProvider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: RecordingTransport(response: jsonResponse(#"{"id":"pred-video","status":"failed","error":"bad prompt","output":null,"urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"}}"#))))
    await #expect(throws: AIError.invalidResponse(provider: "replicate.video", message: "Video generation failed: bad prompt")) {
        _ = try await failedProvider.videoModel("owner/video-model").generateVideo(VideoGenerationRequest(prompt: "cat"))
    }

    let canceledProvider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: RecordingTransport(response: jsonResponse(#"{"id":"pred-video","status":"canceled","output":null,"urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"}}"#))))
    await #expect(throws: AIError.invalidResponse(provider: "replicate.video", message: "Video generation was canceled")) {
        _ = try await canceledProvider.videoModel("owner/video-model").generateVideo(VideoGenerationRequest(prompt: "cat"))
    }

    let noOutputProvider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: RecordingTransport(response: jsonResponse(#"{"id":"pred-video","status":"succeeded","output":null,"urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"}}"#))))
    await #expect(throws: AIError.invalidResponse(provider: "replicate.video", message: "No video URL in response")) {
        _ = try await noOutputProvider.videoModel("owner/video-model").generateVideo(VideoGenerationRequest(prompt: "cat"))
    }
}
