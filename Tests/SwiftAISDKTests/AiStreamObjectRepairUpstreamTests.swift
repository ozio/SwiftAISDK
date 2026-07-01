import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiStreamObjectRepairTextRepairsJSONParseErrorLikeUpstream() async throws {
    let originalText = #"{ "content": "provider metadata test" "#
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .responseMetadata(AIResponseMetadata(
                id: "id-0",
                timestamp: Date(timeIntervalSince1970: 0),
                modelID: "mock-model-id"
            )),
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: originalText),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
        ]
    )

    var object: ObjectGenerationResult<StreamObjectContent>?
    for try await part in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        schema: streamObjectContentSchema(),
        repairText: { context in
            #expect(context.text == originalText)
            #expect(context.errorMessage.contains("noJSON"))
            return context.text + "}"
        }
    ) {
        if case let .object(result) = part {
            object = result
        }
    }

    #expect(object?.object == StreamObjectContent(content: "provider metadata test"))
    #expect(object?.text == #"{ "content": "provider metadata test" }"#)
}

@Test func aiStreamObjectRepairTextRepairsTypeValidationErrorLikeUpstream() async throws {
    let originalText = #"{ "content-a": "provider metadata test" }"#
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .responseMetadata(AIResponseMetadata(
                id: "id-0",
                timestamp: Date(timeIntervalSince1970: 0),
                modelID: "mock-model-id"
            )),
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: originalText),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
        ]
    )

    var object: ObjectGenerationResult<StreamObjectContent>?
    for try await part in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        schema: streamObjectContentSchema(),
        repairText: { context in
            #expect(context.text == originalText)
            #expect(context.errorMessage.contains("schemaValidation"))
            #expect(context.errorMessage.contains("$.content"))
            return #"{ "content": "provider metadata test" }"#
        }
    ) {
        if case let .object(result) = part {
            object = result
        }
    }

    #expect(object?.object == StreamObjectContent(content: "provider metadata test"))
    #expect(object?.text == #"{ "content": "provider metadata test" }"#)
}

@Test func aiStreamObjectRepairTextHandlesNilRepairLikeUpstream() async throws {
    let originalText = #"{ "content-a": "provider metadata test" }"#
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .responseMetadata(AIResponseMetadata(
                id: "id-0",
                timestamp: Date(timeIntervalSince1970: 0),
                modelID: "mock-model-id"
            )),
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: originalText),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
        ]
    )

    do {
        for try await _ in AI.streamObject(
            model: model,
            prompt: "prompt",
            as: StreamObjectContent.self,
            schema: streamObjectContentSchema(),
            repairText: { context in
                #expect(context.text == originalText)
                #expect(context.errorMessage.contains("schemaValidation"))
                return nil
            }
        ) {}
        Issue.record("Expected nil repair result to keep object generation failure.")
    } catch let error as AIObjectGenerationError {
        #expect(error.provider == "mock")
        #expect(error.strategy == .object)
        #expect(error.kind == .schemaValidation)
        #expect(error.path == "$.content")
        #expect(error.text == originalText)
        #expect(error.repairAttempted)
    }
}

@Test func aiStreamObjectRepairTextRepairsMarkdownCodeBlockLikeUpstream() async throws {
    let originalText = "```json\n{ \"content\": \"test message\" }\n```"
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .responseMetadata(AIResponseMetadata(
                id: "id-0",
                timestamp: Date(timeIntervalSince1970: 0),
                modelID: "mock-model-id"
            )),
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: originalText),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
        ]
    )

    var object: ObjectGenerationResult<StreamObjectContent>?
    for try await part in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        schema: streamObjectContentSchema(),
        repairText: { context in
            #expect(context.text == originalText)
            #expect(context.errorMessage.contains("noJSON"))
            return context.text
                .replacingOccurrences(of: #"^```json\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
        }
    ) {
        if case let .object(result) = part {
            object = result
        }
    }

    #expect(object?.object == StreamObjectContent(content: "test message"))
    #expect(object?.text == #"{ "content": "test message" }"#)
}

@Test func aiStreamObjectRepairTextThrowsNoObjectGeneratedWhenParsingStillFailsLikeUpstream() async throws {
    let responseMetadata = AIResponseMetadata(
        id: "id-0",
        timestamp: Date(timeIntervalSince1970: 0),
        modelID: "mock-model-id"
    )
    let usage = TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13)
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .responseMetadata(responseMetadata),
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "{ broken json"),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: usage)
        ]
    )

    do {
        for try await _ in AI.streamObject(
            model: model,
            prompt: "prompt",
            as: StreamObjectContent.self,
            schema: streamObjectContentSchema(),
            repairText: { context in
                #expect(context.text == "{ broken json")
                return context.text + "{"
            }
        ) {}
        Issue.record("Expected repaired streamed object parsing to fail.")
    } catch let error as AIObjectGenerationError {
        #expect(error.provider == "mock")
        #expect(error.strategy == .object)
        #expect(error.kind == .noJSON)
        #expect(error.text == "{ broken json{")
        #expect(error.repairAttempted)
        #expect(error.finishReason == "stop")
        #expect(error.usage == usage)
        #expect(error.responseMetadata == responseMetadata)
    }
}
