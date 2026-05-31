import Foundation

public final class CohereLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "cohere.chat"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let raw = try await config.sendJSON(path: "/chat", modelID: modelID, body: .object(body(for: request, stream: false)), headers: request.headers)
        let text = raw["message"]?["content"]?.arrayValue?.compactMap { item in
            item["type"]?.stringValue == "text" ? item["text"]?.stringValue : nil
        }.joined() ?? ""
        let toolCalls = cohereToolCalls(from: raw["message"]?["tool_calls"])
        guard !text.isEmpty || raw["message"] != nil else {
            throw AIError.invalidResponse(provider: providerID, message: "No Cohere message content found.")
        }
        return TextGenerationResult(
            text: text,
            finishReason: mapCohereFinishReason(raw["finish_reason"]?.stringValue),
            usage: cohereTokenUsage(from: raw),
            toolCalls: toolCalls,
            sources: cohereSources(from: raw["message"]?["citations"]),
            rawValue: raw
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let httpRequest = try config.request(path: "/chat", modelID: modelID, body: .object(body(for: request, stream: true)), headers: request.headers)
                    let response = try await config.transport.send(httpRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        throw httpStatusError(provider: providerID, response: response)
                    }
                    var finishReason: String?
                    var usage: TokenUsage?
                    var pendingToolCall: CoherePendingToolCall?
                    for event in parseServerSentEvents(response.body) {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        continuation.yield(.raw(raw))
                        switch raw["type"]?.stringValue {
                        case "content-delta":
                            if let text = raw["delta"]?["message"]?["content"]?["text"]?.stringValue {
                                continuation.yield(.textDelta(text))
                            }
                            if let thinking = raw["delta"]?["message"]?["content"]?["thinking"]?.stringValue {
                                continuation.yield(.reasoningDelta(thinking))
                            }
                        case "tool-call-start":
                            let toolCall = raw["delta"]?["message"]?["tool_calls"]
                            if let id = toolCall?["id"]?.stringValue,
                               let name = toolCall?["function"]?["name"]?.stringValue {
                                let arguments = toolCall?["function"]?["arguments"]?.stringValue ?? ""
                                pendingToolCall = CoherePendingToolCall(id: id, name: name, arguments: arguments, rawValue: toolCall)
                                continuation.yield(.toolCallDelta(id: id, name: name, argumentsDelta: arguments, index: nil))
                            }
                        case "tool-call-delta":
                            let arguments = raw["delta"]?["message"]?["tool_calls"]?["function"]?["arguments"]?.stringValue ?? ""
                            if var pending = pendingToolCall {
                                pending.arguments += arguments
                                pending.rawValue = raw["delta"]?["message"]?["tool_calls"] ?? pending.rawValue
                                pendingToolCall = pending
                                continuation.yield(.toolCallDelta(id: pending.id, name: pending.name, argumentsDelta: arguments, index: nil))
                            }
                        case "tool-call-end":
                            if let pending = pendingToolCall {
                                continuation.yield(.toolCall(AIToolCall(
                                    id: pending.id,
                                    name: pending.name,
                                    arguments: cohereToolArguments(pending.arguments),
                                    rawValue: pending.rawValue
                                )))
                                pendingToolCall = nil
                            }
                        case "message-end":
                            finishReason = mapCohereFinishReason(raw["delta"]?["finish_reason"]?.stringValue)
                            usage = cohereTokenUsage(from: raw["delta"] ?? raw)
                        default:
                            break
                        }
                    }
                    continuation.yield(.finish(reason: finishReason, usage: usage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func body(for request: LanguageModelRequest, stream: Bool) -> [String: JSONValue] {
        let options = cohereProviderOptions(from: request.extraBody)
        let prompt = coherePromptJSON(from: request.messages)
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "messages": .array(prompt.messages)
        ]
        if !prompt.documents.isEmpty { body["documents"] = .array(prompt.documents) }
        if stream { body["stream"] = true }
        if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
        if let temperature = request.temperature { body["temperature"] = .number(temperature) }
        if let topP = request.topP { body["p"] = .number(topP) }
        if !request.stopSequences.isEmpty { body["stop_sequences"] = .array(request.stopSequences) }
        if let thinking = options["thinking"] { body["thinking"] = thinking }
        if !request.tools.isEmpty { body["tools"] = .object(request.tools) }
        body.merge(options.filter { $0.key != "thinking" }) { _, new in new }
        return body
    }
}

private struct CoherePendingToolCall {
    var id: String
    var name: String
    var arguments: String
    var rawValue: JSONValue?
}

public final class CohereEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    public let providerID = "cohere.textEmbedding"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        let options = cohereProviderOptions(from: request.extraBody)
        guard request.values.count <= 96 else {
            throw AIError.invalidResponse(provider: providerID, message: "Cohere supports at most 96 embedding inputs per call.")
        }
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "embedding_types": .array(["float"]),
            "texts": .array(request.values),
            "input_type": options["inputType"] ?? options["input_type"] ?? .string("search_query")
        ]
        if let dimensions = request.dimensions {
            body["output_dimension"] = .number(Double(dimensions))
        }
        for (key, value) in options {
            switch key {
            case "inputType":
                body["input_type"] = value
            case "outputDimension":
                body["output_dimension"] = value
            default:
                body[key] = value
            }
        }
        let raw = try await config.sendJSON(path: "/embed", modelID: modelID, body: .object(body), headers: request.headers)
        let embeddings = raw["embeddings"]?["float"]?.arrayValue?.map { $0.arrayValue?.compactMap(\.doubleValue) ?? [] } ?? []
        return EmbeddingResult(
            embeddings: embeddings,
            usage: TokenUsage(totalTokens: raw["meta"]?["billed_units"]?["input_tokens"]?.intValue),
            rawValue: raw
        )
    }
}

public final class CohereRerankingModel: RerankingModel, @unchecked Sendable {
    public let providerID = "cohere.reranking"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func rerank(_ request: RerankingRequest) async throws -> RerankingResult {
        let options = cohereProviderOptions(from: request.extraBody)
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "query": .string(request.query),
            "documents": .array(request.documents)
        ]
        if let topK = request.topK { body["top_n"] = .number(Double(topK)) }
        for (key, value) in options {
            switch key {
            case "maxTokensPerDoc":
                body["max_tokens_per_doc"] = value
            default:
                body[key] = value
            }
        }
        let raw = try await config.sendJSON(path: "/rerank", modelID: modelID, body: .object(body), headers: request.headers)
        return RerankingResult(results: rerankingResults(from: raw["results"]), rawValue: raw)
    }
}

public final class VoyageEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    public let providerID = "voyage.embedding"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        let options = voyageProviderOptions(from: request.extraBody)
        guard request.values.count <= 128 else {
            throw AIError.invalidResponse(provider: providerID, message: "Voyage supports at most 128 embedding inputs per call.")
        }
        var body: [String: JSONValue] = [
            "input": .array(request.values),
            "model": .string(modelID)
        ]
        if let dimensions = request.dimensions {
            body["output_dimension"] = .number(Double(dimensions))
        }
        for (key, value) in options {
            switch key {
            case "inputType":
                body["input_type"] = value
            case "outputDimension":
                body["output_dimension"] = value
            case "outputDtype":
                body["output_dtype"] = value
            default:
                body[key] = value
            }
        }
        let raw = try await config.sendJSON(path: "/embeddings", modelID: modelID, body: .object(body), headers: request.headers)
        let items = raw["data"]?.arrayValue ?? []
        let embeddings = items.sorted { ($0["index"]?.intValue ?? 0) < ($1["index"]?.intValue ?? 0) }
            .map { $0["embedding"]?.arrayValue?.compactMap(\.doubleValue) ?? [] }
        return EmbeddingResult(embeddings: embeddings, usage: TokenUsage(totalTokens: raw["usage"]?["total_tokens"]?.intValue), rawValue: raw)
    }
}

public final class VoyageRerankingModel: RerankingModel, @unchecked Sendable {
    public let providerID = "voyage.reranking"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func rerank(_ request: RerankingRequest) async throws -> RerankingResult {
        let options = voyageProviderOptions(from: request.extraBody)
        var body: [String: JSONValue] = [
            "query": .string(request.query),
            "documents": .array(request.documents),
            "model": .string(modelID)
        ]
        if let topK = request.topK { body["top_k"] = .number(Double(topK)) }
        for (key, value) in options {
            switch key {
            case "returnDocuments":
                body["return_documents"] = value
            default:
                body[key] = value
            }
        }
        let raw = try await config.sendJSON(path: "/rerank", modelID: modelID, body: .object(body), headers: request.headers)
        return RerankingResult(results: rerankingResults(from: raw["data"]), rawValue: raw)
    }
}

private func cohereProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "cohere")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func voyageProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "voyage")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func coherePromptJSON(from messages: [AIMessage]) -> (messages: [JSONValue], documents: [JSONValue]) {
    var cohereMessages: [JSONValue] = []
    var documents: [JSONValue] = []

    for message in messages {
        let converted = cohereMessageJSON(message)
        cohereMessages.append(converted.message)
        documents.append(contentsOf: converted.documents)
    }

    return (cohereMessages, documents)
}

private func cohereMessageJSON(_ message: AIMessage) -> (message: JSONValue, documents: [JSONValue]) {
    switch message.role {
    case .system:
        return (.object(["role": .string("system"), "content": .string(message.combinedText)]), [])
    case .assistant:
        return (.object(["role": .string("assistant"), "content": .string(message.combinedText)]), [])
    case .tool:
        return (.object(["role": .string("tool"), "content": .string(message.combinedText)]), [])
    case .user:
        let hasImage = message.content.contains {
            if let payload = $0.filePayload { return payload.mimeType.hasPrefix("image/") }
            if case .imageURL = $0 { return true }
            return false
        }
        let documents = message.content.compactMap(cohereDocumentJSON)
        guard hasImage else {
            let text = message.content.compactMap(\.text).joined()
            return (.object(["role": .string("user"), "content": .string(text)]), documents)
        }
        return (.object([
            "role": .string("user"),
            "content": .array(message.content.compactMap(cohereContentPartJSON))
        ]), documents)
    }
}

private func cohereContentPartJSON(_ part: AIContentPart) -> JSONValue? {
    switch part {
    case let .text(text):
        return text.isEmpty ? nil : .object(["type": .string("text"), "text": .string(text)])
    case let .imageURL(url):
        return .object(["type": .string("image_url"), "image_url": .object(["url": .string(url)])])
    case let .data(mimeType, data) where mimeType.hasPrefix("image/"),
         let .file(mimeType, data, _) where mimeType.hasPrefix("image/"):
        return .object([
            "type": .string("image_url"),
            "image_url": .object(["url": .string("data:\(mimeType);base64,\(data.base64EncodedString())")])
        ])
    case .data, .file, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
        return nil
    }
}

private func cohereDocumentJSON(_ part: AIContentPart) -> JSONValue? {
    guard let payload = part.filePayload, !payload.mimeType.hasPrefix("image/") else {
        return nil
    }
    var data: [String: JSONValue] = [
        "text": .string(String(decoding: payload.data, as: UTF8.self))
    ]
    if let filename = payload.filename { data["title"] = .string(filename) }
    return .object(["data": .object(data)])
}

private func mapCohereFinishReason(_ reason: String?) -> String? {
    switch reason {
    case "COMPLETE", "STOP_SEQUENCE":
        return "stop"
    case "MAX_TOKENS":
        return "length"
    case "ERROR":
        return "error"
    case "TOOL_CALL":
        return "tool-calls"
    default:
        return reason
    }
}

private func cohereToolCalls(from value: JSONValue?) -> [AIToolCall] {
    value?.arrayValue?.enumerated().compactMap { index, item in
        guard let name = item["function"]?["name"]?.stringValue else { return nil }
        return AIToolCall(
            id: item["id"]?.stringValue ?? "tool-call-\(index)",
            name: name,
            arguments: cohereToolArguments(item["function"]?["arguments"]?.stringValue ?? ""),
            rawValue: item
        )
    } ?? []
}

private func cohereSources(from value: JSONValue?) -> [AISource] {
    value?.arrayValue?.enumerated().map { index, citation in
        let document = citation["sources"]?[0]?["document"]
        var metadata: [String: JSONValue] = [:]
        if let start = citation["start"] { metadata["start"] = start }
        if let end = citation["end"] { metadata["end"] = end }
        if let text = citation["text"] { metadata["text"] = text }
        if let sources = citation["sources"] { metadata["sources"] = sources }
        if let citationType = citation["type"] { metadata["citationType"] = citationType }
        return AISource(
            id: "cohere-citation-\(index)",
            sourceType: "document",
            title: document?["title"]?.stringValue ?? "Document",
            mediaType: "text/plain",
            providerMetadata: ["cohere": .object(metadata)],
            rawValue: citation
        )
    } ?? []
}

private func cohereToolArguments(_ arguments: String) -> String {
    let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed == "null" {
        return "{}"
    }
    return trimmed
}

private func cohereTokenUsage(from raw: JSONValue) -> TokenUsage? {
    guard let tokens = raw["usage"]?["tokens"] else { return nil }
    return TokenUsage(
        inputTokens: tokens["input_tokens"]?.intValue,
        outputTokens: tokens["output_tokens"]?.intValue,
        totalTokens: (tokens["input_tokens"]?.intValue).flatMap { input in
            (tokens["output_tokens"]?.intValue).map { input + $0 }
        }
    )
}

private func rerankingResults(from value: JSONValue?) -> [RerankedDocument] {
    value?.arrayValue?.compactMap { item in
        guard let index = item["index"]?.intValue ?? item["document_index"]?.intValue,
              let score = item["relevance_score"]?.doubleValue ?? item["score"]?.doubleValue else {
            return nil
        }
        return RerankedDocument(index: index, score: score, document: item["document"]?.stringValue)
    } ?? []
}
