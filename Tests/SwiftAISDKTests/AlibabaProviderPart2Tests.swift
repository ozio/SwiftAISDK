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
@Test func alibabaLanguageStreamRequiresFirstToolDeltaIDAndNameLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse(#"""
    data: {"choices":[{"delta":{"tool_calls":[{"index":0,"type":"function","function":{"name":"weather","arguments":"{}"}}]},"finish_reason":null,"index":0}]}

    data: [DONE]

    """#))
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.languageModel("qwen-plus")

    await #expect(throws: AIError.invalidResponse(provider: "alibaba.chat", message: "Expected 'id' to be a string.")) {
        for try await _ in model.stream(LanguageModelRequest(messages: [.user("Weather?")])) {}
    }
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
