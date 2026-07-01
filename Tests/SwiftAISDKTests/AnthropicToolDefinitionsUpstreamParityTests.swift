import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicErrorMessageDropsNullDetailsLikeUpstream() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 529,
        headers: ["anthropic-request-id": "req_overloaded"],
        body: Data(#"{"type":"error","error":{"details":null,"type":"overloaded_error","message":"Overloaded"}}"#.utf8)
    ))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    await #expect(throws: AIError.apiCall(
        provider: "anthropic.messages",
        statusCode: 529,
        body: "Overloaded",
        headers: ["anthropic-request-id": "req_overloaded"]
    )) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))
    }
}

@Test func anthropicFunctionToolsMapUpstreamProviderOptionsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use the database.")],
        tools: [
            "query_database": [
                "type": "object",
                "description": "Query a database",
                "properties": [
                    "sql": ["type": "string"]
                ],
                "strict": true,
                "inputExamples": [
                    ["input": ["sql": "select 1"]]
                ],
                "providerOptions": [
                    "anthropic": [
                        "eagerInputStreaming": true,
                        "deferLoading": false,
                        "allowedCallers": ["code_execution_20260120"],
                        "cacheControl": ["type": "ephemeral"]
                    ]
                ]
            ]
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tool = try #require(body["tools"]?[0])
    #expect(tool["name"]?.stringValue == "query_database")
    #expect(tool["description"]?.stringValue == "Query a database")
    #expect(tool["strict"]?.boolValue == true)
    #expect(tool["input_examples"]?[0]?["sql"]?.stringValue == "select 1")
    #expect(tool["eager_input_streaming"]?.boolValue == true)
    #expect(tool["defer_loading"]?.boolValue == false)
    #expect(tool["allowed_callers"]?[0]?.stringValue == "code_execution_20260120")
    #expect(tool["cache_control"]?["type"]?.stringValue == "ephemeral")
    #expect(tool["input_schema"]?["properties"]?["sql"]?["type"]?.stringValue == "string")
    #expect(tool["input_schema"]?["description"] == nil)
    #expect(tool["input_schema"]?["strict"] == nil)
    #expect(tool["input_schema"]?["inputExamples"] == nil)
    #expect(tool["input_schema"]?["providerOptions"] == nil)

    let betaHeader = try #require(request.headers["anthropic-beta"])
    #expect(betaHeader.contains("structured-outputs-2025-11-13"))
    #expect(betaHeader.contains("advanced-tool-use-2025-11-20"))
}

@Test func anthropicFunctionToolsAddStructuredOutputBetaOnSupportedModelsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-5")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use a tool.")],
        tools: [
            "testTool": [
                "type": "object",
                "description": "A test tool",
                "properties": [
                    "value": ["type": "string"]
                ]
            ]
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tool = try #require(body["tools"]?[0])
    #expect(tool["strict"] == nil)
    #expect(request.headers["anthropic-beta"] == "structured-outputs-2025-11-13")
}

@Test func anthropicStrictFunctionToolsAreIgnoredOnUnsupportedModelsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-5-sonnet-20241022")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Use a tool.")],
        tools: [
            "testTool": [
                "type": "object",
                "description": "A test tool",
                "properties": [
                    "value": ["type": "string"]
                ],
                "strict": true
            ]
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tool = try #require(body["tools"]?[0])
    #expect(tool["strict"] == nil)
    #expect(request.headers["anthropic-beta"] == nil)
    #expect(result.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "strict",
        message: "Tool 'testTool' has strict: true, but strict mode is not supported by this provider. The strict property will be ignored."
    )))
}

@Test func anthropicStrictFalseFunctionToolsStayStrictOnSupportedModelsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-5")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use a tool.")],
        tools: [
            "testTool": [
                "type": "object",
                "description": "A test tool",
                "properties": [
                    "value": ["type": "string"]
                ],
                "strict": false
            ]
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tool = try #require(body["tools"]?[0])
    #expect(tool["strict"]?.boolValue == false)
    #expect(request.headers["anthropic-beta"] == "structured-outputs-2025-11-13")
}

@Test func anthropicProviderDefinedToolVariantsMirrorUpstreamPrepareToolsMatrix() async throws {
    let ok = jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """)
    let toolCases: [(tool: JSONValue, type: String, name: String, fields: [String: JSONValue], beta: String?)] = [
        (
            AnthropicTools.computer_20241022(displayWidthPx: 800, displayHeightPx: 600, displayNumber: 1),
            "computer_20241022",
            "computer",
            ["display_width_px": 800, "display_height_px": 600, "display_number": 1],
            "computer-use-2024-10-22"
        ),
        (
            AnthropicTools.computer_20250124(displayWidthPx: 800, displayHeightPx: 600, displayNumber: 1),
            "computer_20250124",
            "computer",
            ["display_width_px": 800, "display_height_px": 600, "display_number": 1],
            "computer-use-2025-01-24"
        ),
        (
            AnthropicTools.computer_20251124(displayWidthPx: 800, displayHeightPx: 600, displayNumber: 1, enableZoom: false),
            "computer_20251124",
            "computer",
            ["display_width_px": 800, "display_height_px": 600, "display_number": 1, "enable_zoom": false],
            "computer-use-2025-11-24"
        ),
        (
            AnthropicTools.textEditor_20241022(),
            "text_editor_20241022",
            "str_replace_editor",
            [:],
            "computer-use-2024-10-22"
        ),
        (
            AnthropicTools.bash_20241022(),
            "bash_20241022",
            "bash",
            [:],
            "computer-use-2024-10-22"
        ),
        (
            AnthropicTools.textEditor_20250728(),
            "text_editor_20250728",
            "str_replace_based_edit_tool",
            [:],
            nil
        ),
        (
            AnthropicTools.webSearch_20250305(maxUses: 2, allowedDomains: ["example.com"], blockedDomains: ["blocked.example"], userLocation: ["type": "approximate", "city": "Tokyo"]),
            "web_search_20250305",
            "web_search",
            ["max_uses": 2, "allowed_domains": ["example.com"], "blocked_domains": ["blocked.example"], "user_location": ["type": "approximate", "city": "Tokyo"]],
            nil
        ),
        (
            AnthropicTools.webFetch_20260209(maxUses: 2, allowedDomains: ["example.com"], blockedDomains: ["blocked.example"], citations: ["enabled": true], maxContentTokens: 500),
            "web_fetch_20260209",
            "web_fetch",
            ["max_uses": 2, "allowed_domains": ["example.com"], "blocked_domains": ["blocked.example"], "citations": ["enabled": true], "max_content_tokens": 500],
            "code-execution-web-tools-2026-02-09"
        ),
        (
            AnthropicTools.toolSearchBm25_20251119(),
            "tool_search_tool_bm25_20251119",
            "tool_search_tool_bm25",
            [:],
            nil
        ),
        (
            AnthropicTools.codeExecution_20260120(),
            "code_execution_20260120",
            "code_execution",
            [:],
            nil
        ),
        (
            AnthropicTools.advisor_20260301(model: "claude-opus-4-7"),
            "advisor_20260301",
            "advisor",
            ["model": "claude-opus-4-7"],
            "advisor-tool-2026-03-01"
        )
    ]
    let transport = RecordingTransport(responses: Array(repeating: ok, count: toolCases.count))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    for (index, toolCase) in toolCases.enumerated() {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Use tool \(index).")],
            tools: ["tool": toolCase.tool]
        ))
    }

    let requests = await transport.requests()
    #expect(requests.count == toolCases.count)
    for (index, toolCase) in toolCases.enumerated() {
        let request = requests[index]
        let body = try decodeJSONBody(try #require(request.body))
        let tool = try #require(body["tools"]?[0])
        #expect(tool["type"]?.stringValue == toolCase.type)
        #expect(tool["name"]?.stringValue == toolCase.name)
        for (field, value) in toolCase.fields {
            #expect(tool[field] == value)
        }
        if let beta = toolCase.beta {
            #expect(request.headers["anthropic-beta"] == beta)
        } else {
            #expect(request.headers["anthropic-beta"] == nil)
        }
    }
}

@Test func anthropicUnsupportedProviderDefinedToolsWarnLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Use a tool.")],
        tools: [
            "unsupported_tool": [
                "type": "provider",
                "id": "unsupported.tool",
                "name": "unsupported_tool",
                "args": [:]
            ]
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["tools"] == nil)
    #expect(body["tool_choice"] == nil)
    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "provider-defined tool unsupported.tool")
    ])
}

