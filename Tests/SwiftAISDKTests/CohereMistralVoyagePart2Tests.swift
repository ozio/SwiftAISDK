import Foundation
import Testing
@testable import SwiftAISDK

@Test func mistralMessagesMapAssistantReasoningPrefixAndImageWildcardLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-1","object":"chat.completion","model":"mistral-small-latest","choices":[{"index":0,"message":{"role":"assistant","content":"continued"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-small-latest")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .text("See"),
            .data(mimeType: "image/*", data: Data([0, 1, 2]))
        ]),
        .assistant("Partial answer", reasoning: " prior thinking")
    ]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let messages = try #require(body["messages"]?.arrayValue)
    let userContent = try #require(messages[0]["content"]?.arrayValue)
    #expect(userContent[1]["type"]?.stringValue == "image_url")
    #expect(userContent[1]["image_url"]?.stringValue == "data:image/jpeg;base64,AAEC")
    #expect(messages[1]["role"]?.stringValue == "assistant")
    #expect(messages[1]["content"]?.stringValue == "Partial answer prior thinking")
    #expect(messages[1]["prefix"]?.boolValue == true)
}
@Test func mistralRejectsUnsupportedUserFilePartsLikeUpstream() async throws {
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: RecordingTransport(responses: [])))
    let model = try provider.languageModel("mistral-small-latest")

    await #expect(throws: AIError.invalidArgument(argument: "files", message: "Mistral chat API only supports image and PDF file parts; got text/plain.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [
            AIMessage(role: .user, content: [.file(mimeType: "text/plain", data: Data("nope".utf8), filename: "note.txt")])
        ]))
    }
}
@Test func mistralLanguageMapsStandardStructuredResponseFormat() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-1","object":"chat.completion","model":"mistral-small-latest","choices":[{"index":0,"message":{"role":"assistant","content":"{\\"value\\":\\"ok\\"}"},"finish_reason":"stop"}],"usage":{"total_tokens":5}}
    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-small-latest")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Answer.")],
        responseFormat: .json(
            schema: [
                "type": "object",
                "properties": ["value": ["type": "string"]],
                "required": ["value"]
            ],
            name: "answer",
            description: "Answer schema"
        )
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?["type"]?.stringValue == "json_schema")
    #expect(body["response_format"]?["json_schema"]?["name"]?.stringValue == "answer")
    #expect(body["response_format"]?["json_schema"]?["description"]?.stringValue == "Answer schema")
    #expect(body["response_format"]?["json_schema"]?["schema"]?["type"]?.stringValue == "object")
    #expect(body["response_format"]?["json_schema"]?["schema"]?["properties"]?["value"]?["type"]?.stringValue == "string")
    #expect(body["response_format"]?["json_schema"]?["strict"]?.boolValue == false)
    #expect(body["messages"]?[0]?["role"]?.stringValue == "user")
    #expect(body["responseFormat"] == nil)
}
@Test func mistralLanguageAllowsStructuredOutputsOverride() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-1","object":"chat.completion","model":"mistral-small-latest","choices":[{"index":0,"message":{"role":"assistant","content":"{\\"value\\":\\"ok\\"}"},"finish_reason":"stop"}],"usage":{"total_tokens":5}}
    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-small-latest")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Answer.")],
        extraBody: [
            "responseFormat": [
                "type": "json",
                "schema": ["type": "object"],
                "name": "answer"
            ],
            "structuredOutputs": false,
            "strictJsonSchema": true
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?["type"]?.stringValue == "json_object")
    #expect(body["response_format"]?["json_schema"] == nil)
    #expect(body["responseFormat"] == nil)
    #expect(body["structuredOutputs"] == nil)
    #expect(body["strictJsonSchema"] == nil)
}
@Test func mistralLanguageUsesProviderOptionsStructuredOutputControls() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-1","object":"chat.completion","model":"mistral-small-latest","choices":[{"index":0,"message":{"role":"assistant","content":"{\\"value\\":\\"ok\\"}"},"finish_reason":"stop"}],"usage":{"total_tokens":5}}
    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-small-latest")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Answer.")],
        responseFormat: .json(schema: ["type": "object"], name: "answer"),
        providerOptions: [
            "mistral": [
                "structuredOutputs": true,
                "strictJsonSchema": true
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?["type"]?.stringValue == "json_schema")
    #expect(body["response_format"]?["json_schema"]?["strict"]?.boolValue == true)
    #expect(body["structuredOutputs"] == nil)
    #expect(body["strictJsonSchema"] == nil)
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
@Test func mistralErrorFinishReasonMapsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-1","object":"chat.completion","model":"mistral-large-latest","choices":[{"index":0,"message":{"role":"assistant","content":"failed"},"finish_reason":"error"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-large-latest")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.finishReason == "error")
}
@Test func mistralProviderDefinedToolsAreSkippedWithWarning() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-1","object":"chat.completion","model":"mistral-small-latest","choices":[{"index":0,"message":{"role":"assistant","content":"done"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-small-latest")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        tools: [
            "lookup": [
                "type": "object",
                "properties": ["value": ["type": "string"]],
                "strict": true
            ],
            "mistral.search": [
                "type": "provider",
                "id": "mistral.search"
            ]
        ]
    ))

    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "provider-defined tool mistral.search")
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.count == 1)
    #expect(tools[0]["function"]?["name"]?.stringValue == "lookup")
    #expect(tools[0]["function"]?["strict"]?.boolValue == true)
    #expect(tools[0]["function"]?["parameters"]?["strict"] == nil)
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
@Test func mistralLanguageSerializesToolCallsAndModelOutputResults() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-2","object":"chat.completion","model":"mistral-small-latest","choices":[{"index":0,"message":{"role":"assistant","content":"done"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":2,"total_tokens":12}}
    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-small-latest")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .user("Weather?"),
        .assistant(
            toolCalls: [
                AIToolCall(
                    id: "call_weather",
                    name: "weather",
                    arguments: #"{"location":"Paris"}"#
                ),
                AIToolCall(
                    id: "call_air",
                    name: "airQuality",
                    arguments: #"{"location":"Paris"}"#
                )
            ]
        ),
        .toolResponses(toolResults: [
            AIToolResult(
                toolCallID: "call_weather",
                toolName: "weather",
                result: ["raw": "do not send"],
                modelOutput: [
                    "type": "content",
                    "value": [
                        ["type": "text", "text": "Sunny in Paris"]
                    ]
                ]
            ),
            AIToolResult(
                toolCallID: "call_air",
                toolName: "airQuality",
                result: ["raw": "fallback"],
                modelOutput: [
                    "type": "text",
                    "value": "Good"
                ]
            ),
            AIToolResult(
                toolCallID: "call_denied",
                toolName: "deny",
                result: ["raw": "fallback"],
                modelOutput: [
                    "type": "execution-denied"
                ]
            )
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let messages = try #require(body["messages"]?.arrayValue)
    #expect(messages[1]["role"]?.stringValue == "assistant")
    #expect(messages[1]["tool_calls"]?[0]?["id"]?.stringValue == "call_weather")
    #expect(messages[1]["tool_calls"]?[0]?["function"]?["name"]?.stringValue == "weather")
    #expect(messages[1]["tool_calls"]?[0]?["function"]?["arguments"]?.stringValue == #"{"location":"Paris"}"#)
    #expect(messages[1]["tool_calls"]?[1]?["id"]?.stringValue == "call_air")
    #expect(messages[2]["role"]?.stringValue == "tool")
    #expect(messages[2]["name"]?.stringValue == "weather")
    #expect(messages[2]["tool_call_id"]?.stringValue == "call_weather")
    #expect(messages[3]["role"]?.stringValue == "tool")
    #expect(messages[3]["name"]?.stringValue == "airQuality")
    #expect(messages[3]["tool_call_id"]?.stringValue == "call_air")
    #expect(messages[3]["content"]?.stringValue == "Good")
    #expect(messages[4]["role"]?.stringValue == "tool")
    #expect(messages[4]["name"]?.stringValue == "deny")
    #expect(messages[4]["tool_call_id"]?.stringValue == "call_denied")
    #expect(messages[4]["content"]?.stringValue == "Tool execution denied.")

    let content = try #require(messages[2]["content"]?.stringValue)
    let contentJSON = try decodeJSONBody(Data(content.utf8))
    #expect(contentJSON[0]?["text"]?.stringValue == "Sunny in Paris")
    #expect(contentJSON[0]?["raw"] == nil)
}
@Test func mistralLanguageStreamsNativeChunks() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"cmpl-1","created":1741257730,"model":"mistral","choices":[{"index":0,"delta":{"role":"assistant","content":[{"type":"thinking","thinking":[{"type":"text","text":"hmm"}]}]},"finish_reason":null}]}

    data: {"id":"cmpl-1","model":"mistral","choices":[{"index":0,"delta":{"content":[{"type":"text","text":"bon"}]},"finish_reason":null}]}

    data: {"id":"cmpl-1","model":"mistral","choices":[{"index":0,"delta":{"content":"jour"},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}

    """, headers: ["x-stream": "yes"]))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-large-latest")

    var text: [String] = []
    var reasoning: [String] = []
    var lifecycle: [String] = []
    var finishReason: String?
    var totalTokens: Int?
    var streamStartWarnings: [AIWarning]?
    var responseMetadata: AIResponseMetadata?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hi")],
        topK: 8,
        providerOptions: ["mistral": ["documentImageLimit": 2]]
    )) {
        switch part {
        case let .textDelta(delta):
            text.append(delta)
        case let .textDeltaPart(id, delta, _):
            lifecycle.append("text-delta:\(id):\(delta)")
            text.append(delta)
        case let .textStart(id, _):
            lifecycle.append("text-start:\(id)")
        case let .textEnd(id, _):
            lifecycle.append("text-end:\(id)")
        case let .reasoningDelta(delta):
            reasoning.append(delta)
        case let .reasoningDeltaPart(id, delta, _):
            lifecycle.append("reasoning-delta:\(id):\(delta)")
            reasoning.append(delta)
        case let .reasoningStart(id, _):
            lifecycle.append("reasoning-start:\(id)")
        case let .reasoningEnd(id, _):
            lifecycle.append("reasoning-end:\(id)")
        case let .streamStart(warnings):
            streamStartWarnings = warnings
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(reasoning == ["hmm"])
    #expect(text == ["bon", "jour"])
    #expect(lifecycle == [
        "reasoning-start:reasoning-0",
        "reasoning-delta:reasoning-0:hmm",
        "reasoning-end:reasoning-0",
        "text-start:0",
        "text-delta:0:bon",
        "text-delta:0:jour",
        "text-end:0"
    ])
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 3)
    #expect(streamStartWarnings == [AIWarning(type: "unsupported", feature: "topK")])
    #expect(responseMetadata?.id == "cmpl-1")
    #expect(responseMetadata?.modelID == "mistral")
    #expect(responseMetadata?.headers["x-stream"] == "yes")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
    #expect(body["document_image_limit"]?.intValue == 2)
    #expect(body["top_k"] == nil)
}
@Test func mistralLanguageStreamsToolCalls() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"cmpl-1","model":"mistral-small-latest","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

    data: {"id":"cmpl-1","model":"mistral-small-latest","choices":[{"index":0,"delta":{"content":null,"tool_calls":[{"id":"gSIMJiOkT","function":{"name":"weather","arguments":"{\\"location\\": \\"San Francisco\\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":124,"completion_tokens":22,"total_tokens":146}}

    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-small-latest")

    var deltas: [String] = []
    var inputLifecycle: [String] = []
    var toolCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Weather?")],
        tools: ["weather": ["type": "object", "properties": ["location": ["type": "string"]]]]
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
    #expect(deltas == [#"{"location": "San Francisco"}"#])
    #expect(inputLifecycle == [
        "start:gSIMJiOkT:weather",
        #"delta:gSIMJiOkT:{"location": "San Francisco"}"#,
        "end:gSIMJiOkT"
    ])
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

    let tooManyValues = Array(repeating: "x", count: 33)
    await #expect(throws: AITooManyEmbeddingValuesForCallError(
        provider: "mistral.embedding",
        modelID: "mistral-embed",
        maxEmbeddingsPerCall: 32,
        values: tooManyValues
    )) {
        _ = try await model.embed(EmbeddingRequest(values: tooManyValues))
    }
    #expect(await transport.requests().count == 1)
}
