import Foundation
import Testing
@testable import SwiftAISDK

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
@Test func aiStreamObjectArrayAcceptsElementSchemaAdapter() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta(#"{"elements":[{"value":"adapter","count":9}]}"#),
            .finish(reason: "stop", usage: nil)
        ]
    )
    let schema = AIJSONSchema<ObjectFacadeAnswer>(
        objectFacadeAnswerSchema(),
        name: "adapterAnswers",
        description: "Adapter element schema."
    )

    var object: ObjectGenerationResult<[ObjectFacadeAnswer]>?
    for try await part in AI.streamObjectArray(
        model: model,
        prompt: "Stream adapter answers.",
        elementSchema: schema
    ) {
        if case let .object(result) = part {
            object = result
        }
    }

    #expect(object?.object == [ObjectFacadeAnswer(value: "adapter", count: 9)])

    let request = try #require(model.streamRequests.first)
    #expect(request.responseFormat == .json(
        schema: arrayOutputSchemaForTest(elementSchema: objectFacadeAnswerSchema()),
        name: "adapterAnswers",
        description: "Adapter element schema."
    ))
    #expect(request.extraBody["responseFormat"]?["schema"]?["properties"]?["elements"]?["items"]?["properties"]?["value"]?["type"]?.stringValue == "string")
    #expect(request.extraBody["responseFormat"]?["name"]?.stringValue == "adapterAnswers")
    #expect(request.extraBody["responseFormat"]?["description"]?.stringValue == "Adapter element schema.")
}
@Test func aiStreamObjectArrayMapsCallbacksToArrayOutput() async throws {
    let recorder = ObjectCallbackRecorder<[ObjectFacadeAnswer]>()
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta(#"{"elements":[{"value":"array-callback","count":2}]}"#),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
        ]
    )

    var object: ObjectGenerationResult<[ObjectFacadeAnswer]>?
    for try await part in AI.streamObjectArray(
        model: model,
        prompt: "Stream callback answers.",
        as: ObjectFacadeAnswer.self,
        elementSchema: objectFacadeAnswerSchema(),
        callbacks: AIObjectGenerationCallbacks(
            onStart: { event in await recorder.recordStart(event) },
            onStepStart: { event in await recorder.recordStepStart(event) },
            onStepFinish: { event in await recorder.recordStepFinish(event) },
            onFinish: { event in await recorder.recordFinish(event) },
            onError: { event in await recorder.recordError(event) }
        )
    ) {
        if case let .object(result) = part {
            object = result
        }
    }

    let events = await recorder.events()
    #expect(object?.object == [ObjectFacadeAnswer(value: "array-callback", count: 2)])
    #expect(events.names == ["start", "step-start", "step-finish", "finish"])
    #expect(events.start?.operationID == "ai.streamObject")
    #expect(events.start?.outputKind == "array")
    #expect(events.stepFinish?.text == #"{"elements":[{"value":"array-callback","count":2}]}"#)
    #expect(events.stepFinish?.usage?.totalTokens == 5)
    #expect(events.finish?.object == [ObjectFacadeAnswer(value: "array-callback", count: 2)])
    #expect(events.error == nil)
}
@Test func aiStreamObjectCanInjectJSONInstruction() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta(#"{"value":"stream-instructed","count":11}"#),
            .finish(reason: "stop", usage: nil)
        ]
    )

    var object: ObjectGenerationResult<ObjectFacadeAnswer>?
    for try await part in AI.streamObject(
        model: model,
        prompt: "Stream an object.",
        as: ObjectFacadeAnswer.self,
        schema: objectFacadeAnswerSchema(),
        jsonInstruction: .automatic
    ) {
        if case let .object(result) = part {
            object = result
        }
    }

    #expect(object?.object == ObjectFacadeAnswer(value: "stream-instructed", count: 11))

    let request = try #require(model.streamRequests.first)
    #expect(request.messages.count == 2)
    #expect(request.messages[0].combinedText.contains("JSON schema:"))
    #expect(request.messages[0].combinedText.contains("You MUST answer with a JSON object that matches the JSON schema above."))
    #expect(request.messages[1] == .user("Stream an object."))
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
@Test func outputTextRoutesThroughGenerateText() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: "plain output",
        finishReason: "stop",
        usage: TokenUsage(totalTokens: 2),
        rawValue: .object([:])
    ))

    let result = try await AI.generateText(
        model: model,
        prompt: "Say hi.",
        output: Output.text()
    )

    #expect(result.output == "plain output")
    #expect(result.text == "plain output")
    #expect(result.rawOutput == .string("plain output"))
    #expect(result.finishReason == "stop")
    #expect(result.usage?.totalTokens == 2)
    #expect(model.requests.first?.responseFormat == nil)
}
@Test func outputObjectRoutesThroughGenerateTextAndValidatesSchema() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{"value":"output-object","count":4}"#,
        rawValue: .object([:])
    ))

    let result = try await AI.generateText(
        model: model,
        prompt: "Return an object.",
        output: Output.object(
            schema: objectFacadeAnswerSchema(),
            name: "answer",
            description: "Answer object.",
            as: ObjectFacadeAnswer.self
        )
    )

    #expect(result.output == ObjectFacadeAnswer(value: "output-object", count: 4))
    #expect(result.rawOutput["value"]?.stringValue == "output-object")
    #expect(result.textResult.text == #"{"value":"output-object","count":4}"#)

    let request = try #require(model.requests.first)
    #expect(request.responseFormat == .json(
        schema: objectFacadeAnswerSchema(),
        name: "answer",
        description: "Answer object."
    ))
    #expect(request.extraBody["responseFormat"]?["name"]?.stringValue == "answer")
}
@Test func outputArrayChoiceAndJSONRouteThroughGenerateText() async throws {
    let arrayModel = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{"elements":[{"value":"one","count":1}]}"#,
        rawValue: .object([:])
    ))
    let arrayResult = try await AI.generateText(
        model: arrayModel,
        prompt: "Return answers.",
        output: Output.array(element: objectFacadeAnswerSchema(), as: ObjectFacadeAnswer.self)
    )

    #expect(arrayResult.output == [ObjectFacadeAnswer(value: "one", count: 1)])
    #expect(arrayResult.rawOutput[0]?["value"]?.stringValue == "one")

    let choiceModel = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{"result":"fast"}"#,
        rawValue: .object([:])
    ))
    let choiceResult = try await AI.generateText(
        model: choiceModel,
        prompt: "Choose speed.",
        output: Output.choice(
            options: ["slow", "fast"],
            name: "speed",
            description: "Speed choice."
        )
    )

    #expect(choiceResult.output == "fast")
    #expect(choiceResult.rawOutput == .string("fast"))
    let choiceRequest = try #require(choiceModel.requests.first)
    #expect(choiceRequest.responseFormat == .json(
        schema: enumOutputSchemaForTest(values: ["slow", "fast"]),
        name: "speed",
        description: "Speed choice."
    ))
    #expect(choiceRequest.extraBody["responseFormat"]?["name"]?.stringValue == "speed")
    #expect(choiceRequest.extraBody["responseFormat"]?["description"]?.stringValue == "Speed choice.")

    let jsonModel = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{"loose":true}"#,
        rawValue: .object([:])
    ))
    let jsonResult = try await AI.generateText(
        model: jsonModel,
        prompt: "Return JSON.",
        output: Output.json(name: "loose", description: "Loose JSON.")
    )

    #expect(jsonResult.output["loose"]?.boolValue == true)
    #expect(jsonResult.rawOutput["loose"]?.boolValue == true)
    let jsonRequest = try #require(jsonModel.requests.first)
    #expect(jsonRequest.responseFormat == .json(name: "loose", description: "Loose JSON."))
    #expect(jsonRequest.extraBody["responseFormat"]?["name"]?.stringValue == "loose")
    #expect(jsonRequest.extraBody["responseFormat"]?["description"]?.stringValue == "Loose JSON.")
}
@Test func outputObjectStreamsThroughStreamText() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta(#"{"value":"stream-output","#),
            .textDelta(#""count":12}"#),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 6))
        ]
    )

    var text = ""
    var partials: [JSONValue] = []
    var output: AIOutputGenerationResult<ObjectFacadeAnswer>?
    var finish: (reason: String?, usage: TokenUsage?)?

    for try await part in AI.streamText(
        model: model,
        prompt: "Stream an object.",
        output: Output.object(schema: objectFacadeAnswerSchema(), as: ObjectFacadeAnswer.self)
    ) {
        switch part {
        case let .textDelta(delta):
            text += delta
        case let .partialOutput(partial):
            partials.append(partial)
        case let .output(result):
            output = result
        case let .finish(reason, usage):
            finish = (reason, usage)
        default:
            break
        }
    }

    #expect(text == #"{"value":"stream-output","count":12}"#)
    #expect(partials.contains { $0["value"]?.stringValue == "stream-output" })
    #expect(output?.output == ObjectFacadeAnswer(value: "stream-output", count: 12))
    #expect(output?.rawOutput["count"]?.intValue == 12)
    #expect(finish?.reason == "stop")
    #expect(finish?.usage?.totalTokens == 6)
}
