import Foundation
import Testing
@testable import SwiftAISDK

actor StreamStopConditionCapture {
    struct Call: Sendable {
        var number: Int
        var stepCount: Int
        var toolCallIDs: [String]
        var toolResultIDs: [String]
    }

    private var calls: [Call] = []

    func record(number: Int, context: AIStopConditionContext) {
        let lastStep = context.steps.last
        calls.append(Call(
            number: number,
            stepCount: context.steps.count,
            toolCallIDs: lastStep?.toolCalls.map(\.id) ?? [],
            toolResultIDs: lastStep?.toolResults.map(\.toolCallID) ?? []
        ))
    }

    func numbers() -> [Int] {
        calls.map(\.number)
    }

    func stepCounts() -> [Int] {
        calls.map(\.stepCount)
    }

    func toolCallIDs() -> [[String]] {
        calls.map(\.toolCallIDs)
    }

    func toolResultIDs() -> [[String]] {
        calls.map(\.toolResultIDs)
    }
}

enum StreamToolInputCallbackEvent: Equatable, Sendable {
    case start(
        toolCallID: String,
        messages: [AIMessage],
        abortSignalIsNil: Bool
    )
    case delta(
        toolCallID: String,
        inputTextDelta: String,
        messages: [AIMessage],
        abortSignalIsNil: Bool
    )
    case available(
        toolCallID: String,
        input: JSONValue,
        messages: [AIMessage],
        abortSignalIsNil: Bool
    )
}

actor StreamToolInputCallbackRecorder {
    private var recordedEvents: [StreamToolInputCallbackEvent] = []

    func record(_ event: StreamToolInputCallbackEvent) {
        recordedEvents.append(event)
    }

    func events() -> [StreamToolInputCallbackEvent] {
        recordedEvents
    }
}

actor StreamStepContentCapture {
    private var recordedContent: [AIResultContentPart] = []

    func record(_ content: [AIResultContentPart]) {
        recordedContent = content
    }

    func content() -> [AIResultContentPart] {
        recordedContent
    }
}

actor StreamToolExecutionInputListCapture {
    private var recordedValues: [JSONValue] = []

    func record(_ value: JSONValue) {
        recordedValues.append(value)
    }

    func values() -> [JSONValue] {
        recordedValues
    }
}

actor StreamPrepareStepResponseMessagesCapture {
    private var recordedSnapshots: [[AIMessage]] = []

    func record(_ value: [AIMessage]) {
        recordedSnapshots.append(value)
    }

    func snapshots() -> [[AIMessage]] {
        recordedSnapshots
    }
}

final class LanguageModelCallContextProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var activeID: String?
    private var wrapperID: String?
    private var capturedID: String?

    func activate(_ callID: String) {
        lock.lock()
        activeID = callID
        wrapperID = callID
        lock.unlock()
    }

    func deactivate() {
        lock.lock()
        activeID = nil
        lock.unlock()
    }

    func captureActiveCallID() {
        lock.lock()
        capturedID = activeID
        lock.unlock()
    }

    func integrationCallID() -> String? {
        lock.lock()
        let value = wrapperID
        lock.unlock()
        return value
    }

    func capturedCallID() -> String? {
        lock.lock()
        let value = capturedID
        lock.unlock()
        return value
    }
}

struct ContextActivatingLanguageModelTelemetry: Telemetry.Integration {
    var probe: LanguageModelCallContextProbe

    func record(_ event: Telemetry.Event) {}

    func executeLanguageModelCall<Output: Sendable>(_ context: Telemetry.LanguageModelCallContext<Output>) async throws -> Output {
        probe.activate(context.callID)
        defer { probe.deactivate() }
        return try await context.execute()
    }
}

final class ContextCapturingStreamLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "context-capturing-stream"
    private let probe: LanguageModelCallContextProbe
    private let streamParts: [LanguageStreamPart]

    init(probe: LanguageModelCallContextProbe, streamParts: [LanguageStreamPart]) {
        self.probe = probe
        self.streamParts = streamParts
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        TextGenerationResult(text: "", rawValue: .object([:]))
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        probe.captureActiveCallID()
        let parts = streamParts
        return AsyncThrowingStream { continuation in
            for part in parts {
                continuation.yield(part)
            }
            continuation.finish()
        }
    }
}

final class ConditionalRawChunkLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "conditional-raw-chunks"
    var streamRequests: [LanguageModelRequest] = []

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        TextGenerationResult(text: "Hello, world!", rawValue: .string("Hello, world!"))
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamRequests.append(request)
        return AsyncThrowingStream { continuation in
            if request.includeRawChunks {
                continuation.yield(.raw(["type": "raw-data", "content": "should appear"]))
            }
            continuation.yield(.textDelta("Hello, world!"))
            continuation.yield(.finish(reason: "stop", usage: TokenUsage(totalTokens: 13)))
            continuation.finish()
        }
    }
}

struct RawChunkFacadeParts {
    var rawValues: [JSONValue] = []
    var textDeltas: [String] = []
}

func collectRawChunkFacadeParts(
    _ stream: AsyncThrowingStream<LanguageStreamPart, Error>
) async throws -> RawChunkFacadeParts {
    var result = RawChunkFacadeParts()
    for try await part in stream {
        switch part {
        case let .raw(raw):
            result.rawValues.append(raw)
        case let .textDelta(delta):
            result.textDeltas.append(delta)
        default:
            break
        }
    }
    return result
}

func deferredProviderToolRequest() -> LanguageModelRequest {
    LanguageModelRequest(
        messages: [.user("test-input")],
        tools: [
            "deferred_tool": [
                "type": "provider",
                "id": "test.deferred_tool",
                "inputSchema": [
                    "type": "object",
                    "properties": ["value": ["type": "string"]],
                    "required": ["value"]
                ],
                "outputSchema": [
                    "type": "object",
                    "properties": ["value": ["type": "string"]],
                    "required": ["value"]
                ],
                "args": .object([:]),
                "supportsDeferredResults": true
            ]
        ]
    )
}
