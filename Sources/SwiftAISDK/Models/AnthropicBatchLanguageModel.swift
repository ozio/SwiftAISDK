import Foundation

/// Anthropic Messages implementation of the durable Batch V4 language-model capability.
public final class AnthropicBatchLanguageModel: BatchLanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    public let supportedURLs: [String: [AISupportedURLPattern]]

    private let languageModel: AnthropicLanguageModel
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
        let languageModel = AnthropicLanguageModel(modelID: modelID, config: config)
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
        try validateAnthropicBatchRequestIDs(options.requests)
        try options.abortSignal?.throwIfAborted()

        let explicitBatchBetas = try anthropicBatchBetas(
            from: options.providerOptions,
            providerID: providerID
        )
        var batchBetas = explicitBatchBetas
        var requests: [JSONValue] = []
        var warnings: [AIBatchWarning] = []
        if options.webhookURL != nil {
            warnings.append(AIBatchWarning(warning: AIWarning(
                type: "unsupported",
                feature: "webhookUrl",
                message: "The Anthropic Message Batches API does not support completion webhooks."
            )))
        }
        requests.reserveCapacity(options.requests.count)

        for request in options.requests {
            try options.abortSignal?.throwIfAborted()
            let explicitRequestBetas = try anthropicExplicitRequestBetas(
                from: request.request,
                providerID: providerID
            )
            guard explicitRequestBetas.isEmpty else {
                throw AIError.invalidArgument(
                    argument: "providerOptions.anthropic.anthropicBeta",
                    message: "Anthropic Message Batches do not support per-request betas (request \"\(request.id)\"). Set providerOptions.anthropic.anthropicBeta on startTextBatch instead."
                )
            }

            let prepared = try AnthropicLanguageModel.body(
                for: request.request,
                modelID: modelID,
                providerID: providerID
            )
            if prepared.usesJSONToolResponseFormat {
                throw AIError.invalidArgument(
                    argument: "responseFormat",
                    message: "Anthropic Message Batches cannot decode the JSON-tool structured-output fallback (request \"\(request.id)\") because batch results are retrieved independently of the start call. Use a model that supports native output_format structured outputs."
                )
            }
            if let aliasedProviderTool = request.request.tools.first(where: { name, tool in
                tool["type"]?.stringValue == "provider"
                    && prepared.toolNameMapping.toProviderToolName(name) != name
            }) {
                throw AIError.invalidArgument(
                    argument: "tools",
                    message: "Anthropic Message Batches cannot restore the custom provider-tool name \"\(aliasedProviderTool.key)\" when results are retrieved independently of the start call (request \"\(request.id)\"). Use the provider's canonical tool name."
                )
            }
            var body = config.transformRequestBody?(prepared.body) ?? prepared.body
            body["stream"] = nil
            try validateAnthropicBatchBody(body, requestID: request.id)

            requests.append(.object([
                "custom_id": .string(request.id),
                "params": .object(body)
            ]))
            for beta in prepared.betas where !batchBetas.contains(beta) {
                batchBetas.append(beta)
            }
            warnings.append(contentsOf: prepared.warnings.map {
                AIBatchWarning(requestID: request.id, warning: $0)
            })
        }

        var headers = options.headers
        if let idempotencyKey = options.idempotencyKey,
           normalizeHeaders(headers)["idempotency-key"] == nil {
            headers["idempotency-key"] = idempotencyKey
        }
        if !batchBetas.isEmpty {
            headers["anthropic-beta"] = batchBetas.joined(separator: ",")
        }
        let request = try config.request(
            path: "/messages/batches",
            modelID: modelID,
            body: .object(["requests": .array(requests)]),
            headers: headers,
            abortSignal: options.abortSignal
        )
        let response = try await config.transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw anthropicHTTPStatusError(provider: providerID, response: response)
        }
        let batch = try parseAnthropicBatchResponse(response.jsonValue())
        return AIBatchStartResult(
            batchID: batch.id,
            status: anthropicBatchStatus(batch),
            warnings: warnings
        )
    }

    public func getBatchStatus(_ options: AIBatchOperationOptions) async throws -> AIBatchStatus {
        anthropicBatchStatus(try await retrieveBatch(options))
    }

    public func getBatchResults(
        _ options: AIBatchOperationOptions
    ) async throws -> AsyncThrowingStream<AIBatchItemResult<TextGenerationResult>, Error> {
        let batch = try await retrieveBatch(options)
        guard anthropicBatchStatus(batch).status != .pending else {
            throw AIError.invalidArgument(
                argument: "batchID",
                message: "Anthropic batch \"\(options.batchID)\" is not complete."
            )
        }
        guard batch.archivedAt == nil else {
            throw AIError.invalidArgument(
                argument: "batchID",
                message: "Anthropic batch \"\(options.batchID)\" results are no longer available."
            )
        }
        guard let resultsURL = batch.resultsURL else {
            throw AIError.invalidResponse(
                provider: providerID,
                message: "Anthropic batch \"\(options.batchID)\" completed without batch output."
            )
        }
        var headers = prepareHeaders(options.headers, defaultHeaders: config.headers)
        headers["accept"] = headers["accept"] ?? "application/jsonl"
        let transport = try requireStreamingTransport(config.transport, providerID: providerID)
        let streamed = try await streamDownloadURL(
            resultsURL,
            transport: transport,
            headers: headers,
            credentialedOrigin: config.baseURL,
            trustedOrigin: config.baseURL,
            abortSignal: options.abortSignal
        )
        let response = streamed.response
        let request = streamed.request
        guard (200..<300).contains(response.statusCode) else {
            throw anthropicHTTPStatusError(
                provider: providerID,
                response: try await bufferedHTTPResponse(from: response, request: request)
            )
        }

        return anthropicBatchResultStream(
            body: response.body,
            providerID: providerID,
            abortSignal: options.abortSignal
        )
    }

    private func retrieveBatch(_ options: AIBatchOperationOptions) async throws -> AnthropicBatchResponse {
        try options.abortSignal?.throwIfAborted()
        let encodedBatchID = anthropicBatchPathEncode(options.batchID)
        let request = AIHTTPRequest(
            method: "GET",
            url: try config.url(modelID, "/messages/batches/\(encodedBatchID)"),
            headers: prepareHeaders(options.headers, defaultHeaders: config.headers),
            abortSignal: options.abortSignal
        )
        let response = try await config.transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw anthropicHTTPStatusError(provider: providerID, response: response)
        }
        return try parseAnthropicBatchResponse(response.jsonValue())
    }
}

private struct AnthropicBatchResponse: Sendable {
    var id: String
    var processingStatus: String
    var counts: [String: JSONValue]
    var createdAt: String
    var expiresAt: String
    var archivedAt: String?
    var cancelInitiatedAt: String?
    var endedAt: String?
    var resultsURL: String?
}

private func parseAnthropicBatchResponse(_ value: JSONValue) throws -> AnthropicBatchResponse {
    guard let id = value["id"]?.stringValue,
          value["type"]?.stringValue == "message_batch",
          let processingStatus = value["processing_status"]?.stringValue,
          let rawCounts = value["request_counts"]?.objectValue,
          ["processing", "succeeded", "errored", "canceled", "expired"].allSatisfy({ key in
              guard case let .number(number)? = rawCounts[key] else { return false }
              return number.isFinite
          }),
          let createdAt = value["created_at"]?.stringValue,
          let expiresAt = value["expires_at"]?.stringValue,
          isNullishString(value["archived_at"]),
          isNullishString(value["cancel_initiated_at"]),
          isNullishString(value["ended_at"]),
          isNullishString(value["results_url"]) else {
        throw AIError.invalidResponse(provider: "anthropic", message: "Invalid Message Batch response.")
    }

    return AnthropicBatchResponse(
        id: id,
        processingStatus: processingStatus,
        counts: rawCounts,
        createdAt: createdAt,
        expiresAt: expiresAt,
        archivedAt: value["archived_at"]?.stringValue,
        cancelInitiatedAt: value["cancel_initiated_at"]?.stringValue,
        endedAt: value["ended_at"]?.stringValue,
        resultsURL: value["results_url"]?.stringValue
    )
}

private func isNullishString(_ value: JSONValue?) -> Bool {
    value == nil || value == .null || value?.stringValue != nil
}

private func anthropicBatchStatus(_ batch: AnthropicBatchResponse) -> AIBatchStatus {
    let status: AIBatchLifecycleStatus = batch.processingStatus == "ended" ? .completed : .pending
    let processing = normalizedBatchJSONInteger(batch.counts["processing"])
    let succeeded = normalizedBatchJSONInteger(batch.counts["succeeded"])
    let errored = normalizedBatchJSONInteger(batch.counts["errored"])
    let cancelled = normalizedBatchJSONInteger(batch.counts["canceled"])
    let expired = normalizedBatchJSONInteger(batch.counts["expired"])
    let failed: Int?
    if let errored, let cancelled, let expired {
        failed = checkedBatchSafeIntegerSum([errored, cancelled, expired])
    } else {
        failed = nil
    }
    let total: Int?
    if let processing, let succeeded, let failed {
        total = checkedBatchSafeIntegerSum([processing, succeeded, failed])
    } else {
        total = nil
    }
    let counts = normalizedBatchRequestCounts(
        total: total,
        pending: processing,
        completed: succeeded,
        failed: failed
    )
    return AIBatchStatus(
        status: status,
        rawStatus: batch.processingStatus,
        requestCounts: counts,
        createdAt: batch.createdAt,
        expiresAt: batch.expiresAt,
        providerMetadata: [
            "anthropic": .object([
                "archivedAt": batch.archivedAt.map(JSONValue.string) ?? .null,
                "cancelInitiatedAt": batch.cancelInitiatedAt.map(JSONValue.string) ?? .null,
                "endedAt": batch.endedAt.map(JSONValue.string) ?? .null,
                "requestCounts": .object(batch.counts),
                "resultsUrl": batch.resultsURL.map(JSONValue.string) ?? .null
            ])
        ]
    )
}

private func validateAnthropicBatchRequestIDs(_ requests: [AILanguageModelBatchRequest]) throws {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
    var ids = Set<String>()
    for request in requests {
        let isValid = (1...64).contains(request.id.utf8.count)
            && request.id.unicodeScalars.allSatisfy { allowed.contains($0) }
        guard isValid else {
            throw AIError.invalidArgument(
                argument: "requests",
                message: "Anthropic batch request ID \"\(request.id)\" must match ^[A-Za-z0-9_-]{1,64}$."
            )
        }
        guard ids.insert(request.id).inserted else {
            throw AIError.invalidArgument(
                argument: "requests",
                message: "Anthropic batch request IDs must be unique; duplicate ID \"\(request.id)\"."
            )
        }
    }
}

private func validateAnthropicBatchBody(_ body: [String: JSONValue], requestID: String) throws {
    if let speed = body["speed"], speed != .null {
        throw AIError.invalidArgument(
            argument: "providerOptions.anthropic.speed",
            message: "Anthropic Message Batches do not support speed (request \"\(requestID)\")."
        )
    }
    if body["fallbacks"]?.arrayValue?.contains(where: {
        guard let speed = $0["speed"] else { return false }
        return speed != .null
    }) == true {
        throw AIError.invalidArgument(
            argument: "providerOptions.anthropic.fallbacks[].speed",
            message: "Anthropic Message Batches do not support fallback speed (request \"\(requestID)\")."
        )
    }
}

private func anthropicBatchBetas(
    from providerOptions: [String: JSONValue],
    providerID: String
) throws -> [String] {
    var betas: [String] = []
    for key in Set(["anthropic", anthropicProviderOptionsName(from: providerID)]) {
        guard let value = providerOptions[key], value != .null else { continue }
        guard let options = value.objectValue else {
            throw AIError.invalidArgument(
                argument: "providerOptions.\(key)",
                message: "Anthropic provider options must be an object."
            )
        }
        for beta in try anthropicBetaValues(
            options["anthropicBeta"],
            argument: "providerOptions.\(key).anthropicBeta"
        ) where !betas.contains(beta) {
            betas.append(beta)
        }
    }
    return betas
}

private func anthropicExplicitRequestBetas(
    from request: LanguageModelRequest,
    providerID: String
) throws -> [String] {
    var betas = try anthropicBatchBetas(from: request.providerOptions, providerID: providerID)
    for beta in try anthropicBetaValues(
        request.extraBody["anthropicBeta"],
        argument: "extraBody.anthropicBeta"
    ) where !betas.contains(beta) {
        betas.append(beta)
    }
    return betas
}

private func anthropicBatchResultStream(
    body: AsyncThrowingStream<Data, Error>,
    providerID: String,
    abortSignal: AIAbortSignal?
) -> AsyncThrowingStream<AIBatchItemResult<TextGenerationResult>, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                var buffer = Data()
                for try await chunk in body {
                    try Task.checkCancellation()
                    try abortSignal?.throwIfAborted()
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(of: 0x0A) {
                        let line = Data(buffer[..<newline])
                        buffer.removeSubrange(...newline)
                        if let item = try parseAnthropicBatchResultLine(line, providerID: providerID) {
                            continuation.yield(item)
                        }
                    }
                }
                if let item = try parseAnthropicBatchResultLine(buffer, providerID: providerID) {
                    continuation.yield(item)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
    }
}

private func parseAnthropicBatchResultLine(
    _ data: Data,
    providerID: String
) throws -> AIBatchItemResult<TextGenerationResult>? {
    var line = data
    if line.last == 0x0D { line.removeLast() }
    guard let text = String(data: line, encoding: .utf8) else {
        throw AIError.invalidResponse(provider: providerID, message: "Message Batch result line is not valid UTF-8.")
    }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
    }
    let raw = try secureJSONParse(text)
    guard let id = raw["custom_id"]?.stringValue else {
        throw AIError.invalidResponse(provider: providerID, message: "Invalid Message Batch result line.")
    }
    guard let result = raw["result"]?.objectValue,
          let type = result["type"]?.stringValue else {
        return invalidAnthropicBatchResult(id: id)
    }

    switch type {
    case "canceled":
        return .cancelled(id: id)
    case "expired":
        return .expired(id: id)
    case "errored":
        guard let errorEnvelope = result["error"]?.objectValue,
              errorEnvelope["type"]?.stringValue == "error",
              isNullishString(errorEnvelope["request_id"]),
              let error = errorEnvelope["error"]?.objectValue,
              let type = error["type"]?.stringValue,
              let message = error["message"]?.stringValue else {
            return invalidAnthropicBatchResult(id: id)
        }
        let requestID = errorEnvelope["request_id"]?.stringValue
        return AIBatchItemResult<TextGenerationResult>.failed(
            id: id,
            error: AIBatchError(message: message, type: type),
            providerMetadata: requestID.map {
                ["anthropic": .object(["requestId": .string($0)])]
            } ?? [:]
        )
    case "succeeded":
        guard let rawMessage = result["message"],
              let message = normalizedAnthropicBatchMessage(rawMessage) else {
            return AIBatchItemResult<TextGenerationResult>.failed(
                id: id,
                error: AIBatchError(
                    message: "Anthropic returned an invalid Message batch result.",
                    code: "invalid_response"
                )
            )
        }
        let generated = anthropicGeneratedContent(
            from: message["content"],
            providerID: providerID,
            citationDocuments: []
        )
        let responseMetadata = AIResponseMetadata(
            id: message["id"]?.stringValue,
            modelID: message["model"]?.stringValue
        )
        return .succeeded(id: id, result: TextGenerationResult(
            text: generated.text ?? "",
            content: generated.content,
            reasoning: generated.reasoning,
            finishReason: anthropicFinishReason(message["stop_reason"]?.stringValue),
            usage: anthropicTokenUsage(from: message["usage"]),
            toolCalls: generated.toolCalls,
            toolResults: generated.toolResults,
            sources: generated.sources,
            providerMetadata: anthropicProviderMetadata(from: message, providerID: providerID),
            rawValue: message,
            responseMetadata: responseMetadata
        ))
    default:
        return invalidAnthropicBatchResult(id: id)
    }
}

private func invalidAnthropicBatchResult(
    id: String
) -> AIBatchItemResult<TextGenerationResult> {
    .failed(
        id: id,
        error: AIBatchError(
            message: "Anthropic returned an invalid Message batch result.",
            code: "invalid_response"
        )
    )
}

private let knownAnthropicBatchContentTypes: Set<String> = [
    "advisor_tool_result",
    "bash_code_execution_tool_result",
    "code_execution_tool_result",
    "compaction",
    "container_upload",
    "fallback",
    "mcp_tool_result",
    "mcp_tool_use",
    "redacted_thinking",
    "server_tool_use",
    "text",
    "text_editor_code_execution_tool_result",
    "thinking",
    "tool_search_tool_result",
    "tool_use",
    "web_fetch_tool_result",
    "web_search_tool_result"
]

private func normalizedAnthropicBatchMessage(_ message: JSONValue) -> JSONValue? {
    guard var object = message.objectValue,
          let rawContent = object["content"]?.arrayValue else {
        return Optional<JSONValue>.none
    }
    var content: [JSONValue] = []
    for part in rawContent {
        guard let type = part["type"]?.stringValue else { return Optional<JSONValue>.none }
        guard knownAnthropicBatchContentTypes.contains(type) else { continue }
        guard isValidAnthropicBatchContentPart(part) else { return Optional<JSONValue>.none }
        content.append(part)
    }
    object["content"] = .array(content)
    let normalized = JSONValue.object(object)
    return isValidAnthropicBatchMessage(normalized) ? normalized : Optional<JSONValue>.none
}

private func isValidAnthropicBatchMessage(_ message: JSONValue) -> Bool {
    guard message["type"]?.stringValue == "message",
          isNullishString(message["id"]),
          isNullishString(message["model"]),
          let content = message["content"]?.arrayValue,
          isNullishString(message["stop_reason"]),
          isNullishString(message["stop_sequence"]),
          isValidAnthropicBatchUsage(message["usage"]) else {
        return false
    }
    return content.allSatisfy(isValidAnthropicBatchContentPart)
}

private func isValidAnthropicBatchContentPart(_ part: JSONValue) -> Bool {
    guard let type = part["type"]?.stringValue else { return false }
    switch type {
        case "text": return part["text"]?.stringValue != nil
        case "thinking":
            return part["thinking"]?.stringValue != nil && part["signature"]?.stringValue != nil
        case "redacted_thinking": return part["data"]?.stringValue != nil
        case "compaction": return part["content"]?.stringValue != nil
        case "fallback": return true
        case "container_upload": return part["file_id"]?.stringValue != nil
        case "tool_use":
            return part["id"]?.stringValue != nil
                && part["name"]?.stringValue != nil
                && part["input"] != nil
        case "server_tool_use":
            return part["id"]?.stringValue != nil
                && part["name"]?.stringValue != nil
                && (part["input"] == nil || part["input"] == .null || part["input"]?.objectValue != nil)
        case "mcp_tool_use":
            return part["id"]?.stringValue != nil
                && part["name"]?.stringValue != nil
                && part["server_name"]?.stringValue != nil
                && part["input"] != nil
        case "mcp_tool_result":
            return part["tool_use_id"]?.stringValue != nil
                && part["is_error"]?.boolValue != nil
                && part["content"]?.arrayValue != nil
        case "web_fetch_tool_result", "web_search_tool_result", "code_execution_tool_result",
             "bash_code_execution_tool_result", "text_editor_code_execution_tool_result",
             "tool_search_tool_result", "advisor_tool_result":
            return part["tool_use_id"]?.stringValue != nil && part["content"] != nil
        default: return false
    }
}

private func isValidAnthropicBatchUsage(_ value: JSONValue?) -> Bool {
    guard let usage = value?.objectValue,
          isFiniteAnthropicBatchNumber(usage["input_tokens"]),
          isFiniteAnthropicBatchNumber(usage["output_tokens"]) else {
        return false
    }
    for key in ["cache_creation_input_tokens", "cache_read_input_tokens"] {
        if let tokenCount = usage[key], tokenCount != .null,
           !isFiniteAnthropicBatchNumber(tokenCount) {
            return false
        }
    }
    return true
}

private func isFiniteAnthropicBatchNumber(_ value: JSONValue?) -> Bool {
    guard case let .number(number)? = value else { return false }
    return number.isFinite
}

private func anthropicBatchPathEncode(_ value: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}
