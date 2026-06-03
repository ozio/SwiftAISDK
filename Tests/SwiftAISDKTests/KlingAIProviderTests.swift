import Foundation
import Testing
@testable import SwiftAISDK

@Test func klingAIT2VSubmitsPollsAndPreservesMetadata() async throws {
    let transport = klingAITransport(taskID: "task-1", videoID: "vid-1", videoURL: "https://kling.example.com/video.mp4", headers: ["kling-header": "poll"])
    let provider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "kling-token", transport: transport))
    let model = try provider.videoModel("kling-v2.1-t2v")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        aspectRatio: "16:9",
        durationSeconds: 5,
        providerOptions: [
            "klingai": .object([
                "mode": .string("std"),
                "pollIntervalMs": .number(1),
                "pollTimeoutMs": .number(1_000)
            ]),
            "openai": .object(["unrelated": .string("ignored")])
        ]
    ))

    #expect(result.urls == ["https://kling.example.com/video.mp4"])
    #expect(result.operationID == "task-1")
    #expect(result.providerMetadata["klingai"]?["taskId"]?.stringValue == "task-1")
    #expect(result.providerMetadata["klingai"]?["videos"]?[0]?["id"]?.stringValue == "vid-1")
    #expect(result.providerMetadata["klingai"]?["videos"]?[0]?["url"]?.stringValue == "https://kling.example.com/video.mp4")
    #expect(result.providerMetadata["klingai"]?["videos"]?[0]?["watermarkUrl"]?.stringValue == "https://kling.example.com/video-watermark.mp4")
    #expect(result.providerMetadata["klingai"]?["videos"]?[0]?["duration"]?.stringValue == "5.0")
    #expect(result.responseMetadata.modelID == "kling-v2.1-t2v")
    #expect(result.responseMetadata.headers["kling-header"] == "poll")
    #expect(result.responseMetadata.body?["data"]?["task_result"]?["videos"]?[0]?["url"]?.stringValue == "https://kling.example.com/video.mp4")

    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].url.absoluteString == "https://api-singapore.klingai.com/v1/videos/text2video")
    #expect(requests[0].headers["authorization"] == "Bearer kling-token")
    #expect(requests[0].headers["user-agent"] == "ai-sdk/klingai/3.0.18")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["model_name"]?.stringValue == "kling-v2-1")
    #expect(body["prompt"]?.stringValue == "cat running")
    #expect(body["aspect_ratio"]?.stringValue == "16:9")
    #expect(body["duration"]?.stringValue == "5")
    #expect(body["mode"]?.stringValue == "std")
    #expect(body["klingai"] == nil)
    #expect(body["openai"] == nil)
    #expect(body["pollIntervalMs"] == nil)
    #expect(body["pollTimeoutMs"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api-singapore.klingai.com/v1/videos/text2video/task-1")
    #expect(requests[1].headers["authorization"] == "Bearer kling-token")
    #expect(requests[1].headers["user-agent"] == "ai-sdk/klingai/3.0.18")
}

@Test func klingAIAppendsVersionedUserAgentToCustomHeader() async throws {
    let transport = klingAITransport(taskID: "task-custom", videoURL: "https://kling.example.com/custom.mp4")
    let provider = try AIProviders.klingAI(settings: ProviderSettings(
        apiKey: "kling-token",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: transport
    ))
    let model = try provider.videoModel("kling-v2.1-t2v")

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "scene",
        providerOptions: ["klingai": .object(["mode": "std", "pollIntervalMs": 1, "pollTimeoutMs": 1000])]
    ))

    let requests = await transport.requests()
    #expect(requests[0].headers["authorization"] == "Bearer kling-token")
    #expect(requests[0].headers["user-agent"] == "CustomApp/1.0 ai-sdk/klingai/3.0.18")
    #expect(requests[1].headers["authorization"] == "Bearer kling-token")
    #expect(requests[1].headers["user-agent"] == "CustomApp/1.0 ai-sdk/klingai/3.0.18")
}

@Test func klingAIT2VMapsProviderOptionsAndWarnings() async throws {
    let transport = klingAITransport(taskID: "task-t2v", videoURL: "https://kling.example.com/t2v.mp4")
    let provider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "kling-token", transport: transport))
    let model = try provider.videoModel("kling-v3.0-t2v")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "scene",
        aspectRatio: "16:9",
        durationSeconds: 10,
        image: ImageInputFile(url: "https://example.com/not-for-t2v.png"),
        resolution: "1080p",
        fps: 30,
        seed: 42,
        count: 2,
        providerOptions: [
            "klingai": .object([
                "mode": "pro",
                "negativePrompt": "blur",
                "sound": "on",
                "cfgScale": 0.7,
                "cameraControl": .object(["type": "simple", "config": .object(["zoom": 5])]),
                "multiShot": true,
                "shotType": "customize",
                "multiPrompt": .array([.object(["index": 1, "prompt": "intro", "duration": "5"])]),
                "voiceList": .array([.object(["voice_id": "voice-1"])]),
                "elementList": .array([.object(["element_id": 101])]),
                "watermarkEnabled": false,
                "extra_passthrough": "kept",
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ]
    ))

    #expect(result.warnings.map(\.feature) == ["image", "resolution", "seed", "fps", "n"])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model_name"]?.stringValue == "kling-v3")
    #expect(body["negative_prompt"]?.stringValue == "blur")
    #expect(body["sound"]?.stringValue == "on")
    #expect(body["cfg_scale"]?.doubleValue == 0.7)
    #expect(body["camera_control"]?["config"]?["zoom"]?.intValue == 5)
    #expect(body["multi_shot"]?.boolValue == true)
    #expect(body["shot_type"]?.stringValue == "customize")
    #expect(body["multi_prompt"]?[0]?["prompt"]?.stringValue == "intro")
    #expect(body["voice_list"]?[0]?["voice_id"]?.stringValue == "voice-1")
    #expect(body["watermark_info"]?["enabled"]?.boolValue == false)
    #expect(body["extra_passthrough"]?.stringValue == "kept")
    #expect(body["element_list"] == nil)
    #expect(body["image"] == nil)
    #expect(body["n"] == nil)
}

@Test func klingAIProviderOptionsValidateKnownSchemaFields() async throws {
    let provider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "kling-token", transport: klingAITransport()))
    let model = try provider.videoModel("kling-v3.0-t2v")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.klingai", message: "KlingAI provider options must be an object.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(
            prompt: "invalid namespace",
            providerOptions: ["klingai": .string("bad")]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateVideo(VideoGenerationRequest(
            prompt: "invalid mode",
            providerOptions: ["klingai": .object(["mode": .string("fast")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateVideo(VideoGenerationRequest(
            prompt: "invalid polling",
            providerOptions: ["klingai": .object(["pollIntervalMs": .number(0)])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateVideo(VideoGenerationRequest(
            prompt: "invalid camera",
            providerOptions: ["klingai": .object(["cameraControl": .object(["type": .string("orbit")])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateVideo(VideoGenerationRequest(
            prompt: "invalid prompt array",
            providerOptions: ["klingai": .object(["multiPrompt": .array([.object(["index": 1, "prompt": "intro", "duration": 5])])])]
        ))
    }
}

@Test func klingAIProviderOptionsNullNamespaceKeepsExtraBodyDefaults() async throws {
    let transport = klingAITransport(taskID: "task-null-namespace", videoURL: "https://kling.example.com/null-namespace.mp4")
    let provider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "kling-token", transport: transport))
    let model = try provider.videoModel("kling-v3.0-t2v")

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "scene",
        providerOptions: ["klingai": .null],
        extraBody: [
            "klingai": .object([
                "mode": "pro",
                "negative_prompt": "extra blur",
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["mode"]?.stringValue == "pro")
    #expect(body["negative_prompt"]?.stringValue == "extra blur")
}

@Test func klingAIProviderOptionsUseUpstreamPassthroughForSnakeCase() async throws {
    let transport = klingAITransport(taskID: "task-snake", videoURL: "https://kling.example.com/snake.mp4")
    let provider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "kling-token", transport: transport))
    let model = try provider.videoModel("kling-v3.0-t2v")

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "scene",
        providerOptions: [
            "klingai": .object([
                "mode": "std",
                "negativePrompt": "mapped",
                "negative_prompt": "passthrough",
                "watermarkEnabled": false,
                "watermark_info": .object(["enabled": true]),
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["mode"]?.stringValue == "std")
    #expect(body["negative_prompt"]?.stringValue == "passthrough")
    #expect(body["watermark_info"]?["enabled"]?.boolValue == true)
}

@Test func klingAIProviderOptionsNullishFieldsClearExtraBodyDefaults() async throws {
    let transport = klingAITransport(taskID: "task-null", videoURL: "https://kling.example.com/null.mp4")
    let provider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "kling-token", transport: transport))
    let model = try provider.videoModel("kling-v3.0-t2v")

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "scene",
        providerOptions: [
            "klingai": .object([
                "mode": .null,
                "negativePrompt": .null,
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ],
        extraBody: [
            "klingai": .object([
                "mode": "pro",
                "negative_prompt": "extra blur"
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["mode"] == nil)
    #expect(body["negative_prompt"] == nil)
}

@Test func klingAII2VMapsStandardImageAndModeOptions() async throws {
    let transport = klingAITransport(taskID: "task-i2v", videoURL: "https://kling.example.com/i2v.mp4")
    let provider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "kling-token", transport: transport))
    let model = try provider.videoModel("kling-v2.5-turbo-i2v")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "animate",
        aspectRatio: "1:1",
        durationSeconds: 5,
        image: ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png"),
        providerOptions: [
            "klingai": .object([
                "mode": "std",
                "imageTail": "https://example.com/end.png",
                "negativePrompt": "blur",
                "staticMask": "mask-b64",
                "dynamicMasks": .array([.object(["mask": "mask-1", "trajectories": .array([.object(["x": 1, "y": 2])])])]),
                "elementList": .array([.object(["element_id": 7])]),
                "voiceList": .array([.object(["voice_id": "voice-1"])]),
                "watermarkEnabled": true,
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ]
    ))

    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "aspectRatio", message: "KlingAI image-to-video does not support aspectRatio. The output dimensions are determined by the input image.")
    ])
    let requests = await transport.requests()
    #expect(requests[0].url.absoluteString == "https://api-singapore.klingai.com/v1/videos/image2video")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["model_name"]?.stringValue == "kling-v2-5-turbo")
    #expect(body["image"]?.stringValue == Data([137, 80, 78, 71]).base64EncodedString())
    #expect(body["image_tail"]?.stringValue == "https://example.com/end.png")
    #expect(body["negative_prompt"]?.stringValue == "blur")
    #expect(body["static_mask"]?.stringValue == "mask-b64")
    #expect(body["dynamic_masks"]?[0]?["trajectories"]?[0]?["x"]?.intValue == 1)
    #expect(body["element_list"]?[0]?["element_id"]?.intValue == 7)
    #expect(body["voice_list"]?[0]?["voice_id"]?.stringValue == "voice-1")
    #expect(body["watermark_info"]?["enabled"]?.boolValue == true)
    #expect(body["aspect_ratio"] == nil)
}

@Test func klingAIMotionControlMapsRequiredOptionsAndWarnings() async throws {
    let transport = klingAITransport(taskID: "task-motion", videoURL: "https://kling.example.com/motion.mp4")
    let provider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "kling-token", transport: transport))
    let model = try provider.videoModel("kling-v3.0-motion-control")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "match action",
        aspectRatio: "16:9",
        durationSeconds: 8,
        image: ImageInputFile(url: "https://example.com/person.png"),
        providerOptions: [
            "klingai": .object([
                "videoUrl": "https://example.com/reference.mp4",
                "characterOrientation": "image",
                "mode": "std",
                "keepOriginalSound": "no",
                "watermarkEnabled": true,
                "elementList": .array([.object(["element_id": 3])]),
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ]
    ))

    #expect(result.warnings.map(\.feature) == ["aspectRatio", "duration"])
    let requests = await transport.requests()
    #expect(requests[0].url.absoluteString == "https://api-singapore.klingai.com/v1/videos/motion-control")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["model_name"]?.stringValue == "kling-v3")
    #expect(body["video_url"]?.stringValue == "https://example.com/reference.mp4")
    #expect(body["character_orientation"]?.stringValue == "image")
    #expect(body["mode"]?.stringValue == "std")
    #expect(body["image_url"]?.stringValue == "https://example.com/person.png")
    #expect(body["keep_original_sound"]?.stringValue == "no")
    #expect(body["watermark_info"]?["enabled"]?.boolValue == true)
    #expect(body["element_list"]?[0]?["element_id"]?.intValue == 3)
    #expect(body["aspect_ratio"] == nil)
    #expect(body["duration"] == nil)
}

@Test func klingAIPollsOnlyAfterConfiguredIntervalLikeUpstream() async throws {
    let transport = klingAITransport(taskID: "delayed-task", videoURL: "https://kling.example.com/delayed.mp4")
    let provider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "kling-token", transport: transport))
    let model = try provider.videoModel("kling-v2.6-t2v")

    let task = Task {
        try await model.generateVideo(VideoGenerationRequest(
            prompt: "delayed poll",
            providerOptions: ["klingai": .object([
                "mode": .string("std"),
                "pollIntervalMs": .number(100),
                "pollTimeoutMs": .number(1_000)
            ])]
        ))
    }

    try await Task.sleep(nanoseconds: 20_000_000)
    #expect((await transport.requests()).count == 1)

    let result = try await task.value
    #expect(result.urls == ["https://kling.example.com/delayed.mp4"])
    #expect((await transport.requests()).count == 2)
}

@Test func klingAIRejectsUnknownModelsAndMissingMotionOptions() async throws {
    let provider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "kling-token", transport: klingAITransport()))
    let unknownModel = try provider.videoModel("unknown-model")

    await #expect(throws: AIError.self) {
        _ = try await unknownModel.generateVideo(VideoGenerationRequest(prompt: "scene"))
    }

    let motionModel = try provider.videoModel("kling-v2.6-motion-control")
    await #expect(throws: AIError.self) {
        _ = try await motionModel.generateVideo(VideoGenerationRequest(prompt: "missing"))
    }
}

private func klingAITransport(taskID: String = "task-1", videoID: String = "vid-1", videoURL: String = "https://kling.example.com/video.mp4", headers: [String: String] = [:]) -> RecordingTransport {
    RecordingTransport(responses: [
        jsonResponse(#"{"code":0,"message":"ok","data":{"task_id":"\#(taskID)","task_status":"submitted"}}"#),
        jsonResponse(
            #"{"code":0,"message":"ok","data":{"task_id":"\#(taskID)","task_status":"succeed","task_result":{"videos":[{"id":"\#(videoID)","url":"\#(videoURL)","watermark_url":"https://kling.example.com/video-watermark.mp4","duration":"5.0"}]}}}"#,
            headers: headers
        )
    ])
}
