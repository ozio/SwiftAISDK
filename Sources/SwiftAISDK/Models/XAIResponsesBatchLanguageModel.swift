import Foundation

/// xAI Responses implementation of the durable Batch V4 language-model capability.
public final class XAIResponsesBatchLanguageModel: BatchLanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    public let supportedURLs: [String: [AISupportedURLPattern]]

    private let languageModel: OpenAICompatibleResponsesModel
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
        let languageModel = OpenAICompatibleResponsesModel(modelID: modelID, config: config)
        self.languageModel = languageModel
        self.supportedURLs = languageModel.supportedURLs
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        try await languageModel.generate(request)
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        languageModel.stream(request)
    }

    public func startBatch(
        _ options: AIBatchStartOptions<AILanguageModelBatchRequest>
    ) async throws -> AIBatchStartResult {
        try options.abortSignal?.throwIfAborted()

        var jsonLines = Data()
        var warnings: [AIBatchWarning] = []
        if options.webhookURL != nil {
            warnings.append(AIBatchWarning(warning: AIWarning(
                type: "unsupported",
                feature: "webhookUrl",
                message: "The xAI Batch API does not support per-batch webhook URLs."
            )))
        }
        for request in options.requests {
            try options.abortSignal?.throwIfAborted()
            let prepared = try languageModel.preparedBatchRequest(for: request.request)
            let line: JSONValue = [
                "custom_id": .string(request.id),
                "method": "POST",
                "url": "/v1/responses",
                "body": .object(prepared.body)
            ]
            jsonLines.append(try encodeJSONBody(line))
            jsonLines.append(0x0A)
            warnings.append(contentsOf: prepared.warnings.map {
                AIBatchWarning(requestID: request.id, warning: $0)
            })
        }

        var form = MultipartFormData()
        form.appendFile(
            name: "file",
            fileName: "batch.jsonl",
            mimeType: "application/jsonl",
            data: jsonLines
        )
        let headers = xaiBatchHeaders(options.headers, idempotencyKey: options.idempotencyKey)
        let uploadRequest = try config.rawRequest(
            path: "/files",
            modelID: modelID,
            body: form.finalize(),
            contentType: "multipart/form-data; boundary=\(form.boundary)",
            headers: headers,
            abortSignal: options.abortSignal
        )
        let uploadResponse = try await config.transport.send(uploadRequest)
        guard (200..<300).contains(uploadResponse.statusCode) else {
            throw openAICompatibleHTTPStatusError(provider: providerID, response: uploadResponse)
        }
        let upload = try uploadResponse.jsonValue()
        guard let uploadedFileID = upload["id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Invalid xAI Files upload response.")
        }

        try options.abortSignal?.throwIfAborted()
        let createRequest = try config.request(
            path: "/batches",
            modelID: modelID,
            body: [
                "name": "ai-sdk-text-batch",
                "input_file_id": .string(uploadedFileID)
            ],
            headers: headers,
            abortSignal: options.abortSignal
        )
        let createResponse = try await config.transport.send(createRequest)
        guard (200..<300).contains(createResponse.statusCode) else {
            throw openAICompatibleHTTPStatusError(provider: providerID, response: createResponse)
        }
        let batch = try parseXAIBatchResponse(createResponse.jsonValue(), providerID: providerID)
        return AIBatchStartResult(
            batchID: batch.id,
            status: xaiBatchStatus(batch),
            warnings: warnings
        )
    }

    public func getBatchStatus(_ options: AIBatchOperationOptions) async throws -> AIBatchStatus {
        xaiBatchStatus(try await retrieveBatch(options))
    }

    public func getBatchResults(
        _ options: AIBatchOperationOptions
    ) async throws -> AsyncThrowingStream<AIBatchItemResult<TextGenerationResult>, Error> {
        let batch = try await retrieveBatch(options)
        guard xaiBatchStatus(batch).status != .pending else {
            throw AIError.invalidArgument(
                argument: "batchID",
                message: "xAI batch \"\(options.batchID)\" is not complete."
            )
        }

        let config = self.config
        let providerID = self.providerID
        let modelID = self.modelID
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var paginationToken: String?
                    repeat {
                        try Task.checkCancellation()
                        try options.abortSignal?.throwIfAborted()
                        var path = "/batches/\(xaiBatchPathEncode(options.batchID))/results?limit=1000"
                        if let paginationToken {
                            path += "&pagination_token=\(xaiBatchQueryEncode(paginationToken))"
                        }
                        let request = AIHTTPRequest(
                            method: "GET",
                            url: try config.url(modelID, path),
                            headers: prepareHeaders(options.headers, defaultHeaders: config.headers),
                            abortSignal: options.abortSignal
                        )
                        let response = try await config.transport.send(request)
                        guard (200..<300).contains(response.statusCode) else {
                            throw openAICompatibleHTTPStatusError(provider: providerID, response: response)
                        }
                        let page = try parseXAIBatchResultsPage(response.jsonValue(), providerID: providerID)
                        for result in page.results {
                            continuation.yield(convertXAIBatchResult(result))
                        }
                        paginationToken = page.paginationToken
                    } while paginationToken != nil
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func retrieveBatch(_ options: AIBatchOperationOptions) async throws -> XAIBatchResponse {
        try options.abortSignal?.throwIfAborted()
        let request = AIHTTPRequest(
            method: "GET",
            url: try config.url(modelID, "/batches/\(xaiBatchPathEncode(options.batchID))"),
            headers: prepareHeaders(options.headers, defaultHeaders: config.headers),
            abortSignal: options.abortSignal
        )
        let response = try await config.transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw openAICompatibleHTTPStatusError(provider: providerID, response: response)
        }
        return try parseXAIBatchResponse(response.jsonValue(), providerID: providerID)
    }
}

private struct XAIBatchResponse: Sendable {
    struct State: Sendable {
        var total: Int?
        var pending: Int?
        var succeeded: Int?
        var errored: Int?
        var cancelled: Int?
    }

    var id: String
    var createdAt: String?
    var expiresAt: String?
    var cancelledAt: String?
    var cancellationMessage: String?
    var state: State?
}

private struct XAIBatchResult: Sendable {
    var id: String
    var chatResponse: JSONValue?
    var errorCode: JSONValue?
    var errorMessage: String?
    var topLevelErrorMessage: String?
    var isValidEnvelope: Bool
}

private struct XAIBatchResultsPage: Sendable {
    var results: [XAIBatchResult]
    var paginationToken: String?
}

private func parseXAIBatchResponse(_ raw: JSONValue, providerID: String) throws -> XAIBatchResponse {
    guard let object = raw.objectValue,
          let id = object["batch_id"]?.stringValue else {
        throw AIError.invalidResponse(provider: providerID, message: "Invalid xAI Batch response.")
    }
    for key in ["create_time", "expire_time", "cancel_time", "cancel_by_xai_message"] {
        if let value = object[key], value != .null, value.stringValue == nil {
            throw AIError.invalidResponse(provider: providerID, message: "xAI Batch field \(key) must be a string.")
        }
    }

    let state: XAIBatchResponse.State?
    if let rawState = object["state"], rawState != .null {
        guard let stateObject = rawState.objectValue else {
            throw AIError.invalidResponse(provider: providerID, message: "xAI Batch state must be an object.")
        }
        for key in ["num_requests", "num_pending", "num_success", "num_error", "num_cancelled"] {
            if let value = stateObject[key], value != .null {
                guard case let .number(number) = value, number.isFinite else {
                    throw AIError.invalidResponse(provider: providerID, message: "xAI Batch state field \(key) must be a number.")
                }
            }
        }
        state = XAIBatchResponse.State(
            total: normalizedBatchJSONInteger(stateObject["num_requests"]),
            pending: normalizedBatchJSONInteger(stateObject["num_pending"]),
            succeeded: normalizedBatchJSONInteger(stateObject["num_success"]),
            errored: normalizedBatchJSONInteger(stateObject["num_error"]),
            cancelled: normalizedBatchJSONInteger(stateObject["num_cancelled"])
        )
    } else {
        state = nil
    }
    return XAIBatchResponse(
        id: id,
        createdAt: object["create_time"]?.stringValue,
        expiresAt: object["expire_time"]?.stringValue,
        cancelledAt: object["cancel_time"]?.stringValue,
        cancellationMessage: object["cancel_by_xai_message"]?.stringValue,
        state: state
    )
}

private func xaiBatchStatus(_ batch: XAIBatchResponse) -> AIBatchStatus {
    let counts: AIBatchRequestCounts? = {
        guard let state = batch.state,
              let total = state.total,
              let pending = state.pending,
              let succeeded = state.succeeded,
              let errored = state.errored,
              let cancelled = state.cancelled else { return nil }
        guard let failed = checkedBatchSafeIntegerSum([errored, cancelled]) else { return nil }
        return normalizedBatchRequestCounts(
            total: total,
            pending: pending,
            completed: succeeded,
            failed: failed
        )
    }()
    let isCancelled = batch.cancelledAt != nil || batch.cancellationMessage != nil
    let isExpired = xaiBatchDate(batch.expiresAt).map { $0 <= Date() } == true
    let status: AIBatchLifecycleStatus
    if isCancelled || isExpired {
        status = .failed
    } else if let counts, counts.total > 0, counts.pending == 0 {
        status = .completed
    } else {
        status = .pending
    }
    let error: AIBatchError?
    if isCancelled {
        error = AIBatchError(
            message: batch.cancellationMessage ?? "xAI batch \"\(batch.id)\" was cancelled.",
            code: "batch_cancelled"
        )
    } else if isExpired {
        error = AIBatchError(
            message: "xAI batch \"\(batch.id)\" expired.",
            code: "batch_expired"
        )
    } else {
        error = nil
    }
    return AIBatchStatus(
        status: status,
        requestCounts: counts,
        error: error,
        createdAt: batch.createdAt,
        expiresAt: batch.expiresAt
    )
}

private func parseXAIBatchResultsPage(_ raw: JSONValue, providerID: String) throws -> XAIBatchResultsPage {
    guard let values = raw["results"]?.arrayValue else {
        throw AIError.invalidResponse(provider: providerID, message: "Invalid xAI Batch results page.")
    }
    if let token = raw["pagination_token"], token != .null, token.stringValue == nil {
        throw AIError.invalidResponse(provider: providerID, message: "xAI Batch pagination_token must be a string.")
    }
    let results = try values.map { value -> XAIBatchResult in
        guard let object = value.objectValue,
              let id = object["batch_request_id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Invalid xAI Batch result item.")
        }
        var isValidEnvelope = isNullishXAIString(object["error_message"])
        let batchResult: [String: JSONValue]?
        if let value = object["batch_result"], value != .null {
            batchResult = value.objectValue
            isValidEnvelope = isValidEnvelope && batchResult != nil
        } else {
            batchResult = nil
        }
        let response: [String: JSONValue]?
        if let value = batchResult?["response"], value != .null {
            response = value.objectValue
            isValidEnvelope = isValidEnvelope && response != nil
        } else {
            response = nil
        }
        let error: [String: JSONValue]?
        if let value = batchResult?["error"], value != .null {
            error = value.objectValue
            isValidEnvelope = isValidEnvelope
                && error != nil
                && isNullishXAIErrorCode(error?["code"])
                && isNullishXAIString(error?["message"])
        } else {
            error = nil
        }
        return XAIBatchResult(
            id: id,
            chatResponse: response?["chat_get_completion"],
            errorCode: error?["code"],
            errorMessage: error?["message"]?.stringValue,
            topLevelErrorMessage: object["error_message"]?.stringValue,
            isValidEnvelope: isValidEnvelope
        )
    }
    return XAIBatchResultsPage(results: results, paginationToken: raw["pagination_token"]?.stringValue)
}

private func convertXAIBatchResult(_ result: XAIBatchResult) -> AIBatchItemResult<TextGenerationResult> {
    guard result.isValidEnvelope else {
        return xaiInvalidBatchResult(id: result.id)
    }
    let code = xaiBatchErrorCode(result.errorCode)
    let hasProviderError = result.topLevelErrorMessage?.isEmpty == false
        || (code != nil && code != "0")
        || (result.errorCode == nil && result.errorMessage?.isEmpty == false)
    if hasProviderError {
        let error = AIBatchError(
            message: result.topLevelErrorMessage?.isEmpty == false
                ? result.topLevelErrorMessage!
                : (result.errorMessage?.isEmpty == false ? result.errorMessage! : "xAI batch request failed."),
            code: code == "0" ? nil : code
        )
        if xaiBatchIsCancellationCode(code) {
            return .cancelled(id: result.id, error: error)
        }
        return .failed(id: result.id, error: error)
    }
    guard let raw = result.chatResponse else {
        return xaiInvalidBatchResult(id: result.id)
    }
    guard isValidXAIChatBatchResponse(raw) else {
        return xaiInvalidBatchResult(id: result.id)
    }
    if let message = raw["error"]?.stringValue {
        return .failed(
            id: result.id,
            error: AIBatchError(
                message: message,
                code: xaiBatchErrorCode(raw["code"])
            )
        )
    }
    guard let choice = raw["choices"]?.arrayValue?.first,
          let message = choice["message"]?.objectValue else {
        return xaiInvalidBatchResult(id: result.id)
    }
    if message["tool_calls"]?.arrayValue?.isEmpty == false {
        return .failed(
            id: result.id,
            error: AIBatchError(
                message: "xAI returned \"tool_calls\" content, but tool content is not supported in AI SDK text batches.",
                code: "unsupported_content"
            )
        )
    }

    let text = message["content"]?.stringValue ?? ""
    let reasoning = message["reasoning_content"]?.stringValue ?? ""
    let sources = (raw["citations"]?.arrayValue ?? []).compactMap { citation -> AISource? in
        guard let url = citation.stringValue else { return nil }
        return AISource(id: url, sourceType: "url", url: url)
    }
    var content: [AIResultContentPart] = []
    if !text.isEmpty { content.append(.text(text)) }
    if !reasoning.isEmpty { content.append(.reasoning(reasoning)) }
    content.append(contentsOf: sources.map(AIResultContentPart.source))

    var metadata: [String: JSONValue] = [:]
    if let cost = raw["usage"]?["cost_in_usd_ticks"] {
        metadata["costInUsdTicks"] = cost
    }
    if let serviceTier = raw["service_tier"] {
        metadata["serviceTier"] = serviceTier
    }
    let providerMetadata = metadata.isEmpty ? [:] : ["xai": JSONValue.object(metadata)]
    let generation = TextGenerationResult(
        text: text,
        content: content,
        reasoning: reasoning,
        finishReason: openAICompatibleFinishReason(choice["finish_reason"]?.stringValue),
        usage: tokenUsage(from: raw) ?? TokenUsage(),
        sources: sources,
        providerMetadata: providerMetadata,
        rawValue: raw,
        responseMetadata: AIResponseMetadata(
            id: raw["id"]?.stringValue,
            timestamp: raw["created"]?.doubleValue.map(Date.init(timeIntervalSince1970:)),
            modelID: raw["model"]?.stringValue
        )
    )
    return .succeeded(id: result.id, result: generation)
}

private func isValidXAIChatBatchResponse(_ raw: JSONValue) -> Bool {
    guard let object = raw.objectValue,
          isNullishXAIString(object["id"]),
          isNullishXAINumber(object["created"]),
          isNullishXAIString(object["model"]),
          isNullishXAIString(object["service_tier"]),
          isNullishXAIString(object["code"]),
          isNullishXAIString(object["error"]) else {
        return false
    }
    if let value = object["object"], value != .null,
       value.stringValue != "chat.completion" {
        return false
    }
    if let usage = object["usage"], usage != .null,
       !isValidXAIChatBatchUsage(usage) {
        return false
    }
    if let citations = object["citations"], citations != .null {
        guard let values = citations.arrayValue,
              values.allSatisfy({ citation in
                  guard let string = citation.stringValue,
                        let url = URL(string: string) else { return false }
                  return url.scheme != nil
              }) else {
            return false
        }
    }
    if let choices = object["choices"], choices != .null {
        guard let values = choices.arrayValue,
              values.allSatisfy(isValidXAIChatBatchChoice) else {
            return false
        }
    }
    return true
}

private func isValidXAIChatBatchChoice(_ value: JSONValue) -> Bool {
    guard let object = value.objectValue,
          isFiniteXAINumber(object["index"]),
          isNullishXAIString(object["finish_reason"]),
          let message = object["message"]?.objectValue,
          message["role"]?.stringValue == "assistant",
          isNullishXAIString(message["content"]),
          isNullishXAIString(message["reasoning_content"]) else {
        return false
    }
    if let toolCalls = message["tool_calls"], toolCalls != .null {
        guard let calls = toolCalls.arrayValue,
              calls.allSatisfy({ call in
                  guard let object = call.objectValue,
                        object["id"]?.stringValue != nil,
                        object["type"]?.stringValue == "function",
                        let function = object["function"]?.objectValue else {
                      return false
                  }
                  return function["name"]?.stringValue != nil
                      && function["arguments"]?.stringValue != nil
              }) else {
            return false
        }
    }
    return true
}

private func isValidXAIChatBatchUsage(_ value: JSONValue) -> Bool {
    guard let object = value.objectValue,
          isFiniteXAINumber(object["prompt_tokens"]),
          isFiniteXAINumber(object["completion_tokens"]),
          isFiniteXAINumber(object["total_tokens"]),
          isNullishXAINumber(object["cost_in_usd_ticks"]) else {
        return false
    }
    let detailFields: [(String, [String])] = [
        ("prompt_tokens_details", ["text_tokens", "audio_tokens", "image_tokens", "cached_tokens"]),
        ("completion_tokens_details", ["reasoning_tokens", "audio_tokens", "accepted_prediction_tokens", "rejected_prediction_tokens"])
    ]
    for (field, numericKeys) in detailFields {
        guard let details = object[field] else { continue }
        if details == .null { continue }
        guard let detailObject = details.objectValue,
              numericKeys.allSatisfy({ isNullishXAINumber(detailObject[$0]) }) else {
            return false
        }
    }
    return true
}

private func isFiniteXAINumber(_ value: JSONValue?) -> Bool {
    guard case let .number(number)? = value else { return false }
    return number.isFinite
}

private func isNullishXAINumber(_ value: JSONValue?) -> Bool {
    value == nil || value == .null || isFiniteXAINumber(value)
}

private func isNullishXAIString(_ value: JSONValue?) -> Bool {
    value == nil || value == .null || value?.stringValue != nil
}

private func isNullishXAIErrorCode(_ value: JSONValue?) -> Bool {
    value == nil || value == .null || value?.stringValue != nil || isFiniteXAINumber(value)
}

private func xaiInvalidBatchResult(id: String) -> AIBatchItemResult<TextGenerationResult> {
    .failed(
        id: id,
        error: AIBatchError(
            message: "xAI returned an invalid Responses batch result.",
            code: "invalid_response"
        )
    )
}

private func xaiBatchErrorCode(_ value: JSONValue?) -> String? {
    if let string = value?.stringValue { return string }
    if let integer = value?.intValue { return String(integer) }
    if let number = value?.doubleValue { return String(number) }
    return nil
}

private func xaiBatchIsCancellationCode(_ code: String?) -> Bool {
    guard let code = code?.lowercased() else { return false }
    return code == "1" || code == "cancelled" || code == "batch_cancelled"
}

private func xaiBatchDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}

private func xaiBatchHeaders(_ headers: [String: String], idempotencyKey: String?) -> [String: String] {
    var output = headers
    if let idempotencyKey, normalizeHeaders(output)["idempotency-key"] == nil {
        output["idempotency-key"] = idempotencyKey
    }
    return output
}

private func xaiBatchPathEncode(_ value: String) -> String {
    if value == "." { return "%252E" }
    if value == ".." { return "%252E%252E" }
    return xaiBatchPercentEncode(value, allowed: Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8))
}

private func xaiBatchQueryEncode(_ value: String) -> String {
    xaiBatchPercentEncode(value, allowed: Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8))
}

private func xaiBatchPercentEncode(_ value: String, allowed: Set<UInt8>) -> String {
    value.utf8.map { byte in
        allowed.contains(byte) ? String(UnicodeScalar(byte)) : String(format: "%%%02X", byte)
    }.joined()
}
