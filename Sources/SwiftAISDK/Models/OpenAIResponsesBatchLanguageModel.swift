import Foundation

/// OpenAI Responses implementation of the durable Batch V4 language-model capability.
public final class OpenAIResponsesBatchLanguageModel: BatchLanguageModel, @unchecked Sendable {
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

        let requestModelIDs = Set(options.requests.map { $0.modelID ?? modelID })
        guard requestModelIDs.count <= 1 else {
            throw AIError.invalidArgument(
                argument: "requests",
                message: "All OpenAI batch requests must use the same model."
            )
        }

        var jsonLines = Data()
        var warnings: [AIBatchWarning] = []
        if options.webhookURL != nil {
            warnings.append(AIBatchWarning(warning: AIWarning(
                type: "unsupported",
                feature: "webhookUrl",
                message: "The OpenAI Batch API does not support per-batch webhook URLs."
            )))
        }
        let inputFileExpiresAfter = try openAIBatchInputFileExpiresAfter(
            options.providerOptions,
            providerID: providerID
        )
        for request in options.requests {
            try options.abortSignal?.throwIfAborted()
            let requestModel = OpenAICompatibleResponsesModel(
                modelID: request.modelID ?? modelID,
                config: config
            )
            let prepared = try requestModel.preparedBatchRequest(for: request.request)
            let line: JSONValue = .object([
                "custom_id": .string(request.id),
                "method": .string("POST"),
                "url": .string("/v1/responses"),
                "body": .object(prepared.body)
            ])
            jsonLines.append(try encodeJSONBody(line))
            jsonLines.append(0x0A)
            warnings.append(contentsOf: prepared.warnings.map {
                AIBatchWarning(requestID: request.id, warning: $0)
            })
            for (name, schema) in request.request.tools {
                guard schema["type"]?.stringValue == "provider",
                      let id = schema["id"]?.stringValue,
                      !openAIBatchConvertibleProviderToolIDs.contains(id) else {
                    continue
                }
                warnings.append(AIBatchWarning(
                    requestID: request.id,
                    warning: AIWarning(
                        type: "unsupported",
                        feature: "batch result conversion for tool \"\(schema["name"]?.stringValue ?? name)\"",
                        message: "OpenAI may return output for this tool that AI SDK text batches cannot currently convert."
                    )
                ))
            }
        }

        var form = MultipartFormData()
        form.appendFile(
            name: "file",
            fileName: "batch.jsonl",
            mimeType: "application/jsonl",
            data: jsonLines
        )
        form.appendField(name: "purpose", value: "batch")
        form.appendField(name: "expires_after[anchor]", value: "created_at")
        form.appendField(name: "expires_after[seconds]", value: String(inputFileExpiresAfter))

        let headers = openAIBatchHeaders(
            options.headers,
            idempotencyKey: options.idempotencyKey
        )
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
        let uploadedFile = try parseOpenAIUploadedFile(
            uploadResponse.jsonValue(),
            providerID: providerID
        )

        try options.abortSignal?.throwIfAborted()
        let createRequest = try config.request(
            path: "/batches",
            modelID: modelID,
            body: .object([
                "input_file_id": .string(uploadedFile.id),
                "endpoint": .string("/v1/responses"),
                "completion_window": .string("24h")
            ]),
            headers: headers,
            abortSignal: options.abortSignal
        )
        let createResponse = try await config.transport.send(createRequest)
        guard (200..<300).contains(createResponse.statusCode) else {
            throw openAICompatibleHTTPStatusError(provider: providerID, response: createResponse)
        }
        let batch = try parseOpenAIBatchResponse(
            createResponse.jsonValue(),
            providerID: providerID
        )
        var inputFileMetadata: [String: JSONValue] = [
            "inputFileId": .string(uploadedFile.id)
        ]
        if let expiresAt = uploadedFile.expiresAt.flatMap(openAIBatchISOTimestamp) {
            inputFileMetadata["inputFileExpiresAt"] = .string(expiresAt)
        }

        return AIBatchStartResult(
            batchID: batch.id,
            status: openAIBatchStatus(batch),
            warnings: warnings,
            providerMetadata: ["openai": .object(inputFileMetadata)]
        )
    }

    public func getBatchStatus(_ options: AIBatchOperationOptions) async throws -> AIBatchStatus {
        openAIBatchStatus(try await retrieveBatch(options))
    }

    public func getBatchResults(
        _ options: AIBatchOperationOptions
    ) async throws -> AsyncThrowingStream<AIBatchItemResult<TextGenerationResult>, Error> {
        let batch = try await retrieveBatch(options)
        guard openAIBatchStatus(batch).status != .pending else {
            throw AIError.invalidArgument(
                argument: "batchID",
                message: "OpenAI batch \"\(options.batchID)\" is not complete."
            )
        }

        let fileIDs = [batch.outputFileID, batch.errorFileID].compactMap { $0 }
        if openAIBatchStatus(batch).status == .completed, fileIDs.isEmpty {
            throw AIError.invalidResponse(
                provider: providerID,
                message: "OpenAI batch \"\(options.batchID)\" completed without batch output."
            )
        }
        guard !fileIDs.isEmpty else {
            return AsyncThrowingStream { $0.finish() }
        }

        let config = self.config
        let providerID = self.providerID
        let modelID = self.modelID
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let transport = try requireStreamingTransport(config.transport, providerID: providerID)
                    for fileID in fileIDs {
                        try Task.checkCancellation()
                        try options.abortSignal?.throwIfAborted()
                        let request = AIHTTPRequest(
                            method: "GET",
                            url: try config.url(modelID, "/files/\(openAIBatchPathEncode(fileID))/content"),
                            headers: prepareHeaders(options.headers, defaultHeaders: config.headers),
                            abortSignal: options.abortSignal
                        )
                        let response = try await transport.stream(request)
                        guard (200..<300).contains(response.statusCode) else {
                            let buffered = try await bufferedHTTPResponse(from: response, request: request)
                            throw openAICompatibleHTTPStatusError(provider: providerID, response: buffered)
                        }
                        try await yieldOpenAIBatchResultLines(
                            response.body,
                            providerID: providerID,
                            abortSignal: options.abortSignal,
                            continuation: continuation
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func cancelBatch(_ options: AIBatchOperationOptions) async throws -> AIBatchCancelResult {
        try options.abortSignal?.throwIfAborted()
        let request = try config.request(
            path: "/batches/\(openAIBatchPathEncode(options.batchID))/cancel",
            modelID: modelID,
            body: .object([:]),
            headers: options.headers,
            abortSignal: options.abortSignal
        )
        let response = try await config.transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw openAICompatibleHTTPStatusError(provider: providerID, response: response)
        }
        _ = try parseOpenAIBatchResponse(response.jsonValue(), providerID: providerID)
        return AIBatchCancelResult()
    }

    public func listBatches(_ options: AIBatchListOptions) async throws -> AIBatchListResult {
        try options.abortSignal?.throwIfAborted()
        var components = URLComponents(url: try config.url(modelID, "/batches"), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []
        if let limit = options.limit { queryItems.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let cursor = options.cursor { queryItems.append(URLQueryItem(name: "after", value: cursor)) }
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else {
            throw AIError.invalidURL("\(config.baseURL)/batches")
        }
        let request = AIHTTPRequest(
            method: "GET",
            url: url,
            headers: prepareHeaders(options.headers, defaultHeaders: config.headers),
            abortSignal: options.abortSignal
        )
        let response = try await config.transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw openAICompatibleHTTPStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        guard let data = raw["data"]?.arrayValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Batch list response.")
        }
        let batches = try data.map { value -> AIBatchListItem in
            let batch = try parseOpenAIBatchResponse(value, providerID: providerID)
            return AIBatchListItem(batchID: batch.id, status: openAIBatchStatus(batch))
        }
        let nextCursor = raw["has_more"]?.boolValue == true
            ? raw["last_id"]?.stringValue
            : nil
        return AIBatchListResult(batches: batches, nextCursor: nextCursor)
    }

    private func retrieveBatch(_ options: AIBatchOperationOptions) async throws -> OpenAIBatchResponse {
        try options.abortSignal?.throwIfAborted()
        let request = AIHTTPRequest(
            method: "GET",
            url: try config.url(modelID, "/batches/\(openAIBatchPathEncode(options.batchID))"),
            headers: prepareHeaders(options.headers, defaultHeaders: config.headers),
            abortSignal: options.abortSignal
        )
        let response = try await config.transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw openAICompatibleHTTPStatusError(provider: providerID, response: response)
        }
        return try parseOpenAIBatchResponse(response.jsonValue(), providerID: providerID)
    }
}

/// Provider-owned OpenAI Batch V4 service. It deliberately accepts text only;
/// modality validation happens before upload or batch creation.
public final class OpenAIBatchProvider: AIBatchProvider, @unchecked Sendable {
    public let providerID: String
    public let supportedURLs: [String: [AISupportedURLPattern]] = [
        "image/*": [AISupportedURLPattern { $0.hasPrefix("http://") || $0.hasPrefix("https://") }],
        "application/pdf": [AISupportedURLPattern { $0.hasPrefix("http://") || $0.hasPrefix("https://") }]
    ]
    private let config: ModelHTTPConfig

    init(config: ModelHTTPConfig) {
        let providerRoot = config.providerID.hasSuffix(".responses")
            ? String(config.providerID.dropLast(".responses".count))
            : config.providerID
        self.providerID = "\(providerRoot).batch"
        self.config = config
    }

    public func startBatch(
        _ options: AIBatchStartOptions<AIBatchRequest>
    ) async throws -> AIBatchStartResult {
        var requests: [AILanguageModelBatchRequest] = []
        requests.reserveCapacity(options.requests.count)
        for request in options.requests {
            guard case let .text(text) = request else {
                throw AIError.invalidArgument(
                    argument: "requests",
                    message: "The OpenAI Batch API supports text requests only."
                )
            }
            guard let modelID = text.modelID, !modelID.isEmpty else {
                throw AIError.invalidArgument(
                    argument: "requests",
                    message: "OpenAI text batch request \"\(text.id)\" must specify a modelID."
                )
            }
            requests.append(AILanguageModelBatchRequest(
                id: text.id,
                modelID: modelID,
                request: text.request
            ))
        }
        guard let modelID = requests.first?.modelID else {
            throw AIError.invalidArgument(argument: "requests", message: "requests must not be empty")
        }
        return try await model(for: modelID).startBatch(AIBatchStartOptions(
            requests: requests,
            providerOptions: options.providerOptions,
            abortSignal: options.abortSignal,
            headers: options.headers,
            idempotencyKey: options.idempotencyKey,
            webhookURL: options.webhookURL
        ))
    }

    public func getBatchStatus(_ options: AIBatchOperationOptions) async throws -> AIBatchStatus {
        try await model(for: "batch").getBatchStatus(options)
    }

    public func getBatchResults(
        _ options: AIBatchOperationOptions
    ) async throws -> AsyncThrowingStream<AIBatchV4ItemResult, Error> {
        let stream = try await model(for: "batch").getBatchResults(options)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await item in stream { continuation.yield(.text(item)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func cancelBatch(_ options: AIBatchOperationOptions) async throws -> AIBatchCancelResult {
        try await model(for: "batch").cancelBatch(options)
    }

    public func listBatches(_ options: AIBatchListOptions) async throws -> AIBatchListResult {
        try await model(for: "batch").listBatches(options)
    }

    private func model(for modelID: String) -> OpenAIResponsesBatchLanguageModel {
        OpenAIResponsesBatchLanguageModel(modelID: modelID, config: config)
    }
}

private struct OpenAIBatchResponse: Sendable {
    struct ErrorDetail: Sendable {
        var code: String?
        var message: String?
    }

    var id: String
    var status: String
    var outputFileID: String?
    var errorFileID: String?
    var createdAt: Double?
    var expiresAt: Double?
    var requestCounts: (total: Int, completed: Int, failed: Int)?
    var errors: [ErrorDetail]
}

private struct OpenAIUploadedBatchFile {
    var id: String
    var expiresAt: Double?
}

private func parseOpenAIUploadedFile(_ raw: JSONValue, providerID: String) throws -> OpenAIUploadedBatchFile {
    guard let object = raw.objectValue,
          let id = object["id"]?.stringValue else {
        throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Files upload response.")
    }
    try validateOpenAIOptionalStringFields(
        object,
        keys: ["object", "filename", "purpose", "status"],
        providerID: providerID,
        entity: "OpenAI Files upload response"
    )
    try validateOpenAIOptionalNumberFields(
        object,
        keys: ["bytes", "created_at", "expires_at"],
        providerID: providerID,
        entity: "OpenAI Files upload response"
    )
    return OpenAIUploadedBatchFile(id: id, expiresAt: object["expires_at"]?.doubleValue)
}

private let openAIBatchConvertibleProviderToolIDs: Set<String> = [
    "openai.code_interpreter",
    "openai.custom",
    "openai.file_search",
    "openai.web_search",
    "openai.web_search_preview"
]

private func openAIBatchInputFileExpiresAfter(
    _ providerOptions: [String: JSONValue],
    providerID: String
) throws -> Int {
    let optionsValue = providerID.contains("azure")
        ? (providerOptions["azure"] ?? providerOptions["openai"])
        : providerOptions["openai"]
    guard let optionsValue, optionsValue != .null else { return 172_800 }
    guard let options = optionsValue.objectValue else {
        throw AIError.invalidArgument(
            argument: "providerOptions",
            message: "OpenAI batch provider options must be an object."
        )
    }
    guard let rawValue = options["inputFileExpiresAfter"] else { return 172_800 }
    guard let number = rawValue.doubleValue,
          number.isFinite,
          number.rounded(.towardZero) == number,
          (3_600.0...2_592_000.0).contains(number) else {
        throw AIError.invalidArgument(
            argument: "providerOptions.openai.inputFileExpiresAfter",
            message: "inputFileExpiresAfter must be an integer from 3600 through 2592000."
        )
    }
    return Int(number)
}

private func parseOpenAIBatchResponse(_ raw: JSONValue, providerID: String) throws -> OpenAIBatchResponse {
    guard let object = raw.objectValue,
          let id = object["id"]?.stringValue,
          let status = object["status"]?.stringValue else {
        throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Batch response.")
    }
    try validateOpenAIOptionalStringFields(
        object,
        keys: ["output_file_id", "error_file_id"],
        providerID: providerID,
        entity: "OpenAI Batch response"
    )
    try validateOpenAIOptionalNumberFields(
        object,
        keys: ["created_at", "expires_at"],
        providerID: providerID,
        entity: "OpenAI Batch response"
    )

    var counts: (total: Int, completed: Int, failed: Int)?
    if let rawCounts = object["request_counts"], rawCounts != .null {
        guard let countObject = rawCounts.objectValue else {
            throw AIError.invalidResponse(provider: providerID, message: "OpenAI Batch request_counts must be an object.")
        }
        try validateOpenAIOptionalNumberFields(
            countObject,
            keys: ["total", "completed", "failed"],
            providerID: providerID,
            entity: "OpenAI Batch request_counts"
        )
        if let total = normalizedBatchJSONInteger(countObject["total"]),
           let completed = normalizedBatchJSONInteger(countObject["completed"]),
           let failed = normalizedBatchJSONInteger(countObject["failed"]) {
            counts = (total, completed, failed)
        }
    }

    var errors: [OpenAIBatchResponse.ErrorDetail] = []
    if let rawErrors = object["errors"], rawErrors != .null {
        guard let errorObject = rawErrors.objectValue else {
            throw AIError.invalidResponse(provider: providerID, message: "OpenAI Batch errors must be an object.")
        }
        if let rawData = errorObject["data"], rawData != .null {
            guard let data = rawData.arrayValue else {
                throw AIError.invalidResponse(provider: providerID, message: "OpenAI Batch errors.data must be an array.")
            }
            errors = try data.map { value in
                guard let detail = value.objectValue else {
                    throw AIError.invalidResponse(provider: providerID, message: "OpenAI Batch error detail must be an object.")
                }
                try validateOpenAIOptionalStringFields(
                    detail,
                    keys: ["code", "message"],
                    providerID: providerID,
                    entity: "OpenAI Batch error detail"
                )
                return OpenAIBatchResponse.ErrorDetail(
                    code: detail["code"]?.stringValue,
                    message: detail["message"]?.stringValue
                )
            }
        }
    }

    return OpenAIBatchResponse(
        id: id,
        status: status,
        outputFileID: object["output_file_id"]?.stringValue,
        errorFileID: object["error_file_id"]?.stringValue,
        createdAt: object["created_at"]?.doubleValue,
        expiresAt: object["expires_at"]?.doubleValue,
        requestCounts: counts,
        errors: errors
    )
}

private func openAIBatchStatus(_ batch: OpenAIBatchResponse) -> AIBatchStatus {
    let status: AIBatchLifecycleStatus
    switch batch.status {
    case "completed":
        status = .completed
    case "failed", "expired", "cancelled":
        status = .failed
    default:
        status = .pending
    }

    let requestCounts = batch.requestCounts.flatMap { counts -> AIBatchRequestCounts? in
        guard let completedAndFailed = checkedBatchSafeIntegerSum([
            counts.completed,
            counts.failed
        ]), completedAndFailed <= counts.total else {
            return nil
        }
        return normalizedBatchRequestCounts(
            total: counts.total,
            pending: counts.total - counts.completed - counts.failed,
            completed: counts.completed,
            failed: counts.failed
        )
    }
    let error = batch.errors.first.map {
        AIBatchError(
            message: $0.message ?? "OpenAI batch failed.",
            code: $0.code
        )
    }

    return AIBatchStatus(
        status: status,
        rawStatus: batch.status,
        requestCounts: requestCounts,
        error: error,
        createdAt: batch.createdAt.flatMap(openAIBatchISOTimestamp),
        expiresAt: batch.expiresAt.flatMap(openAIBatchISOTimestamp)
    )
}

private func yieldOpenAIBatchResultLines(
    _ body: AsyncThrowingStream<Data, Error>,
    providerID: String,
    abortSignal: AIAbortSignal?,
    continuation: AsyncThrowingStream<AIBatchItemResult<TextGenerationResult>, Error>.Continuation
) async throws {
    var buffer = Data()
    for try await chunk in body {
        try Task.checkCancellation()
        try abortSignal?.throwIfAborted()
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if let item = try parseOpenAIBatchResultLine(line, providerID: providerID) {
                continuation.yield(item)
            }
        }
    }
    if let item = try parseOpenAIBatchResultLine(buffer, providerID: providerID) {
        continuation.yield(item)
    }
}

private func parseOpenAIBatchResultLine(
    _ data: Data,
    providerID: String
) throws -> AIBatchItemResult<TextGenerationResult>? {
    var line = data
    if line.last == 0x0D { line.removeLast() }
    guard let text = String(data: line, encoding: .utf8) else {
        throw AIError.invalidResponse(provider: providerID, message: "OpenAI Batch result line is not valid UTF-8.")
    }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

    let raw = try secureJSONParse(text)
    guard let object = raw.objectValue,
          let customID = object["custom_id"]?.stringValue else {
        throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Batch result line.")
    }

    let response: [String: JSONValue]?
    if let rawResponse = object["response"], rawResponse != .null {
        guard let responseObject = rawResponse.objectValue,
              normalizedBatchJSONInteger(responseObject["status_code"]) != nil,
              responseObject["body"] != nil else {
            throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Batch result response.")
        }
        try validateOpenAIOptionalStringFields(
            responseObject,
            keys: ["request_id"],
            providerID: providerID,
            entity: "OpenAI Batch result response"
        )
        response = responseObject
    } else {
        response = nil
    }

    let lineError: [String: JSONValue]?
    if let rawError = object["error"], rawError != .null {
        guard let errorObject = rawError.objectValue,
              errorObject["code"]?.stringValue != nil,
              errorObject["message"]?.stringValue != nil else {
            throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Batch result error.")
        }
        lineError = errorObject
    } else {
        lineError = nil
    }

    if let lineError {
        let error = AIBatchError(
            message: lineError["message"]?.stringValue ?? "OpenAI batch item failed.",
            code: lineError["code"]?.stringValue
        )
        switch lineError["code"]?.stringValue {
        case "batch_cancelled":
            return .cancelled(id: customID, error: error)
        case "batch_expired":
            return .expired(id: customID, error: error)
        default:
            return .failed(id: customID, error: error)
        }
    }

    guard let response else {
        return .failed(
            id: customID,
            error: AIBatchError(
                message: "OpenAI returned a batch result without a response or error.",
                code: "invalid_batch_result"
            )
        )
    }

    let statusCode = normalizedBatchJSONInteger(response["status_code"]) ?? 0
    let responseBody = response["body"] ?? .null
    guard (200..<300).contains(statusCode) else {
        return .failed(
            id: customID,
            error: openAIBatchItemHTTPError(body: responseBody, statusCode: statusCode)
        )
    }

    do {
        switch try convertOpenAIResponsesBatchBody(responseBody, providerID: providerID) {
        case let .success(result):
            return .succeeded(id: customID, result: result)
        case let .failure(error):
            return .failed(id: customID, error: error)
        }
    } catch {
        return invalidOpenAIResponsesBatchResult(id: customID)
    }
}

private func invalidOpenAIResponsesBatchResult(
    id: String
) -> AIBatchItemResult<TextGenerationResult> {
    .failed(
        id: id,
        error: AIBatchError(
            message: "OpenAI returned an invalid Responses batch result.",
            code: "invalid_response"
        )
    )
}

private enum OpenAIResponsesBatchConversion {
    case success(TextGenerationResult)
    case failure(AIBatchError)
}

private func convertOpenAIResponsesBatchBody(
    _ raw: JSONValue,
    providerID: String
) throws -> OpenAIResponsesBatchConversion {
    let output = try validateOpenAIResponsesBatchBody(raw, providerID: providerID)
    if let error = raw["error"], error != .null {
        return .failure(AIBatchError(
            message: error["message"]?.stringValue ?? "OpenAI Responses failed.",
            type: error["type"]?.stringValue,
            code: error["code"]?.stringValue
        ))
    }
    guard let output else {
        let detail = raw["incomplete_details"]?["reason"]?.stringValue
        return .failure(AIBatchError(
            message: detail.map { "OpenAI Responses returned no output (\($0))." }
                ?? "OpenAI Responses returned no output.",
            code: "invalid_response"
        ))
    }

    var content: [AIResultContentPart] = []
    var hasClientToolCall = false
    for item in output {
        switch item["type"]?.stringValue {
        case "reasoning":
            content.append(contentsOf: openAIResponsesOutputContentItem(
                from: item,
                providerID: providerID
            ))
        case "message":
            for part in item["content"]?.arrayValue ?? [] {
                content.append(.text(part["text"]?.stringValue ?? ""))
            }
        case "function_call", "custom_tool_call":
            guard let call = openAIResponsesToolCall(from: item, providerID: providerID) else {
                return .failure(AIBatchError(
                    message: "OpenAI returned an invalid tool call in an AI SDK text batch.",
                    code: "invalid_response"
                ))
            }
            hasClientToolCall = true
            content.append(.toolCall(call))
        case "web_search_call", "file_search_call", "code_interpreter_call":
            guard var call = openAIResponsesToolCall(from: item, providerID: providerID),
                  var result = openAIResponsesToolResult(from: item, providerID: providerID) else {
                return .failure(AIBatchError(
                    message: "OpenAI returned invalid provider tool output in an AI SDK text batch.",
                    code: "invalid_response"
                ))
            }
            call.dynamic = true
            call.providerExecuted = true
            result.dynamic = true
            content.append(.toolCall(call))
            content.append(.toolResult(result))
        default:
            let type = item["type"]?.stringValue ?? "unknown"
            return .failure(AIBatchError(
                message: "OpenAI returned an unsupported \"\(type)\" output item in an AI SDK text batch.",
                code: "unsupported_content"
            ))
        }
    }

    let incompleteReason = raw["incomplete_details"]?["reason"]?.stringValue
    let text = content.compactMap { part -> String? in
        guard case let .text(text, _) = part else { return nil }
        return text
    }.joined()
    return .success(TextGenerationResult(
        text: text,
        content: content,
        finishReason: openResponsesFinishReason(
            incompleteReason: incompleteReason,
            hasToolCalls: hasClientToolCall
        ),
        usage: tokenUsage(from: raw),
        providerMetadata: openAIBatchProviderMetadata(from: raw, providerID: providerID),
        rawValue: raw,
        responseMetadata: AIResponseMetadata(
            id: raw["id"]?.stringValue,
            timestamp: raw["created_at"]?.doubleValue.map(Date.init(timeIntervalSince1970:)),
            modelID: raw["model"]?.stringValue
        )
    ))
}

private func openAIBatchProviderMetadata(
    from raw: JSONValue,
    providerID: String
) -> [String: JSONValue] {
    var providerMetadata = openAIResponsesProviderMetadata(from: raw, providerID: providerID)
    let namespace = openAICompatibleProviderMetadataNamespace(providerID)
    var metadata = providerMetadata[namespace]?.objectValue ?? [:]
    let logprobs = raw["output"]?.arrayValue?.flatMap { item in
        item["content"]?.arrayValue?.compactMap { part -> JSONValue? in
            guard let value = part["logprobs"], value != .null else { return nil }
            return value
        } ?? []
    } ?? []
    if logprobs.isEmpty {
        metadata.removeValue(forKey: "logprobs")
    } else {
        metadata["logprobs"] = .array(logprobs)
    }
    if metadata.isEmpty {
        providerMetadata.removeValue(forKey: namespace)
    } else {
        providerMetadata[namespace] = .object(metadata)
    }
    return providerMetadata
}

private func validateOpenAIResponsesBatchBody(
    _ raw: JSONValue,
    providerID: String
) throws -> [JSONValue]? {
    guard let object = raw.objectValue else {
        throw AIError.invalidResponse(provider: providerID, message: "OpenAI Responses batch body must be an object.")
    }
    try validateOpenAIOptionalStringFields(
        object,
        keys: ["id", "model", "service_tier"],
        providerID: providerID,
        entity: "OpenAI Responses batch body"
    )
    try validateOpenAIOptionalNumberFields(
        object,
        keys: ["created_at"],
        providerID: providerID,
        entity: "OpenAI Responses batch body"
    )

    if let rawError = object["error"], rawError != .null {
        guard let error = rawError.objectValue,
              error["message"]?.stringValue != nil,
              error["type"]?.stringValue != nil,
              error["code"]?.stringValue != nil else {
            throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses error body.")
        }
        try validateOpenAIOptionalStringFields(
            error,
            keys: ["param"],
            providerID: providerID,
            entity: "OpenAI Responses error body"
        )
    }
    if let incomplete = object["incomplete_details"], incomplete != .null {
        guard let details = incomplete.objectValue,
              details["reason"]?.stringValue != nil else {
            throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses incomplete_details.")
        }
    }
    if let reasoning = object["reasoning"], reasoning != .null {
        guard let reasoningObject = reasoning.objectValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses reasoning metadata.")
        }
        try validateOpenAIOptionalStringFields(
            reasoningObject,
            keys: ["context"],
            providerID: providerID,
            entity: "OpenAI Responses reasoning metadata"
        )
    }
    if let usage = object["usage"], usage != .null {
        guard let usageObject = usage.objectValue,
              usageObject["input_tokens"]?.doubleValue != nil,
              usageObject["output_tokens"]?.doubleValue != nil else {
            throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses usage.")
        }
        for key in ["input_tokens_details", "output_tokens_details"] {
            if let details = usageObject[key], details != .null, details.objectValue == nil {
                throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses \(key).")
            }
        }
    }

    guard let rawOutput = object["output"] else { return nil }
    guard rawOutput != .null, let output = rawOutput.arrayValue else {
        if rawOutput == .null { return nil }
        throw AIError.invalidResponse(provider: providerID, message: "OpenAI Responses output must be an array.")
    }

    let ignoredOutputTypes: Set<String> = [
        "image_generation_call", "local_shell_call", "program", "program_output",
        "computer_call", "reasoning", "mcp_call", "mcp_list_tools",
        "mcp_approval_request", "apply_patch_call", "shell_call", "compaction",
        "shell_call_output", "tool_search_call", "tool_search_output"
    ]
    for item in output {
        guard let itemObject = item.objectValue,
              let type = itemObject["type"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses output item.")
        }
        switch type {
        case "message":
            guard itemObject["role"]?.stringValue == "assistant",
                  itemObject["id"]?.stringValue != nil,
                  let parts = itemObject["content"]?.arrayValue else {
                throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses message output.")
            }
            for part in parts {
                guard part["type"]?.stringValue == "output_text",
                      part["text"]?.stringValue != nil,
                      part["annotations"]?.arrayValue != nil else {
                    throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses output_text part.")
                }
                if let logprobs = part["logprobs"], logprobs != .null, logprobs.arrayValue == nil {
                    throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses output_text logprobs.")
                }
            }
        case "function_call":
            guard itemObject["call_id"]?.stringValue != nil,
                  itemObject["name"]?.stringValue != nil,
                  itemObject["arguments"]?.stringValue != nil,
                  itemObject["id"]?.stringValue != nil else {
                throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses function_call output.")
            }
        case "custom_tool_call":
            guard itemObject["call_id"]?.stringValue != nil,
                  itemObject["name"]?.stringValue != nil,
                  itemObject["input"]?.stringValue != nil,
                  itemObject["id"]?.stringValue != nil else {
                throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses custom_tool_call output.")
            }
        case "web_search_call":
            try validateOpenAIBatchWebSearchOutput(itemObject, providerID: providerID)
        case "file_search_call":
            try validateOpenAIBatchFileSearchOutput(itemObject, providerID: providerID)
        case "code_interpreter_call":
            try validateOpenAIBatchCodeInterpreterOutput(itemObject, providerID: providerID)
        case "reasoning":
            guard itemObject["id"]?.stringValue != nil,
                  let summaries = itemObject["summary"]?.arrayValue,
                  summaries.allSatisfy({ summary in
                      summary["type"]?.stringValue == "summary_text"
                          && summary["text"]?.stringValue != nil
                  }),
                  isNullishOpenAIString(itemObject["encrypted_content"]) else {
                throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses reasoning output.")
            }
        default:
            guard ignoredOutputTypes.contains(type) else {
                throw AIError.invalidResponse(provider: providerID, message: "Unknown OpenAI Responses output type \"\(type)\".")
            }
        }
    }
    return output
}

private func validateOpenAIBatchWebSearchOutput(
    _ item: [String: JSONValue],
    providerID: String
) throws {
    guard item["id"]?.stringValue != nil,
          item["status"]?.stringValue != nil else {
        throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses web_search_call output.")
    }
    guard let rawAction = item["action"], rawAction != .null else { return }
    guard let action = rawAction.objectValue,
          let type = action["type"]?.stringValue else {
        throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses web_search_call action.")
    }
    switch type {
    case "search":
        guard isNullishOpenAIString(action["query"]),
              isNullishOpenAIStringArray(action["queries"]),
              isNullishOpenAIWebSearchSources(action["sources"]) else {
            throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses web_search_call search action.")
        }
    case "open_page":
        guard isNullishOpenAIString(action["url"]) else {
            throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses web_search_call open_page action.")
        }
    case "find_in_page":
        guard isNullishOpenAIString(action["url"]),
              isNullishOpenAIString(action["pattern"]) else {
            throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses web_search_call find_in_page action.")
        }
    default:
        throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses web_search_call action type.")
    }
}

private func validateOpenAIBatchFileSearchOutput(
    _ item: [String: JSONValue],
    providerID: String
) throws {
    guard item["id"]?.stringValue != nil,
          let queries = item["queries"]?.arrayValue,
          queries.allSatisfy({ $0.stringValue != nil }) else {
        throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses file_search_call output.")
    }
    guard let rawResults = item["results"], rawResults != .null else { return }
    guard let results = rawResults.arrayValue,
          results.allSatisfy({ value in
              guard let result = value.objectValue,
                    let attributes = result["attributes"]?.objectValue,
                    attributes.values.allSatisfy(isOpenAIFileSearchAttribute),
                    result["file_id"]?.stringValue != nil,
                    result["filename"]?.stringValue != nil,
                    let score = result["score"]?.doubleValue,
                    score.isFinite,
                    result["text"]?.stringValue != nil else {
                  return false
              }
              return true
          }) else {
        throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses file_search_call results.")
    }
}

private func validateOpenAIBatchCodeInterpreterOutput(
    _ item: [String: JSONValue],
    providerID: String
) throws {
    guard item["id"]?.stringValue != nil,
          item["container_id"]?.stringValue != nil,
          item.keys.contains("code"),
          isNullishOpenAIString(item["code"]),
          item.keys.contains("outputs") else {
        throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses code_interpreter_call output.")
    }
    guard let rawOutputs = item["outputs"], rawOutputs != .null else { return }
    guard let outputs = rawOutputs.arrayValue,
          outputs.allSatisfy({ value in
              guard let output = value.objectValue,
                    let type = output["type"]?.stringValue else {
                  return false
              }
              switch type {
              case "logs": return output["logs"]?.stringValue != nil
              case "image": return output["url"]?.stringValue != nil
              default: return false
              }
          }) else {
        throw AIError.invalidResponse(provider: providerID, message: "Invalid OpenAI Responses code_interpreter_call outputs.")
    }
}

private func isNullishOpenAIStringArray(_ value: JSONValue?) -> Bool {
    guard let value, value != .null else { return true }
    guard let values = value.arrayValue else { return false }
    return values.allSatisfy { $0.stringValue != nil }
}

private func isNullishOpenAIWebSearchSources(_ value: JSONValue?) -> Bool {
    guard let value, value != .null else { return true }
    guard let sources = value.arrayValue else { return false }
    return sources.allSatisfy { value in
        guard let source = value.objectValue,
              let type = source["type"]?.stringValue else {
            return false
        }
        switch type {
        case "url": return source["url"]?.stringValue != nil
        case "api": return source["name"]?.stringValue != nil
        default: return false
        }
    }
}

private func isOpenAIFileSearchAttribute(_ value: JSONValue) -> Bool {
    if value.stringValue != nil || value.boolValue != nil { return true }
    return value.doubleValue?.isFinite == true
}

private func isNullishOpenAIString(_ value: JSONValue?) -> Bool {
    value == nil || value == .null || value?.stringValue != nil
}

private func openAIBatchItemHTTPError(body: JSONValue, statusCode: Int) -> AIBatchError {
    guard let error = body["error"]?.objectValue,
          let message = error["message"]?.stringValue else {
        return AIBatchError(
            message: "OpenAI batch request failed with status code \(statusCode).",
            statusCode: statusCode
        )
    }
    return AIBatchError(
        message: message,
        type: error["type"]?.stringValue,
        code: openAIBatchErrorCode(error["code"]),
        statusCode: statusCode
    )
}

private func openAIBatchErrorCode(_ value: JSONValue?) -> String? {
    if let string = value?.stringValue { return string }
    if let number = value?.doubleValue {
        if number.isFinite,
           number.rounded(.towardZero) == number,
           (-Double(aiBatchMaximumSafeInteger)...Double(aiBatchMaximumSafeInteger)).contains(number) {
            return String(Int(number))
        }
        return String(number)
    }
    return nil
}

private func openAIBatchHeaders(
    _ headers: [String: String],
    idempotencyKey: String?
) -> [String: String] {
    var output = headers
    if let idempotencyKey,
       normalizeHeaders(output)["idempotency-key"] == nil {
        output["idempotency-key"] = idempotencyKey
    }
    return output
}

private func validateOpenAIOptionalStringFields(
    _ object: [String: JSONValue],
    keys: [String],
    providerID: String,
    entity: String
) throws {
    for key in keys {
        if let value = object[key], value != .null, value.stringValue == nil {
            throw AIError.invalidResponse(provider: providerID, message: "\(entity) field \(key) must be a string.")
        }
    }
}

private func validateOpenAIOptionalNumberFields(
    _ object: [String: JSONValue],
    keys: [String],
    providerID: String,
    entity: String
) throws {
    for key in keys {
        if let value = object[key], value != .null, value.doubleValue == nil {
            throw AIError.invalidResponse(provider: providerID, message: "\(entity) field \(key) must be a number.")
        }
    }
}

private func openAIBatchISOTimestamp(_ value: Double) -> String? {
    guard value.isFinite else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date(timeIntervalSince1970: value))
}

private func openAIBatchPathEncode(_ value: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}
