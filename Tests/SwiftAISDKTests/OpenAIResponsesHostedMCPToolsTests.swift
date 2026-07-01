import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesSendsMCPToolRequestBodyLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesMCPToolFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-mini")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesMCPTool()
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "gpt-5-mini")
    #expect(body["input"]?[0]?["role"]?.stringValue == "user")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    let tool = try #require(body["tools"]?[0])
    #expect(tool["type"]?.stringValue == "mcp")
    #expect(tool["server_label"]?.stringValue == "dmcp")
    #expect(tool["server_url"]?.stringValue == "https://mcp.exa.ai/mcp")
    #expect(tool["server_description"]?.stringValue == "A web-search API for AI agents")
    #expect(tool["require_approval"]?.stringValue == "never")
}

@Test func openAIResponsesIncludesMCPToolContentLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesMCPToolFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-mini")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesMCPTool()
    ))

    #expect(result.content.count == 5)
    guard case let .reasoning(firstReasoning, firstReasoningMetadata) = result.content[0],
          case let .toolCall(toolCall) = result.content[1],
          case let .toolResult(toolResult) = result.content[2],
          case let .reasoning(secondReasoning, secondReasoningMetadata) = result.content[3],
          case let .text(text, textMetadata) = result.content[4] else {
        Issue.record("Expected upstream MCP tool content order")
        return
    }

    #expect(firstReasoning == "")
    #expect(firstReasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_0a4801d792de11eb00690ccb8775988197b6c6f6d3f6882f5e")
    #expect(firstReasoningMetadata["openai"]?["reasoningEncryptedContent"] == .null)
    #expect(toolCall.id == "mcp_0a4801d792de11eb00690ccb8c3fac8197a4fd94f4528cd432")
    #expect(toolCall.name == "mcp.web_search_exa")
    #expect(toolCall.arguments == #"{"query":"NYC mayoral election results 2025 latest","numResults":5}"#)
    #expect(toolCall.providerExecuted == true)
    #expect(toolCall.dynamic == true)
    #expect(toolCall.providerMetadata.isEmpty)

    #expect(toolResult.toolCallID == toolCall.id)
    #expect(toolResult.toolName == "mcp.web_search_exa")
    #expect(toolResult.dynamic == true)
    #expect(toolResult.providerMetadata["openai"]?["itemId"]?.stringValue == "mcp_0a4801d792de11eb00690ccb8c3fac8197a4fd94f4528cd432")
    #expect(toolResult.result["type"]?.stringValue == "call")
    #expect(toolResult.result["serverLabel"]?.stringValue == "dmcp")
    #expect(toolResult.result["name"]?.stringValue == "web_search_exa")
    #expect(toolResult.result["arguments"]?.stringValue == #"{"query":"NYC mayoral election results 2025 latest","numResults":5}"#)
    #expect(toolResult.result["output"]?.stringValue?.contains(#""requestId":"c72ab09f496225ba33162f7aca08ef60""#) == true)

    #expect(secondReasoning == "")
    #expect(secondReasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_0a4801d792de11eb00690ccb937c208197be08d2d715b7a1a0")
    #expect(text.contains("Zohran Mamdani projected as the winner"))
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_0a4801d792de11eb00690ccb9aec948197aa075d716ac02575")
}

@Test func openAIResponsesSendsMCPApprovalRequestBodyLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesMCPApprovalTurn1FixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-mini")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesMCPApprovalTool()
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "gpt-5-mini")
    #expect(body["input"]?[0]?["role"]?.stringValue == "user")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    let tool = try #require(body["tools"]?[0])
    #expect(tool["type"]?.stringValue == "mcp")
    #expect(tool["server_label"]?.stringValue == "zip1")
    #expect(tool["server_url"]?.stringValue == "https://zip1.io/mcp")
    #expect(tool["server_description"]?.stringValue == "Link shortener")
    #expect(tool["require_approval"]?.stringValue == "always")
}

@Test func openAIResponsesEmitsMCPToolCallAndApprovalRequestLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesMCPApprovalTurn1FixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-mini")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesMCPApprovalTool()
    ))

    #expect(result.content.count == 3)
    guard case let .reasoning(reasoning, reasoningMetadata) = result.content[0],
          case let .toolCall(toolCall) = result.content[1],
          case let .toolApprovalRequest(approvalRequest) = result.content[2] else {
        Issue.record("Expected upstream MCP approval request content order")
        return
    }

    #expect(reasoning == "")
    #expect(reasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_04f6b17429cf2b02006949a66f4df88196a44362d8a21f9cea")
    #expect(reasoningMetadata["openai"]?["reasoningEncryptedContent"] == .null)
    #expect(toolCall.id == "id-0")
    #expect(toolCall.name == "mcp.create_short_url")
    #expect(toolCall.arguments == #"{"alias":"","description":"","max_clicks":100,"password":"","url":"https://ai-sdk.dev/"}"#)
    #expect(toolCall.providerExecuted == true)
    #expect(toolCall.dynamic == true)
    #expect(toolCall.providerMetadata.isEmpty)
    #expect(approvalRequest.id == "mcpr_04f6b17429cf2b02006949a6712b1081968b3c7a72dec695d8")
    #expect(approvalRequest.toolCallID == "id-0")
    #expect(approvalRequest.toolName == "mcp.create_short_url")
    #expect(approvalRequest.arguments == #"{"alias":"","description":"","max_clicks":100,"password":"","url":"https://ai-sdk.dev/"}"#)
    #expect(approvalRequest.providerMetadata.isEmpty)
    #expect(result.finishReason == "stop")
}

@Test func openAIResponsesEmitsMCPTextAfterApprovalDenialLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesMCPApprovalTurn2FixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-mini")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .user("shorten ai-sdk.dev"),
            AIMessage(role: .assistant, content: [
                .toolCall(AIToolCall(
                    id: "mcpr_04f6b17429cf2b02006949a6712b1081968b3c7a72dec695d8",
                    name: "mcp.create_short_url",
                    arguments: #"{"url":"https://ai-sdk.dev/"}"#,
                    providerExecuted: true
                ))
            ]),
            .toolResponses(approvalResponses: [
                AIToolApprovalResponse(
                    id: "mcpr_04f6b17429cf2b02006949a6712b1081968b3c7a72dec695d8",
                    approved: false,
                    providerExecuted: true
                )
            ])
        ],
        tools: openAIResponsesMCPApprovalTool()
    ))

    #expect(result.content.count == 2)
    guard case let .reasoning(reasoning, reasoningMetadata) = result.content[0],
          case let .text(text, textMetadata) = result.content[1] else {
        Issue.record("Expected upstream MCP approval denial text content")
        return
    }

    #expect(reasoning == "")
    #expect(reasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_04f6b17429cf2b02006949a67543c88196ad1f56cb7c8fe476")
    #expect(text.contains("the shortening tool call was not approved"))
    #expect(text.contains("If you don't want me to use the tool"))
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_04f6b17429cf2b02006949a679f35c81968e9b234489fa32b8")
    #expect(result.finishReason == "stop")
}

@Test func openAIResponsesEmitsNewMCPApprovalRequestWhenRetryingLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesMCPApprovalTurn3FixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-mini")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .user("shorten ai-sdk.dev"),
            AIMessage(role: .assistant, content: [
                .toolCall(AIToolCall(
                    id: "mcpr_04f6b17429cf2b02006949a6712b1081968b3c7a72dec695d8",
                    name: "mcp.create_short_url",
                    arguments: #"{"url":"https://ai-sdk.dev/"}"#,
                    providerExecuted: true
                ))
            ]),
            .toolResponses(approvalResponses: [
                AIToolApprovalResponse(
                    id: "mcpr_04f6b17429cf2b02006949a6712b1081968b3c7a72dec695d8",
                    approved: false,
                    providerExecuted: true
                )
            ]),
            AIMessage(role: .assistant, content: [.text("The tool was not approved.")]),
            .user("try again")
        ],
        tools: openAIResponsesMCPApprovalTool()
    ))

    #expect(result.content.count == 3)
    guard case let .reasoning(reasoning, reasoningMetadata) = result.content[0],
          case let .toolCall(toolCall) = result.content[1],
          case let .toolApprovalRequest(approvalRequest) = result.content[2] else {
        Issue.record("Expected upstream MCP retry approval request content")
        return
    }

    #expect(reasoning == "")
    #expect(reasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_04f6b17429cf2b02006949a68a9c7c8196b850018869363b06")
    #expect(toolCall.id == "id-0")
    #expect(toolCall.name == "mcp.create_short_url")
    #expect(toolCall.arguments == #"{"alias":"","description":"","max_clicks":100,"password":"","url":"https://ai-sdk.dev/"}"#)
    #expect(toolCall.providerExecuted == true)
    #expect(toolCall.dynamic == true)
    #expect(approvalRequest.id == "mcpr_04f6b17429cf2b02006949a68bf5808196b6f2008a315c9aa4")
    #expect(approvalRequest.toolCallID == "id-0")
    #expect(approvalRequest.toolName == "mcp.create_short_url")
    #expect(approvalRequest.arguments == #"{"alias":"","description":"","max_clicks":100,"password":"","url":"https://ai-sdk.dev/"}"#)
    #expect(result.finishReason == "stop")
}

@Test func openAIResponsesEmitsMCPToolCallWithResultAfterApprovalLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesMCPApprovalTurn4FixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-mini")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .user("shorten ai-sdk.dev"),
            AIMessage(role: .assistant, content: [
                .toolCall(AIToolCall(
                    id: "mcpr_04f6b17429cf2b02006949a68bf5808196b6f2008a315c9aa4",
                    name: "mcp.create_short_url",
                    arguments: #"{"url":"https://ai-sdk.dev/"}"#,
                    providerExecuted: true
                ))
            ]),
            .toolResponses(approvalResponses: [
                AIToolApprovalResponse(
                    id: "mcpr_04f6b17429cf2b02006949a68bf5808196b6f2008a315c9aa4",
                    approved: true,
                    providerExecuted: true
                )
            ])
        ],
        tools: openAIResponsesMCPApprovalTool()
    ))

    #expect(result.content.count == 3)
    guard case let .toolCall(toolCall) = result.content[0],
          case let .toolResult(toolResult) = result.content[1],
          case let .text(text, textMetadata) = result.content[2] else {
        Issue.record("Expected upstream approved MCP call/result content")
        return
    }

    #expect(toolCall.id == "mcp_04f6b17429cf2b02006949a6908fc4819686c02f71f7faecc6")
    #expect(toolCall.name == "mcp.create_short_url")
    #expect(toolCall.arguments == #"{"alias":"","description":"","max_clicks":100,"password":"","url":"https://ai-sdk.dev/"}"#)
    #expect(toolCall.providerExecuted == true)
    #expect(toolCall.dynamic == true)
    #expect(toolResult.toolCallID == toolCall.id)
    #expect(toolResult.toolName == "mcp.create_short_url")
    #expect(toolResult.dynamic == true)
    #expect(toolResult.providerMetadata["openai"]?["itemId"]?.stringValue == "mcp_04f6b17429cf2b02006949a6908fc4819686c02f71f7faecc6")
    #expect(toolResult.result["type"]?.stringValue == "call")
    #expect(toolResult.result["serverLabel"]?.stringValue == "zip1")
    #expect(toolResult.result["name"]?.stringValue == "create_short_url")
    #expect(toolResult.result["arguments"]?.stringValue == #"{"alias":"","description":"","max_clicks":100,"password":"","url":"https://ai-sdk.dev/"}"#)
    #expect(toolResult.result["output"]?.stringValue?.contains("Short URL created: https://zip1.io/oMAchr") == true)
    #expect(text.contains("Done"))
    #expect(text.contains("https://zip1.io/oMAchr"))
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_04f6b17429cf2b02006949a6930b308196a3ad4f35aa6e0b1b")
    #expect(result.finishReason == "stop")
}

