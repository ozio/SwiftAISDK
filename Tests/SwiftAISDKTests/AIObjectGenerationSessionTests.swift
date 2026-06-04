import Foundation
import Testing
@testable import SwiftAISDK

@MainActor
@Test func aiObjectGenerationSessionStreamsPartialAndFinalOutput() async throws {
    let model = ObjectSessionLanguageModel(streamParts: [
        .streamStart(warnings: [AIWarning(type: "unsupported", feature: "seed")]),
        .textDelta(#"{"value":"session","count":3}"#),
        .metadata(["trace": .string("object-session")]),
        .responseMetadata(AIResponseMetadata(id: "response-1", modelID: "model-1")),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 9))
    ])
    let events = ObjectSessionEvents<ObjectSessionAnswer>()
    let session = AIObjectGenerationSession(
        model: model,
        output: Output.object(schema: objectSessionAnswerSchema(), as: ObjectSessionAnswer.self),
        onFinish: { events.finishEvents.append($0) }
    )

    await session.submit("Make an object.", options: AIObjectGenerationSessionRequestOptions(headers: ["x-test": "1"])).value

    #expect(session.status == .ready)
    #expect(session.isLoading == false)
    #expect(session.partialObject?["value"]?.stringValue == "session")
    #expect(session.object == ObjectSessionAnswer(value: "session", count: 3))
    #expect(session.result?.rawOutput["count"]?.intValue == 3)
    #expect(session.text == #"{"value":"session","count":3}"#)
    #expect(session.warnings.first?.feature == "seed")
    #expect(session.metadata["trace"]?.stringValue == "object-session")
    #expect(session.responseMetadata?.id == "response-1")
    #expect(session.finishReason == "stop")
    #expect(session.usage?.totalTokens == 9)
    #expect(events.finishEvents.first?.object == ObjectSessionAnswer(value: "session", count: 3))

    let request = try #require(model.streamRequests.first)
    #expect(request.messages == [.user("Make an object.")])
    #expect(request.headers == ["x-test": "1"])
    #expect(request.abortSignal != nil)
}

@MainActor
@Test func aiObjectGenerationSessionStopKeepsPartialObjectAndSkipsCallbacks() async throws {
    let model = ObjectSessionLanguageModel(
        streamParts: [.textDelta(#"{"value":"partial","count":1}"#)],
        sleepAfterPartsNanoseconds: 5_000_000_000
    )
    let events = ObjectSessionEvents<ObjectSessionAnswer>()
    let session = AIObjectGenerationSession(
        model: model,
        output: Output.object(schema: objectSessionAnswerSchema(), as: ObjectSessionAnswer.self),
        onError: { events.errors.append(String(describing: $0)) },
        onFinish: { events.finishEvents.append($0) }
    )

    let task = session.submit("Make a partial object.")
    await waitUntil { session.partialObject?["value"]?.stringValue == "partial" }

    session.stop()
    await task.value

    #expect(session.status == .ready)
    #expect(session.partialObject?["value"]?.stringValue == "partial")
    #expect(session.object == nil)
    #expect(events.errors.isEmpty)
    #expect(events.finishEvents.isEmpty)
}

@MainActor
@Test func aiObjectGenerationSessionClearStopsAndResetsObjectState() async throws {
    let model = ObjectSessionLanguageModel(streamParts: [
        .textDelta(#"{"value":"clear","count":2}"#),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 4))
    ])
    let session = AIObjectGenerationSession(
        model: model,
        output: Output.object(schema: objectSessionAnswerSchema(), as: ObjectSessionAnswer.self)
    )

    await session.submit("Make an object.").value
    #expect(session.object == ObjectSessionAnswer(value: "clear", count: 2))

    session.clear()

    #expect(session.status == .ready)
    #expect(session.partialObject == nil)
    #expect(session.object == nil)
    #expect(session.result == nil)
    #expect(session.text.isEmpty)
    #expect(session.error == nil)
}

@MainActor
@Test func aiObjectGenerationSessionReportsFinalObjectErrorsThroughFinish() async throws {
    let model = ObjectSessionLanguageModel(streamParts: [
        .textDelta("not json"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 2))
    ])
    let events = ObjectSessionEvents<ObjectSessionAnswer>()
    let session = AIObjectGenerationSession(
        model: model,
        output: Output.object(schema: objectSessionAnswerSchema(), as: ObjectSessionAnswer.self),
        onError: { events.errors.append(String(describing: $0)) },
        onFinish: { events.finishEvents.append($0) }
    )

    await session.submit("Break object.").value

    #expect(session.status == .ready)
    #expect(session.error == nil)
    #expect(events.errors.isEmpty)
    let finish = try #require(events.finishEvents.first)
    #expect(finish.object == nil)
    #expect(finish.result == nil)
    #expect(finish.error is AIObjectGenerationError)
}

private struct ObjectSessionAnswer: Codable, Equatable, Sendable {
    var value: String
    var count: Int
}

private final class ObjectSessionLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "object-session"
    let modelID = "language"
    var generateRequests: [LanguageModelRequest] = []
    var streamRequests: [LanguageModelRequest] = []
    private let streamParts: [LanguageStreamPart]
    private let sleepAfterPartsNanoseconds: UInt64?

    init(
        streamParts: [LanguageStreamPart],
        sleepAfterPartsNanoseconds: UInt64? = nil
    ) {
        self.streamParts = streamParts
        self.sleepAfterPartsNanoseconds = sleepAfterPartsNanoseconds
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        generateRequests.append(request)
        return TextGenerationResult(text: "{}", rawValue: .object([:]))
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamRequests.append(request)
        let parts = streamParts
        let sleep = sleepAfterPartsNanoseconds
        return AsyncThrowingStream { continuation in
            let task = Task {
                for part in parts {
                    try Task.checkCancellation()
                    continuation.yield(part)
                }
                if let sleep {
                    try await Task.sleep(nanoseconds: sleep)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private final class ObjectSessionEvents<Output: Sendable>: @unchecked Sendable {
    var finishEvents: [AIObjectGenerationSessionFinishEvent<Output>] = []
    var errors: [String] = []
}

private func objectSessionAnswerSchema() -> JSONValue {
    [
        "type": "object",
        "properties": [
            "value": ["type": "string"],
            "count": ["type": "integer"]
        ],
        "required": ["value", "count"],
        "additionalProperties": false
    ]
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    _ predicate: @MainActor () -> Bool
) async {
    let start = DispatchTime.now().uptimeNanoseconds
    while !predicate() && DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
        await Task.yield()
    }
}
