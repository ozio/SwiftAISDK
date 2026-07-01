import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiExtractReasoningMiddlewareExtractsGeneratedReasoningLikeUpstream() {
    let single = extractTaggedSections(
        text: "<think>analyzing the request</think>Here is the response",
        tagName: "think",
        separator: "\n"
    )
    let noText = extractTaggedSections(
        text: "<think>analyzing the request\n</think>",
        tagName: "think",
        separator: "\n"
    )
    let multiple = extractTaggedSections(
        text: "<think>analyzing the request</think>Here is the response<think>thinking about the response</think>more",
        tagName: "think",
        separator: "\n"
    )

    #expect(single?.reasoning == "analyzing the request")
    #expect(single?.text == "Here is the response")
    #expect(noText?.reasoning == "analyzing the request\n")
    #expect(noText?.text == "")
    #expect(multiple?.reasoning == "analyzing the request\nthinking about the response")
    #expect(multiple?.text == "Here is the response\nmore")
}

@Test func aiExtractReasoningMiddlewareHonorsStartWithReasoningLikeUpstream() async throws {
    let trueStream = extractReasoningStream(
        reasoningStreamFromParts([
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "analyzing the request\n"),
            .textDeltaPart(id: "1", delta: "</think>"),
            .textDeltaPart(id: "1", delta: "this is the response"),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: testExtractReasoningUsage)
        ]),
        tagName: "think",
        separator: "\n",
        startWithReasoning: true
    )
    let falseStream = extractReasoningStream(
        reasoningStreamFromParts([
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "analyzing the request\n"),
            .textDeltaPart(id: "1", delta: "</think>"),
            .textDeltaPart(id: "1", delta: "this is the response"),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: testExtractReasoningUsage)
        ]),
        tagName: "think",
        separator: "\n",
        startWithReasoning: false
    )

    #expect(try await collectReasoningParts(trueStream) == [
        .reasoningStart(id: "reasoning-0"),
        .reasoningDeltaPart(id: "reasoning-0", delta: "analyzing the request\n"),
        .reasoningEnd(id: "reasoning-0"),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "this is the response"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: testExtractReasoningUsage)
    ])
    #expect(try await collectReasoningParts(falseStream) == [
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "analyzing the request\n</think>this is the response"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: testExtractReasoningUsage)
    ])
}

@Test func aiExtractReasoningMiddlewareExtractsSplitReasoningTagsFromStreamLikeUpstream() async throws {
    let stream = extractReasoningStream(
        reasoningStreamFromParts([
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "<think>"),
            .textDeltaPart(id: "1", delta: "ana"),
            .textDeltaPart(id: "1", delta: "lyzing the request"),
            .textDeltaPart(id: "1", delta: "</think>"),
            .textDeltaPart(id: "1", delta: "Here"),
            .textDeltaPart(id: "1", delta: " is the response"),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: testExtractReasoningUsage)
        ]),
        tagName: "think",
        separator: "\n",
        startWithReasoning: false
    )

    #expect(try await collectReasoningParts(stream) == [
        .reasoningStart(id: "reasoning-0"),
        .reasoningDeltaPart(id: "reasoning-0", delta: "analyzing the request"),
        .reasoningEnd(id: "reasoning-0"),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Here is the response"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: testExtractReasoningUsage)
    ])
}

@Test func aiExtractReasoningMiddlewareInterleavesMultipleReasoningTagsLikeUpstream() async throws {
    let stream = extractReasoningStream(
        reasoningStreamFromParts([
            .textStart(id: "1"),
            .textDeltaPart(
                id: "1",
                delta: "<think>analyzing the request</think>Here is the response<think>thinking about the response</think>more"
            ),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: testExtractReasoningUsage)
        ]),
        tagName: "think",
        separator: "\n",
        startWithReasoning: false
    )

    #expect(try await collectReasoningParts(stream) == [
        .reasoningStart(id: "reasoning-0"),
        .reasoningDeltaPart(id: "reasoning-0", delta: "analyzing the request"),
        .reasoningEnd(id: "reasoning-0"),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "Here is the response"),
        .reasoningStart(id: "reasoning-1"),
        .reasoningDeltaPart(id: "reasoning-1", delta: "\nthinking about the response"),
        .reasoningEnd(id: "reasoning-1"),
        .textDeltaPart(id: "1", delta: "\nmore"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: testExtractReasoningUsage)
    ])
}

@Test func aiExtractReasoningMiddlewareHandlesNoTextAndEmptyTagsLikeUpstream() async throws {
    let noText = extractReasoningStream(
        reasoningStreamFromParts([
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "<think>"),
            .textDeltaPart(id: "1", delta: "analyzing the request\n"),
            .textDeltaPart(id: "1", delta: "</think>"),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: testExtractReasoningUsage)
        ]),
        tagName: "think",
        separator: "\n",
        startWithReasoning: false
    )
    let emptyTag = extractReasoningStream(
        reasoningStreamFromParts([
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "<think></think>"),
            .textDeltaPart(id: "1", delta: " This is the answer."),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: testExtractReasoningUsage)
        ]),
        tagName: "think",
        separator: "\n",
        startWithReasoning: false
    )

    #expect(try await collectReasoningParts(noText) == [
        .reasoningStart(id: "reasoning-0"),
        .reasoningDeltaPart(id: "reasoning-0", delta: "analyzing the request\n"),
        .reasoningEnd(id: "reasoning-0"),
        .textStart(id: "1"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: testExtractReasoningUsage)
    ])
    #expect(try await collectReasoningParts(emptyTag) == [
        .reasoningStart(id: "reasoning-0"),
        .reasoningEnd(id: "reasoning-0"),
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: " This is the answer."),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: testExtractReasoningUsage)
    ])
}

@Test func aiExtractReasoningMiddlewareKeepsOriginalTextWhenTagIsAbsentLikeUpstream() async throws {
    let stream = extractReasoningStream(
        reasoningStreamFromParts([
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "this is the response"),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: testExtractReasoningUsage)
        ]),
        tagName: "think",
        separator: "\n",
        startWithReasoning: false
    )

    #expect(try await collectReasoningParts(stream) == [
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "this is the response"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: testExtractReasoningUsage)
    ])
}

@Test func aiExtractReasoningMiddlewareHandlesMissingTextStartIDsAsOrdinaryKeysLikeUpstream() async throws {
    let stream = extractReasoningStream(
        reasoningStreamFromParts([
            .textDeltaPart(id: "__proto__", delta: "Hello"),
            .finish(reason: "stop", usage: testExtractReasoningUsage)
        ]),
        tagName: "think",
        separator: "\n",
        startWithReasoning: false
    )

    #expect(try await collectReasoningParts(stream) == [
        .textStart(id: "__proto__"),
        .textDeltaPart(id: "__proto__", delta: "Hello"),
        .textEnd(id: "__proto__"),
        .finish(reason: "stop", usage: testExtractReasoningUsage)
    ])
}

private let testExtractReasoningUsage = TokenUsage(inputTokens: 5, outputTokens: 10, totalTokens: 15)

private func reasoningStreamFromParts(_ parts: [LanguageStreamPart]) -> AsyncThrowingStream<LanguageStreamPart, Error> {
    AsyncThrowingStream { continuation in
        for part in parts {
            continuation.yield(part)
        }
        continuation.finish()
    }
}

private func collectReasoningParts(
    _ stream: AsyncThrowingStream<LanguageStreamPart, Error>
) async throws -> [LanguageStreamPart] {
    var parts: [LanguageStreamPart] = []
    for try await part in stream {
        parts.append(part)
    }
    return parts
}
