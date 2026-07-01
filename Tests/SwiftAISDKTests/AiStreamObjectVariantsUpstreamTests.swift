import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiStreamObjectArrayStreamsOnlyCompleteObjectsLikeUpstream() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: #"{"elements":["#),
            .textDeltaPart(id: "1", delta: #"{ "#),
            .textDeltaPart(id: "1", delta: #""content": "#),
            .textDeltaPart(id: "1", delta: #""element 1""#),
            .textDeltaPart(id: "1", delta: #"},"#),
            .textDeltaPart(id: "1", delta: #"{ "#),
            .textDeltaPart(id: "1", delta: #""content": "#),
            .textDeltaPart(id: "1", delta: #""element 2""#),
            .textDeltaPart(id: "1", delta: #"},"#),
            .textDeltaPart(id: "1", delta: #"{"#),
            .textDeltaPart(id: "1", delta: #""content":"#),
            .textDeltaPart(id: "1", delta: #""element 3""#),
            .textDeltaPart(id: "1", delta: #"}"#),
            .textDeltaPart(id: "1", delta: #"]"#),
            .textDeltaPart(id: "1", delta: #"}"#),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
        ]
    )

    var rawPartials: [JSONValue] = []
    var typedPartials: [[StreamObjectContent]] = []
    var object: ObjectGenerationResult<[StreamObjectContent]>?
    for try await part in AI.streamObjectArray(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        elementSchema: streamObjectContentSchema()
    ) {
        switch part {
        case let .partialObject(partial):
            rawPartials.append(partial)
        case let .partial(partial):
            typedPartials.append(partial)
        case let .object(result):
            object = result
        default:
            break
        }
    }

    let expected = [
        StreamObjectContent(content: "element 1"),
        StreamObjectContent(content: "element 2"),
        StreamObjectContent(content: "element 3")
    ]
    #expect(rawPartials == [
        [],
        [["content": "element 1"]],
        [["content": "element 1"], ["content": "element 2"]],
        [["content": "element 1"], ["content": "element 2"], ["content": "element 3"]]
    ])
    #expect(typedPartials == [
        [],
        [StreamObjectContent(content: "element 1")],
        [StreamObjectContent(content: "element 1"), StreamObjectContent(content: "element 2")],
        expected
    ])
    #expect(object?.object == expected)
    #expect(object?.usage == TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
}

@Test func aiStreamObjectArrayStreamsSingleChunkObjectsLikeUpstream() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: #"{"elements":[{"content":"element 1"},{"content":"element 2"}]}"#),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
        ]
    )

    var rawPartials: [JSONValue] = []
    var typedPartials: [[StreamObjectContent]] = []
    var object: ObjectGenerationResult<[StreamObjectContent]>?
    for try await part in AI.streamObjectArray(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        elementSchema: streamObjectContentSchema()
    ) {
        switch part {
        case let .partialObject(partial):
            rawPartials.append(partial)
        case let .partial(partial):
            typedPartials.append(partial)
        case let .object(result):
            object = result
        default:
            break
        }
    }

    let expected = [
        StreamObjectContent(content: "element 1"),
        StreamObjectContent(content: "element 2")
    ]
    #expect(rawPartials == [
        [["content": "element 1"], ["content": "element 2"]]
    ])
    #expect(typedPartials == [expected])
    #expect(object?.object == expected)
    #expect(object?.usage == TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
}

@Test func aiStreamObjectEnumStreamsValueLikeUpstream() async throws {
    let result = try await collectStreamEnumUpstreamPartials(
        chunks: ["{ ", #""result": "#, #""su"#, "nny", #"""#, " }"],
        values: ["sunny", "rainy", "snowy"]
    )

    #expect(result.rawPartials == ["sunny"])
    #expect(result.typedPartials == ["sunny"])
    #expect(result.object == "sunny")
}

@Test func aiStreamObjectEnumDoesNotStreamIncorrectValuesLikeUpstream() async throws {
    let result = try await collectStreamEnumUpstreamPartials(
        chunks: ["{ ", #""result": "#, #""foo"#, "bar", #"""#, " }"],
        values: ["sunny", "rainy", "snowy"]
    )

    #expect(result.rawPartials.isEmpty)
    #expect(result.typedPartials.isEmpty)
    #expect(result.object == nil)
    #expect(result.error?.kind == .schemaValidation)
}

@Test func aiStreamObjectEnumHandlesAmbiguousValuesLikeUpstream() async throws {
    let result = try await collectStreamEnumUpstreamPartials(
        chunks: ["{ ", #""result": "#, #""foo"#, "bar", #"""#, " }"],
        values: ["foobar", "foobar2"]
    )

    #expect(result.rawPartials == ["foo", "foobar"])
    #expect(result.typedPartials == ["foobar"])
    #expect(result.object == "foobar")
}

@Test func aiStreamObjectEnumHandlesNonAmbiguousValuesLikeUpstream() async throws {
    let result = try await collectStreamEnumUpstreamPartials(
        chunks: ["{ ", #""result": "#, #""foo"#, "bar", #"""#, " }"],
        values: ["foobar", "barfoo"]
    )

    #expect(result.rawPartials == ["foobar"])
    #expect(result.typedPartials == ["foobar"])
    #expect(result.object == "foobar")
}

@Test func aiStreamObjectNoSchemaSendsObjectDeltasLikeUpstream() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "{ "),
            .textDeltaPart(id: "1", delta: #""content": "#),
            .textDeltaPart(id: "1", delta: #""Hello, "#),
            .textDeltaPart(id: "1", delta: "world"),
            .textDeltaPart(id: "1", delta: #"!""#),
            .textDeltaPart(id: "1", delta: " }"),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
        ]
    )

    var partials: [JSONValue] = []
    for try await part in AI.streamJSON(
        model: model,
        prompt: "prompt"
    ) {
        if case let .partialObject(partial) = part {
            partials.append(partial)
        }
    }

    #expect(partials == [
        [:],
        ["content": "Hello, "],
        ["content": "Hello, world"],
        ["content": "Hello, world!"]
    ])
    #expect(model.streamRequests.first?.responseFormat == .json())
    #expect(model.streamRequests.first?.extraBody["responseFormat"]?["type"]?.stringValue == "json")
    #expect(model.streamRequests.first?.extraBody["responseFormat"]?["schema"] == nil)
    #expect(model.streamRequests.first?.extraBody["responseFormat"]?["name"] == nil)
    #expect(model.streamRequests.first?.extraBody["responseFormat"]?["description"] == nil)
}
