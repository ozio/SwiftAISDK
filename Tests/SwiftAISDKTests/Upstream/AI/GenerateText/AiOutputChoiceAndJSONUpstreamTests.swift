import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiOutputChoiceResponseFormatCompleteAndPartialParsingLikeUpstream() async throws {
    let values = ["aaa", "aab", "ccc"]
    let output = Output.choice(
        options: values,
        name: "test-choice-name",
        description: "test choice description"
    )
    let request = objectRequest(
        from: LanguageModelRequest(messages: [.user("Choose.")]),
        schema: enumOutputSchema(values: values),
        schemaName: output.name,
        schemaDescription: output.description,
        jsonInstruction: nil
    )

    #expect(request.responseFormat == .json(
        schema: enumOutputSchema(values: values),
        name: "test-choice-name",
        description: "test choice description"
    ))

    let parsed = try await parseEnum(
        from: #"{ "result": "aaa" }"#,
        values: values,
        repairText: nil,
        providerID: "mock"
    )
    #expect(parsed.object == "aaa")
    #expect(parsed.rawObject == "aaa")

    for invalid in [#"{ broken json"#, #"{}"#, #"{ "result": "d" }"#, #"{ "result": 5 }"#, #""a""#] {
        do {
            _ = try await parseEnum(
                from: invalid,
                values: values,
                repairText: nil,
                providerID: "mock"
            )
            Issue.record("expected invalid choice to throw for \(invalid)")
        } catch let error as AIObjectGenerationError {
            #expect(error.strategy == .enumeration)
        }
    }
}

@Test func aiOutputChoicePartialPrefixResolutionMatchesUpstream() async throws {
    let ambiguous = try await collectStreamEnumPartials(text: #"{ "result": "a"#)
    #expect(ambiguous.isEmpty)

    let singleMatch = try await collectStreamEnumPartials(text: #"{ "result": "c"#)
    #expect(singleMatch == ["ccc"])

    let exact = try await collectStreamEnumPartials(text: #"{ "result": "aab" }"#)
    #expect(exact == ["aab"])

    let missing = try await collectStreamEnumPartials(text: #"{}"#)
    #expect(missing.isEmpty)
}

@Test func aiOutputChoiceStreamsAndResolvesOutputLikeUpstream() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "{ "),
            .textDeltaPart(id: "1", delta: #""result": "#),
            .textDeltaPart(id: "1", delta: #""su"#),
            .textDeltaPart(id: "1", delta: "nny"),
            .textDeltaPart(id: "1", delta: #"""#),
            .textDeltaPart(id: "1", delta: " }"),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 13))
        ]
    )
    var partials: [String] = []
    var output: AIOutputGenerationResult<String>?

    for try await part in AI.streamText(
        model: model,
        prompt: "prompt",
        output: Output.choice(options: ["sunny", "rainy", "snowy"])
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

    #expect(partials == ["sunny"])
    #expect(output?.output == "sunny")
    #expect(output?.rawOutput == "sunny")
    #expect(model.streamRequests.first?.responseFormat == .json(schema: enumOutputSchema(values: ["sunny", "rainy", "snowy"])))
}

@Test func aiOutputJSONResponseFormatCompleteAndPartialParsingLikeUpstream() async throws {
    let output = Output.json(name: "test-json-name", description: "test json description")
    let request = objectRequest(
        from: LanguageModelRequest(messages: [.user("Return JSON.")]),
        schema: output.schema,
        schemaName: output.name,
        schemaDescription: output.description,
        jsonInstruction: nil
    )

    #expect(request.responseFormat == .json(name: "test-json-name", description: "test json description"))
    #expect(request.extraBody["responseFormat"] == responseFormatJSON(
        schema: nil,
        name: "test-json-name",
        description: "test json description"
    ))

    let parsed = try await parseJSONValueObject(
        from: #"{"a":1,"b":[2,3]}"#,
        repairText: nil,
        providerID: "mock"
    )
    #expect(parsed.object == ["a": 1, "b": [2, 3]])

    for invalid in [#"{ a: 1 }"#, "foo"] {
        do {
            _ = try await parseJSONValueObject(
                from: invalid,
                repairText: nil,
                providerID: "mock"
            )
            Issue.record("expected invalid JSON to throw for \(invalid)")
        } catch let error as AIObjectGenerationError {
            #expect(error.strategy == .json)
        }
    }

    #expect(partialObject(from: #"{ "foo": 1, "bar": [2, 3] }"#) == ["foo": 1, "bar": [2, 3]])
    #expect(partialObject(from: #"{ "foo": 123"#)?["foo"] == 123)
    #expect(partialObject(from: "invalid!") == nil)
    #expect(partialObject(from: "undefined") == nil)
}
