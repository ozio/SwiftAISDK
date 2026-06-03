import Foundation
import Testing
@testable import SwiftAISDK

@Test func groqLanguageStreamsReasoningAndMapsOptions() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"groq-1","created":1780326500,"model":"qwen/qwen3-32b","choices":[{"index":0,"delta":{"reasoning":"think"},"finish_reason":null}]}

    data: {"id":"groq-1","model":"qwen/qwen3-32b","choices":[{"index":0,"delta":{"content":"answer"},"finish_reason":"stop"}],"x_groq":{"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5,"prompt_tokens_details":{"cached_tokens":1},"completion_tokens_details":{"reasoning_tokens":1}}}}

    data: [DONE]

    """, headers: ["x-groq": "stream"]))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("qwen/qwen3-32b")

    var streamStartWarnings: [AIWarning]?
    var responseMetadata: AIResponseMetadata?
    var reasoningLifecycle: [String] = []
    var textLifecycle: [String] = []
    var usage: TokenUsage?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hi")],
        reasoning: "xhigh",
        providerOptions: [
            "groq": [
                "reasoningFormat": "parsed",
                "parallelToolCalls": false,
                "serviceTier": "flex"
            ]
        ],
        extraBody: [
            "reasoningFormat": "parsed",
            "parallelToolCalls": true,
            "serviceTier": "performance"
        ]
    )) {
        switch part {
        case let .streamStart(warnings):
            streamStartWarnings = warnings
        case let .responseMetadata(metadata):
            responseMetadata = metadata
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
        case let .finish(_, finishUsage):
            usage = finishUsage
        default:
            break
        }
    }

    #expect(streamStartWarnings == [])
    #expect(responseMetadata?.id == "groq-1")
    #expect(responseMetadata?.modelID == "qwen/qwen3-32b")
    #expect(responseMetadata?.headers["x-groq"] == "stream")
    #expect(reasoningLifecycle == ["start:reasoning-0", "delta:reasoning-0:think", "end:reasoning-0"])
    #expect(textLifecycle == ["start:txt-0", "delta:txt-0:answer", "end:txt-0"])
    #expect(usage?.totalTokens == 5)
    #expect(usage?.inputTokens == 2)
    #expect(usage?.inputTokensNoCache == 2)
    #expect(usage?.inputTokensCacheRead == nil)
    #expect(usage?.outputTokens == 3)
    #expect(usage?.outputTextTokens == 2)
    #expect(usage?.outputReasoningTokens == 1)
    #expect(usage?.rawValue?["prompt_tokens_details"]?["cached_tokens"]?.intValue == 1)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.groq.com/openai/v1/chat/completions")
    #expect(request.headers["authorization"] == "Bearer groq-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
    #expect(body["reasoning_format"]?.stringValue == "parsed")
    #expect(body["reasoning_effort"]?.stringValue == "high")
    #expect(body["parallel_tool_calls"]?.boolValue == false)
    #expect(body["service_tier"]?.stringValue == "flex")
}

@Test func groqProviderAddsVersionedUserAgentSuffix() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"groq-1","model":"gemma2-9b-it","choices":[{"index":0,"message":{"content":"done"},"finish_reason":"stop"}]}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(
        apiKey: "groq-key",
        headers: ["User-Agent": "custom-client/1.0"],
        transport: transport
    ))
    let model = try provider.languageModel("gemma2-9b-it")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    let request = try #require(await transport.requests().first)
    #expect(request.headers["authorization"] == "Bearer groq-key")
    #expect(request.headers["user-agent"] == "custom-client/1.0 ai-sdk/groq/3.0.39")
}

@Test func groqLanguageMapsMissingFinishReasonToOther() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"groq-1","model":"gemma2-9b-it","choices":[{"index":0,"message":{"content":"ok"},"finish_reason":null}]}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("gemma2-9b-it")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "ok")
    #expect(result.finishReason == "other")
}

@Test func groqLanguageAcceptsReasoningOnlyResponseLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"groq-1","model":"qwen/qwen3-32b","choices":[{"index":0,"message":{"content":null,"reasoning":"thinking only"},"finish_reason":"stop"}]}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("qwen/qwen3-32b")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Think.")]))

    #expect(result.text == "")
    #expect(result.reasoning == "thinking only")
    #expect(result.finishReason == "stop")
}

@Test func groqLanguageMapsNestedProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"groq-1","model":"openai/gpt-oss-20b","choices":[{"message":{"content":"answer"},"finish_reason":"stop"}]}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("openai/gpt-oss-20b")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        topK: 4,
        presencePenalty: 0.1,
        frequencyPenalty: 0.2,
        seed: 123,
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

    #expect(result.warnings == [AIWarning(type: "unsupported", feature: "topK")])
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["groq"] == nil)
    #expect(body["user"]?.stringValue == "user-123")
    #expect(body["presence_penalty"]?.doubleValue == 0.1)
    #expect(body["frequency_penalty"]?.doubleValue == 0.2)
    #expect(body["seed"]?.intValue == 123)
    #expect(body["reasoning_format"]?.stringValue == "parsed")
    #expect(body["reasoning_effort"]?.stringValue == "low")
    #expect(body["parallel_tool_calls"]?.boolValue == false)
    #expect(body["service_tier"]?.stringValue == "performance")
    #expect(body["strictJsonSchema"] == nil)
    #expect(body["strict_json_schema"] == nil)
}

@Test func groqLanguageMapsImagesAndAssistantReasoningHistoryLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"groq-1","model":"openai/gpt-oss-20b","choices":[{"index":0,"message":{"content":"answer"},"finish_reason":"stop"}]}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("openai/gpt-oss-20b")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .text("Look"),
            .imageURL("https://example.com/image.png"),
            .data(mimeType: "image/*", data: Data([0, 1, 2]))
        ]),
        .assistant(
            text: "Prior answer",
            reasoning: "Prior reasoning",
            toolCalls: [AIToolCall(id: "call_lookup", name: "lookup", arguments: #"{"query":"x"}"#)]
        )
    ]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let messages = try #require(body["messages"]?.arrayValue)
    let userContent = try #require(messages[0]["content"]?.arrayValue)
    #expect(userContent[0]["type"]?.stringValue == "text")
    #expect(userContent[0]["text"]?.stringValue == "Look")
    #expect(userContent[1]["image_url"]?["url"]?.stringValue == "https://example.com/image.png")
    #expect(userContent[2]["image_url"]?["url"]?.stringValue == "data:image/jpeg;base64,AAEC")
    #expect(messages[1]["role"]?.stringValue == "assistant")
    #expect(messages[1]["content"]?.stringValue == "Prior answer")
    #expect(messages[1]["reasoning"]?.stringValue == "Prior reasoning")
    #expect(messages[1]["tool_calls"]?[0]?["function"]?["name"]?.stringValue == "lookup")
}

@Test func groqLanguageRejectsNonImageFilePartsLikeUpstream() async throws {
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: RecordingTransport(responses: [])))
    let model = try provider.languageModel("gemma2-9b-it")

    await #expect(throws: AIError.invalidArgument(argument: "files", message: "Groq chat API only supports image file parts; got application/pdf.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [
            AIMessage(role: .user, content: [.file(mimeType: "application/pdf", data: Data([0]), filename: "doc.pdf")])
        ]))
    }
}

@Test func groqLanguageValidatesProviderOptionsNamespaceAndSchema() async throws {
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: RecordingTransport(responses: [])))
    let model = try provider.languageModel("openai/gpt-oss-20b")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.groq", message: "Groq provider options must be an object.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["groq": "not-an-object"]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.groq.reasoningFormat", message: "Groq reasoningFormat must be parsed, raw, or hidden.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["groq": .object(["reasoningFormat": "visible"])]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.groq.reasoningEffort", message: "Groq reasoningEffort must be none, default, low, medium, or high.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["groq": .object(["reasoningEffort": "minimal"])]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.groq.parallelToolCalls", message: "Groq parallelToolCalls must be a boolean.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["groq": .object(["parallelToolCalls": "false"])]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.groq.serviceTier", message: "Groq serviceTier must be on_demand, performance, flex, or auto.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["groq": .object(["serviceTier": "priority"])]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.groq.user", message: "Groq user cannot be null.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["groq": .object(["user": .null])]
        ))
    }
}

@Test func groqLanguageStripsUnknownProviderOptionsKeys() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"groq-1","model":"openai/gpt-oss-20b","choices":[{"message":{"content":"answer"},"finish_reason":"stop"}]}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("openai/gpt-oss-20b")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        providerOptions: [
            "groq": .object([
                "user": "user-123",
                "serviceTier": "auto",
                "unsupportedProperty": "drop-me"
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["user"]?.stringValue == "user-123")
    #expect(body["service_tier"]?.stringValue == "auto")
    #expect(body["unsupportedProperty"] == nil)
}

@Test func groqLanguageTreatsNullProviderOptionsNamespaceAsNoop() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"groq-1","model":"openai/gpt-oss-20b","choices":[{"message":{"content":"answer"},"finish_reason":"stop"}]}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("openai/gpt-oss-20b")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        providerOptions: ["groq": .null],
        extraBody: [
            "groq": [
                "user": "user-123",
                "serviceTier": "flex"
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["user"]?.stringValue == "user-123")
    #expect(body["service_tier"]?.stringValue == "flex")
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
        toolChoice: ["type": "tool", "toolName": "lookup"]
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
    {"id":"groq-1","created":1780326500,"model":"llama-3.3-70b-versatile","choices":[{"index":0,"message":{"role":"assistant","content":null,"reasoning":"Need weather.","tool_calls":[{"id":"tk85n1k4m","type":"function","function":{"name":"weather","arguments":"{}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":210,"completion_tokens":15,"total_tokens":225,"prompt_tokens_details":{"cached_tokens":12},"completion_tokens_details":{"reasoning_tokens":5}}}
    """, headers: ["x-groq": "generate"]))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("llama-3.3-70b-versatile")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Weather?")],
        tools: ["weather": ["type": "object", "properties": [:]]]
    ))

    #expect(result.text == "")
    #expect(result.reasoning == "Need weather.")
    #expect(result.finishReason == "tool-calls")
    #expect(result.usage?.totalTokens == 225)
    #expect(result.usage?.inputTokensNoCache == 210)
    #expect(result.usage?.inputTokensCacheRead == nil)
    #expect(result.usage?.outputTextTokens == 10)
    #expect(result.usage?.outputReasoningTokens == 5)
    #expect(result.usage?.rawValue?["prompt_tokens_details"]?["cached_tokens"]?.intValue == 12)
    #expect(result.responseMetadata.id == "groq-1")
    #expect(result.responseMetadata.modelID == "llama-3.3-70b-versatile")
    #expect(result.responseMetadata.headers["x-groq"] == "generate")
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

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Search.")],
        tools: [
            "groq.browser_search": GroqTools.browserSearch()
        ],
        extraBody: ["toolChoice": "required"]
    ))

    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "provider-defined tool groq.browser_search")
    ])
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
    #expect(request.headers["authorization"] == "Bearer groq-key")
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"model\""))
    #expect(bodyText.contains("whisper-large-v3"))
    #expect(bodyText.contains("name=\"file\"; filename=\"audio.mp3\""))
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
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"nested transcript","x_groq":{"id":"req-nested"}}"#))
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

@Test func groqTranscriptionMapsProviderOptionsNamespace() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"provider options transcript","x_groq":{"id":"req-provider"},"language":"fr","duration":0.8}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.transcriptionModel("whisper-large-v3-turbo")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("mp3".utf8),
        fileName: "clip.mp3",
        mimeType: "audio/mpeg",
        providerOptions: [
            "groq": [
                "language": "fr",
                "prompt": "Noms propres",
                "responseFormat": "verbose_json",
                "temperature": 0.25,
                "timestampGranularities": ["segment"]
            ]
        ]
    ))

    #expect(result.text == "provider options transcript")
    #expect(result.requestMetadata.body?["language"]?.stringValue == "fr")
    #expect(result.requestMetadata.body?["prompt"]?.stringValue == "Noms propres")
    #expect(result.requestMetadata.body?["response_format"]?.stringValue == "verbose_json")
    #expect(result.requestMetadata.body?["timestamp_granularities"]?[0]?.stringValue == "segment")

    let request = try #require(await transport.requests().first)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(!bodyText.contains("name=\"groq\""))
    #expect(bodyText.contains("name=\"language\""))
    #expect(bodyText.contains("fr"))
    #expect(bodyText.contains("name=\"prompt\""))
    #expect(bodyText.contains("Noms propres"))
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("verbose_json"))
    #expect(bodyText.contains("name=\"timestamp_granularities[]\""))
    #expect(bodyText.contains("segment"))
}

@Test func groqTranscriptionProviderOptionsNullishFieldsClearExtraBodyDefaults() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"nullish transcript","x_groq":{"id":"req-nullish"}}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.transcriptionModel("whisper-large-v3-turbo")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("mp3".utf8),
        fileName: "clip.mp3",
        mimeType: "audio/mpeg",
        providerOptions: [
            "groq": .object([
                "language": .null,
                "prompt": .null,
                "responseFormat": .null,
                "temperature": .null,
                "timestampGranularities": .null
            ])
        ],
        extraBody: [
            "groq": [
                "language": "ja",
                "prompt": "legacy prompt",
                "responseFormat": "verbose_json",
                "temperature": 0.4,
                "timestampGranularities": ["word"]
            ]
        ]
    ))

    let request = try #require(await transport.requests().first)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(!bodyText.contains("name=\"language\""))
    #expect(!bodyText.contains("name=\"prompt\""))
    #expect(!bodyText.contains("name=\"response_format\""))
    #expect(!bodyText.contains("name=\"temperature\""))
    #expect(!bodyText.contains("name=\"timestamp_granularities[]\""))
}

@Test func groqTranscriptionTreatsNullProviderOptionsNamespaceAsNoop() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"null namespace transcript","x_groq":{"id":"req-null-namespace"}}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.transcriptionModel("whisper-large-v3-turbo")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("mp3".utf8),
        mimeType: "audio/mpeg",
        providerOptions: ["groq": .null],
        extraBody: [
            "groq": [
                "responseFormat": "verbose_json",
                "timestampGranularities": ["segment"],
                "temperature": 0.2
            ]
        ]
    ))

    let request = try #require(await transport.requests().first)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("verbose_json"))
    #expect(bodyText.contains("name=\"timestamp_granularities[]\""))
    #expect(bodyText.contains("segment"))
    #expect(bodyText.contains("name=\"temperature\""))
    #expect(bodyText.contains("0.2"))
}

@Test func groqTranscriptionRejectsMissingXGroqIDLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"missing id"}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.transcriptionModel("whisper-large-v3")

    await #expect(throws: AIError.invalidResponse(provider: "groq.transcription", message: "Groq transcription response is invalid.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("mp3".utf8), mimeType: "audio/mpeg"))
    }
}

@Test func groqTranscriptionRejectsInvalidVerboseSegmentsLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"bad segments","x_groq":{"id":"req-bad"},"segments":[{"text":"missing required fields","start":0,"end":1}]}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.transcriptionModel("whisper-large-v3")

    await #expect(throws: AIError.invalidResponse(provider: "groq.transcription", message: "Groq transcription response is invalid.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("mp3".utf8), mimeType: "audio/mpeg"))
    }
}

@Test func groqTranscriptionProviderOptionsRejectInvalidSchemaFields() async throws {
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: RecordingTransport(responses: [])))
    let model = try provider.transcriptionModel("whisper-large-v3")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.groq", message: "Groq provider options must be an object.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("mp3".utf8),
            providerOptions: ["groq": "not-an-object"]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.groq.language", message: "Groq language must be a string.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("mp3".utf8),
            providerOptions: ["groq": .object(["language": true])]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.groq.temperature", message: "Groq temperature must be a number between 0 and 1.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("mp3".utf8),
            providerOptions: ["groq": .object(["temperature": 1.2])]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.groq.timestampGranularities", message: "Groq providerOptions.groq.timestampGranularities values must be strings.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("mp3".utf8),
            providerOptions: ["groq": .object(["timestampGranularities": ["word", 42]])]
        ))
    }
}
