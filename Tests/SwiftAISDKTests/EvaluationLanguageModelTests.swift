import Foundation
import Testing
@testable import SwiftAISDK

@Suite("EvaluationLanguageModelTests")
struct EvaluationLanguageModelTests {
    @Test func mapsExactLabelsAndFractionalScoresWithStrictInternalSchema() async throws {
        let languageModel = EvaluationLanguageMockModel(result: evaluationLanguageResult(
            text: "{\"q1\":1.25,\"q0\":\"c1\"}"
        ))
        let model = EvaluationLanguageModel(model: languageModel, providerID: "test.evaluation")
        let options = evaluationLanguageOptions()

        let result = try await model.doEvaluate(options)

        #expect(result.answers == [
            "category": .choice(choice: "Needs review"),
            "severity": .score(score: 1.25)
        ])
        #expect(languageModel.callCount == 1)
        let request = try #require(languageModel.lastRequest)
        #expect(request.reasoning == "none")
        #expect(request.temperature == nil)
        #expect(request.tools.isEmpty)
        guard case let .json(schema, name, description) = request.responseFormat else {
            Issue.record("Expected JSON response format")
            return
        }
        #expect(name == "evaluation")
        #expect(description == nil)
        #expect(schema?["type"] == "object")
        #expect(schema?["additionalProperties"] == false)
        #expect(schema?["required"] == ["q0", "q1"])
        #expect(schema?["properties"]?["q0"]?["enum"] == ["c0", "c1", "c2"])
        #expect(schema?["properties"]?["q1"]?["type"] == "number")

        let userMessage = try #require(request.messages.last)
        let prompt = userMessage.combinedText
        let promptJSON = try JSONDecoder().decode(JSONValue.self, from: Data(prompt.utf8))
        #expect(promptJSON["state"] == ["text": "test", "events": [1, .null]])
        #expect(promptJSON["questions"]?["q0"]?["id"] == "category")
        #expect(promptJSON["questions"]?["q0"]?["criteria"]?["c0"]?["label"] == "Needs Review")
        #expect(promptJSON["questions"]?["q0"]?["criteria"]?["c1"]?["label"] == "Needs review")
        #expect(promptJSON["questions"]?["q0"]?["criteria"]?["c2"]?["description"] == .null)
    }

    @Test func preservesUsageWarningsProviderAndResponseMetadataAndForwardsOptions() async throws {
        let timestamp = Date(timeIntervalSince1970: 0)
        let warning = AIWarning(type: "other", message: "test warning")
        let languageModel = EvaluationLanguageMockModel(result: evaluationLanguageResult(
            text: "{\"q0\":\"c1\",\"q1\":1.25}",
            usage: TokenUsage(inputTokens: 20, outputTokens: 12),
            warnings: [warning],
            providerMetadata: ["test": ["original": true]],
            responseMetadata: AIResponseMetadata(
                id: "response",
                timestamp: timestamp,
                modelID: "resolved",
                headers: ["x-request-id": "id"],
                body: ["raw": true]
            )
        ))
        let model = EvaluationLanguageModel(model: languageModel)
        let controller = AIAbortController()
        let options = AIEvaluationModelV4CallOptions(
            state: ["text": "test", "events": [1, .null]],
            questions: evaluationLanguageQuestions(),
            abortSignal: controller.signal,
            headers: ["test": "header"],
            providerOptions: ["test": ["reasoning": "low"]]
        )

        let result = try await model.doEvaluate(options)

        #expect(model.providerID == "test.language.evaluation")
        #expect(model.modelID == languageModel.modelID)
        #expect(result.usage == AIEvaluationModelUsage(inputTokens: 20, outputTokens: 12))
        #expect(result.warnings == [warning])
        #expect(result.providerMetadata == ["test": ["original": true]])
        #expect(result.response == AIResponseMetadata(
            id: "response",
            timestamp: timestamp,
            modelID: "resolved",
            headers: ["x-request-id": "id"],
            body: ["raw": true]
        ))
        #expect(languageModel.lastRequest?.abortSignal === controller.signal)
        #expect(languageModel.lastRequest?.headers == ["test": "header"])
        #expect(languageModel.lastRequest?.providerOptions == ["test": ["reasoning": "low"]])
    }

    @Test func preservesBooleanProbabilityWithoutThresholding() async throws {
        for probability in [0.0, 0.02, 0.5, 0.98, 1.0] {
            let languageModel = EvaluationLanguageMockModel(result: evaluationLanguageResult(
                text: "{\"q0\":\(probability)}"
            ))
            let model = EvaluationLanguageModel(model: languageModel)
            let result = try await model.doEvaluate(AIEvaluationModelV4CallOptions(
                state: "refund",
                questions: [
                    "flag": .boolean(
                        instructions: ["task": ["Is a refund requested?"]],
                        criteria: ["true": ["meaning": "refund"], "false": ["none"]]
                    )
                ]
            ))
            #expect(result.answers == ["flag": .boolean(probability: probability)])
            #expect(model.supportedQuestionTypes == [.choice, .score, .boolean])
        }
    }

    @Test func rejectsEmptyOrInvalidRubricsBeforeCallingLanguageModel() async {
        let languageModel = EvaluationLanguageMockModel(result: evaluationLanguageResult(text: "{}"))
        let model = EvaluationLanguageModel(model: languageModel)

        await #expect(throws: AIError.self) {
            try await model.doEvaluate(AIEvaluationModelV4CallOptions(state: "text", questions: [:]))
        }
        await #expect(throws: AIError.self) {
            try await model.doEvaluate(AIEvaluationModelV4CallOptions(
                state: "text",
                questions: ["choice": .choice(instructions: "Pick", criteria: [:])]
            ))
        }
        await #expect(throws: AIError.self) {
            try await model.doEvaluate(AIEvaluationModelV4CallOptions(
                state: "text",
                questions: ["score": .score(instructions: "Rate", criteria: ["only"])]
            ))
        }
        #expect(languageModel.callCount == 0)
    }

    @Test func rejectsUnfinishedInvalidOrOutOfRangeLanguageModelOutput() async {
        let cases: [(text: String, finishReason: String?)] = [
            ("{\"q0\":\"c1\",\"q1\":1.25}", "length"),
            ("not json", "stop"),
            ("{\"q0\":\"c1\"}", "stop"),
            ("{\"q0\":\"c9\",\"q1\":1.25}", "stop"),
            ("{\"q0\":\"c1\",\"q1\":3}", "stop")
        ]

        for item in cases {
            let languageModel = EvaluationLanguageMockModel(result: evaluationLanguageResult(
                text: item.text,
                finishReason: item.finishReason
            ))
            let model = EvaluationLanguageModel(model: languageModel)
            await #expect(throws: AIError.self) {
                try await model.doEvaluate(evaluationLanguageOptions())
            }
            #expect(languageModel.callCount == 1)
        }

        for probability in [-0.1, 1.1] {
            let languageModel = EvaluationLanguageMockModel(result: evaluationLanguageResult(
                text: "{\"q0\":\(probability)}"
            ))
            let model = EvaluationLanguageModel(model: languageModel)
            await #expect(throws: AIError.self) {
                try await model.doEvaluate(AIEvaluationModelV4CallOptions(
                    state: "text",
                    questions: ["flag": .boolean(instructions: "Yes?")]
                ))
            }
        }
    }

    @Test func joinsTextPartsAndHonorsAbortBeforeAndAfterGeneration() async throws {
        let joinedResult = TextGenerationResult(
            text: "unused",
            content: [.text("{\"q0\":"), .reasoning("ignored"), .text("0.5}")],
            finishReason: "stop",
            rawValue: [:]
        )
        let joinedLanguageModel = EvaluationLanguageMockModel(result: joinedResult)
        let joinedModel = EvaluationLanguageModel(model: joinedLanguageModel)
        let joined = try await joinedModel.doEvaluate(AIEvaluationModelV4CallOptions(
            state: "text",
            questions: ["flag": .boolean(instructions: "Yes?")]
        ))
        #expect(joined.answers == ["flag": .boolean(probability: 0.5)])

        let beforeController = AIAbortController()
        beforeController.abort(reason: "Cancelled")
        let beforeLanguageModel = EvaluationLanguageMockModel(result: joinedResult)
        await #expect(throws: AIAbortError.self) {
            try await EvaluationLanguageModel(model: beforeLanguageModel).doEvaluate(
                AIEvaluationModelV4CallOptions(
                    state: "text",
                    questions: ["flag": .boolean(instructions: "Yes?")],
                    abortSignal: beforeController.signal
                )
            )
        }
        #expect(beforeLanguageModel.callCount == 0)

        let duringController = AIAbortController()
        let duringLanguageModel = EvaluationLanguageMockModel { _ in
            duringController.abort(reason: "Cancelled")
            return joinedResult
        }
        await #expect(throws: AIAbortError.self) {
            try await EvaluationLanguageModel(model: duringLanguageModel).doEvaluate(
                AIEvaluationModelV4CallOptions(
                    state: "text",
                    questions: ["flag": .boolean(instructions: "Yes?")],
                    abortSignal: duringController.signal
                )
            )
        }
        #expect(duringLanguageModel.callCount == 1)
    }
}

private func evaluationLanguageQuestions() -> [String: AIEvaluationQuestion] {
    [
        "category": .choice(
            instructions: ["task": ["Pick the exact label"]],
            criteria: [
                "Needs Review": ["meaning": "manual"],
                "Needs review": ["automatic"],
                "other": .null
            ]
        ),
        "severity": .score(
            instructions: ["Rate the impact"],
            criteria: ["low", ["meaning": "medium"], .null]
        )
    ]
}

private func evaluationLanguageOptions() -> AIEvaluationModelV4CallOptions {
    AIEvaluationModelV4CallOptions(
        state: ["text": "test", "events": [1, .null]],
        questions: evaluationLanguageQuestions()
    )
}

private func evaluationLanguageResult(
    text: String,
    finishReason: String? = "stop",
    usage: TokenUsage? = TokenUsage(inputTokens: 20, outputTokens: 12),
    warnings: [AIWarning] = [],
    providerMetadata: [String: JSONValue] = [:],
    responseMetadata: AIResponseMetadata = AIResponseMetadata()
) -> TextGenerationResult {
    TextGenerationResult(
        text: text,
        finishReason: finishReason,
        usage: usage,
        providerMetadata: providerMetadata,
        rawValue: [:],
        warnings: warnings,
        responseMetadata: responseMetadata
    )
}

private final class EvaluationLanguageMockModel: LanguageModel, @unchecked Sendable {
    let providerID = "test.language"
    let modelID = "test-model"

    private let lock = NSLock()
    private var calls = 0
    private var capturedRequest: LanguageModelRequest?
    private let handler: @Sendable (LanguageModelRequest) async throws -> TextGenerationResult

    var callCount: Int { lock.withLock { calls } }
    var lastRequest: LanguageModelRequest? { lock.withLock { capturedRequest } }

    init(result: TextGenerationResult) {
        self.handler = { _ in result }
    }

    init(handler: @escaping @Sendable (LanguageModelRequest) async throws -> TextGenerationResult) {
        self.handler = handler
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        lock.withLock {
            calls += 1
            capturedRequest = request
        }
        return try await handler(request)
    }
}
