import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesConvertsToolResultContentFileURLLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let result = AIToolResult(
        toolCallID: "call_123",
        toolName: "search",
        result: .object([
            "type": .string("content"),
            "value": .array([
                .object([
                    "type": .string("file"),
                    "data": .object([
                        "type": .string("url"),
                        "url": .string("https://example.com/document.pdf")
                    ]),
                    "mediaType": .string("application/pdf")
                ])
            ])
        ])
    )

    _ = try await model.generate(LanguageModelRequest(messages: [.toolResult(result)]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 1)
    #expect(input[0]["type"]?.stringValue == "function_call_output")
    #expect(input[0]["call_id"]?.stringValue == "call_123")
    #expect(input[0]["output"]?[0]?["type"]?.stringValue == "input_file")
    #expect(input[0]["output"]?[0]?["file_url"]?.stringValue == "https://example.com/document.pdf")
}

@Test func openAIResponsesConvertsMixedToolResultContentWithFileURLLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let result = AIToolResult(
        toolCallID: "call_123",
        toolName: "search",
        result: .object([
            "type": .string("content"),
            "value": .array([
                .object([
                    "type": .string("text"),
                    "text": .string("Here is the file you asked for:")
                ]),
                .object([
                    "type": .string("file"),
                    "data": .object([
                        "type": .string("url"),
                        "url": .string("https://example.com/test.pdf")
                    ]),
                    "mediaType": .string("application/pdf")
                ])
            ])
        ])
    )

    _ = try await model.generate(LanguageModelRequest(messages: [.toolResult(result)]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let output = try #require(body["input"]?[0]?["output"]?.arrayValue)
    #expect(output.count == 2)
    #expect(output[0]["type"]?.stringValue == "input_text")
    #expect(output[0]["text"]?.stringValue == "Here is the file you asked for:")
    #expect(output[1]["type"]?.stringValue == "input_file")
    #expect(output[1]["file_url"]?.stringValue == "https://example.com/test.pdf")
}

@Test func openAIResponsesConvertsBasicToolResultOutputsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .tool, content: [
            .toolResult(AIToolResult(
                toolCallID: "call_json",
                toolName: "search",
                result: ["temperature": "72°F", "condition": "Sunny"]
            )),
            .toolResult(AIToolResult(
                toolCallID: "call_text",
                toolName: "search",
                result: "The weather in San Francisco is 72°F"
            )),
            .toolResult(AIToolResult(
                toolCallID: "call_denied",
                toolName: "search",
                result: ["type": "execution-denied", "reason": "User denied the tool execution"]
            )),
            .toolResult(AIToolResult(
                toolCallID: "call_number",
                toolName: "calculator",
                result: 4
            ))
        ])
    ]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 4)
    #expect(input[0]["type"]?.stringValue == "function_call_output")
    #expect(input[0]["call_id"]?.stringValue == "call_json")
    #expect(input[0]["output"]?.stringValue?.contains(#""temperature":"72°F""#) == true)
    #expect(input[0]["output"]?.stringValue?.contains(#""condition":"Sunny""#) == true)
    #expect(input[1]["call_id"]?.stringValue == "call_text")
    #expect(input[1]["output"]?.stringValue == "The weather in San Francisco is 72°F")
    #expect(input[2]["call_id"]?.stringValue == "call_denied")
    #expect(input[2]["output"]?.stringValue == "User denied the tool execution")
    #expect(input[3]["call_id"]?.stringValue == "call_number")
    #expect(input[3]["output"]?.stringValue == "4")
}

@Test func openAIResponsesConvertsMultipartToolResultContentLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let result = AIToolResult(
        toolCallID: "call_123",
        toolName: "search",
        result: .object([
            "type": .string("content"),
            "value": .array([
                .object([
                    "type": .string("text"),
                    "text": .string("The weather in San Francisco is 72°F")
                ]),
                .object([
                    "type": .string("file"),
                    "mediaType": .string("image/png"),
                    "data": .object([
                        "type": .string("data"),
                        "data": .string("base64_data")
                    ]),
                    "providerOptions": .object([
                        "openai": .object(["imageDetail": .string("original")])
                    ])
                ]),
                .object([
                    "type": .string("file"),
                    "mediaType": .string("image/png"),
                    "data": .object([
                        "type": .string("url"),
                        "url": .string("https://example.com/x.png")
                    ]),
                    "providerOptions": .object([
                        "openai": .object(["imageDetail": .string("high")])
                    ])
                ]),
                .object([
                    "type": .string("file"),
                    "mediaType": .string("application/pdf"),
                    "data": .object([
                        "type": .string("data"),
                        "data": .string("AQIDBAU=")
                    ]),
                    "filename": .string("document.pdf")
                ]),
                .object([
                    "type": .string("file"),
                    "mediaType": .string("application/pdf"),
                    "data": .object([
                        "type": .string("url"),
                        "url": .string("https://example.com/document.pdf")
                    ])
                ])
            ])
        ])
    )

    _ = try await model.generate(LanguageModelRequest(messages: [.toolResult(result)]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let output = try #require(body["input"]?[0]?["output"]?.arrayValue)
    #expect(output.count == 5)
    #expect(output[0]["type"]?.stringValue == "input_text")
    #expect(output[0]["text"]?.stringValue == "The weather in San Francisco is 72°F")
    #expect(output[1]["type"]?.stringValue == "input_image")
    #expect(output[1]["image_url"]?.stringValue == "data:image/png;base64,base64_data")
    #expect(output[1]["detail"]?.stringValue == "original")
    #expect(output[2]["type"]?.stringValue == "input_image")
    #expect(output[2]["image_url"]?.stringValue == "https://example.com/x.png")
    #expect(output[2]["detail"]?.stringValue == "high")
    #expect(output[3]["type"]?.stringValue == "input_file")
    #expect(output[3]["filename"]?.stringValue == "document.pdf")
    #expect(output[3]["file_data"]?.stringValue == "data:application/pdf;base64,AQIDBAU=")
    #expect(output[4]["type"]?.stringValue == "input_file")
    #expect(output[4]["file_url"]?.stringValue == "https://example.com/document.pdf")
}
