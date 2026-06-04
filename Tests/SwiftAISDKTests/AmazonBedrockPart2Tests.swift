import Foundation
import Testing
@testable import SwiftAISDK

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
    #expect(request.headers["user-agent"] == "ai-sdk/amazon-bedrock/4.0.112")
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
@Test func amazonBedrockAnthropicDownloadsURLContentAndPreservesMetadata() async throws {
    let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
    let transport = RecordingTransport(responses: [
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png; charset=binary"], body: imageData),
        jsonResponse("""
        {"id":"msg-bedrock","model":"anthropic.claude-3-haiku-20240307-v1:0","content":[{"type":"text","text":"image ok"}],"stop_reason":"end_turn","usage":{"input_tokens":7,"output_tokens":3}}
        """, headers: ["x-amzn-requestid": "bedrock-response-id"])
    ])
    let provider = try AIProviders.amazonBedrockAnthropic(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: transport
    ))
    let model = try provider.messages("anthropic.claude-3-haiku-20240307-v1:0")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .text("Describe it"),
            .imageURL("https://assets.example.com/cat.png")
        ])
    ]))

    #expect(result.text == "image ok")
    #expect(result.responseMetadata.id == "msg-bedrock")
    #expect(result.providerMetadata["bedrock.anthropic"]?["usage"]?["input_tokens"]?.intValue == 7)
    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].method == "GET")
    #expect(requests[0].url.absoluteString == "https://assets.example.com/cat.png")
    #expect(requests[1].url.absoluteString == "https://bedrock-runtime.us-east-1.amazonaws.com/model/anthropic.claude-3-haiku-20240307-v1%3A0/invoke")
    let body = try decodeJSONBody(try #require(requests[1].body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content[0]["text"]?.stringValue == "Describe it")
    #expect(content[1]["type"]?.stringValue == "image")
    #expect(content[1]["source"]?["type"]?.stringValue == "base64")
    #expect(content[1]["source"]?["media_type"]?.stringValue == "image/png")
    #expect(content[1]["source"]?["data"]?.stringValue == imageData.base64EncodedString())
}
@Test func amazonBedrockAnthropicOmitsStructuredOutputForUnsupportedOpusModels() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"json-ish"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.amazonBedrockAnthropic(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: transport
    ))
    let model = try provider.messages("anthropic.claude-opus-4-7")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Return JSON")],
        responseFormat: .json(schema: .object([
            "type": .string("object"),
            "properties": .object(["answer": .object(["type": .string("string")])])
        ]))
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["output_config"]?["format"] == nil)
    #expect(result.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "responseFormat",
        message: "Bedrock Anthropic does not support native structured output for anthropic.claude-opus-4-7. The response format is ignored."
    )))
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
    #expect(request.headers["user-agent"] == "ai-sdk/amazon-bedrock/4.0.112")
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
