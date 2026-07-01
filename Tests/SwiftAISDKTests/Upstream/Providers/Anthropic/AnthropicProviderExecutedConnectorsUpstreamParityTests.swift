import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicProviderExecutedToolSearchRegexRoundTripsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "srvtoolu_01SACvPAnp6ucMJsstB5qb3f",
                name: "tool_search_tool_regex",
                arguments: #"{"pattern":"weather|forecast","limit":10}"#,
                providerExecuted: true
            )),
            .toolResult(AIToolResult(
                toolCallID: "srvtoolu_01SACvPAnp6ucMJsstB5qb3f",
                toolName: "tool_search_tool_regex",
                result: [],
                modelOutput: [
                    "type": "json",
                    "value": [
                        [
                            "type": "tool_reference",
                            "toolName": "get_weather"
                        ]
                    ]
                ]
            ))
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content[0]["type"]?.stringValue == "server_tool_use")
    #expect(content[0]["id"]?.stringValue == "srvtoolu_01SACvPAnp6ucMJsstB5qb3f")
    #expect(content[0]["name"]?.stringValue == "tool_search_tool_regex")
    #expect(content[0]["input"]?["pattern"]?.stringValue == "weather|forecast")
    #expect(content[0]["input"]?["limit"]?.intValue == 10)
    #expect(content[1]["type"]?.stringValue == "tool_search_tool_result")
    #expect(content[1]["tool_use_id"]?.stringValue == "srvtoolu_01SACvPAnp6ucMJsstB5qb3f")
    #expect(content[1]["content"]?["type"]?.stringValue == "tool_search_tool_search_result")
    let references = try #require(content[1]["content"]?["tool_references"]?.arrayValue)
    #expect(references[0]["type"]?.stringValue == "tool_reference")
    #expect(references[0]["tool_name"]?.stringValue == "get_weather")
    #expect(result.warnings.isEmpty)
}

@Test func anthropicProviderExecutedMCPToolUseRoundTripsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "mcptoolu_01HXPYHs79HH36fBbKHysCrp",
                name: "echo",
                arguments: "{}",
                providerExecuted: true,
                providerMetadata: ["anthropic": ["type": "mcp-tool-use", "serverName": "echo"]]
            )),
            .toolResult(AIToolResult(
                toolCallID: "mcptoolu_01HXPYHs79HH36fBbKHysCrp",
                toolName: "echo",
                result: [],
                modelOutput: [
                    "type": "json",
                    "value": [
                        ["type": "text", "text": "Tool echo: hello world"]
                    ]
                ]
            )),
            .text(#"The echo tool responded back with "hello world" - it simply echoed the message I sent to it!"#)
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content.map { $0["type"]?.stringValue } == [
        "mcp_tool_use",
        "mcp_tool_result",
        "text"
    ])
    #expect(content[0]["id"]?.stringValue == "mcptoolu_01HXPYHs79HH36fBbKHysCrp")
    #expect(content[0]["name"]?.stringValue == "echo")
    #expect(content[0]["server_name"]?.stringValue == "echo")
    #expect(content[0]["input"]?.objectValue?.isEmpty == true)
    #expect(content[1]["tool_use_id"]?.stringValue == "mcptoolu_01HXPYHs79HH36fBbKHysCrp")
    #expect(content[1]["is_error"]?.boolValue == false)
    let mcpContent = try #require(content[1]["content"]?.arrayValue)
    #expect(mcpContent[0]["type"]?.stringValue == "text")
    #expect(mcpContent[0]["text"]?.stringValue == "Tool echo: hello world")
    #expect(content[2]["text"]?.stringValue == #"The echo tool responded back with "hello world" - it simply echoed the message I sent to it!"#)
    #expect(result.warnings == [AIWarning(
        type: "other",
        message: "provider executed tool result for tool echo is not supported"
    )])
}
