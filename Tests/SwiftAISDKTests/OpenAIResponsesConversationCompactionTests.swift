import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesSkipsExistingAssistantItemsWhenConversationIsSetLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            .user("Hello"),
            AIMessage(role: .assistant, content: [
                .text("Hi there!", providerMetadata: ["openai": ["itemId": "msg_existing_123"]])
            ]),
            .user("What is the weather?")
        ],
        providerOptions: ["openai": ["conversation": "conv_123"]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["conversation"]?.stringValue == "conv_123")
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 2)
    #expect(input[0]["role"]?.stringValue == "user")
    #expect(input[0]["content"]?[0]?["text"]?.stringValue == "Hello")
    #expect(input[1]["role"]?.stringValue == "user")
    #expect(input[1]["content"]?[0]?["text"]?.stringValue == "What is the weather?")
}

@Test func openAIResponsesSkipsReasoningItemReferencesWhenPreviousResponseIDIsSetLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .user("Hello"),
            AIMessage(role: .assistant, content: [
                .reasoning("Let me think...", providerMetadata: ["openai": ["itemId": "rs_existing_123"]])
            ])
        ],
        providerOptions: ["openai": ["previousResponseId": "resp_123", "store": true]]
    ))

    #expect(result.warnings.isEmpty)
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["previous_response_id"]?.stringValue == "resp_123")
    #expect(body["store"]?.boolValue == true)
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 1)
    #expect(input[0]["role"]?.stringValue == "user")
    #expect(input[0]["content"]?[0]?["text"]?.stringValue == "Hello")
}

@Test func openAIResponsesSkipsFunctionCallItemReferencesWhenPreviousResponseIDIsSetLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .user("What is the weather?"),
            AIMessage(role: .assistant, content: [
                .toolCall(AIToolCall(
                    id: "call_123",
                    name: "weather",
                    arguments: #"{"location":"San Francisco"}"#,
                    providerMetadata: ["openai": ["itemId": "fc_existing_123"]]
                ))
            ]),
            .toolResponses(toolResults: [
                AIToolResult(toolCallID: "call_123", toolName: "weather", result: ["temp": 72])
            ])
        ],
        providerOptions: ["openai": ["previousResponseId": "resp_123", "store": true]]
    ))

    #expect(result.warnings.isEmpty)
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["previous_response_id"]?.stringValue == "resp_123")
    #expect(body["store"]?.boolValue == true)
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 2)
    #expect(input[0]["role"]?.stringValue == "user")
    #expect(input[0]["content"]?[0]?["text"]?.stringValue == "What is the weather?")
    #expect(input[1]["type"]?.stringValue == "function_call_output")
    #expect(input[1]["call_id"]?.stringValue == "call_123")
    #expect(input[1]["output"]?.stringValue == #"{"temp":72}"#)
}

@Test func openAIResponsesConvertsCompactionToItemReferenceWhenStoredLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .custom(
                    ["kind": "openai.compaction"],
                    providerMetadata: ["openai": [
                        "type": "compaction",
                        "itemId": "cmp_123",
                        "encryptedContent": "encrypted_data_here"
                    ]]
                )
            ])
        ],
        providerOptions: ["openai": ["store": true]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 1)
    #expect(input[0]["type"]?.stringValue == "item_reference")
    #expect(input[0]["id"]?.stringValue == "cmp_123")
}

@Test func openAIResponsesConvertsCompactionToFullItemWhenUnstoredLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .custom(
                    ["kind": "openai.compaction"],
                    providerMetadata: ["openai": [
                        "type": "compaction",
                        "itemId": "cmp_456",
                        "encryptedContent": "encrypted_compaction_state"
                    ]]
                )
            ])
        ],
        providerOptions: ["openai": ["store": false]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 1)
    #expect(input[0]["type"]?.stringValue == "compaction")
    #expect(input[0]["id"]?.stringValue == "cmp_456")
    #expect(input[0]["encrypted_content"]?.stringValue == "encrypted_compaction_state")
}

@Test func openAIResponsesSkipsCompactionWhenConversationIsSetLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            .user("Hello"),
            AIMessage(role: .assistant, content: [
                .custom(
                    ["kind": "openai.compaction"],
                    providerMetadata: ["openai": [
                        "type": "compaction",
                        "itemId": "cmp_789",
                        "encryptedContent": "encrypted_data"
                    ]]
                )
            ])
        ],
        providerOptions: ["openai": ["conversation": "conv_123", "store": true]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 1)
    #expect(input[0]["role"]?.stringValue == "user")
    #expect(input[0]["content"]?[0]?["text"]?.stringValue == "Hello")
}

@Test func openAIResponsesConvertsMixedTextAndCompactionWhenUnstoredLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .text("Here is my response.", providerMetadata: ["openai": ["itemId": "msg_001"]]),
                .custom(
                    ["kind": "openai.compaction"],
                    providerMetadata: ["openai": [
                        "type": "compaction",
                        "itemId": "cmp_001",
                        "encryptedContent": "encrypted_state"
                    ]]
                )
            ])
        ],
        providerOptions: ["openai": ["store": false]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 2)
    #expect(input[0]["role"]?.stringValue == "assistant")
    #expect(input[0]["id"]?.stringValue == "msg_001")
    #expect(input[0]["content"]?[0]?["type"]?.stringValue == "output_text")
    #expect(input[0]["content"]?[0]?["text"]?.stringValue == "Here is my response.")
    #expect(input[1]["type"]?.stringValue == "compaction")
    #expect(input[1]["id"]?.stringValue == "cmp_001")
    #expect(input[1]["encrypted_content"]?.stringValue == "encrypted_state")
}

@Test func openAIResponsesConvertsMixedTextAndCompactionWhenStoredLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .text("Response text", providerMetadata: ["openai": ["itemId": "msg_002"]]),
                .custom(
                    ["kind": "openai.compaction"],
                    providerMetadata: ["openai": [
                        "type": "compaction",
                        "itemId": "cmp_002",
                        "encryptedContent": "encrypted_data"
                    ]]
                )
            ])
        ],
        providerOptions: ["openai": ["store": true]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 2)
    #expect(input[0]["type"]?.stringValue == "item_reference")
    #expect(input[0]["id"]?.stringValue == "msg_002")
    #expect(input[1]["type"]?.stringValue == "item_reference")
    #expect(input[1]["id"]?.stringValue == "cmp_002")
}

