import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesSkipsProviderExecutedToolCallsAndResultsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .text("Let me search for recent news from San Francisco."),
                .toolCall(AIToolCall(
                    id: "ws_67cf2b3051e88190b006770db6fdb13d",
                    name: "web_search",
                    arguments: #"{"query":"San Francisco major news events June 22 2025"}"#,
                    providerExecuted: true
                )),
                .toolResult(AIToolResult(
                    toolCallID: "ws_67cf2b3051e88190b006770db6fdb13d",
                    toolName: "web_search",
                    result: [
                        "type": "json",
                        "value": [
                            "action": [
                                "type": "search",
                                "query": "San Francisco major news events June 22 2025"
                            ],
                            "sources": [
                                [
                                    "type": "url",
                                    "url": "https://patch.com/california/san-francisco/calendar"
                                ]
                            ]
                        ]
                    ]
                )),
                .text("Based on the search results, several significant events took place in San Francisco yesterday (June 22, 2025).")
            ])
        ],
        extraBody: ["store": false]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 2)
    #expect(input[0]["role"]?.stringValue == "assistant")
    #expect(input[0]["content"]?[0]?["text"]?.stringValue == "Let me search for recent news from San Francisco.")
    #expect(input[1]["role"]?.stringValue == "assistant")
    #expect(input[1]["content"]?[0]?["text"]?.stringValue == "Based on the search results, several significant events took place in San Francisco yesterday (June 22, 2025).")
    #expect(result.warnings.count == 1)
    #expect(result.warnings.first?.type == "other")
    #expect(result.warnings.first?.message == "Results for OpenAI tool web_search are not sent to the API when store is false")
}

@Test func openAIResponsesSkipsExecutionDeniedAssistantToolResultsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .text("I need approval before running that tool."),
                .toolResult(AIToolResult(
                    toolCallID: "ws_denied_123",
                    toolName: "web_search",
                    result: ["type": "execution-denied", "reason": "User denied the tool execution"]
                )),
                .toolResult(AIToolResult(
                    toolCallID: "ws_denied_json_123",
                    toolName: "web_search",
                    result: [
                        "type": "json",
                        "value": [
                            "type": "execution-denied",
                            "reason": "User denied the tool execution"
                        ]
                    ]
                )),
                .text("The tool was not run.")
            ])
        ],
        extraBody: ["store": false]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 2)
    #expect(input[0]["content"]?[0]?["text"]?.stringValue == "I need approval before running that tool.")
    #expect(input[1]["content"]?[0]?["text"]?.stringValue == "The tool was not run.")
    #expect(result.warnings.isEmpty)
}
