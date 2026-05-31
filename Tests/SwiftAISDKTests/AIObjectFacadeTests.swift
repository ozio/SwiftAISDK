import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiStreamObjectRequestsSchemaAndEmitsFinalObject() async throws {
    let schema = objectFacadeAnswerSchema()
    let warning = AIWarning(type: "unsupported", feature: "seed")
    let responseMetadata = AIResponseMetadata(id: "stream-resp")
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .streamStart(warnings: [warning]),
            .textDelta(#"{"value":"strea"#),
            .textDelta(#"med","count":3}"#),
            .responseMetadata(responseMetadata),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 9))
        ]
    )

    var text = ""
    var object: ObjectGenerationResult<ObjectFacadeAnswer>?
    var finish: (reason: String?, usage: TokenUsage?)?
    var warnings: [AIWarning] = []
    var partials: [JSONValue] = []
    for try await part in AI.streamObject(
        model: model,
        prompt: "Stream JSON.",
        as: ObjectFacadeAnswer.self,
        schema: schema,
        schemaName: "answer"
    ) {
        switch part {
        case let .textDelta(delta):
            text += delta
        case let .warning(warning):
            warnings.append(warning)
        case let .partialObject(partial):
            partials.append(partial)
        case let .object(result):
            object = result
        case let .finish(reason, usage):
            finish = (reason, usage)
        default:
            break
        }
    }

    #expect(text == #"{"value":"streamed","count":3}"#)
    #expect(warnings == [warning])
    #expect(partials == [
        .object(["value": .string("strea")]),
        .object(["value": .string("streamed"), "count": .number(3)])
    ])
    #expect(object?.object == ObjectFacadeAnswer(value: "streamed", count: 3))
    #expect(object?.text == #"{"value":"streamed","count":3}"#)
    #expect(object?.rawObject["count"]?.intValue == 3)
    #expect(object?.finishReason == "stop")
    #expect(object?.usage?.totalTokens == 9)
    #expect(object?.warnings == [warning])
    #expect(object?.responseMetadata == responseMetadata)
    #expect(finish?.reason == "stop")
    #expect(finish?.usage?.totalTokens == 9)

    let request = try #require(model.streamRequests.first)
    #expect(request.messages == [.user("Stream JSON.")])
    #expect(request.responseFormat == .json(schema: schema, name: "answer"))
    #expect(request.extraBody["responseFormat"]?["schema"]?["properties"]?["value"]?["type"]?.stringValue == "string")
    #expect(request.extraBody["responseFormat"]?["name"]?.stringValue == "answer")
}

@Test func aiStreamObjectEmitsBestEffortPartialObjects() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta("{"),
            .textDelta(#""value":"partial str"#),
            .textDelta(#"","count":42"#),
            .textDelta("}"),
            .finish(reason: "stop", usage: nil)
        ]
    )

    var partials: [JSONValue] = []
    var object: ObjectGenerationResult<ObjectFacadeAnswer>?
    for try await part in AI.streamObject(
        model: model,
        prompt: "Stream partial JSON.",
        as: ObjectFacadeAnswer.self
    ) {
        switch part {
        case let .partialObject(partial):
            partials.append(partial)
        case let .object(result):
            object = result
        default:
            break
        }
    }

    #expect(partials == [
        .object([:]),
        .object(["value": .string("partial str")]),
        .object(["value": .string("partial str"), "count": .number(42)])
    ])
    #expect(object?.object == ObjectFacadeAnswer(value: "partial str", count: 42))
}

@Test func aiStreamObjectTimesOut() async throws {
    let model = SlowObjectFacadeLanguageModel(delayNanoseconds: 80_000_000)

    do {
        for try await _ in AI.streamObject(
            model: model,
            prompt: "Stream slowly.",
            as: ObjectFacadeAnswer.self,
            timeoutNanoseconds: 1_000_000
        ) {}
        Issue.record("Expected object stream timeout.")
    } catch let error as AIError {
        #expect(error == .timeout(durationNanoseconds: 1_000_000))
    }

    #expect(model.streamRequests.count == 1)
}

@Test func aiStreamObjectCanRepairFinalText() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta("value: repaired"),
            .finish(reason: "stop", usage: nil)
        ]
    )

    let stream = AI.streamObject(
        model: model,
        prompt: "Stream repaired JSON.",
        as: ObjectFacadeAnswer.self
    ) { context in
        #expect(context.text == "value: repaired")
        return #"{"value":"repaired","count":4}"#
    }

    var object: ObjectGenerationResult<ObjectFacadeAnswer>?
    for try await part in stream {
        if case let .object(result) = part {
            object = result
        }
    }

    #expect(object?.object == ObjectFacadeAnswer(value: "repaired", count: 4))
    #expect(object?.text == #"{"value":"repaired","count":4}"#)
}

@Test func aiGenerateObjectDecodesJSONAndRequestsSchemaResponseFormat() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: """
        ```json
        {"value":"test-value","count":2}
        ```
        """,
        finishReason: "stop",
        usage: TokenUsage(totalTokens: 7),
        rawValue: .object(["id": "raw-1"]),
        responseMetadata: AIResponseMetadata(id: "resp-1")
    ))
    let schema = objectFacadeAnswerSchema()

    let result = try await AI.generateObject(
        model: model,
        prompt: "Return an object.",
        as: ObjectFacadeAnswer.self,
        schema: schema,
        schemaName: "answer",
        schemaDescription: "A typed answer."
    )

    #expect(result.object == ObjectFacadeAnswer(value: "test-value", count: 2))
    #expect(result.rawObject["value"]?.stringValue == "test-value")
    #expect(result.finishReason == "stop")
    #expect(result.usage?.totalTokens == 7)
    #expect(result.responseMetadata.id == "resp-1")

    let request = try #require(model.requests.first)
    #expect(request.responseFormat == .json(schema: schema, name: "answer", description: "A typed answer."))
    #expect(request.extraBody["responseFormat"]?["type"]?.stringValue == "json")
    #expect(request.extraBody["responseFormat"]?["schema"]?["properties"]?["value"]?["type"]?.stringValue == "string")
    #expect(request.extraBody["responseFormat"]?["name"]?.stringValue == "answer")
    #expect(request.extraBody["responseFormat"]?["description"]?.stringValue == "A typed answer.")
}

@Test func aiGenerateObjectCanRepairInvalidJSONText() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(text: "value: repaired", rawValue: .object([:])))

    let result = try await AI.generateObject(
        model: model,
        prompt: "Return JSON.",
        as: ObjectFacadeAnswer.self
    ) { context in
        #expect(context.text == "value: repaired")
        return #"{"value":"repaired","count":1}"#
    }

    #expect(result.object == ObjectFacadeAnswer(value: "repaired", count: 1))
    #expect(result.text == #"{"value":"repaired","count":1}"#)
}

@Test func aiGenerateObjectThrowsTypedNoJSONError() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(text: "value: missing-json", rawValue: .object([:])))

    do {
        _ = try await AI.generateObject(
            model: model,
            prompt: "Return JSON.",
            as: ObjectFacadeAnswer.self
        )
        Issue.record("Expected object generation to fail.")
    } catch let error as AIObjectGenerationError {
        #expect(error.provider == "mock")
        #expect(error.strategy == .object)
        #expect(error.kind == .noJSON)
        #expect(error.path == nil)
        #expect(error.text == "value: missing-json")
        #expect(!error.repairAttempted)
    }
}

@Test func aiGenerateObjectThrowsTypedRepairFailure() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(text: "value: broken", rawValue: .object([:])))

    do {
        _ = try await AI.generateObject(
            model: model,
            prompt: "Return JSON.",
            as: ObjectFacadeAnswer.self
        ) { context in
            #expect(context.errorMessage.contains("noJSON"))
            return "still broken"
        }
        Issue.record("Expected repaired object generation to fail.")
    } catch let error as AIObjectGenerationError {
        #expect(error.provider == "mock")
        #expect(error.strategy == .object)
        #expect(error.kind == .noJSON)
        #expect(error.text == "still broken")
        #expect(error.repairAttempted)
    }
}

@Test func aiGenerateObjectValidatesGeneratedObjectAgainstSchema() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(text: #"{"value":"too-many","count":10}"#, rawValue: .object([:])))
    let schema = objectFacadeAnswerSchema(countMaximum: 5)

    do {
        _ = try await AI.generateObject(
            model: model,
            prompt: "Return JSON.",
            as: ObjectFacadeAnswer.self,
            schema: schema
        )
        Issue.record("Expected generated object to fail schema validation.")
    } catch let error as AIObjectGenerationError {
        #expect(error.provider == "mock")
        #expect(error.strategy == .object)
        #expect(error.kind == .schemaValidation)
        #expect(error.path == "$.count")
        #expect(error.message.contains("must be <="))
        #expect(error.text == #"{"value":"too-many","count":10}"#)
        #expect(!error.repairAttempted)
    }
}

@Test func aiGenerateObjectCanRepairSchemaValidationFailures() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(text: #"{"value":"too-many","count":10}"#, rawValue: .object([:])))
    let schema = objectFacadeAnswerSchema(countMaximum: 5)

    let result = try await AI.generateObject(
        model: model,
        prompt: "Return JSON.",
        as: ObjectFacadeAnswer.self,
        schema: schema
    ) { context in
        #expect(context.text == #"{"value":"too-many","count":10}"#)
        #expect(context.errorMessage.contains("$.count"))
        return #"{"value":"repaired","count":3}"#
    }

    #expect(result.object == ObjectFacadeAnswer(value: "repaired", count: 3))
    #expect(result.rawObject["count"]?.intValue == 3)
}

@Test func aiGenerateObjectArrayWrapsElementSchemaAndReturnsArray() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{"elements":[{"value":"one","count":1},{"value":"two","count":2}]}"#,
        rawValue: .object([:])
    ))
    let elementSchema = objectFacadeAnswerSchema(includeDraftSchema: true, additionalProperties: false)

    let result = try await AI.generateObjectArray(
        model: model,
        prompt: "Return answers.",
        as: ObjectFacadeAnswer.self,
        elementSchema: elementSchema,
        schemaName: "answers",
        schemaDescription: "A list of answers."
    )

    #expect(result.object == [
        ObjectFacadeAnswer(value: "one", count: 1),
        ObjectFacadeAnswer(value: "two", count: 2)
    ])
    #expect(result.rawObject[0]?["value"]?.stringValue == "one")
    #expect(result.rawObject[1]?["count"]?.intValue == 2)

    let request = try #require(model.requests.first)
    let responseFormat = try #require(request.responseFormat)
    guard case let .json(optionalSchema, name, description) = responseFormat else {
        Issue.record("Expected JSON response format.")
        return
    }
    let schema = try #require(optionalSchema)
    #expect(name == "answers")
    #expect(description == "A list of answers.")
    #expect(schema["properties"]?["elements"]?["items"]?["$schema"] == nil)
    #expect(schema["properties"]?["elements"]?["items"]?["properties"]?["value"]?["type"]?.stringValue == "string")
    #expect(request.extraBody["responseFormat"]?["schema"]?["properties"]?["elements"]?["items"]?["properties"]?["count"]?["type"]?.stringValue == "integer")
    #expect(request.extraBody["responseFormat"]?["name"]?.stringValue == "answers")
}

@Test func aiGenerateEnumWrapsEnumValuesAndReturnsSelectedValue() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(text: #"{"result":"fast"}"#, rawValue: .object([:])))

    let result = try await AI.generateEnum(
        model: model,
        prompt: "Choose speed.",
        values: ["slow", "fast"]
    )

    #expect(result.object == "fast")
    #expect(result.rawObject.stringValue == "fast")
    #expect(result.text == "fast")

    let request = try #require(model.requests.first)
    guard case let .json(schema, _, _) = request.responseFormat else {
        Issue.record("Expected JSON response format.")
        return
    }
    #expect(schema?["properties"]?["result"]?["enum"]?[0]?.stringValue == "slow")
    #expect(schema?["properties"]?["result"]?["enum"]?[1]?.stringValue == "fast")
    #expect(request.extraBody["responseFormat"]?["schema"]?["required"]?[0]?.stringValue == "result")
}

@Test func aiGenerateJSONReturnsRawNoSchemaValue() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(text: #"["loose",1,true]"#, rawValue: .object([:])))

    let result = try await AI.generateJSON(
        model: model,
        prompt: "Return any JSON."
    )

    #expect(result.object[0]?.stringValue == "loose")
    #expect(result.object[1]?.intValue == 1)
    #expect(result.object[2]?.boolValue == true)
    #expect(result.rawObject == result.object)
    #expect(result.text == #"["loose",1,true]"#)

    let request = try #require(model.requests.first)
    #expect(request.responseFormat == .json())
    #expect(request.extraBody["responseFormat"]?["type"]?.stringValue == "json")
    #expect(request.extraBody["responseFormat"]?["schema"] == nil)
}

private func objectFacadeAnswerSchema(
    includeDraftSchema: Bool = false,
    countMaximum: Int? = nil,
    additionalProperties: Bool? = nil
) -> JSONValue {
    var countSchema: [String: JSONValue] = ["type": "integer"]
    if let countMaximum {
        countSchema["maximum"] = .number(Double(countMaximum))
    }
    var schema: [String: JSONValue] = [
        "type": "object",
        "properties": [
            "value": ["type": "string"],
            "count": .object(countSchema)
        ],
        "required": ["value", "count"]
    ]
    if includeDraftSchema {
        schema["$schema"] = "https://json-schema.org/draft-07/schema"
    }
    if let additionalProperties {
        schema["additionalProperties"] = .bool(additionalProperties)
    }
    return .object(schema)
}

private struct ObjectFacadeAnswer: Codable, Equatable, Sendable {
    var value: String
    var count: Int
}

private final class ObjectFacadeMockLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-language"
    var requests: [LanguageModelRequest] = []
    var streamRequests: [LanguageModelRequest] = []
    private var results: [TextGenerationResult]
    private var streamSequences: [[LanguageStreamPart]]

    init(result: TextGenerationResult, streamParts: [LanguageStreamPart] = []) {
        self.results = [result]
        self.streamSequences = [streamParts]
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        requests.append(request)
        return results.count > 1 ? results.removeFirst() : results[0]
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamRequests.append(request)
        let parts = streamSequences.count > 1 ? streamSequences.removeFirst() : streamSequences[0]
        return AsyncThrowingStream { continuation in
            for part in parts {
                continuation.yield(part)
            }
            continuation.finish()
        }
    }
}

private final class SlowObjectFacadeLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "slow-object-language"
    var requests: [LanguageModelRequest] = []
    var streamRequests: [LanguageModelRequest] = []
    let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        requests.append(request)
        return TextGenerationResult(text: "", rawValue: .object([:]))
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamRequests.append(request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                    continuation.yield(.textDelta(#"{"value":"late","count":1}"#))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
