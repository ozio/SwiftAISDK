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
        extraBody: ["resolution": "1280x720", "promptExtend": true, "watermark": false]
    ))

    #expect(result.urls == ["https://dashscope.example.com/video.mp4"])
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
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"role":"assistant","content":"dashscope text","reasoning_content":"thoughts"},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}}"#))
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.languageModel("qwen3-max")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .system("Be brief."),
            AIMessage(role: .user, content: [.text("Look"), .imageURL("https://example.com/image.png")])
        ],
        temperature: 0.2,
        topP: 0.8,
        maxOutputTokens: 128,
        extraBody: ["enableThinking": true, "thinkingBudget": 512, "topK": 20, "presencePenalty": 0.1]
    ))

    #expect(result.text == "dashscope text")
    #expect(result.finishReason == "stop")
    #expect(result.usage?.totalTokens == 5)
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
}

@Test func alibabaLanguageStreamsReasoningAndUsageOnlyChunk() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"choices":[{"delta":{"reasoning_content":"think"},"finish_reason":null}]}

    data: {"choices":[{"delta":{"content":"answer"},"finish_reason":"stop"}]}

    data: {"choices":[],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}

    data: [DONE]

    """))
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: transport))
    let model = try provider.languageModel("qwen3-max")

    var text: [String] = []
    var reasoning: [String] = []
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textDelta(delta):
            text.append(delta)
        case let .reasoningDelta(delta):
            reasoning.append(delta)
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(reasoning == ["think"])
    #expect(text == ["answer"])
    #expect(finishReason == "stop")
    #expect(totalTokens == 3)
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
    #expect(body["stream_options"]?["include_usage"] == true)
    #expect(body["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
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
    var finalCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Weather?")])) {
        switch part {
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
    #expect(finalCall?.id == "call_weather")
    #expect(finalCall?.name == "weather")
    #expect(try decodeJSONBody(Data((try #require(finalCall)).arguments.utf8))["location"]?.stringValue == "San Francisco")
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 13)
}

@Test func prodiaLanguageUsesMultipartJobEndpoint() async throws {
    let imageBytes = Data("png-bytes".utf8)
    let transport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"job-language","state":{"current":"succeeded"},"metrics":{"elapsed":1.5}}"#.utf8)),
        (name: "output", contentType: "text/plain", body: Data("caption text".utf8)),
        (name: "output", contentType: "image/png", body: imageBytes)
    ]))
    let provider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-token", transport: transport))
    let model = try provider.languageModel("inference.nano-banana.img2img.v2")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .system("Use short captions."),
            AIMessage(role: .user, content: [.text("Describe this"), .data(mimeType: "image/png", data: imageBytes)])
        ],
        extraBody: ["aspectRatio": "1:1"]
    ))

    #expect(result.text == "caption text")
    #expect(result.finishReason == "stop")
    #expect(result.rawValue["parts"]?.arrayValue?.contains(where: { $0["base64"]?.stringValue == imageBytes.base64EncodedString() }) == true)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://inference.prodia.com/v2/job?price=true")
    #expect(request.headers["Authorization"] == "Bearer prodia-token")
    #expect(request.headers["Accept"] == "multipart/form-data")
    #expect(request.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=SwiftAISDK-") == true)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains(#""type":"inference.nano-banana.img2img.v2""#))
    #expect(bodyText.contains(#""prompt":"Use short captions.\nDescribe this""#))
    #expect(bodyText.contains(#""include_messages":true"#))
    #expect(bodyText.contains(#""aspect_ratio":"1:1""#))
    #expect(bodyText.contains("name=\"input\"; filename=\"input.png\""))
}

@Test func prodiaImageUsesMultipartJobEndpoint() async throws {
    let transport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"job-1","state":{"current":"succeeded"}}"#.utf8)),
        (name: "output", contentType: "image/png", body: Data("png".utf8))
    ]))
    let provider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-token", transport: transport))
    let model = try provider.imageModel("sdxl")

    let result = try await model.generateImage(ImageGenerationRequest(prompt: "cat", size: "1024x768"))

    #expect(result.base64Images == [Data("png".utf8).base64EncodedString()])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://inference.prodia.com/v2/job?price=true")
    #expect(request.headers["Authorization"] == "Bearer prodia-token")
    #expect(request.headers["Accept"] == "multipart/form-data; image/png")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["type"]?.stringValue == "sdxl")
    #expect(body["config"]?["prompt"]?.stringValue == "cat")
    #expect(body["config"]?["width"]?.intValue == 1024)
    #expect(body["config"]?["height"]?.intValue == 768)
}

@Test func prodiaVideoUsesMultipartJobEndpoint() async throws {
    let transport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"job-video","state":{"current":"succeeded"}}"#.utf8)),
        (name: "output", contentType: "video/mp4", body: Data("mp4".utf8))
    ]))
    let provider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-token", transport: transport))
    let model = try provider.videoModel("veo")

    let result = try await model.generateVideo(VideoGenerationRequest(prompt: "cat running"))

    #expect(result.operationID == "job-video")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://inference.prodia.com/v2/job?price=true")
    #expect(request.headers["Authorization"] == "Bearer prodia-token")
    #expect(request.headers["Accept"] == "multipart/form-data; video/mp4")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["type"]?.stringValue == "veo")
    #expect(body["config"]?["prompt"]?.stringValue == "cat running")
}

@Test func prodiaModelsMapNestedProviderOptions() async throws {
    let languageTransport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"job-language","state":{"current":"succeeded"}}"#.utf8)),
        (name: "output", contentType: "text/plain", body: Data("caption".utf8))
    ]))
    let languageProvider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-token", transport: languageTransport))
    let languageModel = try languageProvider.languageModel("inference.nano-banana.img2img.v2")

    _ = try await languageModel.generate(LanguageModelRequest(
        messages: [.user("Describe")],
        extraBody: ["prodia": .object(["aspectRatio": "16:9", "ignored": true])]
    ))

    let languageBodyText = String(data: try #require((await languageTransport.requests()).first?.body), encoding: .utf8) ?? ""
    #expect(languageBodyText.contains(#""aspect_ratio":"16:9""#))
    #expect(!languageBodyText.contains(#""ignored""#))
    #expect(!languageBodyText.contains(#""prodia""#))

    let imageTransport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"job-image","state":{"current":"succeeded"}}"#.utf8)),
        (name: "output", contentType: "image/png", body: Data("png".utf8))
    ]))
    let imageProvider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-token", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("sdxl")

    _ = try await imageModel.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "1024x768",
        extraBody: [
            "prodia": .object([
                "width": 512,
                "height": 512,
                "seed": 42,
                "steps": 4,
                "stylePreset": "cinematic",
                "loras": ["detail", "light"],
                "progressive": true,
                "ignored": "drop"
            ])
        ]
    ))

    let imageBody = try decodeJSONBody(try #require((await imageTransport.requests()).first?.body))
    #expect(imageBody["config"]?["width"]?.intValue == 512)
    #expect(imageBody["config"]?["height"]?.intValue == 512)
    #expect(imageBody["config"]?["seed"]?.intValue == 42)
    #expect(imageBody["config"]?["steps"]?.intValue == 4)
    #expect(imageBody["config"]?["style_preset"]?.stringValue == "cinematic")
    #expect(imageBody["config"]?["loras"]?[0]?.stringValue == "detail")
    #expect(imageBody["config"]?["progressive"]?.boolValue == true)
    #expect(imageBody["config"]?["stylePreset"] == nil)
    #expect(imageBody["config"]?["prodia"] == nil)
    #expect(imageBody["config"]?["ignored"] == nil)

    let videoTransport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"job-video","state":{"current":"succeeded"}}"#.utf8)),
        (name: "output", contentType: "video/mp4", body: Data("mp4".utf8))
    ]))
    let videoProvider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-token", transport: videoTransport))
    let videoModel = try videoProvider.videoModel("veo")

    _ = try await videoModel.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        extraBody: ["prodia": .object(["resolution": "720p", "seed": 12, "ignored": true])]
    ))

    let videoBody = try decodeJSONBody(try #require((await videoTransport.requests()).first?.body))
    #expect(videoBody["config"]?["prompt"]?.stringValue == "cat running")
    #expect(videoBody["config"]?["resolution"]?.stringValue == "720p")
    #expect(videoBody["config"]?["seed"]?.intValue == 12)
    #expect(videoBody["config"]?["prodia"] == nil)
    #expect(videoBody["config"]?["ignored"] == nil)
}

@Test func azureLanguageDefaultsToResponsesV1URLAndApiKeyHeader() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"azure response","usage":{"input_tokens":2,"output_tokens":3,"total_tokens":5}}"#))
    let provider = try AIProviders.azure(resourceName: "test-resource", apiVersion: "2025-04-01-preview", settings: ProviderSettings(
        apiKey: "azure-key",
        headers: ["Custom-Provider-Header": "provider"],
        transport: transport
    ))
    let model = try provider.languageModel("gpt-4.1-deployment")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        maxOutputTokens: 32,
        extraBody: [
            "azure": .object([
                "previousResponseId": .string("resp-azure"),
                "store": .bool(true)
            ]),
            "openai": .object([
                "previousResponseId": .string("resp-old"),
                "store": .bool(false)
            ])
        ],
        headers: ["Custom-Request-Header": "request"]
    ))

    #expect(result.text == "azure response")
    #expect(result.usage?.totalTokens == 5)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/responses?api-version=2025-04-01-preview")
    #expect(request.headers["api-key"] == "azure-key")
    #expect(request.headers["Custom-Provider-Header"] == "provider")
    #expect(request.headers["Custom-Request-Header"] == "request")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "gpt-4.1-deployment")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
    #expect(body["max_output_tokens"]?.intValue == 32)
    #expect(body["previous_response_id"]?.stringValue == "resp-azure")
    #expect(body["store"]?.boolValue == true)
    #expect(body["azure"] == nil)
    #expect(body["openai"] == nil)
    #expect(body["previousResponseId"] == nil)
}

@Test func azureCompletionMapsAzureProviderOptionsOverOpenAI() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"text":"azure completion","finish_reason":"stop"}],"usage":{"total_tokens":4}}
    """))
    let provider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: transport))
    let model = try provider.completionModel("completion-deployment")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Complete")],
        extraBody: [
            "openai": .object([
                "suffix": .string("openai-tail"),
                "echo": .bool(false)
            ]),
            "azure": .object([
                "suffix": .string("azure-tail"),
                "best_of": .number(2)
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/completions?api-version=v1")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "completion-deployment")
    #expect(body["suffix"]?.stringValue == "azure-tail")
    #expect(body["echo"]?.boolValue == false)
    #expect(body["best_of"]?.intValue == 2)
    #expect(body["azure"] == nil)
    #expect(body["openai"] == nil)
}

@Test func azureChatUsesExplicitChatCompletionURL() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"azure chat"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}"#))
    let provider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: transport))
    let model = try provider.chatModel("chat-deployment")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "azure chat")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/chat/completions?api-version=v1")
    #expect(request.headers["api-key"] == "azure-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "chat-deployment")
    #expect(body["messages"]?[0]?["content"]?.stringValue == "Hi")
}

@Test func azureProviderAliasesRouteToUpstreamEndpoints() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"azure responses"}"#),
        jsonResponse(#"{"choices":[{"message":{"content":"azure chat"},"finish_reason":"stop"}]}"#),
        jsonResponse(#"{"choices":[{"text":"azure completion","finish_reason":"stop"}]}"#)
    ])
    let provider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: transport))

    let languageModel = try provider.languageModel("responses-deployment")
    let responsesModel = try provider.responses("responses-deployment")
    let chatModel = try provider.chat("chat-deployment")
    let completionModel = try provider.completion("completion-deployment")
    let embeddingModel = try provider.embeddingModel("embedding-deployment")
    let imageModel = try provider.imageModel("image-deployment")
    let transcriptionModel = try provider.transcriptionModel("transcription-deployment")
    let speechModel = try provider.speechModel("speech-deployment")

    #expect(provider.providerID == "azure")
    #expect(languageModel.providerID == "azure.responses")
    #expect(responsesModel.providerID == "azure.responses")
    #expect(chatModel.providerID == "azure.chat")
    #expect(completionModel.providerID == "azure.completion")
    #expect(embeddingModel.providerID == "azure.embeddings")
    #expect(imageModel.providerID == "azure.image")
    #expect(transcriptionModel.providerID == "azure.transcription")
    #expect(speechModel.providerID == "azure.speech")

    let responsesResult = try await responsesModel.generate(LanguageModelRequest(messages: [.user("Hi")]))
    let chatResult = try await chatModel.generate(LanguageModelRequest(messages: [.user("Hi")]))
    let completionResult = try await completionModel.generate(LanguageModelRequest(messages: [.user("Finish")]))

    #expect(responsesResult.text == "azure responses")
    #expect(chatResult.text == "azure chat")
    #expect(completionResult.text == "azure completion")
    let requests = await transport.requests()
    #expect(requests[0].url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/responses?api-version=v1")
    #expect(requests[1].url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/chat/completions?api-version=v1")
    #expect(requests[2].url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/completions?api-version=v1")
}

@Test func azureOpenAIToolsHelpersMirrorOpenAIHostedToolFactories() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"azure tools"}"#))
    let provider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: transport))
    let model = try provider.responses("responses-deployment")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Search docs.")],
        tools: [
            "web_search": AzureOpenAITools.webSearch(searchContextSize: "low"),
            "file_search": AzureOpenAITools.fileSearch(vectorStoreIDs: ["vs_azure"], maxNumResults: 2),
            "code_interpreter": AzureOpenAITools.codeInterpreter(),
            "image_generation": AzureOpenAITools.imageGeneration(size: "1024x1024")
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.contains { $0["type"]?.stringValue == "web_search" && $0["search_context_size"]?.stringValue == "low" })
    #expect(tools.contains { $0["type"]?.stringValue == "file_search" && $0["vector_store_ids"]?[0]?.stringValue == "vs_azure" })
    #expect(tools.contains { $0["type"]?.stringValue == "code_interpreter" && $0["container"]?["type"]?.stringValue == "auto" })
    #expect(tools.contains { $0["type"]?.stringValue == "image_generation" && $0["size"]?.stringValue == "1024x1024" })
}

@Test func azureDeploymentBasedTranscriptionURLAndProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"azure transcript"}"#))
    let provider = try AIProviders.azure(
        resourceName: "test-resource",
        useDeploymentBasedURLs: true,
        settings: ProviderSettings(apiKey: "azure-key", transport: transport)
    )
    let model = try provider.transcriptionModel("whisper-1")

    let result = try await model.transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8), mimeType: "audio/wav", extraBody: ["timestampGranularities": ["word"]]))

    #expect(result.text == "azure transcript")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://test-resource.openai.azure.com/openai/deployments/whisper-1/audio/transcriptions?api-version=v1")
    #expect(request.headers["api-key"] == "azure-key")
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("verbose_json"))
    #expect(bodyText.contains("name=\"timestamp_granularities[]\""))
    #expect(bodyText.contains("word"))
}

@Test func azureImageAndSpeechUseOpenAIOptionMapping() async throws {
    let imageTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"azure-image"}]}"#))
    let imageProvider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("dalle-deployment")

    let image = try await imageModel.generateImage(ImageGenerationRequest(prompt: "cat", extraBody: ["outputFormat": "png", "outputCompression": 70]))

    #expect(image.base64Images == ["azure-image"])
    let imageRequest = try #require(await imageTransport.requests().first)
    #expect(imageRequest.url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/images/generations?api-version=v1")
    let imageBody = try decodeJSONBody(try #require(imageRequest.body))
    #expect(imageBody["response_format"]?.stringValue == "b64_json")
    #expect(imageBody["output_format"]?.stringValue == "png")
    #expect(imageBody["output_compression"]?.intValue == 70)

    let speechTransport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("mp3".utf8)))
    let speechProvider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: speechTransport))
    let speechModel = try speechProvider.speechModel("tts-deployment")

    _ = try await speechModel.speak(SpeechRequest(text: "Hello"))

    let speechRequest = try #require(await speechTransport.requests().first)
    #expect(speechRequest.url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/audio/speech?api-version=v1")
    let speechBody = try decodeJSONBody(try #require(speechRequest.body))
    #expect(speechBody["voice"]?.stringValue == "alloy")
    #expect(speechBody["response_format"]?.stringValue == "mp3")
}

@Test func azureImageMapsNestedOpenAIProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"azure-image"}]}"#))
    let provider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: transport))
    let model = try provider.imageModel("dalle-deployment")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "1024x1024",
        count: 1,
        extraBody: [
            "openai": .object([
                "style": .string("natural"),
                "outputFormat": .string("png")
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/images/generations?api-version=v1")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "dalle-deployment")
    #expect(body["n"]?.intValue == 1)
    #expect(body["style"]?.stringValue == "natural")
    #expect(body["output_format"]?.stringValue == "png")
    #expect(body["response_format"]?.stringValue == "b64_json")
    #expect(body["openai"] == nil)
    #expect(body["outputFormat"] == nil)
}

@Test func quiverAIImageGeneratesSVGAndForwardsOptions() async throws {
    let svg = #"<svg viewBox="0 0 10 10"><rect width="10" height="10"/></svg>"#
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"svg-gen-1","created":1713374400,"data":[{"svg":"\(svg.replacingOccurrences(of: "\"", with: "\\\""))","mime_type":"image/svg+xml"}],"usage":{"total_tokens":21,"input_tokens":12,"output_tokens":9}}
    """))
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", transport: transport))
    let model = try provider.imageModel("arrow-1")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "Draw a square icon.",
        count: 1,
        files: [
            ImageInputFile(url: "https://example.com/reference-1.png"),
            ImageInputFile(data: Data([4, 5, 6]), mediaType: "image/png")
        ],
        extraBody: [
            "instructions": "Use clean geometry.",
            "temperature": 0.4,
            "topP": 0.95,
            "presencePenalty": 0.2,
            "maxOutputTokens": 4096
        ]
    ))

    #expect(String(data: Data(base64Encoded: try #require(result.base64Images.first)) ?? Data(), encoding: .utf8) == svg)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.quiver.ai/v1/svgs/generations")
    #expect(request.headers["Authorization"] == "Bearer quiver-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "arrow-1")
    #expect(body["prompt"]?.stringValue == "Draw a square icon.")
    #expect(body["n"]?.intValue == 1)
    #expect(body["stream"]?.boolValue == false)
    #expect(body["instructions"]?.stringValue == "Use clean geometry.")
    #expect(body["temperature"]?.doubleValue == 0.4)
    #expect(body["top_p"]?.doubleValue == 0.95)
    #expect(body["presence_penalty"]?.doubleValue == 0.2)
    #expect(body["max_output_tokens"]?.intValue == 4096)
    #expect(body["references"]?[0]?["url"]?.stringValue == "https://example.com/reference-1.png")
    #expect(body["references"]?[1]?["base64"]?.stringValue == "BAUG")
    #expect(result.rawValue["usage"]?["total_tokens"]?.intValue == 21)
}

@Test func quiverAIVectorizesSingleImage() async throws {
    let svg = #"<svg viewBox="0 0 4 4"><path d="M0 0L4 4"/></svg>"#
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"svg-vec-1","created":1713374460,"data":[{"svg":"\(svg.replacingOccurrences(of: "\"", with: "\\\""))","mime_type":"image/svg+xml"}]}
    """))
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", transport: transport))
    let model = try provider.imageModel("arrow-1")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "",
        count: 1,
        files: [ImageInputFile(url: "https://example.com/logo.png")],
        extraBody: [
            "operation": "vectorize",
            "autoCrop": true,
            "targetSize": 1024
        ]
    ))

    #expect(String(data: Data(base64Encoded: try #require(result.base64Images.first)) ?? Data(), encoding: .utf8) == svg)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.quiver.ai/v1/svgs/vectorizations")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "arrow-1")
    #expect(body["image"]?["url"]?.stringValue == "https://example.com/logo.png")
    #expect(body["auto_crop"]?.boolValue == true)
    #expect(body["target_size"]?.intValue == 1024)
    #expect(body["stream"]?.boolValue == false)
}
