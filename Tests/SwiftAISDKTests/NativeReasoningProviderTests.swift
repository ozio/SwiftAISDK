import Foundation
import Testing
@testable import SwiftAISDK

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
    #expect(result.usage?.inputTokensNoCache == 70)
    #expect(result.usage?.inputTokensCacheRead == 30)
    #expect(result.usage?.inputTokensCacheWrite == nil)
    #expect(result.usage?.outputTextTokens == 60)
    #expect(result.usage?.outputReasoningTokens == 20)
    #expect(result.usage?.rawValue?["cached_tokens"]?.intValue == 30)
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
    var lifecycle: [String] = []
    var finishReason: String?
    var usage: TokenUsage?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: ["moonshotAI": ["reasoningHistory": "disabled"]]
    )) {
        switch part {
        case let .streamStart(warnings):
            #expect(warnings == [])
        case let .textStart(id, _):
            lifecycle.append("start:\(id)")
        case let .textDelta(delta):
            text.append(delta)
        case let .textDeltaPart(id, delta, _):
            lifecycle.append("delta:\(id):\(delta)")
        case let .textEnd(id, _):
            lifecycle.append("end:\(id)")
        case let .finish(reason, finalUsage):
            finishReason = reason
            usage = finalUsage
        default:
            break
        }
    }

    #expect(text == ["moon"])
    #expect(lifecycle == ["start:txt-0", "delta:txt-0:moon", "end:txt-0"])
    #expect(finishReason == "stop")
    #expect(usage?.inputTokens == 3)
    #expect(usage?.outputTokens == 4)
    #expect(usage?.totalTokens == 7)
    #expect(usage?.inputTokensNoCache == 2)
    #expect(usage?.inputTokensCacheRead == 1)
    #expect(usage?.outputTextTokens == 4)
    #expect(usage?.outputReasoningTokens == 0)
    #expect(usage?.rawValue?["cached_tokens"]?.intValue == 1)
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream_options"]?["include_usage"]?.boolValue == true)
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
