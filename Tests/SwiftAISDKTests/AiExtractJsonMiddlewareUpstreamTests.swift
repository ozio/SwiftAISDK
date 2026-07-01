import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiExtractJsonMiddlewareStripsMarkdownFencesFromGeneratedTextLikeUpstream() async throws {
    #expect(defaultExtractJSONTransform("```json\n{\"value\": \"test\"}\n```") == "{\"value\": \"test\"}")
    #expect(defaultExtractJSONTransform("```\n{\"value\": \"test\"}\n```") == "{\"value\": \"test\"}")
    #expect(defaultExtractJSONTransform("{\"value\": \"test\"}") == "{\"value\": \"test\"}")
    #expect(defaultExtractJSONTransform("```json  \n{\"value\": \"test\"}\n```  ") == "{\"value\": \"test\"}")
    #expect(defaultExtractJSONTransform("```json\n```") == "")
}

@Test func aiExtractJsonMiddlewareUsesCustomGenerateTransformAndPreservesNonTextResultContentLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "testTool", arguments: #"{"foo":"bar"}"#)
    let model = ExtractJsonLanguageModel(result: TextGenerationResult(
        text: #"PREFIX{"value": "test"}SUFFIX"#,
        toolCalls: [toolCall],
        rawValue: .object([:])
    ))
    let wrapped = wrapLanguageModel(
        model,
        middleware: extractJsonMiddleware { text in
            text.replacingOccurrences(of: "PREFIX", with: "")
                .replacingOccurrences(of: "SUFFIX", with: "")
        }
    )

    let result = try await wrapped.generate(LanguageModelRequest(messages: [.user("Generate JSON")]))

    #expect(result.text == #"{"value": "test"}"#)
    #expect(result.toolCalls == [toolCall])
}

@Test func aiExtractJsonMiddlewareStripsMarkdownFencesFromStreamedTextLikeUpstream() async throws {
    let stream = transformTextStream(
        streamFromParts([
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "```json\n"),
            .textDeltaPart(id: "1", delta: #"{"value": "test"}"#),
            .textDeltaPart(id: "1", delta: "\n```"),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: testExtractJsonUsage)
        ]),
        transform: defaultExtractJSONTransform
    )

    let parts = try await collectExtractJsonParts(stream)

    #expect(parts == [
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: #"{"value": "test"}"#),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: testExtractJsonUsage)
    ])
}

@Test func aiExtractJsonMiddlewareHandlesSplitFencesCharacterByCharacterAndLargeContentLikeUpstream() async throws {
    let characterParts = Array("```json\n{\"value\": \"test\"}\n```").map {
        LanguageStreamPart.textDeltaPart(id: "1", delta: String($0))
    }
    let characterStream = transformTextStream(
        streamFromParts([.textStart(id: "1")] + characterParts + [.textEnd(id: "1")]),
        transform: defaultExtractJSONTransform
    )

    let characterText = try await collectExtractJsonText(characterStream)

    let largeJson = #"{"data":""# + String(repeating: "x", count: 100) + #"","nested":{"values":[0,1,2,3,4,5,6,7,8,9]}}"#
    let largeStream = transformTextStream(
        streamFromParts([
            .textStart(id: "large"),
            .textDeltaPart(id: "large", delta: "```json\n"),
            .textDeltaPart(id: "large", delta: largeJson),
            .textDeltaPart(id: "large", delta: "\n```"),
            .textEnd(id: "large")
        ]),
        transform: defaultExtractJSONTransform
    )

    let largeText = try await collectExtractJsonText(largeStream)

    #expect(characterText == #"{"value": "test"}"#)
    #expect(largeText == largeJson)
}

@Test func aiExtractJsonMiddlewareLeavesPlainAndBacktickTextUnchangedLikeUpstream() async throws {
    let plainText = try await collectExtractJsonText(transformTextStream(
        streamFromParts([
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "{"),
            .textDeltaPart(id: "1", delta: #""value": "test""#),
            .textDeltaPart(id: "1", delta: "}"),
            .textEnd(id: "1")
        ]),
        transform: defaultExtractJSONTransform
    ))
    let backtickText = try await collectExtractJsonText(transformTextStream(
        streamFromParts([
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "`code`"),
            .textEnd(id: "1")
        ]),
        transform: defaultExtractJSONTransform
    ))

    #expect(plainText == #"{"value": "test"}"#)
    #expect(backtickText == "`code`")
}

@Test func aiExtractJsonMiddlewarePassesThroughNonTextChunksAndMultipleTextIDsLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "tool-1", name: "testTool", arguments: #"{"arg":"value"}"#)
    let stream = transformTextStream(
        streamFromParts([
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "```json\n"),
            .textDeltaPart(id: "1", delta: #"{"first": true}"#),
            .textDeltaPart(id: "1", delta: "\n```"),
            .textEnd(id: "1"),
            .toolCall(toolCall),
            .textStart(id: "2"),
            .textDeltaPart(id: "2", delta: "```json\n"),
            .textDeltaPart(id: "2", delta: #"{"second": true}"#),
            .textDeltaPart(id: "2", delta: "\n```"),
            .textEnd(id: "2"),
            .finish(reason: "stop", usage: testExtractJsonUsage)
        ]),
        transform: defaultExtractJSONTransform
    )

    let parts = try await collectExtractJsonParts(stream)

    #expect(parts.contains(.toolCall(toolCall)))
    #expect(collectTextFromParts(parts) == #"{"first": true}{"second": true}"#)
    #expect(!collectTextFromParts(parts).contains("```"))
}

@Test func aiExtractJsonMiddlewareHandlesUnknownTextDeltaAndShortPrefixLikeUpstream() async throws {
    let unknownIDParts = try await collectExtractJsonParts(transformTextStream(
        streamFromParts([
            .textDeltaPart(id: "__proto__", delta: "some text"),
            .finish(reason: "stop", usage: testExtractJsonUsage)
        ]),
        transform: defaultExtractJSONTransform
    ))
    let shortPrefixParts = try await collectExtractJsonParts(transformTextStream(
        streamFromParts([
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "``"),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: testExtractJsonUsage)
        ]),
        transform: defaultExtractJSONTransform
    ))

    #expect(unknownIDParts.contains(.textDeltaPart(id: "__proto__", delta: "some text")))
    #expect(shortPrefixParts == [
        .textStart(id: "1"),
        .textDeltaPart(id: "1", delta: "``"),
        .textEnd(id: "1"),
        .finish(reason: "stop", usage: testExtractJsonUsage)
    ])
}

@Test func aiExtractJsonMiddlewareAppliesCustomStreamTransformLikeUpstream() async throws {
    let stream = transformTextStream(
        streamFromParts([
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: #"PREFIX{"value": "test"}SUFFIX"#),
            .textEnd(id: "1")
        ]),
        transform: {
            $0.replacingOccurrences(of: "PREFIX", with: "")
                .replacingOccurrences(of: "SUFFIX", with: "")
        }
    )

    let text = try await collectExtractJsonText(stream)

    #expect(text == #"{"value": "test"}"#)
}

private let testExtractJsonUsage = TokenUsage(inputTokens: 5, outputTokens: 10, totalTokens: 15)

private func streamFromParts(_ parts: [LanguageStreamPart]) -> AsyncThrowingStream<LanguageStreamPart, Error> {
    AsyncThrowingStream { continuation in
        for part in parts {
            continuation.yield(part)
        }
        continuation.finish()
    }
}

private func collectExtractJsonParts(
    _ stream: AsyncThrowingStream<LanguageStreamPart, Error>
) async throws -> [LanguageStreamPart] {
    var parts: [LanguageStreamPart] = []
    for try await part in stream {
        parts.append(part)
    }
    return parts
}

private func collectExtractJsonText(
    _ stream: AsyncThrowingStream<LanguageStreamPart, Error>
) async throws -> String {
    collectTextFromParts(try await collectExtractJsonParts(stream))
}

private func collectTextFromParts(_ parts: [LanguageStreamPart]) -> String {
    parts.reduce(into: "") { text, part in
        switch part {
        case let .textDelta(delta):
            text += delta
        case let .textDeltaPart(_, delta, _):
            text += delta
        default:
            break
        }
    }
}

private final class ExtractJsonLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "extract-json"
    let modelID = "language"
    let result: TextGenerationResult

    init(result: TextGenerationResult) {
        self.result = result
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        result
    }
}
