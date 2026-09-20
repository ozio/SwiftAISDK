import Foundation
import Testing
@testable import SwiftAISDK

@Suite("CoreEvaluationTests", .serialized)
struct CoreEvaluationTests {
    @Test func evaluatesMixedQuestionsAndPreservesMetadataAndCallOptions() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_789_560_000)
        let answers = validEvaluationAnswers()
        let model = CoreEvaluationMockModel(result: AIEvaluationModelV4Result(
            answers: answers,
            usage: AIEvaluationModelUsage(inputTokens: 30, outputTokens: 4),
            warnings: [AIWarning(type: "other", message: "Provider note")],
            providerMetadata: ["test": ["confidence": 0.8]],
            response: AIResponseMetadata(
                id: "response",
                timestamp: timestamp,
                modelID: "actual-model",
                headers: ["x-request-id": "request"],
                body: ["raw": true]
            )
        ))
        let controller = AIAbortController()

        let result = try await AIWarningLogging.withLoggingDisabled {
            try await AI.experimentalEvaluate(
                model: model,
                state: ["message": "refund", "history": ["hello"]],
                questions: evaluationQuestions(),
                abortSignal: controller.signal,
                headers: ["custom": "value"],
                providerOptions: ["test": ["option": true]]
            )
        }

        #expect(model.callCount == 1)
        #expect(model.lastOptions?.state == ["message": "refund", "history": ["hello"]])
        #expect(model.lastOptions?.headers["custom"] == "value")
        #expect(model.lastOptions?.headers["user-agent"] == "ai/7.0.107")
        #expect(model.lastOptions?.providerOptions == ["test": ["option": true]])
        #expect(model.lastOptions?.abortSignal === controller.signal)
        #expect(result.answers == answers)
        #expect(result.usage == AIEvaluationUsage(inputTokens: 30, outputTokens: 4, totalTokens: 34))
        #expect(result.providerMetadata == ["test": ["confidence": 0.8]])
        #expect(result.response == AIEvaluationResponseMetadata(
            id: "response",
            timestamp: timestamp,
            modelID: "actual-model",
            headers: ["x-request-id": "request"],
            body: ["raw": true]
        ))
    }

    @Test func fillsUnknownUsageAndResponseDefaults() async throws {
        let model = CoreEvaluationMockModel(result: AIEvaluationModelV4Result(
            answers: validEvaluationAnswersWithoutDistributions(),
            warnings: []
        ))
        let before = Date()
        let result = try await AI.experimentalEvaluate(
            model: model,
            state: "",
            questions: evaluationQuestions()
        )

        #expect(result.usage == AIEvaluationUsage())
        #expect(result.response.modelID == model.modelID)
        #expect(result.response.timestamp >= before)
    }

    @Test func rejectsUnsupportedQuestionBeforeProviderIO() async {
        let model = CoreEvaluationMockModel(
            supportedQuestionTypes: [.choice, .score],
            result: AIEvaluationModelV4Result(answers: validEvaluationAnswers(), warnings: [])
        )

        await #expect(throws: AIEvaluationUnsupportedQuestionTypeError.self) {
            try await AI.experimentalEvaluate(
                model: model,
                state: "refund",
                questions: evaluationQuestions()
            )
        }
        #expect(model.callCount == 0)
    }

    @Test func rejectsUnsupportedModelVersionBeforeProviderIO() async {
        let model = CoreEvaluationMockModel(
            specificationVersion: "v3",
            result: AIEvaluationModelV4Result(answers: validEvaluationAnswers(), warnings: [])
        )

        await #expect(throws: AIEvaluationModelResolutionError.self) {
            try await AI.experimentalEvaluate(
                model: model,
                state: "refund",
                questions: evaluationQuestions()
            )
        }
        #expect(model.callCount == 0)
    }

    @Test func validatesStateAndQuestionRubricsBeforeProviderIO() async {
        let model = CoreEvaluationMockModel(result: AIEvaluationModelV4Result(
            answers: validEvaluationAnswers(),
            warnings: []
        ))

        await #expect(throws: AIError.self) {
            try await AI.experimentalEvaluate(
                model: model,
                state: 42,
                questions: evaluationQuestions()
            )
        }
        await #expect(throws: AIError.self) {
            try await AI.experimentalEvaluate(model: model, state: "text", questions: [:])
        }
        await #expect(throws: AIError.self) {
            try await AI.experimentalEvaluate(
                model: model,
                state: "text",
                questions: ["choice": .choice(instructions: "Pick", criteria: [:])]
            )
        }
        await #expect(throws: AIError.self) {
            try await AI.experimentalEvaluate(
                model: model,
                state: "text",
                questions: ["score": .score(instructions: "Rate", criteria: ["only"])]
            )
        }
        await #expect(throws: AIError.self) {
            try await AI.experimentalEvaluate(
                model: model,
                state: "text",
                questions: ["flag": .boolean(instructions: "Yes?", criteria: ["yes": "yes"])]
            )
        }
        await #expect(throws: AIError.self) {
            try await AI.experimentalEvaluate(
                model: model,
                state: ["invalid": .number(.infinity)],
                questions: evaluationQuestions()
            )
        }
        #expect(model.callCount == 0)
    }

    @Test func rejectsMalformedAnswerKeysTypesAndBoundsWithoutRetrying() async {
        let cases: [[String: AIEvaluationAnswer]] = [
            ["topic": .choice(choice: "billing")],
            validEvaluationAnswers().merging(["extra": .boolean(probability: 1)]) { _, new in new },
            validEvaluationAnswers().merging(["topic": .score(score: 1)]) { _, new in new },
            validEvaluationAnswers().merging(["topic": .choice(choice: "other")]) { _, new in new },
            validEvaluationAnswers().merging(["severity": .score(score: 3)]) { _, new in new },
            validEvaluationAnswers().merging(["refund": .boolean(probability: 1.1)]) { _, new in new }
        ]

        for answers in cases {
            let model = CoreEvaluationMockModel(result: AIEvaluationModelV4Result(answers: answers, warnings: []))
            await #expect(throws: AIError.self) {
                try await AI.experimentalEvaluate(
                    model: model,
                    state: "text",
                    questions: evaluationQuestions(),
                    maxRetries: 2
                )
            }
            #expect(model.callCount == 1)
        }
    }

    @Test func validatesCompleteDistributionsHighestChoiceAndWeightedScores() async {
        let invalidCases: [[String: AIEvaluationAnswer]] = [
            validEvaluationAnswers().merging([
                "topic": .choice(choice: "billing", probabilities: ["billing": 1])
            ]) { _, new in new },
            validEvaluationAnswers().merging([
                "topic": .choice(choice: "billing", probabilities: ["billing": 0.1, "support": 0.9])
            ]) { _, new in new },
            validEvaluationAnswers().merging([
                "severity": .score(score: 1, probabilities: ["0": 0, "1": 0, "2": 1])
            ]) { _, new in new },
            validEvaluationAnswers().merging([
                "severity": .score(score: 1, probabilities: ["0": 0.2, "1": 0.2, "2": 0.2])
            ]) { _, new in new },
            validEvaluationAnswers().merging([
                "severity": .score(score: 1, probabilities: ["0": -0.1, "1": 1.1, "2": 0])
            ]) { _, new in new }
        ]

        for answers in invalidCases {
            let model = CoreEvaluationMockModel(result: AIEvaluationModelV4Result(answers: answers, warnings: []))
            await #expect(throws: AIError.self) {
                try await AI.experimentalEvaluate(model: model, state: "text", questions: evaluationQuestions())
            }
            #expect(model.callCount == 1)
        }
    }

    @Test func honorsDeclaredRoundingWithoutRewritingProviderValues() async throws {
        let probabilities = ["0": 0.33, "1": 0.33, "2": 0.33]
        let roundedAnswers = validEvaluationAnswers().merging([
            "severity": .score(score: 1, probabilities: probabilities)
        ]) { _, new in new }
        let rounding = AIEvaluationRounding(probabilityDecimals: 2, scoreDecimals: 2)
        let model = CoreEvaluationMockModel(result: AIEvaluationModelV4Result(
            answers: roundedAnswers,
            rounding: rounding,
            warnings: []
        ))

        let result = try await AI.experimentalEvaluate(
            model: model,
            state: "text",
            questions: evaluationQuestions()
        )
        #expect(result.answers == roundedAnswers)
        #expect(result.rounding == rounding)

        let noRounding = CoreEvaluationMockModel(result: AIEvaluationModelV4Result(
            answers: roundedAnswers,
            warnings: []
        ))
        await #expect(throws: AIError.self) {
            try await AI.experimentalEvaluate(
                model: noRounding,
                state: "text",
                questions: evaluationQuestions()
            )
        }

        let invalidRounding = CoreEvaluationMockModel(result: AIEvaluationModelV4Result(
            answers: validEvaluationAnswers(),
            rounding: AIEvaluationRounding(probabilityDecimals: 16),
            warnings: []
        ))
        await #expect(throws: AIError.self) {
            try await AI.experimentalEvaluate(
                model: invalidRounding,
                state: "text",
                questions: evaluationQuestions()
            )
        }
    }

    @Test func retriesTransientProviderFailuresAndHonorsZeroRetries() async throws {
        let transient = AIError.apiCall(AIAPICallError(
            provider: "test",
            statusCode: 429,
            responseHeaders: ["retry-after-ms": "0"],
            responseBody: "Rate limited"
        ))
        let attempts = EvaluationAttemptCounter()
        let model = CoreEvaluationMockModel { _ in
            if attempts.increment() == 1 { throw transient }
            return AIEvaluationModelV4Result(answers: validEvaluationAnswers(), warnings: [])
        }

        _ = try await AI.experimentalEvaluate(
            model: model,
            state: "text",
            questions: evaluationQuestions(),
            maxRetries: 1
        )
        #expect(model.callCount == 2)

        let noRetry = CoreEvaluationMockModel { _ in throw transient }
        await #expect(throws: AIError.self) {
            try await AI.experimentalEvaluate(
                model: noRetry,
                state: "text",
                questions: evaluationQuestions(),
                maxRetries: 0
            )
        }
        #expect(noRetry.callCount == 1)
    }

    @Test func honorsAbortBeforeAndDuringProviderCalls() async {
        let beforeController = AIAbortController()
        beforeController.abort(reason: "Cancelled")
        let beforeModel = CoreEvaluationMockModel(result: AIEvaluationModelV4Result(
            answers: validEvaluationAnswers(),
            warnings: []
        ))
        await #expect(throws: AIAbortError.self) {
            try await AI.experimentalEvaluate(
                model: beforeModel,
                state: "text",
                questions: evaluationQuestions(),
                abortSignal: beforeController.signal
            )
        }
        #expect(beforeModel.callCount == 0)

        let duringController = AIAbortController()
        let duringModel = CoreEvaluationMockModel { _ in
            duringController.abort(reason: "Cancelled")
            return AIEvaluationModelV4Result(answers: validEvaluationAnswers(), warnings: [])
        }
        await #expect(throws: AIAbortError.self) {
            try await AI.experimentalEvaluate(
                model: duringModel,
                state: "text",
                questions: evaluationQuestions(),
                abortSignal: duringController.signal
            )
        }
        #expect(duringModel.callCount == 1)
    }
}

private func evaluationQuestions() -> [String: AIEvaluationQuestion] {
    [
        "topic": .choice(
            instructions: "Team?",
            criteria: ["billing": .null, "support": ["includes": ["help"]]]
        ),
        "severity": .score(
            instructions: ["Severity?"],
            criteria: ["Low", "Medium", "High"]
        ),
        "refund": .boolean(
            instructions: "Refund?",
            criteria: ["true": "Money back", "false": .null]
        )
    ]
}

private func validEvaluationAnswers() -> [String: AIEvaluationAnswer] {
    [
        "refund": .boolean(probability: 0.92),
        "severity": .score(score: 1.6, probabilities: ["0": 0, "1": 0.4, "2": 0.6]),
        "topic": .choice(choice: "billing", probabilities: ["billing": 0.9, "support": 0.1])
    ]
}

private func validEvaluationAnswersWithoutDistributions() -> [String: AIEvaluationAnswer] {
    [
        "refund": .boolean(probability: 0.92),
        "severity": .score(score: 1.4),
        "topic": .choice(choice: "support")
    ]
}

private final class CoreEvaluationMockModel: AIEvaluationModelV4, @unchecked Sendable {
    let specificationVersion: String
    let providerID = "test.evaluation"
    let modelID = "mock-model-id"
    let supportedQuestionTypes: [AIEvaluationQuestionType]

    private let lock = NSLock()
    private var calls = 0
    private var capturedOptions: AIEvaluationModelV4CallOptions?
    private let handler: @Sendable (AIEvaluationModelV4CallOptions) async throws -> AIEvaluationModelV4Result

    var callCount: Int { lock.withLock { calls } }
    var lastOptions: AIEvaluationModelV4CallOptions? { lock.withLock { capturedOptions } }

    init(
        specificationVersion: String = "v4",
        supportedQuestionTypes: [AIEvaluationQuestionType] = AIEvaluationQuestionType.allCases,
        result: AIEvaluationModelV4Result
    ) {
        self.specificationVersion = specificationVersion
        self.supportedQuestionTypes = supportedQuestionTypes
        self.handler = { _ in result }
    }

    init(
        specificationVersion: String = "v4",
        supportedQuestionTypes: [AIEvaluationQuestionType] = AIEvaluationQuestionType.allCases,
        handler: @escaping @Sendable (AIEvaluationModelV4CallOptions) async throws -> AIEvaluationModelV4Result
    ) {
        self.specificationVersion = specificationVersion
        self.supportedQuestionTypes = supportedQuestionTypes
        self.handler = handler
    }

    func doEvaluate(_ options: AIEvaluationModelV4CallOptions) async throws -> AIEvaluationModelV4Result {
        lock.withLock {
            calls += 1
            capturedOptions = options
        }
        return try await handler(options)
    }
}

private final class EvaluationAttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}
