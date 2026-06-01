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
    #expect(body["strictJsonSchema"] == nil)
    #expect(body["strict_json_schema"] == nil)
}

@Test func groqLanguageMapsStandardStructuredResponseFormat() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"groq-1","model":"gemma2-9b-it","choices":[{"message":{"content":"{\"value\":\"ok\"}"},"finish_reason":"stop"}],"usage":{"total_tokens":4}}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("gemma2-9b-it")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Answer.")],
        responseFormat: .json(
            schema: [
                "type": "object",
                "properties": ["value": ["type": "string"]],
                "required": ["value"],
                "additionalProperties": false
            ],
            name: "answer",
            description: "Answer schema"
        )
    ))

    #expect(result.warnings.isEmpty)
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?["type"]?.stringValue == "json_schema")
    #expect(body["response_format"]?["json_schema"]?["name"]?.stringValue == "answer")
    #expect(body["response_format"]?["json_schema"]?["description"]?.stringValue == "Answer schema")
    #expect(body["response_format"]?["json_schema"]?["schema"]?["properties"]?["value"]?["type"]?.stringValue == "string")
    #expect(body["response_format"]?["json_schema"]?["strict"]?.boolValue == true)
    #expect(body["responseFormat"] == nil)
}

@Test func groqLanguageWarnsWhenStructuredOutputsDisabledWithSchema() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"groq-1","model":"gemma2-9b-it","choices":[{"message":{"content":"{\"value\":\"ok\"}"},"finish_reason":"stop"}],"usage":{"total_tokens":4}}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("gemma2-9b-it")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Answer.")],
        responseFormat: .json(schema: ["type": "object"], name: "answer"),
        extraBody: ["structuredOutputs": false]
    ))

    #expect(result.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "responseFormat",
            message: "JSON response format schema is only supported with structuredOutputs"
        )
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?["type"]?.stringValue == "json_object")
    #expect(body["response_format"]?["json_schema"] == nil)
    #expect(body["structuredOutputs"] == nil)
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
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"cerebras-gen-1","model":"zai-glm-4.7","choices":[{"message":{"content":"{\"result\":\"2026\"}","reasoning":"think","tool_calls":[{"id":"repeat_call","index":0,"type":"function","function":{"name":"nonUsefulTool","arguments":"{}"}}]},"finish_reason":"tool_calls","logprobs":{"content":[{"token":"2026","logprob":-0.1}]}}],"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5,"completion_tokens_details":{"accepted_prediction_tokens":1,"rejected_prediction_tokens":0}}}"#,
    headers: ["x-cerebras": "yes"]))
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
    #expect(result.reasoning == "think")
    #expect(result.finishReason == "stop")
    #expect(result.toolCalls.isEmpty)
    #expect(result.providerMetadata["cerebras"]?["acceptedPredictionTokens"]?.intValue == 1)
    #expect(result.providerMetadata["cerebras"]?["rejectedPredictionTokens"]?.intValue == 0)
    #expect(result.providerMetadata["cerebras"]?["logprobs"]?[0]?["token"]?.stringValue == "2026")
    #expect(result.responseMetadata.id == "cerebras-gen-1")
    #expect(result.responseMetadata.modelID == "zai-glm-4.7")
    #expect(result.responseMetadata.headers["x-cerebras"] == "yes")
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

@Test func cerebrasLanguageMapsStandardResponseFormatToolsAndToolChoice() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}],"usage":{"total_tokens":5}}"#))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Magic number?")],
        responseFormat: .json(
            schema: [
                "type": "object",
                "properties": ["result": ["type": "string"]],
                "required": ["result"]
            ],
            name: "answer",
            description: "Answer schema"
        ),
        tools: [
            "nonUsefulTool": [
                "type": "object",
                "description": "Returns a magic number",
                "properties": [:],
                "strict": true
            ]
        ],
        toolChoice: ["type": "tool", "toolName": "nonUsefulTool"]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["response_format"]?["type"]?.stringValue == "json_schema")
    #expect(body["response_format"]?["json_schema"]?["name"]?.stringValue == "answer")
    #expect(body["response_format"]?["json_schema"]?["description"]?.stringValue == "Answer schema")
    #expect(body["response_format"]?["json_schema"]?["schema"]?["additionalProperties"]?.boolValue == false)
    #expect(body["tools"]?[0]?["type"]?.stringValue == "function")
    #expect(body["tools"]?[0]?["function"]?["name"]?.stringValue == "nonUsefulTool")
    #expect(body["tools"]?[0]?["function"]?["description"]?.stringValue == "Returns a magic number")
    #expect(body["tools"]?[0]?["function"]?["strict"]?.boolValue == true)
    #expect(body["tools"]?[0]?["function"]?["parameters"]?["strict"] == nil)
    #expect(body["tool_choice"]?["type"]?.stringValue == "function")
    #expect(body["tool_choice"]?["function"]?["name"]?.stringValue == "nonUsefulTool")
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

    var reasoningLifecycle: [String] = []
    var textLifecycle: [String] = []
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .reasoningStart(id, _):
            reasoningLifecycle.append("start:\(id)")
        case let .reasoningDeltaPart(id, delta, _):
            reasoningLifecycle.append("delta:\(id):\(delta)")
        case let .reasoningEnd(id, _):
            reasoningLifecycle.append("end:\(id)")
        case let .textStart(id, _):
            textLifecycle.append("start:\(id)")
        case let .textDeltaPart(id, delta, _):
            textLifecycle.append("delta:\(id):\(delta)")
        case let .textEnd(id, _):
            textLifecycle.append("end:\(id)")
        case let .finish(_, usage):
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(reasoningLifecycle == [
        "start:reasoning-0",
        "delta:reasoning-0:think",
        "end:reasoning-0"
    ])
    #expect(textLifecycle == [
        "start:0",
        "delta:0:done",
        "end:0"
    ])
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

    var textLifecycle: [String] = []
    var inputLifecycle: [String] = []
    var finalCalls: [AIToolCall] = []
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Magic number?")],
        extraBody: ["response_format": .object(["type": "json_schema"])]
    )) {
        switch part {
        case let .textStart(id, _):
            textLifecycle.append("start:\(id)")
        case let .textDeltaPart(id, delta, _):
            textLifecycle.append("delta:\(id):\(delta)")
        case let .textEnd(id, _):
            textLifecycle.append("end:\(id)")
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
        case let .finishMetadata(reason, usage, _):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(textLifecycle == [
        "start:0",
        "delta:0:{\"result\":\"2026\"}",
        "end:0"
    ])
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
