import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicProviderExecutedAdvisorResultRoundTripsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "srvtoolu_advisor_abc123",
                name: "advisor",
                arguments: "{}",
                providerExecuted: true
            )),
            .toolResult(AIToolResult(
                toolCallID: "srvtoolu_advisor_abc123",
                toolName: "advisor",
                result: [:],
                modelOutput: [
                    "type": "json",
                    "value": [
                        "type": "advisor_result",
                        "text": "Use a channel-based coordination pattern. Close the input channel first, then wait on a WaitGroup."
                    ]
                ]
            ))
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content[0]["type"]?.stringValue == "server_tool_use")
    #expect(content[0]["id"]?.stringValue == "srvtoolu_advisor_abc123")
    #expect(content[0]["name"]?.stringValue == "advisor")
    #expect(content[0]["input"]?.objectValue?.isEmpty == true)
    #expect(content[1]["type"]?.stringValue == "advisor_tool_result")
    #expect(content[1]["tool_use_id"]?.stringValue == "srvtoolu_advisor_abc123")
    #expect(content[1]["content"]?["type"]?.stringValue == "advisor_result")
    #expect(content[1]["content"]?["text"]?.stringValue == "Use a channel-based coordination pattern. Close the input channel first, then wait on a WaitGroup.")
    #expect(result.warnings.isEmpty)
}

@Test func anthropicProviderExecutedAdvisorRedactedResultRoundTripsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "srvtoolu_advisor_redacted",
                name: "advisor",
                arguments: "{}",
                providerExecuted: true
            )),
            .toolResult(AIToolResult(
                toolCallID: "srvtoolu_advisor_redacted",
                toolName: "advisor",
                result: [:],
                modelOutput: [
                    "type": "json",
                    "value": [
                        "type": "advisor_redacted_result",
                        "encryptedContent": "opaque-encrypted-blob-xyz"
                    ]
                ]
            ))
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content[1]["type"]?.stringValue == "advisor_tool_result")
    #expect(content[1]["tool_use_id"]?.stringValue == "srvtoolu_advisor_redacted")
    #expect(content[1]["content"]?["type"]?.stringValue == "advisor_redacted_result")
    #expect(content[1]["content"]?["encrypted_content"]?.stringValue == "opaque-encrypted-blob-xyz")
    #expect(result.warnings.isEmpty)
}

@Test func anthropicProviderExecutedAdvisorErrorRoundTripsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "srvtoolu_advisor_err",
                name: "advisor",
                arguments: "{}",
                providerExecuted: true
            )),
            .toolResult(AIToolResult(
                toolCallID: "srvtoolu_advisor_err",
                toolName: "advisor",
                result: [:],
                modelOutput: [
                    "type": "json",
                    "value": [
                        "type": "advisor_tool_result_error",
                        "errorCode": "max_uses_exceeded"
                    ]
                ]
            ))
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content[1]["type"]?.stringValue == "advisor_tool_result")
    #expect(content[1]["content"]?["type"]?.stringValue == "advisor_tool_result_error")
    #expect(content[1]["content"]?["error_code"]?.stringValue == "max_uses_exceeded")
    #expect(result.warnings.isEmpty)
}

@Test func anthropicProviderExecutedAdvisorInterleavedTextRoundTripsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        .user("Build a concurrent worker pool in Go with graceful shutdown."),
        AIMessage(role: .assistant, content: [
            .text("Let me consult the advisor on this."),
            .toolCall(AIToolCall(
                id: "srvtoolu_advisor_1",
                name: "advisor",
                arguments: "{}",
                providerExecuted: true
            )),
            .toolResult(AIToolResult(
                toolCallID: "srvtoolu_advisor_1",
                toolName: "advisor",
                result: [:],
                modelOutput: [
                    "type": "json",
                    "value": [
                        "type": "advisor_result",
                        "text": "Use channels and a WaitGroup."
                    ]
                ]
            )),
            .text("Here is the implementation.")
        ]),
        .user("Now add a max-in-flight limit of 10.")
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let messages = try #require(body["messages"]?.arrayValue)
    #expect(messages.map { $0["role"]?.stringValue } == ["user", "assistant", "user"])
    let assistantContent = try #require(messages[1]["content"]?.arrayValue)
    #expect(assistantContent.map { $0["type"]?.stringValue } == [
        "text",
        "server_tool_use",
        "advisor_tool_result",
        "text"
    ])
    #expect(assistantContent[0]["text"]?.stringValue == "Let me consult the advisor on this.")
    #expect(assistantContent[1]["id"]?.stringValue == "srvtoolu_advisor_1")
    #expect(assistantContent[2]["content"]?["text"]?.stringValue == "Use channels and a WaitGroup.")
    #expect(assistantContent[3]["text"]?.stringValue == "Here is the implementation.")
    #expect(result.warnings.isEmpty)
}

@Test func anthropicAdvisorStopReasonsParseAndReplayLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {
          "model":"claude-sonnet-4-6",
          "id":"msg_advisor_stop_reasons",
          "type":"message",
          "role":"assistant",
          "content":[
            {"type":"server_tool_use","id":"srvtoolu_advisor_plaintext","name":"advisor","input":{}},
            {"type":"advisor_tool_result","tool_use_id":"srvtoolu_advisor_plaintext","content":{"type":"advisor_result","text":"Partial plaintext advice.","stop_reason":"max_tokens"}},
            {"type":"server_tool_use","id":"srvtoolu_advisor_redacted","name":"advisor","input":{}},
            {"type":"advisor_tool_result","tool_use_id":"srvtoolu_advisor_redacted","content":{"type":"advisor_redacted_result","encrypted_content":"opaque-encrypted-advice","stop_reason":"end_turn"}}
          ],
          "stop_reason":"end_turn",
          "usage":{"input_tokens":10,"output_tokens":20}
        }
        """),
        jsonResponse(#"{"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}"#)
    ])
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let parsed = try await model.generate(LanguageModelRequest(
        messages: [.user("Consult the advisor.")],
        tools: ["advisor": AnthropicTools.advisor_20260301(model: "claude-opus-4-7", maxTokens: 2_048)]
    ))
    let plaintext = try #require(parsed.toolResults.first { $0.toolCallID == "srvtoolu_advisor_plaintext" })
    let redacted = try #require(parsed.toolResults.first { $0.toolCallID == "srvtoolu_advisor_redacted" })
    #expect(plaintext.result["stopReason"]?.stringValue == "max_tokens")
    #expect(redacted.result["stopReason"]?.stringValue == "end_turn")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: plaintext.toolCallID,
                name: "advisor",
                arguments: "{}",
                providerExecuted: true
            )),
            .toolResult(plaintext),
            .toolCall(AIToolCall(
                id: redacted.toolCallID,
                name: "advisor",
                arguments: "{}",
                providerExecuted: true
            )),
            .toolResult(redacted)
        ])
    ]))

    let requests = await transport.requests()
    let replayBody = try decodeJSONBody(try #require(requests[1].body))
    let replayContent = try #require(replayBody["messages"]?[0]?["content"]?.arrayValue)
    #expect(replayContent[1]["content"]?["stop_reason"]?.stringValue == "max_tokens")
    #expect(replayContent[3]["content"]?["stop_reason"]?.stringValue == "end_turn")
    #expect(replayContent[3]["content"]?["encrypted_content"]?.stringValue == "opaque-encrypted-advice")
}

@Test func anthropicStreamsAdvisorStopReasonsLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"message_start","message":{"id":"msg_advisor_stop_reasons","type":"message","role":"assistant","content":[],"model":"claude-sonnet-4-6","stop_reason":null,"usage":{"input_tokens":10,"output_tokens":1}}}

    data: {"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use","id":"srvtoolu_advisor_plaintext","name":"advisor","input":{}}}

    data: {"type":"content_block_stop","index":0}

    data: {"type":"content_block_start","index":1,"content_block":{"type":"advisor_tool_result","tool_use_id":"srvtoolu_advisor_plaintext","content":{"type":"advisor_result","text":"Partial plaintext advice.","stop_reason":"max_tokens"}}}

    data: {"type":"content_block_stop","index":1}

    data: {"type":"content_block_start","index":2,"content_block":{"type":"server_tool_use","id":"srvtoolu_advisor_redacted","name":"advisor","input":{}}}

    data: {"type":"content_block_stop","index":2}

    data: {"type":"content_block_start","index":3,"content_block":{"type":"advisor_tool_result","tool_use_id":"srvtoolu_advisor_redacted","content":{"type":"advisor_redacted_result","encrypted_content":"opaque-encrypted-advice","stop_reason":"end_turn"}}}

    data: {"type":"content_block_stop","index":3}

    data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"input_tokens":10,"output_tokens":20}}

    data: {"type":"message_stop"}

    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    var toolResults: [AIToolResult] = []
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Consult the advisor.")],
        tools: ["advisor": AnthropicTools.advisor_20260301(model: "claude-opus-4-7", maxTokens: 2_048)]
    )) {
        if case let .toolResult(result) = part {
            toolResults.append(result)
        }
    }

    #expect(toolResults.map { $0.result["stopReason"]?.stringValue } == ["max_tokens", "end_turn"])
}

@Test func anthropicProviderExecutedAdvisorUnsupportedOutputWarnsAndOmitsResultLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "srvtoolu_advisor_bad",
                name: "advisor",
                arguments: "{}",
                providerExecuted: true
            )),
            .toolResult(AIToolResult(
                toolCallID: "srvtoolu_advisor_bad",
                toolName: "advisor",
                result: [:],
                modelOutput: ["type": "text", "value": "should be json"]
            ))
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content.count == 1)
    #expect(content[0]["type"]?.stringValue == "server_tool_use")
    #expect(content[0]["id"]?.stringValue == "srvtoolu_advisor_bad")
    #expect(result.warnings == [AIWarning(
        type: "other",
        message: "provider executed tool result output type text for tool advisor is not supported"
    )])
}
