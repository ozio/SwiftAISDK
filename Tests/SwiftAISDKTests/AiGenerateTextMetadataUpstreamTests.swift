import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiGenerateTextWarningsAggregateAcrossStepsLikeUpstream() async throws {
    let warning0 = AIWarning(type: "other", message: "step 0 warning")
    let warning1 = AIWarning(type: "other", message: "step 1 warning")
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: "{}")
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            content: [.toolCall(toolCall)],
            finishReason: "tool-calls",
            rawValue: .object(["step": 1]),
            warnings: [warning0]
        ),
        TextGenerationResult(
            text: "Done.",
            content: [.text("Done.")],
            finishReason: "stop",
            rawValue: .object(["step": 2]),
            warnings: [warning1]
        )
    ])
    let tool = AITool(name: "tool1", parameters: ["type": "object"]) { _ in
        "result1"
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "prompt",
        executableTools: [tool],
        maxSteps: 3
    )

    #expect(result.warnings == [warning0, warning1])
    #expect(result.finalStep?.warnings == [warning1])
}

@Test func aiGenerateTextSourcesAndFilesAggregateAcrossStepsLikeUpstream() async throws {
    let source0 = AISource(id: "source-0", sourceType: "url", url: "https://example.com/0", title: "Source 0")
    let source1 = AISource(id: "source-1", sourceType: "url", url: "https://example.com/1", title: "Source 1")
    let file0 = AIStreamFile(mediaType: "text/plain", data: Data("step-0".utf8))
    let file1 = AIStreamFile(mediaType: "text/plain", data: Data("step-1".utf8))
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: "{}")
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            content: [
                .source(source0),
                .file(file0),
                .toolCall(toolCall)
            ],
            finishReason: "tool-calls",
            rawValue: .object(["step": 1])
        ),
        TextGenerationResult(
            text: "",
            content: [
                .source(source1),
                .file(file1)
            ],
            finishReason: "stop",
            rawValue: .object(["step": 2])
        )
    ])
    let tool = AITool(name: "tool1", parameters: ["type": "object"]) { _ in
        "result1"
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "prompt",
        executableTools: [tool],
        maxSteps: 3
    )

    #expect(result.sources == [source0, source1])
    #expect(result.finalStep?.sources == [source1])
    #expect(result.files == [file0, file1])
    #expect(result.finalStep?.files == [file1])
    #expect(result.content.compactMap { part -> AIStreamFile? in
        if case let .file(file) = part {
            return file
        }
        return nil
    } == [file0, file1])
    #expect(result.finalStep?.content.compactMap { part -> AIStreamFile? in
        if case let .file(file) = part {
            return file
        }
        return nil
    } == [file1])
}

@Test func aiGenerateTextStepResultExposesReasoningSourcesFilesAndFinalStepLikeUpstream() async throws {
    let source = AISource(id: "source-1", sourceType: "url", url: "https://example.com", title: "Example")
    let file = AIStreamFile(mediaType: "text/plain", data: Data("payload".utf8))
    let content: [AIResultContentPart] = [
        .reasoning("I will open the conversation with witty banter."),
        .source(source),
        .file(file),
        .text("Hello!")
    ]
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "Hello!",
        content: content,
        reasoning: "I will open the conversation with witty banter.",
        rawValue: .object([:])
    ))

    let result = try await AI.generateText(model: model, prompt: "prompt")

    #expect(result.reasoningText == "I will open the conversation with witty banter.")
    #expect(result.steps.count == 1)
    #expect(result.finalStep?.index == result.steps.last?.index)
    #expect(result.finalStep?.reasoning == "I will open the conversation with witty banter.")
    #expect(result.finalStep?.sources == [source])
    #expect(result.finalStep?.files == [file])
    #expect(result.finalStep?.content == content)
}

@Test func aiGenerateTextRefinesToolInputBeforeExecutionAndResultSurfacesLikeUpstream() async throws {
    let rawToolCall = AIToolCall(
        id: "call-1",
        name: "tool1",
        arguments: #"{"value":" raw "}"#
    )
    let refinedToolCall = AIToolCall(
        id: "call-1",
        name: "tool1",
        arguments: #"{"value":"raw"}"#
    )
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            content: [.toolCall(rawToolCall)],
            finishReason: "tool-calls",
            rawValue: .object(["step": 1])
        ),
        TextGenerationResult(
            text: "Done.",
            content: [.text("Done.")],
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
        ],
        refineArguments: { input in
            ["value": .string(input["value"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")]
        }
    ) { input in
        #expect(input == ["value": "raw"])
        return .string("result:\(input["value"]?.stringValue ?? "")")
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 2
    )

    #expect(result.toolCalls == [refinedToolCall])
    #expect(result.steps[0].toolCalls == [refinedToolCall])
    #expect(result.content.contains(AIResultContentPart.toolCall(refinedToolCall)))
    #expect(result.toolResults == [
        AIToolResult(toolCallID: "call-1", toolName: "tool1", result: "result:raw")
    ])
    #expect(result.responseMessages.first == AIMessage(role: .assistant, content: [
        .toolCall(refinedToolCall)
    ]))
    #expect(model.requests[1].messages[1].content == [.toolCall(refinedToolCall)])
}

@Test func aiGenerateTextToolResultsExposeExecutedOutputsLikeUpstream() async throws {
    let toolCall = AIToolCall(
        id: "call-1",
        name: "tool1",
        arguments: #"{"value":"value"}"#
    )
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            content: [.toolCall(toolCall)],
            finishReason: "tool-calls",
            rawValue: .object(["step": 1])
        ),
        TextGenerationResult(
            text: "Done.",
            content: [.text("Done.")],
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
    ) { input in
        #expect(input == ["value": "value"])
        return "result1"
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 2
    )

    #expect(result.toolResults == [
        AIToolResult(toolCallID: "call-1", toolName: "tool1", result: "result1")
    ])
    #expect(result.steps[0].toolResults == [
        AIToolResult(toolCallID: "call-1", toolName: "tool1", result: "result1")
    ])
}

@Test func aiGenerateTextProviderMetadataIsExposedLikeUpstream() async throws {
    let providerMetadata: [String: JSONValue] = [
        "exampleProvider": [
            "a": 10,
            "b": 20
        ]
    ]
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "",
        content: [],
        providerMetadata: providerMetadata,
        rawValue: .object([:])
    ))

    let result = try await AI.generateText(model: model, prompt: "test-input")

    #expect(result.providerMetadata == providerMetadata)
    #expect(result.finalStep?.providerMetadata == providerMetadata)
}

@Test func aiGenerateTextResponseMetadataOmitsBodyByDefaultLikeUpstream() async throws {
    let responseMetadata = AIResponseMetadata(
        id: "test-id-from-model",
        timestamp: Date(timeIntervalSince1970: 10),
        modelID: "test-response-model-id",
        headers: ["custom-response-header": "response-header-value"],
        body: "test body"
    )
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "Hello, world!",
        content: [.text("Hello, world!")],
        rawValue: .object([:]),
        responseMetadata: responseMetadata
    ))

    let result = try await AI.generateText(model: model, prompt: "prompt")

    #expect(result.responseMetadata.id == responseMetadata.id)
    #expect(result.responseMetadata.timestamp == responseMetadata.timestamp)
    #expect(result.responseMetadata.modelID == responseMetadata.modelID)
    #expect(result.responseMetadata.headers == responseMetadata.headers)
    #expect(result.responseMetadata.body == nil)
    #expect(result.steps.count == 1)
    #expect(result.steps[0].responseMetadata.body == nil)
}

@Test func aiGenerateTextResponseMetadataIncludesBodyWhenRequestedLikeUpstream() async throws {
    let responseMetadata = AIResponseMetadata(
        id: "test-id-from-model",
        timestamp: Date(timeIntervalSince1970: 10),
        modelID: "test-response-model-id",
        headers: ["custom-response-header": "response-header-value"],
        body: "test body"
    )
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "Hello, world!",
        content: [.text("Hello, world!")],
        rawValue: .object([:]),
        responseMetadata: responseMetadata
    ))

    let result = try await AI.generateText(model: model, prompt: "prompt", includeResponseBody: true)

    #expect(result.responseMetadata == responseMetadata)
    #expect(result.steps.count == 1)
    #expect(result.steps[0].responseMetadata == responseMetadata)
}

