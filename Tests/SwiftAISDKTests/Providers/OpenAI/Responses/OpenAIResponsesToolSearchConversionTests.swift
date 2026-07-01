import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesConvertsProviderExecutedToolSearchLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .toolCall(AIToolCall(
                    id: "tsc_hosted_123",
                    name: "tool_search",
                    arguments: #"{"arguments":{"paths":["get_weather"]},"call_id":null}"#,
                    providerExecuted: true,
                    providerMetadata: ["openai": ["itemId": "tsc_hosted_123"]]
                )),
                .toolResult(AIToolResult(
                    toolCallID: "tsc_hosted_123",
                    toolName: "tool_search",
                    result: [
                        "type": "json",
                        "value": [
                            "tools": [
                                [
                                    "type": "function",
                                    "name": "get_weather",
                                    "defer_loading": true
                                ]
                            ]
                        ]
                    ],
                    providerMetadata: ["openai": ["itemId": "tso_hosted_456"]]
                ))
            ])
        ],
        extraBody: ["store": false]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 2)
    #expect(input[0]["type"]?.stringValue == "tool_search_call")
    #expect(input[0]["id"]?.stringValue == "tsc_hosted_123")
    #expect(input[0]["execution"]?.stringValue == "server")
    #expect(input[0]["call_id"] == .null)
    #expect(input[0]["arguments"]?["paths"]?[0]?.stringValue == "get_weather")
    #expect(input[1]["type"]?.stringValue == "tool_search_output")
    #expect(input[1]["id"]?.stringValue == "tso_hosted_456")
    #expect(input[1]["execution"]?.stringValue == "server")
    #expect(input[1]["call_id"] == .null)
    #expect(input[1]["tools"]?[0]?["name"]?.stringValue == "get_weather")
    #expect(input[1]["tools"]?[0]?["defer_loading"]?.boolValue == true)
}

@Test func openAIResponsesMapsHostedToolSearchPartsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_04bd69550b37ba260069aa689530d0819094482b7c14059a0f","object":"response","created_at":1772775573,"status":"completed","background":false,"billing":{"payer":"developer"},"completed_at":1772775575,"error":null,"frequency_penalty":0,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.4-2026-03-05","output":[{"id":"tsc_04bd69550b37ba260069aa689605cc8190bd2d9bf1199fa630","type":"tool_search_call","status":"completed","arguments":{"paths":["get_weather"]},"call_id":null,"execution":"server"},{"id":"tso_04bd69550b37ba260069aa68965b508190949d19c05f1b6df9","type":"tool_search_output","status":"completed","call_id":null,"execution":"server","tools":[{"type":"function","defer_loading":true,"description":"Get the current weather at a specific location","name":"get_weather","parameters":{"type":"object","properties":{"location":{"type":"string","description":"The city and state, e.g. San Francisco, CA"},"unit":{"type":"string","enum":["celsius","fahrenheit"],"description":"Temperature unit"}},"required":["location","unit"],"additionalProperties":false},"strict":true}]},{"id":"fc_04bd69550b37ba260069aa68969e088190a5ebe91c1448f693","type":"function_call","status":"completed","arguments":"{\\"location\\":\\"San Francisco, CA\\",\\"unit\\":\\"fahrenheit\\"}","call_id":"call_ytqozXvUXG8NN1b0IODxzUaE","name":"get_weather","namespace":"get_weather"}],"parallel_tool_calls":true,"presence_penalty":0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"none","summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"function","defer_loading":true,"description":"Get the current weather at a specific location","name":"get_weather","parameters":{"type":"object","properties":{"location":{"type":"string","description":"The city and state, e.g. San Francisco, CA"},"unit":{"type":"string","enum":["celsius","fahrenheit"],"description":"Temperature unit"}},"required":["location","unit"],"additionalProperties":false},"strict":true},{"type":"function","defer_loading":true,"description":"Search through files in the workspace","name":"search_files","parameters":{"type":"object","properties":{"query":{"type":"string","description":"The search query"},"file_types":{"type":"array","items":{"type":"string"},"description":"Filter by file types"}},"required":["query","file_types"],"additionalProperties":false},"strict":true},{"type":"function","defer_loading":true,"description":"Send an email to a recipient","name":"send_email","parameters":{"type":"object","properties":{"to":{"type":"string","description":"Recipient email address"},"subject":{"type":"string","description":"Email subject"},"body":{"type":"string","description":"Email body content"}},"required":["to","subject","body"],"additionalProperties":false},"strict":true},{"type":"tool_search","description":null,"parameters":null}],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":{"input_tokens":640,"input_tokens_details":{"cached_tokens":0},"output_tokens":46,"output_tokens_details":{"reasoning_tokens":20},"total_tokens":686},"user":null,"metadata":{}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "toolSearch": [
                "type": "provider",
                "id": "openai.tool_search",
                "name": "toolSearch",
                "args": [:]
            ],
            "get_weather": [
                "type": "function",
                "description": "Get the current weather at a specific location",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "location": ["type": "string"],
                        "unit": ["type": "string", "enum": ["celsius", "fahrenheit"]]
                    ],
                    "required": ["location", "unit"],
                    "additionalProperties": false
                ],
                "strict": true,
                "providerOptions": [
                    "openai": ["deferLoading": true]
                ]
            ]
        ]
    ))

    let toolSearchParts = result.content.filter { part in
        switch part {
        case let .toolCall(call):
            return call.name == "toolSearch"
        case let .toolResult(result):
            return result.toolName == "toolSearch"
        default:
            return false
        }
    }
    #expect(toolSearchParts.count == 2)
    guard case let .toolCall(toolCall) = toolSearchParts[0],
          case let .toolResult(toolResult) = toolSearchParts[1] else {
        Issue.record("Expected upstream hosted tool search call/result parts")
        return
    }

    #expect(toolCall.id == "tsc_04bd69550b37ba260069aa689605cc8190bd2d9bf1199fa630")
    #expect(toolCall.name == "toolSearch")
    #expect(toolCall.providerExecuted == true)
    let input = try decodeJSONBody(Data(toolCall.arguments.utf8))
    #expect(input["arguments"]?["paths"]?[0]?.stringValue == "get_weather")
    #expect(input["call_id"] == .null)
    #expect(toolCall.providerMetadata["openai"]?["itemId"]?.stringValue == "tsc_04bd69550b37ba260069aa689605cc8190bd2d9bf1199fa630")

    #expect(toolResult.toolCallID == toolCall.id)
    #expect(toolResult.toolName == "toolSearch")
    #expect(toolResult.providerMetadata["openai"]?["itemId"]?.stringValue == "tso_04bd69550b37ba260069aa68965b508190949d19c05f1b6df9")
    let tool = try #require(toolResult.result["tools"]?[0])
    #expect(tool["type"]?.stringValue == "function")
    #expect(tool["defer_loading"]?.boolValue == true)
    #expect(tool["description"]?.stringValue == "Get the current weather at a specific location")
    #expect(tool["name"]?.stringValue == "get_weather")
    #expect(tool["parameters"]?["properties"]?["unit"]?["enum"]?[1]?.stringValue == "fahrenheit")
    #expect(tool["strict"]?.boolValue == true)
}

@Test func openAIResponsesMapsClientToolSearchCallLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesClientToolSearchFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.4")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesClientToolSearchTools(),
        providerOptions: ["openai": ["store": false]]
    ))

    let toolCall = try #require(result.content.compactMap { part -> AIToolCall? in
        guard case let .toolCall(call) = part, call.name == "toolSearch" else { return nil }
        return call
    }.first)

    #expect(toolCall.id == "call_AEvXZ1rvYpxHh8QZb7wGlTGH")
    #expect(toolCall.name == "toolSearch")
    #expect(toolCall.providerExecuted == false)
    #expect(toolCall.providerMetadata["openai"]?["itemId"]?.stringValue == "tsc_01166e06cf473fc80169ab66ea404881968795bb327c429d35")
    let input = try decodeJSONBody(Data(toolCall.arguments.utf8))
    #expect(input["arguments"]?["goal"]?.stringValue == "Find a tool to get current weather for San Francisco")
    #expect(input["call_id"]?.stringValue == "call_AEvXZ1rvYpxHh8QZb7wGlTGH")
}

@Test func openAIResponsesClientToolSearchProviderExecutedFlagIsFalseLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesClientToolSearchFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.4")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesClientToolSearchTools(),
        providerOptions: ["openai": ["store": false]]
    ))

    let toolCall = try #require(result.content.compactMap { part -> AIToolCall? in
        guard case let .toolCall(call) = part, call.name == "toolSearch" else { return nil }
        return call
    }.first)
    #expect(toolCall.providerExecuted == false)
}

@Test func openAIResponsesClientToolSearchUsesCallIDLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesClientToolSearchFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.4")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesClientToolSearchTools(),
        providerOptions: ["openai": ["store": false]]
    ))

    let toolCall = try #require(result.content.compactMap { part -> AIToolCall? in
        guard case let .toolCall(call) = part, call.name == "toolSearch" else { return nil }
        return call
    }.first)
    let input = try decodeJSONBody(Data(toolCall.arguments.utf8))
    #expect(toolCall.id == "call_AEvXZ1rvYpxHh8QZb7wGlTGH")
    #expect(input["call_id"]?.stringValue == "call_AEvXZ1rvYpxHh8QZb7wGlTGH")
}

@Test func openAIResponsesUsesDistinctItemReferencesForHostedToolSearchLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .toolCall(AIToolCall(
                    id: "tsc_hosted_123",
                    name: "tool_search",
                    arguments: #"{"arguments":{"paths":["get_weather"]},"call_id":null}"#,
                    providerExecuted: true,
                    providerMetadata: ["openai": ["itemId": "tsc_hosted_123"]]
                )),
                .toolResult(AIToolResult(
                    toolCallID: "tsc_hosted_123",
                    toolName: "tool_search",
                    result: ["type": "json", "value": ["tools": [["type": "function", "name": "get_weather"]]]],
                    providerMetadata: ["openai": ["itemId": "tso_hosted_456"]]
                ))
            ])
        ],
        extraBody: ["store": true]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 2)
    #expect(input[0]["type"]?.stringValue == "item_reference")
    #expect(input[0]["id"]?.stringValue == "tsc_hosted_123")
    #expect(input[1]["type"]?.stringValue == "item_reference")
    #expect(input[1]["id"]?.stringValue == "tso_hosted_456")
}

@Test func openAIResponsesSerializesClientToolSearchCallAndOutputLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .toolCall(AIToolCall(
                    id: "call_abc123",
                    name: "tool_search",
                    arguments: #"{"arguments":{"goal":"Find weather tools"},"call_id":"call_abc123"}"#,
                    providerMetadata: ["openai": ["itemId": "tsc_client_1"]]
                ))
            ]),
            .toolResult(AIToolResult(
                toolCallID: "call_abc123",
                toolName: "tool_search",
                result: [
                    "type": "json",
                    "value": [
                        "tools": [
                            [
                                "type": "function",
                                "name": "get_weather",
                                "description": "Get weather",
                                "defer_loading": true,
                                "parameters": [
                                    "type": "object",
                                    "properties": ["location": ["type": "string"]],
                                    "required": ["location"]
                                ]
                            ]
                        ]
                    ]
                ]
            ))
        ],
        extraBody: ["store": false]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 2)
    #expect(input[0]["type"]?.stringValue == "tool_search_call")
    #expect(input[0]["id"]?.stringValue == "tsc_client_1")
    #expect(input[0]["execution"]?.stringValue == "client")
    #expect(input[0]["call_id"]?.stringValue == "call_abc123")
    #expect(input[0]["arguments"]?["goal"]?.stringValue == "Find weather tools")
    #expect(input[1]["type"]?.stringValue == "tool_search_output")
    #expect(input[1]["execution"]?.stringValue == "client")
    #expect(input[1]["call_id"]?.stringValue == "call_abc123")
    #expect(input[1]["tools"]?[0]?["name"]?.stringValue == "get_weather")
    #expect(input[1]["tools"]?[0]?["description"]?.stringValue == "Get weather")
    #expect(input[1]["tools"]?[0]?["defer_loading"]?.boolValue == true)
    #expect(input[1]["tools"]?[0]?["parameters"]?["properties"]?["location"]?["type"]?.stringValue == "string")
}
