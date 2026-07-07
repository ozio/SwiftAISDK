import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAICompatibleChatBuildsChatCompletionRequest() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"hello"},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.chatModel("gpt-4.1-mini")

    let result = try await model.generate(LanguageModelRequest(messages: [.system("Be terse."), .user("Hi")], maxOutputTokens: 16))

    #expect(result.text == "hello")
    #expect(result.usage?.totalTokens == 5)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/chat/completions")
    #expect(request.headers["authorization"] == "Bearer test-key")
    #expect(request.headers["user-agent"] == "ai-sdk/openai/4.0.8")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "gpt-4.1-mini")
    #expect(body["messages"]?[1]?["content"]?.stringValue == "Hi")
}

@Test func openAIChatMapsFilePartsByMediaTypeLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.chatModel("gpt-4.1-mini")
    let image = Data([0x89, 0x50, 0x4E, 0x47])
    let audio = Data("RIFF".utf8)
    let pdf = Data("%PDF".utf8)

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .text("Inspect these."),
            .data(mimeType: "image/png", data: image, providerMetadata: ["openai": ["imageDetail": "high"]]),
            .data(mimeType: "audio/wav", data: audio),
            .file(mimeType: "application/pdf", data: pdf, filename: "brief.pdf")
        ])
    ]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content[1]["type"]?.stringValue == "image_url")
    #expect(content[1]["image_url"]?["url"]?.stringValue == "data:image/png;base64,\(image.base64EncodedString())")
    #expect(content[1]["image_url"]?["detail"]?.stringValue == "high")
    #expect(content[2]["type"]?.stringValue == "input_audio")
    #expect(content[2]["input_audio"]?["data"]?.stringValue == audio.base64EncodedString())
    #expect(content[2]["input_audio"]?["format"]?.stringValue == "wav")
    #expect(content[3]["type"]?.stringValue == "file")
    #expect(content[3]["file"]?["filename"]?.stringValue == "brief.pdf")
    #expect(content[3]["file"]?["file_data"]?.stringValue == "data:application/pdf;base64,\(pdf.base64EncodedString())")
}

@Test func openAIChatRejectsUnsupportedFileMediaTypeLikeUpstream() async throws {
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: RecordingTransport(response: jsonResponse("{}"))))
    let model = try provider.chatModel("gpt-4.1-mini")

    await #expect(throws: AIError.invalidArgument(argument: "messages", message: "OpenAI chat file part media type text/plain is not supported.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [
            AIMessage(role: .user, content: [.file(mimeType: "text/plain", data: Data("hello".utf8), filename: "hello.txt")])
        ]))
    }
}

@Test func openAICompatibleChatForwardsAbortSignalToHTTPTransport() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"hello"},"finish_reason":"stop"}]}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.chatModel("gpt-4.1-mini")
    let controller = AIAbortController()

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], abortSignal: controller.signal))

    let request = try #require(await transport.requests().first)
    #expect(request.abortSignal === controller.signal)
}

@Test func openAIChatMapsNestedProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"hello"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.chatModel("gpt-4.1-mini")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: [
            "openai": .object([
                "reasoningEffort": .string("low"),
                "textVerbosity": .string("low"),
                "logprobs": .bool(true)
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["reasoning_effort"]?.stringValue == "low")
    #expect(body["verbosity"]?.stringValue == "low")
    #expect(body["logprobs"]?.boolValue == true)
    #expect(body["openai"] == nil)
    #expect(body["reasoningEffort"] == nil)
    #expect(body["textVerbosity"] == nil)
}

@Test func openAIChatMapsTypedProviderOptionsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"hello"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.chatModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        providerOptions: [
            "openai": [
                "parallelToolCalls": false,
                "maxCompletionTokens": 123,
                "serviceTier": "priority",
                "promptCacheKey": "cache-key",
                "promptCacheRetention": "24h",
                "safetyIdentifier": "safe-user",
                "reasoningEffort": "none",
                "textVerbosity": "high",
                "logprobs": 4
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["parallel_tool_calls"]?.boolValue == false)
    #expect(body["max_completion_tokens"]?.intValue == 123)
    #expect(body["service_tier"]?.stringValue == "priority")
    #expect(body["prompt_cache_key"]?.stringValue == "cache-key")
    #expect(body["prompt_cache_retention"]?.stringValue == "24h")
    #expect(body["safety_identifier"]?.stringValue == "safe-user")
    #expect(body["reasoning_effort"]?.stringValue == "none")
    #expect(body["verbosity"]?.stringValue == "high")
    #expect(body["logprobs"]?.boolValue == true)
    #expect(body["top_logprobs"]?.intValue == 4)
    #expect(body["parallelToolCalls"] == nil)
    #expect(body["maxCompletionTokens"] == nil)
    #expect(body["serviceTier"] == nil)
    #expect(body["promptCacheKey"] == nil)
    #expect(body["promptCacheRetention"] == nil)
    #expect(body["safetyIdentifier"] == nil)
    #expect(body["textVerbosity"] == nil)
    #expect(body["openai"] == nil)
}

@Test func openAICompletionAndEmbeddingMapNestedProviderOptions() async throws {
    let completionTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"text":"done","finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let completionProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: completionTransport))
    let completionModel = try completionProvider.completionModel("gpt-3.5-turbo-instruct")

    _ = try await completionModel.generate(LanguageModelRequest(
        messages: [.user("Finish")],
        extraBody: [
            "openai": .object([
                "suffix": .string("tail"),
                "echo": .bool(true)
            ])
        ]
    ))

    let completionBody = try decodeJSONBody(try #require((await completionTransport.requests()).first?.body))
    #expect(completionBody["suffix"]?.stringValue == "tail")
    #expect(completionBody["echo"]?.boolValue == true)
    #expect(completionBody["openai"] == nil)

    let embeddingTransport = RecordingTransport(response: jsonResponse("""
    {"data":[{"embedding":[0.1,0.2]}],"usage":{"total_tokens":2}}
    """))
    let embeddingProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: embeddingTransport))
    let embeddingModel = try embeddingProvider.embeddingModel("text-embedding-3-small")

    _ = try await embeddingModel.embed(EmbeddingRequest(
        values: ["hello"],
        extraBody: [
            "openai": .object([
                "dimensions": .number(64),
                "encoding_format": .string("float")
            ])
        ]
    ))

    let embeddingBody = try decodeJSONBody(try #require((await embeddingTransport.requests()).first?.body))
    #expect(embeddingBody["dimensions"]?.intValue == 64)
    #expect(embeddingBody["encoding_format"]?.stringValue == "float")
    #expect(embeddingBody["openai"] == nil)
}

@Test func openAICompletionMapsStandardSettingsAndTypedProviderOptionsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"text":"done","finish_reason":"stop","logprobs":{"tokens":["done"]}}],"usage":{"total_tokens":3}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.completionModel("gpt-3.5-turbo-instruct")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.system("Prefix."), .user("Finish")],
        temperature: 0.4,
        topP: 0.8,
        topK: 3,
        presencePenalty: 0.1,
        frequencyPenalty: 0.2,
        seed: 42,
        maxOutputTokens: 12,
        stopSequences: ["END"],
        responseFormat: .json(schema: ["type": "object"]),
        tools: ["lookup": ["type": "object", "properties": [:]]],
        toolChoice: "required",
        providerOptions: [
            "openai": [
                "echo": true,
                "logitBias": ["50256": -100],
                "logprobs": true,
                "suffix": "tail",
                "user": "user-123"
            ]
        ]
    ))

    #expect(result.warnings.map(\.feature).contains("topK"))
    #expect(result.warnings.map(\.feature).contains("tools"))
    #expect(result.warnings.map(\.feature).contains("toolChoice"))
    #expect(result.warnings.map(\.feature).contains("responseFormat"))
    #expect(result.providerMetadata["openai"]?["logprobs"]?["tokens"]?[0]?.stringValue == "done")

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "gpt-3.5-turbo-instruct")
    #expect(body["prompt"]?.stringValue == "Prefix.\n\nuser:\nFinish\n\nassistant:\n")
    #expect(body["temperature"]?.doubleValue == 0.4)
    #expect(body["top_p"]?.doubleValue == 0.8)
    #expect(body["presence_penalty"]?.doubleValue == 0.1)
    #expect(body["frequency_penalty"]?.doubleValue == 0.2)
    #expect(body["seed"]?.intValue == 42)
    #expect(body["max_tokens"]?.intValue == 12)
    #expect(body["stop"]?[0]?.stringValue == "\nuser:")
    #expect(body["stop"]?[1]?.stringValue == "END")
    #expect(body["echo"]?.boolValue == true)
    #expect(body["logit_bias"]?["50256"]?.intValue == -100)
    #expect(body["logprobs"]?.intValue == 0)
    #expect(body["suffix"]?.stringValue == "tail")
    #expect(body["user"]?.stringValue == "user-123")
    #expect(body["openai"] == nil)
    #expect(body["logitBias"] == nil)
    #expect(body["tools"] == nil)
    #expect(body["tool_choice"] == nil)
    #expect(body["response_format"] == nil)
}

@Test func openAIEmbeddingUsesFloatEncodingAndTypedProviderOptionsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"data":[{"embedding":[0.1,0.2]}],"usage":{"prompt_tokens":2}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.embeddingModel("text-embedding-3-small")

    _ = try await model.embed(EmbeddingRequest(
        values: ["hello"],
        providerOptions: ["openai": ["dimensions": 128, "user": "user-123"]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["encoding_format"]?.stringValue == "float")
    #expect(body["dimensions"]?.intValue == 128)
    #expect(body["user"]?.stringValue == "user-123")
    #expect(body["openai"] == nil)
}

@Test func openAICompatibleChatMapsFunctionToolsAndToolChoice() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"tool ready"},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.chatModel("gpt-4.1-mini")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Use lookup.")],
        tools: [
            "lookup": [
                "type": "object",
                "description": "Look up a value.",
                "properties": ["query": ["type": "string"]],
                "strict": true
            ],
            "openai.web_search": [
                "type": "provider",
                "id": "openai.web_search",
                "name": "web_search",
                "args": [:]
            ]
        ],
        extraBody: [
            "toolChoice": ["type": "tool", "toolName": "lookup"],
            "reasoningEffort": "low",
            "textVerbosity": "medium"
        ]
    ))

    #expect(result.text == "tool ready")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.count == 1)
    #expect(tools[0]["type"]?.stringValue == "function")
    #expect(tools[0]["function"]?["name"]?.stringValue == "lookup")
    #expect(tools[0]["function"]?["description"]?.stringValue == "Look up a value.")
    #expect(tools[0]["function"]?["parameters"]?["properties"]?["query"]?["type"]?.stringValue == "string")
    #expect(tools[0]["function"]?["parameters"]?["strict"] == nil)
    #expect(tools[0]["function"]?["strict"]?.boolValue == true)
    #expect(body["tool_choice"]?["type"]?.stringValue == "function")
    #expect(body["tool_choice"]?["function"]?["name"]?.stringValue == "lookup")
    #expect(body["toolChoice"] == nil)
    #expect(body["reasoning_effort"]?.stringValue == "low")
    #expect(body["verbosity"]?.stringValue == "medium")
}

@Test func openAIChatAIFacadeExecutesToolsAndSerializesToolResultMessages() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"choices":[{"message":{"content":"","tool_calls":[{"id":"call_1","type":"function","function":{"name":"lookup","arguments":"{\\"query\\":\\"weather\\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"total_tokens":8}}
        """),
        jsonResponse("""
        {"choices":[{"message":{"content":"It is sunny."},"finish_reason":"stop"}],"usage":{"total_tokens":4}}
        """)
    ])
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.chatModel("gpt-4.1-mini")
    let lookup = AITool(
        name: "lookup",
        description: "Look up a value.",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]],
        toModelOutput: { context in
            ["modelForecast": context.output["forecast"] ?? .string("missing")]
        }
    ) { arguments in
        #expect(arguments["query"]?.stringValue == "weather")
        return ["forecast": "sunny"]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 3
    )

    #expect(result.text == "It is sunny.")
    #expect(result.steps.count == 2)
    #expect(result.toolResults.first?.result["forecast"]?.stringValue == "sunny")
    #expect(result.toolResults.first?.modelOutput?["modelForecast"]?.stringValue == "sunny")

    let requests = await transport.requests()
    #expect(requests.count == 2)
    let firstBody = try decodeJSONBody(try #require(requests.first?.body))
    #expect(firstBody["tools"]?[0]?["function"]?["name"]?.stringValue == "lookup")
    #expect(firstBody["tools"]?[0]?["function"]?["description"]?.stringValue == "Look up a value.")

    let secondBody = try decodeJSONBody(try #require(requests.last?.body))
    #expect(secondBody["messages"]?[1]?["role"]?.stringValue == "assistant")
    #expect(secondBody["messages"]?[1]?["tool_calls"]?[0]?["id"]?.stringValue == "call_1")
    #expect(secondBody["messages"]?[1]?["tool_calls"]?[0]?["function"]?["name"]?.stringValue == "lookup")
    #expect(secondBody["messages"]?[2]?["role"]?.stringValue == "tool")
    #expect(secondBody["messages"]?[2]?["tool_call_id"]?.stringValue == "call_1")
    let toolContent = try decodeJSONBody(Data((try #require(secondBody["messages"]?[2]?["content"]?.stringValue)).utf8))
    #expect(toolContent["modelForecast"]?.stringValue == "sunny")
}

@Test func openAICompatibleAIFacadeGenerateObjectSendsStructuredResponseFormat() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"{\\"value\\":\\"typed\\",\\"count\\":3}"},"finish_reason":"stop"}],"usage":{"total_tokens":5}}
    """))
    let provider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: transport,
        supportsStructuredOutputs: true
    )
    let model = try provider.chatModel("chat-model")
    let schema: JSONValue = [
        "type": "object",
        "properties": [
            "value": ["type": "string"],
            "count": ["type": "integer"]
        ],
        "required": ["value", "count"]
    ]

    let result = try await AI.generateObject(
        model: model,
        prompt: "Return a typed object.",
        as: OpenAIObjectAnswer.self,
        schema: schema,
        schemaName: "answer",
        schemaDescription: "A typed answer."
    )

    #expect(result.object == OpenAIObjectAnswer(value: "typed", count: 3))
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?["type"]?.stringValue == "json_schema")
    #expect(body["response_format"]?["json_schema"]?["name"]?.stringValue == "answer")
    #expect(body["response_format"]?["json_schema"]?["description"]?.stringValue == "A typed answer.")
    #expect(body["response_format"]?["json_schema"]?["strict"]?.boolValue == true)
    #expect(body["response_format"]?["json_schema"]?["schema"]?["additionalProperties"]?.boolValue == false)
    #expect(body["response_format"]?["json_schema"]?["schema"]?["properties"]?["value"]?["type"]?.stringValue == "string")
    #expect(body["responseFormat"] == nil)
}

@Test func openAICompatibleChatParsesToolCalls() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":null,"tool_calls":[{"id":"call_1","type":"function","function":{"name":"lookup","arguments":"{\\"query\\":\\"weather\\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.chatModel("gpt-4.1-mini")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Use a tool.")]))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.toolCalls.count == 1)
    #expect(result.toolCalls[0].id == "call_1")
    #expect(result.toolCalls[0].name == "lookup")
    #expect(result.toolCalls[0].arguments == #"{"query":"weather"}"#)
}

@Test func openAICompatibleChatStreamsToolCallDeltasAndFinalCall() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"lookup","arguments":"{\\"query\\":"}}]}}]}

    data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"weather\\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}

    data: [DONE]

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.chatModel("gpt-4.1-mini")

    var deltas: [String] = []
    var inputLifecycle: [String] = []
    var finalCall: AIToolCall?
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Use a tool.")])) {
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
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(deltas == ["{\"query\":", "\"weather\"}"])
    #expect(inputLifecycle == [
        "start:call_1:lookup",
        "delta:call_1:{\"query\":",
        "delta:call_1:\"weather\"}",
        "end:call_1"
    ])
    #expect(finalCall?.id == "call_1")
    #expect(finalCall?.name == "lookup")
    #expect(finalCall?.arguments == #"{"query":"weather"}"#)
    #expect(finishReason == "tool-calls")
}

@Test func openAICompatibleChatStreamsServerSentEvents() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"choices":[{"delta":{"content":"hel"}}]}

    data: {"choices":[{"delta":{"content":"lo"},"finish_reason":"stop"}]}

    data: [DONE]

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.chatModel("gpt-4.1-mini")

    var deltas: [String] = []
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        if case let .textDelta(delta) = part {
            deltas.append(delta)
        }
    }

    #expect(deltas == ["hel", "lo"])
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
    #expect(body["stream_options"] == nil)
}

private struct OpenAIObjectAnswer: Codable, Equatable, Sendable {
    var value: String
    var count: Int
}
