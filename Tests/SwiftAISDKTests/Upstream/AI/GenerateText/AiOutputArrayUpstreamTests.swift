import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiOutputArrayResponseFormatCompleteAndPartialParsingLikeUpstream() async throws {
    let elementSchema: JSONValue = [
        "type": "object",
        "properties": ["content": ["type": "string"]],
        "required": ["content"],
        "additionalProperties": false
    ]
    let schema = arrayOutputSchema(elementSchema: elementSchema)
    let output = Output.array(
        element: elementSchema,
        name: "test-array-name",
        description: "test array description",
        as: OutputContent.self
    )
    let request = objectRequest(
        from: LanguageModelRequest(messages: [.user("Return array.")]),
        schema: arrayOutputSchema(elementSchema: output.schema ?? .object([:])),
        schemaName: output.name,
        schemaDescription: output.description,
        jsonInstruction: nil
    )

    #expect(request.responseFormat == .json(
        schema: schema,
        name: "test-array-name",
        description: "test array description"
    ))

    let parsed = try await parseObjectArray(
        OutputContent.self,
        from: #"{ "elements": [{ "content": "a" }, { "content": "b" }, { "content": "c" }] }"#,
        elementSchema: elementSchema,
        repairText: nil,
        providerID: "mock"
    )
    #expect(parsed.object == [
        OutputContent(content: "a"),
        OutputContent(content: "b"),
        OutputContent(content: "c")
    ])
    #expect(parsed.rawObject == [
        ["content": "a"],
        ["content": "b"],
        ["content": "c"]
    ])

    let successfulPartial = arrayPartialElements(from: #"{ "elements": [{ "content": "a" }, { "content": "b" }] }"#)
    #expect(successfulPartial == [
        ["content": "a"],
        ["content": "b"]
    ])
    let repairedPartial = arrayPartialElements(from: #"{ "elements": [{ "content": "a" }, { "content": "b" }"#)
    #expect(repairedPartial == [
        ["content": "a"]
    ])
    #expect(arrayPartialElements(from: #"{ "elements": [] }"#) == [])
    #expect(arrayPartialElements(from: #"{ "content": "test" }"#) == nil)
    #expect(arrayPartialElements(from: #"{ "elements": "not-an-array" }"#) == nil)
    #expect(arrayPartialElements(from: #"{ not valid json"#) == nil)
}

@Test func aiOutputArrayStreamsCompleteObjectPartialsAndFinalOutputLikeUpstream() async throws {
    let elementSchema = outputContentSchema()
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: #"{"elements":["#),
            .textDeltaPart(id: "1", delta: #"{"content":"element 1"},"#),
            .textDeltaPart(id: "1", delta: #"{ "content": "element 2"},"#),
            .textDeltaPart(id: "1", delta: #"{"content":"element 3"}"#),
            .textDeltaPart(id: "1", delta: #"]}"#),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 13))
        ]
    )
    var partials: [[OutputContent]] = []
    var output: AIOutputGenerationResult<[OutputContent]>?

    for try await part in AI.streamText(
        model: model,
        prompt: "prompt",
        output: Output.array(element: elementSchema, as: OutputContent.self)
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

    let expected = [
        OutputContent(content: "element 1"),
        OutputContent(content: "element 2"),
        OutputContent(content: "element 3")
    ]
    #expect(partials == [
        [],
        [expected[0]],
        [expected[0], expected[1]],
        expected
    ])
    #expect(output?.output == expected)
    #expect(output?.rawOutput == [
        ["content": "element 1"],
        ["content": "element 2"],
        ["content": "element 3"]
    ])
    #expect(model.streamRequests.first?.responseFormat == .json(schema: arrayOutputSchema(elementSchema: elementSchema)))
}

@Test func aiOutputArrayStreamsAllElementsFromSingleChunkLikeUpstream() async throws {
    let elementSchema = outputContentSchema()
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: #"{"elements":[{"content":"element 1"},{"content":"element 2"}]}"#),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 13))
        ]
    )
    var partials: [[OutputContent]] = []
    var output: AIOutputGenerationResult<[OutputContent]>?

    for try await part in AI.streamText(
        model: model,
        prompt: "prompt",
        output: Output.array(element: elementSchema, as: OutputContent.self)
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

    let expected = [
        OutputContent(content: "element 1"),
        OutputContent(content: "element 2")
    ]
    #expect(partials == [expected])
    #expect(output?.output == expected)
    #expect(output?.rawOutput == [
        ["content": "element 1"],
        ["content": "element 2"]
    ])
}
