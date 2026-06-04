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
    #expect(request.headers["user-agent"] == "ai-sdk/amazon-bedrock/4.0.112")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["system"]?[0]?["text"]?.stringValue == "Brief.")
    #expect(body["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
    #expect(body["inferenceConfig"]?["temperature"]?.doubleValue == 1)
}
@Test func amazonBedrockAppendsVersionedUserAgentToCustomHeaders() async throws {
    let converseTransport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[{"text":"bedrock"}]}},"stopReason":"end_turn","usage":{"inputTokens":1,"outputTokens":1,"totalTokens":2}}
    """))
    let converseProvider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: converseTransport
    ))
    _ = try await converseProvider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")
        .generate(LanguageModelRequest(messages: [.user("Hi")]))

    let anthropicTransport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"anthropic"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
    """))
    let anthropicProvider = try AIProviders.amazonBedrockAnthropic(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: anthropicTransport
    ))
    _ = try await anthropicProvider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")
        .generate(LanguageModelRequest(messages: [.user("Hi")]))

    let mantleTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"mantle"},"finish_reason":"stop"}],"usage":{"total_tokens":2}}
    """))
    let mantleProvider = try AIProviders.bedrockMantle(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "mantle-key",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: mantleTransport
    ))
    _ = try await mantleProvider.languageModel("openai.gpt-oss-20b")
        .generate(LanguageModelRequest(messages: [.user("Hi")]))

    let converseRequest = try #require(await converseTransport.requests().first)
    let anthropicRequest = try #require(await anthropicTransport.requests().first)
    let mantleRequest = try #require(await mantleTransport.requests().first)
    #expect(converseRequest.headers["user-agent"] == "CustomApp/1.0 ai-sdk/amazon-bedrock/4.0.112")
    #expect(anthropicRequest.headers["user-agent"] == "CustomApp/1.0 ai-sdk/amazon-bedrock/4.0.112")
    #expect(mantleRequest.headers["user-agent"] == "CustomApp/1.0 ai-sdk/amazon-bedrock/4.0.112")
}
@Test func amazonBedrockCredentialProviderSignsAllProviderSurfaces() async throws {
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

    let converseTransport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[{"text":"bedrock"}]}},"stopReason":"end_turn","usage":{"inputTokens":1,"outputTokens":1,"totalTokens":2}}
    """))
    let converseProvider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        credentialProvider: {
            AmazonBedrockCredentials(accessKeyID: "DYNAMIC-CONVERSE", secretAccessKey: "secret", sessionToken: "session-converse")
        },
        transport: converseTransport,
        date: { fixedDate }
    ))
    _ = try await converseProvider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")
        .generate(LanguageModelRequest(messages: [.user("Hi")]))

    let anthropicTransport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"anthropic"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
    """))
    let anthropicProvider = try AIProviders.amazonBedrockAnthropic(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        credentialProvider: {
            AmazonBedrockCredentials(accessKeyID: "DYNAMIC-ANTHROPIC", secretAccessKey: "secret", sessionToken: "session-anthropic")
        },
        transport: anthropicTransport,
        date: { fixedDate }
    ))
    _ = try await anthropicProvider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")
        .generate(LanguageModelRequest(messages: [.user("Hi")]))

    let mantleTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"mantle"},"finish_reason":"stop"}],"usage":{"total_tokens":2}}
    """))
    let mantleProvider = try AIProviders.bedrockMantle(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        credentialProvider: {
            AmazonBedrockCredentials(accessKeyID: "DYNAMIC-MANTLE", secretAccessKey: "secret", sessionToken: "session-mantle")
        },
        transport: mantleTransport,
        date: { fixedDate }
    ))
    _ = try await mantleProvider.languageModel("openai.gpt-oss-20b")
        .generate(LanguageModelRequest(messages: [.user("Hi")]))

    let converseRequest = try #require(await converseTransport.requests().first)
    let anthropicRequest = try #require(await anthropicTransport.requests().first)
    let mantleRequest = try #require(await mantleTransport.requests().first)
    #expect(converseRequest.headers["authorization"]?.contains("Credential=DYNAMIC-CONVERSE/20240315/us-east-1/bedrock/aws4_request") == true)
    #expect(converseRequest.headers["x-amz-security-token"] == "session-converse")
    #expect(anthropicRequest.headers["authorization"]?.contains("Credential=DYNAMIC-ANTHROPIC/20240315/us-east-1/bedrock/aws4_request") == true)
    #expect(anthropicRequest.headers["x-amz-security-token"] == "session-anthropic")
    #expect(mantleRequest.headers["authorization"]?.contains("Credential=DYNAMIC-MANTLE/20240315/us-east-1/bedrock-mantle/aws4_request") == true)
    #expect(mantleRequest.headers["x-amz-security-token"] == "session-mantle")
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
@Test func amazonBedrockConverseMapsNativeToolsToolChoiceAndProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[{"text":"tool ready"}]}},"stopReason":"end_turn","usage":{"inputTokens":2,"outputTokens":1,"totalTokens":3}}
    """))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        accessKeyID: "AKIDEXAMPLE",
        secretAccessKey: "secret",
        transport: transport
    ))
    let model = try provider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Use weather.")],
        topK: 12,
        tools: [
            "weather": [
                "type": "object",
                "description": "Look up weather.",
                "properties": ["city": ["type": "string"]],
                "required": ["city"]
            ],
            "unused": [
                "type": "object",
                "properties": [:]
            ]
        ],
        toolChoice: ["type": "tool", "toolName": "weather"],
        providerOptions: [
            "amazonBedrock": [
                "serviceTier": "priority",
                "additionalModelRequestFields": ["custom": "value"]
            ]
        ]
    ))

    #expect(result.text == "tool ready")
    #expect(result.warnings.isEmpty)
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["inferenceConfig"]?["topK"]?.intValue == 12)
    #expect(body["serviceTier"]?["type"]?.stringValue == "priority")
    #expect(body["additionalModelRequestFields"]?["custom"]?.stringValue == "value")
    let tools = try #require(body["toolConfig"]?["tools"]?.arrayValue)
    #expect(tools.count == 1)
    #expect(tools[0]["toolSpec"]?["name"]?.stringValue == "weather")
    #expect(tools[0]["toolSpec"]?["description"]?.stringValue == "Look up weather.")
    #expect(tools[0]["toolSpec"]?["inputSchema"]?["json"]?["properties"]?["city"]?["type"]?.stringValue == "string")
    #expect(body["toolConfig"]?["toolChoice"]?["tool"]?["name"]?.stringValue == "weather")
    #expect(body["amazonBedrock"] == nil)
}
@Test func amazonBedrockConverseMapsReasoningConfigLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[{"text":"thinking done"}]}},"stopReason":"end_turn","usage":{"inputTokens":2,"outputTokens":1,"totalTokens":3}}
    """))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        accessKeyID: "AKIDEXAMPLE",
        secretAccessKey: "secret",
        transport: transport
    ))
    let model = try provider.languageModel("anthropic.claude-3-7-sonnet-20250219-v1:0")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Think.")],
        temperature: 0.5,
        topP: 0.9,
        topK: 50,
        maxOutputTokens: 1000,
        providerOptions: [
            "amazonBedrock": [
                "reasoningConfig": [
                    "type": "enabled",
                    "budgetTokens": 200,
                    "maxReasoningEffort": "high"
                ]
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["inferenceConfig"]?["maxTokens"]?.intValue == 1200)
    #expect(body["inferenceConfig"]?["temperature"] == nil)
    #expect(body["inferenceConfig"]?["topP"] == nil)
    #expect(body["inferenceConfig"]?["topK"] == nil)
    #expect(body["additionalModelRequestFields"]?["thinking"]?["type"]?.stringValue == "enabled")
    #expect(body["additionalModelRequestFields"]?["thinking"]?["budget_tokens"]?.intValue == 200)
    #expect(body["additionalModelRequestFields"]?["output_config"]?["effort"]?.stringValue == "high")
    #expect(body["reasoningConfig"] == nil)
    #expect(result.warnings.contains(AIWarning(type: "unsupported", feature: "temperature", message: "temperature is not supported when thinking is enabled")))
    #expect(result.warnings.contains(AIWarning(type: "unsupported", feature: "topP", message: "topP is not supported when thinking is enabled")))
    #expect(result.warnings.contains(AIWarning(type: "unsupported", feature: "topK", message: "topK is not supported when thinking is enabled")))
}
@Test func amazonBedrockConverseMapsJSONResponseFormatThroughToolLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[{"toolUse":{"toolUseId":"json-tool","name":"json","input":{"answer":"ok"}}}]}},"stopReason":"tool_use","usage":{"inputTokens":2,"outputTokens":1,"totalTokens":3}}
    """))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bearer-key",
        transport: transport
    ))
    let schema: JSONValue = [
        "type": "object",
        "properties": ["answer": ["type": "string"]],
        "required": ["answer"]
    ]
    let model = try provider.languageModel("cohere.command-r-v1:0")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Reply as JSON")],
        presencePenalty: 0.5,
        frequencyPenalty: 0.5,
        seed: 42,
        responseFormat: .json(schema: schema)
    ))

    #expect(try decodeJSONBody(Data(result.text.utf8))["answer"]?.stringValue == "ok")
    #expect(result.finishReason == "stop")
    #expect(result.toolCalls.isEmpty)
    #expect(result.providerMetadata["amazonBedrock"]?["isJsonResponseFromTool"]?.boolValue == true)
    #expect(result.warnings.contains(AIWarning(type: "unsupported", feature: "frequencyPenalty")))
    #expect(result.warnings.contains(AIWarning(type: "unsupported", feature: "presencePenalty")))
    #expect(result.warnings.contains(AIWarning(type: "unsupported", feature: "seed")))
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["toolConfig"]?["tools"]?[0]?["toolSpec"]?["name"]?.stringValue == "json")
    #expect(body["toolConfig"]?["tools"]?[0]?["toolSpec"]?["inputSchema"]?["json"] == schema)
    #expect(body["toolConfig"]?["toolChoice"]?["any"] != nil)
}
@Test func amazonBedrockConverseUsesNativeStructuredOutputForAnthropicThinking() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[{"text":"ok"}]}},"stopReason":"end_turn","usage":{"inputTokens":2,"outputTokens":1,"totalTokens":3}}
    """))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bearer-key",
        transport: transport
    ))
    let schema: JSONValue = [
        "type": "object",
        "properties": ["answer": ["type": "string"]]
    ]
    let model = try provider.languageModel("anthropic.claude-3-7-sonnet-20250219-v1:0")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Reply as JSON")],
        maxOutputTokens: 10,
        responseFormat: .json(schema: schema),
        providerOptions: ["bedrock": ["reasoningConfig": ["type": "enabled", "budgetTokens": 8]]]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["toolConfig"] == nil)
    let outputConfig = body["additionalModelRequestFields"]?["output_config"]
    #expect(outputConfig?["format"]?["type"]?.stringValue == "json_schema")
    #expect(outputConfig?["format"]?["schema"] == schema)
    #expect(body["additionalModelRequestFields"]?["thinking"]?["type"]?.stringValue == "enabled")
}
@Test func amazonBedrockConverseMapsReasoningEffortForOpenAIAndNovaModels() async throws {
    let openAITransport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[{"text":"openai"}]}},"stopReason":"end_turn"}
    """))
    let openAIProvider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        accessKeyID: "AKIDEXAMPLE",
        secretAccessKey: "secret",
        transport: openAITransport
    ))
    let openAIModel = try openAIProvider.languageModel("openai.gpt-oss-120b-1:0")
    _ = try await openAIModel.generate(LanguageModelRequest(
        messages: [.user("Think.")],
        providerOptions: ["bedrock": ["reasoningConfig": ["maxReasoningEffort": "medium"]]]
    ))
    let openAIBody = try decodeJSONBody(try #require((await openAITransport.requests()).first?.body))
    #expect(openAIBody["additionalModelRequestFields"]?["reasoning_effort"]?.stringValue == "medium")

    let novaTransport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[{"text":"nova"}]}},"stopReason":"end_turn"}
    """))
    let novaProvider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        accessKeyID: "AKIDEXAMPLE",
        secretAccessKey: "secret",
        transport: novaTransport
    ))
    let novaModel = try novaProvider.languageModel("us.amazon.nova-pro-v1:0")
    let novaResult = try await novaModel.generate(LanguageModelRequest(
        messages: [.user("Think.")],
        providerOptions: ["amazonBedrock": ["reasoningConfig": ["type": "enabled", "budgetTokens": 64, "maxReasoningEffort": "low"]]]
    ))
    let novaBody = try decodeJSONBody(try #require((await novaTransport.requests()).first?.body))
    #expect(novaBody["additionalModelRequestFields"]?["reasoningConfig"]?["type"]?.stringValue == "enabled")
    #expect(novaBody["additionalModelRequestFields"]?["reasoningConfig"]?["budgetTokens"]?.intValue == 64)
    #expect(novaBody["additionalModelRequestFields"]?["reasoningConfig"]?["maxReasoningEffort"]?.stringValue == "low")
    #expect(novaResult.warnings.contains(AIWarning(type: "unsupported", feature: "budgetTokens", message: "budgetTokens applies only to Anthropic models on Bedrock and will be ignored for this model.")))
}
@Test func amazonBedrockLanguageStreamStartCarriesRequestWarnings() async throws {
    let transport = RecordingTransport(response: amazonEventStreamResponse([
        ("contentBlockDelta", #"{"contentBlockIndex":0,"delta":{"text":"ok"}}"#),
        ("messageStop", #"{"stopReason":"end_turn"}"#)
    ]))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        accessKeyID: "AKIDEXAMPLE",
        secretAccessKey: "secret",
        transport: transport
    ))
    let model = try provider.languageModel("anthropic.claude-3-7-sonnet-20250219-v1:0")

    var startWarnings: [AIWarning] = []
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Think.")],
        temperature: 0.5,
        providerOptions: ["amazonBedrock": ["reasoningConfig": ["type": "adaptive", "display": "summarized"]]]
    )) {
        if case let .streamStart(warnings) = part {
            startWarnings = warnings
        }
    }

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["additionalModelRequestFields"]?["thinking"]?["type"]?.stringValue == "adaptive")
    #expect(body["additionalModelRequestFields"]?["thinking"]?["display"]?.stringValue == "summarized")
    #expect(startWarnings.contains(AIWarning(type: "unsupported", feature: "temperature", message: "temperature is not supported when thinking is enabled")))
}
