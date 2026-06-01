import Foundation

public final class AlibabaLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "alibaba.chat"
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
            body: .object(alibabaBody(for: request, modelID: modelID, stream: false)),
            headers: request.headers
        )
        let choice = raw["choices"]?[0]
        let toolCalls = alibabaToolCalls(from: choice?["message"]?["tool_calls"])
        guard let text = choice?["message"]?["content"]?.stringValue ?? (toolCalls.isEmpty ? nil : "") else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in Alibaba response.")
        }
        return TextGenerationResult(
            text: text,
            finishReason: alibabaFinishReason(choice?["finish_reason"]?.stringValue),
            usage: tokenUsage(from: raw),
            toolCalls: toolCalls,
            rawValue: raw
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await config.transport.send(config.request(
                        path: "/chat/completions",
                        modelID: modelID,
                        body: .object(alibabaBody(for: request, modelID: modelID, stream: true)),
                        headers: request.headers
                    ))
                    guard (200..<300).contains(response.statusCode) else {
                        throw httpStatusError(provider: providerID, response: response)
                    }

                    var latestUsage: TokenUsage?
                    var finishReason: String?
                    var toolCalls = AlibabaStreamingToolCalls()
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        latestUsage = tokenUsage(from: raw) ?? latestUsage
                        guard let choice = raw["choices"]?[0] else { continue }

                        if let reasoning = choice["delta"]?["reasoning_content"]?.stringValue, !reasoning.isEmpty {
                            continuation.yield(.reasoningDelta(reasoning))
                        }
                        if let delta = choice["delta"]?["content"]?.stringValue, !delta.isEmpty {
                            continuation.yield(.textDelta(delta))
                        }
                        if let toolCallDeltas = choice["delta"]?["tool_calls"]?.arrayValue {
                            for toolCallDelta in toolCallDeltas {
                                for part in toolCalls.apply(delta: toolCallDelta) {
                                    continuation.yield(part)
                                }
                            }
                        }
                        if let reason = choice["finish_reason"]?.stringValue {
                            finishReason = alibabaFinishReason(reason)
                        }
                    }
                    for part in toolCalls.finishedParts() {
                        continuation.yield(part)
                    }
                    continuation.yield(.finish(reason: finishReason, usage: latestUsage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private typealias AlibabaStreamingToolCalls = OpenAIStyleStreamingToolCalls

private func alibabaBody(for request: LanguageModelRequest, modelID: String, stream: Bool) -> [String: JSONValue] {
    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "messages": .array(request.messages.map(alibabaMessageJSON))
    ]
    if let temperature = request.temperature { body["temperature"] = .number(temperature) }
    if let topP = request.topP { body["top_p"] = .number(topP) }
    if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
    if !request.stopSequences.isEmpty { body["stop"] = .array(request.stopSequences) }
    if !request.tools.isEmpty { body["tools"] = .object(request.tools) }
    body.merge(alibabaOptions(from: request.extraBody)) { _, new in new }
    if stream {
        body["stream"] = true
        body["stream_options"] = body["stream_options"] ?? .object(["include_usage": true])
    }
    return body
}

private func alibabaMessageJSON(_ message: AIMessage) -> JSONValue {
    switch message.role {
    case .system:
        return .object([
            "role": .string("system"),
            "content": .string(message.combinedText)
        ])
    case .user:
        return .object([
            "role": .string("user"),
            "content": .array(alibabaUserContentParts(message.content))
        ])
    case .assistant:
        return .object([
            "role": .string("assistant"),
            "content": message.combinedText.isEmpty ? .null : .string(message.combinedText)
        ])
    case .tool:
        return .object([
            "role": .string("tool"),
            "content": .string(message.combinedText)
        ])
    }
}

private func alibabaUserContentParts(_ content: [AIContentPart]) -> [JSONValue] {
    content.compactMap { part in
        switch part {
        case let .text(text):
            return .object(["type": .string("text"), "text": .string(text)])
        case let .imageURL(url):
            return .object(["type": .string("image_url"), "image_url": .object(["url": .string(url)])])
        case let .data(mimeType, data), let .file(mimeType, data, _):
            guard mimeType.lowercased().hasPrefix("image/") else { return nil }
            return .object([
                "type": .string("image_url"),
                "image_url": .object(["url": .string("data:\(mimeType);base64,\(data.base64EncodedString())")])
            ])
        case .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
            return nil
        }
    }
}

private func alibabaOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    alibabaMoveKey("topK", to: "top_k", in: &output)
    alibabaMoveKey("presencePenalty", to: "presence_penalty", in: &output)
    alibabaMoveKey("enableThinking", to: "enable_thinking", in: &output)
    alibabaMoveKey("thinkingBudget", to: "thinking_budget", in: &output)
    alibabaMoveKey("parallelToolCalls", to: "parallel_tool_calls", in: &output)
    return output
}

private func alibabaMoveKey(_ source: String, to destination: String, in values: inout [String: JSONValue]) {
    if let value = values.removeValue(forKey: source) {
        values[destination] = value
    }
}

private func alibabaToolCalls(from value: JSONValue?) -> [AIToolCall] {
    value?.arrayValue?.enumerated().compactMap { index, item in
        guard let name = item["function"]?["name"]?.stringValue else { return nil }
        return AIToolCall(
            id: item["id"]?.stringValue ?? "tool-call-\(index)",
            name: name,
            arguments: item["function"]?["arguments"]?.stringValue ?? "",
            rawValue: item
        )
    } ?? []
}

private func alibabaFinishReason(_ reason: String?) -> String? {
    switch reason {
    case "stop":
        return "stop"
    case "length":
        return "length"
    case "content_filter":
        return "content-filter"
    case "function_call", "tool_calls":
        return "tool-calls"
    case nil:
        return nil
    default:
        return "other"
    }
}
