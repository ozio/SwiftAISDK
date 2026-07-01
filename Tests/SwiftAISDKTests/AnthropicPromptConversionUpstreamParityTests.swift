import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicSystemMessagesUseUpstreamTextBlockArray() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .system("This is a system message"),
        .system("This is another system message"),
        .user("Hi")
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["system"] == [
        ["type": "text", "text": "This is a system message"],
        ["type": "text", "text": "This is another system message"]
    ])
    #expect(body["messages"]?[0]?["role"]?.stringValue == "user")
}

@Test func anthropicMidConversationSystemMessagesStayInlineAndAddBetaLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .system("initial"),
        .user("hi"),
        AIMessage(role: .assistant, content: [.text("hello")]),
        .system("switch tone"),
        .user("go")
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["system"] == [["type": "text", "text": "initial"]])
    #expect(body["messages"]?[2]?["role"]?.stringValue == "system")
    #expect(body["messages"]?[2]?["content"]?[0]?["type"]?.stringValue == "text")
    #expect(body["messages"]?[2]?["content"]?[0]?["text"]?.stringValue == "switch tone")
    #expect(request.headers["anthropic-beta"] == "mid-conversation-system-2026-04-07")
}

@Test func anthropicUserMediaDetectsTopLevelInlineMediaTypesLikeUpstream() async throws {
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let pdf = Data([0x25, 0x50, 0x44, 0x46, 0x2D])
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .file(mimeType: "image", data: png),
            .file(mimeType: "image/*", data: png),
            .file(mimeType: "application", data: pdf)
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content[0]["type"]?.stringValue == "image")
    #expect(content[0]["source"]?["media_type"]?.stringValue == "image/png")
    #expect(content[0]["source"]?["data"]?.stringValue == png.base64EncodedString())
    #expect(content[1]["source"]?["media_type"]?.stringValue == "image/png")
    #expect(content[2]["type"]?.stringValue == "document")
    #expect(content[2]["source"]?["media_type"]?.stringValue == "application/pdf")
    #expect(content[2]["source"]?["data"]?.stringValue == pdf.base64EncodedString())
    #expect(request.headers["anthropic-beta"] == "pdfs-2024-09-25")
}

@Test func anthropicPDFURLAddsDocumentSourceAndBetaLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [.imageURL("https://example.com/document.pdf")])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let file = try #require(body["messages"]?[0]?["content"]?[0])
    #expect(file["type"]?.stringValue == "document")
    #expect(file["source"]?["type"]?.stringValue == "url")
    #expect(file["source"]?["url"]?.stringValue == "https://example.com/document.pdf")
    #expect(request.headers["anthropic-beta"] == "pdfs-2024-09-25")
}

@Test func anthropicTextFilePartsKeepFilenameTitleLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .file(mimeType: "text/plain", data: Data("sample text content".utf8), filename: "sample.txt")
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let file = try #require(body["messages"]?[0]?["content"]?[0])
    #expect(file["type"]?.stringValue == "document")
    #expect(file["title"]?.stringValue == "sample.txt")
    #expect(file["source"]?["type"]?.stringValue == "text")
    #expect(file["source"]?["media_type"]?.stringValue == "text/plain")
    #expect(file["source"]?["data"]?.stringValue == "sample text content")
}

@Test func anthropicUnsupportedFileTypesThrowLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    await #expect(throws: AIError.invalidArgument(argument: "mediaType", message: "Unsupported media type: video/mp4.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [
            AIMessage(role: .user, content: [
                .file(mimeType: "video/mp4", data: Data([0x00, 0x01, 0x02]))
            ])
        ]))
    }
}

@Test func anthropicToolMessagesCombineWithAdjacentUserMessagesLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .toolResponses(toolResults: [
            AIToolResult(toolCallID: "tool-call-1", toolName: "tool-1", result: ["test": "This is a tool message"]),
            AIToolResult(toolCallID: "tool-call-2", toolName: "tool-2", result: ["something": "else"])
        ]),
        .user("This is a user message")
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let messages = try #require(body["messages"]?.arrayValue)
    #expect(messages.count == 1)
    #expect(messages[0]["role"]?.stringValue == "user")
    let content = try #require(messages[0]["content"]?.arrayValue)
    #expect(content.count == 3)
    #expect(content[0]["type"]?.stringValue == "tool_result")
    #expect(content[0]["tool_use_id"]?.stringValue == "tool-call-1")
    #expect(content[0]["content"]?.stringValue == #"{"test":"This is a tool message"}"#)
    #expect(content[1]["tool_use_id"]?.stringValue == "tool-call-2")
    #expect(content[1]["content"]?.stringValue == #"{"something":"else"}"#)
    #expect(content[2]["type"]?.stringValue == "text")
    #expect(content[2]["text"]?.stringValue == "This is a user message")
}

@Test func anthropicMultiToolMessageSequenceMapsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .user("weather for berlin, london and paris"),
        AIMessage(role: .assistant, content: [
            .text("I will use the weather tool to get the weather for berlin, london and paris"),
            .toolCall(AIToolCall(id: "weather-call-1", name: "weather", arguments: #"{"location":"berlin"}"#)),
            .toolCall(AIToolCall(id: "weather-call-2", name: "weather", arguments: #"{"location":"london"}"#)),
            .toolCall(AIToolCall(id: "weather-call-3", name: "weather", arguments: #"{"location":"paris"}"#))
        ]),
        .toolResponses(toolResults: [
            AIToolResult(
                toolCallID: "weather-call-1",
                toolName: "weather",
                result: ["unused": true],
                modelOutput: ["type": "json", "value": ["weather": "sunny"]]
            ),
            AIToolResult(
                toolCallID: "weather-call-2",
                toolName: "weather",
                result: ["unused": true],
                modelOutput: ["type": "json", "value": ["weather": "cloudy"]]
            ),
            AIToolResult(
                toolCallID: "weather-call-3",
                toolName: "weather",
                result: ["unused": true],
                modelOutput: ["type": "json", "value": ["weather": "rainy"]]
            )
        ]),
        .assistant("The weather for berlin is sunny, the weather for london is cloudy, and the weather for paris is rainy"),
        .user("and for new york?")
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let messages = try #require(body["messages"]?.arrayValue)
    #expect(body["system"] == nil)
    #expect(messages.count == 5)
    #expect(messages[0] == [
        "role": "user",
        "content": [["type": "text", "text": "weather for berlin, london and paris"]]
    ])
    #expect(messages[1] == [
        "role": "assistant",
        "content": [
            [
                "type": "text",
                "text": "I will use the weather tool to get the weather for berlin, london and paris"
            ],
            [
                "type": "tool_use",
                "id": "weather-call-1",
                "name": "weather",
                "input": ["location": "berlin"]
            ],
            [
                "type": "tool_use",
                "id": "weather-call-2",
                "name": "weather",
                "input": ["location": "london"]
            ],
            [
                "type": "tool_use",
                "id": "weather-call-3",
                "name": "weather",
                "input": ["location": "paris"]
            ]
        ]
    ])
    #expect(messages[2] == [
        "role": "user",
        "content": [
            [
                "type": "tool_result",
                "tool_use_id": "weather-call-1",
                "content": #"{"weather":"sunny"}"#
            ],
            [
                "type": "tool_result",
                "tool_use_id": "weather-call-2",
                "content": #"{"weather":"cloudy"}"#
            ],
            [
                "type": "tool_result",
                "tool_use_id": "weather-call-3",
                "content": #"{"weather":"rainy"}"#
            ]
        ]
    ])
    #expect(messages[3] == [
        "role": "assistant",
        "content": [[
            "type": "text",
            "text": "The weather for berlin is sunny, the weather for london is cloudy, and the weather for paris is rainy"
        ]]
    ])
    #expect(messages[4] == [
        "role": "user",
        "content": [["type": "text", "text": "and for new york?"]]
    ])
}

@Test func anthropicToolResultContentPartsMapLikeUpstream() async throws {
    let imageBase64 = "AAECAw=="
    let pdfBase64 = "JVBERi0xLjQKJeLjz9MKNCAwIG9iago="
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .toolResponses(toolResults: [
            AIToolResult(
                toolCallID: "image-gen-1",
                toolName: "image-generator",
                result: ["raw": "fallback"],
                modelOutput: [
                    "type": "content",
                    "value": [
                        ["type": "text", "text": "Image generated successfully"],
                        ["type": "file", "data": ["type": "data", "data": .string(imageBase64)], "mediaType": "image/png"],
                        ["type": "file", "data": ["type": "data", "data": .string(pdfBase64)], "mediaType": "application/pdf"],
                        ["type": "custom", "providerOptions": ["anthropic": ["type": "tool-reference", "toolName": "get_weather"]]]
                    ]
                ]
            )
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let toolResult = try #require(body["messages"]?[0]?["content"]?[0])
    let content = try #require(toolResult["content"]?.arrayValue)
    #expect(toolResult["type"]?.stringValue == "tool_result")
    #expect(toolResult["tool_use_id"]?.stringValue == "image-gen-1")
    #expect(content[0]["type"]?.stringValue == "text")
    #expect(content[0]["text"]?.stringValue == "Image generated successfully")
    #expect(content[1]["type"]?.stringValue == "image")
    #expect(content[1]["source"]?["type"]?.stringValue == "base64")
    #expect(content[1]["source"]?["media_type"]?.stringValue == "image/png")
    #expect(content[1]["source"]?["data"]?.stringValue == imageBase64)
    #expect(content[2]["type"]?.stringValue == "document")
    #expect(content[2]["source"]?["type"]?.stringValue == "base64")
    #expect(content[2]["source"]?["media_type"]?.stringValue == "application/pdf")
    #expect(content[2]["source"]?["data"]?.stringValue == pdfBase64)
    #expect(content[3]["type"]?.stringValue == "tool_reference")
    #expect(content[3]["tool_name"]?.stringValue == "get_weather")
    #expect(request.headers["anthropic-beta"] == "pdfs-2024-09-25")
}

@Test func anthropicToolResultURLContentPartsMapLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .toolResponses(toolResults: [
            AIToolResult(
                toolCallID: "url-1",
                toolName: "url-tool",
                result: ["raw": "fallback"],
                modelOutput: [
                    "type": "content",
                    "value": [
                        ["type": "file", "data": ["type": "url", "url": "https://example.com/image.png"], "mediaType": "image/png"],
                        ["type": "file", "data": ["type": "url", "url": "https://example.com/document.pdf"], "mediaType": "application/pdf"]
                    ]
                ]
            )
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?[0]?["content"]?.arrayValue)
    #expect(content[0]["type"]?.stringValue == "image")
    #expect(content[0]["source"]?["type"]?.stringValue == "url")
    #expect(content[0]["source"]?["url"]?.stringValue == "https://example.com/image.png")
    #expect(content[1]["type"]?.stringValue == "document")
    #expect(content[1]["source"]?["type"]?.stringValue == "url")
    #expect(content[1]["source"]?["url"]?.stringValue == "https://example.com/document.pdf")
    #expect(request.headers["anthropic-beta"] == nil)
}

@Test func anthropicToolResultErrorJSONSetsIsErrorLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .toolResponses(toolResults: [
            AIToolResult(
                toolCallID: "tool-call-1",
                toolName: "tool-1",
                result: ["raw": "fallback"],
                modelOutput: ["type": "error-json", "value": ["error": "bad"]]
            )
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let toolResult = try #require(body["messages"]?[0]?["content"]?[0])
    #expect(toolResult["type"]?.stringValue == "tool_result")
    #expect(toolResult["tool_use_id"]?.stringValue == "tool-call-1")
    #expect(toolResult["content"]?.stringValue == #"{"error":"bad"}"#)
    #expect(toolResult["is_error"]?.boolValue == true)
}

@Test func anthropicTrimsTrailingWhitespaceFromFinalAssistantMessageLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .user("user content"),
        AIMessage(role: .assistant, content: [
            .text("assistant "),
            .text("content  \n")
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[1]?["content"]?.arrayValue)
    #expect(content[0]["text"]?.stringValue == "assistant ")
    #expect(content[1]["text"]?.stringValue == "content")
}

@Test func anthropicKeepsTrailingAssistantWhitespaceBeforeFurtherUserMessageLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .user("user content"),
        AIMessage(role: .assistant, content: [.text("assistant content  ")]),
        .user("user content 2")
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["messages"]?[1]?["content"]?[0]?["text"]?.stringValue == "assistant content  ")
}

@Test func anthropicCombinesSequentialAssistantMessagesLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .user("Hi!"),
        AIMessage(role: .assistant, content: [.text("Hello")]),
        AIMessage(role: .assistant, content: [.text("World")]),
        AIMessage(role: .assistant, content: [.text("!  ")])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let messages = try #require(body["messages"]?.arrayValue)
    #expect(messages.count == 2)
    #expect(messages[1]["role"]?.stringValue == "assistant")
    let content = try #require(messages[1]["content"]?.arrayValue)
    #expect(content.map { $0["text"]?.stringValue } == ["Hello", "World", "!"])
}

@Test func anthropicAssistantReasoningWithSignatureMapsToThinkingLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(
            role: .assistant,
            content: [.text(#"The word "strawberry" has 2 "r"s."#)],
            reasoning: #"I need to count the number of "r"s in the word "strawberry"."#,
            providerMetadata: ["anthropic": ["signature": "test-signature"]]
        )
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content[0]["type"]?.stringValue == "thinking")
    #expect(content[0]["thinking"]?.stringValue == #"I need to count the number of "r"s in the word "strawberry"."#)
    #expect(content[0]["signature"]?.stringValue == "test-signature")
    #expect(content[1]["type"]?.stringValue == "text")
    #expect(content[1]["text"]?.stringValue == #"The word "strawberry" has 2 "r"s."#)
    #expect(result.warnings.isEmpty)
}

@Test func anthropicAssistantReasoningWithoutSignatureWarnsAndOmitsThinkingLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(
            role: .assistant,
            content: [.text(#"The word "strawberry" has 2 "r"s."#)],
            reasoning: #"I need to count the number of "r"s in the word "strawberry"."#
        )
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content.count == 1)
    #expect(content[0]["type"]?.stringValue == "text")
    #expect(result.warnings == [AIWarning(type: "other", message: "unsupported reasoning metadata")])
}

@Test func anthropicAssistantReasoningCanBeDisabledLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(
                role: .assistant,
                content: [.text(#"The word "strawberry" has 2 "r"s."#)],
                reasoning: #"I need to count the number of "r"s in the word "strawberry"."#,
                providerMetadata: ["anthropic": ["signature": "test-signature"]]
            )
        ],
        providerOptions: ["anthropic": ["sendReasoning": false]]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content.count == 1)
    #expect(content[0]["type"]?.stringValue == "text")
    #expect(result.warnings == [AIWarning(type: "other", message: "sending reasoning content is disabled for this model")])
}

