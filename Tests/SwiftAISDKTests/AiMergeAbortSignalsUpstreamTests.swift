import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiMergeAbortSignalsReturnsSignalThatIsInitiallyNotAbortedLikeUpstream() {
    let controller1 = AIAbortController()
    let controller2 = AIAbortController()

    let merged = mergeAbortSignals(controller1.signal, controller2.signal)

    #expect(merged?.isAborted == false)
}

@Test func aiMergeAbortSignalsAbortsWhenFirstSignalAbortsLikeUpstream() {
    let controller1 = AIAbortController()
    let controller2 = AIAbortController()

    let merged = mergeAbortSignals(controller1.signal, controller2.signal)

    controller1.abort()

    #expect(merged?.isAborted == true)
}

@Test func aiMergeAbortSignalsAbortsWhenSecondSignalAbortsLikeUpstream() {
    let controller1 = AIAbortController()
    let controller2 = AIAbortController()

    let merged = mergeAbortSignals(controller1.signal, controller2.signal)

    controller2.abort()

    #expect(merged?.isAborted == true)
}

@Test func aiMergeAbortSignalsPreservesAbortReasonFromTriggeringSignalLikeUpstream() {
    let controller1 = AIAbortController()
    let controller2 = AIAbortController()

    let merged = mergeAbortSignals(controller1.signal, controller2.signal)

    controller1.abort(reason: "custom abort reason")

    #expect(merged?.reason == "custom abort reason")
}

@Test func aiMergeAbortSignalsPreservesStringAbortReasonLikeUpstream() {
    let controller = AIAbortController()

    let merged = mergeAbortSignals(controller.signal)

    controller.abort(reason: "string reason")

    #expect(merged?.reason == "string reason")
}

@Test func aiMergeAbortSignalsHandlesAlreadyAbortedSignalsLikeUpstream() {
    let controller = AIAbortController()
    controller.abort(reason: "already aborted")

    let merged = mergeAbortSignals(controller.signal)

    #expect(merged?.isAborted == true)
    #expect(merged?.reason == "already aborted")
}

@Test func aiMergeAbortSignalsUsesFirstAlreadyAbortedSignalReasonWhenMultipleAreAbortedLikeUpstream() {
    let controller1 = AIAbortController()
    let controller2 = AIAbortController()

    controller1.abort(reason: "first reason")
    controller2.abort(reason: "second reason")

    let merged = mergeAbortSignals(controller1.signal, controller2.signal)

    #expect(merged?.isAborted == true)
    #expect(merged?.reason == "first reason")
}

@Test func aiMergeAbortSignalsReturnsNilWhenNoSignalsProvidedLikeUpstream() {
    let merged = mergeAbortSignals([])

    #expect(merged == nil)
}

@Test func aiMergeAbortSignalsReturnsNilWhenOnlyNilSignalsProvidedLikeUpstream() {
    let merged = mergeAbortSignals([nil, nil, nil])

    #expect(merged == nil)
}

@Test func aiMergeAbortSignalsCreatesTimeoutSignalFromNumericInputLikeUpstream() async {
    let merged = mergeAbortSignals(sources: .timeoutMilliseconds(1))

    #expect(merged != nil)
    #expect(merged?.isAborted == false)

    #expect(await waitForMergedAbort(merged))
    #expect(merged?.isAborted == true)
    #expect(merged?.reasonName == "TimeoutError")
}

@Test func aiMergeAbortSignalsPreservesFirstAbortReasonWhenMixingSignalsAndTimeoutsLikeUpstream() {
    let controller = AIAbortController()
    let merged = mergeAbortSignals(sources: .signal(controller.signal), .timeoutMilliseconds(100))

    controller.abort(reason: "manual abort reason")

    #expect(merged?.isAborted == true)
    #expect(merged?.reason == "manual abort reason")
}

@Test func aiMergeAbortSignalsFiltersOutNilSignalsLikeUpstream() {
    let controller = AIAbortController()

    let merged = mergeAbortSignals([nil, controller.signal, nil])

    #expect(merged != nil)
    #expect(merged?.isAborted == false)

    controller.abort(reason: "abort reason")

    #expect(merged?.isAborted == true)
    #expect(merged?.reason == "abort reason")
}

@Test func aiMergeAbortSignalsReturnsSignalDirectlyWhenOnlyOneValidSignalProvidedLikeUpstream() {
    let controller = AIAbortController()

    let merged = mergeAbortSignals([nil, controller.signal, nil])

    #expect(merged === controller.signal)
}

@Test func aiMergeAbortSignalsUsesFirstAbortingSignalReasonWhenMultipleAbortSimultaneouslyLikeUpstream() {
    let controller1 = AIAbortController()
    let controller2 = AIAbortController()

    let merged = mergeAbortSignals(controller1.signal, controller2.signal)

    controller1.abort(reason: "first reason")
    controller2.abort(reason: "second reason")

    #expect(merged?.reason == "first reason")
}

@Test func aiMergeAbortSignalsReturnsOriginalSignalWhenOnlyOneSignalProvidedLikeUpstream() {
    let controller = AIAbortController()

    let merged = mergeAbortSignals(controller.signal)

    #expect(merged === controller.signal)
}

@Test func aiMergeAbortSignalsWorksWithManySignalsLikeUpstream() {
    let controllers = (0..<10).map { _ in AIAbortController() }

    let merged = mergeAbortSignals(controllers.map(\.signal))

    #expect(merged?.isAborted == false)

    controllers[5].abort(reason: "signal 5 reason")

    #expect(merged?.isAborted == true)
    #expect(merged?.reason == "signal 5 reason")
}

private func waitForMergedAbort(_ signal: AIAbortSignal?, timeoutNanoseconds: UInt64 = 1_000_000_000) async -> Bool {
    guard let signal else { return false }
    let start = DispatchTime.now().uptimeNanoseconds
    while !signal.isAborted, DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return signal.isAborted
}
