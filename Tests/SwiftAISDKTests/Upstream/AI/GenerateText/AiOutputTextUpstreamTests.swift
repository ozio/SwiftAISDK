import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiOutputTextReturnsTextAndStreamsPartialsLikeUpstream() async throws {
    let generateModel = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: "some output",
        finishReason: "length",
        usage: TokenUsage(inputTokens: 1, outputTokens: 2, totalTokens: 3),
        rawValue: .object([:])
    ))
    let generated = try await AI.generateText(
        model: generateModel,
        prompt: "Return text.",
        output: Output.text()
    )

    #expect(generated.output == "some output")
    #expect(generated.rawOutput == "some output")
    #expect(generated.finishReason == "length")
    #expect(generated.usage == TokenUsage(inputTokens: 1, outputTokens: 2, totalTokens: 3))
    #expect(generateModel.requests.first?.responseFormat == .text)

    let streamModel = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta("partial "),
            .textDelta("text"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 2))
        ]
    )
    var partials: [String] = []
    var output: AIOutputGenerationResult<String>?
    for try await part in AI.streamText(
        model: streamModel,
        prompt: "Stream text.",
        output: Output.text()
    ) {
        switch part {
        case let .partialOutput(partial):
            partials.append(partial)
        case let .output(result):
            output = result
        default:
            break
        }
    }

    #expect(partials == ["partial ", "partial text"])
    #expect(output?.output == "partial text")
    #expect(output?.rawOutput == "partial text")
    #expect(streamModel.streamRequests.first?.responseFormat == .text)
}

@Test func aiOutputTextStreamFiltersEmptyTextDeltasAndExcludesReasoningLikeUpstream() async throws {
    let streamModel = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta("Hello"),
            .textDelta(""),
            .reasoningDelta("thinking"),
            .textDeltaPart(id: "text-1", delta: ", world!", providerMetadata: ["provider": .string("metadata")]),
            .textDeltaPart(id: "text-1", delta: "", providerMetadata: [:]),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 4))
        ]
    )
    var textDeltas: [String] = []
    var partials: [String] = []
    var rawReasoning: [LanguageStreamPart] = []
    var output: AIOutputGenerationResult<String>?

    for try await part in AI.streamText(
        model: streamModel,
        prompt: "Stream text.",
        output: Output.text()
    ) {
        switch part {
        case let .textDelta(delta):
            textDeltas.append(delta)
        case let .partialOutput(partial):
            partials.append(partial)
        case let .raw(rawPart):
            rawReasoning.append(rawPart)
        case let .output(result):
            output = result
        default:
            break
        }
    }

    #expect(textDeltas == ["Hello", ", world!"])
    #expect(partials == ["Hello", "Hello, world!"])
    #expect(rawReasoning == [.reasoningDelta("thinking")])
    #expect(output?.text == "Hello, world!")
    #expect(output?.output == "Hello, world!")
    #expect(output?.reasoning == "thinking")
    #expect(output?.usage == TokenUsage(totalTokens: 4))
}

@Test func aiOutputTextStreamExposesWarningsUsageFinishReasonAndProviderMetadataLikeUpstream() async throws {
    let warning = AIWarning(type: "other", message: "test-warning")
    let usage = TokenUsage(
        inputTokens: 3,
        outputTokens: 10,
        totalTokens: 13,
        inputTokensNoCache: 3,
        outputTextTokens: 10
    )
    let providerMetadata: [String: JSONValue] = [
        "testProvider": ["testKey": "testValue"]
    ]
    let streamModel = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .streamStart(warnings: [warning]),
            .textStart(id: "text-1"),
            .textDeltaPart(id: "text-1", delta: "Hello"),
            .textEnd(id: "text-1"),
            .finishMetadata(reason: "stop", usage: usage, providerMetadata: providerMetadata)
        ]
    )
    var warnings: [AIWarning] = []
    var output: AIOutputGenerationResult<String>?
    var finish: (reason: String?, usage: TokenUsage?)?

    for try await part in AI.streamText(
        model: streamModel,
        prompt: "Stream text.",
        output: Output.text()
    ) {
        switch part {
        case let .warning(warning):
            warnings.append(warning)
        case let .output(result):
            output = result
        case let .finish(reason, usage):
            finish = (reason, usage)
        default:
            break
        }
    }

    #expect(warnings == [warning])
    #expect(output?.warnings == [warning])
    #expect(output?.usage == usage)
    #expect(output?.finishReason == "stop")
    #expect(output?.providerMetadata == providerMetadata)
    #expect(finish?.reason == "stop")
    #expect(finish?.usage == usage)
}

@Test func aiOutputTextStreamExposesResponseMetadataLikeUpstream() async throws {
    let responseMetadata = AIResponseMetadata(
        id: "id-0",
        timestamp: Date(timeIntervalSince1970: 0),
        modelID: "mock-model-id",
        headers: ["call": "2"]
    )
    let streamModel = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .responseMetadata(responseMetadata),
            .textStart(id: "text-1"),
            .textDeltaPart(id: "text-1", delta: "Hello"),
            .textEnd(id: "text-1"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 13))
        ]
    )
    var streamedResponseMetadata: AIResponseMetadata?
    var output: AIOutputGenerationResult<String>?

    for try await part in AI.streamText(
        model: streamModel,
        prompt: "Stream text.",
        output: Output.text()
    ) {
        switch part {
        case let .responseMetadata(metadata):
            streamedResponseMetadata = metadata
        case let .output(result):
            output = result
        default:
            break
        }
    }

    #expect(streamedResponseMetadata == responseMetadata)
    #expect(output?.text == "Hello")
    #expect(output?.responseMetadata == responseMetadata)
}

@Test func aiOutputTextStreamExposesSourcesAndFilesLikeUpstream() async throws {
    let source = AISource(
        id: "source-0",
        sourceType: "url",
        url: "https://example.com/0",
        title: "Source 0"
    )
    let file = AIStreamFile(
        mediaType: "text/plain",
        data: Data("step-0".utf8)
    )
    let streamModel = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .source(source),
            .file(file),
            .textStart(id: "text-1"),
            .textDeltaPart(id: "text-1", delta: "Hello"),
            .textEnd(id: "text-1"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 13))
        ]
    )
    var sources: [AISource] = []
    var rawParts: [LanguageStreamPart] = []
    var output: AIOutputGenerationResult<String>?

    for try await part in AI.streamText(
        model: streamModel,
        prompt: "Stream text.",
        output: Output.text()
    ) {
        switch part {
        case let .source(source):
            sources.append(source)
        case let .raw(rawPart):
            rawParts.append(rawPart)
        case let .output(result):
            output = result
        default:
            break
        }
    }

    #expect(sources == [source])
    #expect(rawParts == [
        .file(file),
        .textStart(id: "text-1"),
        .textEnd(id: "text-1")
    ])
    #expect(output?.textResult.sources == [source])
    #expect(output?.textResult.files == [file])
    #expect(output?.textResult.content == [
        .text("Hello"),
        .source(source),
        .file(file)
    ])
}

@Test func aiOutputTextStreamForwardsErrorPartsAndFinishesLikeUpstream() async throws {
    let streamModel = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textStart(id: "text-1"),
            .textDeltaPart(id: "text-1", delta: "Hello"),
            .error(message: "chunk error", rawValue: ["code": "bad-chunk"]),
            .finish(reason: "error", usage: TokenUsage(totalTokens: 5))
        ]
    )
    var rawParts: [LanguageStreamPart] = []
    var output: AIOutputGenerationResult<String>?
    var finish: (reason: String?, usage: TokenUsage?)?

    for try await part in AI.streamText(
        model: streamModel,
        prompt: "Stream text.",
        output: Output.text()
    ) {
        switch part {
        case let .raw(rawPart):
            rawParts.append(rawPart)
        case let .output(result):
            output = result
        case let .finish(reason, usage):
            finish = (reason, usage)
        default:
            break
        }
    }

    #expect(rawParts == [
        .textStart(id: "text-1"),
        .error(message: "chunk error", rawValue: ["code": "bad-chunk"])
    ])
    #expect(output?.text == "Hello")
    #expect(output?.finishReason == "error")
    #expect(output?.usage == TokenUsage(totalTokens: 5))
    #expect(finish?.reason == "error")
    #expect(finish?.usage == TokenUsage(totalTokens: 5))
}
