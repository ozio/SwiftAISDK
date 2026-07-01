import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiStitchableStreamReturnsNoValuesWhenImmediatelyClosedLikeUpstream() async throws {
    let stitchable: AIStitchableStream<Int> = createStitchableStream()

    stitchable.close()

    #expect(try await collectStitchableStream(stitchable.stream) == [])
}

@Test func aiStitchableStreamReturnsAllValuesFromSingleInnerStreamLikeUpstream() async throws {
    let stitchable: AIStitchableStream<Int> = createStitchableStream()

    try stitchable.addStream(stitchableSource([1, 2, 3]))
    stitchable.close()

    #expect(try await collectStitchableStream(stitchable.stream) == [1, 2, 3])
}

@Test func aiStitchableStreamReturnsAllValuesFromTwoInnerStreamsLikeUpstream() async throws {
    let stitchable: AIStitchableStream<Int> = createStitchableStream()

    try stitchable.addStream(stitchableSource([1, 2, 3]))
    try stitchable.addStream(stitchableSource([4, 5, 6]))
    stitchable.close()

    #expect(try await collectStitchableStream(stitchable.stream) == [1, 2, 3, 4, 5, 6])
}

@Test func aiStitchableStreamReturnsAllValuesFromThreeInnerStreamsLikeUpstream() async throws {
    let stitchable: AIStitchableStream<Int> = createStitchableStream()

    try stitchable.addStream(stitchableSource([1, 2, 3]))
    try stitchable.addStream(stitchableSource([4, 5, 6]))
    try stitchable.addStream(stitchableSource([7, 8, 9]))
    stitchable.close()

    #expect(try await collectStitchableStream(stitchable.stream) == [1, 2, 3, 4, 5, 6, 7, 8, 9])
}

@Test func aiStitchableStreamHandlesEmptyInnerStreamsLikeUpstream() async throws {
    let stitchable: AIStitchableStream<Int> = createStitchableStream()

    try stitchable.addStream(stitchableSource([]))
    try stitchable.addStream(stitchableSource([1, 2]))
    try stitchable.addStream(stitchableSource([]))
    try stitchable.addStream(stitchableSource([3, 4]))
    stitchable.close()

    #expect(try await collectStitchableStream(stitchable.stream) == [1, 2, 3, 4])
}

@Test func aiStitchableStreamHandlesReadingSingleValueBeforeItIsAddedLikeUpstream() async throws {
    let stitchable: AIStitchableStream<Int> = createStitchableStream()

    let readTask = Task {
        var iterator = stitchable.stream.makeAsyncIterator()
        let first = try await iterator.next()
        let second = try await iterator.next()
        return (first, second)
    }

    try await Task.sleep(nanoseconds: 1_000_000)
    try stitchable.addStream(stitchableSource([42]))
    stitchable.close()

    let result = try await readTask.value
    #expect(result.0 == 42)
    #expect(result.1 == nil)
}

@Test func aiStitchableStreamResolvesPendingReadsWhenInnerStreamsAreAddedLikeUpstream() async throws {
    let stitchable: AIStitchableStream<Int> = createStitchableStream()

    let collectTask = Task {
        try await collectStitchableStream(stitchable.stream)
    }

    try await Task.sleep(nanoseconds: 1_000_000)
    try stitchable.addStream(stitchableSource([1, 2, 3]))
    try stitchable.addStream(stitchableSource([4, 5]))
    stitchable.close()

    #expect(try await collectTask.value == [1, 2, 3, 4, 5])
}

@Test func aiStitchableStreamPropagatesErrorsFromInnerStreamsLikeUpstream() async throws {
    let stitchable: AIStitchableStream<Int> = createStitchableStream()
    let error = StitchableStreamTestError(message: "Test error")

    try stitchable.addStream(stitchableSource([1, 2]))
    try stitchable.addStream(AsyncThrowingStream { continuation in
        continuation.finish(throwing: error)
    })
    try stitchable.addStream(stitchableSource([3, 4]))
    stitchable.close()

    do {
        _ = try await collectStitchableStream(stitchable.stream)
        Issue.record("Expected stitchable stream error.")
    } catch let caught as StitchableStreamTestError {
        #expect(caught == error)
    }
}

@Test func aiStitchableStreamThrowsWhenAddingStreamAfterClosingLikeUpstream() throws {
    let stitchable: AIStitchableStream<Int> = createStitchableStream()

    stitchable.close()

    #expect(throws: AIError.invalidArgument(
        argument: "innerStream",
        message: "Cannot add inner stream: outer stream is closed"
    )) {
        try stitchable.addStream(stitchableSource([1, 2]))
    }
}

@Test func aiStitchableStreamTerminateImmediatelyClosesStreamLikeUpstream() async throws {
    let stitchable: AIStitchableStream<Int> = createStitchableStream()

    try stitchable.addStream(simulateReadableStream(
        chunks: [1, 2],
        initialDelayNanoseconds: nil,
        chunkDelayNanoseconds: 100_000_000
    ))
    try stitchable.addStream(stitchableSource([3, 4]))

    var iterator = stitchable.stream.makeAsyncIterator()
    let first = try await iterator.next()
    stitchable.terminate()
    let final = try await iterator.next()

    #expect(first == 1)
    #expect(final == nil)
}

@Test func aiStitchableStreamThrowsWhenAddingStreamAfterTerminatingLikeUpstream() throws {
    let stitchable: AIStitchableStream<Int> = createStitchableStream()

    stitchable.terminate()

    #expect(throws: AIError.invalidArgument(
        argument: "innerStream",
        message: "Cannot add inner stream: outer stream is closed"
    )) {
        try stitchable.addStream(stitchableSource([1, 2]))
    }
}

private struct StitchableStreamTestError: Error, Equatable {
    var message: String
}

private func stitchableSource(_ values: [Int]) -> AsyncThrowingStream<Int, Error> {
    simulateReadableStream(
        chunks: values,
        initialDelayNanoseconds: nil,
        chunkDelayNanoseconds: nil
    )
}

private func collectStitchableStream<Element: Sendable>(
    _ stream: AsyncThrowingStream<Element, Error>
) async throws -> [Element] {
    var result: [Element] = []
    for try await value in stream {
        result.append(value)
    }
    return result
}
