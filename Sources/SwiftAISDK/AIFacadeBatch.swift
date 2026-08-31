import Foundation

private let aiBatchUserAgent = "ai/7.0.85"

extension AI {
    /// Source-compatible overload retained from Batch V4 before completion
    /// webhooks were added.
    public static func startTextBatch(
        model: any LanguageModel,
        requests: [TextBatchRequest],
        providerOptions: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        idempotencyKey: String? = nil,
        abortSignal: AIAbortSignal? = nil,
        timeoutNanoseconds: UInt64? = nil
    ) async throws -> StartTextBatchResult {
        try await startTextBatch(
            model: model,
            requests: requests,
            providerOptions: providerOptions,
            headers: headers,
            idempotencyKey: idempotencyKey,
            webhookURL: nil,
            abortSignal: abortSignal,
            timeoutNanoseconds: timeoutNanoseconds
        )
    }

    /// Starts a durable text-generation batch. Starting is intentionally not retried because it is billable.
    public static func startTextBatch(
        model: any LanguageModel,
        requests: [TextBatchRequest],
        providerOptions: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        idempotencyKey: String? = nil,
        webhookURL: String? = nil,
        abortSignal: AIAbortSignal? = nil,
        timeoutNanoseconds: UInt64? = nil
    ) async throws -> StartTextBatchResult {
        try validateTextBatchRequests(requests)
        let model = try resolveBatchLanguageModel(model)
        let operationAbortSignal = try batchOperationAbortSignal(
            abortSignal: abortSignal,
            timeoutNanoseconds: timeoutNanoseconds
        )
        try operationAbortSignal?.throwIfAborted()

        var normalizedRequests: [AILanguageModelBatchRequest] = []
        normalizedRequests.reserveCapacity(requests.count)
        for request in requests {
            normalizedRequests.append(AILanguageModelBatchRequest(
                id: request.id,
                request: try prepareLanguageModelCallOptions(request.request)
            ))
            try operationAbortSignal?.throwIfAborted()
        }

        let operationHeaders = batchOperationHeaders(headers, idempotencyKey: idempotencyKey)
        let result = try await model.startBatch(AIBatchStartOptions(
            requests: normalizedRequests,
            providerOptions: providerOptions,
            abortSignal: operationAbortSignal,
            headers: operationHeaders,
            idempotencyKey: idempotencyKey,
            webhookURL: webhookURL
        ))
        await AIWarningLogging.logWarnings(
            result.warnings.map(\.warning),
            providerID: model.providerID,
            modelID: model.modelID
        )
        return StartTextBatchResult(
            batch: TextBatch(
                reference: TextBatchReference(
                    id: result.batchID,
                    providerID: model.providerID,
                    modelID: model.modelID
                ),
                status: result.status
            ),
            warnings: result.warnings
        )
    }

    public static func getBatchStatus(
        model: any LanguageModel,
        batch: TextBatchReference,
        providerOptions: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil,
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default
    ) async throws -> AIBatchStatus {
        let model = try resolveBatchLanguageModel(model)
        try validateBatchReference(batch, model: model)
        let operationAbortSignal = try batchOperationAbortSignal(
            abortSignal: abortSignal,
            timeoutNanoseconds: timeoutNanoseconds
        )
        let operationHeaders = batchOperationHeaders(headers, idempotencyKey: nil)

        return try await withRetry(policy: retryPolicy, abortSignal: operationAbortSignal) {
            try await model.getBatchStatus(AIBatchOperationOptions(
                batchID: batch.id,
                providerOptions: providerOptions,
                abortSignal: operationAbortSignal,
                headers: operationHeaders
            ))
        }
    }

    public static func getBatchStatus(
        model: any LanguageModel,
        batch: TextBatch,
        providerOptions: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil,
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default
    ) async throws -> AIBatchStatus {
        try await getBatchStatus(
            model: model,
            batch: batch.reference,
            providerOptions: providerOptions,
            headers: headers,
            abortSignal: abortSignal,
            timeoutNanoseconds: timeoutNanoseconds,
            retryPolicy: retryPolicy
        )
    }

    /// Opens the provider result stream in a task. Connection failures are delivered through the stream.
    public static func getBatchResults(
        model: any LanguageModel,
        batch: TextBatchReference,
        providerOptions: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil,
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default
    ) throws -> AsyncThrowingStream<TextBatchItemResult, Error> {
        let model = try resolveBatchLanguageModel(model)
        try validateBatchReference(batch, model: model)
        let streamAbortController = AIAbortController()
        let operationAbortSignal = try batchOperationAbortSignal(
            abortSignal: mergeAbortSignals(abortSignal, streamAbortController.signal),
            timeoutNanoseconds: timeoutNanoseconds
        )
        let operationHeaders = batchOperationHeaders(headers, idempotencyKey: nil)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = try await withRetry(policy: retryPolicy, abortSignal: operationAbortSignal) {
                        try await model.getBatchResults(AIBatchOperationOptions(
                            batchID: batch.id,
                            providerOptions: providerOptions,
                            abortSignal: operationAbortSignal,
                            headers: operationHeaders
                        ))
                    }
                    for try await item in stream {
                        try Task.checkCancellation()
                        try operationAbortSignal?.throwIfAborted()
                        continuation.yield(convertTextBatchItemResult(item))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                streamAbortController.abort(reason: "Batch results stream was cancelled.")
                task.cancel()
            }
        }
    }

    public static func getBatchResults(
        model: any LanguageModel,
        batch: TextBatch,
        providerOptions: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil,
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default
    ) throws -> AsyncThrowingStream<TextBatchItemResult, Error> {
        try getBatchResults(
            model: model,
            batch: batch.reference,
            providerOptions: providerOptions,
            headers: headers,
            abortSignal: abortSignal,
            timeoutNanoseconds: timeoutNanoseconds,
            retryPolicy: retryPolicy
        )
    }
}

private func resolveBatchLanguageModel(_ model: any LanguageModel) throws -> any BatchLanguageModel {
    guard let batchModel = model as? any BatchLanguageModel else {
        throw AIError.invalidArgument(
            argument: "model",
            message: "The \(model.providerID) model \"\(model.modelID)\" does not support batch processing."
        )
    }
    return batchModel
}

private func validateTextBatchRequests(_ requests: [TextBatchRequest]) throws {
    guard !requests.isEmpty else {
        throw AIError.invalidArgument(argument: "requests", message: "requests must not be empty")
    }
    var ids = Set<String>()
    for request in requests {
        guard !request.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.invalidArgument(argument: "requests", message: "request IDs must not be empty")
        }
        guard ids.insert(request.id).inserted else {
            throw AIError.invalidArgument(
                argument: "requests",
                message: "request IDs must be unique; duplicate ID \"\(request.id)\""
            )
        }
    }
}

private func validateBatchReference(_ batch: TextBatchReference, model: any BatchLanguageModel) throws {
    guard batch.version == 1, batch.type == .text else {
        throw AIError.invalidArgument(argument: "batch", message: "batch must be a supported text batch reference")
    }
    guard batch.providerID == model.providerID, batch.modelID == model.modelID else {
        throw AIError.invalidArgument(
            argument: "model",
            message: "model \(model.providerID):\(model.modelID) is not compatible with batch \(batch.providerID):\(batch.modelID)"
        )
    }
}

private func batchOperationHeaders(_ headers: [String: String], idempotencyKey: String?) -> [String: String] {
    var output = withUserAgentSuffix(headers, aiBatchUserAgent)
    if let idempotencyKey, output["idempotency-key"] == nil {
        output["idempotency-key"] = idempotencyKey
    }
    return output
}

private func batchOperationAbortSignal(
    abortSignal: AIAbortSignal?,
    timeoutNanoseconds: UInt64?
) throws -> AIAbortSignal? {
    guard let timeoutNanoseconds else { return abortSignal }
    guard timeoutNanoseconds > 0 else {
        throw AIError.invalidArgument(
            argument: "timeoutNanoseconds",
            message: "timeoutNanoseconds must be greater than zero."
        )
    }
    let roundedMilliseconds = timeoutNanoseconds / 1_000_000
        + (timeoutNanoseconds % 1_000_000 == 0 ? 0 : 1)
    let milliseconds = Int(min(roundedMilliseconds, UInt64(Int.max)))
    return mergeAbortSignals(sources: [
        abortSignal.map(AIAbortSource.signal),
        .timeoutMilliseconds(milliseconds)
    ])
}

private func convertTextBatchItemResult(
    _ item: AIBatchItemResult<TextGenerationResult>
) -> TextBatchItemResult {
    switch item {
    case let .succeeded(id, result):
        let response = result.responseMetadata == AIResponseMetadata() ? nil : result.responseMetadata
        var usage = result.usage ?? TokenUsage()
        if usage.totalTokens == nil,
           let inputTokens = usage.inputTokens,
           let outputTokens = usage.outputTokens {
            usage.totalTokens = inputTokens + outputTokens
        }
        return .succeeded(id: id, result: TextBatchGenerationResult(
            text: result.content.compactMap { part in
                guard case let .text(text, _) = part else { return nil }
                return text
            }.joined(),
            content: result.content,
            finishReason: result.finishReason,
            rawFinishReason: result.rawValue["stop_reason"]?.stringValue,
            usage: usage,
            response: response,
            providerMetadata: result.providerMetadata
        ))
    case let .failed(id, error, providerMetadata):
        return .failed(id: id, error: error, providerMetadata: providerMetadata)
    case let .cancelled(id, error, providerMetadata):
        return .cancelled(id: id, error: error, providerMetadata: providerMetadata)
    case let .expired(id, error, providerMetadata):
        return .expired(id: id, error: error, providerMetadata: providerMetadata)
    }
}
