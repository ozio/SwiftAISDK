import Foundation
import Testing
@testable import ai_sdk_port

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
    #expect(request.headers["Authorization"] == "Bearer test-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "gpt-4.1-mini")
    #expect(body["messages"]?[1]?["content"]?.stringValue == "Hi")
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
    var finalCall: AIToolCall?
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Use a tool.")])) {
        switch part {
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
