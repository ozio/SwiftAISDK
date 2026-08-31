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
    #expect(request.headers["user-agent"] == "ai-sdk/amazon-bedrock/5.0.68")
    #expect(request.headers["anthropic-beta"] == nil)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"] == nil)
    #expect(body["stream"] == nil)
    #expect(body["anthropic_version"]?.stringValue == "bedrock-2023-05-31")
    #expect(body["system"] == [["type": "text", "text": "Brief."]])
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
@Test func amazonBedrockAnthropicDetectsDownloadedGenericImageMediaTypeLikeUpstream() async throws {
    let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
    let transport = RecordingTransport(responses: [
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "application/octet-stream"], body: imageData),
        jsonResponse(#"{"content":[{"type":"text","text":"image ok"}],"stop_reason":"end_turn"}"#)
    ])
    let provider = try AIProviders.amazonBedrockAnthropic(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: transport
    ))
    let model = try provider.messages("anthropic.claude-3-haiku-20240307-v1:0")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .imageURL("https://assets.example.com/generic")
        ])
    ]))

    let requests = await transport.requests()
    #expect(requests.count == 2)
    let body = try decodeJSONBody(try #require(requests[1].body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content[0]["type"]?.stringValue == "image")
    #expect(content[0]["source"]?["media_type"]?.stringValue == "image/png")
    #expect(content[0]["source"]?["data"]?.stringValue == imageData.base64EncodedString())
}
@Test func amazonBedrockAnthropicResolvesDataURLContentWithoutNetworkDownloadLikeUpstream() async throws {
    let imageData = Data([0x89, 0x50, 0x4E, 0x47])
    let dataURL = "data:image/png;base64,\(imageData.base64EncodedString())"
    let transport = RecordingTransport(response: jsonResponse(#"{"content":[{"type":"text","text":"image ok"}],"stop_reason":"end_turn"}"#))
    let provider = try AIProviders.amazonBedrockAnthropic(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: transport
    ))
    let model = try provider.messages("anthropic.claude-3-haiku-20240307-v1:0")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .imageURL(dataURL)
        ])
    ]))

    let requests = await transport.requests()
    #expect(requests.count == 1)
    let body = try decodeJSONBody(try #require(requests[0].body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content[0]["type"]?.stringValue == "image")
    #expect(content[0]["source"]?["media_type"]?.stringValue == "image/png")
    #expect(content[0]["source"]?["data"]?.stringValue == imageData.base64EncodedString())
}
@Test func amazonBedrockAnthropicUsesJSONToolForModelsWithoutNativeStructuredOutput() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
    {"content":[{"type":"tool_use","id":"json-1","name":"json","input":{"answer":"opus"}}],"stop_reason":"tool_use","usage":{"input_tokens":3,"output_tokens":2}}
    """),
        jsonResponse("""
    {"content":[{"type":"tool_use","id":"json-2","name":"json","input":{"answer":"fable"}}],"stop_reason":"tool_use","usage":{"input_tokens":3,"output_tokens":2}}
    """)
    ])
    let provider = try AIProviders.amazonBedrockAnthropic(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: transport
    ))
    let opus = try provider.messages("anthropic.claude-opus-4-7")
    let fable = try provider.messages("anthropic.claude-fable-5-20260601-v1:0")

    let opusResult = try await opus.generate(LanguageModelRequest(
        messages: [.user("Return JSON")],
        responseFormat: .json(schema: .object([
            "type": .string("object"),
            "properties": .object(["answer": .object(["type": .string("string")])])
        ])),
        tools: [
            "weather": [
                "type": "object",
                "strict": true,
                "properties": ["city": ["type": "string"]]
            ]
        ]
    ))
    let fableResult = try await fable.generate(LanguageModelRequest(
        messages: [.user("Return JSON")],
        responseFormat: .json(schema: .object([
            "type": .string("object"),
            "properties": .object(["answer": .object(["type": .string("string")])])
        ])),
        tools: [
            "weather": [
                "type": "object",
                "strict": true,
                "properties": ["city": ["type": "string"]]
            ]
        ]
    ))

    let requests = await transport.requests()
    let opusBody = try decodeJSONBody(try #require(requests.first?.body))
    let fableBody = try decodeJSONBody(try #require(requests.last?.body))
    #expect(opusBody["output_config"]?["format"] == nil)
    #expect(fableBody["output_config"]?["format"] == nil)
    #expect(opusBody["tools"]?.arrayValue?.contains { $0["name"]?.stringValue == "json" } == true)
    #expect(fableBody["tools"]?.arrayValue?.contains { $0["name"]?.stringValue == "json" } == true)
    let opusWeatherTool = opusBody["tools"]?.arrayValue?.first { $0["name"]?.stringValue == "weather" }
    let fableWeatherTool = fableBody["tools"]?.arrayValue?.first { $0["name"]?.stringValue == "weather" }
    #expect(opusWeatherTool?["strict"] == nil)
    #expect(fableWeatherTool?["strict"] == nil)
    #expect(opusBody["tool_choice"]?["type"]?.stringValue == "any")
    #expect(fableBody["tool_choice"]?["type"]?.stringValue == "any")
    #expect(try decodeJSONBody(Data(opusResult.text.utf8))["answer"]?.stringValue == "opus")
    #expect(try decodeJSONBody(Data(fableResult.text.utf8))["answer"]?.stringValue == "fable")
    #expect(!opusResult.warnings.contains { $0.feature == "responseFormat" })
    #expect(!fableResult.warnings.contains { $0.feature == "responseFormat" })
    #expect(opusResult.warnings.contains { $0.feature == "strict" })
    #expect(fableResult.warnings.contains { $0.feature == "strict" })
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
        if case let .textDeltaPart(_, delta, _) = part {
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
    #expect(request.headers["user-agent"] == "ai-sdk/amazon-bedrock/5.0.68")
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

@Test func amazonBedrockConverseGeneratesDistinctToolCallIDsWhenToolUseIDsAreEmpty() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[
      {"toolUse":{"toolUseId":"","name":"first","input":{"value":1}}},
      {"toolUse":{"toolUseId":"","name":"second","input":{"value":2}}}
    ]}},"stopReason":"tool_use","usage":{"inputTokens":1,"outputTokens":1,"totalTokens":2}}
    """))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: transport
    ))
    let model = try provider.languageModel("us.openai.gpt-5.6-luna")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Use tools.")]))
    let ids = result.toolCalls.map(\.id)

    #expect(ids.count == 2)
    #expect(ids.allSatisfy { !$0.isEmpty })
    #expect(Set(ids).count == 2)
}

@Test func amazonBedrockConverseSurfacesRedactedContentForReplay() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[
      {"reasoningContent":{"redactedContent":"encrypted-reasoning-payload"}},
      {"text":"The answer is 42."}
    ]}},"stopReason":"end_turn","usage":{"inputTokens":4,"outputTokens":34,"totalTokens":38}}
    """))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: transport
    ))
    let model = try provider.languageModel("us.openai.gpt-5.6-luna")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Think.")]))

    #expect(result.text == "The answer is 42.")
    #expect(result.content.count == 2)
    guard case let .reasoning(reasoning, metadata) = result.content[0],
          case let .text(text, _) = result.content[1] else {
        Issue.record("Expected redacted reasoning followed by text.")
        return
    }
    #expect(reasoning.isEmpty)
    #expect(text == "The answer is 42.")
    #expect(metadata["amazonBedrock"]?["redactedContent"]?.stringValue == "encrypted-reasoning-payload")
    #expect(metadata["bedrock"] == metadata["amazonBedrock"])
}

@Test func amazonBedrockConverseReplaysRedactedContentMetadata() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[{"text":"restored"}]}},"stopReason":"end_turn","usage":{"inputTokens":1,"outputTokens":1,"totalTokens":2}}
    """))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: transport
    ))
    let model = try provider.languageModel("us.openai.gpt-5.6-luna")
    let redactedContent = "encrypted-reasoning-payload"

    _ = try await model.generate(LanguageModelRequest(messages: [
        .user("Explain your reasoning."),
        AIMessage(role: .assistant, content: [
            .reasoning("", providerMetadata: [
                "bedrock": .object(["redactedContent": .string(redactedContent)])
            ])
        ]),
        .user("Continue.")
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["messages"]?[1]?["content"]?[0]?["reasoningContent"]?["redactedContent"]?.stringValue == redactedContent)
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
    #expect(result.content.count == 2)
    guard case let .reasoning(_, reasoningMetadata) = result.content[0] else {
        Issue.record("Expected reasoning content first.")
        return
    }
    #expect(reasoningMetadata["amazonBedrock"]?["signature"]?.stringValue == "sig-1")
    #expect(reasoningMetadata["bedrock"] == reasoningMetadata["amazonBedrock"])
    #expect(result.providerMetadata["amazonBedrock"]?["trace"]?["guardrail"]?["action"]?.stringValue == "NONE")
    #expect(result.providerMetadata["amazonBedrock"]?["performanceConfig"]?["latency"]?.stringValue == "optimized")
    #expect(result.providerMetadata["amazonBedrock"]?["serviceTier"]?.stringValue == "priority")
    #expect(result.providerMetadata["amazonBedrock"]?["usage"]?["cacheWriteInputTokens"]?.intValue == 4)
    #expect(result.providerMetadata["amazonBedrock"]?["usage"]?["cacheDetails"]?["cache"]?.stringValue == "warm")
    #expect(result.providerMetadata["amazonBedrock"]?["stopSequence"]?.stringValue == "END")
    #expect(result.providerMetadata["bedrock"] == result.providerMetadata["amazonBedrock"])
}

@Test func amazonBedrockConversePreservesOrderedContentAndAllReasoningMetadataLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[
      {"text":"before"},
      {"reasoningContent":{"reasoningText":{"text":"think","signature":"sig-ordered"}}},
      {"toolUse":{"toolUseId":"tool-1","name":"lookup","input":{"city":"Tokyo"}}},
      {"reasoningContent":{"redactedReasoning":{"data":"legacy-redacted"}}},
      {"text":"after"},
      {"reasoningContent":{"redactedContent":"current-redacted"}}
    ]}},"stopReason":"tool_use","usage":{"inputTokens":2,"outputTokens":3,"totalTokens":5}}
    """))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: transport
    ))

    let result = try await provider.languageModel("us.openai.gpt-5.6-luna").generate(
        LanguageModelRequest(messages: [.user("Think and use a tool.")])
    )

    #expect(result.text == "beforeafter")
    #expect(result.reasoning == "think")
    #expect(result.toolCalls.count == 1)
    #expect(result.content.count == 6)

    guard case let .text(firstText, _) = result.content[0],
          case let .reasoning(reasoning, signatureMetadata) = result.content[1],
          case let .toolCall(toolCall) = result.content[2],
          case let .reasoning(legacyRedacted, legacyMetadata) = result.content[3],
          case let .text(lastText, _) = result.content[4],
          case let .reasoning(currentRedacted, currentMetadata) = result.content[5] else {
        Issue.record("Expected Bedrock result content to preserve wire order.")
        return
    }
    #expect(firstText == "before")
    #expect(reasoning == "think")
    #expect(signatureMetadata["amazonBedrock"]?["signature"]?.stringValue == "sig-ordered")
    #expect(signatureMetadata["bedrock"] == signatureMetadata["amazonBedrock"])
    #expect(toolCall.id == "tool-1")
    #expect(toolCall.name == "lookup")
    #expect(legacyRedacted.isEmpty)
    #expect(legacyMetadata["amazonBedrock"]?["redactedData"]?.stringValue == "legacy-redacted")
    #expect(legacyMetadata["bedrock"] == legacyMetadata["amazonBedrock"])
    #expect(lastText == "after")
    #expect(currentRedacted.isEmpty)
    #expect(currentMetadata["amazonBedrock"]?["redactedContent"]?.stringValue == "current-redacted")
    #expect(currentMetadata["bedrock"] == currentMetadata["amazonBedrock"])
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
        case let .textDeltaPart(_, delta, _):
            deltas.append(delta)
        case let .finishMetadata(_, usage, _):
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
    var reasoningMetadata: [[String: JSONValue]] = []
    var metadata: [[String: JSONValue]] = []
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Think.")])) {
        switch part {
        case let .reasoningDeltaPart(_, delta, providerMetadata):
            reasoning.append(delta)
            if !providerMetadata.isEmpty {
                reasoningMetadata.append(providerMetadata)
            }
        case let .textDeltaPart(_, delta, _):
            text.append(delta)
        case let .metadata(value):
            metadata.append(value)
        case let .finishMetadata(_, usage, _):
            totalTokens = usage?.totalTokens ?? totalTokens
        default:
            break
        }
    }

    #expect(reasoning.joined() == "think")
    #expect(reasoning == ["think", "", ""])
    #expect(text == ["answer"])
    #expect(reasoningMetadata.contains { $0["amazonBedrock"]?["signature"]?.stringValue == "sig-1" })
    #expect(reasoningMetadata.contains { $0["amazonBedrock"]?["redactedData"]?.stringValue == "redacted-1" })
    let eventMetadata = try #require(metadata.first { $0["amazonBedrock"]?["trace"] != nil })
    #expect(eventMetadata["amazonBedrock"]?["trace"]?["guardrail"]?["action"]?.stringValue == "NONE")
    #expect(eventMetadata["amazonBedrock"]?["performanceConfig"]?["latency"]?.stringValue == "optimized")
    #expect(eventMetadata["amazonBedrock"]?["serviceTier"]?.stringValue == "priority")
    #expect(eventMetadata["amazonBedrock"]?["usage"]?["cacheWriteInputTokens"]?.intValue == 5)
    #expect(eventMetadata["bedrock"] == eventMetadata["amazonBedrock"])
    #expect(totalTokens == 4)
}

@Test func amazonBedrockLanguageAccumulatesAndSeparatesStreamedRedactedContent() async throws {
    let transport = RecordingTransport(response: amazonEventStreamResponse([
        ("contentBlockDelta", #"{"contentBlockIndex":0,"delta":{"reasoningContent":{"redactedContent":"encrypted-reasoning-"}}}"#),
        ("contentBlockDelta", #"{"contentBlockIndex":0,"delta":{"reasoningContent":{"redactedContent":"payload"}}}"#),
        ("contentBlockStop", #"{"contentBlockIndex":0}"#),
        ("contentBlockDelta", #"{"contentBlockIndex":1,"delta":{"reasoningContent":{"redactedContent":"second-payload"}}}"#),
        ("contentBlockStop", #"{"contentBlockIndex":1}"#),
        ("contentBlockDelta", #"{"contentBlockIndex":2,"delta":{"text":"The answer is 42."}}"#),
        ("contentBlockStop", #"{"contentBlockIndex":2}"#),
        ("messageStop", #"{"stopReason":"end_turn"}"#),
        ("metadata", #"{"usage":{"inputTokens":1,"outputTokens":1,"totalTokens":2}}"#)
    ]))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: transport
    ))
    let model = try provider.languageModel("us.openai.gpt-5.6-luna")
    var reasoningStarts: [String] = []
    var reasoningEnds: [String: [String: JSONValue]] = [:]
    var errors: [String] = []

    for try await part in model.stream(LanguageModelRequest(messages: [.user("Think.")])) {
        switch part {
        case let .reasoningStart(id, _):
            reasoningStarts.append(id)
        case let .reasoningEnd(id, metadata):
            reasoningEnds[id] = metadata
        case let .error(message, _):
            errors.append(message)
        default:
            break
        }
    }

    #expect(errors.isEmpty)
    #expect(reasoningStarts == ["0", "1"])
    #expect(reasoningEnds["0"]?["amazonBedrock"]?["redactedContent"]?.stringValue == "encrypted-reasoning-payload")
    #expect(reasoningEnds["0"]?["bedrock"] == reasoningEnds["0"]?["amazonBedrock"])
    #expect(reasoningEnds["1"]?["amazonBedrock"]?["redactedContent"]?.stringValue == "second-payload")
    #expect(reasoningEnds["1"]?["bedrock"] == reasoningEnds["1"]?["amazonBedrock"])
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
        case let .finishMetadata(reason, usage, _):
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
