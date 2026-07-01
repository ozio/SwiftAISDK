import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesConvertsLocalShellCallAndResultLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#),
        jsonResponse(#"{"id":"resp-2","status":"completed","output_text":"done"}"#)
    ])
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")
    let call = AIToolCall(
        id: "call_XWgeTylovOiS8xLNz2TONOgO",
        name: "local_shell",
        arguments: #"{"action":{"type":"exec","command":["ls"]}}"#,
        providerMetadata: ["openai": ["itemId": "lsh_68c2e2cf522c81908f3e2c1bccd1493b0b24aae9c6c01e4f"]]
    )
    let result = AIToolResult(
        toolCallID: "call_XWgeTylovOiS8xLNz2TONOgO",
        toolName: "local_shell",
        result: ["type": "json", "value": ["output": "example output"]]
    )

    _ = try await model.generate(LanguageModelRequest(
        messages: [.assistant(toolCalls: [call]), .toolResult(result)],
        extraBody: ["store": true]
    ))
    _ = try await model.generate(LanguageModelRequest(
        messages: [.assistant(toolCalls: [call]), .toolResult(result)],
        extraBody: ["store": false]
    ))

    let firstBody = try decodeJSONBody(try #require((await transport.requests())[0].body))
    let firstInput = try #require(firstBody["input"]?.arrayValue)
    #expect(firstInput.count == 2)
    #expect(firstInput[0]["type"]?.stringValue == "item_reference")
    #expect(firstInput[0]["id"]?.stringValue == "lsh_68c2e2cf522c81908f3e2c1bccd1493b0b24aae9c6c01e4f")
    #expect(firstInput[1]["type"]?.stringValue == "local_shell_call_output")
    #expect(firstInput[1]["call_id"]?.stringValue == "call_XWgeTylovOiS8xLNz2TONOgO")
    #expect(firstInput[1]["output"]?.stringValue == "example output")

    let secondBody = try decodeJSONBody(try #require((await transport.requests())[1].body))
    let secondInput = try #require(secondBody["input"]?.arrayValue)
    #expect(secondInput.count == 2)
    #expect(secondInput[0]["type"]?.stringValue == "local_shell_call")
    #expect(secondInput[0]["call_id"]?.stringValue == "call_XWgeTylovOiS8xLNz2TONOgO")
    #expect(secondInput[0]["id"]?.stringValue == "lsh_68c2e2cf522c81908f3e2c1bccd1493b0b24aae9c6c01e4f")
    #expect(secondInput[0]["action"]?["type"]?.stringValue == "exec")
    #expect(secondInput[0]["action"]?["command"]?[0]?.stringValue == "ls")
    #expect(secondInput[1]["type"]?.stringValue == "local_shell_call_output")
    #expect(secondInput[1]["output"]?.stringValue == "example output")
}

@Test func openAIResponsesConvertsApplyPatchCallsAndOutputsLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#),
        jsonResponse(#"{"id":"resp-2","status":"completed","output_text":"done"}"#)
    ])
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")
    let createCall = AIToolCall(
        id: "call_INoksNAffcdh5UmRTWMLk1Ne",
        name: "apply_patch",
        arguments: #"{"callId":"call_INoksNAffcdh5UmRTWMLk1Ne","operation":{"type":"create_file","path":"index.html","diff":"+<!doctype html>\n+<html></html>"}}"#,
        providerMetadata: ["openai": ["itemId": "apc_0d5dfb28a009b1ee0169713022c3f88195a70b253d2a8cf798"]]
    )
    let createResult = AIToolResult(
        toolCallID: "call_INoksNAffcdh5UmRTWMLk1Ne",
        toolName: "apply_patch",
        result: ["type": "json", "value": ["status": "completed", "output": "Created index.html"]]
    )

    _ = try await model.generate(LanguageModelRequest(
        messages: [.assistant(toolCalls: [createCall]), .toolResult(createResult)],
        extraBody: ["store": true]
    ))
    _ = try await model.generate(LanguageModelRequest(
        messages: [
            .assistant(toolCalls: [
                createCall,
                AIToolCall(
                    id: "call_UpdateFile123",
                    name: "apply_patch",
                    arguments: #"{"callId":"call_UpdateFile123","operation":{"type":"update_file","path":"src/app.ts","diff":"-old line\n+new line"}}"#,
                    providerMetadata: ["openai": ["itemId": "apc_update_file_item_id"]]
                ),
                AIToolCall(
                    id: "call_DeleteFile456",
                    name: "apply_patch",
                    arguments: #"{"callId":"call_DeleteFile456","operation":{"type":"delete_file","path":"temp.txt"}}"#,
                    providerMetadata: ["openai": ["itemId": "apc_delete_file_item_id"]]
                )
            ]),
            .toolResult(createResult)
        ],
        extraBody: ["store": false]
    ))

    let firstBody = try decodeJSONBody(try #require((await transport.requests())[0].body))
    let firstInput = try #require(firstBody["input"]?.arrayValue)
    #expect(firstInput.count == 2)
    #expect(firstInput[0]["type"]?.stringValue == "item_reference")
    #expect(firstInput[0]["id"]?.stringValue == "apc_0d5dfb28a009b1ee0169713022c3f88195a70b253d2a8cf798")
    #expect(firstInput[1]["type"]?.stringValue == "apply_patch_call_output")
    #expect(firstInput[1]["call_id"]?.stringValue == "call_INoksNAffcdh5UmRTWMLk1Ne")
    #expect(firstInput[1]["status"]?.stringValue == "completed")
    #expect(firstInput[1]["output"]?.stringValue == "Created index.html")

    let secondBody = try decodeJSONBody(try #require((await transport.requests())[1].body))
    let secondInput = try #require(secondBody["input"]?.arrayValue)
    #expect(secondInput.count == 4)
    #expect(secondInput[0]["type"]?.stringValue == "apply_patch_call")
    #expect(secondInput[0]["call_id"]?.stringValue == "call_INoksNAffcdh5UmRTWMLk1Ne")
    #expect(secondInput[0]["operation"]?["type"]?.stringValue == "create_file")
    #expect(secondInput[0]["operation"]?["path"]?.stringValue == "index.html")
    #expect(secondInput[1]["operation"]?["type"]?.stringValue == "update_file")
    #expect(secondInput[1]["operation"]?["path"]?.stringValue == "src/app.ts")
    #expect(secondInput[2]["operation"]?["type"]?.stringValue == "delete_file")
    #expect(secondInput[2]["operation"]?["path"]?.stringValue == "temp.txt")
    #expect(secondInput[3]["type"]?.stringValue == "apply_patch_call_output")
    #expect(secondInput[3]["output"]?.stringValue == "Created index.html")
}

@Test func openAIResponsesConvertsMixedProviderToolOutputsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .tool, content: [
            .toolResult(AIToolResult(
                toolCallID: "call-shell",
                toolName: "shell",
                result: [
                    "type": "json",
                    "value": [
                        "output": [
                            [
                                "stdout": "hi\n",
                                "stderr": "",
                                "outcome": ["type": "exit", "exitCode": 0]
                            ]
                        ]
                    ]
                ]
            )),
            .toolResult(AIToolResult(
                toolCallID: "call-apply",
                toolName: "apply_patch",
                result: ["type": "json", "value": ["status": "completed", "output": "patched"]]
            ))
        ])
    ]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 2)
    #expect(input[0]["type"]?.stringValue == "shell_call_output")
    #expect(input[0]["call_id"]?.stringValue == "call-shell")
    #expect(input[0]["output"]?[0]?["stdout"]?.stringValue == "hi\n")
    #expect(input[0]["output"]?[0]?["outcome"]?["type"]?.stringValue == "exit")
    #expect(input[0]["output"]?[0]?["outcome"]?["exit_code"]?.intValue == 0)
    #expect(input[1]["type"]?.stringValue == "apply_patch_call_output")
    #expect(input[1]["call_id"]?.stringValue == "call-apply")
    #expect(input[1]["status"]?.stringValue == "completed")
    #expect(input[1]["output"]?.stringValue == "patched")
}
