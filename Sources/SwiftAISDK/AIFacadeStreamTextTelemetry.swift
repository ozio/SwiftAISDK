import Foundation

func streamTextWithTelemetry(
    makeStream: @escaping @Sendable () async throws -> AsyncThrowingStream<LanguageStreamPart, Error>,
    operationID: String,
    providerID: String,
    modelID: String?,
    input: JSONValue?,
    retryPolicy: AIRetryPolicy,
    telemetry: AITelemetryOptions?,
    abortSignal: AIAbortSignal? = nil
) -> AsyncThrowingStream<LanguageStreamPart, Error> {
    let dispatcher = AITelemetryDispatcher(options: telemetry)
    let callID = UUID().uuidString
    let started = DispatchTime.now().uptimeNanoseconds
    let terminalState = AIStreamTerminalState()

    return AsyncThrowingStream { continuation in
        let task = Task {
            var step = LanguageStreamToolStep()

            do {
                await dispatcher.record(telemetryEvent(
                    kind: .start,
                    callID: callID,
                    operationID: operationID,
                    providerID: providerID,
                    modelID: modelID,
                    options: telemetry,
                    maxRetries: retryPolicy.maxRetries,
                    input: input
                ))
                try validateRetryPolicy(retryPolicy)

                var errors: [String] = []
                var delay = retryPolicy.initialDelayNanoseconds
                while true {
                    var yieldedPart = false
                    do {
                        let stream = try await dispatcher.executeLanguageModelCall(
                            callID: callID,
                            operationID: operationID,
                            providerID: providerID,
                            modelID: modelID,
                            operation: makeStream
                        )
                        for try await part in stream {
                            try Task.checkCancellation()
                            yieldedPart = true
                            step.record(part)
                            continuation.yield(part)
                        }
                        let result = TextGenerationResult(
                            text: step.text,
                            reasoning: step.reasoning,
                            finishReason: step.finishReason,
                            usage: step.usage,
                            toolCalls: step.toolCalls,
                            toolApprovalRequests: step.approvalRequests,
                            toolApprovalResponses: step.approvalResponses,
                            providerMetadata: step.providerMetadata,
                            rawValue: .object([:]),
                            warnings: step.warnings,
                            requestMetadata: input.map { AIRequestMetadata(body: $0) } ?? AIRequestMetadata(),
                            responseMetadata: step.responseMetadata
                        )
                        if await terminalState.claimTerminalEvent() {
                            await dispatcher.record(telemetryEvent(
                                kind: .end,
                                callID: callID,
                                operationID: operationID,
                                providerID: providerID,
                                modelID: modelID,
                                options: telemetry,
                                maxRetries: retryPolicy.maxRetries,
                                durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                                output: textGenerationTelemetryOutput(result),
                                usage: result.usage,
                                warnings: result.warnings,
                                providerMetadata: result.providerMetadata,
                                responseMetadata: result.responseMetadata
                            ))
                            await AIWarningLogging.logWarnings(result.warnings, providerID: providerID, modelID: modelID)
                        }
                        continuation.finish()
                        return
                    } catch is CancellationError {
                        throw AIRetryError(reason: .cancelled, attempts: errors.count + 1, errors: errors)
                    } catch {
                        if yieldedPart {
                            throw error
                        }
                        errors.append(String(describing: error))
                        let attempts = errors.count
                        guard retryPolicy.maxRetries > 0 else { throw error }
                        guard isRetryable(error) else {
                            if attempts == 1 { throw error }
                            throw AIRetryError(reason: .errorNotRetryable, attempts: attempts, errors: errors)
                        }
                        guard attempts <= retryPolicy.maxRetries else {
                            throw AIRetryError(reason: .maxRetriesExceeded, attempts: attempts, errors: errors)
                        }
                        let sleepDelay = retryAfterDelayNanoseconds(from: error) ?? delay
                        await dispatcher.record(telemetryEvent(
                            kind: .retry,
                            callID: callID,
                            operationID: operationID,
                            providerID: providerID,
                            modelID: modelID,
                            options: telemetry,
                            attempt: attempts,
                            maxRetries: retryPolicy.maxRetries,
                            delayNanoseconds: sleepDelay,
                            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                            errorDescription: String(describing: error)
                        ))
                        if sleepDelay > 0 {
                            try await sleep(nanoseconds: sleepDelay, abortSignal: abortSignal)
                        }
                        delay = nextDelay(current: delay, policy: retryPolicy)
                    }
                }
            } catch {
                if isCancellationTelemetryError(error) {
                    if await terminalState.claimTerminalEvent() {
                        await dispatcher.record(telemetryEvent(
                            kind: .abort,
                            callID: callID,
                            operationID: operationID,
                            providerID: providerID,
                            modelID: modelID,
                            options: telemetry,
                            maxRetries: retryPolicy.maxRetries,
                            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                            errorDescription: String(describing: error)
                        ))
                    }
                    continuation.finish()
                } else {
                    if await terminalState.claimTerminalEvent() {
                        await dispatcher.record(telemetryEvent(
                            kind: .error,
                            callID: callID,
                            operationID: operationID,
                            providerID: providerID,
                            modelID: modelID,
                            options: telemetry,
                            maxRetries: retryPolicy.maxRetries,
                            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                            errorDescription: String(describing: error)
                        ))
                    }
                    continuation.finish(throwing: error)
                }
            }
        }

        continuation.onTermination = { termination in
            if case .cancelled = termination {
                Task {
                    if await terminalState.claimTerminalEvent() {
                        await dispatcher.record(telemetryEvent(
                            kind: .abort,
                            callID: callID,
                            operationID: operationID,
                            providerID: providerID,
                            modelID: modelID,
                            options: telemetry,
                            maxRetries: retryPolicy.maxRetries,
                            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                            errorDescription: "Stream cancelled."
                        ))
                    }
                }
            }
            task.cancel()
        }
    }
}
