import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiOutputObjectResponseFormatCompleteAndPartialParsingLikeUpstream() async throws {
    let schema: JSONValue = [
        "type": "object",
        "properties": ["content": ["type": "string"]],
        "required": ["content"],
        "additionalProperties": false
    ]
    let output = Output.object(
        schema: schema,
        name: "test-name",
        description: "test description",
        as: OutputContent.self
    )
    let request = objectRequest(
        from: LanguageModelRequest(messages: [.user("Return object.")]),
        schema: output.schema,
        schemaName: output.name,
        schemaDescription: output.description,
        jsonInstruction: nil
    )

    #expect(request.responseFormat == .json(
        schema: schema,
        name: "test-name",
        description: "test description"
    ))
    #expect(request.extraBody["responseFormat"] == responseFormatJSON(
        schema: schema,
        name: "test-name",
        description: "test description"
    ))

    let parsed = try await parseObject(
        OutputContent.self,
        from: #"{ "content": "test" }"#,
        schema: schema,
        repairText: nil,
        providerID: "mock"
    )
    #expect(parsed.object == OutputContent(content: "test"))
    #expect(parsed.rawObject == ["content": "test"])

    do {
        _ = try await parseObject(
            OutputContent.self,
            from: #"{ "content": 123 }"#,
            schema: schema,
            repairText: nil,
            providerID: "mock"
        )
        Issue.record("expected schema validation error")
    } catch let error as AIObjectGenerationError {
        #expect(error.strategy == .object)
        #expect(error.kind == .schemaValidation)
        #expect(error.path == "$.content")
    }

    #expect(partialObject(from: #"{ "content": "test" }"#) == ["content": "test"])
    #expect(partialObject(from: #"{ "content": "test""#) == ["content": "test"])
    #expect(partialObject(from: #"{ "content": "partial str"#) == ["content": "partial str"])
    #expect(partialObject(from: "") == nil)
}

@Test func aiOutputObjectStreamsValidPartialTextFragmentsLikeUpstream() async throws {
    let schema = outputValueSchema()
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "{ "),
            .textDeltaPart(id: "1", delta: #""value": "#),
            .textDeltaPart(id: "1", delta: #""Hello, "#),
            .textDeltaPart(id: "1", delta: "world"),
            .textDeltaPart(id: "1", delta: #"!""#),
            .textDeltaPart(id: "1", delta: " }"),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 13))
        ]
    )
    var textDeltas: [String] = []

    for try await part in AI.streamText(
        model: model,
        prompt: "prompt",
        output: Output.object(schema: schema, as: OutputValue.self)
    ) {
        if case let .textDelta(delta) = part {
            textDeltas.append(delta)
        }
    }

    #expect(textDeltas == [
        "{ ",
        #""value": "Hello, "#,
        "world",
        #"!""#,
        " }"
    ])
    #expect(model.streamRequests.first?.responseFormat == .json(schema: schema))
}

@Test func aiOutputObjectStreamsPartialsAndFinalOutputLikeUpstream() async throws {
    let schema = outputValueSchema()
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "{ "),
            .textDeltaPart(id: "1", delta: #""value": "#),
            .textDeltaPart(id: "1", delta: #""Hello, "#),
            .textDeltaPart(id: "1", delta: "world"),
            .textDeltaPart(id: "1", delta: #"!" }"#),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 13))
        ]
    )
    var partials: [JSONValue] = []
    var output: AIOutputGenerationResult<OutputValue>?

    for try await part in AI.streamText(
        model: model,
        prompt: "prompt",
        output: Output.object(schema: schema, as: OutputValue.self)
    ) {
        switch part {
        case let .partialOutput(partial):
            partials.append(partial)
        case let .output(result):
            output = result
        default:
            break
        }
    }

    #expect(partials == [
        [:],
        ["value": "Hello, "],
        ["value": "Hello, world"],
        ["value": "Hello, world!"]
    ])
    #expect(output?.text == #"{ "value": "Hello, world!" }"#)
    #expect(output?.output == OutputValue(value: "Hello, world!"))
    #expect(output?.rawOutput == ["value": "Hello, world!"])
}

@Test func aiGenerateTextOutputObjectDoesNotParseToolCallFinishLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "testTool", arguments: #"{ "value": "test" }"#)
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "",
        finishReason: "tool-calls",
        toolCalls: [toolCall],
        rawValue: .object([:])
    ))
    let tool = AITool(
        name: "testTool",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { _ in
        "tool result"
    }
    let schema: JSONValue = [
        "type": "object",
        "properties": ["summary": ["type": "string"]],
        "required": ["summary"],
        "additionalProperties": false
    ]

    let result = try await AI.generateText(
        model: model,
        prompt: "prompt",
        output: Output.object(schema: schema, as: OutputSummary.self),
        executableTools: [tool],
        maxSteps: 1
    )

    #expect(result.output == nil)
    #expect(result.rawOutput == .null)
    #expect(result.textResult.toolCalls == [toolCall])
    #expect(result.textResult.toolResults == [
        AIToolResult(toolCallID: "call-1", toolName: "testTool", result: "tool result")
    ])
    #expect(model.requests.first?.responseFormat == .json(schema: schema))
}
