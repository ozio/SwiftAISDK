import Foundation

// Keep the original internal configuration name for existing provider construction.
typealias TypeSafeAIEvaluationModelConfiguration = TypeSafeAIDecisionModelConfiguration

/// Compatibility Evaluation adapter backed by TypeSafe's native decision implementation.
public final class TypeSafeAIEvaluationModel: AIEvaluationModelV4, @unchecked Sendable {
    public let specificationVersion = "v4"
    public let supportedQuestionTypes: [AIEvaluationQuestionType] = [.choice, .score, .boolean]
    private let decision: TypeSafeAIDecisionModel
    public var providerID: String { decision.providerID }
    public var modelID: String { decision.modelID }

    init(modelID: String, configuration: TypeSafeAIEvaluationModelConfiguration) {
        decision = TypeSafeAIDecisionModel(modelID: modelID, configuration: configuration)
    }
    public func doEvaluate(_ options: AIEvaluationModelV4CallOptions) async throws -> AIEvaluationModelV4Result {
        let result = try await decision.doDecide(options.decisionOptions)
        return try evaluationResult(from: result, providerID: providerID, modelID: modelID)
    }
}
