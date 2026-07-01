import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiGenerateTextResultContentPreservesNonToolPartsLikeUpstream() async throws {
    let source = AISource(
        id: "123",
        sourceType: "url",
        url: "https://example.com",
        title: "Example",
        providerMetadata: ["provider": ["custom": "value"]]
    )
    let file = AIStreamFile(
        mediaType: "image/jpeg",
        data: Data([40, 50, 60])
    )
    let reasoningFile = AIStreamFile(
        mediaType: "image/png",
        data: Data([10, 20, 30]),
        providerMetadata: ["google": ["thoughtSignature": "sig123"]]
    )
    let content: [AIResultContentPart] = [
        .text("Here is a thought image:"),
        .source(source),
        .reasoningFile(reasoningFile),
        .file(file),
        .reasoning("I will open with context.", providerMetadata: ["testProvider": ["signature": "signature"]]),
        .custom(["kind": "openai.compaction"], providerMetadata: ["openai": ["itemId": "cmp_123"]])
    ]
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "Here is a thought image:",
        content: content,
        reasoning: "I will open with context.",
        rawValue: .object([:])
    ))

    let result = try await AI.generateText(model: model, prompt: "prompt")

    #expect(result.content == content)
    #expect(result.sources == [source])
    #expect(result.files == [file])
    #expect(result.responseMessages == [
        AIMessage(role: .assistant, content: [
            .text("Here is a thought image:"),
            .reasoningFile(reasoningFile),
            .file(mimeType: file.mediaType, data: file.data ?? Data(), filename: file.filename),
            .reasoning("I will open with context.", providerMetadata: ["testProvider": ["signature": "signature"]]),
            .custom(["kind": "openai.compaction"], providerMetadata: ["openai": ["itemId": "cmp_123"]])
        ])
    ])
}

@Test func aiGenerateTextResultContentIncludesExecutedToolResultLikeUpstream() async throws {
    let toolCall = AIToolCall(
        id: "call-1",
        name: "tool1",
        arguments: #"{"value":"value"}"#
    )
    let firstContent: [AIResultContentPart] = [
        .text("Hello, world!"),
        .toolCall(toolCall),
        .text("More text")
    ]
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "Hello, world!More text",
            content: firstContent,
            finishReason: "tool-calls",
            rawValue: .object(["step": 1])
        ),
        TextGenerationResult(
            text: "Final answer.",
            content: [.text("Final answer.")],
            finishReason: "stop",
            rawValue: .object(["step": 2])
        )
    ])
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { arguments in
        #expect(arguments == ["value": "value"])
        return "result1"
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "prompt",
        executableTools: [tool],
        maxSteps: 2
    )

    #expect(result.content == [
        .text("Hello, world!"),
        .toolCall(toolCall),
        .text("More text"),
        .toolResult(AIToolResult(toolCallID: "call-1", toolName: "tool1", result: "result1")),
        .text("Final answer.")
    ])
    #expect(result.toolResults == [
        AIToolResult(toolCallID: "call-1", toolName: "tool1", result: "result1")
    ])
}

@Test func aiGenerateTextResponseMessagesAggregateAssistantAndToolMessagesLikeUpstream() async throws {
    let toolCall = AIToolCall(
        id: "call-1",
        name: "tool1",
        arguments: #"{"value":"value"}"#
    )
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "Hello, world!",
            content: [
                .text("Hello, world!"),
                .toolCall(toolCall)
            ],
            finishReason: "tool-calls",
            rawValue: .object(["step": 1])
        ),
        TextGenerationResult(
            text: "Done.",
            content: [.reasoning("I have the tool result."), .text("Done.")],
            finishReason: "stop",
            rawValue: .object(["step": 2])
        )
    ])
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { _ in
        "result1"
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 2
    )

    #expect(result.responseMessages == [
        AIMessage(role: .assistant, content: [
            .text("Hello, world!"),
            .toolCall(toolCall)
        ]),
        AIMessage(role: .tool, content: [
            .toolResult(AIToolResult(toolCallID: "call-1", toolName: "tool1", result: "result1"))
        ]),
        AIMessage(role: .assistant, content: [
            .reasoning("I have the tool result."),
            .text("Done.")
        ])
    ])
    #expect(model.requests[1].messages.suffix(2).map(\.role) == [.assistant, .tool])
}

@Test func aiGenerateTextUsageSumsAcrossStepsAndFinalStepKeepsLastUsageLikeUpstream() async throws {
    let firstUsage = TokenUsage(
        inputTokens: 10,
        outputTokens: 5,
        totalTokens: 15,
        inputTokensNoCache: 10,
        outputTextTokens: 5
    )
    let finalUsage = TokenUsage(
        inputTokens: 3,
        outputTokens: 10,
        totalTokens: 13,
        inputTokensNoCache: 3,
        outputTextTokens: 10
    )
    let firstResponseMetadata = AIResponseMetadata(
        id: "test-id-1-from-model",
        timestamp: Date(timeIntervalSince1970: 0),
        modelID: "test-response-model-id"
    )
    let finalResponseMetadata = AIResponseMetadata(
        id: "test-id-2-from-model",
        timestamp: Date(timeIntervalSince1970: 10),
        modelID: "test-response-model-id",
        headers: ["custom-response-header": "response-header-value"]
    )
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            content: [.toolCall(toolCall)],
            finishReason: "tool-calls",
            usage: firstUsage,
            rawValue: .object(["step": 1]),
            responseMetadata: firstResponseMetadata
        ),
        TextGenerationResult(
            text: "Hello, world!",
            content: [.text("Hello, world!")],
            finishReason: "stop",
            usage: finalUsage,
            rawValue: .object(["step": 2]),
            responseMetadata: finalResponseMetadata
        )
    ])
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { input in
        #expect(input == ["value": "value"])
        return "result1"
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 3
    )

    #expect(result.usage == TokenUsage(
        inputTokens: 13,
        outputTokens: 15,
        totalTokens: 28,
        inputTokensNoCache: 13,
        outputTextTokens: 15
    ))
    #expect(result.steps.map(\.usage) == [firstUsage, finalUsage])
    #expect(result.finalStep?.usage == finalUsage)
    #expect(result.toolCalls == [toolCall])
    #expect(result.toolResults == [AIToolResult(toolCallID: "call-1", toolName: "tool1", result: "result1")])
    #expect(result.finalStep?.toolCalls == [])
    #expect(result.finalStep?.toolResults == [])
    #expect(result.responseMetadata == finalResponseMetadata)
    #expect(result.steps.map(\.responseMetadata) == [firstResponseMetadata, finalResponseMetadata])
    #expect(result.finalStep?.responseMetadata == finalResponseMetadata)
}
