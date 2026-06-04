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
