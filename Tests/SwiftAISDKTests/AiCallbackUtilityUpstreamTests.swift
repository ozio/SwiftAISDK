import Foundation
import Testing
@testable import SwiftAISDK

private struct CallbackUtilityEvent: Equatable, Sendable {
    var value: String
}

private struct CallbackUtilityError: Error {}

private actor CallbackCallLog {
    private var calls: [String] = []

    func append(_ call: String) {
        calls.append(call)
    }

    func snapshot() -> [String] {
        calls
    }
}

private actor CallbackValueRecorder<Value: Sendable> {
    private var values: [Value] = []

    func append(_ value: Value) {
        values.append(value)
    }

    func snapshot() -> [Value] {
        values
    }
}

@Test func aiMergeCallbacksInvokesCallbacksInParallelWaitsAndContinuesAfterErrorsLikeUpstream() async throws {
    let calls = CallbackCallLog()
    let firstCallbackCompleted = AIDelayedPromise<Void>()
    let mergedCompleted = AIDelayedPromise<Void>()

    let callbacks: [AICallback<CallbackUtilityEvent>?] = [
        { event in
            await calls.append("first start: \(event.value)")
            try await firstCallbackCompleted.value()
            await calls.append("first end")
        },
        nil,
        { _ in
            await calls.append("second before throw")
            throw CallbackUtilityError()
        },
        { event in
            await calls.append("third: \(event.value)")
        }
    ]
    let merged = mergeCallbacks(callbacks)

    let mergedTask = Task {
        do {
            try await merged(CallbackUtilityEvent(value: "hello"))
            mergedCompleted.resolve(())
        } catch {
            mergedCompleted.reject(error)
        }
    }

    #expect(mergedCompleted.isPending)
    let startedCalls = await waitForCallbackCalls(
        calls,
        containing: ["first start: hello", "second before throw", "third: hello"]
    )
    #expect(startedCalls.contains("first start: hello"))
    #expect(startedCalls.contains("second before throw"))
    #expect(startedCalls.contains("third: hello"))
    #expect(!startedCalls.contains("first end"))

    firstCallbackCompleted.resolve(())
    try await mergedCompleted.value()
    await mergedTask.value

    let finishedCalls = await calls.snapshot()
    #expect(finishedCalls.contains("first end"))
}

@Test func aiMergeCallbacksIgnoresRejectedCallbacksLikeUpstream() async throws {
    let calls = CallbackCallLog()

    let callbacks: [AICallback<CallbackUtilityEvent>?] = [
        { event in
            await calls.append("first before reject: \(event.value)")
            await Task.yield()
            throw CallbackUtilityError()
        },
        { event in
            await calls.append("second: \(event.value)")
        }
    ]
    let merged = mergeCallbacks(callbacks)

    try await merged(CallbackUtilityEvent(value: "hello"))

    let snapshot = await calls.snapshot()
    #expect(snapshot.contains("first before reject: hello"))
    #expect(snapshot.contains("second: hello"))
}

@Test func aiMergeCallbacksIgnoresUndefinedCallbacksLikeUpstream() async throws {
    let calls = CallbackCallLog()

    let callbacks: [AICallback<CallbackUtilityEvent>?] = [
        nil,
        { event in
            await calls.append(event.value)
        },
        nil
    ]
    let merged = mergeCallbacks(callbacks)

    try await merged(CallbackUtilityEvent(value: "hello"))

    #expect(await calls.snapshot() == ["hello"])
}

@Test func aiNotifyCallsSingleCallbackWithEventLikeUpstream() async {
    let calls = CallbackCallLog()

    await notify(
        event: CallbackUtilityEvent(value: "hello"),
        callback: { event in
            await calls.append(event.value)
        }
    )

    #expect(await calls.snapshot() == ["hello"])
}

@Test func aiNotifyCallsCallbackArrayLikeUpstream() async {
    let calls = CallbackCallLog()
    let callbacks: [AICallback<CallbackUtilityEvent>?] = [
        { event in
            await calls.append("first: \(event.value)")
        },
        { event in
            await calls.append("second: \(event.value)")
        }
    ]

    await notify(event: CallbackUtilityEvent(value: "hello"), callbacks: callbacks)

    let snapshot = await calls.snapshot()
    #expect(snapshot.contains("first: hello"))
    #expect(snapshot.contains("second: hello"))
}

@Test func aiNotifyHandlesUndefinedAndOmittedCallbacksLikeUpstream() async {
    await notify(
        event: CallbackUtilityEvent(value: "hello"),
        callback: nil as AICallback<CallbackUtilityEvent>?
    )
    await notify(event: CallbackUtilityEvent(value: "hello"))
}

@Test func aiNotifyAwaitsAsyncCallbacksBeforeContinuingLikeUpstream() async {
    let calls = CallbackCallLog()

    await notify(
        event: "test",
        callback: { _ in
            try await Task.sleep(nanoseconds: 1_000_000)
            await calls.append("async done")
        }
    )
    await calls.append("after notify")

    #expect(await calls.snapshot() == ["async done", "after notify"])
}

@Test func aiNotifyRunsAsyncCallbacksInParallelAndAwaitsAllLikeUpstream() async throws {
    let calls = CallbackCallLog()
    let slowCompleted = AIDelayedPromise<Void>()
    let notifyCompleted = AIDelayedPromise<Void>()
    let callbacks: [AICallback<String>?] = [
        { _ in
            await calls.append("slow start")
            try await slowCompleted.value()
            await calls.append("slow end")
        },
        { _ in
            await calls.append("fast start")
            await calls.append("fast end")
        }
    ]

    let notifyTask = Task {
        await notify(event: "test", callbacks: callbacks)
        notifyCompleted.resolve(())
    }

    #expect(notifyCompleted.isPending)
    let startedCalls = await waitForCallbackCalls(
        calls,
        containing: ["slow start", "fast start", "fast end"]
    )
    #expect(startedCalls.contains("slow start"))
    #expect(startedCalls.contains("fast start"))
    #expect(startedCalls.contains("fast end"))
    #expect(!startedCalls.contains("slow end"))

    slowCompleted.resolve(())
    try await notifyCompleted.value()
    await notifyTask.value

    #expect((await calls.snapshot()).contains("slow end"))
}

private func waitForCallbackCalls(
    _ calls: CallbackCallLog,
    containing expectedCalls: [String],
    timeoutNanoseconds: UInt64 = 1_000_000_000
) async -> [String] {
    let start = DispatchTime.now().uptimeNanoseconds
    var snapshot = await calls.snapshot()
    while !expectedCalls.allSatisfy(snapshot.contains),
          DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
        try? await Task.sleep(nanoseconds: 1_000_000)
        snapshot = await calls.snapshot()
    }
    return snapshot
}

@Test func aiNotifyCatchesSingleCallbackErrorsLikeUpstream() async {
    let calls = CallbackCallLog()

    await notify(
        event: "test",
        callback: { _ in
            await calls.append("before throw")
            throw CallbackUtilityError()
        }
    )
    await calls.append("after notify")

    #expect(await calls.snapshot() == ["before throw", "after notify"])
}

@Test func aiNotifyCatchesArrayCallbackErrorsAndContinuesLikeUpstream() async {
    let calls = CallbackCallLog()
    let callbacks: [AICallback<String>?] = [
        { _ in
            await calls.append("first before throw")
            throw CallbackUtilityError()
        },
        { _ in
            await calls.append("second runs")
        }
    ]

    await notify(event: "test", callbacks: callbacks)

    let snapshot = await calls.snapshot()
    #expect(snapshot.contains("first before throw"))
    #expect(snapshot.contains("second runs"))
}

@Test func aiNotifyCatchesAsyncRejectionWithoutBreakingLikeUpstream() async {
    let calls = CallbackCallLog()

    await notify(
        event: "test",
        callback: { _ in
            await calls.append("async before reject")
            throw CallbackUtilityError()
        }
    )
    await calls.append("after notify")

    #expect(await calls.snapshot() == ["async before reject", "after notify"])
}

@Test func aiNotifyPreservesEventTypeLikeUpstream() async {
    struct MyEvent: Equatable, Sendable {
        var toolName: String
        var input: Input
        var stepNumber: Int

        struct Input: Equatable, Sendable {
            var location: String
        }
    }

    let received = CallbackValueRecorder<MyEvent>()
    let callback: AICallback<MyEvent> = { event in
        await received.append(event)
    }

    await notify(
        event: MyEvent(
            toolName: "getWeather",
            input: .init(location: "San Francisco"),
            stepNumber: 2
        ),
        callback: callback
    )

    #expect(await received.snapshot() == [
        MyEvent(
            toolName: "getWeather",
            input: .init(location: "San Francisco"),
            stepNumber: 2
        )
    ])
}

@Test func aiNotifyWorksWithComplexNestedEventTypesLikeUpstream() async {
    struct Usage: Sendable {
        var inputTokens: Int
        var outputTokens: Int
    }
    struct Step: Sendable {
        var stepNumber: Int
    }
    struct Model: Sendable {
        var provider: String
        var modelID: String
    }
    struct Event: Sendable {
        var model: Model
        var usage: Usage
        var steps: [Step]
    }
    struct Summary: Equatable, Sendable {
        var provider: String
        var totalSteps: Int
    }

    let received = CallbackValueRecorder<Summary>()

    await notify(
        event: Event(
            model: Model(provider: "openai", modelID: "gpt-4o"),
            usage: Usage(inputTokens: 100, outputTokens: 50),
            steps: [Step(stepNumber: 0), Step(stepNumber: 1)]
        ),
        callback: { event in
            await received.append(Summary(provider: event.model.provider, totalSteps: event.steps.count))
        }
    )

    #expect(await received.snapshot() == [Summary(provider: "openai", totalSteps: 2)])
}

@Test func aiNotifyHandlesRepeatedCallsWithSameCallbackLikeUpstream() async {
    let events = CallbackCallLog()
    let callback: AICallback<String> = { event in
        await events.append(event)
    }

    await notify(event: "first", callback: callback)
    await notify(event: "second", callback: callback)
    await notify(event: "third", callback: callback)

    #expect(await events.snapshot() == ["first", "second", "third"])
}
