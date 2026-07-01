import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicProviderExecutedWebSearchRoundTripsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "srvtoolu_011cNtbtzFARKPcAcp7w4nh9",
                name: "web_search",
                arguments: #"{"query":"San Francisco major news events June 22 2025"}"#,
                providerExecuted: true
            )),
            .toolResult(AIToolResult(
                toolCallID: "srvtoolu_011cNtbtzFARKPcAcp7w4nh9",
                toolName: "web_search",
                result: [],
                modelOutput: [
                    "type": "json",
                    "value": [
                        [
                            "type": "web_search_result",
                            "url": "https://patch.com/california/san-francisco/calendar",
                            "title": "San Francisco Calendar",
                            "pageAge": nil,
                            "encryptedContent": "encrypted-content"
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
    #expect(content[0]["name"]?.stringValue == "web_search")
    #expect(content[0]["input"]?["query"]?.stringValue == "San Francisco major news events June 22 2025")
    #expect(content[1]["type"]?.stringValue == "web_search_tool_result")
    #expect(content[1]["tool_use_id"]?.stringValue == "srvtoolu_011cNtbtzFARKPcAcp7w4nh9")
    let searchResults = try #require(content[1]["content"]?.arrayValue)
    #expect(searchResults[0]["type"]?.stringValue == "web_search_result")
    #expect(searchResults[0]["url"]?.stringValue == "https://patch.com/california/san-francisco/calendar")
    #expect(searchResults[0]["title"]?.stringValue == "San Francisco Calendar")
    #expect(searchResults[0]["page_age"] == .null)
    #expect(searchResults[0]["encrypted_content"]?.stringValue == "encrypted-content")
    #expect(result.warnings.isEmpty)
}

@Test func anthropicMovesRegularToolUseAfterProviderExecutedWebSearchLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .text("I will save a note and search the web."),
            .toolCall(AIToolCall(
                id: "toolu_regular",
                name: "saveNote",
                arguments: #"{"note":"Searching for basketball news"}"#
            )),
            .toolCall(AIToolCall(
                id: "srvtoolu_web_search",
                name: "web_search",
                arguments: #"{"query":"basketball news today"}"#,
                providerExecuted: true
            )),
            .toolResult(AIToolResult(
                toolCallID: "srvtoolu_web_search",
                toolName: "web_search",
                result: [],
                modelOutput: [
                    "type": "json",
                    "value": [
                        [
                            "type": "web_search_result",
                            "url": "https://www.nba.com/news",
                            "title": "NBA News",
                            "pageAge": "1 hour ago",
                            "encryptedContent": "encrypted-content"
                        ]
                    ]
                ]
            ))
        ]),
        .toolResponses(toolResults: [
            AIToolResult(
                toolCallID: "toolu_regular",
                toolName: "saveNote",
                result: ["success": true],
                modelOutput: ["type": "json", "value": ["success": true]]
            )
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let assistantContent = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(assistantContent.map { $0["type"]?.stringValue } == [
        "text",
        "server_tool_use",
        "web_search_tool_result",
        "tool_use"
    ])
    #expect(assistantContent[1]["id"]?.stringValue == "srvtoolu_web_search")
    #expect(assistantContent[2]["tool_use_id"]?.stringValue == "srvtoolu_web_search")
    #expect(assistantContent[2]["content"]?[0]?["page_age"]?.stringValue == "1 hour ago")
    #expect(assistantContent[3]["id"]?.stringValue == "toolu_regular")
    #expect(assistantContent[3]["input"]?["note"]?.stringValue == "Searching for basketball news")

    let regularToolResult = try #require(body["messages"]?[1]?["content"]?[0])
    #expect(regularToolResult["type"]?.stringValue == "tool_result")
    #expect(regularToolResult["tool_use_id"]?.stringValue == "toolu_regular")
    #expect(regularToolResult["content"]?.stringValue == #"{"success":true}"#)
    #expect(result.warnings.isEmpty)
}

@Test func anthropicDoesNotMoveRegularToolUseAcrossThinkingBlocksLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(
            role: .assistant,
            content: [
                .toolCall(AIToolCall(
                    id: "toolu_initial",
                    name: "saveNote",
                    arguments: #"{"note":"phase 1: initial plan"}"#
                ))
            ],
            reasoning: "Think before the initial note.",
            providerMetadata: ["anthropic": ["signature": "test-signature-1"]]
        ),
        AIMessage(
            role: .assistant,
            content: [
                .toolCall(AIToolCall(
                    id: "toolu_revised",
                    name: "saveNote",
                    arguments: #"{"note":"phase 2: revised plan"}"#
                ))
            ],
            reasoning: "Think before the revised note.",
            providerMetadata: ["anthropic": ["signature": "test-signature-2"]]
        ),
        .toolResponses(toolResults: [
            AIToolResult(
                toolCallID: "toolu_initial",
                toolName: "saveNote",
                result: ["unused": true],
                modelOutput: ["type": "json", "value": ["success": true]]
            ),
            AIToolResult(
                toolCallID: "toolu_revised",
                toolName: "saveNote",
                result: ["unused": true],
                modelOutput: ["type": "json", "value": ["success": true]]
            )
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let assistantContent = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(assistantContent == [
        [
            "type": "thinking",
            "thinking": "Think before the initial note.",
            "signature": "test-signature-1"
        ],
        [
            "type": "tool_use",
            "id": "toolu_initial",
            "name": "saveNote",
            "input": ["note": "phase 1: initial plan"]
        ],
        [
            "type": "thinking",
            "thinking": "Think before the revised note.",
            "signature": "test-signature-2"
        ],
        [
            "type": "tool_use",
            "id": "toolu_revised",
            "name": "saveNote",
            "input": ["note": "phase 2: revised plan"]
        ]
    ])
    #expect(body["messages"]?[1]?["content"] == [
        [
            "type": "tool_result",
            "tool_use_id": "toolu_initial",
            "content": #"{"success":true}"#
        ],
        [
            "type": "tool_result",
            "tool_use_id": "toolu_revised",
            "content": #"{"success":true}"#
        ]
    ])
    #expect(result.warnings.isEmpty)
}
