import Foundation
import Testing
@testable import SwiftAISDK

@Test func byteDanceUsesUpstreamARKAPIKeyEnvironmentOnly() throws {
    #expect(throws: AIError.missingAPIKey(provider: "bytedance", environmentVariables: ["ARK_API_KEY"])) {
        _ = try AIProviders.byteDance(settings: ProviderSettings())
    }
}

@Test func byteDanceVideoSubmitsPollsAndPreservesMetadata() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"task-1"}"#),
        jsonResponse(
            #"{"id":"task-1","model":"seedance-final","status":"succeeded","content":{"video_url":"https://bytedance.example.com/video.mp4"},"usage":{"completion_tokens":42}}"#,
            headers: ["x-bytedance": "yes"]
        )
    ])
    let provider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "ark-key", transport: transport))
    let model = try provider.videoModel("seedance-1-0-pro")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        aspectRatio: "16:9",
        durationSeconds: 4,
        resolution: "1920x1080",
        seed: 11,
        providerOptions: [
            "bytedance": .object([
                "serviceTier": "flex"
            ]),
            "openai": .object([
                "serviceTier": "should-not-leak"
            ])
        ],
        headers: ["x-request-id": "req-1"]
    ))

    #expect(result.urls == ["https://bytedance.example.com/video.mp4"])
    #expect(result.operationID == "task-1")
    #expect(result.providerMetadata["bytedance"]?["taskId"]?.stringValue == "task-1")
    #expect(result.providerMetadata["bytedance"]?["usage"]?["completion_tokens"]?.intValue == 42)
    #expect(result.responseMetadata.id == "task-1")
    #expect(result.responseMetadata.modelID == "seedance-final")
    #expect(result.responseMetadata.headers["x-bytedance"] == "yes")
    #expect(result.responseMetadata.body?["content"]?["video_url"]?.stringValue == "https://bytedance.example.com/video.mp4")
    #expect(result.requestMetadata.headers["x-request-id"] == "req-1")
    #expect(result.requestMetadata.body?["content"]?[0]?["text"]?.stringValue == "cat running")

    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].method == "POST")
    #expect(requests[0].url.absoluteString == "https://ark.ap-southeast.bytepluses.com/api/v3/contents/generations/tasks")
    #expect(requests[0].headers["Authorization"] == "Bearer ark-key")
    #expect(requests[0].headers["x-request-id"] == "req-1")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["model"]?.stringValue == "seedance-1-0-pro")
    #expect(body["content"]?[0]?["type"]?.stringValue == "text")
    #expect(body["content"]?[0]?["text"]?.stringValue == "cat running")
    #expect(body["ratio"]?.stringValue == "16:9")
    #expect(body["duration"]?.intValue == 4)
    #expect(body["seed"]?.intValue == 11)
    #expect(body["resolution"]?.stringValue == "1080p")
    #expect(body["service_tier"]?.stringValue == "flex")
    #expect(body["openai"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://ark.ap-southeast.bytepluses.com/api/v3/contents/generations/tasks/task-1")
    #expect(requests[1].headers["Authorization"] == "Bearer ark-key")
    #expect(requests[1].headers["x-request-id"] == "req-1")
}

@Test func byteDanceVideoMapsStandardImageAndReferenceMedia() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"task-2"}"#),
        jsonResponse(#"{"id":"task-2","model":"seedance","status":"succeeded","content":{"video_url":"https://bytedance.example.com/with-refs.mp4"}}"#)
    ])
    let provider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "ark-key", transport: transport))
    let model = try provider.videoModel("seedance-1-0-pro")
    let imageData = Data([1, 2, 3])

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        image: ImageInputFile(data: imageData, mediaType: "image/png"),
        providerOptions: [
            "bytedance": .object([
                "lastFrameImage": "https://example.com/end.png",
                "referenceImages": [
                    "https://example.com/ref-1.png",
                    "https://example.com/ref-2.png"
                ],
                "referenceVideos": ["https://example.com/ref.mp4"],
                "referenceAudio": [
                    "data:audio/mpeg;base64,YXVkaW8="
                ]
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["content"]?[0]?["type"]?.stringValue == "text")
    #expect(body["content"]?[1]?["type"]?.stringValue == "image_url")
    #expect(body["content"]?[1]?["image_url"]?["url"]?.stringValue == "data:image/png;base64,\(imageData.base64EncodedString())")
    #expect(body["content"]?[2]?["role"]?.stringValue == "last_frame")
    #expect(body["content"]?[2]?["image_url"]?["url"]?.stringValue == "https://example.com/end.png")
    #expect(body["content"]?[3]?["role"]?.stringValue == "reference_image")
    #expect(body["content"]?[3]?["image_url"]?["url"]?.stringValue == "https://example.com/ref-1.png")
    #expect(body["content"]?[4]?["role"]?.stringValue == "reference_image")
    #expect(body["content"]?[4]?["image_url"]?["url"]?.stringValue == "https://example.com/ref-2.png")
    #expect(body["content"]?[5]?["role"]?.stringValue == "reference_video")
    #expect(body["content"]?[5]?["video_url"]?["url"]?.stringValue == "https://example.com/ref.mp4")
    #expect(body["content"]?[6]?["role"]?.stringValue == "reference_audio")
    #expect(body["content"]?[6]?["audio_url"]?["url"]?.stringValue == "data:audio/mpeg;base64,YXVkaW8=")
}

@Test func byteDanceVideoMapsProviderOptionsAndWarnings() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"task-3"}"#),
        jsonResponse(#"{"id":"task-3","model":"seedance","status":"succeeded","content":{"video_url":"https://bytedance.example.com/options.mp4"}}"#)
    ])
    let provider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "ark-key", transport: transport))
    let model = try provider.videoModel("seedance-1-0-pro")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        fps: 60,
        count: 2,
        providerOptions: [
            "bytedance": .object([
                "watermark": false,
                "generateAudio": true,
                "cameraFixed": true,
                "returnLastFrame": true,
                "serviceTier": "flex",
                "draft": true,
                "seed": 7,
                "resolution": "1280x720",
                "customFlag": "keep-me",
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ]
    ))

    #expect(result.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "fps",
            message: "ByteDance video models do not support custom FPS. Frame rate is fixed at 24 fps."
        ),
        AIWarning(
            type: "unsupported",
            feature: "n",
            message: "ByteDance video models do not support generating multiple videos per call. Only 1 video will be generated."
        )
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["watermark"]?.boolValue == false)
    #expect(body["generate_audio"]?.boolValue == true)
    #expect(body["camera_fixed"]?.boolValue == true)
    #expect(body["return_last_frame"]?.boolValue == true)
    #expect(body["service_tier"]?.stringValue == "flex")
    #expect(body["draft"]?.boolValue == true)
    #expect(body["seed"]?.intValue == 7)
    #expect(body["resolution"]?.stringValue == "1280x720")
    #expect(body["customFlag"]?.stringValue == "keep-me")
    #expect(body["pollIntervalMs"] == nil)
    #expect(body["pollTimeoutMs"] == nil)
    #expect(body["n"] == nil)
    #expect(body["bytedance"] == nil)
}

@Test func byteDanceExtraBodyKeepsLegacyMediaAliasesAndResolutionMapping() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"task-extra"}"#),
        jsonResponse(#"{"id":"task-extra","model":"seedance","status":"succeeded","content":{"video_url":"https://bytedance.example.com/extra.mp4"}}"#)
    ])
    let provider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "ark-key", transport: transport))
    let model = try provider.videoModel("seedance-1-0-pro")

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        extraBody: [
            "bytedance": .object([
                "last_frame_image": "https://example.com/end.png",
                "reference_audio": [
                    .object([
                        "data": .string("data:audio/mpeg;base64,YXVkaW8=")
                    ])
                ],
                "generate_audio": true,
                "resolution": "1280x720",
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["content"]?[1]?["role"]?.stringValue == "last_frame")
    #expect(body["content"]?[1]?["image_url"]?["url"]?.stringValue == "https://example.com/end.png")
    #expect(body["content"]?[2]?["role"]?.stringValue == "reference_audio")
    #expect(body["content"]?[2]?["audio_url"]?["url"]?.stringValue == "data:audio/mpeg;base64,YXVkaW8=")
    #expect(body["generate_audio"]?.boolValue == true)
    #expect(body["resolution"]?.stringValue == "720p")
}

@Test func byteDanceProviderOptionsValidateKnownSchemaFields() async throws {
    let provider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "ark-key", transport: RecordingTransport(response: jsonResponse(#"{"id":"unused"}"#))))
    let model = try provider.videoModel("seedance-1-0-pro")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.bytedance", message: "ByteDance provider options must be an object.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(
            prompt: "invalid namespace",
            providerOptions: ["bytedance": .string("bad")]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateVideo(VideoGenerationRequest(
            prompt: "invalid boolean",
            providerOptions: ["bytedance": .object(["watermark": .string("no")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateVideo(VideoGenerationRequest(
            prompt: "invalid tier",
            providerOptions: ["bytedance": .object(["serviceTier": .string("premium")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateVideo(VideoGenerationRequest(
            prompt: "invalid reference",
            providerOptions: ["bytedance": .object(["referenceAudio": .array([.object(["data": .string("audio")])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateVideo(VideoGenerationRequest(
            prompt: "invalid polling",
            providerOptions: ["bytedance": .object(["pollTimeoutMs": .number(0)])]
        ))
    }
}

@Test func byteDanceProviderOptionsNullNamespaceKeepsExtraBodyDefaults() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"task-null-namespace"}"#),
        jsonResponse(#"{"id":"task-null-namespace","model":"seedance","status":"succeeded","content":{"video_url":"https://bytedance.example.com/null-namespace.mp4"}}"#)
    ])
    let provider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "ark-key", transport: transport))
    let model = try provider.videoModel("seedance-1-0-pro")

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        providerOptions: ["bytedance": .null],
        extraBody: [
            "bytedance": .object([
                "generate_audio": true,
                "reference_images": ["https://example.com/ref.png"],
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["generate_audio"]?.boolValue == true)
    #expect(body["content"]?.arrayValue?.contains { $0["role"]?.stringValue == "reference_image" } == true)
}

@Test func byteDanceProviderOptionsUseUpstreamPassthroughForSnakeCase() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"task-snake"}"#),
        jsonResponse(#"{"id":"task-snake","model":"seedance","status":"succeeded","content":{"video_url":"https://bytedance.example.com/snake.mp4"}}"#)
    ])
    let provider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "ark-key", transport: transport))
    let model = try provider.videoModel("seedance-1-0-pro")

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        providerOptions: [
            "bytedance": .object([
                "generateAudio": true,
                "generate_audio": false,
                "serviceTier": "flex",
                "service_tier": "default",
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["generate_audio"]?.boolValue == false)
    #expect(body["service_tier"]?.stringValue == "default")
}

@Test func byteDanceProviderOptionsNullishFieldsClearExtraBodyDefaults() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"task-null"}"#),
        jsonResponse(#"{"id":"task-null","model":"seedance","status":"succeeded","content":{"video_url":"https://bytedance.example.com/null.mp4"}}"#)
    ])
    let provider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "ark-key", transport: transport))
    let model = try provider.videoModel("seedance-1-0-pro")

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        providerOptions: [
            "bytedance": .object([
                "generateAudio": .null,
                "referenceImages": .null,
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ],
        extraBody: [
            "bytedance": .object([
                "generateAudio": true,
                "referenceImages": ["https://example.com/ref.png"]
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["generate_audio"] == nil)
    #expect(body["content"]?.arrayValue?.contains { $0["role"]?.stringValue == "reference_image" } == false)
}

@Test func byteDanceVideoThrowsForMissingTaskID() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"model":"seedance"}"#))
    let provider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "ark-key", transport: transport))
    let model = try provider.videoModel("seedance-1-0-pro")

    await #expect(throws: AIError.invalidResponse(provider: "bytedance.video", message: "No task ID returned from API")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat running"))
    }
}

@Test func byteDanceVideoUsesUpstreamErrorMessageSchema() async throws {
    let submitProvider = try AIProviders.byteDance(settings: ProviderSettings(
        apiKey: "ark-key",
        transport: RecordingTransport(response: AIHTTPResponse(
            statusCode: 401,
            headers: ["x-bytedance": "bad"],
            body: Data(#"{"error":{"message":"Invalid API key","code":"unauthorized"}}"#.utf8)
        ))
    ))
    await #expect(throws: AIError.apiCall(
        provider: "bytedance.video",
        statusCode: 401,
        body: "Invalid API key",
        headers: ["x-bytedance": "bad"]
    )) {
        _ = try await submitProvider.videoModel("seedance-1-0-pro").generateVideo(VideoGenerationRequest(prompt: "bad auth"))
    }

    let pollProvider = try AIProviders.byteDance(settings: ProviderSettings(
        apiKey: "ark-key",
        transport: RecordingTransport(responses: [
            jsonResponse(#"{"id":"task-poll-error"}"#),
            AIHTTPResponse(statusCode: 500, headers: [:], body: Data(#"{"message":"Poll failed"}"#.utf8))
        ])
    ))
    await #expect(throws: AIError.apiCall(
        provider: "bytedance.video",
        statusCode: 500,
        body: "Poll failed"
    )) {
        _ = try await pollProvider.videoModel("seedance-1-0-pro").generateVideo(VideoGenerationRequest(
            prompt: "poll error",
            providerOptions: ["bytedance": .object(["pollIntervalMs": 1, "pollTimeoutMs": 1000])]
        ))
    }
}

@Test func byteDanceVideoThrowsForFailedTask() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"task-failed"}"#),
        jsonResponse(#"{"id":"task-failed","status":"failed"}"#)
    ])
    let provider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "ark-key", transport: transport))
    let model = try provider.videoModel("seedance-1-0-pro")

    do {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat running"))
        #expect(Bool(false), "Expected failed ByteDance task to throw")
    } catch AIError.invalidResponse(let provider, let message) {
        #expect(provider == "bytedance.video")
        #expect(message.hasPrefix("Video generation failed: "))
        #expect(message.contains(#""status":"failed""#))
        #expect(message.contains(#""id":"task-failed""#))
    } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
    }
}

@Test func byteDanceVideoThrowsWhenFinalResponseHasNoVideoURL() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"task-empty"}"#),
        jsonResponse(#"{"id":"task-empty","status":"succeeded","content":{}}"#)
    ])
    let provider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "ark-key", transport: transport))
    let model = try provider.videoModel("seedance-1-0-pro")

    await #expect(throws: AIError.invalidResponse(provider: "bytedance.video", message: "No video URL in response")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat running"))
    }
}

@Test func byteDanceVideoTimesOutWithUpstreamMessage() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"task-timeout"}"#),
        jsonResponse(#"{"id":"task-timeout","status":"processing"}"#)
    ])
    let provider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "ark-key", transport: transport))
    let model = try provider.videoModel("seedance-1-0-pro")

    await #expect(throws: AIError.invalidResponse(provider: "bytedance.video", message: "Video generation timed out after 1ms")) {
        _ = try await model.generateVideo(VideoGenerationRequest(
            prompt: "timeout",
            providerOptions: ["bytedance": .object(["pollIntervalMs": 1, "pollTimeoutMs": 1])]
        ))
    }
}
