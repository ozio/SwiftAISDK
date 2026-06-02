import Foundation
import Testing
@testable import SwiftAISDK

@Test func alibabaVideoUsesDashScopeAsyncTaskAPI() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"output":{"task_status":"PENDING","task_id":"task-1"},"request_id":"req-1"}"#),
        jsonResponse(#"{"output":{"task_id":"task-1","task_status":"SUCCEEDED","video_url":"https://dashscope.example.com/video.mp4","actual_prompt":"cat running fast"},"usage":{"duration":5,"size":"1280*720"},"request_id":"req-2"}"#)
    ])
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.videoModel("wan2.1-t2v-plus")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        durationSeconds: 5,
        count: 2,
        extraBody: ["resolution": "1280x720", "promptExtend": true, "watermark": false]
    ))

    #expect(result.urls == ["https://dashscope.example.com/video.mp4"])
    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "n", message: "Alibaba video models only support generating 1 video per call.")
    ])
    #expect(result.operationID == "task-1")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].url.absoluteString == "https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/video-generation/video-synthesis")
    #expect(requests[0].headers["Authorization"] == "Bearer dashscope-key")
    #expect(requests[0].headers["X-DashScope-Async"] == "enable")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["model"]?.stringValue == "wan2.1-t2v-plus")
    #expect(body["input"]?["prompt"]?.stringValue == "cat running")
    #expect(body["parameters"]?["duration"]?.intValue == 5)
    #expect(body["parameters"]?["size"]?.stringValue == "1280*720")
    #expect(body["parameters"]?["prompt_extend"]?.boolValue == true)
    #expect(body["parameters"]?["watermark"]?.boolValue == false)
    #expect(body["parameters"]?["n"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://dashscope-intl.aliyuncs.com/api/v1/tasks/task-1")
}

@Test func alibabaVideoMapsNestedI2VAndR2VOptions() async throws {
    let i2vTransport = RecordingTransport(responses: [
        jsonResponse(#"{"output":{"task_status":"PENDING","task_id":"task-i2v"},"request_id":"req-1"}"#),
        jsonResponse(#"{"output":{"task_id":"task-i2v","task_status":"SUCCEEDED","video_url":"https://dashscope.example.com/i2v.mp4"},"usage":{"duration":6,"output_video_duration":6,"SR":720,"size":"1280*720"},"request_id":"req-2"}"#)
    ])
    let i2vProvider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: i2vTransport))
    let i2vModel = try i2vProvider.videoModel("wan2.1-i2v-plus")

    _ = try await i2vModel.generateVideo(VideoGenerationRequest(
        prompt: "animate image",
        durationSeconds: 6,
        extraBody: [
            "alibaba": .object([
                "imageUrl": "https://example.com/start.png",
                "negativePrompt": "blur",
                "audioUrl": "https://example.com/sync.mp3",
                "resolution": "1280x720",
                "seed": 9,
                "promptExtend": true,
                "shotType": "single",
                "watermark": false,
                "audio": true,
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ]
    ))

    let i2vBody = try decodeJSONBody(try #require((await i2vTransport.requests()).first?.body))
    #expect(i2vBody["model"]?.stringValue == "wan2.1-i2v-plus")
    #expect(i2vBody["input"]?["prompt"]?.stringValue == "animate image")
    #expect(i2vBody["input"]?["img_url"]?.stringValue == "https://example.com/start.png")
    #expect(i2vBody["input"]?["negative_prompt"]?.stringValue == "blur")
    #expect(i2vBody["input"]?["audio_url"]?.stringValue == "https://example.com/sync.mp3")
    #expect(i2vBody["parameters"]?["duration"]?.intValue == 6)
    #expect(i2vBody["parameters"]?["resolution"]?.stringValue == "720P")
    #expect(i2vBody["parameters"]?["seed"]?.intValue == 9)
    #expect(i2vBody["parameters"]?["prompt_extend"]?.boolValue == true)
    #expect(i2vBody["parameters"]?["shot_type"]?.stringValue == "single")
    #expect(i2vBody["parameters"]?["watermark"]?.boolValue == false)
    #expect(i2vBody["parameters"]?["audio"]?.boolValue == true)
    #expect(i2vBody["parameters"]?["pollIntervalMs"] == nil)
    #expect(i2vBody["parameters"]?["pollTimeoutMs"] == nil)
    #expect(i2vBody["parameters"]?["alibaba"] == nil)

    let r2vTransport = RecordingTransport(responses: [
        jsonResponse(#"{"output":{"task_status":"PENDING","task_id":"task-r2v"},"request_id":"req-3"}"#),
        jsonResponse(#"{"output":{"task_id":"task-r2v","task_status":"SUCCEEDED","video_url":"https://dashscope.example.com/r2v.mp4"},"request_id":"req-4"}"#)
    ])
    let r2vProvider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: r2vTransport))
    let r2vModel = try r2vProvider.videoModel("wan2.1-r2v-plus")

    _ = try await r2vModel.generateVideo(VideoGenerationRequest(
        prompt: "character1 waves",
        extraBody: [
            "alibaba": .object([
                "referenceUrls": ["https://example.com/ref.png", "https://example.com/ref.mp4"],
                "resolution": "1920x1080",
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ]
    ))

    let r2vBody = try decodeJSONBody(try #require((await r2vTransport.requests()).first?.body))
    #expect(r2vBody["input"]?["reference_urls"]?[0]?.stringValue == "https://example.com/ref.png")
    #expect(r2vBody["input"]?["reference_urls"]?[1]?.stringValue == "https://example.com/ref.mp4")
    #expect(r2vBody["parameters"]?["size"]?.stringValue == "1920*1080")
    #expect(r2vBody["parameters"]?["referenceUrls"] == nil)
}

@Test func alibabaLanguageUsesNativeMessageShapeAndThinkingOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"chatcmpl-alibaba-1","created":1710000000,"model":"qwen3-max","choices":[{"message":{"role":"assistant","content":"dashscope text","reasoning_content":"thoughts"},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}}"#, headers: ["x-dashscope": "yes"]))
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.languageModel("qwen3-max")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .system("Be brief."),
            AIMessage(role: .user, content: [.text("Look"), .imageURL("https://example.com/image.png")])
        ],
        temperature: 0.2,
        topP: 0.8,
        topK: 10,
        frequencyPenalty: 0.5,
        seed: 123,
        maxOutputTokens: 128,
        extraBody: ["enableThinking": true, "thinkingBudget": 512, "topK": 20, "presencePenalty": 0.1]
    ))

    #expect(result.text == "dashscope text")
    #expect(result.reasoning == "thoughts")
    #expect(result.finishReason == "stop")
    #expect(result.usage?.totalTokens == 5)
    #expect(result.warnings == [AIWarning(type: "unsupported", feature: "frequencyPenalty")])
    #expect(result.responseMetadata.id == "chatcmpl-alibaba-1")
    #expect(result.responseMetadata.modelID == "qwen3-max")
    #expect(result.responseMetadata.headers["x-dashscope"] == "yes")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer dashscope-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "qwen3-max")
    #expect(body["messages"]?[0]?["role"]?.stringValue == "system")
    #expect(body["messages"]?[0]?["content"]?.stringValue == "Be brief.")
    #expect(body["messages"]?[1]?["role"]?.stringValue == "user")
    #expect(body["messages"]?[1]?["content"]?[0]?["type"]?.stringValue == "text")
    #expect(body["messages"]?[1]?["content"]?[0]?["text"]?.stringValue == "Look")
    #expect(body["messages"]?[1]?["content"]?[1]?["type"]?.stringValue == "image_url")
    #expect(body["messages"]?[1]?["content"]?[1]?["image_url"]?["url"]?.stringValue == "https://example.com/image.png")
    #expect(body["temperature"]?.doubleValue == 0.2)
    #expect(body["top_p"]?.doubleValue == 0.8)
    #expect(body["max_tokens"]?.intValue == 128)
    #expect(body["enable_thinking"] == true)
    #expect(body["thinking_budget"]?.intValue == 512)
    #expect(body["top_k"]?.intValue == 20)
    #expect(body["presence_penalty"]?.doubleValue == 0.1)
    #expect(body["seed"]?.intValue == 123)
    #expect(body["frequency_penalty"] == nil)
}

@Test func alibabaLanguageMapsProviderOptionsAndRichUsage() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"chatcmpl-cache-test","created":1770764844,"model":"qwen-plus","choices":[{"message":{"role":"assistant","content":"Hello"},"finish_reason":"stop"}],"usage":{"prompt_tokens":100,"completion_tokens":50,"total_tokens":150,"prompt_tokens_details":{"cached_tokens":80,"cache_creation_input_tokens":20},"completion_tokens_details":{"reasoning_tokens":10}}}"#))
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.languageModel("qwen-plus")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        tools: ["weather": ["type": "object", "properties": [:]]],
        providerOptions: [
            "alibaba": [
                "enableThinking": true,
                "thinkingBudget": 2048,
                "parallelToolCalls": false
            ]
        ],
        extraBody: [
            "alibaba": [
                "enableThinking": false,
                "thinkingBudget": 1024,
                "parallelToolCalls": true,
                "topK": 7,
                "presencePenalty": 0.2
            ]
        ]
    ))

    #expect(result.warnings.isEmpty)
    #expect(result.usage?.inputTokens == 100)
    #expect(result.usage?.outputTokens == 50)
    #expect(result.usage?.totalTokens == 150)
    #expect(result.usage?.inputTokensNoCache == 0)
    #expect(result.usage?.inputTokensCacheRead == 80)
    #expect(result.usage?.inputTokensCacheWrite == 20)
    #expect(result.usage?.outputTextTokens == 40)
    #expect(result.usage?.outputReasoningTokens == 10)
    #expect(result.usage?.rawValue?["prompt_tokens_details"]?["cache_creation_input_tokens"]?.intValue == 20)
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["enable_thinking"]?.boolValue == true)
    #expect(body["thinking_budget"]?.intValue == 2048)
    #expect(body["parallel_tool_calls"]?.boolValue == false)
    #expect(body["top_k"]?.intValue == 7)
    #expect(body["presence_penalty"]?.doubleValue == 0.2)
    #expect(body["alibaba"] == nil)
    #expect(body["enableThinking"] == nil)
    #expect(body["thinkingBudget"] == nil)
    #expect(body["parallelToolCalls"] == nil)
}

@Test func alibabaLanguageProviderOptionsValidateAndStripLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}"#))
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.languageModel("qwen-plus")

    await #expect(throws: AIError.self) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], providerOptions: ["alibaba": false]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], providerOptions: ["alibaba": ["thinkingBudget": 0]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], providerOptions: ["alibaba": ["enableThinking": nil]]))
    }

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        providerOptions: [
            "openai": ["enableThinking": true],
            "alibaba": [
                "enableThinking": true,
                "parallelToolCalls": false,
                "topK": 99
            ]
        ],
        extraBody: ["topK": 7]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["enable_thinking"]?.boolValue == true)
    #expect(body["parallel_tool_calls"] == nil)
    #expect(body["top_k"]?.intValue == 7)
    #expect(body["openai"] == nil)
}

@Test func alibabaLanguageWarnsForUnsupportedPartsProviderToolsAndToolChoice() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}"#))
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.languageModel("qwen-plus")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .user, content: [
                .text("Read this."),
                .data(mimeType: "text/plain", data: Data("not-image".utf8))
            ])
        ],
        tools: ["alibaba.search": ["type": "provider", "id": "alibaba.search"]],
        toolChoice: ["type": "provider"]
    ))

    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "user message part type: file"),
        AIWarning(type: "unsupported", feature: "provider-defined tool alibaba.search"),
        AIWarning(type: "unsupported", feature: "tool choice type: provider")
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["messages"]?[0]?["content"]?.arrayValue?.count == 1)
    #expect(body["tools"] == nil)
    #expect(body["tool_choice"] == nil)
}

@Test func alibabaLanguageMapsStandardResponseFormatToolsAndToolHistory() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}}"#))
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.languageModel("qwen3-max")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            .user("Weather?"),
            .assistant(toolCalls: [
                AIToolCall(id: "call_weather", name: "weather", arguments: "{\"location\":\"Paris\"}")
            ]),
            .toolResult(AIToolResult(
                toolCallID: "call_weather",
                toolName: "weather",
                result: ["ignored": true],
                modelOutput: ["type": "json", "value": ["forecast": "sunny"]]
            ))
        ],
        responseFormat: .json(
            schema: [
                "type": "object",
                "properties": ["forecast": ["type": "string"]],
                "required": ["forecast"]
            ],
            name: "weather_answer",
            description: "Weather answer"
        ),
        reasoning: "medium",
        tools: [
            "weather": [
                "type": "object",
                "description": "Gets the weather",
                "properties": ["location": ["type": "string"]],
                "required": ["location"],
                "strict": true
            ]
        ],
        toolChoice: ["type": "tool", "toolName": "weather"],
        extraBody: ["parallelToolCalls": false]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?["type"]?.stringValue == "json_schema")
    #expect(body["response_format"]?["json_schema"]?["name"]?.stringValue == "weather_answer")
    #expect(body["response_format"]?["json_schema"]?["description"]?.stringValue == "Weather answer")
    #expect(body["tools"]?[0]?["type"]?.stringValue == "function")
    #expect(body["tools"]?[0]?["function"]?["name"]?.stringValue == "weather")
    #expect(body["tools"]?[0]?["function"]?["description"]?.stringValue == "Gets the weather")
    #expect(body["tools"]?[0]?["function"]?["strict"]?.boolValue == true)
    #expect(body["tools"]?[0]?["function"]?["parameters"]?["strict"] == nil)
    #expect(body["tool_choice"]?["type"]?.stringValue == "function")
    #expect(body["tool_choice"]?["function"]?["name"]?.stringValue == "weather")
    #expect(body["parallel_tool_calls"]?.boolValue == false)
    #expect(body["enable_thinking"]?.boolValue == true)
    #expect(body["thinking_budget"]?.intValue == 4915)
    #expect(body["messages"]?[1]?["tool_calls"]?[0]?["id"]?.stringValue == "call_weather")
    #expect(body["messages"]?[1]?["tool_calls"]?[0]?["function"]?["name"]?.stringValue == "weather")
    #expect(body["messages"]?[2]?["role"]?.stringValue == "tool")
    #expect(body["messages"]?[2]?["tool_call_id"]?.stringValue == "call_weather")
    #expect(body["messages"]?[2]?["content"]?.stringValue == "{\"forecast\":\"sunny\"}")
}

@Test func alibabaLanguageStreamsReasoningAndUsageOnlyChunk() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"chatcmpl-alibaba-stream","created":1710000000,"model":"qwen3-max","choices":[{"delta":{"reasoning_content":"think"},"finish_reason":null}]}

    data: {"choices":[{"delta":{"content":"answer"},"finish_reason":"stop"}]}

    data: {"choices":[],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}

    data: [DONE]

    """))
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.languageModel("qwen3-max")

    var streamStartWarnings: [AIWarning]?
    var responseMetadata: AIResponseMetadata?
    var textLifecycle: [String] = []
    var reasoningLifecycle: [String] = []
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")], frequencyPenalty: 0.5)) {
        switch part {
        case let .streamStart(warnings):
            streamStartWarnings = warnings
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .textStart(id, _):
            textLifecycle.append("start:\(id)")
        case let .textDeltaPart(id, delta, _):
            textLifecycle.append("delta:\(id):\(delta)")
        case let .textEnd(id, _):
            textLifecycle.append("end:\(id)")
        case let .reasoningStart(id, _):
            reasoningLifecycle.append("start:\(id)")
        case let .reasoningDeltaPart(id, delta, _):
            reasoningLifecycle.append("delta:\(id):\(delta)")
        case let .reasoningEnd(id, _):
            reasoningLifecycle.append("end:\(id)")
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(streamStartWarnings == [AIWarning(type: "unsupported", feature: "frequencyPenalty")])
    #expect(responseMetadata?.id == "chatcmpl-alibaba-stream")
    #expect(responseMetadata?.modelID == "qwen3-max")
    #expect(reasoningLifecycle == [
        "start:reasoning-0",
        "delta:reasoning-0:think",
        "end:reasoning-0"
    ])
    #expect(textLifecycle == [
        "start:0",
        "delta:0:answer",
        "end:0"
    ])
    #expect(finishReason == "stop")
    #expect(totalTokens == 3)
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
    #expect(body["stream_options"]?["include_usage"] == true)
    #expect(body["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
    #expect(body["frequency_penalty"] == nil)
}

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

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["input"]?["negative_prompt"] == nil)
    #expect(body["input"]?["reference_urls"]?[0]?.stringValue == "https://example.com/ref.png")
    #expect(body["parameters"]?["prompt_extend"] == nil)
    #expect(body["parameters"]?["customUnknown"] == nil)
    #expect(body["parameters"]?["openai"] == nil)
}
