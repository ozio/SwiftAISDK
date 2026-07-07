import Foundation
import Testing
@testable import SwiftAISDK

@Test func alibabaLanguageParsesToolCalls() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"role":"assistant","content":"","tool_calls":[{"id":"call_weather","index":0,"type":"function","function":{"name":"weather","arguments":"{\"location\":\"San Francisco\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":9,"completion_tokens":4,"total_tokens":13}}"#))
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.languageModel("qwen3-max")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Weather?")]))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.usage?.totalTokens == 13)
    #expect(result.toolCalls.count == 1)
    #expect(result.toolCalls[0].id == "call_weather")
    #expect(result.toolCalls[0].name == "weather")
    #expect(try decodeJSONBody(Data(result.toolCalls[0].arguments.utf8))["location"]?.stringValue == "San Francisco")
}

@Test func alibabaLanguageGeneratesMissingToolCallIDLikeUpstreamV4() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"role":"assistant","content":"","tool_calls":[{"index":0,"type":"function","function":{"name":"weather","arguments":"{\"location\":\"San Francisco\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":9,"completion_tokens":4,"total_tokens":13}}"#))
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.languageModel("qwen3-max")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Weather?")]))

    #expect(result.toolCalls.count == 1)
    #expect(result.toolCalls[0].id.count == 16)
    #expect(result.toolCalls[0].id != "tool-call-0")
    #expect(result.toolCalls[0].name == "weather")
}

@Test func alibabaLanguageMapsMissingUsageToEmptyUsageLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop","index":0}]}"#))
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.languageModel("qwen-plus")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "ok")
    #expect(result.usage == TokenUsage(inputTokensNoCache: 0, inputTokensCacheWrite: 0))
}
@Test func alibabaLanguageStreamsFragmentedToolCalls() async throws {
    let transport = RecordingTransport(response: sseResponse(#"""
    data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_weather","type":"function","function":{"name":"weather","arguments":"{\"location\":"}}]},"finish_reason":null}]}

    data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"San Francisco\"}"}}]},"finish_reason":"tool_calls"}]}

    data: {"choices":[],"usage":{"prompt_tokens":9,"completion_tokens":4,"total_tokens":13}}

    data: [DONE]

    """#))
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.languageModel("qwen3-max")

    var deltas: [String] = []
    var inputLifecycle: [String] = []
    var finalCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Weather?")])) {
        switch part {
        case let .toolInputStart(id, name, _, _, _, _):
            inputLifecycle.append("start:\(id):\(name)")
        case let .toolInputDelta(id, delta, _):
            inputLifecycle.append("delta:\(id):\(delta)")
        case let .toolInputEnd(id, _):
            inputLifecycle.append("end:\(id)")
        case let .toolCallDelta(_, _, argumentsDelta, _):
            deltas.append(argumentsDelta)
        case let .toolCall(call):
            finalCall = call
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(deltas == ["{\"location\":", "\"San Francisco\"}"])
    #expect(inputLifecycle == [
        "start:call_weather:weather",
        "delta:call_weather:{\"location\":",
        "delta:call_weather:\"San Francisco\"}",
        "end:call_weather"
    ])
    #expect(finalCall?.id == "call_weather")
    #expect(finalCall?.name == "weather")
    #expect(try decodeJSONBody(Data((try #require(finalCall)).arguments.utf8))["location"]?.stringValue == "San Francisco")
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 13)
}
@Test func alibabaLanguageStreamsErrorChunksAndParseErrorsAsErrorPartsLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse(#"""
    data: {"error":{"message":"Stream failed","code":"InternalError","type":"server_error"}}

    data: not-json

    data: [DONE]

    """#))
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.languageModel("qwen-plus")

    var errors: [String] = []
    var finishReason: String?
    var usage: TokenUsage?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .error(message, _):
            errors.append(message)
        case let .finish(reason, finalUsage):
            finishReason = reason
            usage = finalUsage
        default:
            break
        }
    }

    #expect(errors.first == "Stream failed")
    #expect(errors.count == 2)
    #expect(finishReason == "error")
    #expect(usage == TokenUsage(inputTokensNoCache: 0, inputTokensCacheWrite: 0))
}
@Test func alibabaLanguageStreamGeneratesMissingFirstToolDeltaIDLikeUpstreamV4() async throws {
    let transport = RecordingTransport(response: sseResponse(#"""
    data: {"choices":[{"delta":{"tool_calls":[{"index":0,"type":"function","function":{"name":"weather","arguments":"{}"}}]},"finish_reason":null,"index":0}]}

    data: [DONE]

    """#))
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.languageModel("qwen-plus")

    var inputStartID: String?
    var finalCall: AIToolCall?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Weather?")])) {
        switch part {
        case let .toolInputStart(id, name, _, _, _, _):
            inputStartID = id
            #expect(name == "weather")
        case let .toolCall(call):
            finalCall = call
        default:
            break
        }
    }

    let id = try #require(inputStartID)
    #expect(id.count == 16)
    #expect(id != "tool-call-0")
    #expect(finalCall?.id == id)
    #expect(finalCall?.name == "weather")
}
@Test func alibabaVideoMapsStandardFieldsProviderOptionsWarningsAndMetadata() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"output":{"task_status":"PENDING","task_id":"task-i2v-standard"},"request_id":"req-1"}"#),
        jsonResponse(#"{"output":{"task_id":"task-i2v-standard","task_status":"SUCCEEDED","video_url":"https://dashscope.example.com/standard.mp4","actual_prompt":"animated standard image"},"usage":{"duration":4,"output_video_duration":4,"SR":720,"size":"1280*720"},"request_id":"req-2"}"#, headers: ["x-dashscope-task": "done"])
    ])
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.videoModel("wan2.1-i2v-plus")
    let imageData = Data("png-bytes".utf8)

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "animate",
        aspectRatio: "16:9",
        durationSeconds: 4,
        image: ImageInputFile(data: imageData, mediaType: "image/png"),
        resolution: "1280x720",
        fps: 24,
        seed: 42,
        providerOptions: [
            "alibaba": [
                "negativePrompt": "blur",
                "promptExtend": true,
                "watermark": false,
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ]
        ]
    ))

    #expect(result.urls == ["https://dashscope.example.com/standard.mp4"])
    #expect(result.operationID == "task-i2v-standard")
    #expect(result.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "aspectRatio",
            message: "Alibaba video models use explicit size/resolution dimensions. Use the resolution option or providerOptions.alibaba for size control."
        ),
        AIWarning(
            type: "unsupported",
            feature: "fps",
            message: "Alibaba video models do not support custom FPS."
        )
    ])
    #expect(result.providerMetadata["alibaba"]?["taskId"]?.stringValue == "task-i2v-standard")
    #expect(result.providerMetadata["alibaba"]?["videoUrl"]?.stringValue == "https://dashscope.example.com/standard.mp4")
    #expect(result.providerMetadata["alibaba"]?["actualPrompt"]?.stringValue == "animated standard image")
    #expect(result.providerMetadata["alibaba"]?["usage"]?["duration"]?.intValue == 4)
    #expect(result.providerMetadata["alibaba"]?["usage"]?["outputVideoDuration"]?.intValue == 4)
    #expect(result.providerMetadata["alibaba"]?["usage"]?["resolution"]?.intValue == 720)
    #expect(result.providerMetadata["alibaba"]?["usage"]?["size"]?.stringValue == "1280*720")
    #expect(result.responseMetadata.headers["x-dashscope-task"] == "done")
    #expect(result.responseMetadata.modelID == "wan2.1-i2v-plus")

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["input"]?["img_url"]?.stringValue == imageData.base64EncodedString())
    #expect(body["input"]?["negative_prompt"]?.stringValue == "blur")
    #expect(body["parameters"]?["duration"]?.intValue == 4)
    #expect(body["parameters"]?["resolution"]?.stringValue == "720P")
    #expect(body["parameters"]?["seed"]?.intValue == 42)
    #expect(body["parameters"]?["prompt_extend"]?.boolValue == true)
    #expect(body["parameters"]?["watermark"]?.boolValue == false)
}
@Test func alibabaVideoProviderOptionsValidateScopeAndNullishLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"output":{"task_status":"PENDING","task_id":"task-r2v"},"request_id":"req-1"}"#),
        jsonResponse(#"{"output":{"task_id":"task-r2v","task_status":"SUCCEEDED","video_url":"https://dashscope.example.com/r2v.mp4"},"request_id":"req-2"}"#)
    ])
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.videoModel("wan2.1-r2v-plus")

    await #expect(throws: AIError.self) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "wave", providerOptions: ["alibaba": false]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "wave", providerOptions: ["alibaba": ["shotType": "wide"]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "wave", providerOptions: ["alibaba": ["pollIntervalMs": 0]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "wave", providerOptions: ["alibaba": ["referenceUrls": [1, 2]]]))
    }

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "wave",
        providerOptions: ["alibaba": .null],
        extraBody: ["alibaba": ["negativePrompt": "raw negative", "pollIntervalMs": 1, "pollTimeoutMs": 1_000]]
    ))
    var body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["input"]?["negative_prompt"]?.stringValue == "raw negative")

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "wave",
        providerOptions: [
            "openai": ["negativePrompt": "ignored"],
            "alibaba": [
                "negativePrompt": nil,
                "referenceUrls": ["https://example.com/ref.png"],
                "promptExtend": nil,
                "customUnknown": "kept",
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1_000
            ]
        ]
    ))

    body = try decodeJSONBody(try #require((await transport.requests())[2].body))
    #expect(body["input"]?["negative_prompt"] == nil)
    #expect(body["input"]?["reference_urls"]?[0]?.stringValue == "https://example.com/ref.png")
    #expect(body["parameters"]?["prompt_extend"] == nil)
    #expect(body["parameters"]?["customUnknown"] == nil)
    #expect(body["parameters"]?["openai"] == nil)
}

@Test func alibabaVideoMapsFrameImagesLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"output":{"task_status":"PENDING","task_id":"task-frame-images"},"request_id":"req-1"}"#),
        jsonResponse(#"{"output":{"task_id":"task-frame-images","task_status":"SUCCEEDED","video_url":"https://dashscope.example.com/frame-images.mp4"},"request_id":"req-2"}"#)
    ])
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.videoModel("wan2.6-i2v")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "animate",
        image: ImageInputFile(url: "https://example.com/legacy-start.png"),
        frameImages: [
            VideoFrameImage(image: ImageInputFile(url: "https://example.com/first-frame.png"), frameType: .firstFrame),
            VideoFrameImage(image: ImageInputFile(url: "https://example.com/last-frame.png"), frameType: .lastFrame)
        ],
        providerOptions: ["alibaba": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["input"]?["img_url"]?.stringValue == "https://example.com/first-frame.png")
    #expect(result.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "frameImages",
        message: "Alibaba video models do not support last_frame frameImages. The last_frame image will be ignored."
    )))
}

@Test func alibabaVideoMapsFileFirstFrameLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"output":{"task_status":"PENDING","task_id":"task-file-frame"},"request_id":"req-1"}"#),
        jsonResponse(#"{"output":{"task_id":"task-file-frame","task_status":"SUCCEEDED","video_url":"https://dashscope.example.com/file-frame.mp4"},"request_id":"req-2"}"#)
    ])
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.videoModel("wan2.6-i2v")

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "animate",
        frameImages: [
            VideoFrameImage(image: ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png"), frameType: .firstFrame)
        ],
        providerOptions: ["alibaba": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["input"]?["img_url"]?.stringValue == Data([137, 80, 78, 71]).base64EncodedString())
}

@Test func alibabaVideoMapsInputReferencesForR2VLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"output":{"task_status":"PENDING","task_id":"task-r2v-refs"},"request_id":"req-1"}"#),
        jsonResponse(#"{"output":{"task_id":"task-r2v-refs","task_status":"SUCCEEDED","video_url":"https://dashscope.example.com/r2v-refs.mp4"},"request_id":"req-2"}"#)
    ])
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.videoModel("wan2.6-r2v")

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "animate",
        inputReferences: [ImageInputFile(url: "https://example.com/reference.png")],
        providerOptions: [
            "alibaba": [
                "referenceUrls": ["https://example.com/legacy-reference.png"],
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1_000
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["input"]?["reference_urls"]?.arrayValue?.map(\.stringValue) == ["https://example.com/reference.png"])
}

@Test func alibabaVideoWarnsAndSkipsUnsupportedInputReferencesLikeUpstream() async throws {
    let r2vTransport = RecordingTransport(responses: [
        jsonResponse(#"{"output":{"task_status":"PENDING","task_id":"task-r2v-file-ref"},"request_id":"req-1"}"#),
        jsonResponse(#"{"output":{"task_id":"task-r2v-file-ref","task_status":"SUCCEEDED","video_url":"https://dashscope.example.com/r2v-file-ref.mp4"},"request_id":"req-2"}"#)
    ])
    let r2vProvider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: r2vTransport))
    let r2vResult = try await r2vProvider.videoModel("wan2.6-r2v").generateVideo(VideoGenerationRequest(
        prompt: "animate",
        inputReferences: [ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png")],
        providerOptions: ["alibaba": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]]
    ))

    var body = try decodeJSONBody(try #require((await r2vTransport.requests()).first?.body))
    #expect(body["input"]?["reference_urls"] == nil)
    #expect(r2vResult.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "inputReferences",
        message: "Alibaba R2V inputReferences only support URL references. Non-URL references will be ignored."
    )))

    let i2vTransport = RecordingTransport(responses: [
        jsonResponse(#"{"output":{"task_status":"PENDING","task_id":"task-i2v-ref"},"request_id":"req-1"}"#),
        jsonResponse(#"{"output":{"task_id":"task-i2v-ref","task_status":"SUCCEEDED","video_url":"https://dashscope.example.com/i2v-ref.mp4"},"request_id":"req-2"}"#)
    ])
    let i2vProvider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: i2vTransport))
    let i2vResult = try await i2vProvider.videoModel("wan2.6-i2v").generateVideo(VideoGenerationRequest(
        prompt: "animate",
        inputReferences: [ImageInputFile(url: "https://example.com/reference.png")],
        providerOptions: ["alibaba": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]]
    ))

    body = try decodeJSONBody(try #require((await i2vTransport.requests()).first?.body))
    #expect(body["input"]?["reference_urls"] == nil)
    #expect(i2vResult.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "inputReferences",
        message: "Alibaba inputReferences are only supported by R2V video models."
    )))
}

@Test func alibabaVideoUsesUpstreamFlatErrorMessageSchema() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 400,
        headers: ["x-dashscope": "bad"],
        body: Data(#"{"code":"InvalidParameter","message":"Bad video request","request_id":"req-bad"}"#.utf8)
    ))
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.videoModel("wan2.6-t2v")

    await #expect(throws: AIError.apiCall(
        provider: "alibaba.video",
        statusCode: 400,
        body: "Bad video request",
        headers: ["x-dashscope": "bad"]
    )) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "wave"))
    }
}

@Test func alibabaVideoMapsWan27ReferenceMediaRatioAndWarningsLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"output":{"task_status":"PENDING","task_id":"task-wan27-r2v"},"request_id":"req-1"}"#),
        jsonResponse(#"{"output":{"task_id":"task-wan27-r2v","task_status":"SUCCEEDED","video_url":"https://dashscope.example.com/wan27-r2v.mp4"},"request_id":"req-2"}"#)
    ])
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.videoModel("wan2.7-r2v")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "Image 1 and Video 1 meet",
        aspectRatio: "9:16",
        frameImages: [
            VideoFrameImage(image: ImageInputFile(url: "https://example.com/opening-frame.png"), frameType: .firstFrame)
        ],
        inputReferences: [
            ImageInputFile(url: "https://example.com/character.png"),
            ImageInputFile(url: "https://example.com/motion.mp4"),
            ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png")
        ],
        resolution: "1920x1080",
        generateAudio: true,
        providerOptions: ["alibaba": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "wan2.7-r2v")
    #expect(body["input"]?["reference_urls"] == nil)
    #expect(body["input"]?["media"]?[0]?["type"]?.stringValue == "reference_image")
    #expect(body["input"]?["media"]?[0]?["url"]?.stringValue == "https://example.com/character.png")
    #expect(body["input"]?["media"]?[1]?["type"]?.stringValue == "reference_video")
    #expect(body["input"]?["media"]?[1]?["url"]?.stringValue == "https://example.com/motion.mp4")
    #expect(body["input"]?["media"]?[2]?["type"]?.stringValue == "reference_image")
    #expect(body["input"]?["media"]?[2]?["url"]?.stringValue == "data:image/png;base64,\(Data([137, 80, 78, 71]).base64EncodedString())")
    #expect(body["input"]?["media"]?[3]?["type"]?.stringValue == "first_frame")
    #expect(body["input"]?["media"]?[3]?["url"]?.stringValue == "https://example.com/opening-frame.png")
    #expect(body["parameters"]?["resolution"]?.stringValue == "1080P")
    #expect(body["parameters"]?["ratio"]?.stringValue == "9:16")
    #expect(body["parameters"]?["size"] == nil)
    #expect(body["parameters"]?["audio"] == nil)
    #expect(result.warnings.contains { $0.feature == "aspectRatio" } == false)
    #expect(result.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "generateAudio",
        message: "wan2.7 models always generate audio. The audio option was ignored."
    )))
}

@Test func alibabaVideoMapsWan27ProviderMediaOverrideAndT2VOptionsLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"output":{"task_status":"PENDING","task_id":"task-wan27-media"},"request_id":"req-1"}"#),
        jsonResponse(#"{"output":{"task_id":"task-wan27-media","task_status":"SUCCEEDED","video_url":"https://dashscope.example.com/wan27-media.mp4"},"request_id":"req-2"}"#),
        jsonResponse(#"{"output":{"task_status":"PENDING","task_id":"task-wan27-t2v"},"request_id":"req-3"}"#),
        jsonResponse(#"{"output":{"task_id":"task-wan27-t2v","task_status":"SUCCEEDED","video_url":"https://dashscope.example.com/wan27-t2v.mp4"},"request_id":"req-4"}"#)
    ])
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))

    _ = try await provider.videoModel("wan2.7-r2v-2026-06-12").generateVideo(VideoGenerationRequest(
        prompt: "Use explicit media",
        aspectRatio: "9:16",
        inputReferences: [ImageInputFile(url: "https://example.com/ignored.png")],
        providerOptions: [
            "alibaba": [
                "ratio": "16:9",
                "media": [
                    ["type": "reference_video", "url": "https://example.com/character.mp4", "referenceVoice": "https://example.com/voice.mp3"],
                    ["type": "first_frame", "url": "https://example.com/opening-frame.png"]
                ],
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1_000
            ]
        ]
    ))

    var body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["parameters"]?["ratio"]?.stringValue == "16:9")
    #expect(body["input"]?["media"]?[0]?["type"]?.stringValue == "reference_video")
    #expect(body["input"]?["media"]?[0]?["reference_voice"]?.stringValue == "https://example.com/voice.mp3")
    #expect(body["input"]?["media"]?[1]?["type"]?.stringValue == "first_frame")

    let t2vResult = try await provider.videoModel("wan2.7-t2v").generateVideo(VideoGenerationRequest(
        prompt: "wide cinematic",
        resolution: "1920x1080",
        generateAudio: false,
        providerOptions: ["alibaba": ["shotType": "multi", "pollIntervalMs": 1, "pollTimeoutMs": 1_000]]
    ))

    body = try decodeJSONBody(try #require((await transport.requests())[2].body))
    #expect(body["parameters"]?["resolution"]?.stringValue == "1080P")
    #expect(body["parameters"]?["ratio"]?.stringValue == "16:9")
    #expect(body["parameters"]?["size"] == nil)
    #expect(body["parameters"]?["audio"] == nil)
    #expect(body["parameters"]?["shot_type"] == nil)
    #expect(t2vResult.warnings.contains { $0.feature == "shotType" })
    #expect(t2vResult.warnings.contains { $0.feature == "generateAudio" })
}
