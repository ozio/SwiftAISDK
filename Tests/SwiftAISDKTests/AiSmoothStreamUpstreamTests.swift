import Testing
@testable import SwiftAISDK

@Test func aiSmoothStreamCombinesPartialWordsLikeUpstream() async throws {
    let parts = try await collectSmoothParts([
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Hello"),
        .textDeltaPart(id: "1", delta: ", "),
        .textDeltaPart(id: "1", delta: "world!"),
        .textEnd(id: "1")
    ])

    #expect(parts == [
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Hello, "),
        .textDeltaPart(id: "1", delta: "world!"),
        .textEnd(id: "1")
    ])
}

@Test func aiSmoothStreamSplitsLargeTextChunksLikeUpstream() async throws {
    let parts = try await collectSmoothParts([
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Hello, World! This is an example text."),
        .textEnd(id: "1")
    ])

    #expect(parts == [
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Hello, "),
        .textDeltaPart(id: "1", delta: "World! "),
        .textDeltaPart(id: "1", delta: "This "),
        .textDeltaPart(id: "1", delta: "is "),
        .textDeltaPart(id: "1", delta: "an "),
        .textDeltaPart(id: "1", delta: "example "),
        .textDeltaPart(id: "1", delta: "text."),
        .textEnd(id: "1")
    ])
}

@Test func aiSmoothStreamKeepsLongWhitespaceSequencesWithWordsLikeUpstream() async throws {
    let parts = try await collectSmoothParts([
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "First line"),
        .textDeltaPart(id: "1", delta: " \n\n"),
        .textDeltaPart(id: "1", delta: "  "),
        .textDeltaPart(id: "1", delta: "  Multiple spaces"),
        .textDeltaPart(id: "1", delta: "\n    Indented"),
        .textEnd(id: "1")
    ])

    #expect(parts == [
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "First "),
        .textDeltaPart(id: "1", delta: "line \n\n"),
        .textDeltaPart(id: "1", delta: "    Multiple "),
        .textDeltaPart(id: "1", delta: "spaces\n    "),
        .textDeltaPart(id: "1", delta: "Indented"),
        .textEnd(id: "1")
    ])
}

@Test func aiSmoothStreamFlushesRemainingTextBeforeToolPartsLikeUpstream() async throws {
    let call = AIToolCall(id: "1", name: "weather", arguments: #"{"city":"London"}"#)
    let parts = try await collectSmoothParts([
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "I will check the"),
        .textDeltaPart(id: "1", delta: " weather in Lon"),
        .textDeltaPart(id: "1", delta: "don."),
        .toolInputStart(id: "2", name: "weather"),
        .toolInputDelta(id: "2", delta: #"{ city: "London" }"#),
        .toolInputEnd(id: "2"),
        .toolCall(call),
        .textEnd(id: "1")
    ])

    #expect(parts == [
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "I "),
        .textDeltaPart(id: "1", delta: "will "),
        .textDeltaPart(id: "1", delta: "check "),
        .textDeltaPart(id: "1", delta: "the "),
        .textDeltaPart(id: "1", delta: "weather "),
        .textDeltaPart(id: "1", delta: "in "),
        .textDeltaPart(id: "1", delta: "London."),
        .toolInputStart(id: "2", name: "weather"),
        .toolInputDelta(id: "2", delta: #"{ city: "London" }"#),
        .toolInputEnd(id: "2"),
        .toolCall(call),
        .textEnd(id: "1")
    ])
}

@Test func aiSmoothStreamDoesNotEmitWhitespaceOnlyChunksLikeUpstream() async throws {
    let parts = try await collectSmoothParts([
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: " "),
        .textDeltaPart(id: "1", delta: " "),
        .textDeltaPart(id: "1", delta: " "),
        .textDeltaPart(id: "1", delta: "foo"),
        .textEnd(id: "1")
    ])

    #expect(parts == [
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "   foo"),
        .textEnd(id: "1")
    ])
}

@Test func aiSmoothStreamLineChunkingMatchesUpstream() async throws {
    let parts = try await collectSmoothParts([
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "First line\nSecond line\nThird line with more text\n"),
        .textDeltaPart(id: "1", delta: "Partial line"),
        .textDeltaPart(id: "1", delta: " continues\nFinal line\n"),
        .textEnd(id: "1")
    ], chunking: .line)

    #expect(parts == [
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "First line\n"),
        .textDeltaPart(id: "1", delta: "Second line\n"),
        .textDeltaPart(id: "1", delta: "Third line with more text\n"),
        .textDeltaPart(id: "1", delta: "Partial line continues\n"),
        .textDeltaPart(id: "1", delta: "Final line\n"),
        .textEnd(id: "1")
    ])
}

@Test func aiSmoothStreamLineChunkingFlushesTextWithoutLineEndingsLikeUpstream() async throws {
    let parts = try await collectSmoothParts([
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Text without"),
        .textDeltaPart(id: "1", delta: " any line"),
        .textDeltaPart(id: "1", delta: " breaks"),
        .textEnd(id: "1")
    ], chunking: .line)

    #expect(parts == [
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Text without any line breaks"),
        .textEnd(id: "1")
    ])
}

@Test func aiSmoothStreamCustomDetectorCanReturnPrefixThroughMatchLikeUpstreamRegex() async throws {
    let parts = try await collectSmoothParts([
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Hello_, world!"),
        .textEnd(id: "1")
    ], detectChunk: { buffer in
        guard let index = buffer.firstIndex(of: "_") else { return nil }
        return String(buffer[...index])
    })

    #expect(parts == [
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Hello_"),
        .textDeltaPart(id: "1", delta: ", world!"),
        .textEnd(id: "1")
    ])
}

@Test func aiSmoothStreamCustomDetectorCanChunkCharactersLikeUpstreamRegex() async throws {
    let parts = try await collectSmoothParts([
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Hello"),
        .textEnd(id: "1")
    ], detectChunk: { buffer in
        buffer.isEmpty ? nil : String(buffer.prefix(1))
    })

    #expect(parts == [
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "H"),
        .textDeltaPart(id: "1", delta: "e"),
        .textDeltaPart(id: "1", delta: "l"),
        .textDeltaPart(id: "1", delta: "l"),
        .textDeltaPart(id: "1", delta: "o"),
        .textEnd(id: "1")
    ])
}

@Test func aiSmoothStreamCustomDetectorRejectsInvalidMatchesLikeUpstream() async throws {
    await #expect(throws: AIError.invalidArgument(
        argument: "detectChunk",
        message: "Chunk detector must return a non-empty string."
    )) {
        _ = try await collectSmoothParts([
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "Hello, world!"),
            .textEnd(id: "1")
        ], detectChunk: { _ in "" })
    }

    await #expect(throws: AIError.invalidArgument(
        argument: "detectChunk",
        message: "Chunk detector must return a prefix of the current buffer."
    )) {
        _ = try await collectSmoothParts([
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "Hello, world!"),
            .textEnd(id: "1")
        ], detectChunk: { _ in "world" })
    }
}

@Test func aiSmoothStreamFlushesWhenTextPartIDChangesLikeUpstream() async throws {
    let parts = try await collectSmoothParts([
        .textStart(id: "1"),
        .textStart(id: "2"),
        .textDeltaPart(id: "1", delta: "I will check the"),
        .textDeltaPart(id: "1", delta: " weather in Lon"),
        .textDeltaPart(id: "1", delta: "don."),
        .textDeltaPart(id: "2", delta: "I will check the"),
        .textDeltaPart(id: "2", delta: " weather in Lon"),
        .textDeltaPart(id: "2", delta: "don."),
        .textEnd(id: "1"),
        .textEnd(id: "2")
    ])

    #expect(parts == [
        .textStart(id: "1"),
        .textStart(id: "2"),
        .textDeltaPart(id: "1", delta: "I "),
        .textDeltaPart(id: "1", delta: "will "),
        .textDeltaPart(id: "1", delta: "check "),
        .textDeltaPart(id: "1", delta: "the "),
        .textDeltaPart(id: "1", delta: "weather "),
        .textDeltaPart(id: "1", delta: "in "),
        .textDeltaPart(id: "1", delta: "London."),
        .textDeltaPart(id: "2", delta: "I "),
        .textDeltaPart(id: "2", delta: "will "),
        .textDeltaPart(id: "2", delta: "check "),
        .textDeltaPart(id: "2", delta: "the "),
        .textDeltaPart(id: "2", delta: "weather "),
        .textDeltaPart(id: "2", delta: "in "),
        .textDeltaPart(id: "2", delta: "London."),
        .textEnd(id: "1"),
        .textEnd(id: "2")
    ])
}

@Test func aiSmoothStreamSmoothsReasoningLikeUpstream() async throws {
    let parts = try await collectSmoothParts([
        .reasoningStart(id: "1"),
        .reasoningDeltaPart(id: "1", delta: "Let"),
        .reasoningDeltaPart(id: "1", delta: " me "),
        .reasoningDeltaPart(id: "1", delta: "think..."),
        .reasoningEnd(id: "1")
    ])

    #expect(parts == [
        .reasoningStart(id: "1"),
        .reasoningDeltaPart(id: "1", delta: "Let "),
        .reasoningDeltaPart(id: "1", delta: "me "),
        .reasoningDeltaPart(id: "1", delta: "think..."),
        .reasoningEnd(id: "1")
    ])
}

@Test func aiSmoothStreamFlushesWhenSwitchingBetweenTextAndReasoningLikeUpstream() async throws {
    let parts = try await collectSmoothParts([
        .textStart(id: "t1"),
        .reasoningStart(id: "r1"),
        .reasoningDeltaPart(id: "r1", delta: "Think "),
        .textDeltaPart(id: "t1", delta: "Hello "),
        .reasoningDeltaPart(id: "r1", delta: "more "),
        .textDeltaPart(id: "t1", delta: "world "),
        .reasoningEnd(id: "r1"),
        .textEnd(id: "t1")
    ])

    #expect(parts == [
        .textStart(id: "t1"),
        .reasoningStart(id: "r1"),
        .reasoningDeltaPart(id: "r1", delta: "Think "),
        .textDeltaPart(id: "t1", delta: "Hello "),
        .reasoningDeltaPart(id: "r1", delta: "more "),
        .textDeltaPart(id: "t1", delta: "world "),
        .reasoningEnd(id: "r1"),
        .textEnd(id: "t1")
    ])
}

@Test func aiSmoothStreamPreservesReasoningProviderMetadataLikeUpstream() async throws {
    let signature: [String: JSONValue] = ["anthropic": ["signature": "sig_abc123"]]
    let parts = try await collectSmoothParts([
        .reasoningStart(id: "1"),
        .reasoningDeltaPart(id: "1", delta: "I am"),
        .reasoningDeltaPart(id: "1", delta: " thinking..."),
        .reasoningDeltaPart(id: "1", delta: "", providerMetadata: signature),
        .reasoningEnd(id: "1"),
        .textStart(id: "2"),
        .textDeltaPart(id: "2", delta: "Hello!"),
        .textEnd(id: "2")
    ])

    #expect(parts.contains(.reasoningDeltaPart(
        id: "1",
        delta: "thinking...",
        providerMetadata: signature
    )))
}

@Test func aiSmoothStreamPassesThroughReasoningStartProviderMetadataLikeUpstream() async throws {
    let metadata: [String: JSONValue] = ["anthropic": ["redactedData": "redacted-thinking-data"]]
    let parts = try await collectSmoothParts([
        .reasoningStart(id: "1", providerMetadata: metadata),
        .reasoningEnd(id: "1")
    ])

    #expect(parts == [
        .reasoningStart(id: "1", providerMetadata: metadata),
        .reasoningEnd(id: "1")
    ])
}

private func collectSmoothParts(
    _ parts: [LanguageStreamPart],
    chunking: AISmoothStreamChunking = .word
) async throws -> [LanguageStreamPart] {
    let stream = simulateReadableStream(
        chunks: parts,
        initialDelayNanoseconds: nil,
        chunkDelayNanoseconds: nil
    )
    var output: [LanguageStreamPart] = []
    for try await part in smoothStream(stream, delayNanoseconds: nil, chunking: chunking) {
        output.append(part)
    }
    return output
}

private func collectSmoothParts(
    _ parts: [LanguageStreamPart],
    detectChunk: @escaping AISmoothStreamChunkDetector
) async throws -> [LanguageStreamPart] {
    let stream = simulateReadableStream(
        chunks: parts,
        initialDelayNanoseconds: nil,
        chunkDelayNanoseconds: nil
    )
    var output: [LanguageStreamPart] = []
    for try await part in smoothStream(stream, delayNanoseconds: nil, detectChunk: detectChunk) {
        output.append(part)
    }
    return output
}
