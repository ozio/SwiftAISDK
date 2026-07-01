import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiAsyncIterableStreamReadsAllChunksFromNonEmptyStreamUsingAsyncIterationLikeUpstream() async throws {
    let source = simulateReadableStream(
        chunks: ["chunk1", "chunk2", "chunk3"],
        initialDelayNanoseconds: nil,
        chunkDelayNanoseconds: nil
    )

    let stream = createAsyncIterableStream(source)

    #expect(try await collectAsyncIterableStream(stream) == ["chunk1", "chunk2", "chunk3"])
}

@Test func aiAsyncIterableStreamHandlesEmptyStreamGracefullyLikeUpstream() async throws {
    let source = simulateReadableStream(
        chunks: [] as [String],
        initialDelayNanoseconds: nil,
        chunkDelayNanoseconds: nil
    )

    let stream = createAsyncIterableStream(source)

    #expect(try await collectAsyncIterableStream(stream).isEmpty)
}

@Test func aiAsyncIterableStreamMaintainsStreamFunctionalityLikeUpstream() async throws {
    let source = simulateReadableStream(
        chunks: ["chunk1", "chunk2", "chunk3"],
        initialDelayNanoseconds: nil,
        chunkDelayNanoseconds: nil
    )

    let stream = createAsyncIterableStream(source)

    var iterator = stream.makeAsyncIterator()
    #expect(try await iterator.next() == "chunk1")
    #expect(try await iterator.next() == "chunk2")
    #expect(try await iterator.next() == "chunk3")
    #expect(try await iterator.next() == nil)
}

@Test func aiAsyncIterableStreamDoesNotCancelWhenStreamCompletesNormallyLikeUpstream() async throws {
    let termination = AsyncIterableStreamTerminationState()
    let source = AsyncThrowingStream<String, Error> { continuation in
        continuation.onTermination = { reason in
            termination.record(reason)
        }
        continuation.yield("chunk1")
        continuation.yield("chunk2")
        continuation.yield("chunk3")
        continuation.finish()
    }

    let stream = createAsyncIterableStream(source)

    #expect(try await collectAsyncIterableStream(stream) == ["chunk1", "chunk2", "chunk3"])
    #expect(await waitForAsyncIterableTermination(termination))
    #expect(termination.status == .finished)
}

@Test func aiAsyncIterableStreamPropagatesErrorsFromSourceStreamToAsyncIterableLikeUpstream() async throws {
    let streamError = AsyncIterableStreamTestError(message: "Stream error")
    let source = AsyncThrowingStream<String, Error> { continuation in
        continuation.yield("chunk1")
        continuation.yield("chunk2")
        continuation.finish(throwing: streamError)
    }

    let stream = createAsyncIterableStream(source)
    var collected: [String] = []

    do {
        for try await chunk in stream {
            collected.append(chunk)
        }
        Issue.record("Expected stream error.")
    } catch let error as AsyncIterableStreamTestError {
        #expect(error == streamError)
    }

    #expect(collected == ["chunk1", "chunk2"])
}

private struct AsyncIterableStreamTestError: Error, Equatable {
    var message: String
}

private enum AsyncIterableStreamTerminationStatus: Equatable {
    case cancelled
    case finished
}

private final class AsyncIterableStreamTerminationState: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedStatus: AsyncIterableStreamTerminationStatus?

    var status: AsyncIterableStreamTerminationStatus? {
        lock.lock()
        defer { lock.unlock() }
        return recordedStatus
    }

    func record(_ reason: AsyncThrowingStream<String, Error>.Continuation.Termination) {
        lock.lock()
        switch reason {
        case .cancelled:
            recordedStatus = .cancelled
        case .finished:
            recordedStatus = .finished
        @unknown default:
            recordedStatus = .cancelled
        }
        lock.unlock()
    }
}

private func collectAsyncIterableStream<Stream: AsyncSequence>(
    _ stream: Stream
) async throws -> [Stream.Element] {
    var result: [Stream.Element] = []
    for try await value in stream {
        result.append(value)
    }
    return result
}

private func waitForAsyncIterableTermination(
    _ termination: AsyncIterableStreamTerminationState,
    timeoutNanoseconds: UInt64 = 1_000_000_000
) async -> Bool {
    let start = DispatchTime.now().uptimeNanoseconds
    while termination.status == nil,
          DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return termination.status != nil
}
