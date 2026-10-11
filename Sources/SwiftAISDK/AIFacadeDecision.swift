import Foundation

private let aiDecisionUserAgent = "ai/7.0.137"

extension AI {
    /// Decides answers using a direct Decision Model V4 instance.
    public static func experimentalDecide(
        model: any AIDecisionModelV4,
        state: AIDecisionState,
        questions: [String: AIDecisionQuestion],
        maxRetries: Int? = nil,
        abortSignal: AIAbortSignal? = nil,
        headers: [String: String] = [:],
        providerOptions: [String: JSONValue] = [:],
        telemetry: Telemetry.Options? = nil,
        runtimeContext: [String: JSONValue] = [:],
        onStart: AICallback<AIDecisionStartEvent>? = nil,
        onEnd: AICallback<AIDecisionEndEvent>? = nil
    ) async throws -> AIDecisionResult {
        try await experimentalDecide(model: .model(model), state: state, questions: questions, maxRetries: maxRetries, abortSignal: abortSignal, headers: headers, providerOptions: providerOptions, telemetry: telemetry, runtimeContext: runtimeContext, onStart: onStart, onEnd: onEnd)
    }

    /// Resolves a decision model ID through the configured default provider.
    public static func experimentalDecide(
        model: String,
        state: AIDecisionState,
        questions: [String: AIDecisionQuestion],
        maxRetries: Int? = nil,
        abortSignal: AIAbortSignal? = nil,
        headers: [String: String] = [:],
        providerOptions: [String: JSONValue] = [:],
        telemetry: Telemetry.Options? = nil,
        runtimeContext: [String: JSONValue] = [:],
        onStart: AICallback<AIDecisionStartEvent>? = nil,
        onEnd: AICallback<AIDecisionEndEvent>? = nil
    ) async throws -> AIDecisionResult {
        try await experimentalDecide(model: .modelID(model), state: state, questions: questions, maxRetries: maxRetries, abortSignal: abortSignal, headers: headers, providerOptions: providerOptions, telemetry: telemetry, runtimeContext: runtimeContext, onStart: onStart, onEnd: onEnd)
    }

    /// Decides with either a direct model or a default-provider model ID.
    public static func experimentalDecide(
        model reference: AIDecisionModelReference,
        state: AIDecisionState,
        questions: [String: AIDecisionQuestion],
        maxRetries: Int? = nil,
        abortSignal: AIAbortSignal? = nil,
        headers: [String: String] = [:],
        providerOptions: [String: JSONValue] = [:],
        telemetry: Telemetry.Options? = nil,
        runtimeContext: [String: JSONValue] = [:],
        onStart: AICallback<AIDecisionStartEvent>? = nil,
        onEnd: AICallback<AIDecisionEndEvent>? = nil
    ) async throws -> AIDecisionResult {
        let model = try resolveDecisionModel(reference)
        try validateDecisionInput(state: state, questions: questions)

        for questionID in questions.keys.sorted() {
            guard let question = questions[questionID] else { continue }
            guard model.supportedQuestionTypes.contains(question.type) else {
                throw AIDecisionUnsupportedQuestionTypeError(
                    questionID: questionID,
                    questionType: question.type,
                    providerID: model.providerID,
                    modelID: model.modelID
                )
            }
        }

        let retryPolicy = try prepareRetries(maxRetries: maxRetries)
        let dispatcher = TelemetryDispatcher(options: telemetry)
        let callID = UUID().uuidString
        let started = DispatchTime.now().uptimeNanoseconds
        let filteredRuntimeContext = filterDecisionRuntimeContext(
            runtimeContext,
            include: telemetry?.includeRuntimeContext
        )
        let startEvent = AIDecisionStartEvent(
            runtimeContext: runtimeContext,
            callID: callID,
            providerID: model.providerID,
            modelID: model.modelID,
            state: state,
            questions: questions,
            maxRetries: retryPolicy.maxRetries,
            headers: headers,
            providerOptions: providerOptions
        )
        await dispatcher.record(telemetryEvent(
            kind: .start,
            callID: callID,
            operationID: startEvent.operationID,
            providerID: model.providerID,
            modelID: model.modelID,
            options: telemetry,
            maxRetries: retryPolicy.maxRetries,
            input: decisionTelemetryInput(
                state: state,
                questions: questions,
                headers: headers,
                providerOptions: providerOptions
            ),
            runtimeContext: filteredRuntimeContext
        ))
        await notify(event: startEvent, callback: onStart)

        do {
            let preparedState = try await prepareDecisionState(state, abortSignal: abortSignal)
            let callOptions = AIDecisionModelV4CallOptions(
                state: preparedState,
                questions: questions,
                abortSignal: abortSignal,
                headers: withUserAgentSuffix(headers, aiDecisionUserAgent),
                providerOptions: providerOptions
            )
            let modelCallStarted = DispatchTime.now().uptimeNanoseconds
            await dispatcher.record(telemetryEvent(
                kind: .modelCallStart,
                callID: callID,
                operationID: "ai.decide.doDecide",
                providerID: model.providerID,
                modelID: model.modelID,
                options: telemetry,
                input: decisionTelemetryInput(state: preparedState, questions: questions)
            ))
            let result = try await withRetry(policy: retryPolicy, abortSignal: abortSignal) {
                try abortSignal?.throwIfAborted()
                return try await model.doDecide(callOptions)
            }

            try abortSignal?.throwIfAborted()
            try validateDecisionAnswers(
                questions: questions,
                answers: result.answers,
                rounding: result.rounding,
                providerID: model.providerID
            )
            let refused = questions.keys.sorted().filter { result.answers[$0] == .refusal }
            guard refused.isEmpty else {
                throw AIDecisionRefusalError(questionIDs: refused, providerID: model.providerID, modelID: model.modelID)
            }
            await dispatcher.record(telemetryEvent(
                kind: .modelCallEnd,
                callID: callID,
                operationID: "ai.decide.doDecide",
                providerID: model.providerID,
                modelID: model.modelID,
                options: telemetry,
                durationNanoseconds: DispatchTime.now().uptimeNanoseconds - modelCallStarted,
                input: decisionTelemetryInput(state: preparedState, questions: questions),
                output: decisionModelTelemetryOutput(result),
                usage: decisionTokenUsage(result.usage),
                warnings: result.warnings,
                providerMetadata: result.providerMetadata,
                responseMetadata: result.response ?? AIResponseMetadata()
            ))
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
            let decisionResult = AIDecisionResult(
                answers: result.answers,
                usage: AIDecisionUsage(
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    totalTokens: totalTokens
                ),
                warnings: result.warnings,
                rounding: result.rounding,
                providerMetadata: result.providerMetadata,
                response: AIDecisionResponseMetadata(
                    id: response.id,
                    timestamp: response.timestamp ?? Date(),
                    modelID: response.modelID ?? model.modelID,
                    headers: response.headers,
                    body: response.body
                )
            )
            await notify(event: AIDecisionEndEvent(
                runtimeContext: runtimeContext,
                callID: callID,
                providerID: model.providerID,
                modelID: model.modelID,
                state: state,
                questions: questions,
                maxRetries: retryPolicy.maxRetries,
                headers: headers,
                providerOptions: providerOptions,
                answers: decisionResult.answers,
                usage: decisionResult.usage,
                warnings: decisionResult.warnings,
                rounding: decisionResult.rounding,
                providerMetadata: decisionResult.providerMetadata,
                response: decisionResult.response
            ), callback: onEnd)
            await dispatcher.record(telemetryEvent(
                kind: .end,
                callID: callID,
                operationID: "ai.decide",
                providerID: model.providerID,
                modelID: model.modelID,
                options: telemetry,
                maxRetries: retryPolicy.maxRetries,
                durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                input: decisionTelemetryInput(state: state, questions: questions, headers: headers, providerOptions: providerOptions),
                output: decisionResultTelemetryOutput(decisionResult),
                usage: decisionTokenUsage(decisionResult.usage),
                warnings: decisionResult.warnings,
                providerMetadata: decisionResult.providerMetadata,
                responseMetadata: decisionResponseMetadata(decisionResult.response),
                runtimeContext: filteredRuntimeContext
            ))
            return decisionResult
        } catch {
            await dispatcher.record(telemetryEvent(
                kind: .error,
                callID: callID,
                operationID: "ai.decide",
                providerID: model.providerID,
                modelID: model.modelID,
                options: telemetry,
                maxRetries: retryPolicy.maxRetries,
                durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                errorDescription: String(describing: error),
                runtimeContext: filteredRuntimeContext
            ))
            throw error
        }
    }
}
