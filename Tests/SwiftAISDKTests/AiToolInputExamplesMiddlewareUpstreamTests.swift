import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiAddToolInputExamplesMiddlewareAppendsExamplesToDescriptionLikeUpstream() {
    let tool: JSONValue = [
        "type": "function",
        "name": "weather",
        "description": "Get the weather in a location",
        "inputSchema": [
            "type": "object",
            "properties": ["location": ["type": "string"]]
        ],
        "inputExamples": [
            ["input": ["location": "San Francisco"]],
            ["input": ["location": "London"]]
        ]
    ]

    let transformed = toolWithInputExamplesInDescription(
        tool,
        prefix: "Input Examples:",
        remove: true,
        format: defaultFormatToolInputExample
    )

    #expect(transformed["description"]?.stringValue == """
    Get the weather in a location

    Input Examples:
    {"location":"San Francisco"}
    {"location":"London"}
    """)
    #expect(transformed["inputExamples"] == nil)
    #expect(transformed["inputSchema"] == tool["inputSchema"])
}

@Test func aiAddToolInputExamplesMiddlewareHandlesToolWithoutDescriptionLikeUpstream() {
    let tool: JSONValue = [
        "type": "function",
        "name": "weather",
        "inputSchema": [
            "type": "object",
            "properties": ["location": ["type": "string"]]
        ],
        "inputExamples": [["input": ["location": "Berlin"]]]
    ]

    let transformed = toolWithInputExamplesInDescription(
        tool,
        prefix: "Input Examples:",
        remove: true,
        format: defaultFormatToolInputExample
    )

    #expect(transformed["description"]?.stringValue == """
    Input Examples:
    {"location":"Berlin"}
    """)
    #expect(transformed["inputExamples"] == nil)
}

@Test func aiAddToolInputExamplesMiddlewareSupportsCustomPrefixAndFormatLikeUpstream() {
    let tool: JSONValue = [
        "type": "function",
        "name": "weather",
        "description": "Get the weather",
        "inputExamples": [
            ["input": ["location": "Paris"]],
            ["input": ["location": "Tokyo"]]
        ]
    ]

    let transformed = toolWithInputExamplesInDescription(
        tool,
        prefix: "Here are some example inputs:",
        remove: true,
        format: { context in
            let location = context.example["input"]?["location"]?.stringValue ?? ""
            return "\(context.index + 1). {\"location\":\"\(location)\"}"
        }
    )

    #expect(transformed["description"]?.stringValue == """
    Get the weather

    Here are some example inputs:
    1. {"location":"Paris"}
    2. {"location":"Tokyo"}
    """)
    #expect(transformed["inputExamples"] == nil)
}

@Test func aiAddToolInputExamplesMiddlewareCanKeepInputExamplesLikeUpstream() {
    let examples: JSONValue = [["input": ["location": "NYC"]]]
    let tool: JSONValue = [
        "type": "function",
        "name": "weather",
        "description": "Get the weather",
        "inputExamples": examples
    ]

    let transformed = toolWithInputExamplesInDescription(
        tool,
        prefix: "Input Examples:",
        remove: false,
        format: defaultFormatToolInputExample
    )

    #expect(transformed["description"]?.stringValue == """
    Get the weather

    Input Examples:
    {"location":"NYC"}
    """)
    #expect(transformed["inputExamples"] == examples)
}

@Test func aiAddToolInputExamplesMiddlewarePassesThroughToolsWithoutExamplesLikeUpstream() {
    let noExamples: JSONValue = [
        "type": "function",
        "name": "weather",
        "description": "Get the weather",
        "inputSchema": [
            "type": "object",
            "properties": ["location": ["type": "string"]]
        ]
    ]
    let emptyExamples: JSONValue = [
        "type": "function",
        "name": "weather",
        "description": "Get the weather",
        "inputExamples": []
    ]
    let providerTool: JSONValue = [
        "type": "provider",
        "name": "web_search",
        "id": "anthropic.web_search_20250305",
        "args": ["maxUses": 5]
    ]

    #expect(toolWithInputExamplesInDescription(
        noExamples,
        prefix: "Input Examples:",
        remove: true,
        format: defaultFormatToolInputExample
    ) == noExamples)
    #expect(toolWithInputExamplesInDescription(
        emptyExamples,
        prefix: "Input Examples:",
        remove: true,
        format: defaultFormatToolInputExample
    ) == emptyExamples)
    #expect(toolWithInputExamplesInDescription(
        providerTool,
        prefix: "Input Examples:",
        remove: true,
        format: defaultFormatToolInputExample
    ) == providerTool)
}

@Test func aiAddToolInputExamplesMiddlewareHandlesMultipleAndEmptyToolsLikeUpstream() async throws {
    let model = ToolInputExamplesLanguageModel()
    let wrapped = wrapLanguageModel(model, middleware: addToolInputExamplesMiddleware())

    _ = try await wrapped.generate(LanguageModelRequest(
        messages: [.user("Use tools")],
        tools: [
            "weather": [
                "type": "function",
                "name": "weather",
                "description": "Get the weather",
                "inputExamples": [["input": ["location": "NYC"]]]
            ],
            "time": [
                "type": "function",
                "name": "time",
                "description": "Get the current time"
            ]
        ]
    ))

    let tools = try #require(model.generateRequests.first?.tools)
    #expect(tools["weather"]?["description"]?.stringValue == """
    Get the weather

    Input Examples:
    {"location":"NYC"}
    """)
    #expect(tools["weather"]?["inputExamples"] == nil)
    #expect(tools["time"]?["description"]?.stringValue == "Get the current time")

    _ = try await wrapped.generate(LanguageModelRequest(messages: [.user("No tools")], tools: [:]))

    #expect(model.generateRequests.last?.tools == [:])
}

private final class ToolInputExamplesLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "tool-input-examples"
    let modelID = "language"
    var generateRequests: [LanguageModelRequest] = []

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        generateRequests.append(request)
        return TextGenerationResult(text: "ok", rawValue: .object([:]))
    }
}
