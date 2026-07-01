import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicProviderExecutedWebFetchRoundTripsLikeUpstream() async throws {
    let fetchURL = "https://raw.githubusercontent.com/vercel/ai/blob/main/examples/ai-functions/data/ai.pdf"
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "srvtoolu_011cNtbtzFARKPcAcp7w4nh9",
                name: "web_fetch",
                arguments: #"{"url":"\#(fetchURL)"}"#,
                providerExecuted: true
            )),
            .toolResult(AIToolResult(
                toolCallID: "srvtoolu_011cNtbtzFARKPcAcp7w4nh9",
                toolName: "web_fetch",
                result: [:],
                modelOutput: [
                    "type": "json",
                    "value": [
                        "type": "web_fetch_result",
                        "url": .string(fetchURL),
                        "retrievedAt": "2025-01-01T00:00:00.000Z",
                        "content": [
                            "type": "document",
                            "title": "AI.pdf",
                            "citations": ["enabled": true],
                            "source": [
                                "type": "text",
                                "mediaType": "text/plain",
                                "data": "The PDF says about AI."
                            ]
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
    #expect(content[0]["id"]?.stringValue == "srvtoolu_011cNtbtzFARKPcAcp7w4nh9")
    #expect(content[0]["name"]?.stringValue == "web_fetch")
    #expect(content[0]["input"]?["url"]?.stringValue == fetchURL)
    #expect(content[1]["type"]?.stringValue == "web_fetch_tool_result")
    #expect(content[1]["tool_use_id"]?.stringValue == "srvtoolu_011cNtbtzFARKPcAcp7w4nh9")
    let fetchResult = try #require(content[1]["content"])
    #expect(fetchResult["type"]?.stringValue == "web_fetch_result")
    #expect(fetchResult["url"]?.stringValue == fetchURL)
    #expect(fetchResult["retrieved_at"]?.stringValue == "2025-01-01T00:00:00.000Z")
    #expect(fetchResult["content"]?["type"]?.stringValue == "document")
    #expect(fetchResult["content"]?["title"]?.stringValue == "AI.pdf")
    #expect(fetchResult["content"]?["citations"]?["enabled"]?.boolValue == true)
    #expect(fetchResult["content"]?["source"]?["type"]?.stringValue == "text")
    #expect(fetchResult["content"]?["source"]?["media_type"]?.stringValue == "text/plain")
    #expect(fetchResult["content"]?["source"]?["data"]?.stringValue == "The PDF says about AI.")
    #expect(result.warnings.isEmpty)
}

@Test func anthropicProviderExecutedWebFetchErrorStringRoundTripsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "srvtoolu_016yTvwN6L1sDdjdPUzPbZRV",
                name: "web_fetch",
                arguments: #"{"url":"https://httpbin.org/status/500"}"#,
                providerExecuted: true
            )),
            .toolResult(AIToolResult(
                toolCallID: "srvtoolu_016yTvwN6L1sDdjdPUzPbZRV",
                toolName: "web_fetch",
                result: [:],
                modelOutput: [
                    "type": "error-json",
                    "value": #"{"type":"web_fetch_tool_result_error","errorCode":"url_not_accessible"}"#
                ]
            ))
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content[1]["type"]?.stringValue == "web_fetch_tool_result")
    #expect(content[1]["tool_use_id"]?.stringValue == "srvtoolu_016yTvwN6L1sDdjdPUzPbZRV")
    #expect(content[1]["content"]?["type"]?.stringValue == "web_fetch_tool_result_error")
    #expect(content[1]["content"]?["error_code"]?.stringValue == "url_not_accessible")
    #expect(result.warnings.isEmpty)
}

@Test func anthropicProviderExecutedWebFetchErrorObjectRoundTripsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "srvtoolu_01JteKo9VRHDKZ1rdMXywnwD",
                name: "web_fetch",
                arguments: #"{"url":"https://www.fotball.no/fotballdata/turnering/hjem/?fiksId=193156"}"#,
                providerExecuted: true
            )),
            .toolResult(AIToolResult(
                toolCallID: "srvtoolu_01JteKo9VRHDKZ1rdMXywnwD",
                toolName: "web_fetch",
                result: [:],
                modelOutput: [
                    "type": "error-json",
                    "value": [
                        "type": "web_fetch_tool_result_error",
                        "errorCode": "url_not_allowed"
                    ]
                ]
            ))
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content[1]["content"]?["type"]?.stringValue == "web_fetch_tool_result_error")
    #expect(content[1]["content"]?["error_code"]?.stringValue == "url_not_allowed")
    #expect(result.warnings.isEmpty)
}

@Test func anthropicProviderExecutedWebFetchMalformedErrorDefaultsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "srvtoolu_test123",
                name: "web_fetch",
                arguments: #"{"url":"https://example.com"}"#,
                providerExecuted: true
            )),
            .toolResult(AIToolResult(
                toolCallID: "srvtoolu_test123",
                toolName: "web_fetch",
                result: [:],
                modelOutput: [
                    "type": "error-json",
                    "value": "not valid json at all"
                ]
            ))
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content[1]["type"]?.stringValue == "web_fetch_tool_result")
    #expect(content[1]["tool_use_id"]?.stringValue == "srvtoolu_test123")
    #expect(content[1]["content"]?["type"]?.stringValue == "web_fetch_tool_result_error")
    #expect(content[1]["content"]?["error_code"]?.stringValue == "unavailable")
    #expect(result.warnings.isEmpty)
}
