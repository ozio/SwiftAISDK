import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiGenerateObjectEmitsObjectTelemetry() async throws {
    let recorder = ObjectTelemetryRecorder()
    let schema = objectFacadeAnswerSchema()
    let warning = AIWarning(type: "unsupported", feature: "seed")
    let responseMetadata = AIResponseMetadata(id: "object-resp")
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{"value":"telemetry","count":6}"#,
        finishReason: "stop",
        usage: TokenUsage(totalTokens: 12),
        providerMetadata: ["trace": .string("object")],
        rawValue: .object(["id": .string("raw-object")]),
        warnings: [warning],
        responseMetadata: responseMetadata
    ))

    let result = try await AI.generateObject(
        model: model,
        prompt: "Return a telemetry object.",
        as: ObjectFacadeAnswer.self,
        schema: schema,
        schemaName: "answer",
        schemaDescription: "Answer schema.",
        telemetry: AITelemetryOptions(functionID: "unit.object", integrations: [recorder])
    )
    let events = await recorder.events()

    #expect(result.object == ObjectFacadeAnswer(value: "telemetry", count: 6))
    #expect(events.map(\.kind) == [.start, .end])
    #expect(events.allSatisfy { $0.operationID == "ai.generateObject" })
    #expect(events.allSatisfy { $0.functionID == "unit.object" })
    #expect(events[0].input?["output"]?.stringValue == "object")
    #expect(events[0].input?["schemaName"]?.stringValue == "answer")
    #expect(events[0].input?["schemaDescription"]?.stringValue == "Answer schema.")
    #expect(events[0].input?["schema"]?["properties"]?["value"]?["type"]?.stringValue == "string")
    #expect(events[0].input?["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Return a telemetry object.")
    #expect(events[1].output?["rawObject"]?["count"]?.intValue == 6)
    #expect(events[1].output?["text"]?.stringValue == #"{"value":"telemetry","count":6}"#)
    #expect(events[1].usage?.totalTokens == 12)
    #expect(events[1].warnings == [warning])
    #expect(events[1].providerMetadata["trace"]?.stringValue == "object")
    #expect(events[1].responseMetadata == responseMetadata)
}

@Test func aiGenerateObjectInvokesObjectCallbacksInOrder() async throws {
    let recorder = ObjectCallbackRecorder<ObjectFacadeAnswer>()
    let telemetry = ObjectTelemetryRecorder()
    let schema = objectFacadeAnswerSchema()
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{"value":"callbacks","count":7}"#,
        reasoning: "because",
        finishReason: "stop",
        usage: TokenUsage(totalTokens: 14),
        providerMetadata: ["trace": .string("callbacks")],
        rawValue: .object(["id": .string("raw-callbacks")]),
        responseMetadata: AIResponseMetadata(id: "callback-response")
    ))

    let result = try await AI.generateObject(
        model: model,
        prompt: "Return callback object.",
        as: ObjectFacadeAnswer.self,
        schema: schema,
        schemaName: "answer",
        telemetry: AITelemetryOptions(integrations: [telemetry]),
        callbacks: AIObjectGenerationCallbacks(
            onStart: { event in await recorder.recordStart(event) },
            onStepStart: { event in await recorder.recordStepStart(event) },
            onStepFinish: { event in await recorder.recordStepFinish(event) },
            onFinish: { event in await recorder.recordFinish(event) }
        )
    )

    let events = await recorder.events()
    let telemetryEvents = await telemetry.events()
    #expect(result.object == ObjectFacadeAnswer(value: "callbacks", count: 7))
    #expect(events.names == ["start", "step-start", "step-finish", "finish"])
    #expect(events.callIDs.count == 4)
    #expect(Set(events.callIDs).count == 1)
    #expect(events.callIDs.first == telemetryEvents.first?.callID)
    #expect(events.start?.operationID == "ai.generateObject")
    #expect(events.start?.outputKind == "object")
    #expect(events.start?.schemaName == "answer")
    #expect(events.start?.request.messages == [.user("Return callback object.")])
    #expect(events.stepStart?.stepNumber == 0)
    #expect(events.stepStart?.request.responseFormat == .json(schema: schema, name: "answer"))
    #expect(events.stepFinish?.text == #"{"value":"callbacks","count":7}"#)
    #expect(events.stepFinish?.reasoning == "because")
    #expect(events.stepFinish?.usage?.totalTokens == 14)
    #expect(events.finish?.object == ObjectFacadeAnswer(value: "callbacks", count: 7))
    #expect(events.finish?.rawObject["count"]?.intValue == 7)
    #expect(events.finish?.providerMetadata["trace"]?.stringValue == "callbacks")
    #expect(events.finish?.responseMetadata.id == "callback-response")
}

@Test func aiGenerateObjectInvokesErrorCallbackForParseFailure() async throws {
    let recorder = ObjectCallbackRecorder<ObjectFacadeAnswer>()
    let telemetry = ObjectTelemetryRecorder()
    let warning = AIWarning(type: "unsupported", feature: "json")
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: "not json",
        finishReason: "stop",
        usage: TokenUsage(totalTokens: 4),
        providerMetadata: ["trace": .string("broken")],
        rawValue: .object([:]),
        warnings: [warning],
        responseMetadata: AIResponseMetadata(id: "broken-response")
    ))

    do {
        _ = try await AI.generateObject(
            model: model,
            prompt: "Return broken object.",
            as: ObjectFacadeAnswer.self,
            schema: objectFacadeAnswerSchema(),
            telemetry: AITelemetryOptions(integrations: [telemetry]),
            callbacks: AIObjectGenerationCallbacks(
                onStart: { event in await recorder.recordStart(event) },
                onStepStart: { event in await recorder.recordStepStart(event) },
                onStepFinish: { event in await recorder.recordStepFinish(event) },
                onFinish: { event in await recorder.recordFinish(event) },
                onError: { event in await recorder.recordError(event) }
            )
        )
        Issue.record("Expected generateObject parse failure.")
    } catch let error as AIObjectGenerationError {
        let events = await recorder.events()
        let telemetryEvents = await telemetry.events()
        #expect(error.kind == .noJSON)
        #expect(events.names == ["start", "step-start", "step-finish", "error"])
        #expect(Set(events.callIDs).count == 1)
        #expect(events.callIDs.first == telemetryEvents.first?.callID)
        #expect(events.error?.text == "not json")
        #expect(events.error?.finishReason == "stop")
        #expect(events.error?.usage?.totalTokens == 4)
        #expect(events.error?.warnings == [warning])
        #expect(events.error?.providerMetadata["trace"]?.stringValue == "broken")
        #expect(events.error?.responseMetadata.id == "broken-response")
        #expect(events.error?.errorDescription.isEmpty == false)
        #expect(events.finish == nil)
        #expect(telemetryEvents.map(\.kind) == [.start, .error])
    }
}

@Test func aiStreamObjectInvokesObjectCallbacksInOrder() async throws {
    let recorder = ObjectCallbackRecorder<ObjectFacadeAnswer>()
    let telemetry = ObjectTelemetryRecorder()
    let schema = objectFacadeAnswerSchema()
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta(#"{"value":"stream-callbacks","count":9}"#),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 18))
        ]
    )

    var final: ObjectGenerationResult<ObjectFacadeAnswer>?
    for try await part in AI.streamObject(
        model: model,
        prompt: "Stream callback object.",
        as: ObjectFacadeAnswer.self,
        schema: schema,
        schemaName: "answer",
        telemetry: AITelemetryOptions(integrations: [telemetry]),
        callbacks: AIObjectGenerationCallbacks(
            onStart: { event in await recorder.recordStart(event) },
            onStepStart: { event in await recorder.recordStepStart(event) },
            onStepFinish: { event in await recorder.recordStepFinish(event) },
            onFinish: { event in await recorder.recordFinish(event) },
            onError: { event in await recorder.recordError(event) }
        )
    ) {
        if case let .object(result) = part {
            final = result
        }
    }

    let events = await recorder.events()
    let telemetryEvents = await telemetry.events()
    #expect(final?.object == ObjectFacadeAnswer(value: "stream-callbacks", count: 9))
    #expect(events.names == ["start", "step-start", "step-finish", "finish"])
    #expect(Set(events.callIDs).count == 1)
    #expect(events.callIDs.first == telemetryEvents.first?.callID)
    #expect(events.start?.operationID == "ai.streamObject")
    #expect(events.start?.outputKind == "object")
    #expect(events.start?.schemaName == "answer")
    #expect(events.start?.request.messages == [.user("Stream callback object.")])
    #expect(events.stepStart?.request.responseFormat == .json(schema: schema, name: "answer"))
    #expect(events.stepFinish?.text == #"{"value":"stream-callbacks","count":9}"#)
    #expect(events.stepFinish?.usage?.totalTokens == 18)
    #expect(events.finish?.object == ObjectFacadeAnswer(value: "stream-callbacks", count: 9))
    #expect(events.finish?.rawObject["value"]?.stringValue == "stream-callbacks")
    #expect(events.error == nil)
}

@Test func aiStreamObjectInvokesErrorCallbackForParseFailure() async throws {
    let recorder = ObjectCallbackRecorder<ObjectFacadeAnswer>()
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta("not json"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 3))
        ]
    )

    do {
        for try await _ in AI.streamObject(
            model: model,
            prompt: "Stream broken object.",
            as: ObjectFacadeAnswer.self,
            schema: objectFacadeAnswerSchema(),
            callbacks: AIObjectGenerationCallbacks(
                onStart: { event in await recorder.recordStart(event) },
                onStepStart: { event in await recorder.recordStepStart(event) },
                onStepFinish: { event in await recorder.recordStepFinish(event) },
                onFinish: { event in await recorder.recordFinish(event) },
                onError: { event in await recorder.recordError(event) }
            )
        ) {}
        Issue.record("Expected stream object parse failure.")
    } catch {
        let events = await recorder.events()
        #expect(events.names == ["start", "step-start", "error"])
        #expect(events.error?.text == "not json")
        #expect(events.error?.errorDescription.isEmpty == false)
        #expect(events.finish == nil)
    }
}

@Test func aiStreamObjectRequestsSchemaAndEmitsFinalObject() async throws {
    let recorder = ObjectTelemetryRecorder()
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
        schemaName: "answer",
        telemetry: AITelemetryOptions(integrations: [recorder])
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
    let events = await recorder.events()

    #expect(text == #"{"value":"streamed","count":3}"#)
    #expect(events.map(\.kind) == [.start, .end])
    #expect(events.allSatisfy { $0.operationID == "ai.streamObject" })
    #expect(events[0].input?["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Stream JSON.")
    #expect(events[1].output?["text"]?.stringValue == #"{"value":"streamed","count":3}"#)
    #expect(events[1].output?["rawObject"]?["count"]?.intValue == 3)
    #expect(events[1].output?["partialObjectCount"]?.intValue == 2)
    #expect(events[1].usage?.totalTokens == 9)
    #expect(events[1].warnings == [warning])
    #expect(events[1].responseMetadata == responseMetadata)
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

@Test func aiStreamObjectEmitsAbortTelemetryWhenConsumerCancels() async throws {
    let telemetry = ObjectTelemetryRecorder()
    let callbacks = ObjectCallbackRecorder<ObjectFacadeAnswer>()
    let model = HangingObjectFacadeLanguageModel()
    var firstPart: ObjectStreamPart<ObjectFacadeAnswer>?

    for try await part in AI.streamObject(
        model: model,
        prompt: "Cancel object stream.",
        as: ObjectFacadeAnswer.self,
        schema: objectFacadeAnswerSchema(),
        telemetry: AITelemetryOptions(integrations: [telemetry]),
        callbacks: AIObjectGenerationCallbacks(
            onStart: { event in await callbacks.recordStart(event) },
            onStepStart: { event in await callbacks.recordStepStart(event) },
            onStepFinish: { event in await callbacks.recordStepFinish(event) },
            onFinish: { event in await callbacks.recordFinish(event) },
            onError: { event in await callbacks.recordError(event) }
        )
    ) {
        firstPart = part
        break
    }

    try await Task.sleep(nanoseconds: 20_000_000)
    let telemetryEvents = await telemetry.events()
    let callbackEvents = await callbacks.events()

    if case let .textDelta(delta) = firstPart {
        #expect(delta == #"{"value":"first""#)
    } else {
        Issue.record("Expected the first streamed object part to be a text delta.")
    }
    #expect(telemetryEvents.map(\.kind) == [.start, .abort])
    #expect(telemetryEvents.allSatisfy { $0.operationID == "ai.streamObject" })
    #expect(telemetryEvents[1].errorDescription?.contains("cancelled") == true)
    #expect(callbackEvents.names == ["start", "step-start"])
    #expect(callbackEvents.finish == nil)
    #expect(callbackEvents.error == nil)
}

@Test func aiStreamObjectRetriesRetryableStartErrors() async throws {
    let recorder = ObjectTelemetryRecorder()
    let model = ObjectFacadeFlakyStreamingLanguageModel(outcomes: [
        .failure(AIError.httpStatus(provider: "mock", statusCode: 503, body: "try again")),
        .parts([
            .textDelta(#"{"value":"retried","count":5}"#),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 7))
        ])
    ])

    var object: ObjectGenerationResult<ObjectFacadeAnswer>?
    for try await part in AI.streamObject(
        model: model,
        prompt: "Retry JSON.",
        as: ObjectFacadeAnswer.self,
        schema: objectFacadeAnswerSchema(),
        retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 0),
        telemetry: AITelemetryOptions(integrations: [recorder])
    ) {
        if case let .object(result) = part {
            object = result
        }
    }
    let events = await recorder.events()

    #expect(object?.object == ObjectFacadeAnswer(value: "retried", count: 5))
    #expect(model.streamRequests.count == 2)
    #expect(events.map(\.kind) == [.start, .retry, .end])
    #expect(events[1].operationID == "ai.streamObject")
    #expect(events[1].attempt == 1)
    #expect(events[1].errorDescription?.contains("HTTP 503") == true)
    #expect(events[2].output?["rawObject"]?["value"]?.stringValue == "retried")
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

@Test func aiStreamObjectEmitsTypedPartialObjectsWhenDecodable() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta(#"{"value":"typed"#),
            .textDelta(#"","count":7}"#),
            .finish(reason: "stop", usage: nil)
        ]
    )

    var rawPartials: [JSONValue] = []
    var typedPartials: [ObjectFacadePartialAnswer] = []
    var object: ObjectGenerationResult<ObjectFacadePartialAnswer>?
    for try await part in AI.streamObject(
        model: model,
        prompt: "Stream typed partial JSON.",
        as: ObjectFacadePartialAnswer.self
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
        .object(["value": .string("typed")]),
        .object(["value": .string("typed"), "count": .number(7)])
    ])
    #expect(typedPartials == [
        ObjectFacadePartialAnswer(value: "typed", count: nil),
        ObjectFacadePartialAnswer(value: "typed", count: 7)
    ])
    #expect(object?.object == ObjectFacadePartialAnswer(value: "typed", count: 7))
}

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
        .array([.object(["value": .string("one"), "count": .number(1)])]),
        .array([
            .object(["value": .string("one"), "count": .number(1)]),
            .object(["value": .string("two"), "count": .number(2)])
        ])
    ])
    #expect(typedPartials == [
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

private func arrayOutputSchemaForTest(elementSchema: JSONValue) -> JSONValue {
    let itemSchema: JSONValue
    if var object = elementSchema.objectValue {
        object.removeValue(forKey: "$schema")
        itemSchema = .object(object)
    } else {
        itemSchema = elementSchema
    }
    return .object([
        "$schema": .string("http://json-schema.org/draft-07/schema#"),
        "type": .string("object"),
        "properties": .object([
            "elements": .object([
                "type": .string("array"),
                "items": itemSchema
            ])
        ]),
        "required": .array([.string("elements")]),
        "additionalProperties": .bool(false)
    ])
}

private func enumOutputSchemaForTest(values: [String]) -> JSONValue {
    .object([
        "$schema": .string("http://json-schema.org/draft-07/schema#"),
        "type": .string("object"),
        "properties": .object([
            "result": .object([
                "type": .string("string"),
                "enum": .array(values.map(JSONValue.string))
            ])
        ]),
        "required": .array([.string("result")]),
        "additionalProperties": .bool(false)
    ])
}

private struct ObjectFacadeAnswer: Codable, Equatable, Sendable {
    var value: String
    var count: Int
}

private struct ObjectFacadePartialAnswer: Codable, Equatable, Sendable {
    var value: String?
    var count: Int?
}

private actor ObjectTelemetryRecorder: AITelemetryIntegration {
    private var recordedEvents: [AITelemetryEvent] = []

    func record(_ event: AITelemetryEvent) {
        recordedEvents.append(event)
    }

    func events() -> [AITelemetryEvent] {
        recordedEvents
    }
}

private struct ObjectCallbackEvents<Output: Sendable>: Sendable {
    var names: [String]
    var callIDs: [String]
    var start: AIObjectGenerationStartEvent?
    var stepStart: AIObjectGenerationStepStartEvent?
    var stepFinish: AIObjectGenerationStepFinishEvent?
    var finish: AIObjectGenerationFinishEvent<Output>?
    var error: AIObjectGenerationErrorEvent?
}

private actor ObjectCallbackRecorder<Output: Sendable> {
    private var names: [String] = []
    private var callIDs: [String] = []
    private var start: AIObjectGenerationStartEvent?
    private var stepStart: AIObjectGenerationStepStartEvent?
    private var stepFinish: AIObjectGenerationStepFinishEvent?
    private var finish: AIObjectGenerationFinishEvent<Output>?
    private var error: AIObjectGenerationErrorEvent?

    func recordStart(_ event: AIObjectGenerationStartEvent) {
        names.append("start")
        callIDs.append(event.callID)
        start = event
    }

    func recordStepStart(_ event: AIObjectGenerationStepStartEvent) {
        names.append("step-start")
        callIDs.append(event.callID)
        stepStart = event
    }

    func recordStepFinish(_ event: AIObjectGenerationStepFinishEvent) {
        names.append("step-finish")
        callIDs.append(event.callID)
        stepFinish = event
    }

    func recordFinish(_ event: AIObjectGenerationFinishEvent<Output>) {
        names.append("finish")
        callIDs.append(event.callID)
        finish = event
    }

    func recordError(_ event: AIObjectGenerationErrorEvent) {
        names.append("error")
        callIDs.append(event.callID)
        error = event
    }

    func events() -> ObjectCallbackEvents<Output> {
        ObjectCallbackEvents(
            names: names,
            callIDs: callIDs,
            start: start,
            stepStart: stepStart,
            stepFinish: stepFinish,
            finish: finish,
            error: error
        )
    }
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

private enum ObjectStreamingOutcome {
    case failure(Error)
    case parts([LanguageStreamPart])
}

private final class ObjectFacadeFlakyStreamingLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "flaky-object-language"
    var requests: [LanguageModelRequest] = []
    var streamRequests: [LanguageModelRequest] = []
    private var outcomes: [ObjectStreamingOutcome]

    init(outcomes: [ObjectStreamingOutcome]) {
        self.outcomes = outcomes
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        requests.append(request)
        return TextGenerationResult(text: "", rawValue: .object([:]))
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamRequests.append(request)
        let outcome = outcomes.count > 1 ? outcomes.removeFirst() : outcomes[0]
        return AsyncThrowingStream { continuation in
            switch outcome {
            case let .failure(error):
                continuation.finish(throwing: error)
            case let .parts(parts):
                for part in parts {
                    continuation.yield(part)
                }
                continuation.finish()
            }
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

private final class HangingObjectFacadeLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "hanging-object-language"
    var requests: [LanguageModelRequest] = []
    var streamRequests: [LanguageModelRequest] = []

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        requests.append(request)
        return TextGenerationResult(text: "", rawValue: .object([:]))
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamRequests.append(request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.textDelta(#"{"value":"first""#))
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    continuation.yield(.textDelta(#","count":1}"#))
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
