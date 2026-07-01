import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiStreamObjectArrayStreamsPartialAndFinalArrays() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta(#"{"elements":[{"value":"one","count":1}"#),
            .textDelta(#",{"value":"two","count":2}]}"#),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 8))
        ]
    )

    var rawPartials: [JSONValue] = []
    var typedPartials: [[ObjectFacadeAnswer]] = []
    var object: ObjectGenerationResult<[ObjectFacadeAnswer]>?
    for try await part in AI.streamObjectArray(
        model: model,
        prompt: "Stream answers.",
        as: ObjectFacadeAnswer.self,
        elementSchema: objectFacadeAnswerSchema(),
        schemaName: "answers"
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

    #expect(rawPartials == [
        .array([]),
        .array([
            .object(["value": .string("one"), "count": .number(1)]),
            .object(["value": .string("two"), "count": .number(2)])
        ])
    ])
    #expect(typedPartials == [
        [],
        [ObjectFacadeAnswer(value: "one", count: 1)],
        [ObjectFacadeAnswer(value: "one", count: 1), ObjectFacadeAnswer(value: "two", count: 2)]
    ])
    #expect(object?.object == [
        ObjectFacadeAnswer(value: "one", count: 1),
        ObjectFacadeAnswer(value: "two", count: 2)
    ])
    #expect(object?.rawObject == rawPartials.last)
    let objectText = try #require(object?.text)
    #expect(try decodeJSONBody(Data(objectText.utf8)) == rawPartials.last)
    #expect(object?.finishReason == "stop")
    #expect(object?.usage?.totalTokens == 8)

    let request = try #require(model.streamRequests.first)
    #expect(request.responseFormat == .json(schema: arrayOutputSchemaForTest(elementSchema: objectFacadeAnswerSchema()), name: "answers"))
    #expect(request.extraBody["responseFormat"]?["schema"]?["properties"]?["elements"]?["items"]?["properties"]?["value"]?["type"]?.stringValue == "string")
}
@Test func aiStreamEnumStreamsSelectedValue() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta(#"{"result":"fast"}"#),
            .finish(reason: "stop", usage: nil)
        ]
    )

    var rawPartials: [JSONValue] = []
    var typedPartials: [String] = []
    var object: ObjectGenerationResult<String>?
    for try await part in AI.streamEnum(
        model: model,
        prompt: "Choose speed.",
        values: ["slow", "fast"]
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

    #expect(rawPartials == [.string("fast")])
    #expect(typedPartials == ["fast"])
    #expect(object?.object == "fast")
    #expect(object?.rawObject == .string("fast"))
    #expect(object?.text == "fast")

    let request = try #require(model.streamRequests.first)
    #expect(request.responseFormat == .json(schema: enumOutputSchemaForTest(values: ["slow", "fast"])))
    #expect(request.extraBody["responseFormat"]?["schema"]?["properties"]?["result"]?["enum"]?[1]?.stringValue == "fast")
}
@Test func aiStreamEnumRejectsEmptyValues() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(text: "", rawValue: .object([:])))

    do {
        for try await _ in AI.streamEnum(model: model, prompt: "Choose.", values: []) {}
        Issue.record("Expected empty enum values to fail.")
    } catch let error as AIError {
        #expect(error == .invalidArgument(argument: "values", message: "Enum values are required."))
    }

    #expect(model.streamRequests.isEmpty)
}
@Test func aiStreamJSONStreamsNoSchemaValue() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta(#"["loose","#),
            .textDelta(#"1,true]"#),
            .finish(reason: "stop", usage: nil)
        ]
    )

    var rawPartials: [JSONValue] = []
    var typedPartials: [JSONValue] = []
    var object: ObjectGenerationResult<JSONValue>?
    for try await part in AI.streamJSON(
        model: model,
        prompt: "Stream any JSON."
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

    #expect(rawPartials == [
        .array([.string("loose")]),
        .array([.string("loose"), .number(1), .bool(true)])
    ])
    #expect(typedPartials == rawPartials)
    #expect(object?.object == .array([.string("loose"), .number(1), .bool(true)]))
    #expect(object?.rawObject == object?.object)
    #expect(object?.text == #"["loose",1,true]"#)

    let request = try #require(model.streamRequests.first)
    #expect(request.responseFormat == .json())
    #expect(request.extraBody["responseFormat"]?["type"]?.stringValue == "json")
    #expect(request.extraBody["responseFormat"]?["schema"] == nil)
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
@Test func aiStreamObjectRejectsInvalidTimeout() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: []
    )

    do {
        for try await _ in AI.streamObject(
            model: model,
            prompt: "Invalid timeout.",
            as: ObjectFacadeAnswer.self,
            timeoutNanoseconds: 0
        ) {}
        Issue.record("Expected invalid object stream timeout.")
    } catch let error as AIError {
        #expect(error == .invalidArgument(argument: "timeoutNanoseconds", message: "timeoutNanoseconds must be greater than zero."))
    }

    #expect(model.streamRequests.isEmpty)
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
@Test func aiGenerateObjectAcceptsSchemaAdapter() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{"value":"schema-adapter","count":6}"#,
        rawValue: .object([:])
    ))
    let schema = AIJSONSchema<ObjectFacadeAnswer>(
        objectFacadeAnswerSchema(),
        name: "adapterAnswer",
        description: "Schema supplied through an adapter."
    )

    let result = try await AI.generateObject(
        model: model,
        prompt: "Return an adapter object.",
        schema: schema
    )

    #expect(result.object == ObjectFacadeAnswer(value: "schema-adapter", count: 6))

    let request = try #require(model.requests.first)
    #expect(request.responseFormat == .json(
        schema: objectFacadeAnswerSchema(),
        name: "adapterAnswer",
        description: "Schema supplied through an adapter."
    ))
    #expect(request.extraBody["responseFormat"]?["schema"]?["required"]?[0]?.stringValue == "value")
    #expect(request.extraBody["responseFormat"]?["name"]?.stringValue == "adapterAnswer")
    #expect(request.extraBody["responseFormat"]?["description"]?.stringValue == "Schema supplied through an adapter.")
}
@Test func aiGenerateObjectCanInjectJSONInstruction() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{"value":"instructed","count":8}"#,
        rawValue: .object([:])
    ))

    let result = try await AI.generateObject(
        model: model,
        prompt: "Return an object.",
        as: ObjectFacadeAnswer.self,
        schema: objectFacadeAnswerSchema(),
        jsonInstruction: .automatic
    )

    #expect(result.object == ObjectFacadeAnswer(value: "instructed", count: 8))

    let request = try #require(model.requests.first)
    #expect(request.messages.count == 2)
    #expect(request.messages[0].role == .system)
    let instruction = request.messages[0].combinedText
    #expect(instruction.contains("JSON schema:"))
    #expect(instruction.contains(#""required":["value","count"]"#))
    #expect(instruction.contains("You MUST answer with a JSON object that matches the JSON schema above."))
    #expect(request.messages[1] == .user("Return an object."))
    #expect(request.responseFormat == .json(schema: objectFacadeAnswerSchema()))
}
@Test func aiGenerateJSONCanInjectGenericJSONInstructionIntoExistingSystemMessage() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{"ok":true}"#,
        rawValue: .object([:])
    ))

    let result = try await AI.generateJSON(
        model: model,
        request: LanguageModelRequest(messages: [
            .system("Be terse."),
            .user("Return JSON.")
        ]),
        jsonInstruction: AIJSONInstruction(schemaSuffix: "Reply with strict JSON only.")
    )

    #expect(result.object["ok"]?.boolValue == true)

    let request = try #require(model.requests.first)
    #expect(request.messages.count == 2)
    #expect(request.messages[0].role == .system)
    #expect(request.messages[0].combinedText == "Be terse.\n\nReply with strict JSON only.")
    #expect(request.messages[1] == .user("Return JSON."))
    #expect(request.responseFormat == .json())
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
@Test func aiGenerateObjectThrowsOriginalErrorWhenRepairReturnsNilLikeUpstream() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(text: #"{"value":"too-many","count":10}"#, rawValue: .object([:])))
    let schema = objectFacadeAnswerSchema(countMaximum: 5)

    do {
        _ = try await AI.generateObject(
            model: model,
            prompt: "Return JSON.",
            as: ObjectFacadeAnswer.self,
            schema: schema
        ) { context in
            #expect(context.text == #"{"value":"too-many","count":10}"#)
            #expect(context.errorMessage.contains("$.count"))
            return nil
        }
        Issue.record("Expected nil repair result to keep object generation failure.")
    } catch let error as AIObjectGenerationError {
        #expect(error.provider == "mock")
        #expect(error.strategy == .object)
        #expect(error.kind == .schemaValidation)
        #expect(error.path == "$.count")
        #expect(error.text == #"{"value":"too-many","count":10}"#)
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
