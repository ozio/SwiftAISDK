import Foundation
import Testing
@testable import SwiftAISDK

@Suite("DecisionValidationTests")
struct DecisionValidationTests {
    @Test(arguments: [
        AIDecisionState.object(["value": .number(.nan)]),
        .parts([.json(["value": .number(.infinity)])]),
        .parts([.file(mediaType: "", data: .data(Data()))]),
        .parts([.file(mediaType: "image/png", data: .data(Data()), providerOptions: ["openai": ["value": .number(.nan)]])]),
        .parts([.file(mediaType: "image/png", data: .url(URL(fileURLWithPath: "/tmp/evidence.png")))])
    ])
    func invalidStateFailsBeforeIO(state: AIDecisionState) async {
        let model = DecisionTestModel()
        await #expect(throws: AIError.self) {
            try await AI.experimentalDecide(model: model, state: state, questions: decisionTestQuestions)
        }
        #expect(model.callCount == 0)
    }

    @Test(arguments: [
        [String: AIDecisionQuestion](),
        ["flag": .boolean(instructions: .null)],
        ["flag": .boolean(instructions: "True?", criteria: ["yes": "yes"])],
        ["choice": .choice(instructions: "Pick", criteria: [:])],
        ["choice": .choice(instructions: "Pick", criteria: ["a": 42])],
        ["score": .score(instructions: "Rate", criteria: ["Only one"])],
        ["score": .score(instructions: "Rate", criteria: ["Low", ["bad": .number(.nan)]])]
    ])
    func invalidQuestionsFailBeforeIO(questions: [String: AIDecisionQuestion]) async {
        let model = DecisionTestModel()
        await #expect(throws: AIError.self) {
            try await AI.experimentalDecide(model: model, state: "text", questions: questions)
        }
        #expect(model.callCount == 0)
    }

    @Test(arguments: [
        [String: AIDecisionAnswer](),
        ["extra": .boolean(probability: 1)],
        ["choice": .score(score: 1)],
        ["choice": .choice(choice: "other")],
        ["choice": .choice(choice: "a", probabilities: ["a": 1])],
        ["choice": .choice(choice: "a", probabilities: ["a": 0.1, "b": 0.9])],
        ["choice": .choice(choice: "a", probabilities: ["a": .nan, "b": 0])],
        ["score": .score(score: 3)],
        ["score": .score(score: .nan)],
        ["score": .score(score: 1, probabilities: ["0": 0, "1": 0, "2": 1])],
        ["score": .score(score: 1, probabilities: ["0": 0.2, "1": 0.2, "2": 0.2])],
        ["score": .score(score: 1, probabilities: ["0": -0.1, "1": 1.1, "2": 0])],
        ["flag": .boolean(probability: .infinity)],
        ["flag": .boolean(probability: 1.1)]
    ])
    func malformedAnswersFailWithoutRetry(overrides: [String: AIDecisionAnswer]) async {
        let answers = overrides.isEmpty ? overrides : decisionTestAnswers.merging(overrides) { _, newer in newer }
        let model = DecisionTestModel(result: AIDecisionModelV4Result(answers: answers))
        await #expect(throws: AIError.self) {
            try await AI.experimentalDecide(model: model, state: "text", questions: decisionTestQuestions)
        }
        #expect(model.callCount == 1)
    }

    @Test func nativeRoundedScoreAndDistributionAreNeverRewritten() async throws {
        let answers: [String: AIDecisionAnswer] = ["score": .score(score: 0.97, probabilities: ["0": 0.13, "1": 0.76, "2": 0.11])]
        let rounding = AIDecisionRounding(probabilityDecimals: 2, scoreDecimals: 2)
        let questions = ["score": try #require(decisionTestQuestions["score"])]
        let model = DecisionTestModel(result: AIDecisionModelV4Result(answers: answers, rounding: rounding))
        let result = try await AI.experimentalDecide(model: model, state: "text", questions: questions)
        #expect(result.answers == answers)
        #expect(result.rounding == rounding)
        let unrounded = DecisionTestModel(result: AIDecisionModelV4Result(answers: answers))
        await #expect(throws: AIError.self) {
            try await AI.experimentalDecide(model: unrounded, state: "text", questions: questions)
        }
    }

    @Test func roundedSumAcceptedOnlyWithinDeclaredPrecision() throws {
        let answers: [String: AIDecisionAnswer] = ["score": .score(score: 1, probabilities: ["0": 0.33, "1": 0.33, "2": 0.33])]
        let questions = ["score": try #require(decisionTestQuestions["score"])]
        try validateDecisionAnswers(questions: questions, answers: answers, rounding: .init(probabilityDecimals: 2, scoreDecimals: 2), providerID: "test")
        #expect(throws: AIError.self) {
            try validateDecisionAnswers(questions: questions, answers: ["score": .score(score: 1.5, probabilities: ["0": 0.33, "1": 0.33, "2": 0.33])], rounding: .init(probabilityDecimals: 2, scoreDecimals: 2), providerID: "test")
        }
    }

    @Test(arguments: [-1, 16])
    func invalidRoundingRejected(decimals: Int) {
        #expect(throws: AIError.self) {
            try validateDecisionAnswers(questions: decisionTestQuestions, answers: decisionTestAnswers, rounding: .init(probabilityDecimals: decimals), providerID: "test")
        }
        #expect(throws: AIError.self) {
            try validateDecisionAnswers(questions: decisionTestQuestions, answers: decisionTestAnswers, rounding: .init(scoreDecimals: decimals), providerID: "test")
        }
    }

    @Test func publishedChoiceMaximumRemainsStrictEvenWithDeclaredRounding() {
        // The monorepo fixture is ahead of ai@7.0.137; published code allows only 1e-6 here.
        let questions: [String: AIDecisionQuestion] = ["choice": .choice(instructions: "Pick", criteria: ["a": .null, "b": .null, "c": .null])]
        #expect(throws: AIError.self) {
            try validateDecisionAnswers(questions: questions, answers: ["choice": .choice(choice: "b", probabilities: ["a": 0.44, "b": 0.43, "c": 0.13])], rounding: .init(probabilityDecimals: 2), providerID: "test")
        }
    }

    @Test func toleranceAndUnusualKeysPreserveNativeValues() throws {
        let questions: [String: AIDecisionQuestion] = ["__proto__": .choice(instructions: "Pick", criteria: ["__proto__": .null, "constructor": .null])]
        try validateDecisionAnswers(questions: questions, answers: ["__proto__": .choice(choice: "__proto__")], rounding: nil, providerID: "test")
        try validateDecisionAnswers(questions: ["score": try #require(decisionTestQuestions["score"])], answers: ["score": .score(score: 1, probabilities: ["0": 0.3333333, "1": 0.3333333, "2": 0.3333333])], rounding: nil, providerID: "test")
    }

    @Test func refusalsAreValidRawAnswersForAnyQuestionType() throws {
        try validateDecisionAnswers(questions: decisionTestQuestions, answers: decisionTestQuestions.mapValues { _ in .refusal }, rounding: nil, providerID: "test")
    }
}
