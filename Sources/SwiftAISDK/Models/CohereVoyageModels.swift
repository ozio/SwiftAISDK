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
        let prepared = try body(for: request, stream: false)
        let response = try await config.sendJSONResponse(
            path: "/chat",
            modelID: modelID,
            body: .object(prepared.body),
            headers: request.headers,
            abortSignal: request.abortSignal
        )
        let raw = response.json
        let text = raw["message"]?["content"]?.arrayValue?.compactMap { item in
            item["type"]?.stringValue == "text" ? item["text"]?.stringValue : nil
        }.joined() ?? ""
        let reasoning = raw["message"]?["content"]?.arrayValue?.compactMap { item in
            item["type"]?.stringValue == "thinking" ? item["thinking"]?.stringValue : nil
        }.joined() ?? ""
        let toolCalls = cohereToolCalls(from: raw["message"]?["tool_calls"])
        guard !text.isEmpty || !reasoning.isEmpty || raw["message"] != nil else {
            throw AIError.invalidResponse(provider: providerID, message: "No Cohere message content found.")
        }
        return TextGenerationResult(
            text: text,
            reasoning: reasoning,
            finishReason: mapCohereFinishReason(raw["finish_reason"]?.stringValue),
            usage: cohereTokenUsage(from: raw),
            toolCalls: toolCalls,
            sources: cohereSources(from: raw["message"]?["citations"]),
            rawValue: raw,
            warnings: prepared.warnings,
            responseMetadata: cohereResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = try body(for: request, stream: true)
                    let httpRequest = try config.request(
                        path: "/chat",
                        modelID: modelID,
                        body: .object(prepared.body),
                        headers: request.headers,
                        abortSignal: request.abortSignal
                    )
                    let response = try await config.transport.send(httpRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        throw httpStatusError(provider: providerID, response: response)
                    }
                    continuation.yield(.streamStart(warnings: prepared.warnings))
                    continuation.yield(.responseMetadata(cohereResponseMetadata(response: response, modelID: modelID)))
                    var finishReason: String?
                    var usage: TokenUsage?
                    var pendingToolCall: CoherePendingToolCall?
                    var activeReasoningID: String?
                    for event in parseServerSentEvents(response.body) {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        switch raw["type"]?.stringValue {
                        case "message-start":
                            let metadataRaw: JSONValue? = raw["id"].map { .object(["id": $0]) }
                            continuation.yield(.responseMetadata(cohereResponseMetadata(from: metadataRaw, response: response, modelID: modelID)))
                        case "content-start":
                            let id = String(raw["index"]?.intValue ?? 0)
                            if raw["delta"]?["message"]?["content"]?["type"]?.stringValue == "thinking" {
                                activeReasoningID = id
                                continuation.yield(.reasoningStart(id: id))
                            } else {
                                continuation.yield(.textStart(id: id))
                            }
                        case "content-delta":
                            let id = String(raw["index"]?.intValue ?? 0)
                            if let text = raw["delta"]?["message"]?["content"]?["text"]?.stringValue {
                                continuation.yield(.textDeltaPart(id: id, delta: text))
                            }
                            if let thinking = raw["delta"]?["message"]?["content"]?["thinking"]?.stringValue {
                                continuation.yield(.reasoningDeltaPart(id: id, delta: thinking))
                            }
                        case "content-end":
                            let id = String(raw["index"]?.intValue ?? 0)
                            if activeReasoningID == id {
                                continuation.yield(.reasoningEnd(id: id))
                                activeReasoningID = nil
                            } else {
                                continuation.yield(.textEnd(id: id))
                            }
                        case "tool-call-start":
                            let toolCall = raw["delta"]?["message"]?["tool_calls"]
                            if let id = toolCall?["id"]?.stringValue,
                               let name = toolCall?["function"]?["name"]?.stringValue {
                                let arguments = toolCall?["function"]?["arguments"]?.stringValue ?? ""
                                pendingToolCall = CoherePendingToolCall(id: id, name: name, arguments: arguments, rawValue: toolCall)
                                continuation.yield(.toolInputStart(id: id, name: name))
                                continuation.yield(.toolCallDelta(id: id, name: name, argumentsDelta: arguments, index: nil))
                                if !arguments.isEmpty {
                                    continuation.yield(.toolInputDelta(id: id, delta: arguments))
                                }
                            }
                        case "tool-call-delta":
                            let arguments = raw["delta"]?["message"]?["tool_calls"]?["function"]?["arguments"]?.stringValue ?? ""
                            if var pending = pendingToolCall {
                                pending.arguments += arguments
                                pending.rawValue = raw["delta"]?["message"]?["tool_calls"] ?? pending.rawValue
                                pendingToolCall = pending
                                continuation.yield(.toolCallDelta(id: pending.id, name: pending.name, argumentsDelta: arguments, index: nil))
                                if !arguments.isEmpty {
                                    continuation.yield(.toolInputDelta(id: pending.id, delta: arguments))
                                }
                            }
                        case "tool-call-end":
                            if let pending = pendingToolCall {
                                continuation.yield(.toolInputEnd(id: pending.id))
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

    private func body(for request: LanguageModelRequest, stream: Bool) throws -> CoherePreparedCall {
        var options = try cohereProviderOptions(from: request)
        let responseFormat = cohereResolvedResponseFormat(request: request, options: &options)
        let toolChoice = request.toolChoice ?? options.removeValue(forKey: "toolChoice")
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
        if let topK = request.topK { body["k"] = .number(Double(topK)) }
        if let frequencyPenalty = request.frequencyPenalty { body["frequency_penalty"] = .number(frequencyPenalty) }
        if let presencePenalty = request.presencePenalty { body["presence_penalty"] = .number(presencePenalty) }
        if let seed = request.seed { body["seed"] = .number(Double(seed)) }
        if !request.stopSequences.isEmpty { body["stop_sequences"] = .array(request.stopSequences) }
        if let responseFormat {
            body["response_format"] = responseFormat
        }
        if let thinking = cohereThinking(reasoning: request.reasoning, options: &options) {
            body["thinking"] = thinking
        }
        let tools = cohereTools(from: request.tools, only: cohereForcedToolName(from: toolChoice))
        if !tools.isEmpty {
            body["tools"] = .array(tools)
            if let toolChoice = cohereToolChoice(from: toolChoice) {
                body["tool_choice"] = toolChoice
            }
        }
        for (key, value) in options where !["thinking", "responseFormat", "toolChoice"].contains(key) {
            body[key] = value
        }
        return CoherePreparedCall(body: body, warnings: prompt.warnings)
    }
}

private struct CoherePreparedCall {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
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
        let options = try cohereEmbeddingProviderOptions(
            extraBody: request.extraBody,
            providerOptions: request.providerOptions
        )
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
        let response = try await config.sendJSONResponse(path: "/embed", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let embeddings = raw["embeddings"]?["float"]?.arrayValue?.map { $0.arrayValue?.compactMap(\.doubleValue) ?? [] } ?? []
        return EmbeddingResult(
            embeddings: embeddings,
            usage: TokenUsage(totalTokens: raw["meta"]?["billed_units"]?["input_tokens"]?.intValue),
            rawValue: raw,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
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
        let options = try cohereRerankingProviderOptions(
            extraBody: request.extraBody,
            providerOptions: request.providerOptions
        )
        let preparedDocuments = cohereRerankingDocuments(from: request)
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "query": .string(request.query),
            "documents": .array(preparedDocuments.documents.map(JSONValue.string))
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
        let response = try await config.sendJSONResponse(path: "/rerank", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        return RerankingResult(
            results: rerankingResults(from: raw["results"]),
            rawValue: raw,
            warnings: preparedDocuments.warnings,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
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
        let options = try voyageEmbeddingProviderOptions(
            extraBody: request.extraBody,
            providerOptions: request.providerOptions
        )
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
        let response = try await config.sendJSONResponse(path: "/embeddings", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        try validateVoyageEmbeddingResponse(raw, providerID: providerID)
        let embeddings = raw["data"]?.arrayValue?.map { $0["embedding"]?.arrayValue?.compactMap(\.doubleValue) ?? [] } ?? []
        return EmbeddingResult(
            embeddings: embeddings,
            usage: TokenUsage(totalTokens: raw["usage"]?["total_tokens"]?.intValue),
            rawValue: raw,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
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
        let options = try voyageRerankingProviderOptions(
            extraBody: request.extraBody,
            providerOptions: request.providerOptions
        )
        let preparedDocuments = voyageRerankingDocuments(from: request)
        var body: [String: JSONValue] = [
            "query": .string(request.query),
            "documents": .array(preparedDocuments.documents.map(JSONValue.string)),
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
        let response = try await config.sendJSONResponse(path: "/rerank", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        try validateVoyageRerankingResponse(raw, providerID: providerID)
        return RerankingResult(
            results: rerankingResults(from: raw["data"]),
            rawValue: raw,
            warnings: preparedDocuments.warnings,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

private func cohereProviderOptions(from request: LanguageModelRequest) throws -> [String: JSONValue] {
    var output = cohereProviderOptions(from: request.extraBody)
    if let value = request.providerOptions["cohere"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.cohere", message: "Cohere provider options must be an object.")
        }
        for key in cohereLanguageProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try cohereValidateLanguageProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

private func cohereProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "cohere")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private let cohereLanguageProviderOptionKeys: Set<String> = ["thinking"]
private let cohereEmbeddingProviderOptionKeys: Set<String> = ["inputType", "truncate", "outputDimension"]
private let cohereRerankingProviderOptionKeys: Set<String> = ["maxTokensPerDoc", "priority"]

private func cohereEmbeddingProviderOptions(
    extraBody: [String: JSONValue],
    providerOptions: [String: JSONValue]
) throws -> [String: JSONValue] {
    var output = cohereProviderOptions(from: extraBody)
    if let value = providerOptions["cohere"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.cohere", message: "Cohere provider options must be an object.")
        }
        for key in cohereEmbeddingProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try cohereValidateEmbeddingProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

private func cohereRerankingProviderOptions(
    extraBody: [String: JSONValue],
    providerOptions: [String: JSONValue]
) throws -> [String: JSONValue] {
    var output = cohereProviderOptions(from: extraBody)
    if let value = providerOptions["cohere"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.cohere", message: "Cohere provider options must be an object.")
        }
        for key in cohereRerankingProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try cohereValidateRerankingProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

private func cohereValidateLanguageProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    guard let thinking = options["thinking"] else { return [:] }
    guard thinking != .null else {
        throw AIError.invalidArgument(argument: "providerOptions.cohere.thinking", message: "Cohere thinking cannot be null.")
    }
    guard let object = thinking.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.cohere.thinking", message: "Cohere thinking must be an object.")
    }
    var output: [String: JSONValue] = [:]
    if let type = object["type"] {
        guard type != .null else {
            throw AIError.invalidArgument(argument: "providerOptions.cohere.thinking.type", message: "Cohere thinking.type cannot be null.")
        }
        guard let string = type.stringValue, ["enabled", "disabled"].contains(string) else {
            throw AIError.invalidArgument(argument: "providerOptions.cohere.thinking.type", message: "Cohere thinking.type must be enabled or disabled.")
        }
        output["type"] = type
    }
    if let tokenBudget = object["tokenBudget"] {
        guard tokenBudget != .null else {
            throw AIError.invalidArgument(argument: "providerOptions.cohere.thinking.tokenBudget", message: "Cohere thinking.tokenBudget cannot be null.")
        }
        try cohereRequireNumber(tokenBudget, argument: "providerOptions.cohere.thinking.tokenBudget", message: "Cohere thinking.tokenBudget must be a number.")
        output["tokenBudget"] = tokenBudget
    }
    return ["thinking": .object(output)]
}

private func cohereValidateEmbeddingProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where cohereEmbeddingProviderOptionKeys.contains(key) {
        guard value != .null else {
            throw AIError.invalidArgument(argument: "providerOptions.cohere.\(key)", message: "Cohere \(key) cannot be null.")
        }
        switch key {
        case "inputType":
            guard let string = value.stringValue, ["search_document", "search_query", "classification", "clustering"].contains(string) else {
                throw AIError.invalidArgument(argument: "providerOptions.cohere.inputType", message: "Cohere inputType must be one of search_document, search_query, classification, clustering.")
            }
            output[key] = value
        case "truncate":
            guard let string = value.stringValue, ["NONE", "START", "END"].contains(string) else {
                throw AIError.invalidArgument(argument: "providerOptions.cohere.truncate", message: "Cohere truncate must be one of NONE, START, END.")
            }
            output[key] = value
        case "outputDimension":
            guard let number = value.doubleValue, [256, 512, 1024, 1536].contains(Int(number)), number == Double(Int(number)) else {
                throw AIError.invalidArgument(argument: "providerOptions.cohere.outputDimension", message: "Cohere outputDimension must be one of 256, 512, 1024, 1536.")
            }
            output[key] = value
        default:
            break
        }
    }
    return output
}

private func cohereValidateRerankingProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where cohereRerankingProviderOptionKeys.contains(key) {
        guard value != .null else {
            throw AIError.invalidArgument(argument: "providerOptions.cohere.\(key)", message: "Cohere \(key) cannot be null.")
        }
        try cohereRequireNumber(value, argument: "providerOptions.cohere.\(key)", message: "Cohere \(key) must be a number.")
        output[key] = value
    }
    return output
}

private func cohereRequireNumber(_ value: JSONValue, argument: String, message: String) throws {
    guard value.doubleValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private struct CohereRerankingDocuments {
    var documents: [String]
    var warnings: [AIWarning]
}

private func cohereRerankingDocuments(from request: RerankingRequest) -> CohereRerankingDocuments {
    guard let documentObjects = request.documentObjects else {
        return CohereRerankingDocuments(documents: request.documents, warnings: [])
    }
    let documents = documentObjects.map { object in
        cohereJSONString(.object(object)) ?? ""
    }
    return CohereRerankingDocuments(
        documents: documents,
        warnings: [
            AIWarning(
                type: "compatibility",
                feature: "object documents",
                message: "Object documents are converted to strings."
            )
        ]
    )
}

private func voyageProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "voyage")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private let voyageEmbeddingProviderOptionKeys: Set<String> = ["inputType", "truncation", "outputDimension", "outputDtype"]
private let voyageRerankingProviderOptionKeys: Set<String> = ["returnDocuments", "truncation"]

private func voyageEmbeddingProviderOptions(
    extraBody: [String: JSONValue],
    providerOptions: [String: JSONValue]
) throws -> [String: JSONValue] {
    var output = voyageProviderOptions(from: extraBody)
    if let value = providerOptions["voyage"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.voyage", message: "Voyage provider options must be an object.")
        }
        for key in voyageEmbeddingProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try voyageValidateEmbeddingProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

private func voyageRerankingProviderOptions(
    extraBody: [String: JSONValue],
    providerOptions: [String: JSONValue]
) throws -> [String: JSONValue] {
    var output = voyageProviderOptions(from: extraBody)
    if let value = providerOptions["voyage"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.voyage", message: "Voyage provider options must be an object.")
        }
        for key in voyageRerankingProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try voyageValidateRerankingProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

private func voyageValidateEmbeddingProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where voyageEmbeddingProviderOptionKeys.contains(key) {
        switch key {
        case "inputType":
            if value == .null {
                output[key] = value
                continue
            }
            guard let string = value.stringValue, ["query", "document"].contains(string) else {
                throw AIError.invalidArgument(argument: "providerOptions.voyage.inputType", message: "Voyage inputType must be query, document, or null.")
            }
            output[key] = value
        case "truncation":
            guard value != .null else {
                throw AIError.invalidArgument(argument: "providerOptions.voyage.truncation", message: "Voyage truncation cannot be null.")
            }
            try voyageRequireBoolean(value, argument: "providerOptions.voyage.truncation", message: "Voyage truncation must be a boolean.")
            output[key] = value
        case "outputDimension":
            guard value != .null else {
                throw AIError.invalidArgument(argument: "providerOptions.voyage.outputDimension", message: "Voyage outputDimension cannot be null.")
            }
            try voyageRequireNumber(value, argument: "providerOptions.voyage.outputDimension", message: "Voyage outputDimension must be a number.")
            output[key] = value
        case "outputDtype":
            guard value != .null else {
                throw AIError.invalidArgument(argument: "providerOptions.voyage.outputDtype", message: "Voyage outputDtype cannot be null.")
            }
            guard let string = value.stringValue, ["float", "int8", "uint8", "binary", "ubinary"].contains(string) else {
                throw AIError.invalidArgument(argument: "providerOptions.voyage.outputDtype", message: "Voyage outputDtype must be one of float, int8, uint8, binary, ubinary.")
            }
            output[key] = value
        default:
            break
        }
    }
    return output
}

private func voyageValidateRerankingProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where voyageRerankingProviderOptionKeys.contains(key) {
        guard value != .null else {
            throw AIError.invalidArgument(argument: "providerOptions.voyage.\(key)", message: "Voyage \(key) cannot be null.")
        }
        try voyageRequireBoolean(value, argument: "providerOptions.voyage.\(key)", message: "Voyage \(key) must be a boolean.")
        output[key] = value
    }
    return output
}

private func voyageRequireBoolean(_ value: JSONValue, argument: String, message: String) throws {
    guard value.boolValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func voyageRequireNumber(_ value: JSONValue, argument: String, message: String) throws {
    guard value.doubleValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func validateVoyageEmbeddingResponse(_ raw: JSONValue, providerID: String) throws {
    guard raw["usage"]?["total_tokens"]?.doubleValue != nil,
          let data = raw["data"]?.arrayValue else {
        throw AIError.invalidResponse(provider: providerID, message: "Voyage embedding response is invalid.")
    }
    for item in data {
        guard item["index"]?.doubleValue != nil,
              let embedding = item["embedding"]?.arrayValue,
              embedding.allSatisfy({ $0.doubleValue != nil }) else {
            throw AIError.invalidResponse(provider: providerID, message: "Voyage embedding response is invalid.")
        }
    }
}

private func validateVoyageRerankingResponse(_ raw: JSONValue, providerID: String) throws {
    guard raw["usage"]?["total_tokens"]?.doubleValue != nil,
          let data = raw["data"]?.arrayValue else {
        throw AIError.invalidResponse(provider: providerID, message: "Voyage reranking response is invalid.")
    }
    for item in data {
        guard item["index"]?.doubleValue != nil,
              item["relevance_score"]?.doubleValue != nil else {
            throw AIError.invalidResponse(provider: providerID, message: "Voyage reranking response is invalid.")
        }
    }
}

private struct VoyageRerankingDocuments {
    var documents: [String]
    var warnings: [AIWarning]
}

private func voyageRerankingDocuments(from request: RerankingRequest) -> VoyageRerankingDocuments {
    guard let documentObjects = request.documentObjects else {
        return VoyageRerankingDocuments(documents: request.documents, warnings: [])
    }
    let documents = documentObjects.map { object in
        voyageJSONString(.object(object)) ?? ""
    }
    return VoyageRerankingDocuments(
        documents: documents,
        warnings: [
            AIWarning(
                type: "compatibility",
                feature: "object documents",
                message: "Object documents are converted to strings."
            )
        ]
    )
}

private func voyageJSONString(_ value: JSONValue) -> String? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

private func cohereResolvedResponseFormat(request: LanguageModelRequest, options: inout [String: JSONValue]) -> JSONValue? {
    if let responseFormat = request.responseFormat {
        options.removeValue(forKey: "responseFormat")
        return cohereResponseFormatJSON(responseFormat)
    }
    return cohereResponseFormat(from: options.removeValue(forKey: "responseFormat"))
}

private func cohereResponseFormatJSON(_ responseFormat: AIResponseFormat) -> JSONValue? {
    switch responseFormat {
    case .text:
        return nil
    case let .json(schema, _, _):
        return .object([
            "type": .string("json_object"),
            "json_schema": schema
        ])
    }
}

private func cohereResponseFormat(from value: JSONValue?) -> JSONValue? {
    guard let value else { return nil }
    if value["type"]?.stringValue == "json" {
        return .object([
            "type": .string("json_object"),
            "json_schema": value["schema"]
        ])
    }
    return value
}

private func cohereThinking(reasoning: String?, options: inout [String: JSONValue]) -> JSONValue? {
    if let thinking = options.removeValue(forKey: "thinking") {
        return cohereThinking(from: thinking)
    }
    guard let reasoning else { return nil }
    if reasoning == "none" {
        return .object(["type": .string("disabled")])
    }
    if let tokenBudget = Int(reasoning) {
        return .object([
            "type": .string("enabled"),
            "token_budget": .number(Double(tokenBudget))
        ])
    }
    return .object(["type": .string(reasoning)])
}

private func cohereThinking(from value: JSONValue) -> JSONValue {
    guard var object = value.objectValue else { return value }
    if let tokenBudget = object.removeValue(forKey: "tokenBudget") {
        object["token_budget"] = tokenBudget
    }
    if object["type"] == nil {
        object["type"] = .string("enabled")
    }
    return .object(object)
}

private func cohereTools(from tools: [String: JSONValue], only forcedToolName: String? = nil) -> [JSONValue] {
    tools.sorted { $0.key < $1.key }.compactMap { name, schema in
        guard forcedToolName == nil || forcedToolName == name else { return nil }
        return .object([
            "type": .string("function"),
            "function": .object([
                "name": .string(name),
                "description": schema["description"],
                "parameters": schema
            ])
        ])
    }
}

private func cohereForcedToolName(from value: JSONValue?) -> String? {
    guard value?["type"]?.stringValue == "tool" else { return nil }
    return value?["toolName"]?.stringValue ?? value?["name"]?.stringValue
}

private func cohereToolChoice(from value: JSONValue?) -> JSONValue? {
    switch value?["type"]?.stringValue ?? value?.stringValue {
    case "none":
        return .string("NONE")
    case "required", "tool":
        return .string("REQUIRED")
    case "auto", nil:
        return nil
    default:
        return value
    }
}

private func coherePromptJSON(from messages: [AIMessage]) -> (messages: [JSONValue], documents: [JSONValue], warnings: [AIWarning]) {
    var cohereMessages: [JSONValue] = []
    var documents: [JSONValue] = []
    var warnings: [AIWarning] = []

    for message in messages {
        let converted = cohereMessageJSON(message)
        cohereMessages.append(contentsOf: converted.messages)
        documents.append(contentsOf: converted.documents)
        warnings.append(contentsOf: converted.warnings)
    }

    return (cohereMessages, documents, warnings)
}

private func cohereMessageJSON(_ message: AIMessage) -> (messages: [JSONValue], documents: [JSONValue], warnings: [AIWarning]) {
    switch message.role {
    case .system:
        return ([.object(["role": .string("system"), "content": .string(message.combinedText)])], [], [])
    case .assistant:
        var output: [String: JSONValue] = ["role": .string("assistant")]
        let toolCalls = message.content.compactMap(cohereAssistantToolCallJSON)
        if !toolCalls.isEmpty {
            output["tool_calls"] = .array(toolCalls)
        } else {
            output["content"] = .string(message.combinedText)
        }
        return ([.object(output)], [], [])
    case .tool:
        let toolResults = message.content.compactMap(cohereToolResultMessageJSON)
        if !toolResults.isEmpty {
            return (toolResults, [], [])
        }
        return ([.object(["role": .string("tool"), "content": .string(message.combinedText)])], [], [])
    case .user:
        let hasImage = message.content.contains {
            if let payload = $0.filePayload { return payload.mimeType.hasPrefix("image/") }
            if case .imageURL = $0 { return true }
            return false
        }
        let documents = message.content.compactMap(cohereDocumentJSON)
        let unsupportedFiles = message.content.filter { part in
            guard let payload = part.filePayload else { return false }
            return !payload.mimeType.hasPrefix("image/") && String(data: payload.data, encoding: .utf8) == nil
        }
        let warnings = unsupportedFiles.map { _ in AIWarning(type: "unsupported", feature: "non-text document content") }
        guard hasImage else {
            let text = message.content.compactMap(\.text).joined()
            return ([.object(["role": .string("user"), "content": .string(text)])], documents, warnings)
        }
        return ([.object([
            "role": .string("user"),
            "content": .array(message.content.compactMap(cohereContentPartJSON))
        ])], documents, warnings)
    }
}

private func cohereAssistantToolCallJSON(_ part: AIContentPart) -> JSONValue? {
    guard case let .toolCall(call) = part else { return nil }
    return .object([
        "id": .string(call.id),
        "type": .string("function"),
        "function": .object([
            "name": .string(call.name),
            "arguments": .string(call.arguments)
        ])
    ])
}

private func cohereToolResultMessageJSON(_ part: AIContentPart) -> JSONValue? {
    guard case let .toolResult(result) = part else { return nil }
    return .object([
        "role": .string("tool"),
        "content": .string(cohereToolResultContent(result)),
        "tool_call_id": .string(result.toolCallID)
    ])
}

private func cohereToolResultContent(_ result: AIToolResult) -> String {
    let output = result.modelOutput ?? result.result
    switch output["type"]?.stringValue {
    case "text", "error-text":
        return output["value"]?.stringValue ?? ""
    case "execution-denied":
        return output["reason"]?.stringValue ?? "Tool call execution denied."
    case "content", "json", "error-json":
        if let value = output["value"] {
            return cohereJSONString(value) ?? value.stringValue ?? ""
        }
        return cohereJSONString(output) ?? output.stringValue ?? ""
    default:
        return cohereJSONString(output) ?? output.stringValue ?? ""
    }
}

private func cohereJSONString(_ value: JSONValue) -> String? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
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
    case .data, .file, .providerReference, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
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

private func cohereResponseMetadata(from raw: JSONValue? = nil, response: AIHTTPResponse, modelID: String) -> AIResponseMetadata {
    AIResponseMetadata(
        id: raw?["id"]?.stringValue ?? raw?["generation_id"]?.stringValue,
        timestamp: Date(),
        modelID: raw?["model"]?.stringValue ?? modelID,
        headers: response.headers,
        body: raw
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
