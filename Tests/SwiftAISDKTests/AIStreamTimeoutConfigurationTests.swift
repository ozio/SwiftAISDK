import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiStreamFirstChunkTimeoutIgnoresLifecycleMetadataRawAndEmptyDeltas() async throws {
    let model = TimeoutScriptLanguageModel(scripts: [[
        .yield(.streamStart(warnings: [])),
        .yield(.responseMetadata(AIResponseMetadata(id: "response-1"))),
        .yield(.textDelta("")),
        .yield(.raw(.string(": ping"))),
        .sleep(200_000_000),
    ]])

    do {
        for try await _ in AI.streamText(
            model: model,
            prompt: "test-input",
            timeout: AIStreamTimeoutConfiguration(firstChunkNanoseconds: 30_000_000),
            retryPolicy: .none
        ) {}
        Issue.record("Expected a first-chunk timeout.")
    } catch let error as AIStreamTimeoutError {
        #expect(error == AIStreamTimeoutError(
            phase: .firstChunk,
            durationNanoseconds: 30_000_000
        ))
    }

    #expect(model.streamRequestCount == 1)
}

@Test func aiStreamChunkTimeoutIgnoresNonOutputKeepAliveParts() async throws {
    let model = TimeoutScriptLanguageModel(scripts: [[
        .yield(.textDelta("Hello")),
        .sleep(10_000_000),
        .yield(.responseMetadata(AIResponseMetadata(id: "response-1"))),
        .sleep(10_000_000),
        .yield(.raw(.string(": ping"))),
        .sleep(200_000_000),
    ]])

    do {
        for try await _ in AI.streamText(
            model: model,
            prompt: "test-input",
            timeout: AIStreamTimeoutConfiguration(chunkNanoseconds: 40_000_000),
            retryPolicy: .none
        ) {}
        Issue.record("Expected an inter-chunk timeout.")
    } catch let error as AIStreamTimeoutError {
        #expect(error == AIStreamTimeoutError(
            phase: .chunk,
            durationNanoseconds: 40_000_000
        ))
    }
}

@Test func aiStreamSemanticTimeoutAbortsTheProviderSignalWithTimeoutReason() async throws {
    let model = TimeoutScriptLanguageModel(scripts: [[
        .yield(.responseMetadata(AIResponseMetadata(id: "response-1"))),
        .sleep(200_000_000),
    ]])

    do {
        for try await _ in AI.streamText(
            model: model,
            prompt: "test-input",
            timeout: AIStreamTimeoutConfiguration(firstChunkNanoseconds: 30_000_000),
            retryPolicy: .none
        ) {}
        Issue.record("Expected a first-chunk timeout.")
    } catch is AIStreamTimeoutError {
        // Expected.
    }

    let signal = try #require(model.lastStreamAbortSignal)
    #expect(signal.isAborted)
    #expect(signal.reasonName == "TimeoutError")
    #expect(signal.reason?.contains("First chunk timeout") == true)
}

@Test(arguments: [
    AIStreamTimeoutConfiguration(totalNanoseconds: 30_000_000),
    AIStreamTimeoutConfiguration(stepNanoseconds: 30_000_000),
])
func aiStreamTotalAndStepTimeoutsIncludeRetryBackoff(
    timeout: AIStreamTimeoutConfiguration
) async throws {
    let model = TimeoutScriptLanguageModel(scripts: [
        [.failRetryable],
        [.yield(.textDelta("too late")), .finish],
    ])

    do {
        for try await _ in AI.streamText(
            model: model,
            prompt: "test-input",
            timeout: timeout,
            retryPolicy: AIRetryPolicy(
                maxRetries: 1,
                initialDelayNanoseconds: 200_000_000
            )
        ) {}
        Issue.record("Expected the retry backoff budget to time out.")
    } catch let error as AIError {
        #expect(error == .timeout(durationNanoseconds: 30_000_000))
    }

    #expect(model.streamRequestCount == 1)
    let signal = try #require(model.lastStreamAbortSignal)
    #expect(signal.isAborted)
    #expect(signal.reasonName == "TimeoutError")
}

@Test func aiStreamChunkTimeoutResetsForEverySemanticOutputPart() async throws {
    let model = TimeoutScriptLanguageModel(scripts: [[
        .yield(.textDelta("Hello")),
        .sleep(20_000_000),
        .yield(.reasoningDelta("Thinking")),
        .sleep(20_000_000),
        .yield(.toolInputDelta(id: "call-1", delta: #"{"value":"#, providerMetadata: [:])),
        .sleep(20_000_000),
        .yield(.toolCall(AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"ok"}"#))),
        .yield(.finish(reason: "tool-calls", usage: nil)),
        .finish,
    ]])

    var parts: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "test-input",
        timeout: AIStreamTimeoutConfiguration(
            firstChunkNanoseconds: 40_000_000,
            chunkNanoseconds: 40_000_000
        ),
        retryPolicy: .none
    ) {
        parts.append(part)
    }

    #expect(parts.contains(.toolCall(AIToolCall(
        id: "call-1",
        name: "tool1",
        arguments: #"{"value":"ok"}"#
    ))))
}

@Test func aiStreamFirstChunkTimeoutRearmsForEveryModelCallStep() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: "{}")
    let model = TimeoutScriptLanguageModel(scripts: [
        [
            .yield(.toolCall(toolCall)),
            .yield(.finish(reason: "tool-calls", usage: nil)),
            .finish,
        ],
        [
            .yield(.responseMetadata(AIResponseMetadata(id: "response-2"))),
            .sleep(200_000_000),
        ],
    ])
    let tool = AITool(
        name: "tool1",
        parameters: ["type": "object", "properties": [:]]
    ) { _ in
        .string("tool result")
    }

    do {
        for try await _ in AI.streamText(
            model: model,
            request: LanguageModelRequest(messages: [.user("test-input")]),
            executableTools: [tool],
            maxSteps: 2,
            timeout: AIStreamTimeoutConfiguration(firstChunkNanoseconds: 30_000_000),
            retryPolicy: .none
        ) {}
        Issue.record("Expected the second model-call step to time out.")
    } catch let error as AIStreamTimeoutError {
        #expect(error.phase == .firstChunk)
    }

    #expect(model.streamRequestCount == 2)
}

@Test func aiStreamStepTimeoutAppliesToOneModelCall() async throws {
    let model = TimeoutScriptLanguageModel(scripts: [[
        .yield(.responseMetadata(AIResponseMetadata(id: "response-1"))),
        .sleep(200_000_000),
    ]])

    do {
        for try await _ in AI.streamText(
            model: model,
            prompt: "test-input",
            timeout: AIStreamTimeoutConfiguration(stepNanoseconds: 30_000_000),
            retryPolicy: .none
        ) {}
        Issue.record("Expected a model-step timeout.")
    } catch let error as AIError {
        #expect(error == .timeout(durationNanoseconds: 30_000_000))
    }

    #expect(model.streamRequestCount == 1)
}

@Test func aiStreamStepTimeoutRearmsForEveryModelCallStep() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: "{}")
    let model = TimeoutScriptLanguageModel(scripts: [
        [
            .yield(.toolCall(toolCall)),
            .yield(.finish(reason: "tool-calls", usage: nil)),
            .finish,
        ],
        [
            .yield(.responseMetadata(AIResponseMetadata(id: "response-2"))),
            .sleep(200_000_000),
        ],
    ])
    let tool = AITool(
        name: "tool1",
        parameters: ["type": "object", "properties": [:]]
    ) { _ in
        .string("tool result")
    }

    do {
        for try await _ in AI.streamText(
            model: model,
            request: LanguageModelRequest(messages: [.user("test-input")]),
            executableTools: [tool],
            maxSteps: 2,
            timeout: AIStreamTimeoutConfiguration(stepNanoseconds: 30_000_000),
            retryPolicy: .none
        ) {}
        Issue.record("Expected the second model-call step to time out.")
    } catch let error as AIError {
        #expect(error == .timeout(durationNanoseconds: 30_000_000))
    }

    #expect(model.streamRequestCount == 2)
}

@Test func aiStreamStepTimeoutRemainsActiveThroughClientToolExecution() async throws {
    let model = TimeoutScriptLanguageModel(scripts: [[
        .yield(.toolCall(AIToolCall(id: "call-1", name: "tool1", arguments: "{}"))),
        .yield(.finish(reason: "tool-calls", usage: nil)),
        .finish,
    ]])
    let toolSignal = TimeoutAbortSignalCapture()
    let tool = AITool(
        name: "tool1",
        parameters: ["type": "object", "properties": [:]],
        executeWithContext: { _, context in
            toolSignal.record(context.abortSignal)
            _ = await context.abortSignal?.waitUntilAborted()
            return .string("late result")
        },
        execute: { _ in
            Issue.record("Expected contextual tool execution.")
            return .string("unused")
        }
    )

    do {
        for try await _ in AI.streamText(
            model: model,
            request: LanguageModelRequest(messages: [.user("test-input")]),
            executableTools: [tool],
            maxSteps: 2,
            timeout: AIStreamTimeoutConfiguration(stepNanoseconds: 30_000_000),
            retryPolicy: .none
        ) {}
        Issue.record("Expected tool execution to exceed the step timeout.")
    } catch let error as AIError {
        #expect(error == .timeout(durationNanoseconds: 30_000_000))
    }

    let signal = try #require(toolSignal.signal)
    #expect(signal.isAborted)
    #expect(signal.reasonName == "TimeoutError")
    #expect(signal.reason?.contains("Step timeout") == true)
}

@Test func aiTypedOutputStreamAcceptsStructuredTimeoutAndAbortsProvider() async throws {
    let model = TimeoutScriptLanguageModel(scripts: [[
        .yield(.responseMetadata(AIResponseMetadata(id: "response-1"))),
        .sleep(200_000_000),
    ]])

    do {
        for try await _ in AI.streamText(
            model: model,
            prompt: "test-input",
            output: Output.text(),
            timeout: AIStreamTimeoutConfiguration(firstChunkNanoseconds: 30_000_000),
            retryPolicy: .none
        ) {}
        Issue.record("Expected the typed output stream to time out.")
    } catch let error as AIStreamTimeoutError {
        #expect(error.phase == .firstChunk)
    }

    let signal = try #require(model.lastStreamAbortSignal)
    #expect(signal.isAborted)
    #expect(signal.reasonName == "TimeoutError")
}

@Test func aiStreamTimeoutConfigurationRejectsZeroBeforeCallingModel() async throws {
    let model = TimeoutScriptLanguageModel(scripts: [[]])

    do {
        for try await _ in AI.streamText(
            model: model,
            prompt: "test-input",
            timeout: AIStreamTimeoutConfiguration(firstChunkNanoseconds: 0),
            retryPolicy: .none
        ) {}
        Issue.record("Expected invalid timeout configuration.")
    } catch let error as AIError {
        #expect(error == .invalidArgument(
            argument: "timeout.firstChunkNanoseconds",
            message: "timeout.firstChunkNanoseconds must be greater than zero."
        ))
    }

    #expect(model.streamRequestCount == 0)
}

private enum TimeoutStreamAction: Sendable {
    case yield(LanguageStreamPart)
    case sleep(UInt64)
    case failRetryable
    case finish
}

private final class TimeoutScriptLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "timeout-test"
    let modelID = "timeout-script"

    private let lock = NSLock()
    private var scripts: [[TimeoutStreamAction]]
    private var streamRequests = 0
    private var streamAbortSignals: [AIAbortSignal?] = []

    init(scripts: [[TimeoutStreamAction]]) {
        self.scripts = scripts
    }

    var streamRequestCount: Int {
        lock.withLock { streamRequests }
    }

    var lastStreamAbortSignal: AIAbortSignal? {
        lock.withLock { streamAbortSignals.last.flatMap { $0 } }
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        TextGenerationResult(text: "", rawValue: .object([:]))
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        let actions = lock.withLock { () -> [TimeoutStreamAction] in
            streamRequests += 1
            streamAbortSignals.append(request.abortSignal)
            return scripts.isEmpty ? [] : scripts.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for action in actions {
                        try Task.checkCancellation()
                        switch action {
                        case let .yield(part):
                            continuation.yield(part)
                        case let .sleep(duration):
                            try await Task.sleep(nanoseconds: duration)
                        case .failRetryable:
                            throw AIError.apiCall(AIAPICallError(
                                provider: providerID,
                                url: "https://example.invalid/stream",
                                statusCode: 503,
                                responseBody: "retry",
                                isRetryable: true
                            ))
                        case .finish:
                            continuation.finish()
                            return
                        }
                    }
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

private final class TimeoutAbortSignalCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedSignal: AIAbortSignal?

    var signal: AIAbortSignal? {
        lock.withLock { capturedSignal }
    }

    func record(_ signal: AIAbortSignal?) {
        lock.withLock {
            capturedSignal = signal
        }
    }
}
