import Testing
@testable import SwiftAISDK

private struct SerialJobExecutorTestError: Error {}

private actor SerialJobIntLog {
    private var values: [Int] = []

    func append(_ value: Int) {
        values.append(value)
    }

    func snapshot() -> [Int] {
        values
    }
}

private actor SerialJobStringLog {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func snapshot() -> [String] {
        values
    }
}

private actor SerialJobConcurrencyCounter {
    private var concurrentJobs = 0
    private var maxConcurrentJobs = 0

    func enter() {
        concurrentJobs += 1
        maxConcurrentJobs = max(maxConcurrentJobs, concurrentJobs)
    }

    func leave() {
        concurrentJobs -= 1
    }

    func maxConcurrent() -> Int {
        maxConcurrentJobs
    }
}

@Test func aiSerialJobExecutorExecutesSingleJobSuccessfullyLikeUpstream() async throws {
    let executor = AISerialJobExecutor()
    let result = AIDelayedPromise<String>()

    let job = executor.run {
        result.resolve("done")
    }

    try await job.value
    #expect(try await result.value() == "done")
}

@Test func aiSerialJobExecutorExecutesMultipleJobsInSerialOrderLikeUpstream() async throws {
    let executor = AISerialJobExecutor()
    let executionOrder = SerialJobIntLog()

    let job1 = executor.run {
        await executionOrder.append(1)
    }
    let job2 = executor.run {
        await executionOrder.append(2)
    }
    let job3 = executor.run {
        await executionOrder.append(3)
    }

    try await job1.value
    try await job2.value
    try await job3.value

    #expect(await executionOrder.snapshot() == [1, 2, 3])
}

@Test func aiSerialJobExecutorHandlesJobErrorsLikeUpstream() async {
    let executor = AISerialJobExecutor()
    let job = executor.run {
        throw SerialJobExecutorTestError()
    }

    do {
        try await job.value
        Issue.record("Expected job to throw")
    } catch is SerialJobExecutorTestError {}
    catch {
        Issue.record("Expected SerialJobExecutorTestError, got \(error)")
    }
}

@Test func aiSerialJobExecutorRunsOneJobAtATimeLikeUpstream() async throws {
    let executor = AISerialJobExecutor()
    let counter = SerialJobConcurrencyCounter()
    let job1Gate = AIDelayedPromise<Void>()
    let job2Gate = AIDelayedPromise<Void>()

    let job1 = executor.run {
        await counter.enter()
        try await job1Gate.value()
        await counter.leave()
    }
    let job2 = executor.run {
        await counter.enter()
        try await job2Gate.value()
        await counter.leave()
    }

    job1Gate.resolve(())
    job2Gate.resolve(())

    try await job1.value
    try await job2.value

    #expect(await counter.maxConcurrent() == 1)
}

@Test func aiSerialJobExecutorHandlesMixedSuccessAndFailureJobsLikeUpstream() async throws {
    let executor = AISerialJobExecutor()
    let results = SerialJobStringLog()

    let job1 = executor.run {
        await results.append("job1")
    }
    let job2 = executor.run {
        throw SerialJobExecutorTestError()
    }
    let job3 = executor.run {
        await results.append("job3")
    }

    try await job1.value
    #expect(await results.snapshot() == ["job1"])

    do {
        try await job2.value
        Issue.record("Expected second job to throw")
    } catch is SerialJobExecutorTestError {}
    catch {
        Issue.record("Expected SerialJobExecutorTestError, got \(error)")
    }

    try await job3.value
    #expect(await results.snapshot() == ["job1", "job3"])
}

@Test func aiSerialJobExecutorHandlesConcurrentRunCallsLikeUpstream() async throws {
    let executor = AISerialJobExecutor()
    let executionOrder = SerialJobIntLog()
    let startOrder = SerialJobIntLog()
    let job1Gate = AIDelayedPromise<Void>()
    let job2Gate = AIDelayedPromise<Void>()
    let job3Gate = AIDelayedPromise<Void>()

    let job1 = executor.run {
        await startOrder.append(1)
        try await job1Gate.value()
        await executionOrder.append(1)
    }
    let job2 = executor.run {
        await startOrder.append(2)
        try await job2Gate.value()
        await executionOrder.append(2)
    }
    let job3 = executor.run {
        await startOrder.append(3)
        try await job3Gate.value()
        await executionOrder.append(3)
    }

    job3Gate.resolve(())
    job2Gate.resolve(())
    job1Gate.resolve(())

    try await job1.value
    try await job2.value
    try await job3.value

    #expect(await startOrder.snapshot() == [1, 2, 3])
    #expect(await executionOrder.snapshot() == [1, 2, 3])
}
