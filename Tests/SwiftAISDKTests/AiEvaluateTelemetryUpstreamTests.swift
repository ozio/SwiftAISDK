import Foundation
import Testing
@testable import SwiftAISDK

@Suite("Evaluate telemetry upstream parity", .serialized)
struct AiEvaluateTelemetryUpstreamTests {
    @Test func emitsTypedCallbacksAndFilteredTelemetryLifecycle() async throws {
        let telemetry = TelemetryRecorder()
        let callbacks = EvaluationCallbackRecorder()
        let timestamp = Date(timeIntervalSince1970: 1_790_000_000)
        let model = EvaluationTelemetryModel(result: AIEvaluationModelV4Result(
            answers: evaluationTelemetryAnswers(),
            usage: AIEvaluationModelUsage(inputTokens: 30, outputTokens: 4),
            warnings: [],
            providerMetadata: ["mock": ["trace": "trace-1"]],
            response: AIResponseMetadata(
                id: "response-1",
                timestamp: timestamp,
                modelID: "resolved-evaluation-model",
                headers: ["x-request-id": "request-1"],
                body: ["ok": true]
            )
        ))
        let state: JSONValue = ["message": "refund"]
        let runtimeContext: [String: JSONValue] = [
            "requestId": "request-1",
            "secret": "hidden"
        ]

        let result = try await AI.experimentalEvaluate(
            model: model,
            state: state,
            questions: evaluationTelemetryQuestions(),
            headers: ["x-test": "yes"],
            providerOptions: ["mock": ["mode": "strict"]],
            telemetry: Telemetry.Options(
                includesInput: false,
                includesOutput: true,
                functionID: "unit.evaluate",
                includeRuntimeContext: ["requestId": true],
                integrations: [telemetry]
            ),
            runtimeContext: runtimeContext,
            onStart: { event in await callbacks.recordStart(event) },
            onEnd: { event in await callbacks.recordEnd(event) }
        )

        let events = await telemetry.events()
        #expect(events.map(\.kind) == [.start, .modelCallStart, .modelCallEnd, .end])
        #expect(events.map(\.operationID) == [
            "ai.evaluate",
            "ai.evaluate.doEvaluate",
            "ai.evaluate.doEvaluate",
            "ai.evaluate"
        ])
        #expect(Set(events.map(\.callID)).count == 1)
        #expect(events.allSatisfy { !$0.includesInput && $0.includesOutput })
        #expect(events.allSatisfy { $0.input == nil })
        #expect(events[0].output == nil)
        #expect(events[1].output == nil)
        #expect(events[2].output?["answers"]?["refund"]?["probability"] == 0.9)
        #expect(events[3].output?["usage"]?["totalTokens"] == 34)
        #expect(events[0].runtimeContext == ["requestId": "request-1"])
        #expect(events[1].runtimeContext.isEmpty)
        #expect(events[2].runtimeContext.isEmpty)
        #expect(events[3].runtimeContext == ["requestId": "request-1"])
        #expect(events.allSatisfy { $0.functionID == "unit.evaluate" })
        #expect(events[2].usage == TokenUsage(inputTokens: 30, outputTokens: 4, totalTokens: 34))
        #expect(events[3].responseMetadata.modelID == "resolved-evaluation-model")

        let start = try #require(await callbacks.startEvents().first)
        let end = try #require(await callbacks.endEvents().first)
        #expect(start.callID == events[0].callID)
        #expect(end.callID == start.callID)
        #expect(start.runtimeContext == runtimeContext)
        #expect(end.runtimeContext == runtimeContext)
        #expect(start.maxRetries == 2)
        #expect(start.headers == ["x-test": "yes"])
        #expect(start.providerOptions == ["mock": ["mode": "strict"]])
        #expect(end.answers == evaluationTelemetryAnswers())
        #expect(end.usage == AIEvaluationUsage(inputTokens: 30, outputTokens: 4, totalTokens: 34))
        #expect(end.response.modelID == "resolved-evaluation-model")
        #expect(result == AIEvaluationResult(
            answers: evaluationTelemetryAnswers(),
            usage: AIEvaluationUsage(inputTokens: 30, outputTokens: 4, totalTokens: 34),
            warnings: [],
            providerMetadata: ["mock": ["trace": "trace-1"]],
            response: AIEvaluationResponseMetadata(
                id: "response-1",
                timestamp: timestamp,
                modelID: "resolved-evaluation-model",
                headers: ["x-request-id": "request-1"],
                body: ["ok": true]
            )
        ))
    }

    @Test func logicalModelCallTelemetrySpansAllRetriesExactlyOnce() async throws {
        let telemetry = TelemetryRecorder()
        let transient = AIError.apiCall(AIAPICallError(
            provider: "test",
            statusCode: 429,
            responseHeaders: ["retry-after-ms": "0"],
            responseBody: "Rate limited"
        ))
        let model = EvaluationTelemetryModel(
            failuresBeforeSuccess: 1,
            failure: transient,
            result: AIEvaluationModelV4Result(
                answers: evaluationTelemetryAnswers(),
                warnings: []
            )
        )

        _ = try await AI.experimentalEvaluate(
            model: model,
            state: "refund",
            questions: evaluationTelemetryQuestions(),
            maxRetries: 1,
            telemetry: Telemetry.Options(integrations: [telemetry])
        )

        let events = await telemetry.events()
        #expect(model.callCount == 2)
        #expect(events.map(\.kind) == [.start, .modelCallStart, .modelCallEnd, .end])
        #expect(events.filter { $0.kind == .modelCallStart }.count == 1)
        #expect(events.filter { $0.kind == .modelCallEnd }.count == 1)
    }

    @Test func emitsOneTerminalErrorWithoutSuccessEvents() async {
        let telemetry = TelemetryRecorder()
        let callbacks = EvaluationCallbackRecorder()
        let model = EvaluationTelemetryModel(
            failuresBeforeSuccess: 1,
            failure: EvaluationTelemetryFailure(),
            result: AIEvaluationModelV4Result(
                answers: evaluationTelemetryAnswers(),
                warnings: []
            )
        )

        await #expect(throws: EvaluationTelemetryFailure.self) {
            try await AI.experimentalEvaluate(
                model: model,
                state: "refund",
                questions: evaluationTelemetryQuestions(),
                maxRetries: 0,
                telemetry: Telemetry.Options(
                    includesOutput: false,
                    integrations: [telemetry]
                ),
                runtimeContext: ["requestId": "request-1"],
                onStart: { event in await callbacks.recordStart(event) },
                onEnd: { event in await callbacks.recordEnd(event) }
            )
        }

        let events = await telemetry.events()
        #expect(events.map(\.kind) == [.start, .modelCallStart, .error])
        #expect(Set(events.map(\.callID)).count == 1)
        #expect(events.allSatisfy { !$0.includesOutput && $0.output == nil })
        #expect(events.last?.errorDescription?.contains("evaluation failed") == true)
        #expect(await callbacks.startEvents().count == 1)
        #expect(await callbacks.endEvents().isEmpty)
    }
}

private func evaluationTelemetryQuestions() -> [String: AIEvaluationQuestion] {
    ["refund": .boolean(instructions: "Refund?")]
}

private func evaluationTelemetryAnswers() -> [String: AIEvaluationAnswer] {
    ["refund": .boolean(probability: 0.9)]
}

private struct EvaluationTelemetryFailure: Error, CustomStringConvertible {
    var description: String { "evaluation failed" }
}

private final class EvaluationTelemetryModel: AIEvaluationModelV4, @unchecked Sendable {
    let providerID = "mock-provider"
    let modelID = "mock-model-id"
    let supportedQuestionTypes = AIEvaluationQuestionType.allCases

    private let lock = NSLock()
    private var calls = 0
    private var failuresRemaining: Int
    private let failure: (any Error)?
    private let result: AIEvaluationModelV4Result

    var callCount: Int { lock.withLock { calls } }

    init(
        failuresBeforeSuccess: Int = 0,
        failure: (any Error)? = nil,
        result: AIEvaluationModelV4Result
    ) {
        self.failuresRemaining = failuresBeforeSuccess
        self.failure = failure
        self.result = result
    }

    func doEvaluate(_ options: AIEvaluationModelV4CallOptions) async throws -> AIEvaluationModelV4Result {
        let shouldFail = lock.withLock {
            calls += 1
            guard failuresRemaining > 0 else { return false }
            failuresRemaining -= 1
            return true
        }
        if shouldFail, let failure {
            throw failure
        }
        return result
    }
}

private actor EvaluationCallbackRecorder {
    private var starts: [AIEvaluationStartEvent] = []
    private var ends: [AIEvaluationEndEvent] = []

    func recordStart(_ event: AIEvaluationStartEvent) {
        starts.append(event)
    }

    func recordEnd(_ event: AIEvaluationEndEvent) {
        ends.append(event)
    }

    func startEvents() -> [AIEvaluationStartEvent] {
        starts
    }

    func endEvents() -> [AIEvaluationEndEvent] {
        ends
    }
}
