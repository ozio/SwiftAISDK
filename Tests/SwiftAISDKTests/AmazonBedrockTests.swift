import Foundation
import Testing
@testable import SwiftAISDK

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

@Test func amazonBedrockAnthropicUsesInvokeModelAndTransformsMessagesBody() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"bedrock anthropic"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.amazonBedrockAnthropic(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: transport
    ))
    let model = try provider.messages("anthropic.claude-3-5-sonnet-20241022-v2:0")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.system("Brief."), .user("Hi")],
        maxOutputTokens: 32,
        tools: [
            "bash": AnthropicTools.bash_20241022(),
            "editor": AnthropicTools.textEditor_20241022(),
            "computer": AnthropicTools.computer_20241022(displayWidthPx: 1024, displayHeightPx: 768)
        ],
        extraBody: [
            "toolChoice": ["type": "auto", "disable_parallel_tool_use": true]
        ]
    ))

    #expect(result.text == "bedrock anthropic")
    #expect(result.usage?.inputTokens == 3)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://bedrock-runtime.us-east-1.amazonaws.com/model/anthropic.claude-3-5-sonnet-20241022-v2%3A0/invoke")
    #expect(request.headers["Authorization"] == "Bearer bedrock-key")
    #expect(request.headers["anthropic-beta"] == nil)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"] == nil)
    #expect(body["stream"] == nil)
    #expect(body["anthropic_version"]?.stringValue == "bedrock-2023-05-31")
    #expect(body["system"]?.stringValue == "Brief.")
    #expect(body["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
    #expect(body["max_tokens"]?.intValue == 32)
    #expect(body["tool_choice"]?["type"]?.stringValue == "auto")
    #expect(body["tool_choice"]?["disable_parallel_tool_use"] == nil)
    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.contains { $0["type"]?.stringValue == "bash_20250124" && $0["name"]?.stringValue == "bash" })
    #expect(tools.contains { $0["type"]?.stringValue == "text_editor_20250728" && $0["name"]?.stringValue == "str_replace_based_edit_tool" })
    #expect(tools.contains { $0["type"]?.stringValue == "computer_20250124" && $0["name"]?.stringValue == "computer" })
    #expect(body["anthropic_beta"]?.arrayValue?.contains(.string("computer-use-2025-01-24")) == true)
}

@Test func amazonBedrockAnthropicStreamsEventStreamAsAnthropicEvents() async throws {
    let event1 = #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"bed"}}"#
    let event2 = #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"rock"}}"#
    let transport = RecordingTransport(response: amazonEventStreamResponse([
        ("chunk", #"{"bytes":"\#(Data(event1.utf8).base64EncodedString())"}"#),
        ("chunk", #"{"bytes":"\#(Data(event2.utf8).base64EncodedString())"}"#),
        ("messageStop", #"{}"#)
    ]))
    let provider = try AIProviders.amazonBedrockAnthropic(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: transport
    ))
    let model = try provider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")

    var deltas: [String] = []
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        if case let .textDelta(delta) = part {
            deltas.append(delta)
        }
    }

    #expect(deltas == ["bed", "rock"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://bedrock-runtime.us-east-1.amazonaws.com/model/anthropic.claude-3-haiku-20240307-v1%3A0/invoke-with-response-stream")
    #expect(request.headers["accept"] == "application/vnd.amazon.eventstream")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["anthropic_version"]?.stringValue == "bedrock-2023-05-31")
    #expect(body["stream"] == nil)
}

@Test func bedrockMantleChatUsesBearerAuthAndOpenAIChatEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"mantle chat"},"finish_reason":"stop"}],"usage":{"total_tokens":5}}
    """))
    let provider = try AIProviders.bedrockMantle(settings: AmazonBedrockProviderSettings(
        region: "us-west-2",
        apiKey: "mantle-key",
        headers: ["custom-header": "custom-value"],
        transport: transport
    ))
    let model = try provider.languageModel("openai.gpt-oss-20b")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(provider.providerID == "bedrock-mantle")
    #expect(model.providerID == "bedrock-mantle.chat")
    #expect(result.text == "mantle chat")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://bedrock-mantle.us-west-2.api.aws/v1/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer mantle-key")
    #expect(request.headers["custom-header"] == "custom-value")
    #expect(request.headers["user-agent"] == "SwiftAISDK/amazon-bedrock")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "openai.gpt-oss-20b")
    #expect(body["messages"]?[0]?["content"]?.stringValue == "Hi")
}

@Test func bedrockMantleResponsesUsesSigV4ServiceAndResponsesEndpoint() async throws {
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
    {"output_text":"mantle responses","status":"completed","usage":{"total_tokens":7}}
    """))
    let provider = try AIProviders.bedrockMantle(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        accessKeyID: "AKIDEXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
        transport: transport,
        date: { fixedDate }
    ))
    let model = try provider.responses("openai.gpt-oss-120b")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], maxOutputTokens: 8))

    #expect(model.providerID == "bedrock-mantle.responses")
    #expect(result.text == "mantle responses")
    #expect(result.usage?.totalTokens == 7)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://bedrock-mantle.us-east-1.api.aws/v1/responses")
    #expect(request.headers["x-amz-date"] == "20240315T000000Z")
    #expect(request.headers["authorization"]?.contains("Credential=AKIDEXAMPLE/20240315/us-east-1/bedrock-mantle/aws4_request") == true)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "openai.gpt-oss-120b")
    #expect(body["max_output_tokens"]?.intValue == 8)
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
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
    var inputLifecycle: [String] = []
    var finalCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
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
        case let .finish(reason, usage):
            finishReason = reason ?? finishReason
            totalTokens = usage?.totalTokens ?? totalTokens
        default:
            break
        }
    }

    let call = try #require(finalCall)
    #expect(deltas == ["{\"value\":", "\"Sparkle Day\"}"])
    #expect(inputLifecycle == [
        "start:tool-use-id:test-tool",
        "delta:tool-use-id:{\"value\":",
        "delta:tool-use-id:\"Sparkle Day\"}",
        "end:tool-use-id"
    ])
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

@Test func amazonBedrockRerankingUsesAgentRuntimeShapeAndNestedOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"results":[{"index":1,"relevanceScore":0.81},{"index":0,"relevanceScore":0.42}]}
    """))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-west-2",
        apiKey: "bearer-key",
        transport: transport
    ))
    let model = try provider.rerankingModel("cohere.rerank-v3-5:0")

    let result = try await model.rerank(RerankingRequest(
        query: "rainy day",
        documents: ["sunny beach", "rainy city"],
        topK: 2,
        extraBody: [
            "amazonBedrock": .object([
                "nextToken": .string("token-1"),
                "additionalModelRequestFields": .object(["truncate": .string("END")])
            ])
        ]
    ))

    #expect(result.results.map(\.index) == [1, 0])
    #expect(result.results.map(\.score) == [0.81, 0.42])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://bedrock-agent-runtime.us-west-2.amazonaws.com/rerank")
    #expect(request.headers["Authorization"] == "Bearer bearer-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["nextToken"]?.stringValue == "token-1")
    #expect(body["queries"]?[0]?["textQuery"]?["text"]?.stringValue == "rainy day")
    #expect(body["sources"]?[0]?["inlineDocumentSource"]?["textDocument"]?["text"]?.stringValue == "sunny beach")
    #expect(body["sources"]?[1]?["inlineDocumentSource"]?["textDocument"]?["text"]?.stringValue == "rainy city")
    let rerankingConfig = body["rerankingConfiguration"]
    #expect(rerankingConfig?["type"]?.stringValue == "BEDROCK_RERANKING_MODEL")
    let bedrockConfig = rerankingConfig?["amazonBedrockRerankingConfiguration"]
    #expect(bedrockConfig?["numberOfResults"]?.intValue == 2)
    #expect(bedrockConfig?["modelConfiguration"]?["modelArn"]?.stringValue == "arn:aws:bedrock:us-west-2::foundation-model/cohere.rerank-v3-5:0")
    #expect(bedrockConfig?["modelConfiguration"]?["additionalModelRequestFields"]?["truncate"]?.stringValue == "END")
    #expect(rerankingConfig?["bedrockRerankingConfiguration"] == nil)
    #expect(body["amazonBedrock"] == nil)
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
