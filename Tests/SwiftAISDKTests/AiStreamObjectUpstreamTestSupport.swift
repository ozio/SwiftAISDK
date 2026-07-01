import Foundation
import Testing
@testable import SwiftAISDK

struct StreamObjectContent: Codable, Equatable, Sendable {
    var content: String
}

func streamObjectContentSchema() -> JSONValue {
    [
        "type": "object",
        "properties": [
            "content": ["type": "string"]
        ],
        "required": ["content"],
        "additionalProperties": false
    ]
}

func collectStreamEnumUpstreamPartials(
    chunks: [String],
    values: [String]
) async throws -> (rawPartials: [String], typedPartials: [String], object: String?, error: AIObjectGenerationError?) {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [.textStart(id: "1")]
            + chunks.map { LanguageStreamPart.textDeltaPart(id: "1", delta: $0) }
            + [
                .textEnd(id: "1"),
                .finish(reason: "stop", usage: TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
            ]
    )

    var rawPartials: [String] = []
    var typedPartials: [String] = []
    var object: String?
    do {
        for try await part in AI.streamEnum(
            model: model,
            prompt: "prompt",
            values: values
        ) {
            switch part {
            case let .partialObject(partial):
                if let value = partial.stringValue {
                    rawPartials.append(value)
                }
            case let .partial(partial):
                typedPartials.append(partial)
            case let .object(result):
                object = result.object
            default:
                break
            }
        }
        return (rawPartials, typedPartials, object, nil)
    } catch let error as AIObjectGenerationError {
        return (rawPartials, typedPartials, object, error)
    }
}

func streamObjectContentLanguageParts(
    metadata: [LanguageStreamPart] = [],
    finish: LanguageStreamPart = .finish(reason: "stop", usage: TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
) -> [LanguageStreamPart] {
    [
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "{ "),
        .textDeltaPart(id: "1", delta: #""content": "#),
        .textDeltaPart(id: "1", delta: #""Hello, "#),
        .textDeltaPart(id: "1", delta: "world"),
        .textDeltaPart(id: "1", delta: #"!""#),
        .textDeltaPart(id: "1", delta: " }"),
        .textEnd(id: "1")
    ] + metadata + [finish]
}

func streamObjectContentTextDeltas() -> [String] {
    [
        "{ ",
        #""content": "Hello, "#,
        "world",
        #"!""#,
        " }"
    ]
}

func streamObjectContentPartials() -> [JSONValue] {
    [
        [:],
        ["content": "Hello, "],
        ["content": "Hello, world"],
        ["content": "Hello, world!"]
    ]
}

struct StreamObjectStartFailure: Error {}

actor StreamObjectWarningLogRecorder: AIWarningLogger {
    private var recordedEvents: [AIWarningLogEvent] = []

    func logWarnings(_ event: AIWarningLogEvent) {
        recordedEvents.append(event)
    }

    func events() -> [AIWarningLogEvent] {
        recordedEvents
    }
}

final class StreamObjectCallbackUpstreamRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedNames: [String] = []
    private var recordedCallIDs: [String] = []
    private var start: AIObjectGenerationStartEvent?
    private var stepStart: AIObjectGenerationStepStartEvent?
    private var stepFinish: AIObjectGenerationStepFinishEvent?
    private var finish: AIObjectGenerationFinishEvent<StreamObjectContent>?

    func record(_ name: String) {
        lock.lock()
        recordedNames.append(name)
        lock.unlock()
    }

    func recordStart(_ event: AIObjectGenerationStartEvent) {
        lock.lock()
        recordedNames.append("onStart")
        recordedCallIDs.append(event.callID)
        start = event
        lock.unlock()
    }

    func recordStepStart(_ event: AIObjectGenerationStepStartEvent) {
        lock.lock()
        recordedNames.append("onStepStart")
        recordedCallIDs.append(event.callID)
        stepStart = event
        lock.unlock()
    }

    func recordStepFinish(_ event: AIObjectGenerationStepFinishEvent) {
        lock.lock()
        recordedNames.append("onStepFinish")
        recordedCallIDs.append(event.callID)
        stepFinish = event
        lock.unlock()
    }

    func recordFinish(_ event: AIObjectGenerationFinishEvent<StreamObjectContent>) {
        lock.lock()
        recordedNames.append("onFinish")
        recordedCallIDs.append(event.callID)
        finish = event
        lock.unlock()
    }

    func names() -> [String] {
        lock.lock()
        let output = recordedNames
        lock.unlock()
        return output
    }

    func callIDs() -> [String] {
        lock.lock()
        let output = recordedCallIDs
        lock.unlock()
        return output
    }

    func startEvent() -> AIObjectGenerationStartEvent? {
        lock.lock()
        let output = start
        lock.unlock()
        return output
    }

    func stepStartEvent() -> AIObjectGenerationStepStartEvent? {
        lock.lock()
        let output = stepStart
        lock.unlock()
        return output
    }

    func stepFinishEvent() -> AIObjectGenerationStepFinishEvent? {
        lock.lock()
        let output = stepFinish
        lock.unlock()
        return output
    }

    func finishEvent() -> AIObjectGenerationFinishEvent<StreamObjectContent>? {
        lock.lock()
        let output = finish
        lock.unlock()
        return output
    }
}

final class StreamObjectCallbackLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID: String
    let modelID: String
    private let recorder: StreamObjectCallbackUpstreamRecorder?
    private let parts: [LanguageStreamPart]

    init(
        providerID: String = "mock",
        modelID: String = "mock-language",
        recorder: StreamObjectCallbackUpstreamRecorder? = nil,
        parts: [LanguageStreamPart] = [
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: #"{ "content": "Hello, world!" }"#),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
        ]
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.recorder = recorder
        self.parts = parts
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        TextGenerationResult(text: "", rawValue: .object([:]))
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        recorder?.record("doStream")
        return AsyncThrowingStream { continuation in
            for part in parts {
                continuation.yield(part)
            }
            continuation.finish()
        }
    }
}
