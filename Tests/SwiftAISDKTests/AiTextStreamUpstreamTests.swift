import Testing
@testable import SwiftAISDK

@Test func aiToTextStreamKeepsOnlyTextDeltasLikeUpstream() async throws {
    let stream = toTextStream(languageStream([
        .streamStart(warnings: []),
        .textStart(id: "t1"),
        .textDeltaPart(id: "t1", delta: "Hello"),
        .textDeltaPart(id: "t1", delta: ", world!"),
        .textEnd(id: "t1")
    ]))

    var chunks: [String] = []
    for try await chunk in stream {
        chunks.append(chunk)
    }

    #expect(chunks == ["Hello", ", world!"])
}

private func languageStream(_ parts: [LanguageStreamPart]) -> AsyncThrowingStream<LanguageStreamPart, Error> {
    AsyncThrowingStream { continuation in
        for part in parts {
            continuation.yield(part)
        }
        continuation.finish()
    }
}
