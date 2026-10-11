import Foundation
import Testing
@testable import SwiftAISDK

@Suite("DecisionCoreTests", .serialized)
struct DecisionCoreTests {
    @Test func mixedQuestionsPreserveValuesMetadataAndOptions() async throws {
        let date = Date(timeIntervalSince1970: 100)
        let model = DecisionTestModel(result: AIDecisionModelV4Result(
            answers: decisionTestAnswers,
            rounding: AIDecisionRounding(probabilityDecimals: 2, scoreDecimals: 2),
            usage: AIDecisionModelUsage(inputTokens: 30, outputTokens: 4),
            warnings: [AIWarning(type: "other", message: "provider note")],
            providerMetadata: ["test": ["confidence": 0.8]],
            response: AIResponseMetadata(id: "id", timestamp: date, modelID: "resolved", headers: ["x-test": "header"], body: ["raw": true])
        ))
        let controller = AIAbortController()
        let result = try await AIWarningLogging.withLoggingDisabled {
            try await AI.experimentalDecide(
                model: model,
                state: .object(["message": "refund"]),
                questions: decisionTestQuestions,
                abortSignal: controller.signal,
                headers: ["x-custom": "value"],
                providerOptions: ["test": ["effort": "high"]]
            )
        }
        #expect(result.answers == decisionTestAnswers)
        #expect(result.usage == AIDecisionUsage(inputTokens: 30, outputTokens: 4, totalTokens: 34))
        #expect(result.rounding == AIDecisionRounding(probabilityDecimals: 2, scoreDecimals: 2))
        #expect(result.response == AIDecisionResponseMetadata(id: "id", timestamp: date, modelID: "resolved", headers: ["x-test": "header"], body: ["raw": true]))
        #expect(model.callCount == 1)
        #expect(model.lastOptions?.state == [.json(["message": "refund"])])
        #expect(model.lastOptions?.abortSignal === controller.signal)
        #expect(model.lastOptions?.headers["x-custom"] == "value")
        #expect(model.lastOptions?.headers["user-agent"] == "ai/7.0.137")
        #expect(model.lastOptions?.providerOptions == ["test": ["effort": "high"]])
    }

    @Test func unknownUsageStaysUnknownAndTimestampAndModelDefault() async throws {
        let model = DecisionTestModel(result: AIDecisionModelV4Result(answers: ["flag": .boolean(probability: 0.5)]))
        let before = Date()
        let result = try await AI.experimentalDecide(model: model, state: "", questions: ["flag": .boolean(instructions: "Flag?")])
        #expect(result.usage == AIDecisionUsage())
        #expect(result.response.timestamp >= before)
        #expect(result.response.modelID == model.modelID)
        #expect(model.lastOptions?.state == [.text("")])
    }

    @Test func partialAndOverflowUsageNeverInventTotal() async throws {
        for usage in [AIDecisionModelUsage(inputTokens: 0), AIDecisionModelUsage(outputTokens: 0), AIDecisionModelUsage(inputTokens: Int.max, outputTokens: 1)] {
            let model = DecisionTestModel(result: AIDecisionModelV4Result(answers: ["flag": .boolean(probability: 1)], usage: usage))
            let result = try await AI.experimentalDecide(model: model, state: "yes", questions: ["flag": .boolean(instructions: "Flag?")])
            #expect(result.usage.inputTokens == usage.inputTokens)
            #expect(result.usage.outputTokens == usage.outputTokens)
            #expect(result.usage.totalTokens == nil)
        }
    }

    @Test func rejectsUnsupportedTypesBeforeAnyProviderCall() async {
        let model = DecisionTestModel(supportedQuestionTypes: [.choice, .score])
        await #expect(throws: AIDecisionUnsupportedQuestionTypeError.self) {
            try await AI.experimentalDecide(model: model, state: "", questions: decisionTestQuestions)
        }
        #expect(model.callCount == 0)
    }

    @Test func rejectsUnsupportedModelVersionBeforeIO() async {
        let model = DecisionTestModel(specificationVersion: "v99")
        await #expect(throws: AIDecisionModelResolutionError.self) {
            try await AI.experimentalDecide(model: model, state: "", questions: decisionTestQuestions)
        }
        #expect(model.callCount == 0)
    }

    @Test(arguments: [["flag"], ["score"], ["choice"], ["choice", "flag"]])
    func refusalFailsEntireOperationWithoutRetry(refused: [String]) async throws {
        var answers = decisionTestAnswers
        for id in refused { answers[id] = .refusal }
        let model = DecisionTestModel(result: AIDecisionModelV4Result(answers: answers))
        do {
            _ = try await AI.experimentalDecide(model: model, state: "", questions: decisionTestQuestions)
            Issue.record("Expected refusal")
        } catch let error as AIDecisionRefusalError {
            #expect(error.questionIDs == refused.sorted())
            #expect(error.providerID == model.providerID)
            #expect(error.modelID == model.modelID)
        }
        #expect(model.callCount == 1)
    }

    @Test func invalidResponseIsOutsideRetryBoundary() async {
        let model = DecisionTestModel(result: AIDecisionModelV4Result(answers: [:]))
        await #expect(throws: AIError.self) {
            try await AI.experimentalDecide(model: model, state: "", questions: decisionTestQuestions)
        }
        #expect(model.callCount == 1)
    }

    @Test func retriesTransientErrorsAndPreservesLogicalCall() async throws {
        let model = DecisionTestModel(failures: [.apiCall(AIAPICallError(provider: "test", statusCode: 503, responseBody: "busy"))])
        _ = try await AI.experimentalDecide(model: model, state: "", questions: decisionTestQuestions, maxRetries: 1)
        #expect(model.callCount == 2)
    }

    @Test func zeroRetriesAndPreAbortedCallsDoNotRetry() async {
        let model = DecisionTestModel(failures: [.apiCall(AIAPICallError(provider: "test", statusCode: 503, responseBody: "busy"))])
        await #expect(throws: AIError.self) {
            try await AI.experimentalDecide(model: model, state: "", questions: decisionTestQuestions, maxRetries: 0)
        }
        #expect(model.callCount == 1)
        let controller = AIAbortController()
        controller.abort()
        let aborted = DecisionTestModel()
        await #expect(throws: AIAbortError.self) {
            try await AI.experimentalDecide(model: aborted, state: "", questions: decisionTestQuestions, abortSignal: controller.signal)
        }
        #expect(aborted.callCount == 0)
    }

    @Test func cancellationAfterProviderReturnDoesNotReturnResult() async {
        let controller = AIAbortController()
        let model = DecisionTestModel(handler: { _ in controller.abort(); return AIDecisionModelV4Result(answers: decisionTestAnswers) })
        await #expect(throws: AIAbortError.self) {
            try await AI.experimentalDecide(model: model, state: "", questions: decisionTestQuestions, abortSignal: controller.signal)
        }
        #expect(model.callCount == 1)
    }

    @Test func orderedStateRetainsEmptyTextJSONAndNormalizesImages() async throws {
        let model = DecisionTestModel()
        let bytes = Data([0x89, 0x50, 0x4e, 0x47])
        let state: [AIDecisionStatePart] = [
            .text(""), .json([1, .null, ["label": "package"]]),
            .file(mediaType: "image", data: .data(bytes), filename: "package.png"),
            .file(mediaType: "image", data: .url(try #require(URL(string: "data:image/png;base64,iVBORw==")))),
            .text("Inspect both.")
        ]
        _ = try await AI.experimentalDecide(model: model, state: .parts(state), questions: decisionTestQuestions)
        #expect(model.lastOptions?.state == [
            .text(""), .json([1, .null, ["label": "package"]]),
            .file(mediaType: "image/png", data: .data(bytes), filename: "package.png"),
            .file(mediaType: "image/png", data: .base64("iVBORw==")), .text("Inspect both.")
        ])
    }

    @Test func emptyPartsRemainEmpty() async throws {
        let model = DecisionTestModel()
        _ = try await AI.experimentalDecide(model: model, state: .parts([]), questions: decisionTestQuestions)
        #expect(model.lastOptions?.state == [])
    }

    @Test func downloadsURLBeforeCallingProviderAndPreservesFileOptions() async throws {
        let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png; charset=utf-8"], body: Data([0x89, 0x50, 0x4e, 0x47])))
        let url = try #require(URL(string: "https://example.com/package.png"))
        let parts = try await prepareDecisionState(.parts([.file(mediaType: "image", data: .url(url), filename: "package.png", providerOptions: ["openai": ["imageDetail": "high"]])]), abortSignal: nil, transport: transport)
        #expect(parts == [.file(mediaType: "image/png", data: .data(Data([0x89, 0x50, 0x4e, 0x47])), filename: "package.png", providerOptions: ["openai": ["imageDetail": "high"]])])
        #expect(await transport.requests().count == 1)
    }

    @Test func downloadFailureNeverProducesPreparedEvidence() async throws {
        let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 404, headers: [:], body: Data()))
        await #expect(throws: AIDownloadError.self) {
            try await prepareDecisionState(.parts([.file(mediaType: "image/png", data: .url(try #require(URL(string: "https://example.com/missing.png"))))]), abortSignal: nil, transport: transport)
        }
    }
}

let decisionTestQuestions: [String: AIDecisionQuestion] = [
    "choice": .choice(instructions: "Pick", criteria: ["a": .null, "b": "Other"]),
    "score": .score(instructions: "Rate", criteria: ["Poor", "Fair", "Great"]),
    "flag": .boolean(instructions: "True?")
]
let decisionTestAnswers: [String: AIDecisionAnswer] = [
    "choice": .choice(choice: "a", probabilities: ["a": 0.7, "b": 0.3]),
    "score": .score(score: 1.8, probabilities: ["0": 0.05, "1": 0.1, "2": 0.85]),
    "flag": .boolean(probability: 0.85)
]

final class DecisionTestModel: AIDecisionModelV4, @unchecked Sendable {
    let specificationVersion: String
    let providerID = "test.decision"
    let modelID = "test-model"
    let supportedQuestionTypes: [AIDecisionQuestionType]
    private let lock = NSLock()
    private var calls: [AIDecisionModelV4CallOptions] = []
    private var failures: [AIError]
    private let result: AIDecisionModelV4Result
    private let handler: (@Sendable (AIDecisionModelV4CallOptions) async throws -> AIDecisionModelV4Result)?
    var callCount: Int { lock.withLock { calls.count } }
    var lastOptions: AIDecisionModelV4CallOptions? { lock.withLock { calls.last } }
    init(specificationVersion: String = "v4", supportedQuestionTypes: [AIDecisionQuestionType] = [.choice, .score, .boolean], result: AIDecisionModelV4Result = AIDecisionModelV4Result(answers: decisionTestAnswers), failures: [AIError] = [], handler: (@Sendable (AIDecisionModelV4CallOptions) async throws -> AIDecisionModelV4Result)? = nil) {
        self.specificationVersion = specificationVersion
        self.supportedQuestionTypes = supportedQuestionTypes
        self.result = result
        self.failures = failures
        self.handler = handler
    }
    func doDecide(_ options: AIDecisionModelV4CallOptions) async throws -> AIDecisionModelV4Result {
        let error = lock.withLock { () -> AIError? in
            calls.append(options)
            return failures.isEmpty ? nil : failures.removeFirst()
        }
        if let error { throw error }
        if let handler { return try await handler(options) }
        return result
    }
}
