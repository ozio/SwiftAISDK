import Foundation
import Testing
@testable import SwiftAISDK

@Test func cerebrasLanguageTransformsReasoningContentAndNormalizesJsonFinish() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"cerebras-gen-1","model":"zai-glm-4.7","choices":[{"message":{"content":"{\"result\":\"2026\"}","reasoning":"think","tool_calls":[{"id":"repeat_call","index":0,"type":"function","function":{"name":"nonUsefulTool","arguments":"{}"}}]},"finish_reason":"tool_calls","logprobs":{"content":[{"token":"2026","logprob":-0.1}]}}],"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5,"prompt_tokens_details":{"cached_tokens":1},"completion_tokens_details":{"accepted_prediction_tokens":1,"rejected_prediction_tokens":0,"reasoning_tokens":1}}}"#,
    headers: ["x-cerebras": "yes"]))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Magic number?")],
        responseFormat: .json(schema: ["type": "object"], name: "answer"),
        extraBody: [
            "messages": .array([
                .object(["role": "user", "content": "Magic number?"]),
                .object(["role": "assistant", "content": .null, "reasoning_content": "I should call a tool."])
            ])
        ]
    ))

    #expect(result.text == "{\"result\":\"2026\"}")
    #expect(result.reasoning == "think")
    #expect(result.finishReason == "stop")
    #expect(result.usage?.inputTokensNoCache == 1)
    #expect(result.usage?.inputTokensCacheRead == 1)
    #expect(result.usage?.outputTextTokens == 2)
    #expect(result.usage?.outputReasoningTokens == 1)
    #expect(result.usage?.rawValue?["prompt_tokens_details"]?["cached_tokens"]?.intValue == 1)
    #expect(result.toolCalls.isEmpty)
    #expect(result.providerMetadata["cerebras"]?["acceptedPredictionTokens"]?.intValue == 1)
    #expect(result.providerMetadata["cerebras"]?["rejectedPredictionTokens"]?.intValue == 0)
    #expect(result.providerMetadata["cerebras"]?["logprobs"]?[0]?["token"]?.stringValue == "2026")
    #expect(result.responseMetadata.id == "cerebras-gen-1")
    #expect(result.responseMetadata.modelID == "zai-glm-4.7")
    #expect(result.responseMetadata.headers["x-cerebras"] == "yes")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.cerebras.ai/v1/chat/completions")
    #expect(request.headers["authorization"] == "Bearer cerebras-key")
    #expect(request.headers["user-agent"] == "ai-sdk/cerebras/2.0.54")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["messages"]?[1]?["reasoning"]?.stringValue == "I should call a tool.")
    #expect(body["messages"]?[1]?["reasoning_content"] == nil)
    #expect(body["response_format"]?["type"]?.stringValue == "json_schema")
}

@Test func cerebrasRawResponseFormatDoesNotTriggerStructuredToolCallFilterLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"cerebras-gen-1","model":"zai-glm-4.7","choices":[{"message":{"content":"{\"result\":\"2026\"}","tool_calls":[{"id":"repeat_call","index":0,"type":"function","function":{"name":"nonUsefulTool","arguments":"{}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}}"#))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Magic number?")],
        extraBody: ["response_format": .object(["type": "json_schema"])]
    ))

    #expect(result.text == "{\"result\":\"2026\"}")
    #expect(result.finishReason == "tool-calls")
    #expect(result.toolCalls.map(\.id) == ["repeat_call"])
}

@Test func cerebrasMissingFinishReasonMapsToOtherLikeOpenAICompatible() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"cerebras-gen-1","model":"zai-glm-4.7","choices":[{"message":{"content":"done"},"finish_reason":null}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}"#))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.finishReason == "other")
}

@Test func cerebrasLanguageMapsMissingUsageToEmptyUsageLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"cerebras-no-usage","model":"zai-glm-4.7","choices":[{"message":{"content":"done"},"finish_reason":"stop"}]}"#))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.usage == TokenUsage())
}

@Test func cerebrasLanguageUsesFlatCerebrasErrorSchemaLikeUpstream() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 429,
        headers: ["x-cerebras": "limited"],
        body: Data(#"{"message":"Rate limit exceeded","type":"rate_limit_error","param":"messages","code":"rate_limit"}"#.utf8)
    ))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    await #expect(throws: AIError.httpStatusWithHeaders(
        provider: "cerebras.chat",
        statusCode: 429,
        body: "Rate limit exceeded",
        headers: ["x-cerebras": "limited"]
    )) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))
    }
}

@Test func cerebrasLanguageAppendsUpstreamUserAgentSuffixToCustomHeaders() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"cerebras-ua","model":"zai-glm-4.7","choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}"#))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(
        apiKey: "cerebras-key",
        headers: ["User-Agent": "TestApp/1.0"],
        transport: transport
    ))
    let model = try provider.languageModel("zai-glm-4.7")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    let request = try #require(await transport.requests().first)
    #expect(request.headers["user-agent"] == "TestApp/1.0 ai-sdk/cerebras/2.0.54")
    #expect(request.headers["authorization"] == "Bearer cerebras-key")
}

@Test func cerebrasLanguageMapsProviderOptionsAndStandardSettings() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"cerebras-opts","model":"zai-glm-4.7","choices":[{"message":{"content":"ok"},"finish_reason":"stop"}],"usage":{"total_tokens":5}}"#))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        topK: 4,
        presencePenalty: 0.2,
        frequencyPenalty: 0.1,
        seed: 123,
        reasoning: "medium",
        providerOptions: [
            "openaiCompatible": ["user": "ignored-user", "textVerbosity": "low"],
            "cerebras": [
                "user": "user-123",
                "reasoningEffort": "high",
                "textVerbosity": "medium",
                "strictJsonSchema": false,
                "customOption": "kept"
            ]
        ],
        extraBody: [
            "cerebras": [
                "reasoningEffort": "low",
                "customOption": "overridden"
            ]
        ]
    ))

    #expect(result.warnings == [AIWarning(type: "unsupported", feature: "topK")])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["frequency_penalty"]?.doubleValue == 0.1)
    #expect(body["presence_penalty"]?.doubleValue == 0.2)
    #expect(body["seed"]?.intValue == 123)
    #expect(body["user"]?.stringValue == "user-123")
    #expect(body["reasoning_effort"]?.stringValue == "high")
    #expect(body["verbosity"]?.stringValue == "medium")
    #expect(body["customOption"]?.stringValue == "kept")
    #expect(body["cerebras"] == nil)
    #expect(body["openaiCompatible"] == nil)
    #expect(body["reasoningEffort"] == nil)
    #expect(body["textVerbosity"] == nil)
    #expect(body["strictJsonSchema"] == nil)
}

@Test func cerebrasProviderOptionsValidateKnownOpenAICompatibleSchema() async throws {
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: RecordingTransport(responses: [])))
    let model = try provider.languageModel("zai-glm-4.7")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.cerebras", message: "Cerebras provider options must be an object.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["cerebras": "not-an-object"]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.cerebras.user", message: "Cerebras user cannot be null.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["cerebras": ["user": .null]]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.openaiCompatible.reasoningEffort", message: "Cerebras reasoningEffort must be a string.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["openaiCompatible": ["reasoningEffort": 7]]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.cerebras.strictJsonSchema", message: "Cerebras strictJsonSchema must be a boolean.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["cerebras": ["strictJsonSchema": "yes"]]
        ))
    }
}

@Test func cerebrasProviderOptionsStripKnownKeysButKeepUnknownPassthrough() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"cerebras-opts","model":"zai-glm-4.7","choices":[{"message":{"content":"ok"},"finish_reason":"stop"}],"usage":{"total_tokens":5}}"#))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        providerOptions: [
            "openaiCompatible": [
                "user": "compat-user",
                "customOption": "compat-extra"
            ],
            "cerebras": [
                "user": "cerebras-user",
                "reasoningEffort": "high",
                "textVerbosity": "low",
                "strictJsonSchema": false,
                "customOption": "cerebras-extra"
            ]
        ],
        extraBody: [
            "customOption": "raw-extra"
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["user"]?.stringValue == "cerebras-user")
    #expect(body["reasoning_effort"]?.stringValue == "high")
    #expect(body["verbosity"]?.stringValue == "low")
    #expect(body["customOption"]?.stringValue == "cerebras-extra")
    #expect(body["reasoningEffort"] == nil)
    #expect(body["textVerbosity"] == nil)
    #expect(body["strictJsonSchema"] == nil)
    #expect(body["openaiCompatible"] == nil)
    #expect(body["cerebras"] == nil)
}

@Test func cerebrasProviderOptionsNullNamespaceKeepsExtraBodyEscapeHatch() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"cerebras-opts","model":"zai-glm-4.7","choices":[{"message":{"content":"ok"},"finish_reason":"stop"}],"usage":{"total_tokens":5}}"#))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        providerOptions: ["cerebras": .null],
        extraBody: [
            "cerebras": [
                "user": "raw-user",
                "reasoningEffort": "medium",
                "textVerbosity": "high",
                "customOption": "raw-extra"
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["user"]?.stringValue == "raw-user")
    #expect(body["reasoning_effort"]?.stringValue == "medium")
    #expect(body["verbosity"]?.stringValue == "high")
    #expect(body["customOption"]?.stringValue == "raw-extra")
}

@Test func cerebrasLanguageMapsTopLevelReasoningWhenProviderOptionAbsent() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}"#))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], reasoning: "medium"))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["reasoning_effort"]?.stringValue == "medium")
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

@Test func cerebrasLanguageWarnsForProviderDefinedToolsAndUnsupportedToolChoice() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}"#))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Search.")],
        tools: ["cerebras.search": ["type": "provider", "id": "cerebras.search"]],
        toolChoice: ["type": "provider"]
    ))

    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "provider-defined tool cerebras.search"),
        AIWarning(type: "unsupported", feature: "tool choice type: provider")
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["tools"] == nil)
    #expect(body["tool_choice"] == nil)
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

@Test func cerebrasStreamMissingFinishReasonDefaultsToOtherLikeOpenAICompatible() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"cerebras-1","model":"zai-glm-4.7","choices":[{"index":0,"delta":{"content":"done"},"finish_reason":null}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}

    data: [DONE]

    """))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
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

    #expect(finishReason == "other")
    #expect(totalTokens == 2)
}

@Test func cerebrasLanguageStreamsToolCallsAndDropsStructuredRepeat() async throws {
    let transport = RecordingTransport(response: sseResponse(#"""
    data: {"id":"cerebras-1","model":"zai-glm-4.7","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_magic","type":"function","function":{"name":"nonUsefulTool","arguments":"{}"}}]},"finish_reason":null}]}

    data: {"id":"cerebras-1","model":"zai-glm-4.7","choices":[{"index":0,"delta":{"content":"{\"result\":\"2026\"}"},"finish_reason":null}]}

    data: {"id":"cerebras-1","model":"zai-glm-4.7","choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"id":"repeat_call","type":"function","function":{"name":"nonUsefulTool","arguments":"{}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":9,"completion_tokens":4,"total_tokens":13,"prompt_tokens_details":{"cached_tokens":2},"completion_tokens_details":{"reasoning_tokens":1}}}

    data: [DONE]

    """#))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    var textLifecycle: [String] = []
    var inputLifecycle: [String] = []
    var finalCalls: [AIToolCall] = []
    var finishReason: String?
    var usage: TokenUsage?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Magic number?")],
        responseFormat: .json(schema: ["type": "object"], name: "answer")
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
        case let .finish(reason, finalUsage):
            finishReason = reason
            usage = finalUsage
        case let .finishMetadata(reason, finalUsage, _):
            finishReason = reason
            usage = finalUsage
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
    #expect(usage?.totalTokens == 13)
    #expect(usage?.inputTokensNoCache == 7)
    #expect(usage?.inputTokensCacheRead == 2)
    #expect(usage?.outputTextTokens == 3)
    #expect(usage?.outputReasoningTokens == 1)
}

@Test func cerebrasLanguageStreamsErrorChunksAndParseErrorsAsErrorPartsLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse(#"""
    data: {"message":"First chunk failed","type":"server_error","param":"messages","code":"bad_chunk"}

    data: not-json

    data: [DONE]

    """#))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

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

    #expect(errors.first == "First chunk failed")
    #expect(errors.count == 2)
    #expect(finishReason == "error")
    #expect(usage == TokenUsage())
}

@Test func cerebrasLanguageStreamRequiresFirstToolDeltaIDAndNameLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse(#"""
    data: {"id":"cerebras-1","model":"zai-glm-4.7","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"type":"function","function":{"name":"weather","arguments":"{}"}}]},"finish_reason":null}]}

    data: [DONE]

    """#))
    let provider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: transport))
    let model = try provider.languageModel("zai-glm-4.7")

    await #expect(throws: AIError.invalidResponse(provider: "cerebras.chat", message: "Expected 'id' to be a string.")) {
        for try await _ in model.stream(LanguageModelRequest(messages: [.user("Weather?")])) {}
    }
}
