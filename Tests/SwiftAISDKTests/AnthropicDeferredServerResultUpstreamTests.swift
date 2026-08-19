import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicPreservesDeferredServerResultAcrossClientToolContinuationLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"done"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":1}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "claude-key",
        transport: transport
    ))
    let model = try provider.languageModel("claude-sonnet-4-6")
    let codeExecutionCaller: [String: JSONValue] = [
        "anthropic": [
            "caller": [
                "type": "code_execution_20260120",
                "toolId": "code-execution-call"
            ]
        ]
    ]

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .toolCall(AIToolCall(
                    id: "code-execution-call",
                    name: "code_execution",
                    arguments: #"{"type":"programmatic-tool-call","code":"await fetch_url({ url: \"https://example.com\" })"}"#,
                    providerExecuted: true,
                    providerMetadata: ["anthropic": ["caller": ["type": "direct"]]]
                )),
                .toolCall(AIToolCall(
                    id: "client-tool-call",
                    name: "fetch_url",
                    arguments: #"{"url":"https://example.com"}"#,
                    providerMetadata: codeExecutionCaller
                ))
            ]),
            .toolResponses(toolResults: [
                AIToolResult(
                    toolCallID: "client-tool-call",
                    toolName: "fetch_url",
                    result: "Example Domain"
                )
            ]),
            AIMessage(role: .assistant, content: [
                .toolResult(AIToolResult(
                    toolCallID: "code-execution-call",
                    toolName: "code_execution",
                    result: [:],
                    modelOutput: [
                        "type": "json",
                        "value": [
                            "type": "encrypted_code_execution_result",
                            "encrypted_stdout": "encrypted-output",
                            "stderr": "",
                            "return_code": 0,
                            "content": []
                        ]
                    ],
                    providerExecuted: true
                ))
            ])
        ],
        tools: [
            "code_execution": AnthropicTools.codeExecution_20260120(),
            "fetch_url": [
                "type": "object",
                "properties": ["url": ["type": "string"]]
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let messages = try #require(body["messages"]?.arrayValue)
    #expect(messages.count == 3)

    let firstAssistant = try #require(messages[0]["content"]?.arrayValue)
    #expect(firstAssistant.map { $0["type"]?.stringValue } == ["server_tool_use", "tool_use"])
    #expect(firstAssistant[0]["id"]?.stringValue == "code-execution-call")
    #expect(firstAssistant[0]["input"]?["type"] == nil)
    #expect(firstAssistant[0]["input"]?["code"]?.stringValue == #"await fetch_url({ url: "https://example.com" })"#)
    #expect(firstAssistant[0]["caller"]?["type"]?.stringValue == "direct")
    #expect(firstAssistant[1]["id"]?.stringValue == "client-tool-call")
    #expect(firstAssistant[1]["caller"]?["type"]?.stringValue == "code_execution_20260120")
    #expect(firstAssistant[1]["caller"]?["tool_id"]?.stringValue == "code-execution-call")

    let clientContinuation = try #require(messages[1]["content"]?.arrayValue)
    #expect(messages[1]["role"]?.stringValue == "user")
    #expect(clientContinuation.map { $0["type"]?.stringValue } == ["tool_result"])
    #expect(clientContinuation[0]["tool_use_id"]?.stringValue == "client-tool-call")

    let deferredResult = try #require(messages[2]["content"]?.arrayValue)
    #expect(messages[2]["role"]?.stringValue == "assistant")
    #expect(deferredResult.map { $0["type"]?.stringValue } == ["code_execution_tool_result"])
    #expect(deferredResult[0]["tool_use_id"]?.stringValue == "code-execution-call")
    #expect(deferredResult[0]["content"]?["type"]?.stringValue == "encrypted_code_execution_result")
    #expect(deferredResult[0]["content"]?["encrypted_stdout"]?.stringValue == "encrypted-output")
    #expect(result.warnings.isEmpty)
}
