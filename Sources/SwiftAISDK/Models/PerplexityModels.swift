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
        let raw = try await config.sendJSON(
            path: "/chat/completions",
            modelID: modelID,
            body: .object(perplexityBody(for: request, modelID: modelID, stream: false)),
            headers: request.headers
        )
        let choice = raw["choices"]?[0]
        guard let text = choice?["message"]?["content"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in Perplexity response.")
        }
        return TextGenerationResult(
            text: text,
            finishReason: choice?["finish_reason"]?.stringValue,
            usage: tokenUsage(from: raw),
            sources: perplexitySources(from: raw["citations"]),
            rawValue: raw
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let body = JSONValue.object(perplexityBody(for: request, modelID: modelID, stream: true))
                    let response = try await config.transport.send(config.request(path: "/chat/completions", modelID: modelID, body: body, headers: request.headers))
                    guard (200..<300).contains(response.statusCode) else {
                        throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
                    }

                    var latestUsage: TokenUsage?
                    var emittedSourceURLs: Set<String> = []
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        continuation.yield(.raw(raw))
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

private func perplexityBody(for request: LanguageModelRequest, modelID: String, stream: Bool) -> [String: JSONValue] {
    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "messages": .array(request.messages.map(perplexityMessageJSON))
    ]
    if stream { body["stream"] = true }
    if let temperature = request.temperature { body["temperature"] = .number(temperature) }
    if let topP = request.topP { body["top_p"] = .number(topP) }
    if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
    body.merge(request.extraBody) { _, new in new }
    return body
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
        case .toolCall, .toolResult:
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
        case .data, .file, .toolCall, .toolResult:
            return nil
        }
    }

    return .object([
        "role": .string(message.role.rawValue),
        "content": .array(parts)
    ])
}
