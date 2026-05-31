import Foundation
import Testing
@testable import ai_sdk_port

@Test func blackForestLabsImageSubmitsAndPolls() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-1","polling_url":"https://api.bfl.ai/v1/get_result","cost":0.01,"input_mp":0.5,"output_mp":0.75}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://bfl.example.com/image.png","seed":42}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8))
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))
    let model = try provider.imageModel("flux-pro-1.1")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "1024x768",
        extraBody: [
            "promptUpsampling": true,
            "outputFormat": "png",
            "imagePromptStrength": 0.4,
            "safetyTolerance": 2,
            "webhookUrl": "https://hooks.example.com/bfl",
            "inputImage": "image-b64",
            "pollIntervalMillis": 1,
            "pollTimeoutMillis": 1000
        ]
    ))

    #expect(result.urls == ["https://bfl.example.com/image.png"])
    #expect(result.base64Images == [Data("png".utf8).base64EncodedString()])
    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].url.absoluteString == "https://api.bfl.ai/v1/flux-pro-1.1")
    #expect(requests[0].headers["x-key"] == "bfl-key")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["prompt"]?.stringValue == "cat")
    #expect(body["aspect_ratio"]?.stringValue == "4:3")
    #expect(body["width"]?.intValue == 1024)
    #expect(body["height"]?.intValue == 768)
    #expect(body["prompt_upsampling"]?.boolValue == true)
    #expect(body["output_format"]?.stringValue == "png")
    #expect(body["image_prompt_strength"]?.doubleValue == 0.4)
    #expect(body["safety_tolerance"]?.intValue == 2)
    #expect(body["webhook_url"]?.stringValue == "https://hooks.example.com/bfl")
    #expect(body["input_image"]?.stringValue == "image-b64")
    #expect(body["pollIntervalMillis"] == nil)
    #expect(body["pollTimeoutMillis"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api.bfl.ai/v1/get_result?id=bfl-1")
    #expect(requests[2].method == "GET")
    #expect(requests[2].url.absoluteString == "https://bfl.example.com/image.png")
}

@Test func blackForestLabsImageMapsFilesMaskAndNestedOptions() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-fill-1","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://bfl.example.com/fill.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("fill-png".utf8))
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))
    let model = try provider.imageModel("flux-pro-1.0-fill")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "replace background",
        size: "1280x720",
        files: [
            ImageInputFile(url: "https://example.com/input.png"),
            ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png")
        ],
        mask: ImageInputFile(data: Data([9, 8, 7]), mediaType: "image/png"),
        extraBody: [
            "blackForestLabs": .object([
                "width": 640,
                "height": 360,
                "seed": 123,
                "guidance": 2.5,
                "promptUpsampling": true,
                "outputFormat": "jpeg",
                "pollIntervalMillis": 1,
                "pollTimeoutMillis": 1000
            ])
        ]
    ))

    let requests = await transport.requests()
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["prompt"]?.stringValue == "replace background")
    #expect(body["aspect_ratio"]?.stringValue == "16:9")
    #expect(body["width"]?.intValue == 640)
    #expect(body["height"]?.intValue == 360)
    #expect(body["seed"]?.intValue == 123)
    #expect(body["guidance"]?.doubleValue == 2.5)
    #expect(body["prompt_upsampling"]?.boolValue == true)
    #expect(body["output_format"]?.stringValue == "jpeg")
    #expect(body["image"]?.stringValue == "https://example.com/input.png")
    #expect(body["image_2"]?.stringValue == Data([1, 2, 3]).base64EncodedString())
    #expect(body["mask"]?.stringValue == Data([9, 8, 7]).base64EncodedString())
    #expect(body["blackForestLabs"] == nil)
    #expect(body["pollIntervalMillis"] == nil)
    #expect(body["pollTimeoutMillis"] == nil)

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "too many",
            files: (0..<11).map { ImageInputFile(url: "https://example.com/\($0).png") }
        ))
    }
}

@Test func lumaImageSubmitsAndPollsGeneration() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"lum-1","state":"queued"}"#),
        jsonResponse(#"{"id":"lum-1","state":"completed","assets":{"image":"https://luma.example.com/image.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("luma-png".utf8))
    ])
    let provider = try AIProviders.luma(settings: ProviderSettings(apiKey: "luma-key", transport: transport))
    let model = try provider.imageModel("photon-1")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "1024x768",
        extraBody: [
            "referenceType": "character",
            "images": [
                ["url": "https://example.com/character-a.png", "id": "hero"],
                ["url": "https://example.com/character-b.png", "id": "hero"]
            ],
            "pollIntervalMillis": 1,
            "maxPollAttempts": 3,
            "additional_param": "value"
        ]
    ))

    #expect(result.urls == ["https://luma.example.com/image.png"])
    #expect(result.base64Images == [Data("luma-png".utf8).base64EncodedString()])
    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].url.absoluteString == "https://api.lumalabs.ai/dream-machine/v1/generations/image")
    #expect(requests[0].headers["Authorization"] == "Bearer luma-key")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["prompt"]?.stringValue == "cat")
    #expect(body["model"]?.stringValue == "photon-1")
    #expect(body["aspect_ratio"]?.stringValue == "4:3")
    #expect(body["additional_param"]?.stringValue == "value")
    #expect(body["pollIntervalMillis"] == nil)
    #expect(body["maxPollAttempts"] == nil)
    #expect(body["referenceType"] == nil)
    #expect(body["images"] == nil)
    #expect(body["character"]?["hero"]?["images"]?[0]?.stringValue == "https://example.com/character-a.png")
    #expect(body["character"]?["hero"]?["images"]?[1]?.stringValue == "https://example.com/character-b.png")
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api.lumalabs.ai/dream-machine/v1/generations/lum-1")
    #expect(requests[2].method == "GET")
    #expect(requests[2].url.absoluteString == "https://luma.example.com/image.png")
}

@Test func lumaImageMapsFilesAndNestedReferenceOptions() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"lum-1","state":"queued"}"#),
        jsonResponse(#"{"id":"lum-1","state":"completed","assets":{"image":"https://luma.example.com/image.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("luma-png".utf8))
    ])
    let provider = try AIProviders.luma(settings: ProviderSettings(apiKey: "luma-key", transport: transport))
    let model = try provider.imageModel("photon-1")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "A dog in this style",
        files: [ImageInputFile(url: "https://example.com/style.jpg")],
        extraBody: [
            "luma": .object([
                "referenceType": .string("style"),
                "images": .array([.object(["weight": .number(0.6)])]),
                "pollIntervalMillis": .number(1),
                "maxPollAttempts": .number(3),
                "additional_param": .string("value")
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["prompt"]?.stringValue == "A dog in this style")
    #expect(body["model"]?.stringValue == "photon-1")
    #expect(body["style"]?[0]?["url"]?.stringValue == "https://example.com/style.jpg")
    #expect(body["style"]?[0]?["weight"]?.doubleValue == 0.6)
    #expect(body["additional_param"]?.stringValue == "value")
    #expect(body["referenceType"] == nil)
    #expect(body["images"] == nil)
    #expect(body["pollIntervalMillis"] == nil)
    #expect(body["maxPollAttempts"] == nil)
    #expect(body["luma"] == nil)
}

@Test func lumaImageMapsModifyImageAndRejectsUnsupportedInputs() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"lum-1","state":"queued"}"#),
        jsonResponse(#"{"id":"lum-1","state":"completed","assets":{"image":"https://luma.example.com/image.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("luma-png".utf8))
    ])
    let provider = try AIProviders.luma(settings: ProviderSettings(apiKey: "luma-key", transport: transport))
    let model = try provider.imageModel("photon-1")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Transform flowers",
        files: [ImageInputFile(url: "https://example.com/input.jpg")],
        extraBody: ["luma": .object(["referenceType": .string("modify_image")])]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["modify_image"]?["url"]?.stringValue == "https://example.com/input.jpg")
    #expect(body["modify_image"]?["weight"]?.intValue == 1)

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "Masked edit",
            files: [ImageInputFile(url: "https://example.com/input.jpg")],
            mask: ImageInputFile(url: "https://example.com/mask.png")
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "Data edit",
            files: [ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png")]
        ))
    }
}

@Test func klingAIVideoCreatesTaskAndPolls() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"code":0,"message":"ok","data":{"task_id":"task-1","task_status":"submitted"}}"#),
        jsonResponse(#"{"code":0,"message":"ok","data":{"task_id":"task-1","task_status":"succeed","task_result":{"videos":[{"id":"vid-1","url":"https://kling.example.com/video.mp4","duration":"5"}]}}}"#)
    ])
    let provider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "kling-token", transport: transport))
    let model = try provider.videoModel("kling-v2.1-t2v")

    let result = try await model.generateVideo(VideoGenerationRequest(prompt: "cat running", aspectRatio: "16:9", durationSeconds: 5))

    #expect(result.urls == ["https://kling.example.com/video.mp4"])
    #expect(result.operationID == "task-1")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].url.absoluteString == "https://api-singapore.klingai.com/v1/videos/text2video")
    #expect(requests[0].headers["Authorization"] == "Bearer kling-token")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["model_name"]?.stringValue == "kling-v2-1")
    #expect(body["prompt"]?.stringValue == "cat running")
    #expect(body["aspect_ratio"]?.stringValue == "16:9")
    #expect(body["duration"]?.stringValue == "5")
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api-singapore.klingai.com/v1/videos/text2video/task-1")
}

@Test func klingAIVideoMapsNestedOptionsForT2VI2VAndMotionControl() async throws {
    let t2vTransport = RecordingTransport(responses: [
        jsonResponse(#"{"code":0,"message":"ok","data":{"task_id":"task-t2v","task_status":"submitted"}}"#),
        jsonResponse(#"{"code":0,"message":"ok","data":{"task_id":"task-t2v","task_status":"succeed","task_result":{"videos":[{"id":"vid-1","url":"https://kling.example.com/t2v.mp4"}]}}}"#)
    ])
    let t2vProvider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "kling-token", transport: t2vTransport))
    let t2vModel = try t2vProvider.videoModel("kling-v3.0-t2v")

    _ = try await t2vModel.generateVideo(VideoGenerationRequest(
        prompt: "scene",
        aspectRatio: "16:9",
        durationSeconds: 10,
        extraBody: [
            "klingai": .object([
                "mode": "pro",
                "negativePrompt": "blur",
                "sound": "on",
                "cfgScale": 0.7,
                "cameraControl": .object(["type": "simple"]),
                "multiShot": true,
                "shotType": "customize",
                "multiPrompt": .array([.object(["index": 1, "prompt": "intro", "duration": "5"])]),
                "voiceList": .array([.object(["voice_id": "voice-1"])]),
                "watermarkEnabled": false,
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ]
    ))

    let t2vBody = try decodeJSONBody(try #require((await t2vTransport.requests()).first?.body))
    #expect(t2vBody["model_name"]?.stringValue == "kling-v3")
    #expect(t2vBody["negative_prompt"]?.stringValue == "blur")
    #expect(t2vBody["sound"]?.stringValue == "on")
    #expect(t2vBody["cfg_scale"]?.doubleValue == 0.7)
    #expect(t2vBody["camera_control"]?["type"]?.stringValue == "simple")
    #expect(t2vBody["multi_shot"]?.boolValue == true)
    #expect(t2vBody["shot_type"]?.stringValue == "customize")
    #expect(t2vBody["multi_prompt"]?[0]?["prompt"]?.stringValue == "intro")
    #expect(t2vBody["voice_list"]?[0]?["voice_id"]?.stringValue == "voice-1")
    #expect(t2vBody["watermark_info"]?["enabled"]?.boolValue == false)
    #expect(t2vBody["klingai"] == nil)
    #expect(t2vBody["pollIntervalMs"] == nil)
    #expect(t2vBody["pollTimeoutMs"] == nil)

    let i2vTransport = RecordingTransport(responses: [
        jsonResponse(#"{"code":0,"message":"ok","data":{"task_id":"task-i2v","task_status":"submitted"}}"#),
        jsonResponse(#"{"code":0,"message":"ok","data":{"task_id":"task-i2v","task_status":"succeed","task_result":{"videos":[{"id":"vid-2","url":"https://kling.example.com/i2v.mp4"}]}}}"#)
    ])
    let i2vProvider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "kling-token", transport: i2vTransport))
    let i2vModel = try i2vProvider.videoModel("kling-v2.1-i2v")

    _ = try await i2vModel.generateVideo(VideoGenerationRequest(
        prompt: "animate",
        aspectRatio: "1:1",
        durationSeconds: 5,
        extraBody: [
            "klingai": .object([
                "imageUrl": "https://example.com/start.png",
                "imageTail": "https://example.com/end.png",
                "staticMask": "mask-b64",
                "dynamicMasks": .array([.object(["mask": "mask-1", "trajectories": .array([.object(["x": 1, "y": 2])])])]),
                "elementList": .array([.object(["element_id": 7])]),
                "watermarkEnabled": true,
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ]
    ))

    let i2vRequests = await i2vTransport.requests()
    #expect(i2vRequests[0].url.absoluteString == "https://api-singapore.klingai.com/v1/videos/image2video")
    let i2vBody = try decodeJSONBody(try #require(i2vRequests[0].body))
    #expect(i2vBody["image"]?.stringValue == "https://example.com/start.png")
    #expect(i2vBody["image_tail"]?.stringValue == "https://example.com/end.png")
    #expect(i2vBody["static_mask"]?.stringValue == "mask-b64")
    #expect(i2vBody["dynamic_masks"]?[0]?["mask"]?.stringValue == "mask-1")
    #expect(i2vBody["element_list"]?[0]?["element_id"]?.intValue == 7)
    #expect(i2vBody["watermark_info"]?["enabled"]?.boolValue == true)
    #expect(i2vBody["aspect_ratio"] == nil)
    #expect(i2vBody["imageUrl"] == nil)
    #expect(i2vBody["pollIntervalMs"] == nil)

    let motionTransport = RecordingTransport(responses: [
        jsonResponse(#"{"code":0,"message":"ok","data":{"task_id":"task-motion","task_status":"submitted"}}"#),
        jsonResponse(#"{"code":0,"message":"ok","data":{"task_id":"task-motion","task_status":"succeed","task_result":{"videos":[{"id":"vid-3","url":"https://kling.example.com/motion.mp4"}]}}}"#)
    ])
    let motionProvider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "kling-token", transport: motionTransport))
    let motionModel = try motionProvider.videoModel("kling-v2.6-motion-control")

    _ = try await motionModel.generateVideo(VideoGenerationRequest(
        prompt: "match action",
        extraBody: [
            "klingai": .object([
                "videoUrl": "https://example.com/reference.mp4",
                "characterOrientation": "image",
                "mode": "std",
                "imageUrl": "https://example.com/person.png",
                "keepOriginalSound": "no",
                "watermarkEnabled": true,
                "elementList": .array([.object(["element_id": 3])]),
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ]
    ))

    let motionRequests = await motionTransport.requests()
    #expect(motionRequests[0].url.absoluteString == "https://api-singapore.klingai.com/v1/videos/motion-control")
    let motionBody = try decodeJSONBody(try #require(motionRequests[0].body))
    #expect(motionBody["video_url"]?.stringValue == "https://example.com/reference.mp4")
    #expect(motionBody["character_orientation"]?.stringValue == "image")
    #expect(motionBody["mode"]?.stringValue == "std")
    #expect(motionBody["image_url"]?.stringValue == "https://example.com/person.png")
    #expect(motionBody["keep_original_sound"]?.stringValue == "no")
    #expect(motionBody["watermark_info"]?["enabled"]?.boolValue == true)
    #expect(motionBody["element_list"]?[0]?["element_id"]?.intValue == 3)

    await #expect(throws: AIError.self) {
        _ = try await motionModel.generateVideo(VideoGenerationRequest(prompt: "missing"))
    }
}

@Test func byteDanceVideoCreatesTaskAndPolls() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"task-1"}"#),
        jsonResponse(#"{"id":"task-1","model":"seedance","status":"succeeded","content":{"video_url":"https://bytedance.example.com/video.mp4"},"usage":{"completion_tokens":42}}"#)
    ])
    let provider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "ark-key", transport: transport))
    let model = try provider.videoModel("seedance-1-0-pro")

    let result = try await model.generateVideo(VideoGenerationRequest(prompt: "cat running", aspectRatio: "16:9", durationSeconds: 4))

    #expect(result.urls == ["https://bytedance.example.com/video.mp4"])
    #expect(result.operationID == "task-1")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].url.absoluteString == "https://ark.ap-southeast.bytepluses.com/api/v3/contents/generations/tasks")
    #expect(requests[0].headers["Authorization"] == "Bearer ark-key")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["model"]?.stringValue == "seedance-1-0-pro")
    #expect(body["content"]?[0]?["type"]?.stringValue == "text")
    #expect(body["content"]?[0]?["text"]?.stringValue == "cat running")
    #expect(body["ratio"]?.stringValue == "16:9")
    #expect(body["duration"]?.intValue == 4)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://ark.ap-southeast.bytepluses.com/api/v3/contents/generations/tasks/task-1")
}

@Test func byteDanceVideoMapsNestedOptionsReferenceMediaAndPolling() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"task-2"}"#),
        jsonResponse(#"{"id":"task-2","model":"seedance","status":"succeeded","content":{"video_url":"https://bytedance.example.com/with-refs.mp4"},"usage":{"completion_tokens":12}}"#)
    ])
    let provider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "ark-key", transport: transport))
    let model = try provider.videoModel("seedance-1-0-pro")

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        aspectRatio: "16:9",
        durationSeconds: 4,
        extraBody: [
            "bytedance": .object([
                "imageUrl": "https://example.com/start.png",
                "lastFrameImage": "https://example.com/end.png",
                "referenceImages": ["https://example.com/ref-1.png", "https://example.com/ref-2.png"],
                "referenceVideos": ["https://example.com/ref.mp4"],
                "referenceAudio": ["https://example.com/ref.mp3"],
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

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "seedance-1-0-pro")
    #expect(body["content"]?[0]?["type"]?.stringValue == "text")
    #expect(body["content"]?[1]?["image_url"]?["url"]?.stringValue == "https://example.com/start.png")
    #expect(body["content"]?[2]?["role"]?.stringValue == "last_frame")
    #expect(body["content"]?[2]?["image_url"]?["url"]?.stringValue == "https://example.com/end.png")
    #expect(body["content"]?[3]?["role"]?.stringValue == "reference_image")
    #expect(body["content"]?[4]?["image_url"]?["url"]?.stringValue == "https://example.com/ref-2.png")
    #expect(body["content"]?[5]?["video_url"]?["url"]?.stringValue == "https://example.com/ref.mp4")
    #expect(body["content"]?[6]?["audio_url"]?["url"]?.stringValue == "https://example.com/ref.mp3")
    #expect(body["watermark"]?.boolValue == false)
    #expect(body["generate_audio"]?.boolValue == true)
    #expect(body["camera_fixed"]?.boolValue == true)
    #expect(body["return_last_frame"]?.boolValue == true)
    #expect(body["service_tier"]?.stringValue == "flex")
    #expect(body["draft"]?.boolValue == true)
    #expect(body["seed"]?.intValue == 7)
    #expect(body["resolution"]?.stringValue == "720p")
    #expect(body["customFlag"]?.stringValue == "keep-me")
    #expect(body["bytedance"] == nil)
    #expect(body["imageUrl"] == nil)
    #expect(body["lastFrameImage"] == nil)
    #expect(body["referenceImages"] == nil)
    #expect(body["pollIntervalMs"] == nil)
    #expect(body["pollTimeoutMs"] == nil)
}
