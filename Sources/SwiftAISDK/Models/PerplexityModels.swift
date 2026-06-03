import Foundation

public final class PerplexityLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "perplexity"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try perplexityPreparedCall(for: request, modelID: modelID, stream: false)
        let response = try await config.sendJSONResponse(
            path: "/chat/completions",
            modelID: modelID,
            body: .object(prepared.body),
            headers: request.headers,
            abortSignal: request.abortSignal
        )
        let raw = response.json
        let choice = raw["choices"]?[0]
        guard let text = choice?["message"]?["content"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in Perplexity response.")
        }
        return TextGenerationResult(
            text: text,
            finishReason: perplexityFinishReason(choice?["finish_reason"]?.stringValue),
            usage: perplexityUsage(from: raw),
            sources: perplexitySources(from: raw["citations"]),
            providerMetadata: perplexityProviderMetadata(from: raw),
            rawValue: raw,
            warnings: prepared.warnings,
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = try perplexityPreparedCall(for: request, modelID: modelID, stream: true)
                    let body = JSONValue.object(prepared.body)
                    let response = try await config.transport.send(config.request(path: "/chat/completions", modelID: modelID, body: body, headers: request.headers, abortSignal: request.abortSignal))
                    guard (200..<300).contains(response.statusCode) else {
                        throw httpStatusError(provider: providerID, response: response)
                    }

                    continuation.yield(.streamStart(warnings: prepared.warnings))
                    var latestUsage: TokenUsage?
                    var finishReason: String?
                    var providerMetadata = perplexityEmptyProviderMetadata()
                    var didEmitResponseMetadata = false
                    var didEmitSources = false
                    var activeTextID: String?
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        if !didEmitResponseMetadata {
                            didEmitResponseMetadata = true
                            continuation.yield(.responseMetadata(aiResponseMetadata(from: raw, response: response, modelID: modelID)))
                        }
                        latestUsage = perplexityUsage(from: raw) ?? latestUsage
                        perplexityMergeProviderMetadata(from: raw, into: &providerMetadata)
                        if !didEmitSources {
                            didEmitSources = true
                            for source in perplexitySources(from: raw["citations"]) {
                                continuation.yield(.source(source))
                            }
                        }
                        if let delta = raw["choices"]?[0]?["delta"]?["content"]?.stringValue, !delta.isEmpty {
                            let id = activeTextID ?? "0"
                            if activeTextID == nil {
                                activeTextID = id
                                continuation.yield(.textStart(id: id))
                            }
                            continuation.yield(.textDeltaPart(id: id, delta: delta))
                        }
                        if let reason = raw["choices"]?[0]?["finish_reason"]?.stringValue {
                            finishReason = perplexityFinishReason(reason)
                        }
                    }
                    if let textID = activeTextID {
                        continuation.yield(.textEnd(id: textID))
                    }
                    continuation.yield(.finishMetadata(reason: finishReason, usage: latestUsage, providerMetadata: providerMetadata))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private struct PerplexityPreparedCall {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
}

private func perplexityPreparedCall(for request: LanguageModelRequest, modelID: String, stream: Bool) throws -> PerplexityPreparedCall {
    var options = perplexityProviderOptions(from: request)
    let responseFormat = perplexityResolvedResponseFormat(request: request, options: &options)
    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "messages": .array(try request.messages.map(perplexityMessageJSON))
    ]
    if stream { body["stream"] = true }
    if let temperature = request.temperature { body["temperature"] = .number(temperature) }
    if let topP = request.topP { body["top_p"] = .number(topP) }
    if let topK = request.topK { body["top_k"] = .number(Double(topK)) }
    if let presencePenalty = request.presencePenalty { body["presence_penalty"] = .number(presencePenalty) }
    if let frequencyPenalty = request.frequencyPenalty { body["frequency_penalty"] = .number(frequencyPenalty) }
    if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
    if let responseFormat = perplexityResponseFormat(from: responseFormat) {
        body["response_format"] = responseFormat
    }
    body.merge(options) { _, new in new }
    return PerplexityPreparedCall(body: body, warnings: perplexityWarnings(for: request))
}

private func perplexityProviderOptions(from request: LanguageModelRequest) -> [String: JSONValue] {
    var output = request.extraBody
    if let nested = output.removeValue(forKey: "perplexity")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    if let nested = request.providerOptions["perplexity"]?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func perplexityResolvedResponseFormat(request: LanguageModelRequest, options: inout [String: JSONValue]) -> JSONValue? {
    if let responseFormat = request.responseFormat {
        options.removeValue(forKey: "responseFormat")
        return perplexityResponseFormatJSON(responseFormat)
    }
    return options.removeValue(forKey: "responseFormat")
}

private func perplexityResponseFormatJSON(_ responseFormat: AIResponseFormat) -> JSONValue? {
    switch responseFormat {
    case .text:
        return nil
    case let .json(schema, name, description):
        return .object([
            "type": .string("json"),
            "schema": schema,
            "name": name.map(JSONValue.string),
            "description": description.map(JSONValue.string)
        ])
    }
}

private func perplexityResponseFormat(from value: JSONValue?) -> JSONValue? {
    guard value?["type"]?.stringValue == "json" else { return nil }
    var jsonSchema: [String: JSONValue] = [:]
    if let schema = value?["schema"] {
        jsonSchema["schema"] = schema
    }
    return .object([
        "type": .string("json_schema"),
        "json_schema": .object(jsonSchema)
    ])
}

private func perplexityWarnings(for request: LanguageModelRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.topK != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "topK"))
    }
    if !request.stopSequences.isEmpty {
        warnings.append(AIWarning(type: "unsupported", feature: "stopSequences"))
    }
    if request.seed != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "seed"))
    }
    if request.reasoning != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "reasoning",
            message: "This provider does not support reasoning configuration."
        ))
    }
    return warnings
}

private func perplexitySources(from citations: JSONValue?) -> [AISource] {
    citations?.arrayValue?.enumerated().compactMap { index, citation in
        guard let url = citation.stringValue else { return nil }
        return AISource(
            id: "citation-\(index)",
            sourceType: "url",
            url: url,
            providerMetadata: ["perplexity": .object(["citationIndex": .number(Double(index))])],
            rawValue: citation
        )
    } ?? []
}

private func perplexityProviderMetadata(from raw: JSONValue) -> [String: JSONValue] {
    [
        "perplexity": .object([
            "usage": perplexityUsageMetadata(from: raw["usage"]),
            "cost": perplexityCostMetadata(from: raw["usage"]?["cost"]),
            "images": perplexityImagesMetadata(from: raw["images"])
        ])
    ]
}

private func perplexityEmptyProviderMetadata() -> [String: JSONValue] {
    [
        "perplexity": .object([
            "usage": .object([
                "citationTokens": .null,
                "numSearchQueries": .null
            ]),
            "cost": .null,
            "images": .null
        ])
    ]
}

private func perplexityMergeProviderMetadata(from raw: JSONValue, into metadata: inout [String: JSONValue]) {
    var perplexity = metadata["perplexity"]?.objectValue
        ?? perplexityEmptyProviderMetadata()["perplexity"]?.objectValue
        ?? [:]
    if let usage = raw["usage"] {
        perplexity["usage"] = perplexityUsageMetadata(from: usage)
        perplexity["cost"] = perplexityCostMetadata(from: usage["cost"])
    }
    if raw["images"] != nil {
        perplexity["images"] = perplexityImagesMetadata(from: raw["images"])
    }
    metadata["perplexity"] = .object(perplexity)
}

private func perplexityUsageMetadata(from value: JSONValue?) -> JSONValue {
    .object([
        "citationTokens": value?["citation_tokens"] ?? .null,
        "numSearchQueries": value?["num_search_queries"] ?? .null
    ])
}

private func perplexityCostMetadata(from value: JSONValue?) -> JSONValue {
    guard let value else { return .null }
    return .object([
        "inputTokensCost": value["input_tokens_cost"] ?? .null,
        "outputTokensCost": value["output_tokens_cost"] ?? .null,
        "requestCost": value["request_cost"] ?? .null,
        "totalCost": value["total_cost"] ?? .null
    ])
}

private func perplexityImagesMetadata(from value: JSONValue?) -> JSONValue {
    guard let images = value?.arrayValue else { return .null }
    return .array(images.map { image in
        .object([
            "imageUrl": image["image_url"] ?? .null,
            "originUrl": image["origin_url"] ?? .null,
            "height": image["height"] ?? .null,
            "width": image["width"] ?? .null
        ])
    })
}

private func perplexityUsage(from raw: JSONValue) -> TokenUsage? {
    guard let usage = raw["usage"] else { return nil }
    let inputTokens = usage["prompt_tokens"]?.intValue ?? 0
    let outputTokens = usage["completion_tokens"]?.intValue ?? 0
    let reasoningTokens = usage["reasoning_tokens"]?.intValue ?? 0
    return TokenUsage(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: usage["total_tokens"]?.intValue ?? inputTokens + outputTokens,
        inputTokensNoCache: inputTokens,
        outputTextTokens: outputTokens - reasoningTokens,
        outputReasoningTokens: reasoningTokens,
        rawValue: usage
    )
}

private func perplexityFinishReason(_ reason: String?) -> String? {
    switch reason {
    case "stop", "length":
        return reason
    case nil:
        return nil
    default:
        return "other"
    }
}

private func perplexityMessageJSON(_ message: AIMessage) throws -> JSONValue {
    guard message.role != .tool else {
        throw AIError.invalidArgument(argument: "messages", message: "Perplexity does not support tool messages.")
    }

    let multipart = message.content.contains { part in
        switch part {
        case .text:
            return false
        case .imageURL:
            return true
        case let .data(mimeType, _), let .file(mimeType, _, _):
            return mimeType.hasPrefix("image/") || mimeType == "application/pdf"
        case .providerReference, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
            return false
        }
    }

    guard multipart else {
        return .object([
            "role": .string(message.role.rawValue),
            "content": .string(message.content.compactMap(\.text).joined())
        ])
    }

    let parts = message.content.enumerated().compactMap { index, part -> JSONValue? in
        switch part {
        case let .text(text):
            return .object(["type": .string("text"), "text": .string(text)])
        case let .imageURL(url):
            return .object([
                "type": .string("image_url"),
                "image_url": .object(["url": .string(url)])
            ])
        case let .data(mimeType, data) where mimeType == "application/pdf":
            return .object([
                "type": .string("file_url"),
                "file_url": .object(["url": .string(data.base64EncodedString())]),
                "file_name": .string("document-\(index).pdf")
            ])
        case let .file(mimeType, data, filename) where mimeType == "application/pdf":
            return .object([
                "type": .string("file_url"),
                "file_url": .object(["url": .string(data.base64EncodedString())]),
                "file_name": .string(filename ?? "document-\(index).pdf")
            ])
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

    return .object([
        "role": .string(message.role.rawValue),
        "content": .array(parts)
    ])
}
