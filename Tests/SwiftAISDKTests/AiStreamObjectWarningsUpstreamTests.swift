import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiStreamObjectWarningsResolveEmptyWarningsLikeUpstream() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .streamStart(warnings: []),
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: #"{ "content": "Hello, world!" }"#),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
        ]
    )

    var object: ObjectGenerationResult<StreamObjectContent>?
    for try await part in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        schema: streamObjectContentSchema()
    ) {
        if case let .object(result) = part {
            object = result
        }
    }

    #expect(object?.warnings == [])
}

@Test func aiStreamObjectWarningsResolveWarningsLikeUpstream() async throws {
    let expectedWarnings = [
        AIWarning(
            type: "unsupported",
            feature: "frequency_penalty",
            message: "This model does not support the frequency_penalty setting."
        ),
        AIWarning(type: "other", message: "Test warning message")
    ]
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .streamStart(warnings: expectedWarnings),
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: #"{ "content": "Hello, world!" }"#),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
        ]
    )

    var warningParts: [AIWarning] = []
    var object: ObjectGenerationResult<StreamObjectContent>?
    for try await part in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        schema: streamObjectContentSchema()
    ) {
        switch part {
        case let .warning(warning):
            warningParts.append(warning)
        case let .object(result):
            object = result
        default:
            break
        }
    }

    #expect(warningParts == expectedWarnings)
    #expect(object?.warnings == expectedWarnings)
}

@Test func aiStreamObjectWarningsCallLogWarningsWithWarningsLikeUpstream() async throws {
    let expectedWarnings = [
        AIWarning(type: "other", message: "Setting is not supported"),
        AIWarning(
            type: "unsupported",
            feature: "temperature",
            message: "Temperature parameter not supported"
        )
    ]
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .streamStart(warnings: expectedWarnings),
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: #"{ "content": "Hello, world!" }"#),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
        ]
    )
    let recorder = StreamObjectWarningLogRecorder()

    try await AIWarningLogging.withLogger(recorder) {
        for try await _ in AI.streamObject(
            model: model,
            prompt: "prompt",
            as: StreamObjectContent.self,
            schema: streamObjectContentSchema()
        ) {}
    }

    #expect(await recorder.events() == [
        AIWarningLogEvent(warnings: expectedWarnings, providerID: "mock", modelID: "mock-language")
    ])
}

@Test func aiStreamObjectWarningsCallLogWarningsWithEmptyArrayLikeUpstream() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .streamStart(warnings: []),
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: #"{ "content": "Hello, world!" }"#),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
        ]
    )
    let recorder = StreamObjectWarningLogRecorder()

    try await AIWarningLogging.withLogger(recorder) {
        for try await _ in AI.streamObject(
            model: model,
            prompt: "prompt",
            as: StreamObjectContent.self,
            schema: streamObjectContentSchema()
        ) {}
    }

    #expect(await recorder.events() == [
        AIWarningLogEvent(warnings: [], providerID: "mock", modelID: "mock-language")
    ])
}
