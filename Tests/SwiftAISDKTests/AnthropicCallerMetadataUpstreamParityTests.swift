import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicPreservesCallerMetadataAndReplaysItAcrossTurnsLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {
          "id":"msg_1",
          "content":[
            {"type":"server_tool_use","id":"srv_1","name":"web_search","input":{"query":"Swift"},"caller":{"type":"code_execution_20260120","tool_id":"code_1"}},
            {"type":"web_search_tool_result","tool_use_id":"srv_1","content":[{"type":"web_search_result","url":"https://example.com","title":"Example","encrypted_content":"encrypted"}],"caller":{"type":"code_execution_20260120","tool_id":"code_1"}},
            {"type":"tool_use","id":"call_1","name":"lookup","input":{"query":"SDK"},"caller":{"type":"direct"}}
          ],
          "stop_reason":"tool_use",
          "usage":{"input_tokens":3,"output_tokens":5}
        }
        """),
        jsonResponse(#"{"id":"msg_2","content":[{"type":"text","text":"done"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":1}}"#)
    ])
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-20250514")

    let first = try await model.generate(LanguageModelRequest(messages: [.user("Search")]))
    let serverCall = try #require(first.toolCalls.first { $0.id == "srv_1" })
    let clientCall = try #require(first.toolCalls.first { $0.id == "call_1" })
    let webResult = try #require(first.toolResults.first { $0.toolCallID == "srv_1" })
    #expect(serverCall.providerMetadata["anthropic"]?["caller"]?["type"]?.stringValue == "code_execution_20260120")
    #expect(serverCall.providerMetadata["anthropic"]?["caller"]?["toolId"]?.stringValue == "code_1")
    #expect(webResult.providerMetadata["anthropic"]?["caller"]?["toolId"]?.stringValue == "code_1")
    #expect(clientCall.providerMetadata["anthropic"]?["caller"]?["type"]?.stringValue == "direct")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .user("Search"),
        AIMessage(role: .assistant, content: [
            .toolCall(serverCall),
            .toolCall(clientCall)
        ]),
        .toolResponses(toolResults: [webResult])
    ]))

    let requests = await transport.requests()
    let replayBody = try decodeJSONBody(try #require(requests.last?.body))
    let assistantContent = try #require(replayBody["messages"]?[1]?["content"]?.arrayValue)
    let userContent = try #require(replayBody["messages"]?[2]?["content"]?.arrayValue)
    #expect(assistantContent[0]["type"]?.stringValue == "server_tool_use")
    #expect(assistantContent[0]["caller"]?["type"]?.stringValue == "code_execution_20260120")
    #expect(assistantContent[0]["caller"]?["tool_id"]?.stringValue == "code_1")
    #expect(assistantContent[1]["type"]?.stringValue == "tool_use")
    #expect(assistantContent[1]["caller"]?["type"]?.stringValue == "direct")
    #expect(userContent[0]["type"]?.stringValue == "web_search_tool_result")
    #expect(userContent[0]["caller"]?["tool_id"]?.stringValue == "code_1")
}

@Test func anthropicStreamingToolCallKeepsCallerMetadataLikeUpstream() throws {
    var streamingCalls = AnthropicStreamingToolCalls(providerID: "anthropic.messages")
    let started = streamingCalls.apply(event: [
        "type": "content_block_start",
        "index": 0,
        "content_block": [
            "type": "server_tool_use",
            "id": "srv_stream",
            "name": "web_fetch",
            "input": [:],
            "caller": ["type": "code_execution_20250825", "tool_id": "code_stream"]
        ]
    ])
    let stopped = streamingCalls.apply(event: ["type": "content_block_stop", "index": 0])

    guard case let .toolInputStart(_, _, _, _, _, startMetadata) = try #require(started.first),
          case let .toolCall(call) = try #require(stopped.last) else {
        Issue.record("Expected streaming tool lifecycle")
        return
    }
    #expect(startMetadata["anthropic"]?["caller"]?["toolId"]?.stringValue == "code_stream")
    #expect(call.providerMetadata["anthropic"]?["caller"]?["type"]?.stringValue == "code_execution_20250825")
    #expect(call.providerMetadata["anthropic"]?["caller"]?["toolId"]?.stringValue == "code_stream")
}

@Test func anthropicReplaysAliasedProviderToolCallerMetadataLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"msg_alias","content":[{"type":"text","text":"done"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":1}}"#))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-20250514")
    let caller: [String: JSONValue] = [
        "anthropic": [
            "caller": [
                "type": "code_execution_20260120",
                "toolId": "code_alias"
            ]
        ]
    ]
    let call = AIToolCall(
        id: "srv_alias",
        name: "search",
        arguments: #"{"query":"Swift"}"#,
        providerExecuted: true,
        providerMetadata: caller
    )
    let result = AIToolResult(
        toolCallID: "srv_alias",
        toolName: "search",
        result: .null,
        modelOutput: [
            "type": "json",
            "value": [[
                "type": "web_search_result",
                "url": "https://example.com",
                "title": "Example",
                "encryptedContent": "encrypted"
            ]]
        ],
        providerExecuted: true,
        providerMetadata: caller
    )

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            .user("Search"),
            AIMessage(role: .assistant, content: [.toolCall(call)]),
            .toolResponses(toolResults: [result])
        ],
        tools: ["search": AnthropicTools.webSearch_20260209()]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let assistantContent = try #require(body["messages"]?[1]?["content"]?.arrayValue)
    let userContent = try #require(body["messages"]?[2]?["content"]?.arrayValue)
    #expect(assistantContent[0]["type"]?.stringValue == "server_tool_use")
    #expect(assistantContent[0]["name"]?.stringValue == "web_search")
    #expect(assistantContent[0]["caller"]?["tool_id"]?.stringValue == "code_alias")
    #expect(userContent[0]["type"]?.stringValue == "web_search_tool_result")
    #expect(userContent[0]["caller"]?["tool_id"]?.stringValue == "code_alias")
}
