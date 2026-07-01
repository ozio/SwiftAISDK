import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiStopConditionIsStepCountReturnsTrueWhenCountMatchesExactly() async throws {
    let stopCondition = AIStopCondition.isStepCount(2)

    #expect(try await stopCondition.evaluate(AIStopConditionContext(steps: [
        createStopConditionStep(index: 0),
        createStopConditionStep(index: 1)
    ])))
}

@Test func aiStopConditionIsStepCountReturnsFalseWhenCountDoesNotMatchExactly() async throws {
    let stopCondition = AIStopCondition.isStepCount(2)

    #expect(try await !stopCondition.evaluate(AIStopConditionContext(steps: [
        createStopConditionStep(index: 0)
    ])))
    #expect(try await !stopCondition.evaluate(AIStopConditionContext(steps: [
        createStopConditionStep(index: 0),
        createStopConditionStep(index: 1),
        createStopConditionStep(index: 2)
    ])))
}

@Test func aiStopConditionIsLoopFinishedAlwaysReturnsFalse() async throws {
    let stopCondition = AIStopCondition.isLoopFinished()

    #expect(try await !stopCondition.evaluate(AIStopConditionContext(steps: [])))
    #expect(try await !stopCondition.evaluate(AIStopConditionContext(steps: [
        createStopConditionStep(index: 0)
    ])))
}

@Test func aiStopConditionHasToolCallReturnsTrueWhenLastStepContainsSpecifiedToolCall() async throws {
    let stopCondition = AIStopCondition.hasToolCall("finalAnswer")

    #expect(try await stopCondition.evaluate(AIStopConditionContext(steps: [
        createStopConditionStep(index: 0),
        createStopConditionStep(index: 1, toolNames: ["finalAnswer"])
    ])))
}

@Test func aiStopConditionHasToolCallReturnsFalseWhenSpecifiedToolOnlyAppearsEarlier() async throws {
    let stopCondition = AIStopCondition.hasToolCall("finalAnswer")

    #expect(try await !stopCondition.evaluate(AIStopConditionContext(steps: [
        createStopConditionStep(index: 0, toolNames: ["finalAnswer"]),
        createStopConditionStep(index: 1)
    ])))
}

@Test func aiStopConditionHasToolCallReturnsTrueForAnyProvidedToolNameInLastStep() async throws {
    let stopCondition = AIStopCondition.hasToolCall("search", "finalAnswer")

    #expect(try await stopCondition.evaluate(AIStopConditionContext(steps: [
        createStopConditionStep(index: 0),
        createStopConditionStep(index: 1, toolNames: ["finalAnswer"])
    ])))
}

@Test func aiStopConditionHasToolCallReturnsFalseWhenLastStepContainsNoProvidedToolName() async throws {
    let stopCondition = AIStopCondition.hasToolCall("search", "finalAnswer")

    #expect(try await !stopCondition.evaluate(AIStopConditionContext(steps: [
        createStopConditionStep(index: 0),
        createStopConditionStep(index: 1, toolNames: ["weather"])
    ])))
}

@Test func aiStopConditionHasToolCallReturnsFalseWhenThereAreNoSteps() async throws {
    let stopCondition = AIStopCondition.hasToolCall("finalAnswer")

    #expect(try await !stopCondition.evaluate(AIStopConditionContext(steps: [])))
}

@Test func aiIsStopConditionMetReturnsTrueWhenAnyConditionReturnsTrue() async throws {
    let result = try await isStopConditionMet([
        AIStopCondition { _ in false },
        AIStopCondition { _ in true },
        AIStopCondition { _ in false }
    ], steps: [createStopConditionStep(index: 0)])

    #expect(result)
}

@Test func aiIsStopConditionMetReturnsFalseWhenAllConditionsReturnFalse() async throws {
    let result = try await isStopConditionMet([
        AIStopCondition { _ in false },
        AIStopCondition { _ in false }
    ], steps: [createStopConditionStep(index: 0)])

    #expect(!result)
}

@Test func aiIsStopConditionMetSupportsAsynchronousStopConditions() async throws {
    let result = try await isStopConditionMet([
        AIStopCondition { _ in
            try await Task.sleep(nanoseconds: 1)
            return false
        },
        AIStopCondition { context in
            try await Task.sleep(nanoseconds: 1)
            return context.steps.count == 2
        }
    ], steps: [
        createStopConditionStep(index: 0),
        createStopConditionStep(index: 1)
    ])

    #expect(result)
}

@Test func aiIsStopConditionMetThrowsWhenAConditionThrows() async throws {
    do {
        _ = try await isStopConditionMet([
            AIStopCondition { _ in false },
            AIStopCondition { _ in throw StopConditionTestError.stopConditionFailed }
        ], steps: [createStopConditionStep(index: 0)])
        Issue.record("Expected stop condition to throw.")
    } catch let error as StopConditionTestError {
        #expect(error.errorDescription == "stop condition failed")
    }
}

private enum StopConditionTestError: Error, LocalizedError {
    case stopConditionFailed

    var errorDescription: String? {
        "stop condition failed"
    }
}

private func createStopConditionStep(index: Int, toolNames: [String] = []) -> AIToolStep {
    AIToolStep(
        index: index,
        text: "",
        toolCalls: toolNames.enumerated().map { offset, toolName in
            AIToolCall(
                id: "call-\(index)-\(offset)",
                name: toolName,
                arguments: "{}"
            )
        }
    )
}
