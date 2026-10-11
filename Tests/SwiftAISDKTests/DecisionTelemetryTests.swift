import Foundation
import Testing
@testable import SwiftAISDK

@Suite("DecisionTelemetryTests", .serialized)
struct DecisionTelemetryTests {
    @Test func lifecyclePreservesStructuredInputsAndNormalizedModelEvidence() async throws {
        let recorder = TelemetryRecorder()
        let callbacks = DecisionCallbackRecorder()
        let model = DecisionTestModel(result: .init(answers: decisionTestAnswers, usage: .init(inputTokens: 0, outputTokens: 4), response: .init(id: "response", modelID: "resolved")))
        let state = AIDecisionState.object(["events": [1, .null], "text": "refund"])
        let questions: [String: AIDecisionQuestion] = [
            "choice": .choice(instructions: ["task": ["Pick"]], criteria: ["a": .null, "b": ["meaning": "Other"]]),
            "score": .score(instructions: ["Rate"], criteria: ["Poor", "Fair", .null]),
            "flag": .boolean(instructions: ["task": "True?"], criteria: ["true": "yes"])
        ]
        let context: [String: JSONValue] = ["requestId": "request", "secret": "hidden"]
        _ = try await AI.experimentalDecide(
            model: model, state: state, questions: questions,
            headers: ["x-test": "yes"], providerOptions: ["test": ["effort": "high"]],
            telemetry: .init(functionID: "test.decide", includeRuntimeContext: ["requestId": true], integrations: [recorder]),
            runtimeContext: context,
            onStart: { await callbacks.recordStart($0) },
            onEnd: { await callbacks.recordEnd($0) }
        )
        let events = await recorder.events()
        #expect(events.map(\.kind) == [.start, .modelCallStart, .modelCallEnd, .end])
        #expect(events.map(\.operationID) == ["ai.decide", "ai.decide.doDecide", "ai.decide.doDecide", "ai.decide"])
        #expect(Set(events.map(\.callID)).count == 1)
        #expect(events[0].input?["state"] == ["events": [1, .null], "text": "refund"])
        #expect(events[1].input?["state"] == [["type": "json", "value": ["events": [1, .null], "text": "refund"]]])
        #expect(events[2].input?["state"] == events[1].input?["state"])
        #expect(events.allSatisfy { $0.input?["questions"]?["choice"]?["instructions"] == ["task": ["Pick"]] })
        #expect(events[0].runtimeContext == ["requestId": "request"])
        #expect(events[1].runtimeContext.isEmpty)
        #expect(events[2].runtimeContext.isEmpty)
        #expect(events[3].runtimeContext == ["requestId": "request"])
        #expect(events[3].usage == .init(inputTokens: 0, outputTokens: 4, totalTokens: 4))
        #expect(events[3].output?["usage"]?["totalTokens"] == 4)
        #expect(events[3].responseMetadata.modelID == "resolved")
        let start = try #require(await callbacks.startEvents().first)
        let end = try #require(await callbacks.endEvents().first)
        #expect(start.state == state)
        #expect(end.state == state)
        #expect(start.runtimeContext == context)
        #expect(end.runtimeContext == context)
        #expect(start.headers == ["x-test": "yes"])
        #expect(end.answers == decisionTestAnswers)
        #expect(start.questions == questions)
        #expect(end.questions == questions)
    }

    @Test func privacySettingsFilterRecordedPayloadsWithoutChangingCallbacks() async throws {
        let recorder = TelemetryRecorder()
        let callbacks = DecisionCallbackRecorder()
        _ = try await AI.experimentalDecide(model: DecisionTestModel(), state: "secret", questions: decisionTestQuestions, telemetry: .init(includesInput: false, includesOutput: false, integrations: [recorder]), onStart: { await callbacks.recordStart($0) }, onEnd: { await callbacks.recordEnd($0) })
        let events = await recorder.events()
        #expect(events.count == 4)
        #expect(events.allSatisfy { $0.input == nil && $0.output == nil })
        #expect(await callbacks.startEvents().first?.state == .text("secret"))
        #expect(await callbacks.endEvents().first?.answers == decisionTestAnswers)
    }

    @Test func errorsAndRefusalsEmitExactlyOneTerminalError() async {
        for result in [AIDecisionModelV4Result(answers: [:]), .init(answers: decisionTestQuestions.mapValues { _ in .refusal })] {
            let recorder = TelemetryRecorder()
            let callbacks = DecisionCallbackRecorder()
            let model = DecisionTestModel(result: result)
            await #expect(throws: (any Error).self) {
                try await AI.experimentalDecide(model: model, state: "text", questions: decisionTestQuestions, telemetry: .init(integrations: [recorder]), onStart: { await callbacks.recordStart($0) }, onEnd: { await callbacks.recordEnd($0) })
            }
            #expect(await recorder.events().map(\.kind) == [.start, .modelCallStart, .error])
            #expect(await callbacks.startEvents().count == 1)
            #expect(await callbacks.endEvents().isEmpty)
            #expect(model.callCount == 1)
        }
    }

    @Test func retryEmitsOneLogicalModelLifecycle() async throws {
        let recorder = TelemetryRecorder()
        let model = DecisionTestModel(failures: [.apiCall(.init(provider: "test", statusCode: 429, responseHeaders: ["retry-after-ms": "0"], responseBody: "busy"))])
        _ = try await AI.experimentalDecide(model: model, state: "", questions: decisionTestQuestions, maxRetries: 1, telemetry: .init(integrations: [recorder]))
        #expect(model.callCount == 2)
        #expect(await recorder.events().map(\.kind) == [.start, .modelCallStart, .modelCallEnd, .end])
    }

    @Test func callbacksAreObservedWhenTelemetryDisabledAndCallbackFailureIgnored() async throws {
        let recorder = TelemetryRecorder()
        let callbacks = DecisionCallbackRecorder()
        let result = try await AI.experimentalDecide(model: DecisionTestModel(), state: "", questions: decisionTestQuestions, telemetry: .init(isEnabled: false, integrations: [recorder]), onStart: { event in await callbacks.recordStart(event); throw DecisionCallbackFailure() }, onEnd: { event in await callbacks.recordEnd(event); throw DecisionCallbackFailure() })
        #expect(result.answers == decisionTestAnswers)
        #expect(await recorder.events().isEmpty)
        #expect(await callbacks.startEvents().count == 1)
        #expect(await callbacks.endEvents().count == 1)
    }

    @Test func serializedStateAndRefusalPayloadsRoundTrip() throws {
        let state: AIDecisionState = .parts([.text(""), .json(.null), .file(mediaType: "image/png", data: .base64("iVBORw=="), filename: "x.png", providerOptions: ["openai": ["imageDetail": "low"]])])
        #expect(decisionState(from: decisionStateJSON(state)) == state)
        let output = decisionModelTelemetryOutput(.init(answers: ["flag": .refusal]))
        #expect(output["answers"]?["flag"] == ["type": "refusal"])
    }
}

private actor DecisionCallbackRecorder {
    private var starts: [AIDecisionStartEvent] = []
    private var ends: [AIDecisionEndEvent] = []
    func recordStart(_ event: AIDecisionStartEvent) { starts.append(event) }
    func recordEnd(_ event: AIDecisionEndEvent) { ends.append(event) }
    func startEvents() -> [AIDecisionStartEvent] { starts }
    func endEvents() -> [AIDecisionEndEvent] { ends }
}
private struct DecisionCallbackFailure: Error {}
