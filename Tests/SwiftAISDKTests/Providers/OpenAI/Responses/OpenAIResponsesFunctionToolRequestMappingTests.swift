import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesGroupsFunctionToolsByNamespaceAndIncludesToolCallNamespace() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            .user("Use namespaced tools."),
            .assistant(toolCalls: [
                AIToolCall(
                    id: "call-1",
                    name: "sum",
                    arguments: #"{"a":1,"b":2}"#,
                    providerMetadata: ["openai": ["namespace": "math"]]
                )
            ])
        ],
        tools: [
            "sum": [
                "type": "object",
                "properties": ["a": ["type": "number"], "b": ["type": "number"]],
                "providerOptions": [
                    "openai": [
                        "namespace": ["name": "math", "description": "Math tools"],
                        "deferLoading": true
                    ]
                ]
            ],
            "multiply": [
                "type": "object",
                "properties": ["a": ["type": "number"], "b": ["type": "number"]],
                "providerOptions": [
                    "openai": [
                        "namespace": ["name": "math", "description": "Math tools"]
                    ]
                ]
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let namespace = try #require(body["tools"]?.arrayValue?.first { $0["type"]?.stringValue == "namespace" })
    #expect(namespace["name"]?.stringValue == "math")
    #expect(namespace["description"]?.stringValue == "Math tools")
    #expect(namespace["tools"]?.arrayValue?.count == 2)
    let sum = try #require(namespace["tools"]?.arrayValue?.first { $0["name"]?.stringValue == "sum" })
    #expect(sum["type"]?.stringValue == "function")
    #expect(sum["defer_loading"]?.boolValue == true)
    #expect(sum["parameters"]?["providerOptions"] == nil)
    #expect(sum["parameters"]?["openai"] == nil)
    let input = try #require(body["input"]?.arrayValue)
    let functionCall = try #require(input.first { $0["type"]?.stringValue == "function_call" })
    #expect(functionCall["namespace"]?.stringValue == "math")
}

@Test func openAIResponsesDefaultsMissingToolCallInputToEmptyObjectLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            .assistant(toolCalls: [
                AIToolCall(id: "call_123", name: "search", arguments: "")
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 1)
    #expect(input[0]["type"]?.stringValue == "function_call")
    #expect(input[0]["call_id"]?.stringValue == "call_123")
    #expect(input[0]["name"]?.stringValue == "search")
    #expect(input[0]["arguments"]?.stringValue == "{}")
}
