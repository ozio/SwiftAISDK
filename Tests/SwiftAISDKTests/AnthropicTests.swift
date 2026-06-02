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

@Test func anthropicRequestMapsNestedProviderOptionsAndBetaHeaderLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":1}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "claude-key",
        headers: ["anthropic-beta": "configured-beta"],
        transport: transport
    ))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        providerOptions: [
            "anthropic": [
                "metadata": ["userId": "user-typed"],
                "effort": "xhigh",
                "speed": "fast",
                "taskBudget": ["type": "tokens", "total": 20_000],
                "anthropicBeta": ["my-beta-2025-01-01", "another-beta-2025-06-01"],
                "unsupportedTypedKey": "drop-me"
            ]
        ],
        extraBody: [
            "metadata": ["userId": "raw-user"],
            "anthropicBeta": ["raw-beta-2025-02-02"]
        ],
        headers: ["anthropic-beta": "request-beta"]
    ))

    let request = try #require(await transport.requests().first)
    let betaHeader = try #require(request.headers["anthropic-beta"])
    #expect(betaHeader.contains("configured-beta"))
    #expect(betaHeader.contains("request-beta"))
    #expect(betaHeader.contains("my-beta-2025-01-01"))
    #expect(betaHeader.contains("another-beta-2025-06-01"))
    #expect(betaHeader.contains("raw-beta-2025-02-02"))

    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["metadata"]?["user_id"]?.stringValue == "user-typed")
    #expect(body["output_config"]?["effort"]?.stringValue == "xhigh")
    #expect(body["output_config"]?["task_budget"]?["type"]?.stringValue == "tokens")
    #expect(body["output_config"]?["task_budget"]?["total"]?.intValue == 20_000)
    #expect(body["speed"]?.stringValue == "fast")
    #expect(body["anthropicBeta"] == nil)
    #expect(body["unsupportedTypedKey"] == nil)

    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.anthropic.anthropicBeta[0]",
        message: "Anthropic anthropicBeta values must be strings."
    )) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["anthropic": ["anthropicBeta": [1]]]
        ))
    }
}

@Test func anthropicRequestAddsAutomaticBetaHeadersForOptionFeatures() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":1}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        providerOptions: [
            "anthropic": [
                "mcpServers": [
                    [
                        "type": "url",
                        "name": "docs",
                        "url": "https://mcp.example.com",
                        "toolConfiguration": ["enabled": true]
                    ]
                ],
                "contextManagement": [
                    "edits": [
                        [
                            "type": "compact_20260112",
                            "trigger": ["type": "input_tokens", "value": 100_000]
                        ]
                    ]
                ],
                "container": [
                    "id": "container_123",
                    "skills": [
                        ["type": "anthropic", "skillId": "skill_123", "version": "v1"]
                    ]
                ],
                "taskBudget": ["type": "tokens", "total": 40_000],
                "speed": "fast"
            ]
        ]
    ))

    let request = try #require(await transport.requests().first)
    let betaHeader = try #require(request.headers["anthropic-beta"])
    #expect(betaHeader.contains("mcp-client-2025-04-04"))
    #expect(betaHeader.contains("context-management-2025-06-27"))
    #expect(betaHeader.contains("compact-2026-01-12"))
    #expect(betaHeader.contains("code-execution-2025-08-25"))
    #expect(betaHeader.contains("skills-2025-10-02"))
    #expect(betaHeader.contains("files-api-2025-04-14"))
    #expect(betaHeader.contains("task-budgets-2026-03-13"))
    #expect(betaHeader.contains("fast-mode-2026-02-01"))

    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["mcp_servers"]?[0]?["tool_configuration"]?["enabled"]?.boolValue == true)
    #expect(body["context_management"]?["edits"]?[0]?["type"]?.stringValue == "compact_20260112")
    #expect(body["container"]?["skills"]?[0]?["skill_id"]?.stringValue == "skill_123")
    #expect(body["output_config"]?["task_budget"]?["total"]?.intValue == 40_000)
    #expect(body["speed"]?.stringValue == "fast")
}

@Test func anthropicRequestConvertsProviderReferenceFilesLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":1}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .text("Read these"),
            .providerReference(mimeType: "application/pdf", reference: ["anthropic": "file_pdf", "openai": "file_openai"]),
            .providerReference(mimeType: "image/png", reference: ["anthropic": "file_image"])
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let betaHeader = try #require(request.headers["anthropic-beta"])
    #expect(betaHeader.contains("files-api-2025-04-14"))
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["messages"]?[0]?["content"]?[0]?["type"]?.stringValue == "text")
    #expect(body["messages"]?[0]?["content"]?[1]?["type"]?.stringValue == "document")
    #expect(body["messages"]?[0]?["content"]?[1]?["source"]?["type"]?.stringValue == "file")
    #expect(body["messages"]?[0]?["content"]?[1]?["source"]?["file_id"]?.stringValue == "file_pdf")
    #expect(body["messages"]?[0]?["content"]?[2]?["type"]?.stringValue == "image")
    #expect(body["messages"]?[0]?["content"]?[2]?["source"]?["type"]?.stringValue == "file")
    #expect(body["messages"]?[0]?["content"]?[2]?["source"]?["file_id"]?.stringValue == "file_image")

    let missingProvider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: RecordingTransport(responses: [])))
    let missingModel = try missingProvider.languageModel("claude-sonnet-4-6")
    await #expect(throws: AINoSuchProviderReferenceError(provider: "anthropic", reference: ["xai": "file_xai"])) {
        _ = try await missingModel.generate(LanguageModelRequest(messages: [
            AIMessage(role: .user, content: [
                .providerReference(mimeType: "application/pdf", reference: ["xai": "file_xai"])
            ])
        ]))
    }
}

@Test func anthropicAWSRequestUsesAWSProviderReferenceKeyForUploadedFiles() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"aws"}],"stop_reason":"end_turn","usage":{"input_tokens":2,"output_tokens":1}}
    """))
    let provider = try AIProviders.anthropicAWS(settings: AnthropicAWSProviderSettings(
        region: "us-west-2",
        workspaceID: "wrkspc_test",
        apiKey: "aws-api-key",
        transport: transport
    ))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .providerReference(mimeType: "application/pdf", reference: ["anthropic-aws": "file_aws"])
        ])
    ]))

    let request = try #require(await transport.requests().first)
    #expect(request.headers["anthropic-beta"]?.contains("files-api-2025-04-14") == true)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["messages"]?[0]?["content"]?[0]?["type"]?.stringValue == "document")
    #expect(body["messages"]?[0]?["content"]?[0]?["source"]?["type"]?.stringValue == "file")
    #expect(body["messages"]?[0]?["content"]?[0]?["source"]?["file_id"]?.stringValue == "file_aws")
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

@Test func anthropicLanguageExposesContainerAndContextManagementProviderMetadata() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "id":"msg_123",
      "model":"claude-sonnet-4-6",
      "content":[{"type":"text","text":"metadata"}],
      "stop_reason":"end_turn",
      "stop_sequence":"done",
      "usage":{"input_tokens":100,"output_tokens":50},
      "container":{
        "id":"container_123",
        "expires_at":"2026-06-02T12:00:00Z",
        "skills":[{"type":"anthropic","skill_id":"skill_123","version":"v1"}]
      },
      "context_management":{
        "applied_edits":[{"type":"clear_tool_uses_20250919","cleared_tool_uses":5,"cleared_input_tokens":10000}]
      }
    }
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))
    let metadata = try #require(result.providerMetadata["anthropic"])

    #expect(metadata["usage"]?["input_tokens"]?.intValue == 100)
    #expect(metadata["stopSequence"]?.stringValue == "done")
    #expect(metadata["container"]?["id"]?.stringValue == "container_123")
    #expect(metadata["container"]?["expiresAt"]?.stringValue == "2026-06-02T12:00:00Z")
    #expect(metadata["container"]?["skills"]?[0]?["skillId"]?.stringValue == "skill_123")
    #expect(metadata["contextManagement"]?["appliedEdits"]?[0]?["clearedToolUses"]?.intValue == 5)
    #expect(metadata["contextManagement"]?["appliedEdits"]?[0]?["clearedInputTokens"]?.intValue == 10000)
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
    #expect(result.toolResults.count == 1)
    #expect(result.toolResults[0].toolCallID == "srvtoolu_1")
    #expect(result.toolResults[0].toolName == "web_search")
    #expect(result.toolResults[0].result[0]?["encryptedContent"]?.stringValue == "encrypted_content_123")
    #expect(result.toolResults[0].result[0]?["pageAge"]?.stringValue == "January 15, 2025")
}

@Test func anthropicLanguageMapsProviderExecutedToolResultsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "content":[
        {"type":"server_tool_use","id":"srv_code_1","name":"code_execution","input":{"code":"print(1)"}},
        {"type":"code_execution_tool_result","tool_use_id":"srv_code_1","content":{"type":"code_execution_result","stdout":"1\\n","stderr":"","return_code":0,"content":[{"type":"text","text":"ok"}]}},
        {"type":"tool_search_tool_result","tool_use_id":"srv_search_1","content":{"type":"tool_search_tool_search_result","tool_references":[{"type":"tool","tool_name":"weather"}]}},
        {"type":"advisor_tool_result","tool_use_id":"srv_advisor_1","content":{"type":"advisor_redacted_result","encrypted_content":"encrypted-advice"}},
        {"type":"mcp_tool_use","id":"mcp_1","name":"lookup","server_name":"docs","input":{"query":"sdk"}},
        {"type":"mcp_tool_result","tool_use_id":"mcp_1","is_error":true,"content":[{"type":"text","text":"failed"}]}
      ],
      "stop_reason":"end_turn",
      "usage":{"input_tokens":5,"output_tokens":7}
    }
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Use hosted tools.")]))

    #expect(result.toolResults.count == 4)
    let code = try #require(result.toolResults.first { $0.toolName == "code_execution" })
    #expect(code.toolCallID == "srv_code_1")
    #expect(code.result["type"]?.stringValue == "code_execution_result")
    #expect(code.result["stdout"]?.stringValue == "1\n")
    #expect(code.result["return_code"]?.intValue == 0)
    #expect(code.result["content"]?[0]?["text"]?.stringValue == "ok")

    let toolSearch = try #require(result.toolResults.first { $0.toolName == "tool_search" })
    #expect(toolSearch.toolCallID == "srv_search_1")
    #expect(toolSearch.result[0]?["toolName"]?.stringValue == "weather")

    let advisor = try #require(result.toolResults.first { $0.toolName == "advisor" })
    #expect(advisor.result["type"]?.stringValue == "advisor_redacted_result")
    #expect(advisor.result["encryptedContent"]?.stringValue == "encrypted-advice")

    let mcp = try #require(result.toolResults.first { $0.toolName == "lookup" })
    #expect(mcp.toolCallID == "mcp_1")
    #expect(mcp.isError == true)
    #expect(mcp.dynamic == true)
    #expect(mcp.result[0]?["text"]?.stringValue == "failed")
    #expect(mcp.providerMetadata["anthropic"]?["type"]?.stringValue == "mcp-tool-use")
    #expect(mcp.providerMetadata["anthropic"]?["serverName"]?.stringValue == "docs")
}
