import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiSimulateReadableStreamCreatesStreamWithProvidedValuesLikeUpstream() async throws {
    let values = ["a", "b", "c"]
    let stream = simulateReadableStream(chunks: values)

    let result = try await collectSimulatedStream(stream)

    #expect(result == values)
}

@Test func aiSimulateReadableStreamRespectsChunkDelaySettingLikeUpstream() async throws {
    let delays = SimulatedStreamDelayRecorder()
    let stream = simulateReadableStream(
        chunks: [1, 2, 3],
        initialDelayNanoseconds: milliseconds(500),
        chunkDelayNanoseconds: milliseconds(100),
        delay: delays.record
    )

    _ = try await collectSimulatedStream(stream)

    #expect(delays.values == [milliseconds(500), milliseconds(100), milliseconds(100)])
}

@Test func aiSimulateReadableStreamHandlesEmptyValuesArrayLikeUpstream() async throws {
    let stream = simulateReadableStream(chunks: [] as [String])

    let result = try await collectSimulatedStream(stream)

    #expect(result.isEmpty)
}

@Test func aiSimulateReadableStreamHandlesDifferentValueTypesLikeUpstream() async throws {
    let chunks = [
        SimulatedStreamObject(id: 1, text: "hello"),
        SimulatedStreamObject(id: 2, text: "world")
    ]
    let stream = simulateReadableStream(chunks: chunks)

    let result = try await collectSimulatedStream(stream)

    #expect(result == chunks)
}

@Test func aiSimulateReadableStreamSkipsAllDelaysWhenBothDelaySettingsAreNilLikeUpstream() async throws {
    let delays = SimulatedStreamDelayRecorder()
    let stream = simulateReadableStream(
        chunks: [1, 2, 3],
        initialDelayNanoseconds: nil,
        chunkDelayNanoseconds: nil,
        delay: delays.record
    )

    _ = try await collectSimulatedStream(stream)

    #expect(delays.values == [nil, nil, nil])
}

@Test func aiSimulateReadableStreamAppliesChunkDelaysButSkipsInitialDelayWhenInitialDelayIsNilLikeUpstream() async throws {
    let delays = SimulatedStreamDelayRecorder()
    let stream = simulateReadableStream(
        chunks: [1, 2, 3],
        initialDelayNanoseconds: nil,
        chunkDelayNanoseconds: milliseconds(100),
        delay: delays.record
    )

    _ = try await collectSimulatedStream(stream)

    #expect(delays.values == [nil, milliseconds(100), milliseconds(100)])
}

@Test func aiSimulateReadableStreamAppliesInitialDelayButSkipsChunkDelaysWhenChunkDelayIsNilLikeUpstream() async throws {
    let delays = SimulatedStreamDelayRecorder()
    let stream = simulateReadableStream(
        chunks: [1, 2, 3],
        initialDelayNanoseconds: milliseconds(500),
        chunkDelayNanoseconds: nil,
        delay: delays.record
    )

    _ = try await collectSimulatedStream(stream)

    #expect(delays.values == [milliseconds(500), nil, nil])
}

private struct SimulatedStreamObject: Equatable, Sendable {
    var id: Int
    var text: String
}

private final class SimulatedStreamDelayRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [UInt64?] = []

    var values: [UInt64?] {
        lock.lock()
        defer { lock.unlock() }
        return recordedValues
    }

    func record(_ delay: UInt64?) async throws {
        append(delay)
    }

    private func append(_ delay: UInt64?) {
        lock.lock()
        recordedValues.append(delay)
        lock.unlock()
    }
}

private func collectSimulatedStream<Element: Sendable>(
    _ stream: AsyncThrowingStream<Element, Error>
) async throws -> [Element] {
    var result: [Element] = []
    for try await value in stream {
        result.append(value)
    }
    return result
}

private func milliseconds(_ value: UInt64) -> UInt64 {
    value * 1_000_000
}
