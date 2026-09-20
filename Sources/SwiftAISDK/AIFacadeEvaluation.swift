import Foundation

private let aiEvaluationUserAgent = "ai/7.0.107"

extension AI {
    /// Evaluates a map of typed questions against one shared state.
    public static func experimentalEvaluate(
        model: any AIEvaluationModelV4,
        state: JSONValue,
        questions: [String: AIEvaluationQuestion],
        maxRetries: Int? = nil,
        abortSignal: AIAbortSignal? = nil,
        headers: [String: String] = [:],
        providerOptions: [String: JSONValue] = [:]
    ) async throws -> AIEvaluationResult {
        try await experimentalEvaluate(
            model: .model(model),
            state: state,
            questions: questions,
            maxRetries: maxRetries,
            abortSignal: abortSignal,
            headers: headers,
            providerOptions: providerOptions
        )
    }

    /// Resolves an evaluation model ID through the configured default provider.
    public static func experimentalEvaluate(
        model: String,
        state: JSONValue,
        questions: [String: AIEvaluationQuestion],
        maxRetries: Int? = nil,
        abortSignal: AIAbortSignal? = nil,
        headers: [String: String] = [:],
        providerOptions: [String: JSONValue] = [:]
    ) async throws -> AIEvaluationResult {
        try await experimentalEvaluate(
            model: .modelID(model),
            state: state,
            questions: questions,
            maxRetries: maxRetries,
            abortSignal: abortSignal,
            headers: headers,
            providerOptions: providerOptions
        )
    }

    /// Evaluates with either a direct model or a default-provider model ID.
    public static func experimentalEvaluate(
        model reference: AIEvaluationModelReference,
        state: JSONValue,
        questions: [String: AIEvaluationQuestion],
        maxRetries: Int? = nil,
        abortSignal: AIAbortSignal? = nil,
        headers: [String: String] = [:],
        providerOptions: [String: JSONValue] = [:]
    ) async throws -> AIEvaluationResult {
        let model = try resolveEvaluationModel(reference)
        try validateEvaluationInput(state: state, questions: questions)

        for questionID in questions.keys.sorted() {
            guard let question = questions[questionID] else { continue }
            guard model.supportedQuestionTypes.contains(question.type) else {
                throw AIEvaluationUnsupportedQuestionTypeError(
                    questionID: questionID,
                    questionType: question.type,
                    providerID: model.providerID,
                    modelID: model.modelID
                )
            }
        }

        let retryPolicy = try prepareRetries(maxRetries: maxRetries)
        let callOptions = AIEvaluationModelV4CallOptions(
            state: state,
            questions: questions,
            abortSignal: abortSignal,
            headers: withUserAgentSuffix(headers, aiEvaluationUserAgent),
            providerOptions: providerOptions
        )
        let result = try await withRetry(policy: retryPolicy, abortSignal: abortSignal) {
            try abortSignal?.throwIfAborted()
            return try await model.doEvaluate(callOptions)
        }

        try abortSignal?.throwIfAborted()
        try validateEvaluationAnswers(
            questions: questions,
            answers: result.answers,
            rounding: result.rounding,
            providerID: model.providerID
        )
        await AIWarningLogging.logWarnings(
            result.warnings,
            providerID: model.providerID,
            modelID: model.modelID
        )

        let inputTokens = result.usage?.inputTokens
        let outputTokens = result.usage?.outputTokens
        let totalTokens: Int?
        if let inputTokens, let outputTokens {
            let total = inputTokens.addingReportingOverflow(outputTokens)
            totalTokens = total.overflow ? nil : total.partialValue
        } else {
            totalTokens = nil
        }

        let response = result.response ?? AIResponseMetadata()
        return AIEvaluationResult(
            answers: result.answers,
            usage: AIEvaluationUsage(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                totalTokens: totalTokens
            ),
            warnings: result.warnings,
            rounding: result.rounding,
            providerMetadata: result.providerMetadata,
            response: AIEvaluationResponseMetadata(
                id: response.id,
                timestamp: response.timestamp ?? Date(),
                modelID: response.modelID ?? model.modelID,
                headers: response.headers,
                body: response.body
            )
        )
    }
}
