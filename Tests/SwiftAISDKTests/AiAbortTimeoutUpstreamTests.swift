import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiSetAbortTimeoutDoesNotAbortBeforeTimeoutElapsesLikeUpstream() async throws {
    let abortController = AIAbortController()
    let timeout = setAbortTimeout(
        abortController: abortController,
        label: "Step",
        timeoutMilliseconds: 100
    )

    try await Task.sleep(nanoseconds: 5_000_000)

    #expect(!abortController.signal.isAborted)
    timeout?.cancel()
}

@Test func aiSetAbortTimeoutAbortsWhenTimeoutElapsesLikeUpstream() async {
    let abortController = AIAbortController()

    setAbortTimeout(abortController: abortController, label: "Step", timeoutMilliseconds: 1)

    #expect(await waitForAbort(abortController.signal))
}

@Test func aiSetAbortTimeoutAbortsWithTimeoutErrorNameLikeUpstream() async {
    let abortController = AIAbortController()

    setAbortTimeout(abortController: abortController, label: "Step", timeoutMilliseconds: 1)
    _ = await waitForAbort(abortController.signal)

    #expect(abortController.signal.reasonName == "TimeoutError")
}

@Test func aiSetAbortTimeoutIncludesLabelAndDurationInReasonMessageLikeUpstream() async {
    let abortController = AIAbortController()

    setAbortTimeout(abortController: abortController, label: "Chunk", timeoutMilliseconds: 1)
    _ = await waitForAbort(abortController.signal)

    #expect(abortController.signal.reason == "Chunk timeout of 1ms exceeded")
}

@Test func aiSetAbortTimeoutReturnsTaskThatCanBeCancelledLikeUpstreamClearTimeout() async throws {
    let abortController = AIAbortController()

    let timeout = setAbortTimeout(
        abortController: abortController,
        label: "Step",
        timeoutMilliseconds: 20
    )
    timeout?.cancel()
    try await Task.sleep(nanoseconds: 30_000_000)

    #expect(!abortController.signal.isAborted)
}

@Test func aiSetAbortTimeoutReturnsNilWhenAbortControllerIsNilLikeUpstream() {
    let timeout = setAbortTimeout(
        abortController: nil,
        label: "Step",
        timeoutMilliseconds: 100
    )

    #expect(timeout == nil)
}

@Test func aiSetAbortTimeoutReturnsNilWhenTimeoutIsNilLikeUpstream() async throws {
    let abortController = AIAbortController()

    let timeout = setAbortTimeout(
        abortController: abortController,
        label: "Step",
        timeoutMilliseconds: nil
    )
    try await Task.sleep(nanoseconds: 5_000_000)

    #expect(timeout == nil)
    #expect(!abortController.signal.isAborted)
}

private func waitForAbort(_ signal: AIAbortSignal, timeoutNanoseconds: UInt64 = 1_000_000_000) async -> Bool {
    let start = DispatchTime.now().uptimeNanoseconds
    while !signal.isAborted, DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return signal.isAborted
}
