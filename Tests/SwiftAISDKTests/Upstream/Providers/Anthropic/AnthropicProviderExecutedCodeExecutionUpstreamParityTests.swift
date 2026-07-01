import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicProviderExecutedCodeExecutionResultRoundTripsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "srvtoolu_01XyZ1234567890",
                name: "code_execution",
                arguments: #"{"code":"print(\"Hello, world!\")"}"#,
                providerExecuted: true
            )),
            .toolResult(AIToolResult(
                toolCallID: "srvtoolu_01XyZ1234567890",
                toolName: "code_execution",
                result: [:],
                modelOutput: [
                    "type": "json",
                    "value": [
                        "type": "code_execution_result",
                        "stdout": "Hello, world!",
                        "stderr": "",
                        "return_code": 0
                    ]
                ]
            ))
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content[0]["type"]?.stringValue == "server_tool_use")
    #expect(content[0]["id"]?.stringValue == "srvtoolu_01XyZ1234567890")
    #expect(content[0]["name"]?.stringValue == "code_execution")
    #expect(content[0]["input"]?["code"]?.stringValue == #"print("Hello, world!")"#)
    #expect(content[1]["type"]?.stringValue == "code_execution_tool_result")
    #expect(content[1]["tool_use_id"]?.stringValue == "srvtoolu_01XyZ1234567890")
    #expect(content[1]["content"]?["type"]?.stringValue == "code_execution_result")
    #expect(content[1]["content"]?["stdout"]?.stringValue == "Hello, world!")
    #expect(content[1]["content"]?["stderr"]?.stringValue == "")
    #expect(content[1]["content"]?["return_code"]?.intValue == 0)
    #expect(content[1]["content"]?["content"]?.arrayValue == [])
    #expect(result.warnings.isEmpty)
}

@Test func anthropicProviderExecutedEncryptedCodeExecutionResultRoundTripsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "srvtoolu_webfetch_01",
                name: "web_fetch",
                arguments: #"{"url":"https://example.com"}"#,
                providerExecuted: true
            )),
            .toolResult(AIToolResult(
                toolCallID: "srvtoolu_webfetch_01",
                toolName: "web_fetch",
                result: [:],
                modelOutput: [
                    "type": "json",
                    "value": [
                        "type": "web_fetch_result",
                        "url": "https://example.com",
                        "retrievedAt": "2026-01-01T00:00:00Z",
                        "content": [
                            "type": "document",
                            "title": "Example",
                            "source": ["type": "text", "mediaType": "text/plain", "data": "hello"]
                        ]
                    ]
                ]
            )),
            .toolCall(AIToolCall(
                id: "srvtoolu_codeexec_01",
                name: "code_execution",
                arguments: #"{"code":"print(\"done\")"}"#,
                providerExecuted: true
            )),
            .toolResult(AIToolResult(
                toolCallID: "srvtoolu_codeexec_01",
                toolName: "code_execution",
                result: [:],
                modelOutput: [
                    "type": "json",
                    "value": [
                        "type": "encrypted_code_execution_result",
                        "encrypted_stdout": "enc_abc123",
                        "stderr": "",
                        "return_code": 0,
                        "content": []
                    ]
                ]
            ))
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    let codeResult = try #require(content.first { $0["type"]?.stringValue == "code_execution_tool_result" })
    #expect(codeResult["tool_use_id"]?.stringValue == "srvtoolu_codeexec_01")
    #expect(codeResult["content"]?["type"]?.stringValue == "encrypted_code_execution_result")
    #expect(codeResult["content"]?["encrypted_stdout"]?.stringValue == "enc_abc123")
    #expect(codeResult["content"]?["stderr"]?.stringValue == "")
    #expect(codeResult["content"]?["return_code"]?.intValue == 0)
    #expect(codeResult["content"]?["content"]?.arrayValue == [])
    #expect(result.warnings.isEmpty)
}

@Test func anthropicProviderExecutedTextEditorAndBashCodeExecutionRoundTripsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "srvtoolu_01Hq9rR6fZwwDGHkTYRafn7k",
                name: "code_execution",
                arguments: #"{"type":"text_editor_code_execution","command":"create","path":"/tmp/fibonacci.py","file_text":"def.."}"#,
                providerExecuted: true
            )),
            .toolResult(AIToolResult(
                toolCallID: "srvtoolu_01Hq9rR6fZwwDGHkTYRafn7k",
                toolName: "code_execution",
                result: [:],
                modelOutput: [
                    "type": "json",
                    "value": [
                        "type": "text_editor_code_execution_create_result",
                        "is_file_update": false
                    ]
                ]
            )),
            .toolCall(AIToolCall(
                id: "srvtoolu_0193G3ttnkiTfZASwHQSKc2V",
                name: "code_execution",
                arguments: #"{"type":"bash_code_execution","command":"python /tmp/fibonacci.py"}"#,
                providerExecuted: true
            )),
            .toolResult(AIToolResult(
                toolCallID: "srvtoolu_0193G3ttnkiTfZASwHQSKc2V",
                toolName: "code_execution",
                result: [:],
                modelOutput: [
                    "type": "json",
                    "value": [
                        "type": "bash_code_execution_result",
                        "content": [],
                        "stdout": "The 10th Fibonacci number is: 34\n",
                        "stderr": "",
                        "return_code": 0
                    ]
                ]
            ))
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content.map { $0["type"]?.stringValue } == [
        "server_tool_use",
        "text_editor_code_execution_tool_result",
        "server_tool_use",
        "bash_code_execution_tool_result"
    ])
    #expect(content[0]["name"]?.stringValue == "text_editor_code_execution")
    #expect(content[0]["input"]?["file_text"]?.stringValue == "def..")
    #expect(content[1]["tool_use_id"]?.stringValue == "srvtoolu_01Hq9rR6fZwwDGHkTYRafn7k")
    #expect(content[1]["content"]?["type"]?.stringValue == "text_editor_code_execution_create_result")
    #expect(content[1]["content"]?["is_file_update"]?.boolValue == false)
    #expect(content[2]["name"]?.stringValue == "bash_code_execution")
    #expect(content[2]["input"]?["command"]?.stringValue == "python /tmp/fibonacci.py")
    #expect(content[3]["tool_use_id"]?.stringValue == "srvtoolu_0193G3ttnkiTfZASwHQSKc2V")
    #expect(content[3]["content"]?["type"]?.stringValue == "bash_code_execution_result")
    #expect(content[3]["content"]?["stdout"]?.stringValue == "The 10th Fibonacci number is: 34\n")
    #expect(content[3]["content"]?["return_code"]?.intValue == 0)
    #expect(result.warnings.isEmpty)
}

@Test func anthropicStreamedSkillToolCallPreservesTextEditorDiscriminatorLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"claude-sonnet-4-5-20250929","stop_reason":null,"usage":{"input_tokens":1,"output_tokens":1}}}

    data: {"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use","id":"srvtoolu_pptx_skill","name":"text_editor_code_execution","input":{}}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":""}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"co"}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"mmand\\": \\""}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"view\\""}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":", \\"path\\": \\""}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"/skills"}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"/pptx/"}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"SKILL"}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":".md\\"}"}}

    data: {"type":"content_block_stop","index":0}

    data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":4}}

    data: {"type":"message_stop"}

    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    var toolCalls: [AIToolCall] = []
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Create a PowerPoint presentation.")],
        tools: [
            "anthropic.code_execution_20250825": [
                "type": "provider",
                "id": "anthropic.code_execution_20250825",
                "name": "code_execution",
                "args": [:]
            ]
        ],
        providerOptions: [
            "anthropic": [
                "container": [
                    "skills": [
                        ["type": "anthropic", "skillId": "pptx"]
                    ]
                ]
            ]
        ]
    )) {
        if case let .toolCall(call) = part {
            toolCalls.append(call)
        }
    }

    let skillReadToolCall = try #require(toolCalls.first {
        $0.name == "code_execution" && $0.arguments.contains("/skills/pptx/SKILL.md")
    })
    #expect(skillReadToolCall.providerExecuted == true)
    #expect(skillReadToolCall.arguments == #"{"type":"text_editor_code_execution","command": "view", "path": "/skills/pptx/SKILL.md"}"#)
}
