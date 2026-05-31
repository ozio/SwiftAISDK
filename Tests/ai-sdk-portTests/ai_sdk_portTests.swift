import Foundation
import Testing
@testable import ai_sdk_port

actor RecordingTransport: AITransport {
    private var _requests: [AIHTTPRequest] = []
    private var responses: [AIHTTPResponse]

    init(response: AIHTTPResponse) {
        self.responses = [response]
    }

    init(responses: [AIHTTPResponse]) {
        self.responses = responses
    }

    func requests() -> [AIHTTPRequest] {
        _requests
    }

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        _requests.append(request)
        if responses.count > 1 {
            return responses.removeFirst()
        }
        return responses[0]
    }
}

func jsonResponse(_ json: String) -> AIHTTPResponse {
    AIHTTPResponse(statusCode: 200, headers: ["content-type": "application/json"], body: Data(json.utf8))
}

func sseResponse(_ text: String) -> AIHTTPResponse {
    AIHTTPResponse(statusCode: 200, headers: ["content-type": "text/event-stream"], body: Data(text.utf8))
}

func multipartResponse(parts: [(name: String, contentType: String, body: Data)]) -> AIHTTPResponse {
    let boundary = "test-boundary"
    var body = Data()
    for part in parts {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(part.name)\"\r\n".utf8))
        body.append(Data("Content-Type: \(part.contentType)\r\n\r\n".utf8))
        body.append(part.body)
        body.append(Data("\r\n".utf8))
    }
    body.append(Data("--\(boundary)--\r\n".utf8))
    return AIHTTPResponse(statusCode: 200, headers: ["content-type": "multipart/form-data; boundary=\(boundary)"], body: body)
}

func amazonEventStreamResponse(_ events: [(eventType: String, payload: String)]) -> AIHTTPResponse {
    let body = events.reduce(into: Data()) { data, event in
        data.append(amazonEventStreamFrame(eventType: event.eventType, payload: Data(event.payload.utf8)))
    }
    return AIHTTPResponse(statusCode: 200, headers: ["content-type": "application/vnd.amazon.eventstream"], body: body)
}

private func amazonEventStreamFrame(eventType: String, payload: Data) -> Data {
    var headers = Data()
    appendAmazonStringHeader(name: ":message-type", value: "event", to: &headers)
    appendAmazonStringHeader(name: ":event-type", value: eventType, to: &headers)

    let totalLength = UInt32(12 + headers.count + payload.count + 4)
    var frame = Data()
    appendUInt32(totalLength, to: &frame)
    appendUInt32(UInt32(headers.count), to: &frame)
    appendUInt32(0, to: &frame)
    frame.append(headers)
    frame.append(payload)
    appendUInt32(0, to: &frame)
    return frame
}

private func appendAmazonStringHeader(name: String, value: String, to data: inout Data) {
    let nameData = Data(name.utf8)
    let valueData = Data(value.utf8)
    data.append(UInt8(nameData.count))
    data.append(nameData)
    data.append(7)
    appendUInt16(UInt16(valueData.count), to: &data)
    data.append(valueData)
}

private func appendUInt16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8(value & 0xff))
}

private func appendUInt32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8((value >> 24) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8(value & 0xff))
}

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

@Test func anthropicRequestUsesMessagesEndpointAndHeaders() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"bonjour"}],"stop_reason":"end_turn","usage":{"input_tokens":4,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-5-haiku-latest")

    let result = try await model.generate(LanguageModelRequest(messages: [.system("French."), .user("Hi")]))

    #expect(result.text == "bonjour")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.anthropic.com/v1/messages")
    #expect(request.headers["x-api-key"] == "claude-key")
    #expect(request.headers["anthropic-version"] == "2023-06-01")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["system"]?.stringValue == "French.")
    #expect(body["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
}

@Test func anthropicMessagesAliasUsesMessagesModel() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"alias"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.messages("claude-3-5-haiku-latest")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "alias")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.anthropic.com/v1/messages")
}

@Test func anthropicAWSUsesWorkspaceAndAPIKeyHeaders() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"aws claude"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropicAWS(settings: AnthropicAWSProviderSettings(
        region: "us-west-2",
        workspaceID: "wrkspc_test",
        apiKey: "aws-api-key",
        transport: transport
    ))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))

    #expect(result.text == "aws claude")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://aws-external-anthropic.us-west-2.api.aws/v1/messages")
    #expect(request.headers["x-api-key"] == "aws-api-key")
    #expect(request.headers["anthropic-workspace-id"] == "wrkspc_test")
    #expect(request.headers["anthropic-version"] == "2023-06-01")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "claude-sonnet-4-6")
    #expect(body["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
}

@Test func anthropicAWSSignsMessagesWithSigV4() async throws {
    let fixedDate = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2024,
        month: 3,
        day: 15,
        hour: 0,
        minute: 0,
        second: 0
    ).date!
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"signed"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
    """))
    let provider = try AIProviders.anthropicAWS(settings: AnthropicAWSProviderSettings(
        region: "us-west-2",
        workspaceID: "wrkspc_test",
        accessKeyID: "AKIDEXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
        transport: transport,
        date: { fixedDate }
    ))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))

    #expect(result.text == "signed")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://aws-external-anthropic.us-west-2.api.aws/v1/messages")
    #expect(request.headers["x-amz-date"] == "20240315T000000Z")
    #expect(request.headers["x-amz-content-sha256"] != nil)
    #expect(request.headers["authorization"]?.contains("Credential=AKIDEXAMPLE/20240315/us-west-2/aws-external-anthropic/aws4_request") == true)
    #expect(request.headers["anthropic-workspace-id"] == "wrkspc_test")
}

@Test func anthropicRequestMapsProviderOptionsAndDocuments() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"max_tokens","usage":{"input_tokens":10,"output_tokens":4}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-7-sonnet-latest")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .user, content: [
                .text("Read this"),
                .data(mimeType: "application/pdf", data: Data("%PDF".utf8))
            ])
        ],
        temperature: 0.7,
        topP: 0.9,
        maxOutputTokens: 128,
        tools: ["lookup": ["type": "object", "properties": ["query": ["type": "string"]]]],
        extraBody: [
            "topK": 40,
            "thinking": ["type": "enabled"],
            "metadata": ["userId": "user-1"],
            "contextManagement": [
                "edits": [
                    [
                        "type": "clear_tool_uses_20250919",
                        "clearAtLeast": ["type": "input_tokens", "value": 2000],
                        "clearToolInputs": true,
                        "excludeTools": ["lookup"]
                    ]
                ]
            ],
            "mcpServers": [
                [
                    "type": "url",
                    "name": "docs",
                    "url": "https://mcp.example.com",
                    "authorizationToken": "token",
                    "toolConfiguration": ["allowedTools": ["search"], "enabled": true]
                ]
            ],
            "effort": "high",
            "taskBudget": ["type": "tokens", "total": 20000, "remainingTokens": 12000],
            "inferenceGeo": "us",
            "cacheControl": ["type": "ephemeral", "ttl": "5m"]
        ]
    ))

    #expect(result.finishReason == "length")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["max_tokens"]?.intValue == 1152)
    #expect(body["temperature"] == nil)
    #expect(body["top_p"] == nil)
    #expect(body["top_k"] == nil)
    #expect(body["thinking"]?["budget_tokens"]?.intValue == 1024)
    #expect(body["metadata"]?["user_id"]?.stringValue == "user-1")
    #expect(body["context_management"]?["edits"]?[0]?["clear_at_least"]?["value"]?.intValue == 2000)
    #expect(body["context_management"]?["edits"]?[0]?["clear_tool_inputs"]?.boolValue == true)
    #expect(body["context_management"]?["edits"]?[0]?["exclude_tools"]?[0]?.stringValue == "lookup")
    #expect(body["mcp_servers"]?[0]?["authorization_token"]?.stringValue == "token")
    #expect(body["mcp_servers"]?[0]?["tool_configuration"]?["allowed_tools"]?[0]?.stringValue == "search")
    #expect(body["output_config"]?["effort"]?.stringValue == "high")
    #expect(body["output_config"]?["task_budget"]?["remaining"]?.intValue == 12000)
    #expect(body["inference_geo"]?.stringValue == "us")
    #expect(body["cache_control"]?["ttl"]?.stringValue == "5m")
    #expect(body["tools"]?[0]?["name"]?.stringValue == "lookup")
    #expect(body["messages"]?[0]?["content"]?[1]?["type"]?.stringValue == "document")
    #expect(body["messages"]?[0]?["content"]?[1]?["source"]?["media_type"]?.stringValue == "application/pdf")
    #expect(body["messages"]?[0]?["content"]?[1]?["source"]?["data"]?.stringValue == Data("%PDF".utf8).base64EncodedString())
}

@Test func anthropicToolsHelpersMirrorProviderExecutedToolFactories() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"tools"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "claude-key",
        headers: ["anthropic-beta": "existing-beta"],
        transport: transport
    ))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use Anthropic tools.")],
        tools: [
            "advisor": AnthropicTools.advisor_20260301(
                model: "claude-opus-4-8",
                maxUses: 2,
                caching: ["type": "ephemeral", "ttl": "5m"]
            ),
            "bash": AnthropicTools.bash_20250124(),
            "code": AnthropicTools.codeExecution_20250825(),
            "computer": AnthropicTools.computer_20251124(displayWidthPx: 1280, displayHeightPx: 720, displayNumber: 1, enableZoom: true),
            "memory": AnthropicTools.memory_20250818(),
            "text_editor": AnthropicTools.textEditor_20250728(maxCharacters: 4000),
            "web_fetch": AnthropicTools.webFetch_20250910(
                maxUses: 3,
                allowedDomains: ["example.com"],
                blockedDomains: ["blocked.example"],
                citations: ["enabled": true],
                maxContentTokens: 1200
            ),
            "web_search": AnthropicTools.webSearch_20260209(
                maxUses: 4,
                allowedDomains: ["docs.example"],
                blockedDomains: ["old.example"],
                userLocation: ["type": "approximate", "city": "Tokyo", "country": "JP"]
            ),
            "tool_search": AnthropicTools.toolSearchRegex_20251119()
        ],
        headers: ["anthropic-beta": "request-beta"]
    ))

    let request = try #require(await transport.requests().first)
    let betaHeader = try #require(request.headers["anthropic-beta"])
    #expect(betaHeader.contains("existing-beta"))
    #expect(betaHeader.contains("request-beta"))
    #expect(betaHeader.contains("advisor-tool-2026-03-01"))
    #expect(betaHeader.contains("computer-use-2025-01-24"))
    #expect(betaHeader.contains("code-execution-2025-08-25"))
    #expect(betaHeader.contains("computer-use-2025-11-24"))
    #expect(betaHeader.contains("context-management-2025-06-27"))
    #expect(betaHeader.contains("web-fetch-2025-09-10"))
    #expect(betaHeader.contains("code-execution-web-tools-2026-02-09"))

    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    let advisor = try #require(tools.first { $0["type"]?.stringValue == "advisor_20260301" })
    #expect(advisor["name"]?.stringValue == "advisor")
    #expect(advisor["model"]?.stringValue == "claude-opus-4-8")
    #expect(advisor["max_uses"]?.intValue == 2)
    #expect(advisor["caching"]?["ttl"]?.stringValue == "5m")
    #expect(tools.contains { $0["type"]?.stringValue == "bash_20250124" && $0["name"]?.stringValue == "bash" })
    #expect(tools.contains { $0["type"]?.stringValue == "code_execution_20250825" && $0["name"]?.stringValue == "code_execution" })
    let computer = try #require(tools.first { $0["type"]?.stringValue == "computer_20251124" })
    #expect(computer["display_width_px"]?.intValue == 1280)
    #expect(computer["display_height_px"]?.intValue == 720)
    #expect(computer["display_number"]?.intValue == 1)
    #expect(computer["enable_zoom"]?.boolValue == true)
    #expect(tools.contains { $0["type"]?.stringValue == "memory_20250818" && $0["name"]?.stringValue == "memory" })
    let textEditor = try #require(tools.first { $0["type"]?.stringValue == "text_editor_20250728" })
    #expect(textEditor["name"]?.stringValue == "str_replace_based_edit_tool")
    #expect(textEditor["max_characters"]?.intValue == 4000)
    let webFetch = try #require(tools.first { $0["type"]?.stringValue == "web_fetch_20250910" })
    #expect(webFetch["max_uses"]?.intValue == 3)
    #expect(webFetch["allowed_domains"]?[0]?.stringValue == "example.com")
    #expect(webFetch["blocked_domains"]?[0]?.stringValue == "blocked.example")
    #expect(webFetch["citations"]?["enabled"]?.boolValue == true)
    #expect(webFetch["max_content_tokens"]?.intValue == 1200)
    let webSearch = try #require(tools.first { $0["type"]?.stringValue == "web_search_20260209" })
    #expect(webSearch["max_uses"]?.intValue == 4)
    #expect(webSearch["allowed_domains"]?[0]?.stringValue == "docs.example")
    #expect(webSearch["blocked_domains"]?[0]?.stringValue == "old.example")
    #expect(webSearch["user_location"]?["city"]?.stringValue == "Tokyo")
    #expect(tools.contains { $0["type"]?.stringValue == "tool_search_tool_regex_20251119" && $0["name"]?.stringValue == "tool_search_tool_regex" })
}

@Test func googleVertexAnthropicToolsHelpersExposeSupportedSubset() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"vertex anthropic tools"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
    """))
    let provider = try AIProviders.googleVertexAnthropic(
        project: "test-project",
        location: "us-central1",
        settings: ProviderSettings(apiKey: "vertex-token", transport: transport)
    )
    let model = try provider.languageModel("claude-sonnet-4@20250514")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use Vertex Anthropic tools.")],
        tools: [
            "bash": GoogleVertexAnthropicTools.bash_20241022(),
            "search": GoogleVertexAnthropicTools.webSearch_20250305(maxUses: 2),
            "bm25": GoogleVertexAnthropicTools.toolSearchBm25_20251119()
        ]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString.contains("/claude-sonnet-4@20250514:rawPredict"))
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["anthropic_version"]?.stringValue == "vertex-2023-10-16")
    #expect(body["model"] == nil)
    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.contains { $0["type"]?.stringValue == "bash_20241022" && $0["name"]?.stringValue == "bash" })
    #expect(tools.contains { $0["type"]?.stringValue == "web_search_20250305" && $0["max_uses"]?.intValue == 2 })
    #expect(tools.contains { $0["type"]?.stringValue == "tool_search_tool_bm25_20251119" && $0["name"]?.stringValue == "tool_search_tool_bm25" })
}

@Test func anthropicLanguageParsesToolUseBlocks() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"I'll check."},{"type":"tool_use","id":"toolu_1","name":"lookup","input":{"query":"weather"}},{"type":"server_tool_use","id":"srvtoolu_1","name":"web_search","input":{"query":"weather"}}],"stop_reason":"tool_use","usage":{"input_tokens":5,"output_tokens":7}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-5-haiku-latest")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Use a tool.")],
        tools: ["lookup": ["type": "object", "properties": ["query": ["type": "string"]]]]
    ))

    #expect(result.text == "I'll check.")
    #expect(result.finishReason == "tool-calls")
    #expect(result.toolCalls.count == 2)
    #expect(result.toolCalls[0].id == "toolu_1")
    #expect(result.toolCalls[0].name == "lookup")
    #expect(try decodeJSONBody(Data(result.toolCalls[0].arguments.utf8))["query"]?.stringValue == "weather")
    #expect(result.toolCalls[0].providerExecuted == false)
    #expect(result.toolCalls[1].id == "srvtoolu_1")
    #expect(result.toolCalls[1].name == "web_search")
    #expect(try decodeJSONBody(Data(result.toolCalls[1].arguments.utf8))["query"]?.stringValue == "weather")
    #expect(result.toolCalls[1].providerExecuted == true)
}

@Test func anthropicLanguageMapsCitationAndWebSearchSources() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"server_tool_use","id":"srvtoolu_1","name":"web_search","input":{"query":"latest AI news"}},{"type":"web_search_tool_result","tool_use_id":"srvtoolu_1","content":[{"type":"web_search_result","url":"https://example.com/ai-news","title":"Latest AI Developments","encrypted_content":"encrypted_content_123","page_age":"January 15, 2025"}]},{"type":"text","text":"The report shows growth.","citations":[{"type":"page_location","cited_text":"Revenue increased by 25% year over year","document_index":0,"document_title":"Financial Report 2023","start_page_number":5,"end_page_number":6},{"type":"web_search_result_location","cited_text":"AI continues to advance","url":"https://example.com/ai-news","title":"Latest AI Developments","encrypted_index":"enc_1"}]}],"stop_reason":"end_turn","usage":{"input_tokens":5,"output_tokens":7}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-5-haiku-latest")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .data(mimeType: "application/pdf", data: Data("%PDF".utf8)),
            .text("Summarize with sources.")
        ])
    ]))

    #expect(result.text == "The report shows growth.")
    #expect(result.sources.count == 3)
    #expect(result.sources[0].id == "anthropic-source-0")
    #expect(result.sources[0].sourceType == "url")
    #expect(result.sources[0].url == "https://example.com/ai-news")
    #expect(result.sources[0].title == "Latest AI Developments")
    #expect(result.sources[0].providerMetadata["anthropic"]?["pageAge"]?.stringValue == "January 15, 2025")
    #expect(result.sources[1].sourceType == "document")
    #expect(result.sources[1].title == "Financial Report 2023")
    #expect(result.sources[1].mediaType == "application/pdf")
    #expect(result.sources[1].providerMetadata["anthropic"]?["citedText"]?.stringValue == "Revenue increased by 25% year over year")
    #expect(result.sources[1].providerMetadata["anthropic"]?["startPageNumber"]?.intValue == 5)
    #expect(result.sources[1].providerMetadata["anthropic"]?["endPageNumber"]?.intValue == 6)
    #expect(result.sources[2].sourceType == "url")
    #expect(result.sources[2].url == "https://example.com/ai-news")
    #expect(result.sources[2].providerMetadata["anthropic"]?["citedText"]?.stringValue == "AI continues to advance")
    #expect(result.sources[2].providerMetadata["anthropic"]?["encryptedIndex"]?.stringValue == "enc_1")
}

@Test func googleRequestUsesGenerateContentShape() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"gemini"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":2,"totalTokenCount":3}}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Ping")]))

    #expect(result.text == "gemini")
    #expect(result.usage?.totalTokens == 3)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
    #expect(request.headers["x-goog-api-key"] == "gemini-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["contents"]?[0]?["role"]?.stringValue == "user")
}

@Test func googleLanguageMapsFunctionToolsAndToolChoice() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"tool-ready"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Use lookup.")],
        tools: [
            "lookup": [
                "type": "object",
                "description": "Look up a value.",
                "properties": ["query": ["type": "string"]],
                "required": ["query"],
                "additionalProperties": false,
                "$schema": "http://json-schema.org/draft-07/schema#"
            ]
        ],
        extraBody: ["toolChoice": ["type": "tool", "toolName": "lookup"]]
    ))

    #expect(result.text == "tool-ready")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let declaration = try #require(body["tools"]?[0]?["functionDeclarations"]?[0])
    #expect(declaration["name"]?.stringValue == "lookup")
    #expect(declaration["description"]?.stringValue == "Look up a value.")
    #expect(declaration["parameters"]?["properties"]?["query"]?["type"]?.stringValue == "string")
    #expect(declaration["parameters"]?["required"]?[0]?.stringValue == "query")
    #expect(declaration["parameters"]?["additionalProperties"] == nil)
    #expect(declaration["parameters"]?["$schema"] == nil)
    #expect(body["toolConfig"]?["functionCallingConfig"]?["mode"]?.stringValue == "ANY")
    #expect(body["toolConfig"]?["functionCallingConfig"]?["allowedFunctionNames"]?[0]?.stringValue == "lookup")
    #expect(body["toolChoice"] == nil)
}

@Test func googleLanguageMapsProviderDefinedTools() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"grounded"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Search.")],
        tools: [
            "google.google_search": GoogleTools.googleSearch(searchTypes: ["imageSearch": [:]]),
            "google.code_execution": GoogleTools.codeExecution()
        ],
        extraBody: ["toolChoice": "auto"]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.contains { $0["googleSearch"]?["searchTypes"]?["imageSearch"] != nil })
    #expect(tools.contains { $0["codeExecution"]?.objectValue?.isEmpty == true })
    #expect(body["toolConfig"] == nil)
    #expect(body["toolChoice"] == nil)
}

@Test func googleToolsHelpersMirrorProviderExecutedToolFactories() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"grounded"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use Google tools.")],
        tools: [
            "google.google_search": GoogleTools.googleSearch(
                searchTypes: ["webSearch": [:], "imageSearch": [:]],
                timeRangeFilter: ["startTime": "2025-01-01T00:00:00Z", "endTime": "2025-02-01T00:00:00Z"]
            ),
            "google.enterprise_web_search": GoogleTools.enterpriseWebSearch(),
            "google.google_maps": GoogleTools.googleMaps(),
            "google.url_context": GoogleTools.urlContext(),
            "google.file_search": GoogleTools.fileSearch(
                fileSearchStoreNames: ["fileSearchStores/store-1"],
                metadataFilter: #"author="Ada""#,
                topK: 4
            ),
            "google.code_execution": GoogleTools.codeExecution()
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    let googleSearch = try #require(tools.first { $0["googleSearch"] != nil })
    #expect(googleSearch["googleSearch"]?["searchTypes"]?["webSearch"] != nil)
    #expect(googleSearch["googleSearch"]?["timeRangeFilter"]?["startTime"]?.stringValue == "2025-01-01T00:00:00Z")
    #expect(tools.contains { $0["enterpriseWebSearch"]?.objectValue?.isEmpty == true })
    #expect(tools.contains { $0["googleMaps"]?.objectValue?.isEmpty == true })
    #expect(tools.contains { $0["urlContext"]?.objectValue?.isEmpty == true })
    let fileSearch = try #require(tools.first { $0["fileSearch"] != nil })
    #expect(fileSearch["fileSearch"]?["fileSearchStoreNames"]?[0]?.stringValue == "fileSearchStores/store-1")
    #expect(fileSearch["fileSearch"]?["metadataFilter"]?.stringValue == #"author="Ada""#)
    #expect(fileSearch["fileSearch"]?["topK"]?.intValue == 4)
    #expect(tools.contains { $0["codeExecution"]?.objectValue?.isEmpty == true })
}

@Test func googleLanguageParsesFunctionCalls() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"functionCall":{"name":"weather","args":{"location":"San Francisco"}}}],"role":"model"},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":29,"candidatesTokenCount":15,"totalTokenCount":44}}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Weather?")]))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.usage?.totalTokens == 44)
    #expect(result.toolCalls.count == 1)
    #expect(result.toolCalls[0].id == "tool-call-0")
    #expect(result.toolCalls[0].name == "weather")
    #expect(try decodeJSONBody(Data(result.toolCalls[0].arguments.utf8))["location"]?.stringValue == "San Francisco")
}

@Test func googleLanguageExtractsGroundingSources() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"grounded"}]},"finishReason":"STOP","groundingMetadata":{"groundingChunks":[{"web":{"uri":"https://source.example.com","title":"Source Title"}},{"retrievedContext":{"uri":"gs://rag-corpus/document.pdf","title":"RAG Document","text":"Retrieved context"}},{"retrievedContext":{"fileSearchStore":"fileSearchStores/test-store-xyz","title":"Test Document"}},{"maps":{"uri":"https://maps.google.com/maps?cid=12345","title":"Best Restaurant"}},{"image":{"sourceUri":"https://example.com/article","imageUri":"https://example.com/image.jpg","title":"Image Result"}}]}}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Ground it.")]))

    #expect(result.text == "grounded")
    #expect(result.sources.count == 5)
    #expect(result.sources[0].id == "grounding-0")
    #expect(result.sources[0].sourceType == "url")
    #expect(result.sources[0].url == "https://source.example.com")
    #expect(result.sources[0].title == "Source Title")
    #expect(result.sources[1].sourceType == "document")
    #expect(result.sources[1].title == "RAG Document")
    #expect(result.sources[1].mediaType == "application/pdf")
    #expect(result.sources[1].filename == "document.pdf")
    #expect(result.sources[2].sourceType == "document")
    #expect(result.sources[2].title == "Test Document")
    #expect(result.sources[2].mediaType == "application/octet-stream")
    #expect(result.sources[2].filename == "test-store-xyz")
    #expect(result.sources[3].sourceType == "url")
    #expect(result.sources[3].url == "https://maps.google.com/maps?cid=12345")
    #expect(result.sources[3].title == "Best Restaurant")
    #expect(result.sources[4].sourceType == "url")
    #expect(result.sources[4].url == "https://example.com/article")
    #expect(result.sources[4].title == "Image Result")
    #expect(result.sources[4].rawValue?["image"]?["imageUri"]?.stringValue == "https://example.com/image.jpg")
}

@Test func googleImagenUsesPredictInstancesAndParameters() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"predictions":[{"bytesBase64Encoded":"image-1"},{"bytesBase64Encoded":"image-2"}]}"#))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.imageModel("imagen-4.0-generate-001")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "16:9",
        count: 2,
        extraBody: ["negativePrompt": "blur", "personGeneration": "allow_adult"]
    ))

    #expect(result.base64Images == ["image-1", "image-2"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/imagen-4.0-generate-001:predict")
    #expect(request.headers["x-goog-api-key"] == "gemini-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["instances"]?[0]?["prompt"]?.stringValue == "cat")
    #expect(body["parameters"]?["sampleCount"]?.intValue == 2)
    #expect(body["parameters"]?["aspectRatio"]?.stringValue == "16:9")
    #expect(body["parameters"]?["negativePrompt"]?.stringValue == "blur")
    #expect(body["parameters"]?["personGeneration"]?.stringValue == "allow_adult")
}

@Test func googleGeminiImageUsesGenerateContentImageModality() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"gemini-image"}}]}}]}"#))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.imageModel("gemini-2.5-flash-image")

    let result = try await model.generateImage(ImageGenerationRequest(prompt: "cat", size: "1:1"))

    #expect(result.base64Images == ["gemini-image"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["contents"]?[0]?["parts"]?[0]?["text"]?.stringValue == "cat")
    #expect(body["generationConfig"]?["responseModalities"]?[0]?.stringValue == "IMAGE")
    #expect(body["generationConfig"]?["imageConfig"]?["aspectRatio"]?.stringValue == "1:1")
}

@Test func googleVeoCreatesLongRunningOperationAndPollsVideoURL() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"name":"operations/video-1","done":false}"#),
        jsonResponse(#"{"name":"operations/video-1","done":true,"response":{"generateVideoResponse":{"generatedSamples":[{"video":{"uri":"https://generativelanguage.googleapis.com/files/video-123.mp4?alt=media"}}]}}}"#)
    ])
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.videoModel("veo-3.1-generate-preview")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        aspectRatio: "16:9",
        durationSeconds: 5,
        extraBody: ["sampleCount": 1, "resolution": "1920x1080", "seed": 42, "negativePrompt": "rain", "pollIntervalMs": 0]
    ))

    #expect(result.urls == ["https://generativelanguage.googleapis.com/files/video-123.mp4?alt=media&key=gemini-key"])
    #expect(result.operationID == "operations/video-1")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/veo-3.1-generate-preview:predictLongRunning")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["instances"]?[0]?["prompt"]?.stringValue == "cat running")
    #expect(body["parameters"]?["sampleCount"]?.intValue == 1)
    #expect(body["parameters"]?["aspectRatio"]?.stringValue == "16:9")
    #expect(body["parameters"]?["durationSeconds"]?.intValue == 5)
    #expect(body["parameters"]?["resolution"]?.stringValue == "1080p")
    #expect(body["parameters"]?["seed"]?.intValue == 42)
    #expect(body["parameters"]?["negativePrompt"]?.stringValue == "rain")
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/operations/video-1")
}

@Test func googleInteractionsUsesInteractionsEndpointAndInputShape() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"interaction-1","status":"completed","service_tier":"standard","model":"gemini-2.5-flash","usage":{"total_tokens":58,"total_input_tokens":7,"total_output_tokens":19,"total_thought_tokens":32,"total_cached_tokens":0},"steps":[{"type":"thought","summary":[{"type":"text","text":"thinking"}]},{"type":"model_output","content":[{"type":"text","text":"Hello from interactions"}]}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsModel("gemini-2.5-flash")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.system("Be helpful."), .user("Hello")],
        temperature: 0.3,
        topP: 0.8,
        maxOutputTokens: 64,
        extraBody: [
            "previousInteractionId": "interaction-old",
            "serviceTier": "flex",
            "store": false,
            "responseModalities": ["text", "image"],
            "responseFormat": [
                ["type": "image", "mimeType": "image/png", "aspectRatio": "1:1", "imageSize": "1K"]
            ],
            "thinkingLevel": "high",
            "thinkingSummaries": true
        ]
    ))

    #expect(result.text == "Hello from interactions")
    #expect(result.finishReason == "stop")
    #expect(result.usage?.inputTokens == 7)
    #expect(result.usage?.outputTokens == 51)
    #expect(result.usage?.totalTokens == 58)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/interactions")
    #expect(request.headers["x-goog-api-key"] == "gemini-key")
    #expect(request.headers["Api-Revision"] == "2026-05-20")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "gemini-2.5-flash")
    #expect(body["system_instruction"]?.stringValue == "Be helpful.")
    #expect(body["input"]?[0]?["type"]?.stringValue == "user_input")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    #expect(body["generation_config"]?["temperature"]?.doubleValue == 0.3)
    #expect(body["generation_config"]?["top_p"]?.doubleValue == 0.8)
    #expect(body["generation_config"]?["max_output_tokens"]?.intValue == 64)
    #expect(body["generation_config"]?["thinking_level"]?.stringValue == "high")
    #expect(body["generation_config"]?["thinking_summaries"]?.boolValue == true)
    #expect(body["previous_interaction_id"]?.stringValue == "interaction-old")
    #expect(body["service_tier"]?.stringValue == "flex")
    #expect(body["store"]?.boolValue == false)
    #expect(body["response_modalities"]?[0]?.stringValue == "text")
    #expect(body["response_format"]?[0]?["mime_type"]?.stringValue == "image/png")
    #expect(body["response_format"]?[0]?["aspect_ratio"]?.stringValue == "1:1")
    #expect(body["response_format"]?[0]?["image_size"]?.stringValue == "1K")
}

@Test func googleInteractionsExtractsSourcesAndProviderMetadata() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"interaction-1","status":"completed","service_tier":"standard","usage":{"total_tokens":12,"total_input_tokens":3,"total_output_tokens":4},"steps":[{"type":"model_output","content":[{"type":"text","text":"Grounded answer","annotations":[{"type":"url_citation","url":"https://example.com/article","title":"Example Article"},{"type":"file_citation","document_uri":"gs://bucket/path/report.pdf","file_name":"report.pdf"},{"type":"place_citation","url":"https://maps.google.com/?q=foo","name":"Foo Place"}]}]},{"type":"url_context_result","call_id":"url-1","result":[{"url":"https://context.example.com/a","status":"success"},{"url":"https://context.example.com/b","status":"error"}]},{"type":"google_search_result","call_id":"search-1","result":[{"url":"https://news.example.com/1","title":"Article 1"},{"search_suggestions":"<html/>"}]},{"type":"file_search_result","call_id":"file-1","result":[{"file_name":"notes.md","source":"fileSearchStores/x/notes.md"},{"document_uri":"https://storage.example.com/file.txt"}]},{"type":"google_maps_result","call_id":"maps-1","result":[{"places":[{"name":"Bar Cafe","url":"https://maps.google.com/?q=bar"},{"name":"No URL"}]}]}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsModel("gemini-2.5-flash")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Ground it.")]))

    #expect(result.text == "Grounded answer")
    #expect(result.providerMetadata["google"]?["interactionId"]?.stringValue == "interaction-1")
    #expect(result.providerMetadata["google"]?["serviceTier"]?.stringValue == "standard")
    #expect(result.sources.count == 8)
    #expect(result.sources[0].sourceType == "url")
    #expect(result.sources[0].url == "https://example.com/article")
    #expect(result.sources[0].title == "Example Article")
    #expect(result.sources[1].sourceType == "document")
    #expect(result.sources[1].title == "report.pdf")
    #expect(result.sources[1].mediaType == "application/pdf")
    #expect(result.sources[1].filename == "report.pdf")
    #expect(result.sources[2].sourceType == "url")
    #expect(result.sources[2].url == "https://maps.google.com/?q=foo")
    #expect(result.sources[2].title == "Foo Place")
    #expect(result.sources[3].url == "https://context.example.com/a")
    #expect(result.sources[4].url == "https://news.example.com/1")
    #expect(result.sources[4].title == "Article 1")
    #expect(result.sources[5].sourceType == "document")
    #expect(result.sources[5].title == "notes.md")
    #expect(result.sources[5].mediaType == "text/markdown")
    #expect(result.sources[5].filename == "notes.md")
    #expect(result.sources[6].sourceType == "url")
    #expect(result.sources[6].url == "https://storage.example.com/file.txt")
    #expect(result.sources[7].sourceType == "url")
    #expect(result.sources[7].url == "https://maps.google.com/?q=bar")
    #expect(result.sources[7].title == "Bar Cafe")
}

@Test func googleInteractionsStreamsTextAndFinishUsage() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"interaction":{"id":"interaction-1","status":"in_progress"},"event_type":"interaction.created"}

    data: {"index":0,"step":{"type":"model_output"},"event_type":"step.start"}

    data: {"index":0,"delta":{"type":"text","text":"hello "},"event_type":"step.delta"}

    data: {"index":0,"delta":{"type":"text","text":"world"},"event_type":"step.delta"}

    data: {"interaction":{"id":"interaction-1","status":"completed","usage":{"total_tokens":12,"total_input_tokens":3,"total_output_tokens":4,"total_thought_tokens":5}},"event_type":"interaction.completed"}

    data: [DONE]

    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsModel("gemini-2.5-flash")

    var deltas: [String] = []
    var finishReason: String?
    var totalTokens: Int?
    var outputTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hello")])) {
        switch part {
        case let .textDelta(delta):
            deltas.append(delta)
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
            outputTokens = usage?.outputTokens
        default:
            break
        }
    }

    #expect(deltas == ["hello ", "world"])
    #expect(finishReason == "stop")
    #expect(totalTokens == 12)
    #expect(outputTokens == 9)
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
    #expect(body["model"]?.stringValue == "gemini-2.5-flash")
}

@Test func googleInteractionsStreamsSourcesAndMetadata() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"interaction":{"id":"interaction-1","status":"in_progress","service_tier":"standard"},"event_type":"interaction.created"}

    data: {"index":0,"step":{"type":"model_output","content":[{"type":"text","text":"","annotations":[{"type":"url_citation","url":"https://example.com/article","title":"Example Article"}]}]},"event_type":"step.start"}

    data: {"index":0,"delta":{"type":"text","text":"hello"},"event_type":"step.delta"}

    data: {"index":0,"delta":{"type":"text_annotation","annotations":[{"type":"url_citation","url":"https://example.com/article","title":"Example Article"},{"type":"file_citation","document_uri":"gs://bucket/report.pdf","file_name":"report.pdf"}]},"event_type":"step.delta"}

    data: {"index":1,"step":{"type":"google_search_result","call_id":"search-1","result":[{"url":"https://news.example.com/1","title":"Article 1"}]},"event_type":"step.start"}

    data: {"interaction":{"id":"interaction-1","status":"completed","service_tier":"priority","usage":{"total_tokens":12,"total_input_tokens":3,"total_output_tokens":4,"total_thought_tokens":5}},"event_type":"interaction.completed"}

    data: [DONE]

    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsModel("gemini-2.5-flash")

    var text: [String] = []
    var sources: [AISource] = []
    var metadata: [[String: JSONValue]] = []
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hello")])) {
        switch part {
        case let .textDelta(delta):
            text.append(delta)
        case let .source(source):
            sources.append(source)
        case let .metadata(value):
            metadata.append(value)
        case let .finish(_, usage):
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(text == ["hello"])
    #expect(sources.count == 3)
    #expect(sources[0].url == "https://example.com/article")
    #expect(sources[0].title == "Example Article")
    #expect(sources[1].sourceType == "document")
    #expect(sources[1].mediaType == "application/pdf")
    #expect(sources[1].filename == "report.pdf")
    #expect(sources[2].url == "https://news.example.com/1")
    #expect(sources[2].title == "Article 1")
    #expect(metadata.first?["google"]?["interactionId"]?.stringValue == "interaction-1")
    #expect(metadata.first?["google"]?["serviceTier"]?.stringValue == "standard")
    #expect(metadata.last?["google"]?["serviceTier"]?.stringValue == "priority")
    #expect(totalTokens == 12)
}

@Test func googleInteractionsParsesFunctionCallSteps() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"interaction-1","status":"requires_action","usage":{"total_tokens":109,"total_input_tokens":53,"total_output_tokens":15,"total_thought_tokens":41},"steps":[{"type":"thought","signature":"sig"},{"id":"zggxzq8r","type":"function_call","name":"getWeather","arguments":{"location":"San Francisco"}}],"model":"gemini-2.5-flash"}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsModel("gemini-2.5-flash")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Weather?")]))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.usage?.totalTokens == 109)
    #expect(result.toolCalls.count == 1)
    #expect(result.toolCalls[0].id == "zggxzq8r")
    #expect(result.toolCalls[0].name == "getWeather")
    #expect(try decodeJSONBody(Data(result.toolCalls[0].arguments.utf8))["location"]?.stringValue == "San Francisco")
}

@Test func googleInteractionsStreamsFunctionCallSteps() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"interaction":{"id":"interaction-1","status":"in_progress"},"event_type":"interaction.created"}

    data: {"index":1,"step":{"id":"61nzpsv4","signature":"","type":"function_call","name":"getWeather","arguments":{}},"event_type":"step.start"}

    data: {"index":1,"delta":{"arguments":"{\\"location\\":\\"San Francisco\\"}","type":"arguments_delta"},"event_type":"step.delta"}

    data: {"index":1,"event_type":"step.stop"}

    data: {"interaction":{"id":"interaction-1","status":"requires_action","usage":{"total_tokens":133,"total_input_tokens":53,"total_output_tokens":15,"total_thought_tokens":65}},"event_type":"interaction.completed"}

    data: [DONE]

    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsModel("gemini-2.5-flash")

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

    let call = try #require(finalCall)
    #expect(deltas == [#"{"location":"San Francisco"}"#])
    #expect(call.id == "61nzpsv4")
    #expect(call.name == "getWeather")
    #expect(try decodeJSONBody(Data(call.arguments.utf8))["location"]?.stringValue == "San Francisco")
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 133)
}

@Test func googleInteractionsAgentUsesAgentAndBackgroundBody() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"agent-interaction","status":"in_progress"}"#),
        jsonResponse(#"{"id":"agent-interaction","status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":"agent done"}]}],"usage":{"total_tokens":4,"total_input_tokens":1,"total_output_tokens":3}}"#)
    ])
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsAgent("deep-research")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Research")],
        extraBody: [
            "background": true,
            "agentConfig": ["type": "deep-research", "thinkingSummaries": true, "collaborativePlanning": false],
            "environment": ["type": "remote"]
        ]
    ))

    #expect(result.text == "agent done")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["agent"]?.stringValue == "deep-research")
    #expect(body["model"] == nil)
    #expect(body["background"]?.boolValue == true)
    #expect(body["agent_config"]?["type"]?.stringValue == "deep-research")
    #expect(body["agent_config"]?["thinking_summaries"]?.boolValue == true)
    #expect(body["agent_config"]?["collaborative_planning"]?.boolValue == false)
    #expect(body["environment"]?["type"]?.stringValue == "remote")
    #expect(body["generation_config"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/interactions/agent-interaction")
}

@Test func missingAPIKeyThrowsProviderSpecificError() throws {
    #expect(throws: AIError.self) {
        _ = try AIProviders.openAI(settings: ProviderSettings())
    }
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

@Test func openAICompatibleStreamsIncludeUsageWhenEnabled() async throws {
    let chatTransport = RecordingTransport(response: sseResponse("""
    data: {"choices":[{"delta":{"content":"hi"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}

    data: [DONE]

    """))
    let chatProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: chatTransport,
        includeUsage: true
    )
    let chatModel = try chatProvider.chatModel("chat-model")

    var chatUsage: TokenUsage?
    for try await part in chatModel.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        if case let .finish(_, usage) = part {
            chatUsage = usage
        }
    }

    #expect(chatUsage?.totalTokens == 3)
    let chatBody = try decodeJSONBody(try #require((await chatTransport.requests()).first?.body))
    #expect(chatBody["stream"] == true)
    #expect(chatBody["stream_options"]?["include_usage"]?.boolValue == true)

    let completionTransport = RecordingTransport(response: sseResponse("""
    data: {"choices":[{"text":"hel"}]}

    data: {"choices":[{"text":"lo","finish_reason":"stop"}],"usage":{"total_tokens":4}}

    data: [DONE]

    """))
    let completionProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: completionTransport,
        includeUsage: true
    )
    let completionModel = try completionProvider.completionModel("completion-model")

    var completionDeltas: [String] = []
    var completionUsage: TokenUsage?
    for try await part in completionModel.stream(LanguageModelRequest(messages: [.user("Finish")])) {
        switch part {
        case let .textDelta(delta):
            completionDeltas.append(delta)
        case let .finish(_, usage):
            completionUsage = usage
        default:
            break
        }
    }

    #expect(completionDeltas == ["hel", "lo"])
    #expect(completionUsage?.totalTokens == 4)
    let completionBody = try decodeJSONBody(try #require((await completionTransport.requests()).first?.body))
    #expect(completionBody["stream"] == true)
    #expect(completionBody["stream_options"]?["include_usage"]?.boolValue == true)
}

@Test func openAICompatibleAppendsQueryParamsToModelURLs() async throws {
    let chatTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"hello"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let chatProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com/base",
        apiKey: "test-key",
        queryParams: ["api-version": "2026-01-01", "region": "tokyo"],
        transport: chatTransport
    )
    _ = try await chatProvider.chatModel("chat-model").generate(LanguageModelRequest(messages: [.user("Hi")]))
    let chatRequest = try #require(await chatTransport.requests().first)
    #expect(chatRequest.url.absoluteString == "https://api.example.com/base/chat/completions?api-version=2026-01-01&region=tokyo")

    let completionTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"text":"done","finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let completionProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com/base",
        apiKey: "test-key",
        queryParams: ["api-version": "2026-01-01", "region": "tokyo"],
        transport: completionTransport
    )
    _ = try await completionProvider.completionModel("completion-model").generate(LanguageModelRequest(messages: [.user("Finish")]))
    let completionRequest = try #require(await completionTransport.requests().first)
    #expect(completionRequest.url.absoluteString == "https://api.example.com/base/completions?api-version=2026-01-01&region=tokyo")

    let embeddingTransport = RecordingTransport(response: jsonResponse("""
    {"data":[{"embedding":[0.1,0.2]}],"usage":{"total_tokens":2}}
    """))
    let embeddingProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com/base",
        apiKey: "test-key",
        queryParams: ["api-version": "2026-01-01", "region": "tokyo"],
        transport: embeddingTransport
    )
    _ = try await embeddingProvider.embeddingModel("embedding-model").embed(EmbeddingRequest(values: ["hello"]))
    let embeddingRequest = try #require(await embeddingTransport.requests().first)
    #expect(embeddingRequest.url.absoluteString == "https://api.example.com/base/embeddings?api-version=2026-01-01&region=tokyo")
}

@Test func openAICompatibleMapsResponseFormatForStructuredOutputs() async throws {
    let fallbackTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"{\\"value\\":\\"plain\\"}"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let fallbackProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: fallbackTransport
    )

    _ = try await fallbackProvider.chatModel("chat-model").generate(LanguageModelRequest(
        messages: [.user("JSON")],
        extraBody: [
            "responseFormat": [
                "type": "json",
                "schema": [
                    "type": "object",
                    "properties": ["value": ["type": "string"]],
                    "required": ["value"]
                ]
            ]
        ]
    ))

    let fallbackBody = try decodeJSONBody(try #require((await fallbackTransport.requests()).first?.body))
    #expect(fallbackBody["response_format"]?["type"]?.stringValue == "json_object")
    #expect(fallbackBody["response_format"]?["json_schema"] == nil)
    #expect(fallbackBody["responseFormat"] == nil)

    let structuredTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"{\\"value\\":\\"structured\\"}"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let structuredProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: structuredTransport,
        supportsStructuredOutputs: true
    )

    _ = try await structuredProvider.chatModel("chat-model").generate(LanguageModelRequest(
        messages: [.user("JSON")],
        extraBody: [
            "responseFormat": [
                "type": "json",
                "name": "answer",
                "description": "Answer schema",
                "schema": [
                    "type": "object",
                    "properties": ["value": ["type": "string"]],
                    "required": ["value"]
                ]
            ],
            "strictJsonSchema": false
        ]
    ))

    let structuredBody = try decodeJSONBody(try #require((await structuredTransport.requests()).first?.body))
    #expect(structuredBody["response_format"]?["type"]?.stringValue == "json_schema")
    #expect(structuredBody["response_format"]?["json_schema"]?["name"]?.stringValue == "answer")
    #expect(structuredBody["response_format"]?["json_schema"]?["description"]?.stringValue == "Answer schema")
    #expect(structuredBody["response_format"]?["json_schema"]?["schema"]?["type"]?.stringValue == "object")
    #expect(structuredBody["response_format"]?["json_schema"]?["strict"]?.boolValue == false)
    #expect(structuredBody["responseFormat"] == nil)
    #expect(structuredBody["strictJsonSchema"] == nil)
}

@Test func openAICompatibleTransformsChatRequestBodyForGenerateAndStream() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"hello"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let generateProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: generateTransport,
        transformRequestBody: { body in
            var body = body
            body["model_alias"] = body.removeValue(forKey: "model")
            body["proxy"] = .object(["mode": .string("generate")])
            return body
        }
    )

    _ = try await generateProvider.chatModel("chat-model").generate(LanguageModelRequest(messages: [.user("Hi")]))

    let generateBody = try decodeJSONBody(try #require((await generateTransport.requests()).first?.body))
    #expect(generateBody["model"] == nil)
    #expect(generateBody["model_alias"]?.stringValue == "chat-model")
    #expect(generateBody["proxy"]?["mode"]?.stringValue == "generate")
    #expect(generateBody["messages"]?[0]?["content"]?.stringValue == "Hi")

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"choices":[{"delta":{"content":"hi"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}

    data: [DONE]

    """))
    let streamProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: streamTransport,
        includeUsage: true,
        transformRequestBody: { body in
            var body = body
            body["proxy"] = .object([
                "sawStream": body["stream"] ?? .bool(false),
                "sawIncludeUsage": body["stream_options"]?["include_usage"] ?? .bool(false)
            ])
            body.removeValue(forKey: "stream_options")
            return body
        }
    )

    let streamModel = try streamProvider.chatModel("chat-model")
    for try await _ in streamModel.stream(LanguageModelRequest(messages: [.user("Hi")])) {}

    let streamBody = try decodeJSONBody(try #require((await streamTransport.requests()).first?.body))
    #expect(streamBody["stream"]?.boolValue == true)
    #expect(streamBody["stream_options"] == nil)
    #expect(streamBody["proxy"]?["sawStream"]?.boolValue == true)
    #expect(streamBody["proxy"]?["sawIncludeUsage"]?.boolValue == true)
}

@Test func openAICompatibleMapsNestedProviderOptionsByNamespace() async throws {
    let chatTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"hello"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let chatProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: chatTransport
    )

    _ = try await chatProvider.chatModel("chat-model").generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: [
            "direct": .string("kept"),
            "openai-compatible": .object(["user": .string("deprecated-user")]),
            "openaiCompatible": .object(["reasoningEffort": .string("low")]),
            "test-provider": .object(["custom": .string("raw")]),
            "testProvider": .object(["custom": .string("camel"), "textVerbosity": .string("high")])
        ]
    ))

    let chatBody = try decodeJSONBody(try #require((await chatTransport.requests()).first?.body))
    #expect(chatBody["direct"]?.stringValue == "kept")
    #expect(chatBody["user"]?.stringValue == "deprecated-user")
    #expect(chatBody["reasoning_effort"]?.stringValue == "low")
    #expect(chatBody["verbosity"]?.stringValue == "high")
    #expect(chatBody["custom"]?.stringValue == "camel")
    #expect(chatBody["openai-compatible"] == nil)
    #expect(chatBody["openaiCompatible"] == nil)
    #expect(chatBody["test-provider"] == nil)
    #expect(chatBody["testProvider"] == nil)

    let completionTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"text":"done","finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let completionProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: completionTransport
    )

    _ = try await completionProvider.completionModel("completion-model").generate(LanguageModelRequest(
        messages: [.user("Finish")],
        extraBody: [
            "test-provider": .object(["suffix": .string("raw")]),
            "testProvider": .object(["suffix": .string("camel"), "echo": .bool(true)])
        ]
    ))

    let completionBody = try decodeJSONBody(try #require((await completionTransport.requests()).first?.body))
    #expect(completionBody["suffix"]?.stringValue == "camel")
    #expect(completionBody["echo"]?.boolValue == true)
    #expect(completionBody["test-provider"] == nil)
    #expect(completionBody["testProvider"] == nil)

    let embeddingTransport = RecordingTransport(response: jsonResponse("""
    {"data":[{"embedding":[0.1,0.2]}],"usage":{"total_tokens":2}}
    """))
    let embeddingProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: embeddingTransport
    )

    _ = try await embeddingProvider.embeddingModel("embedding-model").embed(EmbeddingRequest(
        values: ["hello"],
        extraBody: [
            "openaiCompatible": .object(["encoding_format": .string("float")]),
            "test-provider": .object(["dimensions": .number(64)])
        ]
    ))

    let embeddingBody = try decodeJSONBody(try #require((await embeddingTransport.requests()).first?.body))
    #expect(embeddingBody["encoding_format"]?.stringValue == "float")
    #expect(embeddingBody["dimensions"]?.intValue == 64)
    #expect(embeddingBody["openaiCompatible"] == nil)
    #expect(embeddingBody["test-provider"] == nil)

    let imageTransport = RecordingTransport(response: jsonResponse("""
    {"data":[{"b64_json":"image-data"}]}
    """))
    let imageProvider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: imageTransport
    )

    _ = try await imageProvider.imageModel("image-model").generateImage(ImageGenerationRequest(
        prompt: "cat",
        extraBody: [
            "response_format": .string("url"),
            "test-provider": .object(["style": .string("raw")]),
            "testProvider": .object(["style": .string("camel")])
        ]
    ))

    let imageBody = try decodeJSONBody(try #require((await imageTransport.requests()).first?.body))
    #expect(imageBody["response_format"]?.stringValue == "b64_json")
    #expect(imageBody["style"]?.stringValue == "camel")
    #expect(imageBody["test-provider"] == nil)
    #expect(imageBody["testProvider"] == nil)
}

@Test func openAICompatibleImageRejectsMoreThanMaxImagesPerCall() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"unused"}]}"#))
    let provider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: transport
    )
    let model = try provider.imageModel("image-model")

    await #expect(throws: AIError.invalidArgument(argument: "count", message: "OpenAI-compatible image models support at most 10 image(s) per call.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", count: 11))
    }

    #expect(await transport.requests().isEmpty)
}

@Test func openAIImageRejectsMoreThanModelSpecificMaxImagesPerCall() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"unused"}]}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.imageModel("dall-e-3")

    await #expect(throws: AIError.invalidArgument(argument: "count", message: "OpenAI-compatible image models support at most 1 image(s) per call.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", count: 2))
    }

    #expect(await transport.requests().isEmpty)
}

@Test func azureImageDeploymentRejectsMoreThanDefaultMaxImagesPerCall() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"unused"}]}"#))
    let provider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: transport))
    let model = try provider.imageModel("dalle-deployment")

    await #expect(throws: AIError.invalidArgument(argument: "count", message: "OpenAI-compatible image models support at most 1 image(s) per call.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", count: 2))
    }

    #expect(await transport.requests().isEmpty)
}

@Test func openAICompatibleEmbeddingRejectsMoreThanMaxEmbeddingsPerCall() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"embedding":[0.1,0.2]}]}"#))
    let provider = try AIProviders.openAICompatible(
        name: "test-provider",
        baseURL: "https://api.example.com",
        apiKey: "test-key",
        transport: transport,
        maxEmbeddingsPerCall: 2
    )
    let model = try provider.embeddingModel("embedding-model")

    await #expect(throws: AIError.invalidArgument(argument: "values", message: "OpenAI-compatible embedding models support at most 2 values per call.")) {
        _ = try await model.embed(EmbeddingRequest(values: ["one", "two", "three"]))
    }

    #expect(await transport.requests().isEmpty)
}

@Test func openAILanguageDefaultsToResponsesAndMapsMultimodalInput() async throws {
    let pdf = Data("%PDF".utf8)
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"response text","usage":{"input_tokens":3,"output_tokens":4,"total_tokens":7}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        headers: ["OpenAI-Organization": "org-123", "OpenAI-Project": "proj-123"],
        transport: transport
    ))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .system("Be precise."),
            AIMessage(role: .user, content: [
                .text("Inspect this"),
                .imageURL("https://example.com/image.png"),
                .data(mimeType: "application/pdf", data: pdf)
            ])
        ],
        temperature: 0.4,
        topP: 0.9,
        maxOutputTokens: 256,
        extraBody: [
            "reasoningEffort": "medium",
            "reasoningSummary": "auto",
            "previousResponseId": "resp-old",
            "parallelToolCalls": false,
            "serviceTier": "flex"
        ]
    ))

    #expect(result.text == "response text")
    #expect(result.finishReason == "stop")
    #expect(result.usage?.totalTokens == 7)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/responses")
    #expect(request.headers["Authorization"] == "Bearer test-key")
    #expect(request.headers["OpenAI-Organization"] == "org-123")
    #expect(request.headers["OpenAI-Project"] == "proj-123")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "gpt-4.1")
    #expect(body["temperature"]?.doubleValue == 0.4)
    #expect(body["top_p"]?.doubleValue == 0.9)
    #expect(body["max_output_tokens"]?.intValue == 256)
    #expect(body["previous_response_id"]?.stringValue == "resp-old")
    #expect(body["parallel_tool_calls"]?.boolValue == false)
    #expect(body["service_tier"]?.stringValue == "flex")
    #expect(body["reasoning"]?["effort"]?.stringValue == "medium")
    #expect(body["reasoning"]?["summary"]?.stringValue == "auto")
    #expect(body["input"]?[0]?["role"]?.stringValue == "system")
    #expect(body["input"]?[0]?["content"]?.stringValue == "Be precise.")
    #expect(body["input"]?[1]?["role"]?.stringValue == "user")
    #expect(body["input"]?[1]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[1]?["content"]?[0]?["text"]?.stringValue == "Inspect this")
    #expect(body["input"]?[1]?["content"]?[1]?["type"]?.stringValue == "input_image")
    #expect(body["input"]?[1]?["content"]?[1]?["image_url"]?.stringValue == "https://example.com/image.png")
    #expect(body["input"]?[1]?["content"]?[2]?["type"]?.stringValue == "input_file")
    #expect(body["input"]?[1]?["content"]?[2]?["filename"]?.stringValue == "part-2.pdf")
    #expect(body["input"]?[1]?["content"]?[2]?["file_data"]?.stringValue == "data:application/pdf;base64,\(pdf.base64EncodedString())")
}

@Test func openAIProviderAliasesRouteToUpstreamEndpoints() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"responses alias"}"#),
        jsonResponse(#"{"choices":[{"message":{"content":"chat alias"},"finish_reason":"stop"}]}"#),
        jsonResponse(#"{"choices":[{"text":"completion alias","finish_reason":"stop"}]}"#)
    ])
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))

    let responsesResult = try await provider.responses("gpt-4.1").generate(LanguageModelRequest(messages: [.user("Hi")]))
    let chatResult = try await provider.chat("gpt-4.1-mini").generate(LanguageModelRequest(messages: [.user("Hi")]))
    let completionResult = try await provider.completion("gpt-3.5-turbo-instruct").generate(LanguageModelRequest(messages: [.user("Finish")]))

    #expect(responsesResult.text == "responses alias")
    #expect(chatResult.text == "chat alias")
    #expect(completionResult.text == "completion alias")
    let requests = await transport.requests()
    #expect(requests[0].url.absoluteString == "https://api.openai.com/v1/responses")
    #expect(requests[1].url.absoluteString == "https://api.openai.com/v1/chat/completions")
    #expect(requests[2].url.absoluteString == "https://api.openai.com/v1/completions")
}

@Test func openAIResponsesMapsNestedProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done","usage":{"total_tokens":3}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: [
            "openai": .object([
                "store": .bool(false),
                "previousResponseId": .string("resp-old"),
                "parallelToolCalls": .bool(false),
                "reasoningEffort": .string("low"),
                "reasoningSummary": .string("auto")
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["store"]?.boolValue == false)
    #expect(body["previous_response_id"]?.stringValue == "resp-old")
    #expect(body["parallel_tool_calls"]?.boolValue == false)
    #expect(body["reasoning"]?["effort"]?.stringValue == "low")
    #expect(body["reasoning"]?["summary"]?.stringValue == "auto")
    #expect(body["openai"] == nil)
    #expect(body["previousResponseId"] == nil)
    #expect(body["parallelToolCalls"] == nil)
    #expect(body["reasoningEffort"] == nil)
    #expect(body["reasoningSummary"] == nil)
}

@Test func openAIResponsesGenerateMapsIncompleteFinishReason() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output_text":"partial","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "partial")
    #expect(result.finishReason == "length")
    #expect(result.usage?.totalTokens == 3)
}

@Test func openAIResponsesMapsFunctionAndProviderTools() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Search, inspect files, and generate an image.")],
        tools: [
            "lookup": [
                "type": "object",
                "description": "Look up a value.",
                "properties": ["query": ["type": "string"]],
                "strict": true,
                "deferLoading": true
            ],
            "web_search": OpenAITools.webSearch(
                filters: ["allowedDomains": ["example.com"]],
                externalWebAccess: true,
                searchContextSize: "high",
                userLocation: ["type": "approximate", "country": "US"]
            ),
            "file_search": OpenAITools.fileSearch(
                vectorStoreIDs: ["vs_123"],
                maxNumResults: 5,
                ranking: ["ranker": "auto", "scoreThreshold": 0.2]
            ),
            "code_interpreter": OpenAITools.codeInterpreter(container: ["fileIds": ["file_1", "file_2"]]),
            "image_generation": OpenAITools.imageGeneration(
                inputFidelity: "high",
                inputImageMask: ["fileId": "file_mask", "imageUrl": "https://example.com/mask.png"],
                model: "gpt-image-1",
                outputCompression: 70,
                outputFormat: "webp",
                partialImages: 2,
                quality: "high",
                size: "1024x1024"
            ),
            "remote_docs": OpenAITools.mcp(
                serverLabel: "docs",
                allowedTools: ["readOnly": true, "toolNames": ["search"]],
                requireApproval: ["never": ["toolNames": ["search"]]],
                serverURL: "https://mcp.example.com"
            ),
            "grammar_tool": OpenAITools.customTool(
                name: "grammar_tool",
                description: "Return a code.",
                format: ["type": "grammar", "syntax": "regex", "definition": "[A-Z]+"]
            ),
            "tool_search": OpenAITools.toolSearch(execution: "client", description: "Find deferred tools.")
        ],
        extraBody: ["toolChoice": ["type": "tool", "toolName": "web_search"]]
    ))

    #expect(result.text == "done")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.count == 8)

    let functionTool = try #require(tools.first { $0["type"]?.stringValue == "function" })
    #expect(functionTool["name"]?.stringValue == "lookup")
    #expect(functionTool["description"]?.stringValue == "Look up a value.")
    #expect(functionTool["parameters"]?["properties"]?["query"]?["type"]?.stringValue == "string")
    #expect(functionTool["parameters"]?["strict"] == nil)
    #expect(functionTool["strict"]?.boolValue == true)
    #expect(functionTool["defer_loading"]?.boolValue == true)

    let webSearch = try #require(tools.first { $0["type"]?.stringValue == "web_search" })
    #expect(webSearch["external_web_access"]?.boolValue == true)
    #expect(webSearch["search_context_size"]?.stringValue == "high")
    #expect(webSearch["filters"]?["allowed_domains"]?[0]?.stringValue == "example.com")
    #expect(webSearch["user_location"]?["country"]?.stringValue == "US")

    let fileSearch = try #require(tools.first { $0["type"]?.stringValue == "file_search" })
    #expect(fileSearch["vector_store_ids"]?[0]?.stringValue == "vs_123")
    #expect(fileSearch["max_num_results"]?.intValue == 5)
    #expect(fileSearch["ranking_options"]?["score_threshold"]?.doubleValue == 0.2)

    let codeInterpreter = try #require(tools.first { $0["type"]?.stringValue == "code_interpreter" })
    #expect(codeInterpreter["container"]?["type"]?.stringValue == "auto")
    #expect(codeInterpreter["container"]?["file_ids"]?[1]?.stringValue == "file_2")

    let imageGeneration = try #require(tools.first { $0["type"]?.stringValue == "image_generation" })
    #expect(imageGeneration["input_fidelity"]?.stringValue == "high")
    #expect(imageGeneration["input_image_mask"]?["file_id"]?.stringValue == "file_mask")
    #expect(imageGeneration["partial_images"]?.intValue == 2)
    #expect(imageGeneration["output_compression"]?.intValue == 70)
    #expect(imageGeneration["output_format"]?.stringValue == "webp")

    let mcp = try #require(tools.first { $0["type"]?.stringValue == "mcp" })
    #expect(mcp["server_label"]?.stringValue == "docs")
    #expect(mcp["allowed_tools"]?["read_only"]?.boolValue == true)
    #expect(mcp["allowed_tools"]?["tool_names"]?[0]?.stringValue == "search")
    #expect(mcp["require_approval"]?["never"]?["tool_names"]?[0]?.stringValue == "search")

    let custom = try #require(tools.first { $0["type"]?.stringValue == "custom" })
    #expect(custom["name"]?.stringValue == "grammar_tool")
    #expect(custom["format"]?["syntax"]?.stringValue == "regex")

    let toolSearch = try #require(tools.first { $0["type"]?.stringValue == "tool_search" })
    #expect(toolSearch["execution"]?.stringValue == "client")
    #expect(body["tool_choice"]?["type"]?.stringValue == "web_search")
    #expect(body["toolChoice"] == nil)
}

@Test func openAIResponsesMapsCustomToolChoice() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"custom"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use the custom tool.")],
        tools: [
            "grammar_tool": [
                "type": "provider",
                "id": "openai.custom",
                "name": "grammar_tool",
                "args": ["format": ["type": "text"]]
            ]
        ],
        extraBody: ["toolChoice": ["type": "tool", "toolName": "grammar_tool"]]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["tool_choice"]?["type"]?.stringValue == "custom")
    #expect(body["tool_choice"]?["name"]?.stringValue == "grammar_tool")
}

@Test func openAIResponsesParsesFunctionAndHostedToolCalls() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp-1","status":"completed","output":[{"type":"function_call","id":"fc_1","call_id":"call_1","name":"lookup","arguments":"{\\"query\\":\\"weather\\"}"},{"type":"web_search_call","id":"ws_1","status":"completed","action":{"type":"search","query":"weather"}}],"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Use tools.")]))

    #expect(result.text == "")
    #expect(result.finishReason == "stop")
    #expect(result.toolCalls.count == 2)
    #expect(result.toolCalls[0].id == "call_1")
    #expect(result.toolCalls[0].name == "lookup")
    #expect(result.toolCalls[0].arguments == #"{"query":"weather"}"#)
    #expect(result.toolCalls[1].id == "ws_1")
    #expect(result.toolCalls[1].name == "web_search")
    #expect(result.toolCalls[1].providerExecuted == true)
}

@Test func openAIResponsesStreamsFunctionToolCalls() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"lookup","arguments":""}}

    data: {"type":"response.function_call_arguments.delta","output_index":0,"delta":"{\\"query\\":"}

    data: {"type":"response.function_call_arguments.delta","output_index":0,"delta":"\\"weather\\"}"}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"lookup","arguments":"{\\"query\\":\\"weather\\"}"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    var deltas: [String] = []
    var toolCall: AIToolCall?
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Use a tool.")])) {
        switch part {
        case let .toolCallDelta(_, _, argumentsDelta, _):
            deltas.append(argumentsDelta)
        case let .toolCall(call):
            toolCall = call
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(deltas == ["", "{\"query\":", "\"weather\"}"])
    #expect(toolCall?.id == "call_1")
    #expect(toolCall?.name == "lookup")
    #expect(toolCall?.arguments == #"{"query":"weather"}"#)
    #expect(finishReason == "stop")
}

@Test func openAIResponsesStreamsTextReasoningAndFinishUsage() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.reasoning_summary_text.delta","delta":"think"}

    data: {"type":"response.output_text.delta","delta":"answer"}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

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
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
}

@Test func openAIResponsesStreamMapsIncompleteFinishReason() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_text.delta","delta":"partial"}

    data: {"type":"response.incomplete","response":{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    var text: [String] = []
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textDelta(delta):
            text.append(delta)
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(text == ["partial"])
    #expect(finishReason == "length")
    #expect(totalTokens == 3)
}

@Test func xAILanguageDefaultsToResponsesEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"xai text","usage":{"input_tokens":2,"output_tokens":3,"total_tokens":5}}"#))
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.languageModel("grok-4")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], maxOutputTokens: 12))

    #expect(result.text == "xai text")
    #expect(result.usage?.totalTokens == 5)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.x.ai/v1/responses")
    #expect(request.headers["Authorization"] == "Bearer xai-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "grok-4")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
    #expect(body["max_output_tokens"]?.intValue == 12)
}

@Test func huggingFaceLanguageDefaultsToResponsesEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"hf text","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}"#))
    let provider = try AIProviders.huggingFace(settings: ProviderSettings(apiKey: "hf-key", transport: transport))
    let model = try provider.languageModel("openai/gpt-oss-120b")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], maxOutputTokens: 24))

    #expect(provider.providerID == "huggingface")
    #expect(model.providerID == "huggingface.responses")
    #expect(result.text == "hf text")
    #expect(result.usage?.totalTokens == 3)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://router.huggingface.co/v1/responses")
    #expect(request.headers["Authorization"] == "Bearer hf-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "openai/gpt-oss-120b")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
    #expect(body["max_output_tokens"]?.intValue == 24)
}

@Test func huggingFaceResponsesAliasAndUnsupportedFamiliesMatchProviderWrapper() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"hf text"}"#))
    let provider = try AIProviders.huggingFace(settings: ProviderSettings(apiKey: "hf-key", transport: transport))
    let model = try provider.responsesModel("openai/gpt-oss-120b")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(model.providerID == "huggingface.responses")
    #expect(throws: AIError.unsupportedModel(provider: "huggingface", capability: .embedding, modelID: "embed")) {
        _ = try provider.embeddingModel("embed")
    }
    #expect(throws: AIError.unsupportedModel(provider: "huggingface", capability: .image, modelID: "image")) {
        _ = try provider.imageModel("image")
    }
}

@Test func huggingFaceLanguageMapsNativeResponsesContentAndOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp-hf-1","model":"deepseek-ai/DeepSeek-V3-0324","object":"response","created_at":1741257730,"status":"completed","error":null,"incomplete_details":null,"usage":{"input_tokens":20,"output_tokens":50,"total_tokens":70},"output":[{"id":"reasoning-1","type":"reasoning","content":[{"type":"reasoning_text","text":"thinking"}]},{"id":"call-1","type":"function_call","call_id":"call_weather","name":"weather","arguments":"{\\"city\\":\\"Tokyo\\"}"},{"id":"mcp-1","type":"mcp_call","name":"search","arguments":"{\\"query\\":\\"AI\\"}","output":"found results"},{"id":"msg-1","type":"message","role":"assistant","content":[{"type":"output_text","text":"Answer with source.","annotations":[{"type":"url_citation","url":"https://example.com/article","title":"Example Article"}]}]}],"output_text":null}
    """))
    let provider = try AIProviders.huggingFace(settings: ProviderSettings(apiKey: "hf-key", transport: transport))
    let model = try provider.languageModel("deepseek-ai/DeepSeek-V3-0324")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .system("Be concise."),
            AIMessage(role: .user, content: [
                .text("Use the image."),
                .imageURL("https://example.com/image.png"),
                .file(mimeType: "image/png", data: Data([0, 1, 2, 3]), filename: "inline.png"),
                .file(mimeType: "text/plain", data: Data("ignored".utf8), filename: "ignored.txt")
            ])
        ],
        temperature: 0.4,
        topP: 0.8,
        maxOutputTokens: 64,
        tools: ["weather": ["type": "object", "properties": ["city": ["type": "string"]]]],
        extraBody: [
            "huggingface": .object([
                "metadata": ["trace": "abc"],
                "instructions": "Use citations.",
                "reasoningEffort": "low",
                "toolChoice": ["type": "tool", "toolName": "weather"]
            ])
        ]
    ))

    #expect(result.text == "Answer with source.")
    #expect(result.reasoning == "thinking")
    #expect(result.usage?.totalTokens == 70)
    #expect(result.providerMetadata["huggingface"]?["responseId"]?.stringValue == "resp-hf-1")
    #expect(result.sources.count == 1)
    #expect(result.sources[0].sourceType == "url")
    #expect(result.sources[0].url == "https://example.com/article")
    #expect(result.sources[0].title == "Example Article")
    #expect(result.toolCalls.count == 2)
    #expect(result.toolCalls[0].id == "call_weather")
    #expect(result.toolCalls[0].name == "weather")
    #expect(result.toolCalls[0].arguments == #"{"city":"Tokyo"}"#)
    #expect(result.toolCalls[0].providerExecuted == false)
    #expect(result.toolCalls[1].id == "mcp-1")
    #expect(result.toolCalls[1].name == "search")
    #expect(result.toolCalls[1].providerExecuted == true)

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "deepseek-ai/DeepSeek-V3-0324")
    #expect(body["input"]?[0]?["role"]?.stringValue == "system")
    #expect(body["input"]?[0]?["content"]?.stringValue == "Be concise.")
    #expect(body["input"]?[1]?["content"]?.arrayValue?.count == 3)
    #expect(body["input"]?[1]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[1]?["content"]?[1]?["type"]?.stringValue == "input_image")
    #expect(body["input"]?[1]?["content"]?[1]?["image_url"]?.stringValue == "https://example.com/image.png")
    #expect(body["input"]?[1]?["content"]?[2]?["image_url"]?.stringValue == "data:image/png;base64,AAECAw==")
    #expect(body["metadata"]?["trace"]?.stringValue == "abc")
    #expect(body["instructions"]?.stringValue == "Use citations.")
    #expect(body["reasoning"]?["effort"]?.stringValue == "low")
    #expect(body["tools"]?[0]?["type"]?.stringValue == "function")
    #expect(body["tools"]?[0]?["name"]?.stringValue == "weather")
    #expect(body["tool_choice"]?["type"]?.stringValue == "function")
    #expect(body["tool_choice"]?["name"]?.stringValue == "weather")
    #expect(body["huggingface"] == nil)
}

@Test func huggingFaceLanguageStreamsReasoningTextAndToolCalls() async throws {
    let chunks = [
        #"data:{"type":"response.reasoning_text.delta","item_id":"reasoning-1","delta":"think"}"#,
        #"data:{"type":"response.output_text.delta","item_id":"msg-1","delta":"hello"}"#,
        #"data:{"type":"response.output_item.done","output_index":1,"item":{"id":"call-1","type":"function_call","call_id":"call_weather","name":"weather","arguments":"{\"city\":\"Tokyo\"}"}}"#,
        #"data:{"type":"response.completed","response":{"id":"resp-hf-1","status":"completed","incomplete_details":null,"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}"#
    ].map { Data(($0 + "\n\n").utf8) }
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "text/event-stream"], body: chunks.reduce(Data(), +)))
    let provider = try AIProviders.huggingFace(settings: ProviderSettings(apiKey: "hf-key", transport: transport))
    let model = try provider.languageModel("deepseek-ai/DeepSeek-V3-0324")

    var text = ""
    var reasoning = ""
    var finalToolCall: AIToolCall?
    var finishUsage: TokenUsage?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textDelta(delta):
            text += delta
        case let .reasoningDelta(delta):
            reasoning += delta
        case let .toolCall(toolCall):
            finalToolCall = toolCall
        case let .finish(_, usage):
            finishUsage = usage
        default:
            break
        }
    }

    #expect(reasoning == "think")
    #expect(text == "hello")
    #expect(finalToolCall?.id == "call_weather")
    #expect(finalToolCall?.name == "weather")
    #expect(finalToolCall?.arguments == #"{"city":"Tokyo"}"#)
    #expect(finishUsage?.totalTokens == 3)
}

@Test func openResponsesProviderUsesConfiguredEndpointAndResponsesBody() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"custom text","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}"#))
    let provider = try AIProviders.openResponses(
        name: "lmstudio",
        url: "https://open.example.test/custom/responses",
        settings: ProviderSettings(apiKey: "open-key", headers: ["X-Custom": "yes"], transport: transport)
    )
    let model = try provider.languageModel("local-model")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        maxOutputTokens: 12,
        extraBody: ["previousResponseId": "resp-old"]
    ))

    #expect(result.text == "custom text")
    #expect(result.usage?.totalTokens == 3)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://open.example.test/custom/responses")
    #expect(request.headers["Authorization"] == "Bearer open-key")
    #expect(request.headers["X-Custom"] == "yes")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "local-model")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
    #expect(body["max_output_tokens"]?.intValue == 12)
    #expect(body["previous_response_id"]?.stringValue == "resp-old")
    #expect(body["messages"] == nil)
}

@Test func perplexityLanguageUsesNativeChatShapeAndKeepsMetadata() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"ppl-1","created":1710000000,"model":"sonar","choices":[{"message":{"role":"assistant","content":"answer"},"finish_reason":"stop"}],"citations":["https://example.com/a"],"images":[{"image_url":"https://img.example.com/a.png","origin_url":"https://origin.example.com","height":512,"width":768}],"usage":{"prompt_tokens":3,"completion_tokens":4,"total_tokens":7,"citation_tokens":2,"num_search_queries":1,"cost":{"request_cost":0.01,"total_cost":0.02}}}
    """))
    let provider = try AIProviders.perplexity(settings: ProviderSettings(apiKey: "pplx-key", transport: transport))
    let model = try provider.languageModel("sonar")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .system("Search carefully."),
            AIMessage(role: .user, content: [
                .text("Look at this."),
                .imageURL("https://example.com/image.png"),
                .data(mimeType: "application/pdf", data: Data("pdf".utf8))
            ])
        ],
        temperature: 0.2,
        topP: 0.9,
        maxOutputTokens: 64,
        stopSequences: ["ignored"],
        extraBody: ["search_mode": "academic"]
    ))

    #expect(result.text == "answer")
    #expect(result.usage?.totalTokens == 7)
    #expect(result.sources.count == 1)
    #expect(result.sources[0].id == "citation-0")
    #expect(result.sources[0].sourceType == "url")
    #expect(result.sources[0].url == "https://example.com/a")
    #expect(result.sources[0].providerMetadata["perplexity"]?["citationIndex"]?.intValue == 0)
    #expect(result.rawValue["citations"]?[0]?.stringValue == "https://example.com/a")
    #expect(result.rawValue["images"]?[0]?["image_url"]?.stringValue == "https://img.example.com/a.png")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.perplexity.ai/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer pplx-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "sonar")
    #expect(body["temperature"]?.doubleValue == 0.2)
    #expect(body["top_p"]?.doubleValue == 0.9)
    #expect(body["max_tokens"]?.intValue == 64)
    #expect(body["stop"] == nil)
    #expect(body["search_mode"]?.stringValue == "academic")
    #expect(body["messages"]?[0]?["content"]?.stringValue == "Search carefully.")
    let content = body["messages"]?[1]?["content"]
    #expect(content?[0]?["type"]?.stringValue == "text")
    #expect(content?[1]?["type"]?.stringValue == "image_url")
    #expect(content?[1]?["image_url"]?["url"]?.stringValue == "https://example.com/image.png")
    #expect(content?[2]?["type"]?.stringValue == "file_url")
    #expect(content?[2]?["file_url"]?["url"]?.stringValue == Data("pdf".utf8).base64EncodedString())
    #expect(content?[2]?["file_name"]?.stringValue == "document-2.pdf")
}

@Test func perplexityLanguageStreamsNativeChunksWithUsage() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"ppl-1","created":1710000000,"model":"sonar","choices":[{"delta":{"role":"assistant","content":"hel"},"finish_reason":null}],"usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3},"citations":["https://example.com/a"]}

    data: {"id":"ppl-1","created":1710000000,"model":"sonar","choices":[{"delta":{"role":"assistant","content":"lo"},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":2,"total_tokens":4,"citation_tokens":1,"num_search_queries":1}}

    data: [DONE]

    """))
    let provider = try AIProviders.perplexity(settings: ProviderSettings(apiKey: "pplx-key", transport: transport))
    let model = try provider.languageModel("sonar")

    var deltas: [String] = []
    var sources: [AISource] = []
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textDelta(delta):
            deltas.append(delta)
        case let .source(source):
            sources.append(source)
        case let .finish(_, usage):
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(deltas == ["hel", "lo"])
    #expect(sources.count == 1)
    #expect(sources[0].id == "citation-0")
    #expect(sources[0].url == "https://example.com/a")
    #expect(sources[0].providerMetadata["perplexity"]?["citationIndex"]?.intValue == 0)
    #expect(totalTokens == 4)
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
    #expect(body["messages"]?[0]?["content"]?.stringValue == "Hi")
}

@Test func basetenChatUsesBearerAuthAndModelAPIBase() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"baseten"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """))
    let provider = try AIProviders.baseten(settings: ProviderSettings(apiKey: "baseten-key", transport: transport))
    let model = try provider.languageModel("deepseek-ai/DeepSeek-V3-0324")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "baseten")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://inference.baseten.co/v1/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer baseten-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "deepseek-ai/DeepSeek-V3-0324")
}

@Test func basetenEmbeddingRequiresSyncModelURL() throws {
    let provider = try AIProviders.baseten(settings: ProviderSettings(apiKey: "baseten-key", transport: RecordingTransport(response: jsonResponse("{}"))))

    #expect(throws: AIError.self) {
        _ = try provider.embeddingModel("embeddings")
    }
}

@Test func basetenEmbeddingUsesSyncModelURL() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"embedding":[0.1,0.2]}],"usage":{"total_tokens":3}}"#))
    let provider = try AIProviders.baseten(settings: ProviderSettings(
        apiKey: "baseten-key",
        baseURL: "https://model-123.api.baseten.co/environments/production/sync",
        transport: transport
    ))
    let model = try provider.embeddingModel("embeddings")

    let result = try await model.embed(EmbeddingRequest(values: ["hello"]))

    #expect(result.embeddings == [[0.1, 0.2]])
    #expect(result.usage?.totalTokens == 3)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://model-123.api.baseten.co/environments/production/sync/v1/embeddings")
    #expect(request.headers["Authorization"] == "Bearer baseten-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "embeddings")
    #expect(body["input"]?[0]?.stringValue == "hello")
}

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
    var toolCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Use a tool.")],
        tools: ["test_tool": ["type": "object", "properties": ["value": ["type": "string"]]]]
    )) {
        switch part {
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
    var finalCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Weather?")])) {
        switch part {
        case let .reasoningDelta(delta):
            reasoning.append(delta)
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
    #expect(finalCalls.map(\.id) == ["call_magic"])
    #expect(finalCalls.first?.name == "nonUsefulTool")
    #expect(finalCalls.first?.arguments == "{}")
    #expect(finishReason == "stop")
    #expect(totalTokens == 13)
}

@Test func openAITranscriptionUsesMultipartFormData() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"text":"transcribed"}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.transcriptionModel("whisper-1")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("abc".utf8),
        fileName: "clip.wav",
        mimeType: "audio/wav",
        language: "en",
        prompt: "Names",
        extraBody: ["timestampGranularities": ["word", "segment"]]
    ))

    #expect(result.text == "transcribed")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/audio/transcriptions")
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=ai-sdk-port-") == true)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"model\""))
    #expect(bodyText.contains("whisper-1"))
    #expect(bodyText.contains("name=\"file\"; filename=\"clip.wav\""))
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("verbose_json"))
    #expect(bodyText.contains("name=\"timestamp_granularities[]\""))
    #expect(bodyText.contains("word"))
    #expect(bodyText.contains("segment"))
}

@Test func openAITranscriptionUsesJSONFormatForGPT4oProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"transcribed"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.transcriptionModel("gpt-4o-transcribe")

    _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("abc".utf8), mimeType: "audio/wav", extraBody: ["temperature": 0.1]))

    let request = try #require(await transport.requests().first)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("json"))
    #expect(bodyText.contains("name=\"temperature\""))
    #expect(bodyText.contains("0.1"))
}

@Test func openAITranscriptionMapsNestedProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"transcribed"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.transcriptionModel("gpt-4o-transcribe")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("abc".utf8),
        mimeType: "audio/wav",
        extraBody: [
            "openai": .object([
                "timestampGranularities": .array([.string("word")]),
                "temperature": .number(0.1),
                "include": .array([.string("logprobs")])
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("json"))
    #expect(bodyText.contains("name=\"timestamp_granularities[]\""))
    #expect(bodyText.contains("word"))
    #expect(bodyText.contains("name=\"temperature\""))
    #expect(bodyText.contains("0.1"))
    #expect(bodyText.contains("name=\"include[]\""))
    #expect(bodyText.contains("logprobs"))
    #expect(!bodyText.contains("name=\"openai\""))
}

@Test func openAISpeechUsesDefaultVoiceAndResponseFormat() async throws {
    let audio = Data("mp3".utf8)
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: audio))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.speechModel("tts-1")

    let result = try await model.speak(SpeechRequest(text: "Hello", extraBody: ["speed": 1.25, "instructions": "Calm"]))

    #expect(result.audio == audio)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/audio/speech")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "tts-1")
    #expect(body["input"]?.stringValue == "Hello")
    #expect(body["voice"]?.stringValue == "alloy")
    #expect(body["response_format"]?.stringValue == "mp3")
    #expect(body["speed"]?.doubleValue == 1.25)
    #expect(body["instructions"]?.stringValue == "Calm")
}

@Test func openAISpeechMapsNestedProviderOptions() async throws {
    let audio = Data("mp3".utf8)
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: audio))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.speechModel("tts-1")

    _ = try await model.speak(SpeechRequest(
        text: "Hello",
        extraBody: [
            "openai": .object([
                "speed": .number(1.25),
                "instructions": .string("Calm")
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["speed"]?.doubleValue == 1.25)
    #expect(body["instructions"]?.stringValue == "Calm")
    #expect(body["openai"] == nil)
}

@Test func openAIImageMapsProviderOptionsAndDefaultResponseFormat() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"created":1710000000,"data":[{"b64_json":"image-b64","revised_prompt":"cat"}],"usage":{"total_tokens":10}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.imageModel("dall-e-3")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "1024x1024",
        count: 1,
        extraBody: [
            "quality": "hd",
            "style": "vivid",
            "background": "transparent",
            "moderation": "low",
            "outputFormat": "webp",
            "outputCompression": 80,
            "user": "user-1"
        ]
    ))

    #expect(result.base64Images == ["image-b64"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/images/generations")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "dall-e-3")
    #expect(body["prompt"]?.stringValue == "cat")
    #expect(body["response_format"]?.stringValue == "b64_json")
    #expect(body["output_format"]?.stringValue == "webp")
    #expect(body["output_compression"]?.intValue == 80)
    #expect(body["quality"]?.stringValue == "hd")
    #expect(body["style"]?.stringValue == "vivid")
    #expect(body["background"]?.stringValue == "transparent")
    #expect(body["moderation"]?.stringValue == "low")
    #expect(body["user"]?.stringValue == "user-1")
}

@Test func openAIImageMapsNestedProviderOptionsForGenerateAndEdit() async throws {
    let generationTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"image-b64"}]}"#))
    let generationProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: generationTransport))
    let generationModel = try generationProvider.imageModel("gpt-image-1")

    _ = try await generationModel.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "1024x1024",
        count: 1,
        extraBody: [
            "openai": .object([
                "quality": .string("high"),
                "background": .string("transparent"),
                "moderation": .string("low"),
                "outputFormat": .string("webp"),
                "outputCompression": .number(80),
                "user": .string("user-1")
            ])
        ]
    ))

    let generationBody = try decodeJSONBody(try #require((await generationTransport.requests()).first?.body))
    #expect(generationBody["quality"]?.stringValue == "high")
    #expect(generationBody["background"]?.stringValue == "transparent")
    #expect(generationBody["moderation"]?.stringValue == "low")
    #expect(generationBody["output_format"]?.stringValue == "webp")
    #expect(generationBody["output_compression"]?.intValue == 80)
    #expect(generationBody["user"]?.stringValue == "user-1")
    #expect(generationBody["openai"] == nil)
    #expect(generationBody["outputFormat"] == nil)
    #expect(generationBody["outputCompression"] == nil)

    let editTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"edited-b64"}]}"#))
    let editProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: editTransport))
    let editModel = try editProvider.imageModel("gpt-image-1")

    _ = try await editModel.generateImage(ImageGenerationRequest(
        prompt: "edit",
        files: [ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png", fileName: "input.png")],
        extraBody: [
            "openai": .object([
                "outputFormat": .string("webp"),
                "outputCompression": .number(70),
                "inputFidelity": .string("high")
            ])
        ]
    ))

    let editBody = try #require((await editTransport.requests()).first?.body)
    #expect(editBody.range(of: Data(#"name="output_format""#.utf8)) != nil)
    #expect(editBody.range(of: Data("webp".utf8)) != nil)
    #expect(editBody.range(of: Data(#"name="output_compression""#.utf8)) != nil)
    #expect(editBody.range(of: Data("70".utf8)) != nil)
    #expect(editBody.range(of: Data(#"name="input_fidelity""#.utf8)) != nil)
    #expect(editBody.range(of: Data("high".utf8)) != nil)
    #expect(editBody.range(of: Data(#"name="openai""#.utf8)) == nil)
}

@Test func openAIImageEditUsesMultipartEditsEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"created":1710000000,"data":[{"b64_json":"edited-b64"}]}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.imageModel("gpt-image-1")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "edit the image",
        size: "1024x1024",
        count: 1,
        files: [ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png", fileName: "input.png")],
        mask: ImageInputFile(data: Data([255, 255, 255, 0]), mediaType: "image/png", fileName: "mask.png"),
        extraBody: [
            "quality": "high",
            "background": "transparent",
            "outputFormat": "webp",
            "outputCompression": 80,
            "inputFidelity": "high",
            "user": "user-1"
        ]
    ))

    #expect(result.base64Images == ["edited-b64"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/images/edits")
    #expect(request.headers["Authorization"] == "Bearer test-key")
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=ai-sdk-port-") == true)
    let body = try #require(request.body)
    #expect(body.range(of: Data(#"name="model""#.utf8)) != nil)
    #expect(body.range(of: Data("gpt-image-1".utf8)) != nil)
    #expect(body.range(of: Data(#"name="prompt""#.utf8)) != nil)
    #expect(body.range(of: Data("edit the image".utf8)) != nil)
    #expect(body.range(of: Data(#"name="image"; filename="input.png""#.utf8)) != nil)
    #expect(body.range(of: Data(#"name="mask"; filename="mask.png""#.utf8)) != nil)
    #expect(body.range(of: Data(#"name="output_format""#.utf8)) != nil)
    #expect(body.range(of: Data("webp".utf8)) != nil)
    #expect(body.range(of: Data(#"name="output_compression""#.utf8)) != nil)
    #expect(body.range(of: Data("80".utf8)) != nil)
    #expect(body.range(of: Data(#"name="input_fidelity""#.utf8)) != nil)
    #expect(body.range(of: Data("high".utf8)) != nil)
}

@Test func deepgramTranscriptionPostsRawAudioToListenEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"results":{"channels":[{"alternatives":[{"transcript":"hello world","words":[]}],"detected_language":"en"}]},"metadata":{"duration":1.2}}
    """))
    let provider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transport))
    let model = try provider.transcriptionModel("nova-3")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        fileName: "clip.wav",
        mimeType: "audio/wav",
        language: "en",
        extraBody: [
            "detectLanguage": .bool(false),
            "detectEntities": .bool(true),
            "fillerWords": .bool(true),
            "smartFormat": .bool(true),
            "summarize": .string("v2"),
            "topics": .bool(true),
            "utterances": .bool(true),
            "uttSplit": .number(0.8),
            "redact": .array([.string("ssn"), .string("pci")]),
            "search": .string("Codex")
        ]
    ))

    #expect(result.text == "hello world")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepgram.com/v1/listen?detect_entities=true&detect_language=false&diarize=true&filler_words=true&language=en&model=nova-3&redact=ssn%2Cpci&search=Codex&smart_format=true&summarize=v2&topics=true&utt_split=0.8&utterances=true")
    #expect(request.headers["authorization"] == "Token deepgram-key")
    #expect(request.headers["content-type"] == "audio/wav")
    #expect(request.body == Data("wav".utf8))
}

@Test func deepgramSpeechUsesSpeakEndpointWithFormatQuery() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/wav"], body: Data("audio".utf8)))
    let provider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transport))
    let model = try provider.speechModel("aura-2-helena-en")

    let result = try await model.speak(SpeechRequest(
        text: "Hello",
        voice: "ignored-voice",
        format: "wav_24000",
        extraBody: [
            "callback": .string("https://example.com/hook"),
            "callbackMethod": .string("PUT"),
            "mipOptOut": .bool(true),
            "tag": .array([.string("test"), .string("swift")])
        ]
    ))

    #expect(result.audio == Data("audio".utf8))
    #expect(result.contentType == "audio/wav")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepgram.com/v1/speak?callback=https%3A%2F%2Fexample.com%2Fhook&callback_method=PUT&container=wav&encoding=linear16&mip_opt_out=true&model=aura-2-helena-en&sample_rate=24000&tag=test%2Cswift")
    #expect(request.headers["authorization"] == "Token deepgram-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["text"]?.stringValue == "Hello")
}

@Test func deepgramAudioModelsMapNestedProviderOptions() async throws {
    let transcriptionTransport = RecordingTransport(response: jsonResponse("""
    {"results":{"channels":[{"alternatives":[{"transcript":"nested","words":[]}],"detected_language":"ja"}]}}
    """))
    let transcriptionProvider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transcriptionTransport))
    let transcriptionModel = try transcriptionProvider.transcriptionModel("nova-3")

    _ = try await transcriptionModel.transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        mimeType: "audio/wav",
        language: "en",
        extraBody: [
            "deepgram": .object([
                "language": .string("ja"),
                "detectLanguage": .bool(true),
                "diarize": .bool(false),
                "smartFormat": .bool(true)
            ])
        ]
    ))

    let transcriptionRequest = try #require(await transcriptionTransport.requests().first)
    #expect(transcriptionRequest.url.absoluteString == "https://api.deepgram.com/v1/listen?detect_language=true&diarize=false&language=ja&model=nova-3&smart_format=true")

    let speechTransport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("audio".utf8)))
    let speechProvider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: speechTransport))
    let speechModel = try speechProvider.speechModel("aura-2-helena-en")

    _ = try await speechModel.speak(SpeechRequest(
        text: "Hello",
        format: "wav_24000",
        extraBody: [
            "deepgram": .object([
                "encoding": .string("mp3"),
                "bitRate": .number(48000),
                "sampleRate": .number(16000),
                "callbackMethod": .string("POST"),
                "mipOptOut": .bool(true)
            ])
        ]
    ))

    let speechRequest = try #require(await speechTransport.requests().first)
    #expect(speechRequest.url.absoluteString == "https://api.deepgram.com/v1/speak?bit_rate=48000&callback_method=POST&encoding=mp3&mip_opt_out=true&model=aura-2-helena-en")
}

@Test func assemblyAITranscriptionUploadsSubmitsAndPolls() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"job-123","status":"queued"}"#),
        jsonResponse(#"{"id":"job-123","status":"completed","text":"assembled text","language_code":"en"}"#)
    ])
    let provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: transport))
    let model = try provider.transcriptionModel("best")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        mimeType: "audio/wav",
        language: "en",
        extraBody: [
            "autoChapters": .bool(true),
            "contentSafetyConfidence": .number(75),
            "entityDetection": .bool(true),
            "filterProfanity": .bool(true),
            "languageDetection": .bool(true),
            "redactPiiPolicies": .array([.string("person_name")]),
            "speakerLabels": .bool(true),
            "speakersExpected": .number(2),
            "webhookUrl": .string("https://example.com/assembly"),
            "wordBoost": .array([.string("Codex")])
        ]
    ))

    #expect(result.text == "assembled text")
    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].url.absoluteString == "https://api.assemblyai.com/v2/upload")
    #expect(requests[0].method == "POST")
    #expect(requests[0].headers["authorization"] == "assembly-key")
    #expect(requests[0].headers["content-type"] == "application/octet-stream")
    #expect(requests[0].body == Data("audio".utf8))

    #expect(requests[1].url.absoluteString == "https://api.assemblyai.com/v2/transcript")
    let submitBody = try decodeJSONBody(try #require(requests[1].body))
    #expect(submitBody["speech_model"]?.stringValue == "best")
    #expect(submitBody["audio_url"]?.stringValue == "https://cdn.example.com/audio.wav")
    #expect(submitBody["language_code"]?.stringValue == "en")
    #expect(submitBody["auto_chapters"]?.boolValue == true)
    #expect(submitBody["content_safety_confidence"]?.intValue == 75)
    #expect(submitBody["entity_detection"]?.boolValue == true)
    #expect(submitBody["filter_profanity"]?.boolValue == true)
    #expect(submitBody["language_detection"]?.boolValue == true)
    #expect(submitBody["redact_pii_policies"]?[0]?.stringValue == "person_name")
    #expect(submitBody["speaker_labels"]?.boolValue == true)
    #expect(submitBody["speakers_expected"]?.intValue == 2)
    #expect(submitBody["webhook_url"]?.stringValue == "https://example.com/assembly")
    #expect(submitBody["word_boost"]?[0]?.stringValue == "Codex")
    #expect(submitBody["autoChapters"] == nil)
    #expect(submitBody["speakerLabels"] == nil)

    #expect(requests[2].method == "GET")
    #expect(requests[2].url.absoluteString == "https://api.assemblyai.com/v2/transcript/job-123")
}

@Test func assemblyAITranscriptionMapsNestedProviderOptions() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"job-123","status":"queued"}"#),
        jsonResponse(#"{"id":"job-123","status":"completed","text":"assembled nested"}"#)
    ])
    let provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: transport))
    let model = try provider.transcriptionModel("nano")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        extraBody: [
            "assemblyai": .object([
                "disfluencies": true,
                "multichannel": true,
                "punctuate": false,
                "summarization": true,
                "summaryModel": "informative",
                "summaryType": "bullets",
                "speechThreshold": 0.6
            ])
        ]
    ))

    let requests = await transport.requests()
    let submitBody = try decodeJSONBody(try #require(requests[1].body))
    #expect(submitBody["speech_model"]?.stringValue == "nano")
    #expect(submitBody["disfluencies"]?.boolValue == true)
    #expect(submitBody["multichannel"]?.boolValue == true)
    #expect(submitBody["punctuate"]?.boolValue == false)
    #expect(submitBody["summarization"]?.boolValue == true)
    #expect(submitBody["summary_model"]?.stringValue == "informative")
    #expect(submitBody["summary_type"]?.stringValue == "bullets")
    #expect(submitBody["speech_threshold"]?.doubleValue == 0.6)
    #expect(submitBody["assemblyai"] == nil)
    #expect(submitBody["summaryModel"] == nil)
}

@Test func revAITranscriptionSubmitsMultipartJobAndFetchesTranscript() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"job-123","status":"transcribed","language":"en"}"#),
        jsonResponse(#"{"monologues":[{"elements":[{"type":"text","value":"hello","ts":0,"end_ts":0.4},{"type":"punct","value":" "},{"type":"text","value":"rev","ts":0.5,"end_ts":0.9}]}]}"#)
    ])
    let provider = try AIProviders.revAI(settings: ProviderSettings(apiKey: "rev-key", transport: transport))
    let model = try provider.transcriptionModel("machine")

    let result = try await model.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), fileName: "clip.wav", mimeType: "audio/wav", language: "en"))

    #expect(result.text == "hello rev")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].url.absoluteString == "https://api.rev.ai/speechtotext/v1/jobs")
    #expect(requests[0].headers["Authorization"] == "Bearer rev-key")
    #expect(requests[0].headers["content-type"]?.hasPrefix("multipart/form-data; boundary=ai-sdk-port-") == true)
    let form = String(data: try #require(requests[0].body), encoding: .utf8) ?? ""
    #expect(form.contains("name=\"media\"; filename=\"clip.wav\""))
    #expect(form.contains("name=\"config\""))
    #expect(form.contains("\"transcriber\":\"machine\""))
    #expect(form.contains("\"language\":\"en\""))

    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api.rev.ai/speechtotext/v1/jobs/job-123/transcript")
}

@Test func revAITranscriptionMapsNestedProviderOptions() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"job-123","status":"transcribed","language":"ja"}"#),
        jsonResponse(#"{"monologues":[{"elements":[{"type":"text","value":"nested","ts":0,"end_ts":0.5}]}]}"#)
    ])
    let provider = try AIProviders.revAI(settings: ProviderSettings(apiKey: "rev-key", transport: transport))
    let model = try provider.transcriptionModel("machine")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        fileName: "clip.wav",
        mimeType: "audio/wav",
        extraBody: [
            "revai": .object([
                "metadata": "case-1",
                "language": "ja",
                "verbatim": true,
                "skip_diarization": true,
                "speaker_channels_count": 2,
                "summarization_config": ["model": "standard", "type": "bullets"],
                "translation_config": ["target_languages": [["language": "en"]], "model": "standard"],
                "forced_alignment": true
            ])
        ]
    ))

    let form = String(data: try #require((await transport.requests()).first?.body), encoding: .utf8) ?? ""
    #expect(form.contains("\"transcriber\":\"machine\""))
    #expect(form.contains("\"metadata\":\"case-1\""))
    #expect(form.contains("\"language\":\"ja\""))
    #expect(form.contains("\"verbatim\":true"))
    #expect(form.contains("\"skip_diarization\":true"))
    #expect(form.contains("\"speaker_channels_count\":2"))
    #expect(form.contains("\"summarization_config\""))
    #expect(form.contains("\"translation_config\""))
    #expect(form.contains("\"forced_alignment\":true"))
    #expect(!form.contains("\"revai\""))
}

@Test func gladiaTranscriptionUploadsInitiatesAndPollsResultURL() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
        jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-123"}"#),
        jsonResponse(#"{"status":"done","result":{"metadata":{"audio_duration":2.4},"transcription":{"full_transcript":"gladia text","languages":["en"],"utterances":[{"start":0,"end":2.4,"text":"gladia text"}]}}}"#)
    ])
    let provider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "gladia-key", transport: transport))
    let model = try provider.transcriptionModel("default")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        fileName: "clip.wav",
        mimeType: "audio/wav",
        language: "en",
        extraBody: [
            "contextPrompt": .string("Names include Codex."),
            "detectLanguage": .bool(false),
            "enableCodeSwitching": .bool(true),
            "codeSwitchingConfig": .object(["languages": .array([.string("en"), .string("ja")])]),
            "subtitles": .bool(true),
            "subtitlesConfig": .object([
                "formats": .array([.string("srt")]),
                "minimumDuration": .number(1),
                "maximumCharactersPerRow": .number(42)
            ]),
            "diarization": .bool(true),
            "diarizationConfig": .object([
                "numberOfSpeakers": .number(2),
                "enhanced": .bool(true)
            ]),
            "translation": .bool(true),
            "translationConfig": .object([
                "targetLanguages": .array([.string("fr")]),
                "matchOriginalUtterances": .bool(true)
            ]),
            "namedEntityRecognition": .bool(true),
            "customSpellingConfig": .object(["spellingDictionary": .object(["Codex": .array([.string("code ex")])])]),
            "structuredDataExtraction": .bool(true),
            "sentimentAnalysis": .bool(true),
            "audioToLlmConfig": .object(["prompts": .array([.string("summarize")])]),
            "displayMode": .bool(true),
            "punctuationEnhanced": .bool(true)
        ]
    ))

    #expect(result.text == "gladia text")
    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].url.absoluteString == "https://api.gladia.io/v2/upload")
    #expect(requests[0].headers["x-gladia-key"] == "gladia-key")
    #expect(requests[0].headers["content-type"]?.hasPrefix("multipart/form-data; boundary=ai-sdk-port-") == true)
    let uploadBody = String(data: try #require(requests[0].body), encoding: .utf8) ?? ""
    #expect(uploadBody.contains("name=\"audio\"; filename=\"clip.wav\""))

    #expect(requests[1].url.absoluteString == "https://api.gladia.io/v2/pre-recorded")
    let initBody = try decodeJSONBody(try #require(requests[1].body))
    #expect(initBody["audio_url"]?.stringValue == "https://audio.example.com/file.wav")
    #expect(initBody["language"]?.stringValue == "en")
    #expect(initBody["context_prompt"]?.stringValue == "Names include Codex.")
    #expect(initBody["detect_language"]?.boolValue == false)
    #expect(initBody["enable_code_switching"]?.boolValue == true)
    #expect(initBody["code_switching_config"]?["languages"]?[1]?.stringValue == "ja")
    #expect(initBody["subtitles_config"]?["minimum_duration"]?.intValue == 1)
    #expect(initBody["subtitles_config"]?["maximum_characters_per_row"]?.intValue == 42)
    #expect(initBody["diarization_config"]?["number_of_speakers"]?.intValue == 2)
    #expect(initBody["diarization_config"]?["enhanced"]?.boolValue == true)
    #expect(initBody["translation_config"]?["target_languages"]?[0]?.stringValue == "fr")
    #expect(initBody["translation_config"]?["match_original_utterances"]?.boolValue == true)
    #expect(initBody["named_entity_recognition"]?.boolValue == true)
    #expect(initBody["custom_spelling_config"]?["spelling_dictionary"]?["Codex"]?[0]?.stringValue == "code ex")
    #expect(initBody["structured_data_extraction"]?.boolValue == true)
    #expect(initBody["sentiment_analysis"]?.boolValue == true)
    #expect(initBody["audio_to_llm_config"]?["prompts"]?[0]?.stringValue == "summarize")
    #expect(initBody["display_mode"]?.boolValue == true)
    #expect(initBody["punctuation_enhanced"]?.boolValue == true)
    #expect(initBody["contextPrompt"] == nil)
    #expect(initBody["diarizationConfig"] == nil)

    #expect(requests[2].method == "GET")
    #expect(requests[2].url.absoluteString == "https://api.gladia.io/v2/pre-recorded/result/job-123")
}

@Test func gladiaTranscriptionMapsNestedProviderOptions() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
        jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-123"}"#),
        jsonResponse(#"{"status":"done","result":{"transcription":{"full_transcript":"gladia nested"}}}"#)
    ])
    let provider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "gladia-key", transport: transport))
    let model = try provider.transcriptionModel("default")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        extraBody: [
            "gladia": .object([
                "language": "ja",
                "callback": true,
                "callbackConfig": ["url": "https://example.com/hook", "method": "POST"],
                "subtitles": true,
                "diarization": true,
                "translation": true,
                "summarization": true,
                "moderation": true,
                "chapterization": true,
                "sentences": true,
                "summarizationConfig": ["type": "concise"]
            ])
        ]
    ))

    let requests = await transport.requests()
    let initBody = try decodeJSONBody(try #require(requests[1].body))
    #expect(initBody["language"]?.stringValue == "ja")
    #expect(initBody["callback"]?.boolValue == true)
    #expect(initBody["callback_config"]?["url"]?.stringValue == "https://example.com/hook")
    #expect(initBody["callback_config"]?["method"]?.stringValue == "POST")
    #expect(initBody["subtitles"]?.boolValue == true)
    #expect(initBody["diarization"]?.boolValue == true)
    #expect(initBody["translation"]?.boolValue == true)
    #expect(initBody["summarization"]?.boolValue == true)
    #expect(initBody["moderation"]?.boolValue == true)
    #expect(initBody["chapterization"]?.boolValue == true)
    #expect(initBody["sentences"]?.boolValue == true)
    #expect(initBody["summarization_config"]?["type"]?.stringValue == "concise")
    #expect(initBody["gladia"] == nil)
    #expect(initBody["callbackConfig"] == nil)
}

@Test func openAIFilesUploadUsesMultipartFilesEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"file_123","filename":"notes.txt","purpose":"assistants","bytes":3,"created_at":1710000000,"status":"processed"}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let result = try await provider.files().uploadFile(FileUploadRequest(data: Data("hey".utf8), mediaType: "text/plain", filename: "notes.txt"))

    #expect(result.providerReference["openai"] == "file_123")
    #expect(result.filename == "notes.txt")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/files")
    #expect(request.headers["Authorization"] == "Bearer test-key")
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=ai-sdk-port-") == true)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"file\"; filename=\"notes.txt\""))
    #expect(bodyText.contains("name=\"purpose\""))
    #expect(bodyText.contains("assistants"))
}

@Test func openAISkillsUploadUsesMultipartSkillsEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"skill_123","object":"skill","name":"capture-skill","description":"captures data","default_version":"1","latest_version":"2","created_at":1772078479,"updated_at":1772078480}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let result = try await provider.skills().uploadSkill(SkillUploadRequest(
        files: [
            SkillUploadFile(path: "index.ts", data: Data("console.log('hi')".utf8), mediaType: "text/typescript")
        ],
        displayTitle: "Capture Skill"
    ))

    #expect(result.providerReference["openai"] == "skill_123")
    #expect(result.name == "capture-skill")
    #expect(result.description == "captures data")
    #expect(result.latestVersion == "2")
    #expect(result.providerMetadata["openai"]?["defaultVersion"]?.stringValue == "1")
    #expect(result.providerMetadata["openai"]?["createdAt"]?.intValue == 1_772_078_479)
    #expect(result.providerMetadata["openai"]?["updatedAt"]?.intValue == 1_772_078_480)
    #expect(result.warnings == [AIWarning(type: "unsupported", feature: "displayTitle")])

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/skills")
    #expect(request.headers["Authorization"] == "Bearer test-key")
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=ai-sdk-port-") == true)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"files[]\"; filename=\"index.ts\""))
    #expect(bodyText.contains("Content-Type: text/typescript"))
    #expect(bodyText.contains("console.log('hi')"))
}

@Test func anthropicFilesUploadAddsBetaHeader() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"file_abc","type":"file","filename":"data.pdf","mime_type":"application/pdf","size_bytes":10,"created_at":"2026-01-01T00:00:00Z","downloadable":true}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let result = try await provider.files().uploadFile(FileUploadRequest(data: Data([1, 2, 3]), mediaType: "application/pdf", filename: "data.pdf"))

    #expect(result.providerReference["anthropic"] == "file_abc")
    #expect(result.mediaType == "application/pdf")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.anthropic.com/v1/files")
    #expect(request.headers["x-api-key"] == "claude-key")
    #expect(request.headers["anthropic-beta"] == "files-api-2025-04-14")
}

@Test func anthropicSkillsUploadAddsBetaHeaderAndFetchesVersionMetadata() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"skill_01","display_title":"Test Capture Skill","latest_version":"1772078378207930","source":"custom","created_at":"2026-02-26T03:59:39.314772Z","updated_at":"2026-02-26T03:59:39.314772Z"}
        """),
        jsonResponse("""
        {"type":"skill_version","skill_id":"skill_01","name":"test-capture-skill","description":"An updated test skill for fixture capture"}
        """)
    ])
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let result = try await provider.skills().uploadSkill(SkillUploadRequest(
        files: [
            SkillUploadFile(path: "index.ts", data: Data("console.log('hi')".utf8), mediaType: "text/typescript")
        ],
        displayTitle: "My Custom Title"
    ))

    #expect(result.providerReference["anthropic"] == "skill_01")
    #expect(result.displayTitle == "Test Capture Skill")
    #expect(result.name == "test-capture-skill")
    #expect(result.description == "An updated test skill for fixture capture")
    #expect(result.latestVersion == "1772078378207930")
    #expect(result.providerMetadata["anthropic"]?["source"]?.stringValue == "custom")
    #expect(result.providerMetadata["anthropic"]?["createdAt"]?.stringValue == "2026-02-26T03:59:39.314772Z")
    #expect(result.providerMetadata["anthropic"]?["updatedAt"]?.stringValue == "2026-02-26T03:59:39.314772Z")
    #expect(result.warnings.isEmpty)

    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].url.absoluteString == "https://api.anthropic.com/v1/skills")
    #expect(requests[0].headers["x-api-key"] == "claude-key")
    #expect(requests[0].headers["anthropic-beta"] == "skills-2025-10-02")
    #expect(requests[0].headers["content-type"]?.hasPrefix("multipart/form-data; boundary=ai-sdk-port-") == true)
    let bodyText = String(data: try #require(requests[0].body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"display_title\""))
    #expect(bodyText.contains("My Custom Title"))
    #expect(bodyText.contains("name=\"files[]\"; filename=\"index.ts\""))
    #expect(bodyText.contains("Content-Type: text/typescript"))
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api.anthropic.com/v1/skills/skill_01/versions/1772078378207930")
    #expect(requests[1].headers["anthropic-beta"] == "skills-2025-10-02")
}

@Test func anthropicLanguageStreamsMessagesEvents() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hel"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lo"}}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":2}}

    event: message_stop
    data: {"type":"message_stop"}

    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-5-haiku-latest")

    var deltas: [String] = []
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textDelta(delta):
            deltas.append(delta)
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(deltas == ["hel", "lo"])
    #expect(finishReason == "stop")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.anthropic.com/v1/messages")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
}

@Test func anthropicLanguageStreamsThinkingDeltasAndMappedFinishReason() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"think"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"answer"}}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"},"usage":{"output_tokens":3}}

    event: message_stop
    data: {"type":"message_stop"}

    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-7-sonnet-latest")

    var reasoning: [String] = []
    var text: [String] = []
    var finishReason: String?
    var outputTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .reasoningDelta(delta):
            reasoning.append(delta)
        case let .textDelta(delta):
            text.append(delta)
        case let .finish(reason, usage):
            finishReason = reason
            outputTokens = usage?.outputTokens
        default:
            break
        }
    }

    #expect(reasoning == ["think"])
    #expect(text == ["answer"])
    #expect(finishReason == "length")
    #expect(outputTokens == 3)
}

@Test func anthropicLanguageStreamsToolUseDeltasAndFinalCall() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"lookup","input":{}}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"query\\":"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\\"weather\\"}"}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":0}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":4}}

    event: message_stop
    data: {"type":"message_stop"}

    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-5-haiku-latest")

    var deltas: [String] = []
    var toolCall: AIToolCall?
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Use a tool.")],
        tools: ["lookup": ["type": "object", "properties": ["query": ["type": "string"]]]]
    )) {
        switch part {
        case let .toolCallDelta(_, _, argumentsDelta, _):
            deltas.append(argumentsDelta)
        case let .toolCall(call):
            toolCall = call
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    let finalToolCall = try #require(toolCall)
    #expect(deltas == ["", "{\"query\":", "\"weather\"}"])
    #expect(finalToolCall.id == "toolu_1")
    #expect(finalToolCall.name == "lookup")
    #expect(finalToolCall.providerExecuted == false)
    #expect(try decodeJSONBody(Data(finalToolCall.arguments.utf8))["query"]?.stringValue == "weather")
    #expect(finishReason == "tool-calls")
}

@Test func anthropicLanguageStreamsCitationSources() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Based on the document"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"citations_delta","citation":{"type":"char_location","cited_text":"important information","document_index":0,"document_title":"Test Document","start_char_index":15,"end_char_index":35}}}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":2}}

    event: message_stop
    data: {"type":"message_stop"}

    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-5-haiku-latest")

    var deltas: [String] = []
    var sources: [AISource] = []
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .data(mimeType: "text/plain", data: Data("Test document content".utf8)),
            .text("What does this say?")
        ])
    ])) {
        switch part {
        case let .textDelta(delta):
            deltas.append(delta)
        case let .source(source):
            sources.append(source)
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(deltas == ["Based on the document"])
    #expect(sources.count == 1)
    #expect(sources[0].id == "anthropic-source-0")
    #expect(sources[0].sourceType == "document")
    #expect(sources[0].title == "Test Document")
    #expect(sources[0].mediaType == "text/plain")
    #expect(sources[0].providerMetadata["anthropic"]?["citedText"]?.stringValue == "important information")
    #expect(sources[0].providerMetadata["anthropic"]?["startCharIndex"]?.intValue == 15)
    #expect(sources[0].providerMetadata["anthropic"]?["endCharIndex"]?.intValue == 35)
    #expect(finishReason == "stop")
}

@Test func googleFilesUploadUsesResumableUploadFlow() async throws {
    let transport = RecordingTransport(responses: [
        AIHTTPResponse(statusCode: 200, headers: ["x-goog-upload-url": "https://upload.example.com/session"], body: Data()),
        jsonResponse("""
        {"file":{"name":"files/abc","displayName":"Clip","mimeType":"video/mp4","uri":"https://generativelanguage.googleapis.com/v1beta/files/abc","state":"ACTIVE"}}
        """)
    ])
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let result = try await provider.files().uploadFile(FileUploadRequest(data: Data("video".utf8), mediaType: "video/mp4", displayName: "Clip"))

    #expect(result.providerReference["google"] == "https://generativelanguage.googleapis.com/v1beta/files/abc")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].url.absoluteString == "https://generativelanguage.googleapis.com/upload/v1beta/files")
    #expect(requests[0].headers["X-Goog-Upload-Protocol"] == "resumable")
    #expect(requests[0].headers["X-Goog-Upload-Header-Content-Length"] == "5")
    let startBody = try decodeJSONBody(try #require(requests[0].body))
    #expect(startBody["file"]?["display_name"]?.stringValue == "Clip")
    #expect(requests[1].url.absoluteString == "https://upload.example.com/session")
    #expect(requests[1].headers["X-Goog-Upload-Command"] == "upload, finalize")
    #expect(requests[1].body == Data("video".utf8))
}

@Test func lmntSpeechUsesBytesEndpointAndVoiceBody() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/aac"], body: Data("lmnt".utf8)))
    let provider = try AIProviders.lmnt(settings: ProviderSettings(apiKey: "lmnt-key", transport: transport))
    let model = try provider.speechModel("aurora")

    let result = try await model.speak(SpeechRequest(
        text: "Hi",
        voice: "ava",
        format: "aac",
        extraBody: [
            "sampleRate": .number(16000),
            "topP": .number(0.8),
            "temperature": .number(0.6),
            "seed": .number(42),
            "conversational": .bool(true),
            "length": .number(20),
            "format": .string("wav"),
            "model": .string("ignored")
        ]
    ))

    #expect(result.audio == Data("lmnt".utf8))
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.lmnt.com/v1/ai/speech/bytes")
    #expect(request.headers["X-API-Key"] == "lmnt-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "aurora")
    #expect(body["text"]?.stringValue == "Hi")
    #expect(body["voice"]?.stringValue == "ava")
    #expect(body["response_format"]?.stringValue == "aac")
    #expect(body["sample_rate"]?.intValue == 16000)
    #expect(body["top_p"]?.doubleValue == 0.8)
    #expect(body["temperature"]?.doubleValue == 0.6)
    #expect(body["seed"]?.intValue == 42)
    #expect(body["conversational"]?.boolValue == true)
    #expect(body["length"]?.intValue == 20)
    #expect(body["sampleRate"] == nil)
    #expect(body["topP"] == nil)
    #expect(body["format"] == nil)
}

@Test func lmntSpeechMapsNestedProviderOptions() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/wav"], body: Data("lmnt".utf8)))
    let provider = try AIProviders.lmnt(settings: ProviderSettings(apiKey: "lmnt-key", transport: transport))
    let model = try provider.speechModel("aurora")

    _ = try await model.speak(SpeechRequest(
        text: "Hi",
        voice: "ava",
        format: "wav",
        extraBody: [
            "lmnt": .object([
                "sampleRate": 24000,
                "topP": 0.7,
                "temperature": 0.5,
                "speed": 1.2,
                "seed": 77,
                "conversational": true,
                "length": 12,
                "format": "mp3",
                "model": "ignored"
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?.stringValue == "wav")
    #expect(body["sample_rate"]?.intValue == 24000)
    #expect(body["top_p"]?.doubleValue == 0.7)
    #expect(body["temperature"]?.doubleValue == 0.5)
    #expect(body["speed"]?.doubleValue == 1.2)
    #expect(body["seed"]?.intValue == 77)
    #expect(body["conversational"]?.boolValue == true)
    #expect(body["length"]?.intValue == 12)
    #expect(body["lmnt"] == nil)
    #expect(body["sampleRate"] == nil)
    #expect(body["format"] == nil)
}

@Test func humeSpeechUsesTTSFileEndpointWithUtterances() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("hume".utf8)))
    let provider = try AIProviders.hume(settings: ProviderSettings(apiKey: "hume-key", transport: transport))
    let model = try provider.speechModel("")

    let result = try await model.speak(SpeechRequest(
        text: "Hello",
        voice: "voice-id",
        format: "wav",
        extraBody: [
            "context": .object([
                "utterances": .array([
                    .object([
                        "text": .string("Earlier line"),
                        "description": .string("warm"),
                        "speed": .number(0.9),
                        "trailingSilence": .number(0.25),
                        "voice": .object(["id": .string("prior-voice"), "provider": .string("HUME_AI")])
                    ])
                ])
            ])
        ]
    ))

    #expect(result.audio == Data("hume".utf8))
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.hume.ai/v0/tts/file")
    #expect(request.headers["X-Hume-Api-Key"] == "hume-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["utterances"]?[0]?["text"]?.stringValue == "Hello")
    #expect(body["utterances"]?[0]?["voice"]?["id"]?.stringValue == "voice-id")
    #expect(body["utterances"]?[0]?["voice"]?["provider"]?.stringValue == "HUME_AI")
    #expect(body["format"]?["type"]?.stringValue == "wav")
    #expect(body["context"]?["utterances"]?[0]?["trailing_silence"]?.doubleValue == 0.25)
    #expect(body["context"]?["utterances"]?[0]?["trailingSilence"] == nil)
    #expect(body["context"]?["utterances"]?[0]?["voice"]?["id"]?.stringValue == "prior-voice")
}

@Test func humeSpeechMapsNestedProviderOptionsAndUtteranceFields() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("hume".utf8)))
    let provider = try AIProviders.hume(settings: ProviderSettings(apiKey: "hume-key", transport: transport))
    let model = try provider.speechModel("")

    _ = try await model.speak(SpeechRequest(
        text: "Hello",
        voice: "voice-id",
        format: "mp3",
        extraBody: [
            "hume": .object([
                "speed": 0.8,
                "description": "calm",
                "context": [
                    "generationId": "gen-123"
                ]
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["utterances"]?[0]?["text"]?.stringValue == "Hello")
    #expect(body["utterances"]?[0]?["speed"]?.doubleValue == 0.8)
    #expect(body["utterances"]?[0]?["description"]?.stringValue == "calm")
    #expect(body["context"]?["generation_id"]?.stringValue == "gen-123")
    #expect(body["hume"] == nil)
    #expect(body["speed"] == nil)
    #expect(body["description"] == nil)
    #expect(body["context"]?["generationId"] == nil)
}

@Test func elevenLabsSpeechUsesTextToSpeechVoiceEndpoint() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("eleven-audio".utf8)))
    let provider = try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: "eleven-key", transport: transport))
    let model = try provider.speechModel("eleven_multilingual_v2")

    let result = try await model.speak(SpeechRequest(
        text: "Hello",
        voice: "voice-123",
        format: "mp3_192",
        extraBody: [
            "languageCode": "en",
            "voiceSettings": ["similarityBoost": 0.7, "useSpeakerBoost": true],
            "enableLogging": false
        ]
    ))

    #expect(result.audio == Data("eleven-audio".utf8))
    #expect(result.contentType == "audio/mpeg")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.elevenlabs.io/v1/text-to-speech/voice-123?enable_logging=false&output_format=mp3_44100_192")
    #expect(request.headers["xi-api-key"] == "eleven-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["text"]?.stringValue == "Hello")
    #expect(body["model_id"]?.stringValue == "eleven_multilingual_v2")
    #expect(body["language_code"]?.stringValue == "en")
    #expect(body["voice_settings"]?["similarity_boost"]?.doubleValue == 0.7)
    #expect(body["voice_settings"]?["use_speaker_boost"]?.boolValue == true)
}

@Test func elevenLabsSpeechMapsNestedProviderOptionsAndMergesVoiceSettings() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("eleven-audio".utf8)))
    let provider = try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: "eleven-key", transport: transport))
    let model = try provider.speechModel("eleven_multilingual_v2")

    _ = try await model.speak(SpeechRequest(
        text: "Hello",
        voice: "voice-123",
        format: "mp3_128",
        extraBody: [
            "elevenlabs": .object([
                "languageCode": "ja",
                "speed": 0.85,
                "voiceSettings": [
                    "stability": 0.4,
                    "similarityBoost": 0.7,
                    "style": 0.2,
                    "useSpeakerBoost": true
                ],
                "pronunciationDictionaryLocators": [
                    ["pronunciationDictionaryId": "dict-1", "versionId": "v2"]
                ],
                "seed": 42,
                "previousText": "Before",
                "nextText": "After",
                "previousRequestIds": ["prev-1"],
                "nextRequestIds": ["next-1"],
                "applyTextNormalization": "auto",
                "applyLanguageTextNormalization": true,
                "enableLogging": false
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.elevenlabs.io/v1/text-to-speech/voice-123?enable_logging=false&output_format=mp3_44100_128")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["language_code"]?.stringValue == "ja")
    #expect(body["voice_settings"]?["speed"]?.doubleValue == 0.85)
    #expect(body["voice_settings"]?["stability"]?.doubleValue == 0.4)
    #expect(body["voice_settings"]?["similarity_boost"]?.doubleValue == 0.7)
    #expect(body["voice_settings"]?["style"]?.doubleValue == 0.2)
    #expect(body["voice_settings"]?["use_speaker_boost"]?.boolValue == true)
    #expect(body["pronunciation_dictionary_locators"]?[0]?["pronunciation_dictionary_id"]?.stringValue == "dict-1")
    #expect(body["pronunciation_dictionary_locators"]?[0]?["version_id"]?.stringValue == "v2")
    #expect(body["seed"]?.intValue == 42)
    #expect(body["previous_text"]?.stringValue == "Before")
    #expect(body["next_text"]?.stringValue == "After")
    #expect(body["previous_request_ids"]?[0]?.stringValue == "prev-1")
    #expect(body["next_request_ids"]?[0]?.stringValue == "next-1")
    #expect(body["apply_text_normalization"]?.stringValue == "auto")
    #expect(body["apply_language_text_normalization"]?.boolValue == true)
    #expect(body["elevenlabs"] == nil)
}

@Test func elevenLabsTranscriptionUsesSpeechToTextMultipartEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"language_code":"en","language_probability":0.99,"text":"eleven transcript","words":[{"text":"eleven","type":"word","start":0,"end":0.4}]}"#))
    let provider = try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: "eleven-key", transport: transport))
    let model = try provider.transcriptionModel("scribe_v1")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("mp3".utf8),
        fileName: "clip.mp3",
        mimeType: "audio/mpeg",
        language: "en",
        extraBody: ["tagAudioEvents": false, "timestampsGranularity": "word", "fileFormat": "other", "diarize": false]
    ))

    #expect(result.text == "eleven transcript")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.elevenlabs.io/v1/speech-to-text")
    #expect(request.headers["xi-api-key"] == "eleven-key")
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=ai-sdk-port-") == true)
    let body = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(body.contains("name=\"model_id\""))
    #expect(body.contains("scribe_v1"))
    #expect(body.contains("name=\"file\"; filename=\"clip.mp3\""))
    #expect(body.contains("name=\"diarize\""))
    #expect(body.contains("false"))
    #expect(body.contains("name=\"language_code\""))
    #expect(body.contains("en"))
    #expect(body.contains("name=\"tag_audio_events\""))
    #expect(body.contains("name=\"timestamps_granularity\""))
    #expect(body.contains("word"))
}

@Test func elevenLabsTranscriptionMapsNestedProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"language_code":"ja","language_probability":0.99,"text":"nested transcript"}"#))
    let provider = try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: "eleven-key", transport: transport))
    let model = try provider.transcriptionModel("scribe_v1")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("mp3".utf8),
        fileName: "clip.mp3",
        mimeType: "audio/mpeg",
        extraBody: [
            "elevenlabs": .object([
                "languageCode": "ja",
                "tagAudioEvents": true,
                "numSpeakers": 2,
                "timestampsGranularity": "character",
                "fileFormat": "mp3",
                "diarize": false
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(body.contains("name=\"language_code\""))
    #expect(body.contains("ja"))
    #expect(body.contains("name=\"tag_audio_events\""))
    #expect(body.contains("true"))
    #expect(body.contains("name=\"num_speakers\""))
    #expect(body.contains("2"))
    #expect(body.contains("name=\"timestamps_granularity\""))
    #expect(body.contains("character"))
    #expect(body.contains("name=\"file_format\""))
    #expect(body.contains("mp3"))
    #expect(body.contains("name=\"diarize\""))
    #expect(body.contains("false"))
    #expect(!body.contains("elevenlabs"))
}

@Test func googleLanguageStreamsGenerateContentEvents() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"candidates":[{"content":{"parts":[{"text":"gem"}],"role":"model"},"index":0,"groundingMetadata":{"groundingChunks":[{"web":{"uri":"https://source.example.com","title":"Source Title"}}]}}]}

    data: {"candidates":[{"content":{"parts":[{"text":"ini"}],"role":"model"},"finishReason":"STOP","index":0,"groundingMetadata":{"groundingChunks":[{"web":{"uri":"https://source.example.com","title":"Source Title"}}]}}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":2,"totalTokenCount":3}}

    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    var deltas: [String] = []
    var sources: [AISource] = []
    var usage: TokenUsage?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Ping")])) {
        switch part {
        case let .textDelta(delta):
            deltas.append(delta)
        case let .source(source):
            sources.append(source)
        case let .finish(_, value):
            usage = value
        default:
            break
        }
    }

    #expect(deltas == ["gem", "ini"])
    #expect(sources.count == 1)
    #expect(sources[0].id == "grounding-0")
    #expect(sources[0].url == "https://source.example.com")
    #expect(sources[0].title == "Source Title")
    #expect(usage?.totalTokens == 3)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse")
    #expect(request.headers["x-goog-api-key"] == "gemini-key")
}

@Test func googleLanguageStreamsFunctionCallPartialArguments() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"weather","willContinue":true}}]},"index":0}]}

    data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"partialArgs":[{"jsonPath":"$.location","stringValue":"San ","willContinue":true}],"willContinue":true}}]},"index":0}]}

    data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"partialArgs":[{"jsonPath":"$.location","stringValue":"Francisco","willContinue":true}],"willContinue":true}}]},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":29,"candidatesTokenCount":15,"totalTokenCount":44}}

    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    var finalCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Weather?")])) {
        switch part {
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
    #expect(call.id == "tool-call-0")
    #expect(call.name == "weather")
    #expect(try decodeJSONBody(Data(call.arguments.utf8))["location"]?.stringValue == "San Francisco")
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 44)
}

@Test func gatewayLanguageUsesGatewayEndpointAndModelHeaders() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"via gateway"}],"finishReason":"stop"}
    """))
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: transport), teamIDOrSlug: "team_123")
    let model = try provider.languageModel("openai/gpt-4.1-mini")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "via gateway")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://ai-gateway.vercel.sh/v4/ai/language-model")
    #expect(request.headers["Authorization"] == "Bearer gateway-key")
    #expect(request.headers["x-vercel-ai-gateway-team"] == "team_123")
    #expect(request.headers["ai-language-model-id"] == "openai/gpt-4.1-mini")
    #expect(request.headers["ai-language-model-streaming"] == "false")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
}

@Test func gatewayLanguageMapsToolsToolChoiceAndContentToolCalls() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"checking"},{"type":"source","sourceType":"url","id":"src_1","url":"https://example.com/a","title":"Example A","providerMetadata":{"gateway":{"rank":1}}},{"type":"tool-call","toolCallId":"call_1","toolName":"lookup","input":"{\\"query\\":\\"weather\\"}"},{"type":"tool-call","toolCallId":"gateway_search","toolName":"perplexity_search","input":{"query":"latest news"},"providerExecuted":true}],"finishReason":"stop","usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}}
    """))
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: transport))
    let model = try provider.languageModel("openai/gpt-4.1-mini")

    let result = try await model.generate(LanguageModelRequest(
        messages: [AIMessage(role: .user, content: [
            .text("Use tools."),
            .imageURL("https://example.com/image.png"),
            .data(mimeType: "application/pdf", data: Data("%PDF".utf8))
        ])],
        tools: [
            "lookup": [
                "type": "object",
                "description": "Look up a value.",
                "properties": ["query": ["type": "string"]]
            ],
            "gateway.perplexity_search": [
                "type": "provider",
                "id": "gateway.perplexity_search",
                "name": "perplexity_search",
                "args": ["maxResults": 5]
            ]
        ],
        extraBody: [
            "toolChoice": ["type": "tool", "toolName": "lookup"],
            "providerOptions": ["gateway": ["order": ["openai", "anthropic"]]]
        ]
    ))

    #expect(result.text == "checking")
    #expect(result.finishReason == "tool-calls")
    #expect(result.usage?.totalTokens == 5)
    #expect(result.toolCalls.count == 2)
    #expect(result.toolCalls[0].id == "call_1")
    #expect(result.toolCalls[0].name == "lookup")
    #expect(result.toolCalls[0].arguments == #"{"query":"weather"}"#)
    #expect(result.toolCalls[1].providerExecuted == true)
    #expect(try decodeJSONBody(Data(result.toolCalls[1].arguments.utf8))["query"]?.stringValue == "latest news")
    #expect(result.sources.count == 1)
    #expect(result.sources[0].id == "src_1")
    #expect(result.sources[0].sourceType == "url")
    #expect(result.sources[0].url == "https://example.com/a")
    #expect(result.sources[0].title == "Example A")
    #expect(result.sources[0].providerMetadata["gateway"]?["rank"]?.intValue == 1)

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?[0]?["content"]?[1]?["data"]?["type"]?.stringValue == "url")
    #expect(body["prompt"]?[0]?["content"]?[1]?["data"]?["url"]?.stringValue == "https://example.com/image.png")
    #expect(body["prompt"]?[0]?["content"]?[2]?["data"]?["type"]?.stringValue == "data")
    #expect(body["prompt"]?[0]?["content"]?[2]?["data"]?["data"]?.stringValue == Data("%PDF".utf8).base64EncodedString())
    #expect(body["prompt"]?[0]?["content"]?[2]?["mediaType"]?.stringValue == "application/pdf")
    let tools = try #require(body["tools"]?.arrayValue)
    let functionTool = try #require(tools.first { $0["type"]?.stringValue == "function" })
    #expect(functionTool["name"]?.stringValue == "lookup")
    #expect(functionTool["description"]?.stringValue == "Look up a value.")
    #expect(functionTool["inputSchema"]?["properties"]?["query"]?["type"]?.stringValue == "string")
    let providerTool = try #require(tools.first { $0["type"]?.stringValue == "provider" })
    #expect(providerTool["id"]?.stringValue == "gateway.perplexity_search")
    #expect(providerTool["name"]?.stringValue == "perplexity_search")
    #expect(providerTool["args"]?["maxResults"]?.intValue == 5)
    #expect(body["toolChoice"]?["type"]?.stringValue == "tool")
    #expect(body["toolChoice"]?["toolName"]?.stringValue == "lookup")
    #expect(body["providerOptions"]?["gateway"]?["order"]?[0]?.stringValue == "openai")
}

@Test func gatewayToolsHelpersMirrorProviderExecutedToolFactories() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"finishReason":"stop"}
    """))
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: transport))
    let model = try provider.languageModel("openai/gpt-4.1-mini")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Search.")],
        tools: [
            "gateway.perplexity_search": GatewayTools.perplexitySearch(
                maxResults: 5,
                maxTokensPerPage: 3000,
                maxTokens: 9000,
                country: "US",
                searchDomainFilter: ["nature.com"],
                searchLanguageFilter: ["en"],
                searchRecencyFilter: "week"
            ),
            "gateway.parallel_search": GatewayTools.parallelSearch(
                mode: "agentic",
                maxResults: 3,
                includeDomains: ["example.com"],
                excludeDomains: ["spam.example"],
                afterDate: "2024-01-01",
                maxCharsPerResult: 500,
                maxCharsTotal: 2000,
                maxAgeSeconds: 60
            )
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    let perplexitySearch = try #require(tools.first { $0["id"]?.stringValue == "gateway.perplexity_search" })
    #expect(perplexitySearch["type"]?.stringValue == "provider")
    #expect(perplexitySearch["name"]?.stringValue == "perplexity_search")
    #expect(perplexitySearch["args"]?["maxResults"]?.intValue == 5)
    #expect(perplexitySearch["args"]?["maxTokensPerPage"]?.intValue == 3000)
    #expect(perplexitySearch["args"]?["maxTokens"]?.intValue == 9000)
    #expect(perplexitySearch["args"]?["country"]?.stringValue == "US")
    #expect(perplexitySearch["args"]?["searchDomainFilter"]?[0]?.stringValue == "nature.com")
    #expect(perplexitySearch["args"]?["searchLanguageFilter"]?[0]?.stringValue == "en")
    #expect(perplexitySearch["args"]?["searchRecencyFilter"]?.stringValue == "week")

    let parallelSearch = try #require(tools.first { $0["id"]?.stringValue == "gateway.parallel_search" })
    #expect(parallelSearch["type"]?.stringValue == "provider")
    #expect(parallelSearch["name"]?.stringValue == "parallel_search")
    #expect(parallelSearch["args"]?["mode"]?.stringValue == "agentic")
    #expect(parallelSearch["args"]?["maxResults"]?.intValue == 3)
    #expect(parallelSearch["args"]?["sourcePolicy"]?["includeDomains"]?[0]?.stringValue == "example.com")
    #expect(parallelSearch["args"]?["sourcePolicy"]?["excludeDomains"]?[0]?.stringValue == "spam.example")
    #expect(parallelSearch["args"]?["sourcePolicy"]?["afterDate"]?.stringValue == "2024-01-01")
    #expect(parallelSearch["args"]?["excerpts"]?["maxCharsPerResult"]?.intValue == 500)
    #expect(parallelSearch["args"]?["excerpts"]?["maxCharsTotal"]?.intValue == 2000)
    #expect(parallelSearch["args"]?["fetchPolicy"]?["maxAgeSeconds"]?.intValue == 60)
}

@Test func gatewayLanguageStreamsV4ReasoningAndToolInputChunks() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"text-delta","id":"txt","delta":"Hello"}

    data: {"type":"reasoning-delta","id":"r","delta":"think"}

    data: {"type":"source","sourceType":"document","id":"doc_1","title":"Report","mediaType":"application/pdf","filename":"report.pdf","providerMetadata":{"gateway":{"page":2}}}

    data: {"type":"tool-input-start","id":"call_1","toolName":"lookup"}

    data: {"type":"tool-input-delta","id":"call_1","delta":"{\\"query\\":"}

    data: {"type":"tool-input-delta","id":"call_1","delta":"\\"weather\\"}"}

    data: {"type":"tool-input-end","id":"call_1"}

    data: {"type":"finish","finishReason":"stop","usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}}

    """))
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: transport))
    let model = try provider.languageModel("openai/gpt-4.1-mini")

    var textDeltas: [String] = []
    var reasoningDeltas: [String] = []
    var argumentDeltas: [String] = []
    var sources: [AISource] = []
    var toolCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Use a tool.")])) {
        switch part {
        case let .textDelta(delta):
            textDeltas.append(delta)
        case let .reasoningDelta(delta):
            reasoningDeltas.append(delta)
        case let .source(source):
            sources.append(source)
        case let .toolCallDelta(_, _, argumentsDelta, _):
            argumentDeltas.append(argumentsDelta)
        case let .toolCall(call):
            toolCall = call
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(textDeltas == ["Hello"])
    #expect(reasoningDeltas == ["think"])
    #expect(sources.count == 1)
    #expect(sources[0].id == "doc_1")
    #expect(sources[0].sourceType == "document")
    #expect(sources[0].title == "Report")
    #expect(sources[0].mediaType == "application/pdf")
    #expect(sources[0].filename == "report.pdf")
    #expect(sources[0].providerMetadata["gateway"]?["page"]?.intValue == 2)
    #expect(argumentDeltas == [#"{"query":"#, #""weather"}"#])
    #expect(toolCall?.id == "call_1")
    #expect(toolCall?.name == "lookup")
    #expect(toolCall?.arguments == #"{"query":"weather"}"#)
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 5)
}

@Test func gatewayEmbeddingAndRerankingUseGatewayEndpoints() async throws {
    let embeddingTransport = RecordingTransport(response: jsonResponse("""
    {"embeddings":[[0.1,0.2]],"usage":{"tokens":3}}
    """))
    let gateway = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: embeddingTransport))
    let embeddings = try await gateway.embeddingModel("text-embedding").embed(EmbeddingRequest(values: ["a"]))
    #expect(embeddings.embeddings == [[0.1, 0.2]])
    #expect(embeddings.usage?.totalTokens == 3)
    let embeddingRequest = try #require(await embeddingTransport.requests().first)
    #expect(embeddingRequest.url.absoluteString == "https://ai-gateway.vercel.sh/v4/ai/embedding-model")
    #expect(embeddingRequest.headers["ai-model-id"] == "text-embedding")

    let rerankTransport = RecordingTransport(response: jsonResponse("""
    {"ranking":[{"index":1,"relevanceScore":0.9}]}
    """))
    let rerankGateway = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: rerankTransport))
    let ranking = try await rerankGateway.rerankingModel("reranker").rerank(RerankingRequest(query: "q", documents: ["a", "b"], topK: 1))
    #expect(ranking.results == [RerankedDocument(index: 1, score: 0.9)])
    let rerankRequest = try #require(await rerankTransport.requests().first)
    #expect(rerankRequest.url.absoluteString == "https://ai-gateway.vercel.sh/v4/ai/reranking-model")
    let rerankBody = try decodeJSONBody(try #require(rerankRequest.body))
    #expect(rerankBody["topN"]?.intValue == 1)
}

@Test func gatewayMetadataMethodsUseManagementEndpointsAndMapResponses() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"models":[{"id":"openai/gpt-5","name":"GPT-5","modelType":"language","specification":{"specificationVersion":"v4","provider":"openai","modelId":"gpt-5"}}]}"#),
        jsonResponse(#"{"balance":"42.00","total_used":"8.50"}"#),
        jsonResponse("""
        {"results":[{"day":"2026-03-01","model":"anthropic/claude-sonnet-4.6","provider":"anthropic","credential_type":"byok","total_cost":10.5,"market_cost":9.25,"input_tokens":100,"output_tokens":50,"cached_input_tokens":20,"cache_creation_input_tokens":5,"reasoning_tokens":7,"request_count":25}]}
        """),
        jsonResponse("""
        {"data":{"id":"gen_01","total_cost":0.12,"upstream_inference_cost":0.08,"usage":0.12,"created_at":"2026-03-01T00:00:00Z","model":"anthropic/claude-sonnet-4.6","is_byok":true,"provider_name":"anthropic","streamed":true,"finish_reason":"stop","latency":123,"generation_time":456,"native_tokens_prompt":100,"native_tokens_completion":50,"native_tokens_reasoning":7,"native_tokens_cached":20,"native_tokens_cache_creation":5,"billable_web_search_calls":2}}
        """)
    ])
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", baseURL: "https://custom-gateway.example.com/v4/ai", transport: transport), teamIDOrSlug: "team_123")

    let models = try await provider.getAvailableModels()
    #expect(models.first?.id == "openai/gpt-5")
    #expect(models.first?.provider == "openai")
    #expect(models.first?.modelID == "gpt-5")

    let credits = try await provider.getCredits()
    #expect(credits == GatewayCredits(balance: "42.00", totalUsed: "8.50"))

    let report = try await provider.getSpendReport(GatewaySpendReportParams(
        startDate: "2026-03-01",
        endDate: "2026-03-25",
        groupBy: "model",
        datePart: "day",
        userID: "user-123",
        model: "anthropic/claude-sonnet-4.6",
        provider: "anthropic",
        credentialType: "byok",
        tags: ["production", "api"]
    ))
    #expect(report.results.first?.day == "2026-03-01")
    #expect(report.results.first?.model == "anthropic/claude-sonnet-4.6")
    #expect(report.results.first?.credentialType == "byok")
    #expect(report.results.first?.totalCost == 10.5)
    #expect(report.results.first?.marketCost == 9.25)
    #expect(report.results.first?.inputTokens == 100)
    #expect(report.results.first?.requestCount == 25)

    let generation = try await provider.getGenerationInfo(id: "gen_01")
    #expect(generation.id == "gen_01")
    #expect(generation.totalCost == 0.12)
    #expect(generation.upstreamInferenceCost == 0.08)
    #expect(generation.model == "anthropic/claude-sonnet-4.6")
    #expect(generation.isByok)
    #expect(generation.providerName == "anthropic")
    #expect(generation.streamed)
    #expect(generation.finishReason == "stop")
    #expect(generation.promptTokens == 100)
    #expect(generation.billableWebSearchCalls == 2)

    let requests = await transport.requests()
    #expect(requests.count == 4)
    #expect(requests[0].url.absoluteString == "https://custom-gateway.example.com/v4/ai/config")
    #expect(requests[1].url.absoluteString == "https://custom-gateway.example.com/v1/credits")
    #expect(requests[2].url.path == "/v1/report")
    let reportItems = Dictionary(uniqueKeysWithValues: URLComponents(url: requests[2].url, resolvingAgainstBaseURL: false)?.queryItems?.map { ($0.name, $0.value ?? "") } ?? [])
    #expect(reportItems["start_date"] == "2026-03-01")
    #expect(reportItems["end_date"] == "2026-03-25")
    #expect(reportItems["group_by"] == "model")
    #expect(reportItems["date_part"] == "day")
    #expect(reportItems["user_id"] == "user-123")
    #expect(reportItems["model"] == "anthropic/claude-sonnet-4.6")
    #expect(reportItems["provider"] == "anthropic")
    #expect(reportItems["credential_type"] == "byok")
    #expect(reportItems["tags"] == "production,api")
    #expect(requests[3].url.absoluteString == "https://custom-gateway.example.com/v1/generation?id=gen_01")
    for request in requests {
        #expect(request.headers["Authorization"] == "Bearer gateway-key")
        #expect(request.headers["x-vercel-ai-gateway-team"] == "team_123")
        #expect(request.headers["ai-gateway-protocol-version"] == "0.0.1")
    }
}

@Test func gatewayImageMapsFilesMaskAndProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"images":["base64-image"]}"#))
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: transport))
    let model = try provider.imageModel("google/imagen-4.0-generate")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "Edit these images",
        size: "1024x1024",
        count: 2,
        files: [
            ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png"),
            ImageInputFile(url: "https://example.com/reference.png")
        ],
        mask: ImageInputFile(data: Data([4, 5, 6]), mediaType: "image/png"),
        extraBody: [
            "aspectRatio": "16:9",
            "seed": 42,
            "providerOptions": [
                "gateway": [
                    "order": ["vertex", "openai"],
                    "serviceTier": "priority"
                ]
            ]
        ]
    ))

    #expect(result.base64Images == ["base64-image"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://ai-gateway.vercel.sh/v4/ai/image-model")
    #expect(request.headers["ai-image-model-specification-version"] == "4")
    #expect(request.headers["ai-model-id"] == "google/imagen-4.0-generate")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?.stringValue == "Edit these images")
    #expect(body["n"]?.intValue == 2)
    #expect(body["size"]?.stringValue == "1024x1024")
    #expect(body["aspectRatio"]?.stringValue == "16:9")
    #expect(body["seed"]?.intValue == 42)
    #expect(body["providerOptions"]?["gateway"]?["order"]?[0]?.stringValue == "vertex")
    #expect(body["providerOptions"]?["gateway"]?["serviceTier"]?.stringValue == "priority")
    #expect(body["files"]?[0]?["type"]?.stringValue == "file")
    #expect(body["files"]?[0]?["mediaType"]?.stringValue == "image/png")
    #expect(body["files"]?[0]?["data"]?.stringValue == Data([1, 2, 3]).base64EncodedString())
    #expect(body["files"]?[1]?["type"]?.stringValue == "url")
    #expect(body["files"]?[1]?["url"]?.stringValue == "https://example.com/reference.png")
    #expect(body["mask"]?["type"]?.stringValue == "file")
    #expect(body["mask"]?["mediaType"]?.stringValue == "image/png")
    #expect(body["mask"]?["data"]?.stringValue == Data([4, 5, 6]).base64EncodedString())
}

@Test func gatewayVideoThrowsOnErrorEvent() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"error","message":"Rate limit exceeded","errorType":"rate_limit_exceeded","statusCode":429,"param":null}

    """))
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: transport))
    let model = try provider.videoModel("fal/luma-ray-2")

    do {
        _ = try await model.generateVideo(VideoGenerationRequest(
            prompt: "A sunset",
            aspectRatio: "16:9",
            durationSeconds: 5,
            extraBody: [
                "n": 1,
                "resolution": "1920x1080",
                "fps": 24,
                "seed": 42,
                "providerOptions": ["fal": ["motionStrength": 0.8]]
            ]
        ))
        Issue.record("Expected Gateway video error event to throw.")
    } catch let error as AIError {
        #expect(error == .httpStatus(provider: "gateway", statusCode: 429, body: "Rate limit exceeded"))
    }

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://ai-gateway.vercel.sh/v4/ai/video-model")
    #expect(request.headers["ai-video-model-specification-version"] == "4")
    #expect(request.headers["ai-model-id"] == "fal/luma-ray-2")
    #expect(request.headers["accept"] == "text/event-stream")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?.stringValue == "A sunset")
    #expect(body["aspectRatio"]?.stringValue == "16:9")
    #expect(body["duration"]?.intValue == 5)
    #expect(body["n"]?.intValue == 1)
    #expect(body["resolution"]?.stringValue == "1920x1080")
    #expect(body["fps"]?.intValue == 24)
    #expect(body["seed"]?.intValue == 42)
    #expect(body["providerOptions"]?["fal"]?["motionStrength"]?.doubleValue == 0.8)
}

@Test func cohereLanguageUsesChatEndpointAndCohereShape() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"generation_id":"gen-1","message":{"role":"assistant","content":[{"type":"text","text":"co"},{"type":"text","text":"here"}]},"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":3,"output_tokens":2},"billed_units":{"input_tokens":3,"output_tokens":2}}}
    """))
    let provider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: transport))
    let model = try provider.languageModel("command-a-03-2025")

    let result = try await model.generate(LanguageModelRequest(messages: [.system("Brief."), .user("Hi")], topP: 0.8, maxOutputTokens: 12))

    #expect(result.text == "cohere")
    #expect(result.finishReason == "stop")
    #expect(result.usage?.totalTokens == 5)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.cohere.com/v2/chat")
    #expect(request.headers["Authorization"] == "Bearer cohere-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "command-a-03-2025")
    #expect(body["messages"]?[0]?["role"]?.stringValue == "system")
    #expect(body["messages"]?[1]?["content"]?.stringValue == "Hi")
    #expect(body["p"]?.doubleValue == 0.8)
    #expect(body["max_tokens"]?.intValue == 12)
    #expect(body["documents"] == nil)
}

@Test func cohereLanguageExtractsUserFilesIntoDocuments() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"generation_id":"gen-1","message":{"role":"assistant","content":[{"type":"text","text":"done"}]},"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":3,"output_tokens":1}}}
    """))
    let provider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: transport))
    let model = try provider.languageModel("command-r-plus")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .text("What do these documents say?"),
            .file(mimeType: "text/plain", data: Data("First document content".utf8), filename: "doc1.txt"),
            .file(mimeType: "application/json", data: Data("{\"key\":\"value\"}".utf8), filename: "data.json"),
            .data(mimeType: "application/pdf", data: Data("PDF-like content".utf8))
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["messages"]?[0]?["role"]?.stringValue == "user")
    #expect(body["messages"]?[0]?["content"]?.stringValue == "What do these documents say?")
    #expect(body["documents"]?.arrayValue?.count == 3)
    #expect(body["documents"]?[0]?["data"]?["text"]?.stringValue == "First document content")
    #expect(body["documents"]?[0]?["data"]?["title"]?.stringValue == "doc1.txt")
    #expect(body["documents"]?[1]?["data"]?["text"]?.stringValue == "{\"key\":\"value\"}")
    #expect(body["documents"]?[1]?["data"]?["title"]?.stringValue == "data.json")
    #expect(body["documents"]?[2]?["data"]?["text"]?.stringValue == "PDF-like content")
    #expect(body["documents"]?[2]?["data"]?["title"] == nil)
    #expect(String(data: try #require(request.body), encoding: .utf8)?.contains("application/pdf") == false)
}

@Test func cohereLanguageKeepsImagesInlineWhileExtractingDocuments() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"generation_id":"gen-1","message":{"role":"assistant","content":[{"type":"text","text":"done"}]},"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":3,"output_tokens":1}}}
    """))
    let provider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: transport))
    let model = try provider.languageModel("command-r-plus")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .text("Use both."),
            .file(mimeType: "image/png", data: Data([0, 1, 2, 3]), filename: "image.png"),
            .file(mimeType: "text/plain", data: Data("Document text".utf8), filename: "note.txt")
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content[0]["type"]?.stringValue == "text")
    #expect(content[0]["text"]?.stringValue == "Use both.")
    #expect(content[1]["type"]?.stringValue == "image_url")
    #expect(content[1]["image_url"]?["url"]?.stringValue == "data:image/png;base64,AAECAw==")
    #expect(body["documents"]?.arrayValue?.count == 1)
    #expect(body["documents"]?[0]?["data"]?["text"]?.stringValue == "Document text")
    #expect(body["documents"]?[0]?["data"]?["title"]?.stringValue == "note.txt")
}

@Test func cohereLanguageParsesToolCallsAndNullArguments() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"generation_id":"gen-1","message":{"role":"assistant","content":[],"tool_calls":[{"id":"currentTime_tf4dywn8wgnk","type":"function","function":{"name":"currentTime","arguments":"null"}}]},"finish_reason":"TOOL_CALL","usage":{"tokens":{"input_tokens":3,"output_tokens":2}}}
    """))
    let provider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: transport))
    let model = try provider.languageModel("command-a-03-2025")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("What time is it?")]))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.usage?.totalTokens == 5)
    #expect(result.toolCalls.count == 1)
    #expect(result.toolCalls[0].id == "currentTime_tf4dywn8wgnk")
    #expect(result.toolCalls[0].name == "currentTime")
    #expect(result.toolCalls[0].arguments == "{}")
}

@Test func cohereLanguageMapsCitationSources() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"generation_id":"gen-1","message":{"role":"assistant","content":[{"type":"text","text":"AI helps automate work."}],"citations":[{"start":9,"end":17,"text":"automate","sources":[{"type":"document","id":"doc:0","document":{"id":"doc:0","text":"AI helps automate work.","title":"benefits.txt"}}],"type":"TEXT_CONTENT"}]},"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":3,"output_tokens":4}}}
    """))
    let provider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: transport))
    let model = try provider.languageModel("command-r-plus")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("What are AI benefits?")]))

    #expect(result.text == "AI helps automate work.")
    #expect(result.sources.count == 1)
    #expect(result.sources[0].id == "cohere-citation-0")
    #expect(result.sources[0].sourceType == "document")
    #expect(result.sources[0].title == "benefits.txt")
    #expect(result.sources[0].mediaType == "text/plain")
    #expect(result.sources[0].providerMetadata["cohere"]?["start"]?.intValue == 9)
    #expect(result.sources[0].providerMetadata["cohere"]?["end"]?.intValue == 17)
    #expect(result.sources[0].providerMetadata["cohere"]?["text"]?.stringValue == "automate")
    #expect(result.sources[0].providerMetadata["cohere"]?["citationType"]?.stringValue == "TEXT_CONTENT")
    #expect(result.sources[0].providerMetadata["cohere"]?["sources"]?[0]?["document"]?["title"]?.stringValue == "benefits.txt")
    #expect(result.sources[0].rawValue?["sources"]?[0]?["id"]?.stringValue == "doc:0")
}

@Test func mistralLanguageUsesNativeChatShapeAndOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-1","object":"chat.completion","model":"mistral-large-latest","choices":[{"index":0,"message":{"role":"assistant","content":[{"type":"thinking","thinking":[{"type":"text","text":"hmm"}]},{"type":"text","text":"bonjour"}]},"finish_reason":"model_length"}],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}
    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-large-latest")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .system("Reply in French."),
            AIMessage(role: .user, content: [.text("See this"), .data(mimeType: "application/pdf", data: Data("pdf".utf8))])
        ],
        temperature: 0.2,
        topP: 0.9,
        maxOutputTokens: 16,
        tools: [
            "lookup": [
                "type": "object",
                "description": "Look up a value.",
                "properties": ["value": ["type": "string"]],
                "required": ["value"]
            ],
            "unused": ["type": "object"]
        ],
        extraBody: [
            "safePrompt": true,
            "randomSeed": 7,
            "documentPageLimit": 2,
            "parallelToolCalls": false,
            "toolChoice": ["type": "tool", "toolName": "lookup"]
        ]
    ))

    #expect(result.text == "bonjour")
    #expect(result.finishReason == "length")
    #expect(result.usage?.totalTokens == 5)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.mistral.ai/v1/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer mistral-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "mistral-large-latest")
    #expect(body["messages"]?[0]?["role"]?.stringValue == "system")
    #expect(body["messages"]?[1]?["content"]?[0]?["type"]?.stringValue == "text")
    #expect(body["messages"]?[1]?["content"]?[1]?["type"]?.stringValue == "document_url")
    #expect(body["messages"]?[1]?["content"]?[1]?["document_url"]?.stringValue?.hasPrefix("data:application/pdf;base64,") == true)
    #expect(body["safe_prompt"]?.boolValue == true)
    #expect(body["random_seed"]?.intValue == 7)
    #expect(body["document_page_limit"]?.intValue == 2)
    #expect(body["tools"]?.arrayValue?.count == 1)
    #expect(body["tools"]?[0]?["type"]?.stringValue == "function")
    #expect(body["tools"]?[0]?["function"]?["name"]?.stringValue == "lookup")
    #expect(body["tools"]?[0]?["function"]?["description"]?.stringValue == "Look up a value.")
    #expect(body["tools"]?[0]?["function"]?["parameters"]?["properties"]?["value"]?["type"]?.stringValue == "string")
    #expect(body["tool_choice"]?.stringValue == "any")
    #expect(body["parallel_tool_calls"]?.boolValue == false)
}

@Test func mistralUnknownFinishReasonMapsToOtherAndParallelToolsNeedTools() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-1","object":"chat.completion","model":"mistral-large-latest","choices":[{"index":0,"message":{"role":"assistant","content":"done"},"finish_reason":"unexpected"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-large-latest")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: ["parallelToolCalls": false, "toolChoice": "required"]
    ))

    #expect(result.finishReason == "other")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["parallel_tool_calls"] == nil)
    #expect(body["tool_choice"] == nil)
    #expect(body["tools"] == nil)
}

@Test func mistralLanguageParsesToolCalls() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-1","object":"chat.completion","model":"mistral-small-latest","choices":[{"index":0,"message":{"role":"assistant","content":"","tool_calls":[{"id":"gSIMJiOkT","function":{"name":"weather","arguments":"{\\"location\\": \\"San Francisco\\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":124,"completion_tokens":22,"total_tokens":146}}
    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-small-latest")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Weather?")],
        tools: ["weather": ["type": "object", "properties": ["location": ["type": "string"]]]]
    ))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.usage?.totalTokens == 146)
    #expect(result.toolCalls.count == 1)
    #expect(result.toolCalls[0].id == "gSIMJiOkT")
    #expect(result.toolCalls[0].name == "weather")
    #expect(try decodeJSONBody(Data(result.toolCalls[0].arguments.utf8))["location"]?.stringValue == "San Francisco")
}

@Test func mistralLanguageStreamsNativeChunks() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"cmpl-1","model":"mistral","choices":[{"index":0,"delta":{"role":"assistant","content":[{"type":"thinking","thinking":[{"type":"text","text":"hmm"}]}]},"finish_reason":null}]}

    data: {"id":"cmpl-1","model":"mistral","choices":[{"index":0,"delta":{"content":[{"type":"text","text":"bon"}]},"finish_reason":null}]}

    data: {"id":"cmpl-1","model":"mistral","choices":[{"index":0,"delta":{"content":"jour"},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}

    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-large-latest")

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

    #expect(reasoning == ["hmm"])
    #expect(text == ["bon", "jour"])
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 3)
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
}

@Test func mistralLanguageStreamsToolCalls() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"cmpl-1","model":"mistral-small-latest","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

    data: {"id":"cmpl-1","model":"mistral-small-latest","choices":[{"index":0,"delta":{"content":null,"tool_calls":[{"id":"gSIMJiOkT","function":{"name":"weather","arguments":"{\\"location\\": \\"San Francisco\\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":124,"completion_tokens":22,"total_tokens":146}}

    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-small-latest")

    var deltas: [String] = []
    var toolCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Weather?")],
        tools: ["weather": ["type": "object", "properties": ["location": ["type": "string"]]]]
    )) {
        switch part {
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
    #expect(deltas == [#"{"location": "San Francisco"}"#])
    #expect(finalToolCall.id == "gSIMJiOkT")
    #expect(finalToolCall.name == "weather")
    #expect(try decodeJSONBody(Data(finalToolCall.arguments.utf8))["location"]?.stringValue == "San Francisco")
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 146)
}

@Test func mistralEmbeddingUsesFloatEncodingAndLimit() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"embedding":[0.1,0.2]},{"embedding":[0.3,0.4]}],"usage":{"prompt_tokens":6}}"#))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.embeddingModel("mistral-embed")

    let result = try await model.embed(EmbeddingRequest(values: ["hello", "world"]))

    #expect(result.embeddings == [[0.1, 0.2], [0.3, 0.4]])
    #expect(result.usage?.inputTokens == 6)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.mistral.ai/v1/embeddings")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["input"]?[0]?.stringValue == "hello")
    #expect(body["encoding_format"]?.stringValue == "float")
}

@Test func mistralModelsMapNestedProviderOptions() async throws {
    let chatTransport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}"#))
    let chatProvider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: chatTransport))
    let chatModel = try chatProvider.languageModel("mistral-small-latest")

    _ = try await chatModel.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        tools: ["lookup": ["type": "object", "properties": [:]]],
        extraBody: [
            "safePrompt": false,
            "mistral": [
                "safePrompt": true,
                "randomSeed": 11,
                "documentImageLimit": 3,
                "parallelToolCalls": false,
                "reasoningEffort": "high"
            ]
        ]
    ))

    let chatRequest = try #require(await chatTransport.requests().first)
    let chatBody = try decodeJSONBody(try #require(chatRequest.body))
    #expect(chatBody["mistral"] == nil)
    #expect(chatBody["safe_prompt"]?.boolValue == true)
    #expect(chatBody["random_seed"]?.intValue == 11)
    #expect(chatBody["document_image_limit"]?.intValue == 3)
    #expect(chatBody["parallel_tool_calls"]?.boolValue == false)
    #expect(chatBody["reasoning_effort"]?.stringValue == "high")

    let embeddingTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"embedding":[0.1,0.2]}]}"#))
    let embeddingProvider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: embeddingTransport))
    let embeddingModel = try embeddingProvider.embeddingModel("mistral-embed")

    _ = try await embeddingModel.embed(EmbeddingRequest(
        values: ["hello"],
        extraBody: ["mistral": ["encoding_format": "float"]]
    ))

    let embeddingRequest = try #require(await embeddingTransport.requests().first)
    let embeddingBody = try decodeJSONBody(try #require(embeddingRequest.body))
    #expect(embeddingBody["mistral"] == nil)
    #expect(embeddingBody["encoding_format"]?.stringValue == "float")
}

@Test func cohereLanguageStreamsChatEvents() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"content-delta","index":0,"delta":{"message":{"content":{"text":"co"}}}}

    data: {"type":"content-delta","index":0,"delta":{"message":{"content":{"text":"here"}}}}

    data: {"type":"message-end","delta":{"finish_reason":"MAX_TOKENS","usage":{"tokens":{"input_tokens":1,"output_tokens":2}}}}

    """))
    let provider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: transport))
    let model = try provider.languageModel("command-a-03-2025")

    var deltas: [String] = []
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textDelta(delta):
            deltas.append(delta)
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(deltas == ["co", "here"])
    #expect(finishReason == "length")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
}

@Test func cohereLanguageStreamsToolCallEvents() async throws {
    let transport = RecordingTransport(response: sseResponse(#"""
    data: {"type":"tool-call-start","delta":{"message":{"tool_calls":{"id":"weather_dqgshstja6p9","type":"function","function":{"name":"weather","arguments":"{\"location\":"}}}}}

    data: {"type":"tool-call-delta","delta":{"message":{"tool_calls":{"function":{"arguments":"\"San Francisco\"}"}}}}}

    data: {"type":"tool-call-end"}

    data: {"type":"message-end","delta":{"finish_reason":"TOOL_CALL","usage":{"tokens":{"input_tokens":3,"output_tokens":2}}}}

    """#))
    let provider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: transport))
    let model = try provider.languageModel("command-a-03-2025")

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

    let call = try #require(finalCall)
    #expect(deltas == ["{\"location\":", "\"San Francisco\"}"])
    #expect(call.id == "weather_dqgshstja6p9")
    #expect(call.name == "weather")
    #expect(try decodeJSONBody(Data(call.arguments.utf8))["location"]?.stringValue == "San Francisco")
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 5)
}

@Test func cohereEmbeddingAndRerankingUseNativeEndpoints() async throws {
    let embeddingTransport = RecordingTransport(response: jsonResponse("""
    {"embeddings":{"float":[[0.1,0.2],[0.3,0.4]]},"meta":{"billed_units":{"input_tokens":7}}}
    """))
    let embeddingProvider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: embeddingTransport))
    let embeddingModel = try embeddingProvider.embeddingModel("embed-english-v3.0")

    let embedding = try await embeddingModel.embed(EmbeddingRequest(values: ["hello", "world"], dimensions: 512, extraBody: ["inputType": "classification", "truncate": "END"]))

    #expect(embedding.embeddings == [[0.1, 0.2], [0.3, 0.4]])
    #expect(embedding.usage?.totalTokens == 7)
    let embeddingRequest = try #require(await embeddingTransport.requests().first)
    #expect(embeddingRequest.url.absoluteString == "https://api.cohere.com/v2/embed")
    let embeddingBody = try decodeJSONBody(try #require(embeddingRequest.body))
    #expect(embeddingBody["texts"]?[0]?.stringValue == "hello")
    #expect(embeddingBody["embedding_types"]?[0]?.stringValue == "float")
    #expect(embeddingBody["input_type"]?.stringValue == "classification")
    #expect(embeddingBody["output_dimension"]?.intValue == 512)
    #expect(embeddingBody["truncate"]?.stringValue == "END")

    let rerankTransport = RecordingTransport(response: jsonResponse(#"{"id":"rank-1","results":[{"index":1,"relevance_score":0.9},{"index":0,"relevance_score":0.1}]}"#))
    let rerankProvider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: rerankTransport))
    let rerankModel = try rerankProvider.rerankingModel("rerank-v3.5")

    let reranking = try await rerankModel.rerank(RerankingRequest(query: "q", documents: ["a", "b"], topK: 1, extraBody: ["maxTokensPerDoc": 256]))

    #expect(reranking.results.map(\.index) == [1, 0])
    let rerankRequest = try #require(await rerankTransport.requests().first)
    #expect(rerankRequest.url.absoluteString == "https://api.cohere.com/v2/rerank")
    let rerankBody = try decodeJSONBody(try #require(rerankRequest.body))
    #expect(rerankBody["top_n"]?.intValue == 1)
    #expect(rerankBody["max_tokens_per_doc"]?.intValue == 256)
}

@Test func cohereModelsMapNestedProviderOptions() async throws {
    let chatTransport = RecordingTransport(response: jsonResponse(#"{"message":{"role":"assistant","content":[{"type":"text","text":"ok"}]},"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":1,"output_tokens":1}}}"#))
    let chatProvider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: chatTransport))
    let chatModel = try chatProvider.languageModel("command-a-reasoning-08-2025")

    _ = try await chatModel.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: [
            "cohere": [
                "thinking": [
                    "type": "enabled",
                    "tokenBudget": 128
                ]
            ]
        ]
    ))

    let chatRequest = try #require(await chatTransport.requests().first)
    let chatBody = try decodeJSONBody(try #require(chatRequest.body))
    #expect(chatBody["cohere"] == nil)
    #expect(chatBody["thinking"]?["type"]?.stringValue == "enabled")
    #expect(chatBody["thinking"]?["tokenBudget"]?.intValue == 128)

    let embeddingTransport = RecordingTransport(response: jsonResponse(#"{"embeddings":{"float":[[0.1,0.2]]},"meta":{"billed_units":{"input_tokens":3}}}"#))
    let embeddingProvider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: embeddingTransport))
    let embeddingModel = try embeddingProvider.embeddingModel("embed-v4.0")

    _ = try await embeddingModel.embed(EmbeddingRequest(
        values: ["hello"],
        extraBody: [
            "cohere": [
                "inputType": "search_document",
                "outputDimension": 1024,
                "truncate": "START"
            ]
        ]
    ))

    let embeddingRequest = try #require(await embeddingTransport.requests().first)
    let embeddingBody = try decodeJSONBody(try #require(embeddingRequest.body))
    #expect(embeddingBody["cohere"] == nil)
    #expect(embeddingBody["input_type"]?.stringValue == "search_document")
    #expect(embeddingBody["output_dimension"]?.intValue == 1024)
    #expect(embeddingBody["truncate"]?.stringValue == "START")

    let rerankTransport = RecordingTransport(response: jsonResponse(#"{"results":[{"index":0,"relevance_score":0.8}]}"#))
    let rerankProvider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: rerankTransport))
    let rerankModel = try rerankProvider.rerankingModel("rerank-v3.5")

    _ = try await rerankModel.rerank(RerankingRequest(
        query: "q",
        documents: ["a"],
        extraBody: [
            "cohere": [
                "maxTokensPerDoc": 128,
                "priority": 1
            ]
        ]
    ))

    let rerankRequest = try #require(await rerankTransport.requests().first)
    let rerankBody = try decodeJSONBody(try #require(rerankRequest.body))
    #expect(rerankBody["cohere"] == nil)
    #expect(rerankBody["max_tokens_per_doc"]?.intValue == 128)
    #expect(rerankBody["priority"]?.intValue == 1)
}

@Test func voyageEmbeddingAndRerankingUseNativeEndpoints() async throws {
    let embeddingTransport = RecordingTransport(response: jsonResponse("""
    {"model":"voyage-3","data":[{"index":1,"embedding":[0.3,0.4]},{"index":0,"embedding":[0.1,0.2]}],"usage":{"total_tokens":9}}
    """))
    let embeddingProvider = try AIProviders.voyage(settings: ProviderSettings(apiKey: "voyage-key", transport: embeddingTransport))
    let embeddingModel = try embeddingProvider.embeddingModel("voyage-3")

    let embedding = try await embeddingModel.embed(EmbeddingRequest(values: ["a", "b"], dimensions: 256, extraBody: ["inputType": "query", "truncation": true, "outputDtype": "float"]))

    #expect(embedding.embeddings == [[0.1, 0.2], [0.3, 0.4]])
    #expect(embedding.usage?.totalTokens == 9)
    let embeddingRequest = try #require(await embeddingTransport.requests().first)
    #expect(embeddingRequest.url.absoluteString == "https://api.voyageai.com/v1/embeddings")
    #expect(embeddingRequest.headers["Authorization"] == "Bearer voyage-key")
    let embeddingBody = try decodeJSONBody(try #require(embeddingRequest.body))
    #expect(embeddingBody["input"]?[0]?.stringValue == "a")
    #expect(embeddingBody["input_type"]?.stringValue == "query")
    #expect(embeddingBody["truncation"]?.boolValue == true)
    #expect(embeddingBody["output_dimension"]?.intValue == 256)
    #expect(embeddingBody["output_dtype"]?.stringValue == "float")

    let rerankTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"index":0,"relevance_score":0.7},{"index":1,"relevance_score":0.2}]}"#))
    let rerankProvider = try AIProviders.voyage(settings: ProviderSettings(apiKey: "voyage-key", transport: rerankTransport))
    let rerankModel = try rerankProvider.rerankingModel("rerank-2.5")

    let reranking = try await rerankModel.rerank(RerankingRequest(query: "q", documents: ["a", "b"], topK: 2, extraBody: ["returnDocuments": true, "truncation": true]))

    #expect(reranking.results.map(\.score) == [0.7, 0.2])
    let rerankRequest = try #require(await rerankTransport.requests().first)
    #expect(rerankRequest.url.absoluteString == "https://api.voyageai.com/v1/rerank")
    let rerankBody = try decodeJSONBody(try #require(rerankRequest.body))
    #expect(rerankBody["top_k"]?.intValue == 2)
    #expect(rerankBody["return_documents"]?.boolValue == true)
    #expect(rerankBody["returnDocuments"] == nil)
    #expect(rerankBody["truncation"]?.boolValue == true)
}

@Test func voyageModelsMapNestedProviderOptions() async throws {
    let embeddingTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"index":0,"embedding":[0.1,0.2]}],"usage":{"total_tokens":3}}"#))
    let embeddingProvider = try AIProviders.voyage(settings: ProviderSettings(apiKey: "voyage-key", transport: embeddingTransport))
    let embeddingModel = try embeddingProvider.embeddingModel("voyage-4")

    _ = try await embeddingModel.embed(EmbeddingRequest(
        values: ["a"],
        extraBody: [
            "voyage": [
                "inputType": "document",
                "truncation": false,
                "outputDimension": 512,
                "outputDtype": "int8"
            ]
        ]
    ))

    let embeddingRequest = try #require(await embeddingTransport.requests().first)
    let embeddingBody = try decodeJSONBody(try #require(embeddingRequest.body))
    #expect(embeddingBody["voyage"] == nil)
    #expect(embeddingBody["input_type"]?.stringValue == "document")
    #expect(embeddingBody["truncation"]?.boolValue == false)
    #expect(embeddingBody["output_dimension"]?.intValue == 512)
    #expect(embeddingBody["output_dtype"]?.stringValue == "int8")

    let rerankTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"index":0,"relevance_score":0.7}]}"#))
    let rerankProvider = try AIProviders.voyage(settings: ProviderSettings(apiKey: "voyage-key", transport: rerankTransport))
    let rerankModel = try rerankProvider.rerankingModel("rerank-2.5")

    _ = try await rerankModel.rerank(RerankingRequest(
        query: "q",
        documents: ["a"],
        extraBody: [
            "voyage": [
                "returnDocuments": true,
                "truncation": false
            ]
        ]
    ))

    let rerankRequest = try #require(await rerankTransport.requests().first)
    let rerankBody = try decodeJSONBody(try #require(rerankRequest.body))
    #expect(rerankBody["voyage"] == nil)
    #expect(rerankBody["return_documents"]?.boolValue == true)
    #expect(rerankBody["truncation"]?.boolValue == false)
}

@Test func togetherAIImageAndRerankingUseNativeEndpoints() async throws {
    let imageTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"base64-image"}]}"#))
    let imageProvider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("black-forest-labs/FLUX.1-schnell-Free")

    let image = try await imageModel.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "1024x768",
        count: 2,
        files: [ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png")],
        extraBody: [
            "steps": 4,
            "guidance": 3.5,
            "negativePrompt": "low quality",
            "disableSafetyChecker": true
        ]
    ))

    #expect(image.base64Images == ["base64-image"])
    let imageRequest = try #require(await imageTransport.requests().first)
    #expect(imageRequest.url.absoluteString == "https://api.together.xyz/v1/images/generations")
    #expect(imageRequest.headers["Authorization"] == "Bearer together-key")
    let imageBody = try decodeJSONBody(try #require(imageRequest.body))
    #expect(imageBody["model"]?.stringValue == "black-forest-labs/FLUX.1-schnell-Free")
    #expect(imageBody["prompt"]?.stringValue == "cat")
    #expect(imageBody["width"]?.intValue == 1024)
    #expect(imageBody["height"]?.intValue == 768)
    #expect(imageBody["n"]?.intValue == 2)
    #expect(imageBody["response_format"]?.stringValue == "base64")
    #expect(imageBody["steps"]?.intValue == 4)
    #expect(imageBody["guidance"]?.doubleValue == 3.5)
    #expect(imageBody["negative_prompt"]?.stringValue == "low quality")
    #expect(imageBody["disable_safety_checker"]?.boolValue == true)
    #expect(imageBody["image_url"]?.stringValue?.hasPrefix("data:image/png;base64,") == true)

    let rerankTransport = RecordingTransport(response: jsonResponse(#"{"id":"rank-1","model":"Salesforce/Llama-Rank-v1","results":[{"index":1,"relevance_score":0.8},{"index":0,"relevance_score":0.2}]}"#))
    let rerankProvider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: rerankTransport))
    let rerankModel = try rerankProvider.rerankingModel("Salesforce/Llama-Rank-v1")

    let reranking = try await rerankModel.rerank(RerankingRequest(query: "q", documents: ["a", "b"], topK: 1, extraBody: ["rankFields": ["title", "text"]]))

    #expect(reranking.results.map(\.index) == [1, 0])
    let rerankRequest = try #require(await rerankTransport.requests().first)
    #expect(rerankRequest.url.absoluteString == "https://api.together.xyz/v1/rerank")
    let rerankBody = try decodeJSONBody(try #require(rerankRequest.body))
    #expect(rerankBody["top_n"]?.intValue == 1)
    #expect(rerankBody["return_documents"]?.boolValue == false)
    #expect(rerankBody["rank_fields"]?[0]?.stringValue == "title")
}

@Test func togetherAIMapsNestedProviderOptions() async throws {
    let imageTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"nested-image"}]}"#))
    let imageProvider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("black-forest-labs/FLUX.1-schnell-Free")

    _ = try await imageModel.generateImage(ImageGenerationRequest(
        prompt: "cat",
        files: [ImageInputFile(url: "https://example.com/input.png")],
        extraBody: [
            "togetherai": .object([
                "steps": 3,
                "guidance": 2.5,
                "negative_prompt": "blur",
                "disable_safety_checker": true,
                "custom": "value"
            ])
        ]
    ))

    let imageBody = try decodeJSONBody(try #require((await imageTransport.requests()).first?.body))
    #expect(imageBody["steps"]?.intValue == 3)
    #expect(imageBody["guidance"]?.doubleValue == 2.5)
    #expect(imageBody["negative_prompt"]?.stringValue == "blur")
    #expect(imageBody["disable_safety_checker"]?.boolValue == true)
    #expect(imageBody["custom"]?.stringValue == "value")
    #expect(imageBody["image_url"]?.stringValue == "https://example.com/input.png")
    #expect(imageBody["togetherai"] == nil)

    let rerankTransport = RecordingTransport(response: jsonResponse(#"{"results":[{"index":0,"relevance_score":0.9}]}"#))
    let rerankProvider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: rerankTransport))
    let rerankModel = try rerankProvider.rerankingModel("Salesforce/Llama-Rank-v1")

    _ = try await rerankModel.rerank(RerankingRequest(
        query: "q",
        documents: ["a"],
        topK: 1,
        extraBody: ["togetherai": .object(["rankFields": ["title"]])]
    ))

    let rerankBody = try decodeJSONBody(try #require((await rerankTransport.requests()).first?.body))
    #expect(rerankBody["rank_fields"]?[0]?.stringValue == "title")
    #expect(rerankBody["togetherai"] == nil)
}

@Test func xAIImageAndVideoUseNativeEndpoints() async throws {
    let imageTransport = RecordingTransport(responses: [
        jsonResponse(#"{"data":[{"url":"https://x.ai/image.png","revised_prompt":"cat!"}],"usage":{"cost_in_usd_ticks":123}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("xai-png".utf8))
    ])
    let imageProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("grok-2-image")

    let image = try await imageModel.generateImage(ImageGenerationRequest(prompt: "cat", size: "16:9", count: 2, extraBody: ["quality": "high", "output_format": "png"]))

    #expect(image.urls == ["https://x.ai/image.png"])
    #expect(image.base64Images == [Data("xai-png".utf8).base64EncodedString()])
    let imageRequests = await imageTransport.requests()
    #expect(imageRequests.count == 2)
    let imageRequest = try #require(imageRequests.first)
    #expect(imageRequest.url.absoluteString == "https://api.x.ai/v1/images/generations")
    #expect(imageRequest.headers["Authorization"] == "Bearer xai-key")
    let imageBody = try decodeJSONBody(try #require(imageRequest.body))
    #expect(imageBody["model"]?.stringValue == "grok-2-image")
    #expect(imageBody["prompt"]?.stringValue == "cat")
    #expect(imageBody["n"]?.intValue == 2)
    #expect(imageBody["aspect_ratio"]?.stringValue == "16:9")
    #expect(imageBody["response_format"]?.stringValue == "b64_json")
    #expect(imageBody["quality"]?.stringValue == "high")
    #expect(imageBody["output_format"]?.stringValue == "png")
    #expect(imageRequests[1].method == "GET")
    #expect(imageRequests[1].headers["Authorization"] == nil)

    let videoTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"vid-1"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/video.mp4","duration":6,"respect_moderation":true},"progress":100}"#)
    ])
    let videoProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: videoTransport))
    let videoModel = try videoProvider.videoModel("grok-2-video")

    let video = try await videoModel.generateVideo(VideoGenerationRequest(prompt: "cat running", aspectRatio: "16:9", durationSeconds: 6, extraBody: ["resolution": "720p", "pollIntervalMs": 1]))

    #expect(video.urls == ["https://x.ai/video.mp4"])
    #expect(video.operationID == "vid-1")
    let requests = await videoTransport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].url.absoluteString == "https://api.x.ai/v1/videos/generations")
    let videoBody = try decodeJSONBody(try #require(requests[0].body))
    #expect(videoBody["model"]?.stringValue == "grok-2-video")
    #expect(videoBody["prompt"]?.stringValue == "cat running")
    #expect(videoBody["duration"]?.intValue == 6)
    #expect(videoBody["aspect_ratio"]?.stringValue == "16:9")
    #expect(videoBody["resolution"]?.stringValue == "720p")
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api.x.ai/v1/videos/vid-1")

    let editTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"edit-1"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/edit.mp4","respect_moderation":true}}"#)
    ])
    let editProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: editTransport))
    let editModel = try editProvider.videoModel("grok-2-video")

    let edit = try await editModel.generateVideo(VideoGenerationRequest(
        prompt: "make it brighter",
        aspectRatio: "16:9",
        durationSeconds: 6,
        extraBody: ["videoUrl": "https://x.ai/source.mp4", "pollIntervalMs": 1]
    ))

    #expect(edit.urls == ["https://x.ai/edit.mp4"])
    let editRequests = await editTransport.requests()
    #expect(editRequests[0].url.absoluteString == "https://api.x.ai/v1/videos/edits")
    let editBody = try decodeJSONBody(try #require(editRequests[0].body))
    #expect(editBody["video"]?["url"]?.stringValue == "https://x.ai/source.mp4")
    #expect(editBody["aspect_ratio"] == nil)
    #expect(editBody["duration"] == nil)
}

@Test func xAIMapsNestedImageEditAndVideoOptions() async throws {
    let imageTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"edited-image"}]}"#))
    let imageProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("grok-2-image")

    let image = try await imageModel.generateImage(ImageGenerationRequest(
        prompt: "restyle",
        files: [
            ImageInputFile(url: "https://example.com/input.png"),
            ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png")
        ],
        extraBody: [
            "xai": .object([
                "aspect_ratio": "1:1",
                "output_format": "png",
                "sync_mode": true,
                "resolution": "2k",
                "quality": "high",
                "user": "user-1"
            ])
        ]
    ))

    #expect(image.base64Images == ["edited-image"])
    let imageRequest = try #require(await imageTransport.requests().first)
    #expect(imageRequest.url.absoluteString == "https://api.x.ai/v1/images/edits")
    let imageBody = try decodeJSONBody(try #require(imageRequest.body))
    #expect(imageBody["model"]?.stringValue == "grok-2-image")
    #expect(imageBody["aspect_ratio"]?.stringValue == "1:1")
    #expect(imageBody["output_format"]?.stringValue == "png")
    #expect(imageBody["sync_mode"]?.boolValue == true)
    #expect(imageBody["resolution"]?.stringValue == "2k")
    #expect(imageBody["quality"]?.stringValue == "high")
    #expect(imageBody["user"]?.stringValue == "user-1")
    #expect(imageBody["images"]?[0]?["url"]?.stringValue == "https://example.com/input.png")
    #expect(imageBody["images"]?[0]?["type"]?.stringValue == "image_url")
    #expect(imageBody["images"]?[1]?["url"]?.stringValue == "data:image/png;base64,\(Data([1, 2, 3]).base64EncodedString())")
    #expect(imageBody["xai"] == nil)

    let videoTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"r2v-1"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/r2v.mp4","respect_moderation":true}}"#)
    ])
    let videoProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: videoTransport))
    let videoModel = try videoProvider.videoModel("grok-2-video")

    _ = try await videoModel.generateVideo(VideoGenerationRequest(
        prompt: "reference scene",
        aspectRatio: "16:9",
        extraBody: [
            "xai": .object([
                "mode": "reference-to-video",
                "referenceImageUrls": ["https://example.com/ref-1.png", "https://example.com/ref-2.png"],
                "resolution": "720p",
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ]
    ))

    let videoRequests = await videoTransport.requests()
    #expect(videoRequests[0].url.absoluteString == "https://api.x.ai/v1/videos/generations")
    let videoBody = try decodeJSONBody(try #require(videoRequests[0].body))
    #expect(videoBody["reference_images"]?[0]?["url"]?.stringValue == "https://example.com/ref-1.png")
    #expect(videoBody["reference_images"]?[1]?["url"]?.stringValue == "https://example.com/ref-2.png")
    #expect(videoBody["resolution"]?.stringValue == "720p")
    #expect(videoBody["xai"] == nil)
    #expect(videoBody["pollIntervalMs"] == nil)
}

@Test func deepInfraImageUsesInferenceEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"images":["data:image/png;base64,deepinfra-image"]}"#))
    let provider = try AIProviders.deepInfra(settings: ProviderSettings(apiKey: "deepinfra-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/FLUX-1-schnell")

    let result = try await model.generateImage(ImageGenerationRequest(prompt: "cat", size: "1024x768", count: 1, extraBody: ["seed": 42]))

    #expect(result.base64Images == ["deepinfra-image"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepinfra.com/v1/inference/black-forest-labs/FLUX-1-schnell")
    #expect(request.headers["Authorization"] == "Bearer deepinfra-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?.stringValue == "cat")
    #expect(body["num_images"]?.intValue == 1)
    #expect(body["width"]?.stringValue == "1024")
    #expect(body["height"]?.stringValue == "768")
    #expect(body["seed"]?.intValue == 42)
}

@Test func deepInfraImageMapsNestedProviderOptions() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse(#"{"images":["data:image/png;base64,nested-image"]}"#))
    let generateProvider = try AIProviders.deepInfra(settings: ProviderSettings(apiKey: "deepinfra-key", transport: generateTransport))
    let generateModel = try generateProvider.imageModel("black-forest-labs/FLUX-1-schnell")

    _ = try await generateModel.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "16:9",
        count: 1,
        extraBody: [
            "deepinfra": .object([
                "seed": 42,
                "additional_param": "value"
            ])
        ]
    ))

    let generateBody = try decodeJSONBody(try #require((await generateTransport.requests()).first?.body))
    #expect(generateBody["prompt"]?.stringValue == "cat")
    #expect(generateBody["aspect_ratio"]?.stringValue == "16:9")
    #expect(generateBody["seed"]?.intValue == 42)
    #expect(generateBody["additional_param"]?.stringValue == "value")
    #expect(generateBody["deepinfra"] == nil)

    let editTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"edited-image"}]}"#))
    let editProvider = try AIProviders.deepInfra(settings: ProviderSettings(apiKey: "deepinfra-key", transport: editTransport))
    let editModel = try editProvider.imageModel("black-forest-labs/FLUX.1-Kontext-dev")

    _ = try await editModel.generateImage(ImageGenerationRequest(
        prompt: "edit",
        files: [ImageInputFile(data: Data("png".utf8), mediaType: "image/png", fileName: "input.png")],
        extraBody: [
            "deepinfra": .object([
                "guidance_scale": 2.5,
                "tags": ["a", "b"]
            ])
        ]
    ))

    let editRequest = try #require(await editTransport.requests().first)
    let bodyText = String(data: try #require(editRequest.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains(#"name="guidance_scale""#))
    #expect(bodyText.contains("2.5"))
    #expect(bodyText.contains(#"name="tags""#))
    #expect(bodyText.contains("\r\na\r\n"))
    #expect(bodyText.contains("\r\nb\r\n"))
    #expect(!bodyText.contains(#"name="deepinfra""#))
}

@Test func deepInfraImageEditUsesOpenAICompatibleMultipartEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"edited-image"}]}"#))
    let provider = try AIProviders.deepInfra(settings: ProviderSettings(apiKey: "deepinfra-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/FLUX.1-Kontext-dev")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "turn the cat into a dog",
        size: "1024x1024",
        count: 1,
        files: [ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png", fileName: "input.png")],
        mask: ImageInputFile(data: Data([255, 255, 255, 0]), mediaType: "image/png", fileName: "mask.png"),
        extraBody: ["guidance": 7.5]
    ))

    #expect(result.base64Images == ["edited-image"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepinfra.com/v1/openai/images/edits")
    #expect(request.headers["Authorization"] == "Bearer deepinfra-key")
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=ai-sdk-port-") == true)
    let body = try #require(request.body)
    #expect(body.range(of: Data(#"name="model""#.utf8)) != nil)
    #expect(body.range(of: Data("black-forest-labs/FLUX.1-Kontext-dev".utf8)) != nil)
    #expect(body.range(of: Data(#"name="prompt""#.utf8)) != nil)
    #expect(body.range(of: Data("turn the cat into a dog".utf8)) != nil)
    #expect(body.range(of: Data(#"name="image"; filename="input.png""#.utf8)) != nil)
    #expect(body.range(of: Data(#"name="mask"; filename="mask.png""#.utf8)) != nil)
    #expect(body.range(of: Data(#"name="size""#.utf8)) != nil)
    #expect(body.range(of: Data("1024x1024".utf8)) != nil)
    #expect(body.range(of: Data(#"name="guidance""#.utf8)) != nil)
    #expect(body.range(of: Data("7.5".utf8)) != nil)
}

@Test func fireworksLanguageTransformsThinkingOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"fw"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """))
    let provider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: transport))
    let model = try provider.languageModel("accounts/fireworks/models/kimi-k2-thinking")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: [
            "thinking": .object(["type": "enabled", "budgetTokens": 2048]),
            "reasoningHistory": "interleaved",
            "reasoning_effort": "xhigh"
        ]
    ))

    #expect(result.text == "fw")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.fireworks.ai/inference/v1/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer fireworks-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["thinking"]?["type"]?.stringValue == "enabled")
    #expect(body["thinking"]?["budget_tokens"]?.intValue == 2048)
    #expect(body["thinking"]?["budgetTokens"] == nil)
    #expect(body["reasoning_history"]?.stringValue == "interleaved")
    #expect(body["reasoningHistory"] == nil)
    #expect(body["reasoning_effort"]?.stringValue == "high")
}

@Test func fireworksImageUsesWorkflowBinaryEndpoint() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8)))
    let provider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: transport))
    let model = try provider.imageModel("accounts/fireworks/models/flux-1-schnell-fp8")

    let result = try await model.generateImage(ImageGenerationRequest(prompt: "cat", size: "16:9", count: 1, extraBody: ["seed": 42]))

    #expect(result.base64Images == [Data("png".utf8).base64EncodedString()])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.fireworks.ai/inference/v1/workflows/accounts/fireworks/models/flux-1-schnell-fp8/text_to_image")
    #expect(request.headers["Authorization"] == "Bearer fireworks-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?.stringValue == "cat")
    #expect(body["samples"]?.intValue == 1)
    #expect(body["aspect_ratio"]?.stringValue == "16:9")
    #expect(body["seed"]?.intValue == 42)
}

@Test func fireworksAsyncImagePollsAndDownloadsResult() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"fw-1"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://assets.example.com/fireworks.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("async-png".utf8))
    ])
    let provider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: transport))
    let model = try provider.imageModel("accounts/fireworks/models/flux-kontext-pro")

    let result = try await model.generateImage(ImageGenerationRequest(prompt: "cat", size: "1024x768", count: 2))

    #expect(result.urls == ["https://assets.example.com/fireworks.png"])
    #expect(result.base64Images == [Data("async-png".utf8).base64EncodedString()])
    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].url.absoluteString == "https://api.fireworks.ai/inference/v1/workflows/accounts/fireworks/models/flux-kontext-pro")
    let submitBody = try decodeJSONBody(try #require(requests[0].body))
    #expect(submitBody["prompt"]?.stringValue == "cat")
    #expect(submitBody["samples"]?.intValue == 2)
    #expect(submitBody["width"]?.stringValue == "1024")
    #expect(submitBody["height"]?.stringValue == "768")
    #expect(requests[1].url.absoluteString == "https://api.fireworks.ai/inference/v1/workflows/accounts/fireworks/models/flux-kontext-pro/get_result")
    let pollBody = try decodeJSONBody(try #require(requests[1].body))
    #expect(pollBody["id"]?.stringValue == "fw-1")
    #expect(requests[2].method == "GET")
    #expect(requests[2].url.absoluteString == "https://assets.example.com/fireworks.png")
}

@Test func fireworksImageMapsNestedOptionsAndInputImage() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"fw-edit"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://assets.example.com/fireworks-edit.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("edit-png".utf8))
    ])
    let provider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: transport))
    let model = try provider.imageModel("accounts/fireworks/models/flux-kontext-pro")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "restyle",
        files: [ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png")],
        extraBody: [
            "fireworks": .object([
                "seed": 99,
                "strength": 0.7
            ])
        ]
    ))

    let submitBody = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(submitBody["prompt"]?.stringValue == "restyle")
    #expect(submitBody["input_image"]?.stringValue == "data:image/png;base64,\(Data([1, 2, 3]).base64EncodedString())")
    #expect(submitBody["seed"]?.intValue == 99)
    #expect(submitBody["strength"]?.doubleValue == 0.7)
    #expect(submitBody["fireworks"] == nil)
}

@Test func googleVertexOAuthBuildsRegionalPublisherURL() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"vertex"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":2,"candidatesTokenCount":1,"totalTokenCount":3}}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "us-central1",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    let result = try await model.generate(LanguageModelRequest(messages: [.system("Brief"), .user("Hi")], maxOutputTokens: 32))

    #expect(result.text == "vertex")
    #expect(result.usage?.totalTokens == 3)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://us-central1-aiplatform.googleapis.com/v1beta1/projects/test-project/locations/us-central1/publishers/google/models/gemini-2.5-pro:generateContent")
    #expect(request.headers["Authorization"] == "Bearer token")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["systemInstruction"]?["parts"]?[0]?["text"]?.stringValue == "Brief")
    #expect(body["contents"]?[0]?["parts"]?[0]?["text"]?.stringValue == "Hi")
}

@Test func googleVertexLanguageExtractsGroundingSources() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"vertex grounded"}]},"finishReason":"STOP","groundingMetadata":{"groundingChunks":[{"retrievedContext":{"uri":"https://external-rag-source.com/page","title":"External RAG Source"}},{"retrievedContext":{"uri":"gs://bucket/notes.md"}}]}}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Ground it.")]))

    #expect(result.text == "vertex grounded")
    #expect(result.sources.count == 2)
    #expect(result.sources[0].sourceType == "url")
    #expect(result.sources[0].url == "https://external-rag-source.com/page")
    #expect(result.sources[0].title == "External RAG Source")
    #expect(result.sources[1].sourceType == "document")
    #expect(result.sources[1].title == "Unknown Document")
    #expect(result.sources[1].mediaType == "text/markdown")
    #expect(result.sources[1].filename == "notes.md")
}

@Test func googleVertexLanguageMapsFunctionToolsAndToolChoice() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"vertex tools"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Use lookup.")],
        tools: [
            "lookup": [
                "type": "object",
                "properties": ["query": ["type": "string"]],
                "required": ["query"]
            ]
        ],
        extraBody: ["toolChoice": "required"]
    ))

    #expect(result.text == "vertex tools")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["tools"]?[0]?["functionDeclarations"]?[0]?["name"]?.stringValue == "lookup")
    #expect(body["toolConfig"]?["functionCallingConfig"]?["mode"]?.stringValue == "ANY")
    #expect(body["toolChoice"] == nil)
}

@Test func googleVertexToolsHelpersMirrorProviderExecutedToolFactories() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"vertex grounded"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use Vertex tools.")],
        tools: [
            "google.google_search": GoogleVertexTools.googleSearch(),
            "google.vertex_rag_store": GoogleVertexTools.vertexRagStore(
                ragCorpus: "projects/test-project/locations/us-central1/ragCorpora/rag-1",
                topK: 3
            )
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.contains { $0["googleSearch"]?.objectValue?.isEmpty == true })
    let retrieval = try #require(tools.first { $0["retrieval"] != nil })
    #expect(retrieval["retrieval"]?["vertex_rag_store"]?["rag_resources"]?["rag_corpus"]?.stringValue == "projects/test-project/locations/us-central1/ragCorpora/rag-1")
    #expect(retrieval["retrieval"]?["vertex_rag_store"]?["similarity_top_k"]?.intValue == 3)
}

@Test func googleVertexLanguageStreamsGenerateContentEvents() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"candidates":[{"content":{"parts":[{"text":"ver"}],"role":"model"},"index":0}]}

    data: {"candidates":[{"content":{"parts":[{"text":"tex"}],"role":"model"},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":2,"candidatesTokenCount":2,"totalTokenCount":4}}

    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    var deltas: [String] = []
    var usage: TokenUsage?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textDelta(delta):
            deltas.append(delta)
        case let .finish(_, value):
            usage = value
        default:
            break
        }
    }

    #expect(deltas == ["ver", "tex"])
    #expect(usage?.totalTokens == 4)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://aiplatform.googleapis.com/v1beta1/projects/test-project/locations/global/publishers/google/models/gemini-2.5-pro:streamGenerateContent?alt=sse")
    #expect(request.headers["Authorization"] == "Bearer token")
}

@Test func googleVertexLanguageParsesAndStreamsFunctionCalls() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"functionCall":{"name":"weather","args":{"location":"Boston"}}}],"role":"model"},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":20,"candidatesTokenCount":8,"totalTokenCount":28}}
    """))
    let generateProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: generateTransport
    ))
    let generateModel = try generateProvider.languageModel("gemini-2.5-pro")

    let result = try await generateModel.generate(LanguageModelRequest(messages: [.user("Weather?")]))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.toolCalls.first?.name == "weather")
    #expect(try decodeJSONBody(Data((try #require(result.toolCalls.first)).arguments.utf8))["location"]?.stringValue == "Boston")

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"weather","args":{"location":"Boston"}}}]},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":20,"candidatesTokenCount":8,"totalTokenCount":28}}

    """))
    let streamProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: streamTransport
    ))
    let streamModel = try streamProvider.languageModel("gemini-2.5-pro")

    var finalCall: AIToolCall?
    var finishReason: String?
    for try await part in streamModel.stream(LanguageModelRequest(messages: [.user("Weather?")])) {
        switch part {
        case let .toolCall(call):
            finalCall = call
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(finalCall?.name == "weather")
    #expect(try decodeJSONBody(Data((try #require(finalCall)).arguments.utf8))["location"]?.stringValue == "Boston")
    #expect(finishReason == "tool-calls")
}

@Test func googleVertexAPIKeyUsesExpressModeAndPredictEmbedding() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"predictions":[{"embeddings":{"values":[0.4,0.5],"statistics":{"token_count":2}}}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "vertex-key", transport: transport))
    let model = try provider.embeddingModel("text-embedding-005")

    let result = try await model.embed(EmbeddingRequest(values: ["hello"], dimensions: 128))

    #expect(result.embeddings == [[0.4, 0.5]])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://aiplatform.googleapis.com/v1/publishers/google/models/text-embedding-005:predict")
    #expect(request.headers["x-goog-api-key"] == "vertex-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["instances"]?[0]?["content"]?.stringValue == "hello")
    #expect(body["parameters"]?["outputDimensionality"]?.intValue == 128)
}

@Test func googleVertexImageAndVideoUsePredictEndpoints() async throws {
    let imageTransport = RecordingTransport(response: jsonResponse("""
    {"predictions":[{"bytesBase64Encoded":"abc"}]}
    """))
    let imageProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "vertex-key", baseURL: "https://api.example.com", transport: imageTransport))
    let image = try await imageProvider.imageModel("imagen-3.0-generate-002").generateImage(ImageGenerationRequest(prompt: "cat", count: 2))
    #expect(image.base64Images == ["abc"])
    let imageRequest = try #require(await imageTransport.requests().first)
    #expect(imageRequest.url.absoluteString == "https://api.example.com/models/imagen-3.0-generate-002:predict")
    let imageBody = try decodeJSONBody(try #require(imageRequest.body))
    #expect(imageBody["instances"]?[0]?["prompt"]?.stringValue == "cat")
    #expect(imageBody["parameters"]?["sampleCount"]?.intValue == 2)

    let videoTransport = RecordingTransport(response: jsonResponse("""
    {"name":"operations/123"}
    """))
    let videoProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "vertex-key", baseURL: "https://api.example.com", transport: videoTransport))
    let video = try await videoProvider.videoModel("veo-2.0-generate-001").generateVideo(VideoGenerationRequest(prompt: "cat running", aspectRatio: "16:9", durationSeconds: 4))
    #expect(video.operationID == "operations/123")
    let videoRequest = try #require(await videoTransport.requests().first)
    #expect(videoRequest.url.absoluteString == "https://api.example.com/models/veo-2.0-generate-001:predictLongRunning")
    let videoBody = try decodeJSONBody(try #require(videoRequest.body))
    #expect(videoBody["parameters"]?["aspectRatio"]?.stringValue == "16:9")
    #expect(videoBody["parameters"]?["durationSeconds"]?.intValue == 4)
}

@Test func googleVertexImagenEditUsesReferenceImagesAndMaskOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"predictions":[{"bytesBase64Encoded":"edited-image","mimeType":"image/png"}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "vertex-key", baseURL: "https://api.example.com", transport: transport))
    let model = try provider.imageModel("imagen-3.0-generate-002")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "Remove the object",
        count: 1,
        files: [ImageInputFile(data: Data("source".utf8), mediaType: "image/png")],
        mask: ImageInputFile(data: Data("mask".utf8), mediaType: "image/png"),
        extraBody: [
            "googleVertex": [
                "negativePrompt": "blur",
                "edit": [
                    "mode": "EDIT_MODE_INPAINT_REMOVAL",
                    "baseSteps": 50,
                    "maskMode": "MASK_MODE_USER_PROVIDED",
                    "maskDilation": 0.01
                ]
            ]
        ]
    ))

    #expect(result.base64Images == ["edited-image"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.example.com/models/imagen-3.0-generate-002:predict")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["instances"]?[0]?["prompt"]?.stringValue == "Remove the object")
    #expect(body["instances"]?[0]?["referenceImages"]?[0]?["referenceType"]?.stringValue == "REFERENCE_TYPE_RAW")
    #expect(body["instances"]?[0]?["referenceImages"]?[0]?["referenceId"]?.intValue == 1)
    #expect(body["instances"]?[0]?["referenceImages"]?[0]?["referenceImage"]?["bytesBase64Encoded"]?.stringValue == Data("source".utf8).base64EncodedString())
    #expect(body["instances"]?[0]?["referenceImages"]?[1]?["referenceType"]?.stringValue == "REFERENCE_TYPE_MASK")
    #expect(body["instances"]?[0]?["referenceImages"]?[1]?["referenceId"]?.intValue == 2)
    #expect(body["instances"]?[0]?["referenceImages"]?[1]?["referenceImage"]?["bytesBase64Encoded"]?.stringValue == Data("mask".utf8).base64EncodedString())
    #expect(body["instances"]?[0]?["referenceImages"]?[1]?["maskImageConfig"]?["maskMode"]?.stringValue == "MASK_MODE_USER_PROVIDED")
    #expect(body["instances"]?[0]?["referenceImages"]?[1]?["maskImageConfig"]?["dilation"]?.doubleValue == 0.01)
    #expect(body["parameters"]?["sampleCount"]?.intValue == 1)
    #expect(body["parameters"]?["negativePrompt"]?.stringValue == "blur")
    #expect(body["parameters"]?["editMode"]?.stringValue == "EDIT_MODE_INPAINT_REMOVAL")
    #expect(body["parameters"]?["editConfig"]?["baseSteps"]?.intValue == 50)
    #expect(body["parameters"]?["edit"] == nil)
    #expect(body["parameters"]?["googleVertex"] == nil)
}

@Test func googleVertexImagenEditRejectsURLFilesLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"predictions":[]}"#))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "vertex-key", baseURL: "https://api.example.com", transport: transport))
    let model = try provider.imageModel("imagen-3.0-generate-002")

    await #expect(throws: AIError.invalidArgument(argument: "files", message: "URL-based images are not supported for Google Vertex image editing. Provide image data directly.")) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "Edit this image",
            files: [ImageInputFile(url: "https://example.com/source.png")]
        ))
    }
    #expect(await transport.requests().isEmpty)
}

@Test func googleVertexMaaSUsesOpenAICompatibleEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"maas"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}
    """))
    let provider = try AIProviders.googleVertexMaaS(project: "test-project", location: "us-central1", settings: ProviderSettings(apiKey: "vertex-token", transport: transport))
    let model = try provider.languageModel("meta/llama-3.1-405b-instruct-maas")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "maas")
    #expect(result.usage?.totalTokens == 3)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://aiplatform.googleapis.com/v1/projects/test-project/locations/us-central1/endpoints/openapi/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer vertex-token")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "meta/llama-3.1-405b-instruct-maas")
    #expect(body["messages"]?[0]?["content"]?.stringValue == "Hi")
}

@Test func googleVertexXAIStripsReasoningEffort() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"grok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":663,"completion_tokens":50,"completion_tokens_details":{"reasoning_tokens":124}}}
    """))
    let provider = try AIProviders.googleVertexXAI(project: "test-project", settings: ProviderSettings(apiKey: "vertex-token", transport: transport))
    let model = try provider.languageModel("xai/grok-4.1-fast-reasoning")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], extraBody: ["reasoning_effort": "high"]))

    #expect(result.text == "grok")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://aiplatform.googleapis.com/v1/projects/test-project/locations/global/endpoints/openapi/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer vertex-token")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "xai/grok-4.1-fast-reasoning")
    #expect(body["reasoning_effort"] == nil)
}

@Test func googleVertexAnthropicUsesRawPredictShape() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"vertex claude"}],"stop_reason":"end_turn","usage":{"input_tokens":2,"output_tokens":3}}
    """))
    let provider = try AIProviders.googleVertexAnthropic(project: "test-project", location: "us-east5", settings: ProviderSettings(apiKey: "vertex-token", transport: transport))
    let model = try provider.languageModel("claude-3-5-sonnet-v2@20241022")

    let result = try await model.generate(LanguageModelRequest(messages: [.system("Brief"), .user("Hi")], maxOutputTokens: 32))

    #expect(result.text == "vertex claude")
    #expect(result.usage?.inputTokens == 2)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://us-east5-aiplatform.googleapis.com/v1/projects/test-project/locations/us-east5/publishers/anthropic/models/claude-3-5-sonnet-v2@20241022:rawPredict")
    #expect(request.headers["Authorization"] == "Bearer vertex-token")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"] == nil)
    #expect(body["anthropic_version"]?.stringValue == "vertex-2023-10-16")
    #expect(body["system"]?.stringValue == "Brief")
    #expect(body["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
}

@Test func replicateImageUsesModelPredictionEndpoint() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-1","status":"succeeded","output":["https://replicate.example.com/image.png"]}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("replicate-png".utf8))
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/flux-schnell")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        count: 2,
        extraBody: [
            "aspectRatio": .string("3:4"),
            "guidance_scale": .number(7.5),
            "maxWaitTimeInSeconds": .number(30)
        ]
    ))

    #expect(result.urls == ["https://replicate.example.com/image.png"])
    #expect(result.base64Images == [Data("replicate-png".utf8).base64EncodedString()])
    let requests = await transport.requests()
    #expect(requests.count == 2)
    let request = try #require(requests.first)
    #expect(request.url.absoluteString == "https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions")
    #expect(request.headers["Authorization"] == "Bearer replicate-key")
    #expect(request.headers["prefer"] == "wait=30")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["input"]?["prompt"]?.stringValue == "cat")
    #expect(body["input"]?["num_outputs"]?.intValue == 2)
    #expect(body["input"]?["aspect_ratio"]?.stringValue == "3:4")
    #expect(body["input"]?["guidance_scale"]?.doubleValue == 7.5)
    #expect(body["input"]?["maxWaitTimeInSeconds"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://replicate.example.com/image.png")
}

@Test func replicateImageMapsEditingInputsAndNestedOptions() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-1","status":"succeeded","output":"https://replicate.example.com/edited.webp"}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/webp"], body: Data("edited-webp".utf8))
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.imageModel("owner/inpaint-model")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Replace the masked area",
        count: 1,
        files: [ImageInputFile(url: "https://example.com/input.jpg")],
        mask: ImageInputFile(data: Data([0x89, 0x50, 0x4E, 0x47]), mediaType: "image/png"),
        extraBody: [
            "replicate": .object([
                "guidance_scale": .number(7.5),
                "num_inference_steps": .number(30),
                "negative_prompt": .string("blur"),
                "maxWaitTimeInSeconds": .number(45)
            ])
        ]
    ))

    let requests = await transport.requests()
    let request = try #require(requests.first)
    #expect(request.headers["prefer"] == "wait=45")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["input"]?["prompt"]?.stringValue == "Replace the masked area")
    #expect(body["input"]?["image"]?.stringValue == "https://example.com/input.jpg")
    #expect(body["input"]?["mask"]?.stringValue == "data:image/png;base64,\(Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString())")
    #expect(body["input"]?["guidance_scale"]?.doubleValue == 7.5)
    #expect(body["input"]?["num_inference_steps"]?.intValue == 30)
    #expect(body["input"]?["negative_prompt"]?.stringValue == "blur")
    #expect(body["input"]?["maxWaitTimeInSeconds"] == nil)
    #expect(body["input"]?["replicate"] == nil)
}

@Test func replicateFlux2ImageMapsMultipleInputImages() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-1","status":"succeeded","output":["https://replicate.example.com/flux.webp"]}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/webp"], body: Data("flux-webp".utf8))
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/flux-2-pro")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Use reference images",
        files: [
            ImageInputFile(url: "https://example.com/reference-1.jpg"),
            ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png"),
            ImageInputFile(url: "https://example.com/reference-3.jpg")
        ],
        mask: ImageInputFile(url: "https://example.com/mask.png")
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["input"]?["input_image"]?.stringValue == "https://example.com/reference-1.jpg")
    #expect(body["input"]?["input_image_2"]?.stringValue == "data:image/png;base64,\(Data([1, 2, 3]).base64EncodedString())")
    #expect(body["input"]?["input_image_3"]?.stringValue == "https://example.com/reference-3.jpg")
    #expect(body["input"]?["mask"] == nil)
    #expect(body["input"]?["image"] == nil)
}

@Test func replicateVideoUsesPredictionEndpointAndReturnsOutputURL() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-video","status":"starting","output":null,"urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"}}
        """),
        jsonResponse("""
        {"id":"pred-video","status":"succeeded","output":"https://replicate.example.com/video.mp4","urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"}}
        """)
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.videoModel("owner/video-model")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        aspectRatio: "16:9",
        durationSeconds: 4,
        extraBody: [
            "guidance_scale": .number(7.5),
            "maxWaitTimeInSeconds": .number(30),
            "pollIntervalMs": .number(1),
            "pollTimeoutMs": .number(1_000)
        ]
    ))

    #expect(result.urls == ["https://replicate.example.com/video.mp4"])
    #expect(result.operationID == "pred-video")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    let request = try #require(requests.first)
    #expect(request.url.absoluteString == "https://api.replicate.com/v1/models/owner/video-model/predictions")
    #expect(request.headers["prefer"] == "wait=30")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["input"]?["prompt"]?.stringValue == "cat running")
    #expect(body["input"]?["aspect_ratio"]?.stringValue == "16:9")
    #expect(body["input"]?["duration"]?.intValue == 4)
    #expect(body["input"]?["guidance_scale"]?.doubleValue == 7.5)
    #expect(body["input"]?["maxWaitTimeInSeconds"] == nil)
    #expect(body["input"]?["pollIntervalMs"] == nil)
    #expect(body["input"]?["pollTimeoutMs"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api.replicate.com/v1/predictions/pred-video")
}

@Test func replicateVideoMapsNestedOptionsAndImageInput() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"pred-video","status":"succeeded","output":"https://replicate.example.com/video.mp4","urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"},"metrics":{"predict_time":25.5}}
    """))
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.videoModel("stability-ai/stable-video-diffusion:abc123")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "Animate the image",
        aspectRatio: "9:16",
        durationSeconds: 5,
        extraBody: [
            "replicate": .object([
                "resolution": .string("1920x1080"),
                "fps": .number(24),
                "seed": .number(42),
                "image": .object([
                    "data": .string("base64-image-data"),
                    "mediaType": .string("image/png")
                ]),
                "guidance_scale": .number(8),
                "motion_bucket_id": .number(127),
                "prompt_optimizer": .bool(true),
                "pollIntervalMs": .number(1),
                "pollTimeoutMs": .number(1_000),
                "maxWaitTimeInSeconds": .number(30)
            ])
        ]
    ))

    #expect(result.urls == ["https://replicate.example.com/video.mp4"])
    #expect(result.operationID == "pred-video")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.replicate.com/v1/predictions")
    #expect(request.headers["prefer"] == "wait=30")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["version"]?.stringValue == "abc123")
    #expect(body["input"]?["prompt"]?.stringValue == "Animate the image")
    #expect(body["input"]?["aspect_ratio"]?.stringValue == "9:16")
    #expect(body["input"]?["duration"]?.intValue == 5)
    #expect(body["input"]?["size"]?.stringValue == "1920x1080")
    #expect(body["input"]?["fps"]?.intValue == 24)
    #expect(body["input"]?["seed"]?.intValue == 42)
    #expect(body["input"]?["image"]?.stringValue == "data:image/png;base64,base64-image-data")
    #expect(body["input"]?["guidance_scale"]?.intValue == 8)
    #expect(body["input"]?["motion_bucket_id"]?.intValue == 127)
    #expect(body["input"]?["prompt_optimizer"]?.boolValue == true)
    #expect(body["input"]?["resolution"] == nil)
    #expect(body["input"]?["pollIntervalMs"] == nil)
    #expect(body["input"]?["pollTimeoutMs"] == nil)
    #expect(body["input"]?["maxWaitTimeInSeconds"] == nil)
    #expect(body["input"]?["replicate"] == nil)
}

@Test func falImageUsesRunEndpoint() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"image":{"url":"https://fal.example.com/image.png","content_type":"image/png"}}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("fal-png".utf8))
    ])
    let provider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transport))
    let model = try provider.imageModel("fal-ai/flux/schnell")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        extraBody: [
            "aspectRatio": .string("16:9"),
            "guidanceScale": .number(3.5),
            "numInferenceSteps": .number(24),
            "outputFormat": .string("png"),
            "syncMode": .bool(true),
            "useMultipleImages": .bool(true)
        ]
    ))

    #expect(result.urls == ["https://fal.example.com/image.png"])
    #expect(result.base64Images == [Data("fal-png".utf8).base64EncodedString()])
    let requests = await transport.requests()
    #expect(requests.count == 2)
    let request = try #require(requests.first)
    #expect(request.url.absoluteString == "https://fal.run/fal-ai/flux/schnell")
    #expect(request.headers["Authorization"] == "Key fal-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?.stringValue == "cat")
    #expect(body["image_size"]?.stringValue == "landscape_16_9")
    #expect(body["guidance_scale"]?.doubleValue == 3.5)
    #expect(body["num_inference_steps"]?.intValue == 24)
    #expect(body["output_format"]?.stringValue == "png")
    #expect(body["sync_mode"]?.boolValue == true)
    #expect(body["aspectRatio"] == nil)
    #expect(body["useMultipleImages"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://fal.example.com/image.png")
    #expect(requests[1].headers["Authorization"] == nil)
}

@Test func falImageMapsFilesMaskAndNestedOptions() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"images":[{"url":"https://fal.example.com/edited.png","content_type":"image/png"}]}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("fal-edited".utf8))
    ])
    let provider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transport))
    let model = try provider.imageModel("fal-ai/flux-2/edit")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Blend references",
        files: [
            ImageInputFile(url: "https://example.com/reference-1.png"),
            ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png")
        ],
        mask: ImageInputFile(data: Data([9, 8, 7]), mediaType: "image/png"),
        extraBody: [
            "fal": .object([
                "useMultipleImages": .bool(true),
                "guidanceScale": .number(7.5),
                "numInferenceSteps": .number(30),
                "enableSafetyChecker": .bool(false),
                "outputFormat": .string("png"),
                "syncMode": .bool(true),
                "safetyTolerance": .number(5)
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?.stringValue == "Blend references")
    #expect(body["image_urls"]?[0]?.stringValue == "https://example.com/reference-1.png")
    #expect(body["image_urls"]?[1]?.stringValue == "data:image/png;base64,\(Data([1, 2, 3]).base64EncodedString())")
    #expect(body["mask_url"]?.stringValue == "data:image/png;base64,\(Data([9, 8, 7]).base64EncodedString())")
    #expect(body["guidance_scale"]?.doubleValue == 7.5)
    #expect(body["num_inference_steps"]?.intValue == 30)
    #expect(body["enable_safety_checker"]?.boolValue == false)
    #expect(body["output_format"]?.stringValue == "png")
    #expect(body["sync_mode"]?.boolValue == true)
    #expect(body["safety_tolerance"]?.intValue == 5)
    #expect(body["useMultipleImages"] == nil)
    #expect(body["fal"] == nil)
}

@Test func falVideoUsesQueueAndResponseURL() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"req-1","response_url":"https://queue.fal.run/fal-ai/kling-video/requests/req-1"}"#),
        AIHTTPResponse(statusCode: 422, headers: ["content-type": "application/json"], body: Data(#"{"detail":"Request is still in progress"}"#.utf8)),
        jsonResponse(#"{"video":{"url":"https://fal.example.com/video.mp4","content_type":"video/mp4"},"seed":123}"#)
    ])
    let provider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transport))
    let model = try provider.videoModel("fal-ai/kling-video/v1/standard/text-to-video")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        aspectRatio: "16:9",
        durationSeconds: 4,
        extraBody: [
            "motionStrength": .number(0.5),
            "negativePrompt": .string("rain"),
            "promptOptimizer": .bool(true),
            "pollIntervalMs": .number(1),
            "pollTimeoutMs": .number(1_000)
        ]
    ))

    #expect(result.urls == ["https://fal.example.com/video.mp4"])
    #expect(result.operationID == "req-1")
    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].url.absoluteString == "https://queue.fal.run/fal-ai/kling-video/v1/standard/text-to-video")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["prompt"]?.stringValue == "cat running")
    #expect(body["aspect_ratio"]?.stringValue == "16:9")
    #expect(body["duration"]?.stringValue == "4s")
    #expect(body["motion_strength"]?.doubleValue == 0.5)
    #expect(body["negative_prompt"]?.stringValue == "rain")
    #expect(body["prompt_optimizer"]?.boolValue == true)
    #expect(body["pollIntervalMs"] == nil)
    #expect(body["pollTimeoutMs"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://queue.fal.run/fal-ai/kling-video/requests/req-1")
    #expect(requests[2].method == "GET")
    #expect(requests[2].url.absoluteString == "https://queue.fal.run/fal-ai/kling-video/requests/req-1")
}

@Test func falVideoMapsNestedOptionsAndImageInput() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"req-1","response_url":"https://queue.fal.run/fal-ai/luma-dream-machine/requests/req-1"}"#),
        jsonResponse(#"{"video":{"url":"https://fal.example.com/video.mp4","content_type":"video/mp4","width":1280,"height":720},"seed":42}"#)
    ])
    let provider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transport))
    let model = try provider.videoModel("fal-ai/luma-dream-machine")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "Animate this",
        aspectRatio: "16:9",
        durationSeconds: 5,
        extraBody: [
            "fal": .object([
                "image": .object([
                    "data": .string("base64-image"),
                    "mediaType": .string("image/png")
                ]),
                "loop": .bool(true),
                "motionStrength": .number(0.6),
                "resolution": .string("720p"),
                "negativePrompt": .string("rain"),
                "promptOptimizer": .bool(true),
                "pollIntervalMs": .number(1),
                "pollTimeoutMs": .number(1_000)
            ])
        ]
    ))

    #expect(result.urls == ["https://fal.example.com/video.mp4"])
    #expect(result.operationID == "req-1")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["prompt"]?.stringValue == "Animate this")
    #expect(body["aspect_ratio"]?.stringValue == "16:9")
    #expect(body["duration"]?.stringValue == "5s")
    #expect(body["image_url"]?.stringValue == "data:image/png;base64,base64-image")
    #expect(body["loop"]?.boolValue == true)
    #expect(body["motion_strength"]?.doubleValue == 0.6)
    #expect(body["resolution"]?.stringValue == "720p")
    #expect(body["negative_prompt"]?.stringValue == "rain")
    #expect(body["prompt_optimizer"]?.boolValue == true)
    #expect(body["pollIntervalMs"] == nil)
    #expect(body["pollTimeoutMs"] == nil)
    #expect(body["fal"] == nil)
}

@Test func falSpeechAndTranscriptionUseNativeFalEndpoints() async throws {
    let speechTransport = RecordingTransport(responses: [
        jsonResponse(#"{"audio":{"url":"https://fal.example.com/audio.mp3"},"duration_ms":1000,"request_id":"speech-1"}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("fal-audio".utf8))
    ])
    let speechProvider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: speechTransport))
    let speechModel = try speechProvider.speechModel("fal-ai/minimax/speech-02-hd")

    let speech = try await speechModel.speak(SpeechRequest(text: "hello", voice: "voice-id", format: "url", extraBody: ["language_boost": "English"]))

    #expect(speech.audio == Data("fal-audio".utf8))
    let speechRequests = await speechTransport.requests()
    #expect(speechRequests.count == 2)
    #expect(speechRequests[0].url.absoluteString == "https://fal.run/fal-ai/minimax/speech-02-hd")
    #expect(speechRequests[0].headers["Authorization"] == "Key fal-key")
    let speechBody = try decodeJSONBody(try #require(speechRequests[0].body))
    #expect(speechBody["text"]?.stringValue == "hello")
    #expect(speechBody["voice"]?.stringValue == "voice-id")
    #expect(speechBody["output_format"]?.stringValue == "url")
    #expect(speechBody["language_boost"]?.stringValue == "English")
    #expect(speechRequests[1].method == "GET")
    #expect(speechRequests[1].url.absoluteString == "https://fal.example.com/audio.mp3")
    #expect(speechRequests[1].headers["Authorization"] == nil)

    let transcriptionTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"transcription-1"}"#),
        jsonResponse(#"{"text":"fal transcript","chunks":[{"text":"fal","timestamp":[0,0.4]}],"inferred_languages":["en"]}"#)
    ])
    let transcriptionProvider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transcriptionTransport))
    let transcriptionModel = try transcriptionProvider.transcriptionModel("whisper")

    let transcription = try await transcriptionModel.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), mimeType: "audio/wav", language: "en", extraBody: ["chunkLevel": "segment", "batchSize": 32]))

    #expect(transcription.text == "fal transcript")
    let transcriptionRequests = await transcriptionTransport.requests()
    #expect(transcriptionRequests.count == 2)
    #expect(transcriptionRequests[0].url.absoluteString == "https://queue.fal.run/fal-ai/whisper")
    let transcriptionBody = try decodeJSONBody(try #require(transcriptionRequests[0].body))
    #expect(transcriptionBody["task"]?.stringValue == "transcribe")
    #expect(transcriptionBody["language"]?.stringValue == "en")
    #expect(transcriptionBody["diarize"]?.boolValue == true)
    #expect(transcriptionBody["chunk_level"]?.stringValue == "segment")
    #expect(transcriptionBody["batch_size"]?.intValue == 32)
    #expect(transcriptionBody["audio_url"]?.stringValue?.hasPrefix("data:audio/wav;base64,") == true)
    #expect(transcriptionRequests[1].method == "GET")
    #expect(transcriptionRequests[1].url.absoluteString == "https://queue.fal.run/fal-ai/whisper/requests/transcription-1")
}

@Test func falAudioModelsMapNestedProviderOptions() async throws {
    let speechTransport = RecordingTransport(responses: [
        jsonResponse(#"{"audio":{"url":"https://fal.example.com/audio.mp3"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("fal-audio".utf8))
    ])
    let speechProvider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: speechTransport))
    let speechModel = try speechProvider.speechModel("fal-ai/minimax/speech-02-hd")

    _ = try await speechModel.speak(SpeechRequest(
        text: "hello",
        voice: "voice-id",
        format: "url",
        extraBody: [
            "fal": .object([
                "voice_setting": .object([
                    "speed": .number(1.1),
                    "vol": .number(0.8),
                    "voice_id": .string("override-voice")
                ]),
                "language_boost": .string("English")
            ])
        ]
    ))

    let speechBody = try decodeJSONBody(try #require((await speechTransport.requests()).first?.body))
    #expect(speechBody["text"]?.stringValue == "hello")
    #expect(speechBody["voice"]?.stringValue == "voice-id")
    #expect(speechBody["output_format"]?.stringValue == "url")
    #expect(speechBody["voice_setting"]?["speed"]?.doubleValue == 1.1)
    #expect(speechBody["voice_setting"]?["vol"]?.doubleValue == 0.8)
    #expect(speechBody["voice_setting"]?["voice_id"]?.stringValue == "override-voice")
    #expect(speechBody["language_boost"]?.stringValue == "English")
    #expect(speechBody["fal"] == nil)

    let transcriptionTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"transcription-1"}"#),
        jsonResponse(#"{"text":"fal transcript","chunks":[]}"#)
    ])
    let transcriptionProvider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transcriptionTransport))
    let transcriptionModel = try transcriptionProvider.transcriptionModel("whisper")

    _ = try await transcriptionModel.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        mimeType: "audio/wav",
        extraBody: [
            "fal": .object([
                "language": .string("en"),
                "diarize": .bool(false),
                "chunkLevel": .string("segment"),
                "batchSize": .number(32),
                "numSpeakers": .number(2)
            ])
        ]
    ))

    let transcriptionBody = try decodeJSONBody(try #require((await transcriptionTransport.requests()).first?.body))
    #expect(transcriptionBody["language"]?.stringValue == "en")
    #expect(transcriptionBody["diarize"]?.boolValue == false)
    #expect(transcriptionBody["chunk_level"]?.stringValue == "segment")
    #expect(transcriptionBody["batch_size"]?.intValue == 32)
    #expect(transcriptionBody["num_speakers"]?.intValue == 2)
    #expect(transcriptionBody["fal"] == nil)
    #expect(transcriptionBody["chunkLevel"] == nil)
    #expect(transcriptionBody["batchSize"] == nil)
    #expect(transcriptionBody["numSpeakers"] == nil)
}

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
    #expect(request.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=ai-sdk-port-") == true)
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

    let responsesResult = try await provider.responses("responses-deployment").generate(LanguageModelRequest(messages: [.user("Hi")]))
    let chatResult = try await provider.chat("chat-deployment").generate(LanguageModelRequest(messages: [.user("Hi")]))
    let completionResult = try await provider.completion("completion-deployment").generate(LanguageModelRequest(messages: [.user("Finish")]))

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

@Test func providerRegistryConstructsDiscoveredProvidersWithExplicitKeys() throws {
    let transport = RecordingTransport(response: jsonResponse("{}"))
    let settings = ProviderSettings(apiKey: "key", transport: transport)

    _ = try AIProviders.anthropicAWS(settings: AnthropicAWSProviderSettings(region: "us-east-1", workspaceID: "workspace", apiKey: "key", transport: transport))
    _ = try AIProviders.googleVertexMaaS(project: "project", settings: settings)
    _ = try AIProviders.googleVertexXAI(project: "project", settings: settings)
    _ = try AIProviders.googleVertexAnthropic(project: "project", settings: settings)
    _ = try AIProviders.mistral(settings: settings)
    _ = try AIProviders.xAI(settings: settings)
    _ = try AIProviders.deepSeek(settings: settings)
    _ = try AIProviders.togetherAI(settings: settings)
    _ = try AIProviders.cohere(settings: settings)
    _ = try AIProviders.groq(settings: settings)
    _ = try AIProviders.perplexity(settings: settings)
    _ = try AIProviders.fireworks(settings: settings)
    _ = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(region: "us-east-1", accessKeyID: "access", secretAccessKey: "secret", transport: transport))
    _ = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "vertex-key", transport: transport))
    _ = try AIProviders.deepInfra(settings: settings)
    _ = try AIProviders.baseten(settings: settings)
    _ = try AIProviders.cerebras(settings: settings)
    _ = try AIProviders.vercel(settings: settings)
    _ = try AIProviders.alibaba(settings: settings)
    _ = try AIProviders.moonshotAI(settings: settings)
    _ = try AIProviders.huggingFace(settings: settings)
    _ = try AIProviders.replicate(settings: settings)
    _ = try AIProviders.fal(settings: settings)
    _ = try AIProviders.deepgram(settings: settings)
    _ = try AIProviders.assemblyAI(settings: settings)
    _ = try AIProviders.elevenLabs(settings: settings)
    _ = try AIProviders.revAI(settings: settings)
    _ = try AIProviders.gladia(settings: settings)
    _ = try AIProviders.hume(settings: settings)
    _ = try AIProviders.lmnt(settings: settings)
    _ = try AIProviders.blackForestLabs(settings: settings)
    _ = try AIProviders.prodia(settings: settings)
    _ = try AIProviders.luma(settings: settings)
    _ = try AIProviders.klingAI(settings: settings)
    _ = try AIProviders.byteDance(settings: settings)
    _ = try AIProviders.voyage(settings: settings)
    _ = try AIProviders.quiverAI(settings: settings)
    _ = try AIProviders.azure(resourceName: "resource", settings: settings)
    _ = try AIProviders.gateway(settings: settings)
    _ = try AIProviders.openResponses(name: "open-responses", url: "https://example.com/responses", settings: settings)
}

@Test func providerFactoryAliasesMirrorUpstreamNames() throws {
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: RecordingTransport(response: jsonResponse("{}"))))

    let language = try provider("openai/gpt-4.1-mini")
    let chat = try provider.chat("openai/gpt-4.1-mini")
    let embedding = try provider.embedding("openai/text-embedding-3-small")
    let textEmbeddingModel = try provider.textEmbeddingModel("openai/text-embedding-3-small")
    let textEmbedding = try provider.textEmbedding("openai/text-embedding-3-small")
    let image = try provider.image("openai/gpt-image-1")
    let transcription = try provider.transcription("openai/gpt-4o-transcribe")
    let speech = try provider.speech("openai/gpt-4o-mini-tts")
    let video = try provider.video("fal/minimax/hailuo-02/standard/text-to-video")
    let reranking = try provider.reranking("cohere/rerank-v3.5")

    #expect(language.providerID == "gateway")
    #expect(language.modelID == "openai/gpt-4.1-mini")
    #expect(chat.providerID == "gateway")
    #expect(embedding.providerID == "gateway")
    #expect(textEmbeddingModel.providerID == "gateway")
    #expect(textEmbedding.providerID == "gateway")
    #expect(image.providerID == "gateway")
    #expect(transcription.providerID == "gateway")
    #expect(speech.providerID == "gateway")
    #expect(video.providerID == "gateway")
    #expect(reranking.providerID == "gateway")
}

@Test func vercelLanguageUsesV0EndpointAndChatProviderID() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"v0 response"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let provider = try AIProviders.vercel(settings: ProviderSettings(apiKey: "vercel-key", transport: transport))
    let model = try provider.languageModel("v0-1.5-md")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Build UI")]))

    #expect(provider.providerID == "vercel")
    #expect(model.providerID == "vercel.chat")
    #expect(result.text == "v0 response")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.v0.dev/v1/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer vercel-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "v0-1.5-md")
    #expect(body["messages"]?[0]?["content"]?.stringValue == "Build UI")
}

@Test func vercelProviderRejectsUnsupportedModelFamiliesWithVercelID() throws {
    let provider = try AIProviders.vercel(settings: ProviderSettings(apiKey: "vercel-key", transport: RecordingTransport(response: jsonResponse("{}"))))

    #expect(throws: AIError.unsupportedModel(provider: "vercel", capability: .embedding, modelID: "embed")) {
        _ = try provider.embeddingModel("embed")
    }
}

@Test func amazonBedrockConverseUsesSigV4AndConverseShape() async throws {
    let fixedDate = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2024,
        month: 3,
        day: 15,
        hour: 0,
        minute: 0,
        second: 0
    ).date!
    let transport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[{"text":"bedrock"}]}},"stopReason":"end_turn","usage":{"inputTokens":2,"outputTokens":1,"totalTokens":3}}
    """))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        accessKeyID: "AKIDEXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
        headers: ["custom-header": "value"],
        transport: transport,
        date: { fixedDate }
    ))
    let model = try provider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")

    let result = try await model.generate(LanguageModelRequest(messages: [.system("Brief."), .user("Hi")], temperature: 1.4, maxOutputTokens: 12))

    #expect(result.text == "bedrock")
    #expect(result.usage?.totalTokens == 3)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://bedrock-runtime.us-east-1.amazonaws.com/model/anthropic.claude-3-haiku-20240307-v1%3A0/converse")
    #expect(request.headers["x-amz-date"] == "20240315T000000Z")
    #expect(request.headers["x-amz-content-sha256"] != nil)
    #expect(request.headers["authorization"]?.contains("Credential=AKIDEXAMPLE/20240315/us-east-1/bedrock/aws4_request") == true)
    #expect(request.headers["authorization"]?.contains("SignedHeaders=") == true)
    #expect(request.headers["custom-header"] == "value")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["system"]?[0]?["text"]?.stringValue == "Brief.")
    #expect(body["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
    #expect(body["inferenceConfig"]?["temperature"]?.doubleValue == 1)
}

@Test func amazonBedrockConverseMapsDocumentDataAndProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[{"text":"ok"}]}},"stopReason":"end_turn","usage":{"inputTokens":2,"outputTokens":1,"totalTokens":3}}
    """))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        accessKeyID: "AKIDEXAMPLE",
        secretAccessKey: "secret",
        transport: transport
    ))
    let model = try provider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .user, content: [
                .text("Use these inputs."),
                .data(mimeType: "application/pdf", data: Data("pdf bytes".utf8)),
                .data(mimeType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47]))
            ])
        ],
        extraBody: [
            "amazonBedrock": .object([
                "citations": .object(["enabled": .bool(true)]),
                "guardrailConfig": .object([
                    "guardrailIdentifier": .string("gr-1"),
                    "guardrailVersion": .string("1")
                ]),
                "serviceTier": .string("priority"),
                "additionalModelRequestFields": .object(["trace": .string("enabled")])
            ]),
            "bedrock": .object([
                "serviceTier": .string("legacy")
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content[0]["text"]?.stringValue == "Use these inputs.")
    #expect(content[1]["document"]?["format"]?.stringValue == "pdf")
    #expect(content[1]["document"]?["name"]?.stringValue == "document-1")
    #expect(content[1]["document"]?["source"]?["bytes"]?.stringValue == Data("pdf bytes".utf8).base64EncodedString())
    #expect(content[1]["document"]?["citations"]?["enabled"]?.boolValue == true)
    #expect(content[2]["image"]?["format"]?.stringValue == "png")
    #expect(content[2]["image"]?["source"]?["bytes"]?.stringValue == Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString())
    #expect(body["guardrailConfig"]?["guardrailIdentifier"]?.stringValue == "gr-1")
    #expect(body["serviceTier"]?["type"]?.stringValue == "priority")
    #expect(body["additionalModelRequestFields"]?["trace"]?.stringValue == "enabled")
    #expect(body["amazonBedrock"] == nil)
    #expect(body["bedrock"] == nil)
}

@Test func amazonBedrockConverseParsesToolUseBlocks() async throws {
    let fixedDate = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2024,
        month: 3,
        day: 15,
        hour: 0,
        minute: 0,
        second: 0
    ).date!
    let transport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[{"toolUse":{"toolUseId":"tool-use-id","name":"test-tool","input":{"value":"Sparkle Day"}}}]}},"stopReason":"tool_use","usage":{"inputTokens":2,"outputTokens":1,"totalTokens":3}}
    """))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        accessKeyID: "AKIDEXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
        transport: transport,
        date: { fixedDate }
    ))
    let model = try provider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Use a tool.")]))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.usage?.totalTokens == 3)
    #expect(result.toolCalls.count == 1)
    #expect(result.toolCalls[0].id == "tool-use-id")
    #expect(result.toolCalls[0].name == "test-tool")
    #expect(try decodeJSONBody(Data(result.toolCalls[0].arguments.utf8))["value"]?.stringValue == "Sparkle Day")
}

@Test func amazonBedrockConverseParsesReasoningAndProviderMetadata() async throws {
    let fixedDate = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2024,
        month: 3,
        day: 15,
        hour: 0,
        minute: 0,
        second: 0
    ).date!
    let transport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[{"reasoningContent":{"reasoningText":{"text":"Think it through.","signature":"sig-1"}}},{"text":"answer"}]}},"stopReason":"end_turn","usage":{"inputTokens":2,"outputTokens":1,"totalTokens":3,"cacheWriteInputTokens":4,"cacheDetails":{"cache":"warm"}},"trace":{"guardrail":{"action":"NONE"}},"performanceConfig":{"latency":"optimized"},"serviceTier":"priority","additionalModelResponseFields":{"delta":{"stop_sequence":"END"}}}
    """))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        accessKeyID: "AKIDEXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
        transport: transport,
        date: { fixedDate }
    ))
    let model = try provider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Think.")]))

    #expect(result.text == "answer")
    #expect(result.reasoning == "Think it through.")
    #expect(result.providerMetadata["amazonBedrock"]?["trace"]?["guardrail"]?["action"]?.stringValue == "NONE")
    #expect(result.providerMetadata["amazonBedrock"]?["performanceConfig"]?["latency"]?.stringValue == "optimized")
    #expect(result.providerMetadata["amazonBedrock"]?["serviceTier"]?.stringValue == "priority")
    #expect(result.providerMetadata["amazonBedrock"]?["usage"]?["cacheWriteInputTokens"]?.intValue == 4)
    #expect(result.providerMetadata["amazonBedrock"]?["usage"]?["cacheDetails"]?["cache"]?.stringValue == "warm")
    #expect(result.providerMetadata["amazonBedrock"]?["stopSequence"]?.stringValue == "END")
    #expect(result.providerMetadata["bedrock"] == result.providerMetadata["amazonBedrock"])
}

@Test func amazonBedrockLanguageStreamsConverseEvents() async throws {
    let fixedDate = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2024,
        month: 3,
        day: 15,
        hour: 0,
        minute: 0,
        second: 0
    ).date!
    let transport = RecordingTransport(response: amazonEventStreamResponse([
        ("contentBlockDelta", #"{"contentBlockIndex":0,"delta":{"text":"bed"}}"#),
        ("contentBlockDelta", #"{"contentBlockIndex":0,"delta":{"text":"rock"}}"#),
        ("messageStop", #"{"stopReason":"end_turn"}"#),
        ("metadata", #"{"usage":{"inputTokens":2,"outputTokens":2,"totalTokens":4}}"#)
    ]))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        accessKeyID: "AKIDEXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
        transport: transport,
        date: { fixedDate }
    ))
    let model = try provider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")

    var deltas: [String] = []
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textDelta(delta):
            deltas.append(delta)
        case let .finish(_, usage):
            totalTokens = usage?.totalTokens ?? totalTokens
        default:
            break
        }
    }

    #expect(deltas == ["bed", "rock"])
    #expect(totalTokens == 4)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://bedrock-runtime.us-east-1.amazonaws.com/model/anthropic.claude-3-haiku-20240307-v1%3A0/converse-stream")
    #expect(request.headers["accept"] == "application/vnd.amazon.eventstream")
    #expect(request.headers["authorization"]?.contains("Credential=AKIDEXAMPLE/20240315/us-east-1/bedrock/aws4_request") == true)
}

@Test func amazonBedrockLanguageStreamsReasoningAndMetadata() async throws {
    let fixedDate = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2024,
        month: 3,
        day: 15,
        hour: 0,
        minute: 0,
        second: 0
    ).date!
    let transport = RecordingTransport(response: amazonEventStreamResponse([
        ("contentBlockDelta", #"{"contentBlockIndex":0,"delta":{"reasoningContent":{"text":"think"}}}"#),
        ("contentBlockDelta", #"{"contentBlockIndex":0,"delta":{"reasoningContent":{"signature":"sig-1"}}}"#),
        ("contentBlockDelta", #"{"contentBlockIndex":1,"delta":{"reasoningContent":{"data":"redacted-1"}}}"#),
        ("contentBlockDelta", #"{"contentBlockIndex":2,"delta":{"text":"answer"}}"#),
        ("messageStop", #"{"stopReason":"end_turn"}"#),
        ("metadata", #"{"usage":{"inputTokens":2,"outputTokens":2,"totalTokens":4,"cacheWriteInputTokens":5,"cacheDetails":{"cache":"warm"}},"trace":{"guardrail":{"action":"NONE"}},"performanceConfig":{"latency":"optimized"},"serviceTier":"priority"}"#)
    ]))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        accessKeyID: "AKIDEXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
        transport: transport,
        date: { fixedDate }
    ))
    let model = try provider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")

    var reasoning: [String] = []
    var text: [String] = []
    var metadata: [[String: JSONValue]] = []
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Think.")])) {
        switch part {
        case let .reasoningDelta(delta):
            reasoning.append(delta)
        case let .textDelta(delta):
            text.append(delta)
        case let .metadata(value):
            metadata.append(value)
        case let .finish(_, usage):
            totalTokens = usage?.totalTokens ?? totalTokens
        default:
            break
        }
    }

    #expect(reasoning == ["think"])
    #expect(text == ["answer"])
    #expect(metadata.contains { $0["amazonBedrock"]?["signature"]?.stringValue == "sig-1" })
    #expect(metadata.contains { $0["amazonBedrock"]?["redactedData"]?.stringValue == "redacted-1" })
    let eventMetadata = try #require(metadata.first { $0["amazonBedrock"]?["trace"] != nil })
    #expect(eventMetadata["amazonBedrock"]?["trace"]?["guardrail"]?["action"]?.stringValue == "NONE")
    #expect(eventMetadata["amazonBedrock"]?["performanceConfig"]?["latency"]?.stringValue == "optimized")
    #expect(eventMetadata["amazonBedrock"]?["serviceTier"]?.stringValue == "priority")
    #expect(eventMetadata["amazonBedrock"]?["usage"]?["cacheWriteInputTokens"]?.intValue == 5)
    #expect(eventMetadata["bedrock"] == eventMetadata["amazonBedrock"])
    #expect(totalTokens == 4)
}

@Test func amazonBedrockLanguageStreamsToolUseBlocks() async throws {
    let fixedDate = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2024,
        month: 3,
        day: 15,
        hour: 0,
        minute: 0,
        second: 0
    ).date!
    let transport = RecordingTransport(response: amazonEventStreamResponse([
        ("contentBlockStart", #"{"contentBlockIndex":0,"start":{"toolUse":{"toolUseId":"tool-use-id","name":"test-tool"}}}"#),
        ("contentBlockDelta", #"{"contentBlockIndex":0,"delta":{"toolUse":{"input":"{\"value\":"}}}"#),
        ("contentBlockDelta", #"{"contentBlockIndex":0,"delta":{"toolUse":{"input":"\"Sparkle Day\"}"}}}"#),
        ("contentBlockStop", #"{"contentBlockIndex":0}"#),
        ("messageStop", #"{"stopReason":"tool_use"}"#),
        ("metadata", #"{"usage":{"inputTokens":2,"outputTokens":2,"totalTokens":4}}"#)
    ]))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        accessKeyID: "AKIDEXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
        transport: transport,
        date: { fixedDate }
    ))
    let model = try provider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")

    var deltas: [String] = []
    var finalCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Use a tool.")])) {
        switch part {
        case let .toolCallDelta(_, _, argumentsDelta, _):
            deltas.append(argumentsDelta)
        case let .toolCall(call):
            finalCall = call
        case let .finish(reason, usage):
            finishReason = reason ?? finishReason
            totalTokens = usage?.totalTokens ?? totalTokens
        default:
            break
        }
    }

    let call = try #require(finalCall)
    #expect(deltas == ["{\"value\":", "\"Sparkle Day\"}"])
    #expect(call.id == "tool-use-id")
    #expect(call.name == "test-tool")
    #expect(try decodeJSONBody(Data(call.arguments.utf8))["value"]?.stringValue == "Sparkle Day")
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 4)
}

@Test func amazonBedrockEmbeddingUsesInvokeEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"embedding":[0.1,0.2,0.3]}
    """))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-west-2",
        apiKey: "bearer-key",
        transport: transport
    ))
    let model = try provider.embeddingModel("amazon.titan-embed-text-v2:0")

    let result = try await model.embed(EmbeddingRequest(values: ["hello"], dimensions: 256))

    #expect(result.embeddings == [[0.1, 0.2, 0.3]])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://bedrock-runtime.us-west-2.amazonaws.com/model/amazon.titan-embed-text-v2%3A0/invoke")
    #expect(request.headers["Authorization"] == "Bearer bearer-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["inputText"]?.stringValue == "hello")
    #expect(body["dimensions"]?.intValue == 256)
}

@Test func amazonBedrockImageMapsTextOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"images":["image-1"]}"#))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bearer-key",
        transport: transport
    ))
    let model = try provider.imageModel("amazon.nova-canvas-v1:0")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "A studio portrait",
        size: "1024x768",
        count: 2,
        extraBody: [
            "bedrock": .object([
                "negativeText": .string("blur"),
                "quality": .string("premium"),
                "cfgScale": .number(7),
                "style": .string("PHOTOREALISM"),
                "seed": .number(1234)
            ])
        ]
    ))

    #expect(result.base64Images == ["image-1"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://bedrock-runtime.us-east-1.amazonaws.com/model/amazon.nova-canvas-v1%3A0/invoke")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["taskType"]?.stringValue == "TEXT_IMAGE")
    #expect(body["textToImageParams"]?["text"]?.stringValue == "A studio portrait")
    #expect(body["textToImageParams"]?["negativeText"]?.stringValue == "blur")
    #expect(body["textToImageParams"]?["style"]?.stringValue == "PHOTOREALISM")
    #expect(body["imageGenerationConfig"]?["width"]?.intValue == 1024)
    #expect(body["imageGenerationConfig"]?["height"]?.intValue == 768)
    #expect(body["imageGenerationConfig"]?["numberOfImages"]?.intValue == 2)
    #expect(body["imageGenerationConfig"]?["quality"]?.stringValue == "premium")
    #expect(body["imageGenerationConfig"]?["cfgScale"]?.intValue == 7)
    #expect(body["imageGenerationConfig"]?["seed"]?.intValue == 1234)
    #expect(body["bedrock"] == nil)
}

@Test func amazonBedrockImageMapsEditModes() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"images":["inpainted"]}"#),
        jsonResponse(#"{"images":["outpainted"]}"#),
        jsonResponse(#"{"images":["background-removed"]}"#),
        jsonResponse(#"{"images":["variation"]}"#)
    ])
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bearer-key",
        transport: transport
    ))
    let model = try provider.imageModel("amazon.nova-canvas-v1:0")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Replace the sky",
        count: 1,
        files: [ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png")],
        extraBody: [
            "amazonBedrock": .object([
                "maskPrompt": .string("sky"),
                "negativeText": .string("rain"),
                "quality": .string("standard")
            ])
        ]
    ))
    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Extend the scene",
        files: [ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png")],
        mask: ImageInputFile(data: Data([255, 255, 255, 0]), mediaType: "image/png"),
        extraBody: [
            "amazonBedrock": .object([
                "taskType": .string("OUTPAINTING"),
                "outPaintingMode": .string("DEFAULT")
            ])
        ]
    ))
    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "",
        files: [ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png")],
        extraBody: ["amazonBedrock": .object(["taskType": .string("BACKGROUND_REMOVAL")])]
    ))
    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Create a variation",
        size: "512x512",
        count: 3,
        files: [
            ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png"),
            ImageInputFile(data: Data([255, 216, 255, 224]), mediaType: "image/jpeg")
        ],
        extraBody: [
            "amazonBedrock": .object([
                "taskType": .string("IMAGE_VARIATION"),
                "similarityStrength": .number(0.7),
                "negativeText": .string("low quality")
            ])
        ]
    ))

    let requests = await transport.requests()
    let inpainting = try decodeJSONBody(try #require(requests[0].body))
    #expect(inpainting["taskType"]?.stringValue == "INPAINTING")
    #expect(inpainting["inPaintingParams"]?["image"]?.stringValue == Data([137, 80, 78, 71]).base64EncodedString())
    #expect(inpainting["inPaintingParams"]?["maskPrompt"]?.stringValue == "sky")
    #expect(inpainting["inPaintingParams"]?["negativeText"]?.stringValue == "rain")
    #expect(inpainting["imageGenerationConfig"]?["quality"]?.stringValue == "standard")

    let outpainting = try decodeJSONBody(try #require(requests[1].body))
    #expect(outpainting["taskType"]?.stringValue == "OUTPAINTING")
    #expect(outpainting["outPaintingParams"]?["maskImage"]?.stringValue == Data([255, 255, 255, 0]).base64EncodedString())
    #expect(outpainting["outPaintingParams"]?["outPaintingMode"]?.stringValue == "DEFAULT")

    let backgroundRemoval = try decodeJSONBody(try #require(requests[2].body))
    #expect(backgroundRemoval["taskType"]?.stringValue == "BACKGROUND_REMOVAL")
    #expect(backgroundRemoval["backgroundRemovalParams"]?["image"]?.stringValue == Data([137, 80, 78, 71]).base64EncodedString())
    #expect(backgroundRemoval["imageGenerationConfig"] == nil)

    let variation = try decodeJSONBody(try #require(requests[3].body))
    #expect(variation["taskType"]?.stringValue == "IMAGE_VARIATION")
    #expect(variation["imageVariationParams"]?["images"]?[0]?.stringValue == Data([137, 80, 78, 71]).base64EncodedString())
    #expect(variation["imageVariationParams"]?["images"]?[1]?.stringValue == Data([255, 216, 255, 224]).base64EncodedString())
    #expect(variation["imageVariationParams"]?["similarityStrength"]?.doubleValue == 0.7)
    #expect(variation["imageGenerationConfig"]?["width"]?.intValue == 512)
    #expect(variation["imageGenerationConfig"]?["height"]?.intValue == 512)
    #expect(variation["imageGenerationConfig"]?["numberOfImages"]?.intValue == 3)
}
