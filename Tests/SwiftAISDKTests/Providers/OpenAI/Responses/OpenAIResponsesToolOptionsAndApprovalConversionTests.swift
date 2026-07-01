import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesMapsCustomToolChoice() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"custom"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use the custom tool.")],
        tools: [
            "grammar_tool": [
                "type": "provider",
                "id": "openai.custom",
                "name": "grammar_tool",
                "args": ["format": ["type": "text"]]
            ]
        ],
        extraBody: ["toolChoice": ["type": "tool", "toolName": "grammar_tool"]]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["tool_choice"]?["type"]?.stringValue == "custom")
    #expect(body["tool_choice"]?["name"]?.stringValue == "grammar_tool")
}
@Test func openAIResponsesMapsContextManagementCompactionLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    for try await _ in model.stream(LanguageModelRequest(
        messages: [.user("Compact context.")],
        extraBody: [
            "openai": [
                "store": false,
                "contextManagement": [
                    ["type": "compaction", "compactThreshold": 50000]
                ]
            ]
        ]
    )) {}

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["store"]?.boolValue == false)
    #expect(body["context_management"]?[0]?["type"]?.stringValue == "compaction")
    #expect(body["context_management"]?[0]?["compact_threshold"]?.intValue == 50000)
    #expect(body["contextManagement"] == nil)
    #expect(body["context_management"]?[0]?["compactThreshold"] == nil)
}
@Test func openAIResponsesMapsProviderExecutedToolApprovalResponses() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#),
        jsonResponse(#"{"id":"resp-2","status":"completed","output_text":"done"}"#)
    ])
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let approvalResponse = AIToolApprovalResponse(id: "approval-for-mcp", approved: true, providerExecuted: true)
    let duplicateApprovalResponse = AIToolApprovalResponse(id: "approval-for-mcp", approved: false, providerExecuted: true)
    let localApprovalResponse = AIToolApprovalResponse(id: "local-approval", approved: true)
    let regularResult = AIToolResult(
        toolCallID: "regular-call-1",
        toolName: "calculator",
        result: ["result": 42]
    )
    let deniedProviderResult = AIToolResult(
        toolCallID: "mcp-call-1",
        toolName: "mcp.create_short_url",
        result: ["type": "execution-denied", "reason": "Denied"],
        providerMetadata: ["openai": ["approvalId": "approval-for-mcp"]]
    )

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            .user("Continue."),
            .toolResponses(
                approvalResponses: [approvalResponse, duplicateApprovalResponse, localApprovalResponse],
                toolResults: [regularResult, deniedProviderResult]
            )
        ]
    ))

    let firstBody = try decodeJSONBody(try #require((await transport.requests())[0].body))
    let firstInput = try #require(firstBody["input"]?.arrayValue)
    #expect(firstInput.count == 4)
    #expect(firstInput[1]["type"]?.stringValue == "item_reference")
    #expect(firstInput[1]["id"]?.stringValue == "approval-for-mcp")
    #expect(firstInput[2]["type"]?.stringValue == "mcp_approval_response")
    #expect(firstInput[2]["approval_request_id"]?.stringValue == "approval-for-mcp")
    #expect(firstInput[2]["approve"]?.boolValue == true)
    #expect(firstInput[3]["type"]?.stringValue == "function_call_output")
    #expect(firstInput[3]["call_id"]?.stringValue == "regular-call-1")
    #expect(firstInput[3]["output"]?.stringValue == #"{"result":42}"#)

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            .toolResponses(approvalResponses: [approvalResponse])
        ],
        extraBody: ["openai": ["store": false]]
    ))

    let secondBody = try decodeJSONBody(try #require((await transport.requests())[1].body))
    let secondInput = try #require(secondBody["input"]?.arrayValue)
    #expect(secondInput.count == 1)
    #expect(secondInput[0]["type"]?.stringValue == "mcp_approval_response")
    #expect(secondInput[0]["approval_request_id"]?.stringValue == "approval-for-mcp")
    #expect(secondInput[0]["approve"]?.boolValue == true)
}
