import Foundation
import Testing
@testable import SwiftAISDK

@Test func groqLanguageStreamsReasoningAndMapsOptions() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"groq-1","model":"qwen/qwen3-32b","choices":[{"index":0,"delta":{"reasoning":"think"},"finish_reason":null}]}

    data: {"id":"groq-1","model":"qwen/qwen3-32b","choices":[{"index":0,"delta":{"content":"answer"},"finish_reason":"stop"}],"x_groq":{"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5,"completion_tokens_details":{"reasoning_tokens":1}}}}

    data: [DONE]

    """))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("qwen/qwen3-32b")

    var reasoning: [String] = []
    var text: [String] = []
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: [
            "reasoningFormat": "parsed",
            "reasoningEffort": "xhigh",
            "parallelToolCalls": false,
            "serviceTier": "flex"
        ]
    )) {
        switch part {
        case let .reasoningDelta(delta):
            reasoning.append(delta)
        case let .textDelta(delta):
            text.append(delta)
        case let .finish(_, usage):
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(reasoning == ["think"])
    #expect(text == ["answer"])
    #expect(totalTokens == 5)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.groq.com/openai/v1/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer groq-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
    #expect(body["reasoning_format"]?.stringValue == "parsed")
    #expect(body["reasoning_effort"]?.stringValue == "high")
    #expect(body["parallel_tool_calls"]?.boolValue == false)
    #expect(body["service_tier"]?.stringValue == "flex")
}

@Test func groqLanguageMapsNestedProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"groq-1","model":"openai/gpt-oss-20b","choices":[{"message":{"content":"answer"},"finish_reason":"stop"}]}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("openai/gpt-oss-20b")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: [
            "user": "user-123",
            "serviceTier": "flex",
            "groq": [
                "reasoningFormat": "parsed",
                "reasoningEffort": "minimal",
                "parallelToolCalls": false,
                "serviceTier": "performance",
                "strictJsonSchema": true
            ]
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["groq"] == nil)
    #expect(body["user"]?.stringValue == "user-123")
    #expect(body["reasoning_format"]?.stringValue == "parsed")
    #expect(body["reasoning_effort"]?.stringValue == "low")
    #expect(body["parallel_tool_calls"]?.boolValue == false)
    #expect(body["service_tier"]?.stringValue == "performance")
    #expect(body["strict_json_schema"]?.boolValue == true)
}

@Test func groqLanguageMapsFunctionToolsAndBrowserSearchTool() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"groq-1","model":"openai/gpt-oss-120b","choices":[{"message":{"content":"answer"},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("openai/gpt-oss-120b")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Search and call the tool.")],
        tools: [
            "lookup": [
                "type": "object",
                "description": "Look up a value.",
                "properties": ["query": ["type": "string"]],
                "strict": true
            ],
            "groq.browser_search": GroqTools.browserSearch()
        ],
        extraBody: ["toolChoice": ["type": "tool", "toolName": "lookup"]]
    ))

    #expect(result.text == "answer")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    let functionTool = try #require(tools.first { $0["type"]?.stringValue == "function" })
    let browserSearchTool = try #require(tools.first { $0["type"]?.stringValue == "browser_search" })
    #expect(functionTool["function"]?["name"]?.stringValue == "lookup")
    #expect(functionTool["function"]?["description"]?.stringValue == "Look up a value.")
    #expect(functionTool["function"]?["parameters"]?["properties"]?["query"]?["type"]?.stringValue == "string")
    #expect(functionTool["function"]?["parameters"]?["strict"] == nil)
    #expect(functionTool["function"]?["strict"]?.boolValue == true)
    #expect(browserSearchTool["type"]?.stringValue == "browser_search")
    #expect(body["tool_choice"]?["type"]?.stringValue == "function")
    #expect(body["tool_choice"]?["function"]?["name"]?.stringValue == "lookup")
    #expect(body["toolChoice"] == nil)
}

@Test func groqLanguageParsesToolCalls() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"groq-1","model":"llama-3.3-70b-versatile","choices":[{"index":0,"message":{"role":"assistant","content":null,"tool_calls":[{"id":"tk85n1k4m","type":"function","function":{"name":"weather","arguments":"{}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":210,"completion_tokens":15,"total_tokens":225}}
    """))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("llama-3.3-70b-versatile")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Weather?")],
        tools: ["weather": ["type": "object", "properties": [:]]]
    ))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.usage?.totalTokens == 225)
    #expect(result.toolCalls.count == 1)
    #expect(result.toolCalls[0].id == "tk85n1k4m")
    #expect(result.toolCalls[0].name == "weather")
    #expect(result.toolCalls[0].arguments == "{}")
}

@Test func groqLanguageStreamsFragmentedToolCalls() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"groq-1","model":"llama-3.3-70b-versatile","choices":[{"index":0,"delta":{"role":"assistant","content":null},"finish_reason":null}]}

    data: {"id":"groq-1","model":"llama-3.3-70b-versatile","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"test_tool","arguments":"{\\""}}]},"finish_reason":null}]}

    data: {"id":"groq-1","model":"llama-3.3-70b-versatile","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"value"}}]},"finish_reason":null}]}

    data: {"id":"groq-1","model":"llama-3.3-70b-versatile","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\":\\"Sparkle Day\\"}"}}]},"finish_reason":null}]}

    data: {"id":"groq-1","model":"llama-3.3-70b-versatile","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}],"x_groq":{"usage":{"prompt_tokens":210,"completion_tokens":15,"total_tokens":225}}}

    data: [DONE]

    """))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("llama-3.3-70b-versatile")

    var deltas: [String] = []
    var inputLifecycle: [String] = []
    var toolCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Use a tool.")],
        tools: ["test_tool": ["type": "object", "properties": ["value": ["type": "string"]]]]
    )) {
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
            toolCall = call
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    let finalToolCall = try #require(toolCall)
    #expect(deltas == ["{\"", "value", "\":\"Sparkle Day\"}"])
    #expect(inputLifecycle == [
        "start:call_1:test_tool",
        "delta:call_1:{\"",
        "delta:call_1:value",
        "delta:call_1:\":\"Sparkle Day\"}",
        "end:call_1"
    ])
    #expect(finalToolCall.id == "call_1")
    #expect(finalToolCall.name == "test_tool")
    #expect(try decodeJSONBody(Data(finalToolCall.arguments.utf8))["value"]?.stringValue == "Sparkle Day")
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 225)
}

@Test func groqBrowserSearchToolIsSkippedForUnsupportedModels() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"groq-1","model":"gemma2-9b-it","choices":[{"message":{"content":"answer"},"finish_reason":"stop"}]}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("gemma2-9b-it")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Search.")],
        tools: [
            "groq.browser_search": GroqTools.browserSearch()
        ],
        extraBody: ["toolChoice": "required"]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["tools"] == nil)
    #expect(body["tool_choice"] == nil)
}

@Test func groqTranscriptionMapsProviderOptionsToMultipartFields() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"groq transcript","x_groq":{"id":"req-1"},"language":"en","duration":1.2}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.transcriptionModel("whisper-large-v3")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("mp3".utf8),
        fileName: "clip.mp3",
        mimeType: "audio/mpeg",
        language: "en",
        prompt: "Names",
        extraBody: [
            "responseFormat": "verbose_json",
            "temperature": 0,
            "timestampGranularities": ["word", "segment"]
        ]
    ))

    #expect(result.text == "groq transcript")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.groq.com/openai/v1/audio/transcriptions")
    #expect(request.headers["Authorization"] == "Bearer groq-key")
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"model\""))
    #expect(bodyText.contains("whisper-large-v3"))
    #expect(bodyText.contains("name=\"file\"; filename=\"clip.mp3\""))
    #expect(bodyText.contains("name=\"language\""))
    #expect(bodyText.contains("en"))
    #expect(bodyText.contains("name=\"prompt\""))
    #expect(bodyText.contains("Names"))
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("verbose_json"))
    #expect(bodyText.contains("name=\"temperature\""))
    #expect(bodyText.contains("0"))
    #expect(bodyText.contains("name=\"timestamp_granularities[]\""))
    #expect(bodyText.contains("word"))
    #expect(bodyText.contains("segment"))
}

@Test func groqTranscriptionMapsNestedProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"nested transcript"}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.transcriptionModel("whisper-large-v3-turbo")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("mp3".utf8),
        fileName: "clip.mp3",
        mimeType: "audio/mpeg",
        extraBody: [
            "temperature": 0.7,
            "groq": [
                "responseFormat": "verbose_json",
                "timestampGranularities": ["word"],
                "temperature": 0
            ]
        ]
    ))

    let request = try #require(await transport.requests().first)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(!bodyText.contains("name=\"groq\""))
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("verbose_json"))
    #expect(bodyText.contains("name=\"timestamp_granularities[]\""))
    #expect(bodyText.contains("word"))
    #expect(bodyText.contains("name=\"temperature\""))
    #expect(bodyText.contains("\r\n0\r\n"))
}

@Test func deepSeekLanguageStreamsReasoningAndIncludesUsageOptions() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"ds-1","model":"deepseek-reasoner","choices":[{"index":0,"delta":{"reasoning_content":"think"},"finish_reason":null}]}

    data: {"id":"ds-1","model":"deepseek-reasoner","choices":[{"index":0,"delta":{"content":"answer"},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5,"prompt_cache_hit_tokens":1,"prompt_cache_miss_tokens":1}}

    data: [DONE]

    """))
    let provider = try AIProviders.deepSeek(settings: ProviderSettings(apiKey: "deepseek-key", transport: transport))
    let model = try provider.languageModel("deepseek-reasoner")

    var reasoning: [String] = []
    var text: [String] = []
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: ["thinking": .object(["type": "enabled"]), "reasoningEffort": "xhigh"]
    )) {
        switch part {
        case let .reasoningDelta(delta):
            reasoning.append(delta)
        case let .textDelta(delta):
            text.append(delta)
        case let .finish(_, usage):
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(reasoning == ["think"])
    #expect(text == ["answer"])
    #expect(totalTokens == 5)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepseek.com/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer deepseek-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
    #expect(body["stream_options"]?["include_usage"]?.boolValue == true)
    #expect(body["thinking"]?["type"]?.stringValue == "enabled")
    #expect(body["reasoning_effort"]?.stringValue == "max")
}

@Test func deepSeekLanguageParsesToolCalls() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"role":"assistant","content":"","reasoning_content":"I should call weather.","tool_calls":[{"id":"call_weather","index":0,"type":"function","function":{"name":"weather","arguments":"{\"location\":\"San Francisco\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":9,"completion_tokens":4,"total_tokens":13}}"#))
    let provider = try AIProviders.deepSeek(settings: ProviderSettings(apiKey: "deepseek-key", transport: transport))
    let model = try provider.languageModel("deepseek-reasoner")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Weather?")]))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.usage?.totalTokens == 13)
    #expect(result.toolCalls.count == 1)
    #expect(result.toolCalls[0].id == "call_weather")
    #expect(result.toolCalls[0].name == "weather")
    #expect(try decodeJSONBody(Data(result.toolCalls[0].arguments.utf8))["location"]?.stringValue == "San Francisco")
}

@Test func deepSeekChatModelUsesNativeReasoningMapping() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"done"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}"#))
    let provider = try AIProviders.deepSeek(settings: ProviderSettings(apiKey: "deepseek-key", transport: transport))
    let model = try provider.chatModel("deepseek-chat")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: ["reasoningEffort": "xhigh"]
    ))

    #expect(model.providerID == "deepseek.chat")
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["reasoning_effort"]?.stringValue == "max")
    #expect(body["reasoningEffort"] == nil)
}

@Test func deepSeekLanguageStreamsFragmentedToolCalls() async throws {
    let transport = RecordingTransport(response: sseResponse(#"""
    data: {"id":"ds-1","model":"deepseek-reasoner","choices":[{"index":0,"delta":{"reasoning_content":"think"},"finish_reason":null}]}

    data: {"id":"ds-1","model":"deepseek-reasoner","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_weather","type":"function","function":{"name":"weather","arguments":"{\"location\":"}}]},"finish_reason":null}]}

    data: {"id":"ds-1","model":"deepseek-reasoner","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"San Francisco\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":9,"completion_tokens":4,"total_tokens":13}}

    data: [DONE]

    """#))
    let provider = try AIProviders.deepSeek(settings: ProviderSettings(apiKey: "deepseek-key", transport: transport))
    let model = try provider.languageModel("deepseek-reasoner")

    var reasoning: [String] = []
    var deltas: [String] = []
    var inputLifecycle: [String] = []
    var finalCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Weather?")])) {
        switch part {
        case let .reasoningDelta(delta):
            reasoning.append(delta)
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

    let call = try #require(finalCall)
    #expect(reasoning == ["think"])
    #expect(deltas == ["{\"location\":", "\"San Francisco\"}"])
    #expect(inputLifecycle == [
        "start:call_weather:weather",
        "delta:call_weather:{\"location\":",
        "delta:call_weather:\"San Francisco\"}",
        "end:call_weather"
    ])
    #expect(call.id == "call_weather")
    #expect(call.name == "weather")
    #expect(try decodeJSONBody(Data(call.arguments.utf8))["location"]?.stringValue == "San Francisco")
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 13)
}

@Test func deepSeekV4AssistantMessagesIncludeEmptyReasoningContent() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"ok","reasoning_content":"r"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}"#))
    let provider = try AIProviders.deepSeek(settings: ProviderSettings(apiKey: "deepseek-key", transport: transport))
    let model = try provider.languageModel("deepseek-v4")

    let result = try await model.generate(LanguageModelRequest(messages: [.assistant("Previous answer"), .user("Continue")]))

    #expect(result.text == "ok")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["messages"]?[0]?["role"]?.stringValue == "assistant")
    #expect(body["messages"]?[0]?["reasoning_content"]?.stringValue == "")
}

@Test func moonshotLanguageTransformsThinkingOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"moon"},"finish_reason":"stop"}],"usage":{"prompt_tokens":100,"completion_tokens":80,"cached_tokens":30,"completion_tokens_details":{"reasoning_tokens":20}}}
    """))
    let provider = try AIProviders.moonshotAI(settings: ProviderSettings(apiKey: "moonshot-key", transport: transport))
    let model = try provider.languageModel("kimi-k2-thinking")

    #expect(model.providerID == "moonshotai.chat")
    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: [
            "thinking": .object(["type": "disabled"]),
            "moonshotai": .object([
                "thinking": .object(["type": "enabled", "budgetTokens": 1024]),
                "reasoningHistory": .string("preserved")
            ])
        ]
    ))

    #expect(result.text == "moon")
    #expect(result.usage?.inputTokens == 100)
    #expect(result.usage?.outputTokens == 80)
    #expect(result.usage?.totalTokens == 180)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.moonshot.ai/v1/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer moonshot-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["moonshotai"] == nil)
    #expect(body["thinking"]?["type"]?.stringValue == "enabled")
    #expect(body["thinking"]?["budget_tokens"]?.intValue == 1024)
    #expect(body["thinking"]?["budgetTokens"] == nil)
    #expect(body["reasoning_history"]?.stringValue == "preserved")
    #expect(body["reasoningHistory"] == nil)
}

@Test func moonshotLanguageStreamsUsageWithoutTotalTokens() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"choices":[{"delta":{"content":"moon"},"finish_reason":null}]}

    data: {"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":3,"completion_tokens":4,"cached_tokens":1}}

    data: [DONE]

    """))
    let provider = try AIProviders.moonshotAI(settings: ProviderSettings(apiKey: "moonshot-key", transport: transport))
    let model = try provider.languageModel("kimi-k2-thinking")

    var text: [String] = []
    var finishReason: String?
    var usage: TokenUsage?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: ["moonshotAI": ["reasoningHistory": "disabled"]]
    )) {
        switch part {
        case let .textDelta(delta):
            text.append(delta)
        case let .finish(reason, finalUsage):
            finishReason = reason
            usage = finalUsage
        default:
            break
        }
    }

    #expect(text == ["moon"])
    #expect(finishReason == "stop")
    #expect(usage?.inputTokens == 3)
    #expect(usage?.outputTokens == 4)
    #expect(usage?.totalTokens == 7)
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["moonshotAI"] == nil)
    #expect(body["reasoning_history"]?.stringValue == "disabled")
}

@Test func cerebrasLanguageTransformsReasoningContentAndNormalizesJsonFinish() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"{\"result\":\"2026\"}","reasoning":"think","tool_calls":[{"id":"repeat_call","index":0,"type":"function","function":{"name":"nonUsefulTool","arguments":"{}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}}"#))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Magic number?")],
        extraBody: [
            "response_format": .object(["type": "json_schema"]),
            "messages": .array([
                .object(["role": "user", "content": "Magic number?"]),
                .object(["role": "assistant", "content": .null, "reasoning_content": "I should call a tool."])
            ])
        ]
    ))

    #expect(result.text == "{\"result\":\"2026\"}")
    #expect(result.finishReason == "stop")
    #expect(result.toolCalls.isEmpty)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.cerebras.ai/v1/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer cerebras-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["messages"]?[1]?["reasoning"]?.stringValue == "I should call a tool.")
    #expect(body["messages"]?[1]?["reasoning_content"] == nil)
    #expect(body["response_format"]?["type"]?.stringValue == "json_schema")
}

@Test func cerebrasLanguageMapsStandardStructuredResponseFormat() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"{\"result\":\"2026\"}"},"finish_reason":"stop"}],"usage":{"total_tokens":5}}"#))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Magic number?")],
        extraBody: [
            "responseFormat": [
                "type": "json",
                "name": "answer",
                "description": "Answer schema",
                "schema": [
                    "type": "object",
                    "properties": ["result": ["type": "string"]],
                    "required": ["result"]
                ]
            ],
            "strictJsonSchema": false
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?["type"]?.stringValue == "json_schema")
    #expect(body["response_format"]?["json_schema"]?["name"]?.stringValue == "answer")
    #expect(body["response_format"]?["json_schema"]?["description"]?.stringValue == "Answer schema")
    #expect(body["response_format"]?["json_schema"]?["schema"]?["type"]?.stringValue == "object")
    #expect(body["response_format"]?["json_schema"]?["schema"]?["additionalProperties"] == nil)
    #expect(body["response_format"]?["json_schema"]?["strict"]?.boolValue == false)
    #expect(body["responseFormat"] == nil)
    #expect(body["strictJsonSchema"] == nil)
}

@Test func cerebrasChatModelUsesNativeStructuredResponseFormat() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"{\"result\":\"2026\"}"},"finish_reason":"stop"}],"usage":{"total_tokens":5}}"#))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.chatModel("zai-glm-4.7")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Magic number?")],
        extraBody: [
            "responseFormat": [
                "type": "json",
                "schema": ["type": "object"]
            ]
        ]
    ))

    #expect(model.providerID == "cerebras.chat")
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?["type"]?.stringValue == "json_schema")
    #expect(body["response_format"]?["json_schema"]?["schema"]?["type"]?.stringValue == "object")
    #expect(body["response_format"]?["json_schema"]?["schema"]?["additionalProperties"]?.boolValue == false)
    #expect(body["responseFormat"] == nil)
}

@Test func cerebrasLanguageParsesToolCalls() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"role":"assistant","reasoning":"I should call a tool.","tool_calls":[{"id":"call_magic","index":0,"type":"function","function":{"name":"nonUsefulTool","arguments":"{}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":9,"completion_tokens":4,"total_tokens":13}}"#))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Magic number?")]))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.usage?.totalTokens == 13)
    #expect(result.toolCalls.count == 1)
    #expect(result.toolCalls[0].id == "call_magic")
    #expect(result.toolCalls[0].name == "nonUsefulTool")
    #expect(result.toolCalls[0].arguments == "{}")
}

@Test func cerebrasLanguageStreamsReasoningDeltas() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"cerebras-1","model":"zai-glm-4.7","choices":[{"index":0,"delta":{"reasoning":"think"},"finish_reason":null}]}

    data: {"id":"cerebras-1","model":"zai-glm-4.7","choices":[{"index":0,"delta":{"content":"done"},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3}}

    data: [DONE]

    """))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    var reasoning: [String] = []
    var text: [String] = []
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .reasoningDelta(delta):
            reasoning.append(delta)
        case let .textDelta(delta):
            text.append(delta)
        case let .finish(_, usage):
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(reasoning == ["think"])
    #expect(text == ["done"])
    #expect(totalTokens == 3)
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
}

@Test func cerebrasLanguageStreamsToolCallsAndDropsStructuredRepeat() async throws {
    let transport = RecordingTransport(response: sseResponse(#"""
    data: {"id":"cerebras-1","model":"zai-glm-4.7","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_magic","type":"function","function":{"name":"nonUsefulTool","arguments":"{}"}}]},"finish_reason":null}]}

    data: {"id":"cerebras-1","model":"zai-glm-4.7","choices":[{"index":0,"delta":{"content":"{\"result\":\"2026\"}"},"finish_reason":null}]}

    data: {"id":"cerebras-1","model":"zai-glm-4.7","choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"id":"repeat_call","type":"function","function":{"name":"nonUsefulTool","arguments":"{}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":9,"completion_tokens":4,"total_tokens":13}}

    data: [DONE]

    """#))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    var text: [String] = []
    var inputLifecycle: [String] = []
    var finalCalls: [AIToolCall] = []
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Magic number?")],
        extraBody: ["response_format": .object(["type": "json_schema"])]
    )) {
        switch part {
        case let .textDelta(delta):
            text.append(delta)
        case let .toolInputStart(id, name, _, _, _, _):
            inputLifecycle.append("start:\(id):\(name)")
        case let .toolInputDelta(id, delta, _):
            inputLifecycle.append("delta:\(id):\(delta)")
        case let .toolInputEnd(id, _):
            inputLifecycle.append("end:\(id)")
        case let .toolCall(call):
            finalCalls.append(call)
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(text == ["{\"result\":\"2026\"}"])
    #expect(inputLifecycle == [
        "start:call_magic:nonUsefulTool",
        "delta:call_magic:{}",
        "end:call_magic"
    ])
    #expect(finalCalls.map(\.id) == ["call_magic"])
    #expect(finalCalls.first?.name == "nonUsefulTool")
    #expect(finalCalls.first?.arguments == "{}")
    #expect(finishReason == "stop")
    #expect(totalTokens == 13)
}
