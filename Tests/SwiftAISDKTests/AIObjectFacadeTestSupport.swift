import Foundation
import Testing
@testable import SwiftAISDK

func objectFacadeAnswerSchema(
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
func arrayOutputSchemaForTest(elementSchema: JSONValue) -> JSONValue {
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
func enumOutputSchemaForTest(values: [String]) -> JSONValue {
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
struct ObjectFacadeAnswer: Codable, Equatable, Sendable {
    var value: String
    var count: Int
}
struct ObjectFacadePartialAnswer: Codable, Equatable, Sendable {
    var value: String?
    var count: Int?
}
actor ObjectTelemetryRecorder: Telemetry.Integration {
    private var recordedEvents: [Telemetry.Event] = []

    func record(_ event: Telemetry.Event) {
        recordedEvents.append(event)
    }

    func events() -> [Telemetry.Event] {
        recordedEvents
    }
}
struct ObjectCallbackEvents<Output: Sendable>: Sendable {
    var names: [String]
    var callIDs: [String]
    var start: AIObjectGenerationStartEvent?
    var stepStart: AIObjectGenerationStepStartEvent?
    var stepFinish: AIObjectGenerationStepFinishEvent?
    var finish: AIObjectGenerationFinishEvent<Output>?
    var error: AIObjectGenerationErrorEvent?
}
actor ObjectCallbackRecorder<Output: Sendable> {
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
final class ObjectFacadeMockLanguageModel: LanguageModel, @unchecked Sendable {
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
enum ObjectStreamingOutcome {
    case failure(Error)
    case parts([LanguageStreamPart])
}
final class ObjectFacadeFlakyStreamingLanguageModel: LanguageModel, @unchecked Sendable {
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
final class SlowObjectFacadeLanguageModel: LanguageModel, @unchecked Sendable {
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
final class HangingObjectFacadeLanguageModel: LanguageModel, @unchecked Sendable {
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
