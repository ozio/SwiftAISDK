import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicToolCacheControlLimitsBreakpointsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Use cached tools.")],
        tools: Dictionary(uniqueKeysWithValues: (1...5).map { index in
            (
                "tool\(index)",
                JSONValue.object([
                    "type": .string("object"),
                    "description": .string("Test \(index)"),
                    "properties": .object([:]),
                    "providerOptions": .object([
                        "anthropic": .object([
                            "cacheControl": .object(["type": .string("ephemeral")])
                        ])
                    ])
                ])
            )
        })
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    let cacheControlledTools = tools.filter { $0["cache_control"] != nil }
    #expect(cacheControlledTools.count == 4)
    let uncachedTool = try #require(tools.first { $0["cache_control"] == nil })
    #expect(uncachedTool["name"]?.stringValue != nil)
    #expect(result.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "cacheControl breakpoint limit",
        message: "Maximum 4 cache breakpoints exceeded (found 5). This breakpoint will be ignored."
    )))
}

@Test func anthropicSystemMessageCacheControlMapsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(
            role: .system,
            content: [.text("system message")],
            providerMetadata: ["anthropic": ["cacheControl": ["type": "ephemeral"]]]
        )
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let system = try #require(body["system"]?.arrayValue)
    #expect(system == [
        [
            "type": "text",
            "text": "system message",
            "cache_control": ["type": "ephemeral"]
        ]
    ])
    #expect(body["messages"] == [])
}

@Test func anthropicUserMessageCacheControlAppliesToLastPartLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(
            role: .user,
            content: [.text("part1"), .text("part2")],
            providerMetadata: ["anthropic": ["cacheControl": ["type": "ephemeral"]]]
        )
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let message = try #require(body["messages"]?[0])
    #expect(message["role"]?.stringValue == "user")
    #expect(message["content"] == [
        ["type": "text", "text": "part1"],
        ["type": "text", "text": "part2", "cache_control": ["type": "ephemeral"]]
    ])
}

@Test func anthropicUserTextPartCacheControlMapsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .text("test", providerMetadata: ["anthropic": ["cacheControl": ["type": "ephemeral"]]])
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["messages"]?[0]?["content"] == [
        [
            "type": "text",
            "text": "test",
            "cache_control": ["type": "ephemeral"]
        ]
    ])
}

@Test func anthropicAssistantTextPartCacheControlMapsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .user("user-content"),
        AIMessage(role: .assistant, content: [
            .text("test", providerMetadata: ["anthropic": ["cacheControl": ["type": "ephemeral"]]])
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["messages"]?[1]?["content"] == [
        [
            "type": "text",
            "text": "test",
            "cache_control": ["type": "ephemeral"]
        ]
    ])
}

@Test func anthropicAssistantToolCallCacheControlMapsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .user("user-content"),
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "test-id",
                name: "test-tool",
                arguments: #"{"some":"arg"}"#,
                providerMetadata: ["anthropic": ["cacheControl": ["type": "ephemeral"]]]
            ))
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let assistant = try #require(body["messages"]?[1])
    #expect(assistant["role"]?.stringValue == "assistant")
    #expect(assistant["content"] == [
        [
            "type": "tool_use",
            "id": "test-id",
            "name": "test-tool",
            "input": ["some": "arg"],
            "cache_control": ["type": "ephemeral"]
        ]
    ])
}

@Test func anthropicToolResultCacheControlMapsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .tool, content: [
            .toolResult(AIToolResult(
                toolCallID: "test",
                toolName: "test",
                result: ["test": "test"],
                providerMetadata: ["anthropic": ["cacheControl": ["type": "ephemeral"]]]
            ))
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let toolMessage = try #require(body["messages"]?[0])
    #expect(toolMessage["role"]?.stringValue == "user")
    #expect(toolMessage["content"] == [
        [
            "type": "tool_result",
            "tool_use_id": "test",
            "content": #"{"test":"test"}"#,
            "cache_control": ["type": "ephemeral"]
        ]
    ])
}

@Test func anthropicToolResultOutputCacheControlMapsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .tool, content: [
            .toolResult(AIToolResult(
                toolCallID: "test",
                toolName: "test",
                result: "fallback",
                modelOutput: [
                    "type": "text",
                    "value": "test",
                    "providerOptions": ["anthropic": ["cacheControl": ["type": "ephemeral"]]]
                ]
            ))
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let toolResult = try #require(body["messages"]?[0]?["content"]?[0])
    #expect(toolResult["content"]?.stringValue == "test")
    #expect(toolResult["cache_control"] == ["type": "ephemeral"])
}

@Test func anthropicToolResultContentOutputCacheControlMapsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .tool, content: [
            .toolResult(AIToolResult(
                toolCallID: "test",
                toolName: "test",
                result: "fallback",
                modelOutput: [
                    "type": "content",
                    "value": [
                        [
                            "type": "text",
                            "text": "test",
                            "providerOptions": ["anthropic": ["cacheControl": ["type": "ephemeral"]]]
                        ]
                    ]
                ]
            ))
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let toolResult = try #require(body["messages"]?[0]?["content"]?[0])
    #expect(toolResult["content"] == [["type": "text", "text": "test"]])
    #expect(toolResult["cache_control"] == ["type": "ephemeral"])
}

@Test func anthropicPromptCacheControlLimitsBreakpointsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")
    let cacheMetadata: [String: JSONValue] = ["anthropic": ["cacheControl": ["type": "ephemeral"]]]

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .system, content: [.text("system 1")], providerMetadata: cacheMetadata),
        AIMessage(role: .system, content: [.text("system 2")], providerMetadata: cacheMetadata),
        AIMessage(role: .user, content: [.text("user 1")], providerMetadata: cacheMetadata),
        AIMessage(role: .assistant, content: [.text("assistant 1")], providerMetadata: cacheMetadata),
        AIMessage(role: .user, content: [.text("user 2 (should be rejected)")], providerMetadata: cacheMetadata)
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let system = try #require(body["system"]?.arrayValue)
    let messages = try #require(body["messages"]?.arrayValue)
    #expect(system[0]["cache_control"] == ["type": "ephemeral"])
    #expect(system[1]["cache_control"] == ["type": "ephemeral"])
    #expect(messages[0]["content"]?[0]?["cache_control"] == ["type": "ephemeral"])
    #expect(messages[1]["content"]?[0]?["cache_control"] == ["type": "ephemeral"])
    #expect(messages[2]["content"]?[0]?["cache_control"] == nil)
    #expect(result.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "cacheControl breakpoint limit",
        message: "Maximum 4 cache breakpoints exceeded (found 5). This breakpoint will be ignored."
    )))
}

@Test func anthropicThinkingCacheControlIsRejectedLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(
            role: .assistant,
            content: [],
            reasoning: "thinking content",
            providerMetadata: [
                "anthropic": [
                    "signature": "test-sig",
                    "cacheControl": ["type": "ephemeral"]
                ]
            ]
        )
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let thinking = try #require(body["messages"]?[0]?["content"]?[0])
    #expect(thinking == [
        "type": "thinking",
        "thinking": "thinking content",
        "signature": "test-sig"
    ])
    #expect(result.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "cache_control on non-cacheable context",
            message: "cache_control cannot be set on thinking block. It will be ignored."
        )
    ])
}

@Test func anthropicRedactedThinkingCacheControlIsRejectedLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(
            role: .assistant,
            content: [],
            reasoning: "redacted",
            providerMetadata: [
                "anthropic": [
                    "redactedData": "abc123",
                    "cacheControl": ["type": "ephemeral"]
                ]
            ]
        )
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let thinking = try #require(body["messages"]?[0]?["content"]?[0])
    #expect(thinking == [
        "type": "redacted_thinking",
        "data": "abc123"
    ])
    #expect(result.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "cache_control on non-cacheable context",
            message: "cache_control cannot be set on redacted thinking block. It will be ignored."
        )
    ])
}

