import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesConvertsCustomToolCallsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .toolCall(AIToolCall(id: "call_custom_001", name: "write_sql", arguments: "SELECT * FROM users WHERE age > 25")),
                .toolCall(AIToolCall(id: "call_custom_002", name: "write_sql", arguments: #"{"query":"test"}"#)),
                .toolCall(AIToolCall(
                    id: "call_custom_003",
                    name: "write_sql",
                    arguments: #""SELECT 1""#,
                    providerMetadata: ["openai": ["itemId": "ct_ref_123"]]
                ))
            ])
        ],
        tools: ["write_sql": OpenAITools.customTool(name: "write_sql")],
        providerOptions: ["openai": ["store": true]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 3)
    #expect(input[0]["type"]?.stringValue == "custom_tool_call")
    #expect(input[0]["call_id"]?.stringValue == "call_custom_001")
    #expect(input[0]["name"]?.stringValue == "write_sql")
    #expect(input[0]["input"]?.stringValue == "SELECT * FROM users WHERE age > 25")
    #expect(input[1]["type"]?.stringValue == "custom_tool_call")
    #expect(input[1]["call_id"]?.stringValue == "call_custom_002")
    #expect(input[1]["input"]?.stringValue == #"{"query":"test"}"#)
    #expect(input[2]["type"]?.stringValue == "item_reference")
    #expect(input[2]["id"]?.stringValue == "ct_ref_123")
}

@Test func openAIResponsesConvertsCustomToolOutputsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            .toolResponses(toolResults: [
                AIToolResult(
                    toolCallID: "call_custom_001",
                    toolName: "write_sql",
                    result: "Query executed successfully. 42 rows returned."
                ),
                AIToolResult(
                    toolCallID: "call_custom_002",
                    toolName: "write_sql",
                    result: ["rows": 42, "status": "ok"]
                ),
                AIToolResult(
                    toolCallID: "call_custom_denied_001",
                    toolName: "write_sql",
                    result: ["type": "execution-denied", "reason": "User denied the tool execution"]
                )
            ])
        ],
        tools: ["write_sql": OpenAITools.customTool(name: "write_sql")]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 3)
    #expect(input[0]["type"]?.stringValue == "custom_tool_call_output")
    #expect(input[0]["call_id"]?.stringValue == "call_custom_001")
    #expect(input[0]["output"]?.stringValue == "Query executed successfully. 42 rows returned.")
    #expect(input[1]["type"]?.stringValue == "custom_tool_call_output")
    #expect(input[1]["call_id"]?.stringValue == "call_custom_002")
    let jsonOutput = try decodeJSONBody(Data((try #require(input[1]["output"]?.stringValue)).utf8))
    #expect(jsonOutput["rows"]?.intValue == 42)
    #expect(jsonOutput["status"]?.stringValue == "ok")
    #expect(input[2]["type"]?.stringValue == "custom_tool_call_output")
    #expect(input[2]["call_id"]?.stringValue == "call_custom_denied_001")
    #expect(input[2]["output"]?.stringValue == "User denied the tool execution")
}

@Test func openAIResponsesConvertsCustomToolContentOutputsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .toolResponses(toolResults: [
                AIToolResult(
                    toolCallID: "call_custom_005",
                    toolName: "write_sql",
                    result: ["type": "content", "value": [
                        ["type": "text", "text": "hello"]
                    ]]
                ),
                AIToolResult(
                    toolCallID: "call_custom_006",
                    toolName: "write_sql",
                    result: ["type": "content", "value": [
                        ["type": "text", "text": "Here is the file:"],
                        [
                            "type": "file",
                            "data": ["type": "url", "url": "https://example.com/test.pdf"],
                            "mediaType": "application/pdf"
                        ]
                    ]]
                )
            ])
        ],
        tools: ["write_sql": OpenAITools.customTool(name: "write_sql")]
    ))

    #expect(result.warnings.isEmpty)
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 2)
    #expect(input[0]["type"]?.stringValue == "custom_tool_call_output")
    #expect(input[0]["call_id"]?.stringValue == "call_custom_005")
    #expect(input[0]["output"]?[0]?["type"]?.stringValue == "input_text")
    #expect(input[0]["output"]?[0]?["text"]?.stringValue == "hello")
    #expect(input[1]["type"]?.stringValue == "custom_tool_call_output")
    #expect(input[1]["call_id"]?.stringValue == "call_custom_006")
    #expect(input[1]["output"]?[0]?["type"]?.stringValue == "input_text")
    #expect(input[1]["output"]?[0]?["text"]?.stringValue == "Here is the file:")
    #expect(input[1]["output"]?[1]?["type"]?.stringValue == "input_file")
    #expect(input[1]["output"]?[1]?["file_url"]?.stringValue == "https://example.com/test.pdf")
}

@Test func openAIResponsesFallsBackToFunctionCallWithoutCustomToolDefinitionLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .toolCall(AIToolCall(id: "call_custom_001", name: "write_sql", arguments: #""SELECT 1""#))
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 1)
    #expect(input[0]["type"]?.stringValue == "function_call")
    #expect(input[0]["call_id"]?.stringValue == "call_custom_001")
    #expect(input[0]["name"]?.stringValue == "write_sql")
    #expect(input[0]["arguments"]?.stringValue == #""SELECT 1""#)
}
