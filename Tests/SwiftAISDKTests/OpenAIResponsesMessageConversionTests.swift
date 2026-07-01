import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAILanguageDefaultsToResponsesAndMapsMultimodalInput() async throws {
    let pdf = Data("%PDF".utf8)
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"response text","usage":{"input_tokens":3,"output_tokens":4,"total_tokens":7}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        headers: ["OpenAI-Organization": "org-123", "OpenAI-Project": "proj-123"],
        transport: transport
    ))
    let model = try provider.languageModel("gpt-5-mini")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .system("Be precise."),
            AIMessage(role: .user, content: [
                .text("Inspect this"),
                .imageURL("https://example.com/image.png"),
                .data(mimeType: "application/pdf", data: pdf)
            ])
        ],
        temperature: 0.4,
        topP: 0.9,
        maxOutputTokens: 256,
        extraBody: [
            "reasoningEffort": "medium",
            "reasoningSummary": "auto",
            "previousResponseId": "resp-old",
            "parallelToolCalls": false,
            "serviceTier": "flex"
        ]
    ))

    #expect(result.text == "response text")
    #expect(result.finishReason == "stop")
    #expect(result.usage?.totalTokens == 7)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/responses")
    #expect(request.headers["authorization"] == "Bearer test-key")
    #expect(request.headers["openai-organization"] == "org-123")
    #expect(request.headers["openai-project"] == "proj-123")
    #expect(request.headers["user-agent"] == "ai-sdk/openai/3.0.74")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "gpt-5-mini")
    #expect(body["temperature"] == nil)
    #expect(body["top_p"] == nil)
    #expect(body["max_output_tokens"]?.intValue == 256)
    #expect(body["previous_response_id"]?.stringValue == "resp-old")
    #expect(body["parallel_tool_calls"]?.boolValue == false)
    #expect(body["service_tier"]?.stringValue == "flex")
    #expect(body["reasoning"]?["effort"]?.stringValue == "medium")
    #expect(body["reasoning"]?["summary"]?.stringValue == "auto")
    #expect(body["input"]?[0]?["role"]?.stringValue == "developer")
    #expect(body["input"]?[0]?["content"]?.stringValue == "Be precise.")
    #expect(body["input"]?[1]?["role"]?.stringValue == "user")
    #expect(body["input"]?[1]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[1]?["content"]?[0]?["text"]?.stringValue == "Inspect this")
    #expect(body["input"]?[1]?["content"]?[1]?["type"]?.stringValue == "input_image")
    #expect(body["input"]?[1]?["content"]?[1]?["image_url"]?.stringValue == "https://example.com/image.png")
    #expect(body["input"]?[1]?["content"]?[2]?["type"]?.stringValue == "input_file")
    #expect(body["input"]?[1]?["content"]?[2]?["filename"]?.stringValue == "part-2.pdf")
    #expect(body["input"]?[1]?["content"]?[2]?["file_data"]?.stringValue == "data:application/pdf;base64,\(pdf.base64EncodedString())")
}

@Test func openAIResponsesConvertsImageProviderReferenceLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .user, content: [
                .providerReference(mimeType: "image/png", reference: ["openai": "file-12345"])
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let content = try #require(body["input"]?[0]?["content"]?[0])
    #expect(content["type"]?.stringValue == "input_image")
    #expect(content["file_id"]?.stringValue == "file-12345")
}

@Test func openAIResponsesConvertsPDFProviderReferenceLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .user, content: [
                .providerReference(mimeType: "application/pdf", reference: ["openai": "file-pdf-12345"])
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let content = try #require(body["input"]?[0]?["content"]?[0])
    #expect(content["type"]?.stringValue == "input_file")
    #expect(content["file_id"]?.stringValue == "file-pdf-12345")
}

@Test func openAIResponsesThrowsWhenProviderReferenceCannotResolveOpenAILikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    await #expect(throws: AINoSuchProviderReferenceError(provider: "openai", reference: ["anthropic": "file-xyz"])) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [
                AIMessage(role: .user, content: [
                    .providerReference(mimeType: "image/png", reference: ["anthropic": "file-xyz"])
                ])
            ]
        ))
    }
    #expect(await transport.requests().isEmpty)
}

@Test func openAIResponsesDetectsWildcardImageMimeTypeLikeUpstream() async throws {
    let png = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .user, content: [
                .data(mimeType: "image/*", data: png)
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let content = try #require(body["input"]?[0]?["content"]?[0])
    #expect(content["type"]?.stringValue == "input_image")
    #expect(content["image_url"]?.stringValue == "data:image/png;base64,\(png.base64EncodedString())")
}

@Test func openAIResponsesThrowsWhenWildcardImageMimeTypeCannotBeDetectedLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    await #expect(throws: AIError.invalidArgument(
        argument: "messages",
        message: #"Could not determine media type for file data with media type "image/*"."#
    )) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [
                AIMessage(role: .user, content: [
                    .data(mimeType: "image/*", data: Data([0, 1, 2, 3]))
                ])
            ]
        ))
    }
}

@Test func openAIResponsesConvertsAssistantTextPhaseLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .text("I will search for that", providerMetadata: [
                    "openai": [
                        "itemId": "msg_001",
                        "phase": "commentary"
                    ]
                ])
            ]),
            AIMessage(role: .assistant, content: [
                .text("The capital of France is Paris.", providerMetadata: [
                    "openai": [
                        "itemId": "msg_002",
                        "phase": "final_answer"
                    ]
                ])
            ]),
            AIMessage(role: .assistant, content: [
                .text("Hello", providerMetadata: [
                    "openai": [
                        "itemId": "msg_003"
                    ]
                ])
            ])
        ],
        extraBody: ["store": false]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 3)
    #expect(input[0]["role"]?.stringValue == "assistant")
    #expect(input[0]["content"]?[0]?["type"]?.stringValue == "output_text")
    #expect(input[0]["content"]?[0]?["text"]?.stringValue == "I will search for that")
    #expect(input[0]["id"]?.stringValue == "msg_001")
    #expect(input[0]["phase"]?.stringValue == "commentary")
    #expect(input[1]["id"]?.stringValue == "msg_002")
    #expect(input[1]["phase"]?.stringValue == "final_answer")
    #expect(input[2]["id"]?.stringValue == "msg_003")
    #expect(input[2]["phase"] == nil)
}

@Test func openAIResponsesConvertsAssistantTextAndToolCallLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .text("I will search for that information."),
                .toolCall(AIToolCall(
                    id: "call_123",
                    name: "search",
                    arguments: #"{"query":"weather in San Francisco"}"#
                ))
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 2)
    let textItem = try #require(input.first)
    let toolCall = try #require(input.dropFirst().first)
    #expect(textItem["role"]?.stringValue == "assistant")
    #expect(textItem["content"]?[0]?["type"]?.stringValue == "output_text")
    #expect(textItem["content"]?[0]?["text"]?.stringValue == "I will search for that information.")
    #expect(toolCall["type"]?.stringValue == "function_call")
    #expect(toolCall["call_id"]?.stringValue == "call_123")
    #expect(toolCall["name"]?.stringValue == "search")
    #expect(toolCall["arguments"]?.stringValue == #"{"query":"weather in San Francisco"}"#)
}

@Test func openAIResponsesConvertsMultipleAssistantToolCallsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .toolCall(AIToolCall(
                    id: "call_123",
                    name: "search",
                    arguments: #"{"query":"weather in San Francisco"}"#
                )),
                .toolCall(AIToolCall(
                    id: "call_456",
                    name: "calculator",
                    arguments: #"{"expression":"2 + 2"}"#
                ))
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 2)
    let searchCall = try #require(input.first)
    let calculatorCall = try #require(input.dropFirst().first)
    #expect(searchCall["type"]?.stringValue == "function_call")
    #expect(searchCall["call_id"]?.stringValue == "call_123")
    #expect(searchCall["name"]?.stringValue == "search")
    #expect(searchCall["arguments"]?.stringValue == #"{"query":"weather in San Francisco"}"#)
    #expect(calculatorCall["type"]?.stringValue == "function_call")
    #expect(calculatorCall["call_id"]?.stringValue == "call_456")
    #expect(calculatorCall["name"]?.stringValue == "calculator")
    #expect(calculatorCall["arguments"]?.stringValue == #"{"expression":"2 + 2"}"#)
}

@Test func openAIResponsesConvertsAssistantTextIDToItemReferenceButNotToolCallLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .text("I will search for that information.", providerMetadata: [
                    "openai": [
                        "itemId": "id_123"
                    ]
                ]),
                .toolCall(AIToolCall(
                    id: "call_123",
                    name: "search",
                    arguments: #"{"query":"weather in San Francisco"}"#,
                    providerMetadata: [
                        "openai": [
                            "itemId": "id_456"
                        ]
                    ]
                ))
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 2)
    let itemReference = try #require(input.first)
    let toolCall = try #require(input.dropFirst().first)
    #expect(itemReference["type"]?.stringValue == "item_reference")
    #expect(itemReference["id"]?.stringValue == "id_123")
    #expect(toolCall["type"]?.stringValue == "function_call")
    #expect(toolCall["id"] == nil)
    #expect(toolCall["call_id"]?.stringValue == "call_123")
    #expect(toolCall["name"]?.stringValue == "search")
    #expect(toolCall["arguments"]?.stringValue == #"{"query":"weather in San Francisco"}"#)
}

@Test func openAIResponsesConvertsSingleReasoningPartWithTextLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .reasoning("Analyzing the problem step by step", providerMetadata: [
                    "openai": [
                        "itemId": "reasoning_001",
                        "reasoningEncryptedContent": "encrypted_content_001"
                    ]
                ])
            ])
        ],
        extraBody: ["store": false]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let reasoning = try #require(body["input"]?[0])
    #expect(reasoning["type"]?.stringValue == "reasoning")
    #expect(reasoning["id"]?.stringValue == "reasoning_001")
    #expect(reasoning["encrypted_content"]?.stringValue == "encrypted_content_001")
    #expect(reasoning["summary"]?[0]?["type"]?.stringValue == "summary_text")
    #expect(reasoning["summary"]?[0]?["text"]?.stringValue == "Analyzing the problem step by step")
    #expect(result.warnings.isEmpty)
}

@Test func openAIResponsesCreatesEmptyReasoningSummaryForInitialEmptyTextLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .reasoning("", providerMetadata: [
                    "openai": [
                        "itemId": "reasoning_001",
                        "reasoningEncryptedContent": "encrypted_content_001"
                    ]
                ])
            ])
        ],
        extraBody: ["store": false]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let reasoning = try #require(body["input"]?[0])
    #expect(reasoning["type"]?.stringValue == "reasoning")
    #expect(reasoning["id"]?.stringValue == "reasoning_001")
    #expect(reasoning["encrypted_content"]?.stringValue == "encrypted_content_001")
    #expect(reasoning["summary"]?.arrayValue == [])
    #expect(result.warnings.isEmpty)
}

@Test func openAIResponsesWarnsWhenAppendingEmptyReasoningTextLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .reasoning("First reasoning step", providerMetadata: [
                    "openai": [
                        "itemId": "reasoning_001"
                    ]
                ]),
                .reasoning("", providerMetadata: [
                    "openai": [
                        "itemId": "reasoning_001",
                        "reasoningEncryptedContent": "encrypted_content_001"
                    ]
                ])
            ])
        ],
        extraBody: ["store": false]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let reasoning = try #require(body["input"]?[0])
    #expect(reasoning["type"]?.stringValue == "reasoning")
    #expect(reasoning["id"]?.stringValue == "reasoning_001")
    #expect(reasoning["encrypted_content"]?.stringValue == "encrypted_content_001")
    #expect(reasoning["summary"]?.arrayValue?.count == 1)
    #expect(reasoning["summary"]?[0]?["text"]?.stringValue == "First reasoning step")
    #expect(result.warnings.count == 1)
    #expect(result.warnings.first?.type == "other")
    #expect(result.warnings.first?.message?.contains("Cannot append empty reasoning part to existing reasoning sequence.") == true)
}

@Test func openAIResponsesMergesConsecutiveReasoningPartsWithSameIDLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .reasoning("First reasoning step", providerMetadata: [
                    "openai": [
                        "itemId": "reasoning_001"
                    ]
                ]),
                .reasoning("Second reasoning step", providerMetadata: [
                    "openai": [
                        "itemId": "reasoning_001",
                        "reasoningEncryptedContent": "encrypted_content_001"
                    ]
                ])
            ])
        ],
        extraBody: ["store": false]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let reasoning = try #require(body["input"]?[0])
    #expect(reasoning["type"]?.stringValue == "reasoning")
    #expect(reasoning["id"]?.stringValue == "reasoning_001")
    #expect(reasoning["encrypted_content"]?.stringValue == "encrypted_content_001")
    #expect(reasoning["summary"]?.arrayValue?.count == 2)
    #expect(reasoning["summary"]?[0]?["text"]?.stringValue == "First reasoning step")
    #expect(reasoning["summary"]?[1]?["text"]?.stringValue == "Second reasoning step")
    #expect(result.warnings.isEmpty)
}

@Test func openAIResponsesDropsReasoningWithoutEncryptedContentWhenStoreFalseLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .reasoning("First reasoning step", providerMetadata: [
                    "openai": [
                        "itemId": "reasoning_001"
                    ]
                ]),
                .reasoning("Second reasoning step", providerMetadata: [
                    "openai": [
                        "itemId": "reasoning_001"
                    ]
                ])
            ])
        ],
        extraBody: ["store": false]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["input"]?.arrayValue == [])
    #expect(result.warnings.count == 1)
    #expect(result.warnings.first?.type == "other")
    #expect(result.warnings.first?.message == "Reasoning parts without encrypted content are not supported when store is false. Skipping reasoning parts.")
}

@Test func openAIResponsesCreatesSeparateReasoningMessagesForDifferentIDsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .reasoning("First reasoning block", providerMetadata: [
                    "openai": [
                        "itemId": "reasoning_001",
                        "reasoningEncryptedContent": "encrypted_content_001"
                    ]
                ]),
                .reasoning("Second reasoning block", providerMetadata: [
                    "openai": [
                        "itemId": "reasoning_002",
                        "reasoningEncryptedContent": "encrypted_content_002"
                    ]
                ])
            ])
        ],
        extraBody: ["store": false]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 2)
    #expect(input[0]["type"]?.stringValue == "reasoning")
    #expect(input[0]["id"]?.stringValue == "reasoning_001")
    #expect(input[0]["encrypted_content"]?.stringValue == "encrypted_content_001")
    #expect(input[0]["summary"]?[0]?["text"]?.stringValue == "First reasoning block")
    #expect(input[1]["type"]?.stringValue == "reasoning")
    #expect(input[1]["id"]?.stringValue == "reasoning_002")
    #expect(input[1]["encrypted_content"]?.stringValue == "encrypted_content_002")
    #expect(input[1]["summary"]?[0]?["text"]?.stringValue == "Second reasoning block")
    #expect(result.warnings.isEmpty)
}

@Test func openAIResponsesHandlesReasoningAcrossMultipleAssistantMessagesStoreTrueLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .user("First user question"),
            AIMessage(role: .assistant, content: [
                .reasoning("First reasoning step (message 1)", providerMetadata: ["openai": ["itemId": "reasoning_001"]]),
                .reasoning("Second reasoning step (message 1)", providerMetadata: ["openai": ["itemId": "reasoning_001"]]),
                .text("First response")
            ]),
            .user("Second user question"),
            AIMessage(role: .assistant, content: [
                .reasoning("First reasoning step (message 2)", providerMetadata: ["openai": ["itemId": "reasoning_002"]]),
                .text("Second response")
            ])
        ],
        extraBody: ["store": true]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 6)
    #expect(input[0]["role"]?.stringValue == "user")
    #expect(input[0]["content"]?[0]?["text"]?.stringValue == "First user question")
    #expect(input[1]["type"]?.stringValue == "item_reference")
    #expect(input[1]["id"]?.stringValue == "reasoning_001")
    #expect(input[2]["role"]?.stringValue == "assistant")
    #expect(input[2]["content"]?[0]?["text"]?.stringValue == "First response")
    #expect(input[3]["role"]?.stringValue == "user")
    #expect(input[3]["content"]?[0]?["text"]?.stringValue == "Second user question")
    #expect(input[4]["type"]?.stringValue == "item_reference")
    #expect(input[4]["id"]?.stringValue == "reasoning_002")
    #expect(input[5]["role"]?.stringValue == "assistant")
    #expect(input[5]["content"]?[0]?["text"]?.stringValue == "Second response")
    #expect(result.warnings.isEmpty)
}

@Test func openAIResponsesHandlesReasoningAcrossMultipleAssistantMessagesStoreFalseLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .user("First user question"),
            AIMessage(role: .assistant, content: [
                .reasoning("First reasoning step (message 1)", providerMetadata: ["openai": ["itemId": "reasoning_001"]]),
                .reasoning("Second reasoning step (message 1)", providerMetadata: [
                    "openai": [
                        "itemId": "reasoning_001",
                        "reasoningEncryptedContent": "encrypted_content_001"
                    ]
                ]),
                .text("First response")
            ]),
            .user("Second user question"),
            AIMessage(role: .assistant, content: [
                .reasoning("First reasoning step (message 2)", providerMetadata: [
                    "openai": [
                        "itemId": "reasoning_002",
                        "reasoningEncryptedContent": "encrypted_content_002"
                    ]
                ]),
                .text("Second response")
            ])
        ],
        extraBody: ["store": false]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 6)
    #expect(input[0]["role"]?.stringValue == "user")
    #expect(input[1]["type"]?.stringValue == "reasoning")
    #expect(input[1]["id"]?.stringValue == "reasoning_001")
    #expect(input[1]["encrypted_content"]?.stringValue == "encrypted_content_001")
    #expect(input[1]["summary"]?.arrayValue?.count == 2)
    #expect(input[1]["summary"]?[0]?["text"]?.stringValue == "First reasoning step (message 1)")
    #expect(input[1]["summary"]?[1]?["text"]?.stringValue == "Second reasoning step (message 1)")
    #expect(input[2]["role"]?.stringValue == "assistant")
    #expect(input[2]["content"]?[0]?["text"]?.stringValue == "First response")
    #expect(input[3]["role"]?.stringValue == "user")
    #expect(input[4]["type"]?.stringValue == "reasoning")
    #expect(input[4]["id"]?.stringValue == "reasoning_002")
    #expect(input[4]["encrypted_content"]?.stringValue == "encrypted_content_002")
    #expect(input[4]["summary"]?[0]?["text"]?.stringValue == "First reasoning step (message 2)")
    #expect(input[5]["role"]?.stringValue == "assistant")
    #expect(input[5]["content"]?[0]?["text"]?.stringValue == "Second response")
    #expect(result.warnings.isEmpty)
}

@Test func openAIResponsesHandlesComplexReasoningSequencesWithToolInteractionsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .reasoning("Initial analysis step 1", providerMetadata: [
                    "openai": [
                        "itemId": "reasoning_001",
                        "reasoningEncryptedContent": "encrypted_content_001"
                    ]
                ]),
                .reasoning("Initial analysis step 2", providerMetadata: [
                    "openai": [
                        "itemId": "reasoning_001",
                        "reasoningEncryptedContent": "encrypted_content_001"
                    ]
                ]),
                .toolCall(AIToolCall(id: "call_001", name: "search", arguments: #"{"query":"initial search"}"#))
            ]),
            .toolResult(AIToolResult(toolCallID: "call_001", toolName: "search", result: ["results": ["result1", "result2"]])),
            AIMessage(role: .assistant, content: [
                .reasoning("Processing results step 1", providerMetadata: [
                    "openai": [
                        "itemId": "reasoning_002",
                        "reasoningEncryptedContent": "encrypted_content_002"
                    ]
                ]),
                .reasoning("Processing results step 2", providerMetadata: [
                    "openai": [
                        "itemId": "reasoning_002",
                        "reasoningEncryptedContent": "encrypted_content_002"
                    ]
                ]),
                .reasoning("Processing results step 3", providerMetadata: [
                    "openai": [
                        "itemId": "reasoning_002",
                        "reasoningEncryptedContent": "encrypted_content_002"
                    ]
                ]),
                .toolCall(AIToolCall(id: "call_002", name: "calculator", arguments: #"{"expression":"2 + 2"}"#))
            ]),
            .toolResult(AIToolResult(toolCallID: "call_002", toolName: "calculator", result: ["result": 4])),
            .assistant("Based on my analysis and calculations, here is the final answer.")
        ],
        extraBody: ["store": false]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 7)
    #expect(input[0]["type"]?.stringValue == "reasoning")
    #expect(input[0]["id"]?.stringValue == "reasoning_001")
    #expect(input[0]["summary"]?.arrayValue?.count == 2)
    #expect(input[0]["summary"]?[0]?["text"]?.stringValue == "Initial analysis step 1")
    #expect(input[0]["summary"]?[1]?["text"]?.stringValue == "Initial analysis step 2")
    #expect(input[1]["type"]?.stringValue == "function_call")
    #expect(input[1]["call_id"]?.stringValue == "call_001")
    #expect(input[1]["name"]?.stringValue == "search")
    #expect(input[1]["arguments"]?.stringValue == #"{"query":"initial search"}"#)
    #expect(input[2]["type"]?.stringValue == "function_call_output")
    #expect(input[2]["call_id"]?.stringValue == "call_001")
    #expect(input[2]["output"]?.stringValue == #"{"results":["result1","result2"]}"#)
    #expect(input[3]["type"]?.stringValue == "reasoning")
    #expect(input[3]["id"]?.stringValue == "reasoning_002")
    #expect(input[3]["summary"]?.arrayValue?.count == 3)
    #expect(input[3]["summary"]?[2]?["text"]?.stringValue == "Processing results step 3")
    #expect(input[4]["type"]?.stringValue == "function_call")
    #expect(input[4]["call_id"]?.stringValue == "call_002")
    #expect(input[4]["name"]?.stringValue == "calculator")
    #expect(input[4]["arguments"]?.stringValue == #"{"expression":"2 + 2"}"#)
    #expect(input[5]["type"]?.stringValue == "function_call_output")
    #expect(input[5]["call_id"]?.stringValue == "call_002")
    #expect(input[5]["output"]?.stringValue == #"{"result":4}"#)
    #expect(input[6]["role"]?.stringValue == "assistant")
    #expect(input[6]["content"]?[0]?["text"]?.stringValue == "Based on my analysis and calculations, here is the final answer.")
    #expect(result.warnings.isEmpty)
}
