import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicRequestUsesMessagesEndpointAndHeaders() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"bonjour"}],"stop_reason":"end_turn","usage":{"input_tokens":4,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-5-haiku-latest")

    #expect(model.providerID == "anthropic.messages")
    let result = try await model.generate(LanguageModelRequest(messages: [.system("French."), .user("Hi")]))

    #expect(result.text == "bonjour")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.anthropic.com/v1/messages")
    #expect(request.headers["x-api-key"] == "claude-key")
    #expect(request.headers["anthropic-version"] == "2023-06-01")
    #expect(request.headers["user-agent"] == "ai-sdk/anthropic/3.0.84")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["system"]?.stringValue == "French.")
    #expect(body["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
}
@Test func anthropicAppendsVersionedUserAgentToCustomHeader() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "claude-key",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: transport
    ))
    let model = try provider.languageModel("claude-3-5-haiku-latest")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    let request = try #require(await transport.requests().first)
    #expect(request.headers["x-api-key"] == "claude-key")
    #expect(request.headers["user-agent"] == "CustomApp/1.0 ai-sdk/anthropic/3.0.84")
}
@Test func anthropicAuthTokenBaseURLAndCustomProviderNameMirrorUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"custom"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(
        authToken: "auth-token",
        baseURL: "https://anthropic-proxy.example.com/v1/",
        transport: transport,
        name: "custom-anthropic.messages"
    ))
    let model = try provider.languageModel("claude-sonnet-4-6")

    #expect(model.providerID == "custom-anthropic.messages")
    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        providerOptions: [
            "anthropic": [
                "metadata": ["userId": "canonical-user"]
            ],
            "custom-anthropic": [
                "metadata": ["userId": "custom-user"],
                "anthropicBeta": ["custom-beta-2026-01-01"]
            ]
        ]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://anthropic-proxy.example.com/v1/messages")
    #expect(request.headers["authorization"] == "Bearer auth-token")
    #expect(request.headers["x-api-key"] == nil)
    #expect(request.headers["anthropic-beta"]?.contains("custom-beta-2026-01-01") == true)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["metadata"]?["user_id"]?.stringValue == "custom-user")
}
@Test func anthropicRejectsExplicitAPIKeyAndAuthTokenLikeUpstream() throws {
    #expect(throws: AIError.invalidArgument(
        argument: "apiKey/authToken",
        message: "Both apiKey and authToken were provided. Please use only one authentication method."
    )) {
        _ = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", authToken: "auth-token"))
    }
}
@Test func anthropicMessagesAliasUsesMessagesModel() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"alias"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.messages("claude-3-5-haiku-latest")

    #expect(model.providerID == "anthropic.messages")
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

    #expect(model.providerID == "anthropic-aws.messages")
    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))

    #expect(result.text == "aws claude")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://aws-external-anthropic.us-west-2.api.aws/v1/messages")
    #expect(request.headers["x-api-key"] == "aws-api-key")
    #expect(request.headers["anthropic-workspace-id"] == "wrkspc_test")
    #expect(request.headers["anthropic-version"] == "2023-06-01")
    #expect(request.headers["user-agent"] == "ai-sdk/anthropic-aws/1.0.6")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "claude-sonnet-4-6")
    #expect(body["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
}
@Test func anthropicAWSAppendsVersionedUserAgentToCustomHeader() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"aws custom"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
    """))
    let provider = try AIProviders.anthropicAWS(settings: AnthropicAWSProviderSettings(
        region: "us-west-2",
        workspaceID: "wrkspc_test",
        apiKey: "aws-api-key",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: transport
    ))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))

    let request = try #require(await transport.requests().first)
    #expect(request.headers["x-api-key"] == "aws-api-key")
    #expect(request.headers["user-agent"] == "CustomApp/1.0 ai-sdk/anthropic-aws/1.0.6")
}
@Test func anthropicAWSAPIKeyOverridesCustomXAPIKeyLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"aws auth"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
    """))
    let provider = try AIProviders.anthropicAWS(settings: AnthropicAWSProviderSettings(
        region: "us-west-2",
        workspaceID: "wrkspc_test",
        apiKey: "aws-api-key",
        headers: ["x-api-key": "custom-key"],
        transport: transport
    ))
    let model = try provider.chat("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))

    let request = try #require(await transport.requests().first)
    #expect(request.headers["x-api-key"] == "aws-api-key")
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
    #expect(request.headers["user-agent"] == "ai-sdk/anthropic-aws/1.0.6")
}
@Test func anthropicAWSSupportsDynamicCredentialProviderLikeUpstream() async throws {
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
    {"content":[{"type":"text","text":"dynamic"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
    """))
    let provider = try AIProviders.anthropicAWS(settings: AnthropicAWSProviderSettings(
        region: "us-west-2",
        workspaceID: "wrkspc_test",
        credentialProvider: {
            AnthropicAWSCredentials(
                accessKeyID: "DYNAMICACCESS",
                secretAccessKey: "dynamicSecret",
                sessionToken: "dynamic-session"
            )
        },
        transport: transport,
        date: { fixedDate }
    ))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))

    let request = try #require(await transport.requests().first)
    #expect(request.headers["authorization"]?.contains("Credential=DYNAMICACCESS/20240315/us-west-2/aws-external-anthropic/aws4_request") == true)
    #expect(request.headers["x-amz-security-token"] == "dynamic-session")
}
@Test func anthropicAWSRejectsUnsupportedModelFamiliesLikeUpstream() throws {
    let provider = try AIProviders.anthropicAWS(settings: AnthropicAWSProviderSettings(
        region: "us-west-2",
        workspaceID: "wrkspc_test",
        apiKey: "aws-api-key",
        transport: RecordingTransport(response: jsonResponse("{}"))
    ))

    #expect(throws: AIError.unsupportedModel(provider: "anthropic-aws", capability: .embedding, modelID: "embed")) {
        _ = try provider.embeddingModel("embed")
    }
    #expect(throws: AIError.unsupportedModel(provider: "anthropic-aws", capability: .embedding, modelID: "embed")) {
        _ = try provider.textEmbeddingModel("embed")
    }
    #expect(throws: AIError.unsupportedModel(provider: "anthropic-aws", capability: .image, modelID: "image")) {
        _ = try provider.imageModel("image")
    }
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
    #expect(result.warnings.contains {
        $0.type == "compatibility" && $0.feature == "extended thinking"
    })
    #expect(result.warnings.contains {
        $0.type == "unsupported" && $0.feature == "temperature" && $0.message == "temperature is not supported when thinking is enabled"
    })
    #expect(result.warnings.contains {
        $0.type == "unsupported" && $0.feature == "topK" && $0.message == "topK is not supported when thinking is enabled"
    })
    #expect(result.warnings.contains {
        $0.type == "unsupported" && $0.feature == "topP" && $0.message == "topP is not supported when thinking is enabled"
    })
}

@Test func anthropicRequestMapsFallbacksBetaStopDetailsAndFallbackUsage() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "content": [
        {"type":"fallback","message":"primary failed"},
        {"type":"text","text":"served by fallback"}
      ],
      "stop_reason": "end_turn",
      "stop_details": {"type":"model_context_window_exceeded","recommended_model":"claude-fable-5"},
      "usage": {
        "input_tokens": 11,
        "output_tokens": 7,
        "iterations": [
          {"type":"message","model":"claude-sonnet-4-6","input_tokens":100,"output_tokens":50},
          {"type":"fallback_message","model":"claude-fable-5","input_tokens":11,"output_tokens":7}
        ]
      }
    }
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        providerOptions: [
            "anthropic": [
                "fallbacks": [
                    ["model": "claude-fable-5"]
                ]
            ]
        ]
    ))

    #expect(result.text == "served by fallback")
    #expect(result.usage?.inputTokens == 11)
    #expect(result.usage?.outputTokens == 7)
    #expect(result.providerMetadata["anthropic"]?["stopDetails"]?["recommendedModel"]?.stringValue == "claude-fable-5")
    #expect(result.providerMetadata["anthropic"]?["iterations"]?[1]?["type"]?.stringValue == "fallback_message")
    #expect(result.providerMetadata["anthropic"]?["iterations"]?[1]?["model"]?.stringValue == "claude-fable-5")
    let request = try #require(await transport.requests().first)
    #expect(request.headers["anthropic-beta"]?.contains("server-side-fallback-2026-06-01") == true)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["fallbacks"]?[0]?["model"]?.stringValue == "claude-fable-5")
}

@Test func anthropicRequestWarnsAndOmitsUnsupportedStandardSettingsLikeUpstream() async throws {
    let schema: JSONValue = [
        "type": "object",
        "properties": [
            "answer": ["type": "string"]
        ],
        "required": ["answer"]
    ]
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"{\\"answer\\":\\"ok\\"}"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Return JSON.")],
        temperature: 1.4,
        topP: 0.8,
        topK: 12,
        presencePenalty: 0.1,
        frequencyPenalty: 0.2,
        seed: 42,
        responseFormat: .json(schema: schema),
        extraBody: [
            "responseFormat": ["type": "json", "schema": schema]
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["temperature"]?.doubleValue == 1)
    #expect(body["top_p"] == nil)
    #expect(body["top_k"]?.intValue == 12)
    #expect(body["presence_penalty"] == nil)
    #expect(body["frequency_penalty"] == nil)
    #expect(body["seed"] == nil)
    #expect(body["responseFormat"] == nil)
    #expect(body["output_config"]?["format"]?["type"]?.stringValue == "json_schema")
    #expect(body["output_config"]?["format"]?["schema"]?["properties"]?["answer"]?["type"]?.stringValue == "string")
    #expect(result.warnings.contains(AIWarning(type: "unsupported", feature: "frequencyPenalty")))
    #expect(result.warnings.contains(AIWarning(type: "unsupported", feature: "presencePenalty")))
    #expect(result.warnings.contains(AIWarning(type: "unsupported", feature: "seed")))
    #expect(result.warnings.contains {
        $0.type == "unsupported" && $0.feature == "temperature" && $0.message == "1.4 exceeds anthropic maximum of 1.0. clamped to 1.0"
    })
    #expect(result.warnings.contains {
        $0.type == "unsupported" && $0.feature == "topP" && $0.message == "topP is not supported when temperature is set. topP is ignored."
    })
}
@Test func anthropicRequestWarnsWhenSchemaLessJSONResponseFormatIsIgnored() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":1}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Return JSON.")],
        responseFormat: .json()
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["output_config"]?["format"] == nil)
    #expect(result.warnings.contains {
        $0.type == "unsupported" && $0.feature == "responseFormat" && $0.message == "JSON response format requires a schema. The response format is ignored."
    })
}
