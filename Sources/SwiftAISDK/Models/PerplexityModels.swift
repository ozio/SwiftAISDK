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
        let prepared = perplexityPreparedCall(for: request, modelID: modelID, stream: false)
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
            finishReason: choice?["finish_reason"]?.stringValue,
            usage: tokenUsage(from: raw),
            sources: perplexitySources(from: raw["citations"]),
            rawValue: raw,
            warnings: prepared.warnings,
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = perplexityPreparedCall(for: request, modelID: modelID, stream: true)
                    let body = JSONValue.object(prepared.body)
                    let response = try await config.transport.send(config.request(path: "/chat/completions", modelID: modelID, body: body, headers: request.headers, abortSignal: request.abortSignal))
                    guard (200..<300).contains(response.statusCode) else {
                        throw httpStatusError(provider: providerID, response: response)
                    }

                    continuation.yield(.responseMetadata(aiResponseMetadata(response: response, modelID: modelID)))
                    if !prepared.warnings.isEmpty {
                        continuation.yield(.streamStart(warnings: prepared.warnings))
                    }
                    var latestUsage: TokenUsage?
                    var emittedSourceURLs: Set<String> = []
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        latestUsage = tokenUsage(from: raw) ?? latestUsage
                        for source in perplexitySources(from: raw["citations"]) where source.url.map({ !emittedSourceURLs.contains($0) }) ?? true {
                            if let url = source.url {
                                emittedSourceURLs.insert(url)
                            }
                            continuation.yield(.source(source))
                        }
                        if let delta = raw["choices"]?[0]?["delta"]?["content"]?.stringValue, !delta.isEmpty {
                            continuation.yield(.textDelta(delta))
                        }
                        if let reason = raw["choices"]?[0]?["finish_reason"]?.stringValue {
                            continuation.yield(.finish(reason: reason, usage: latestUsage))
                        }
                    }
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

private func perplexityPreparedCall(for request: LanguageModelRequest, modelID: String, stream: Bool) -> PerplexityPreparedCall {
    var options = perplexityProviderOptions(from: request)
    let responseFormat = perplexityResolvedResponseFormat(request: request, options: &options)
    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "messages": .array(request.messages.map(perplexityMessageJSON))
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

private func perplexityMessageJSON(_ message: AIMessage) -> JSONValue {
    let multipart = message.content.contains { part in
        switch part {
        case .text:
            return false
        case .imageURL:
            return true
        case let .data(mimeType, _), let .file(mimeType, _, _):
            return mimeType.hasPrefix("image/") || mimeType == "application/pdf"
        case .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
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
        case let .data(mimeType, data) where mimeType == "application/pdf",
             let .file(mimeType, data, _) where mimeType == "application/pdf":
            return .object([
                "type": .string("file_url"),
                "file_url": .object(["url": .string(data.base64EncodedString())]),
                "file_name": .string("document-\(index).pdf")
            ])
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

    return .object([
        "role": .string(message.role.rawValue),
        "content": .array(parts)
    ])
}
