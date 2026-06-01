import Foundation

public final class DeepSeekLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "deepseek.chat"
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
            body: .object(deepSeekBody(for: request, modelID: modelID, stream: false)),
            headers: request.headers
        )
        let choice = raw["choices"]?[0]
        let toolCalls = deepSeekToolCalls(from: choice?["message"]?["tool_calls"])
        guard let text = choice?["message"]?["content"]?.stringValue ?? (toolCalls.isEmpty ? nil : "") else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in DeepSeek response.")
        }
        return TextGenerationResult(
            text: text,
            finishReason: deepSeekFinishReason(choice?["finish_reason"]?.stringValue),
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
                        body: .object(deepSeekBody(for: request, modelID: modelID, stream: true)),
                        headers: request.headers
                    ))
                    guard (200..<300).contains(response.statusCode) else {
                        throw httpStatusError(provider: providerID, response: response)
                    }

                    var latestUsage: TokenUsage?
                    var finishReason: String?
                    var toolCalls = DeepSeekStreamingToolCalls()
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        latestUsage = tokenUsage(from: raw) ?? latestUsage
                        if let reasoning = raw["choices"]?[0]?["delta"]?["reasoning_content"]?.stringValue, !reasoning.isEmpty {
                            continuation.yield(.reasoningDelta(reasoning))
                        }
                        if let delta = raw["choices"]?[0]?["delta"]?["content"]?.stringValue, !delta.isEmpty {
                            continuation.yield(.textDelta(delta))
                        }
                        if let toolCallDeltas = raw["choices"]?[0]?["delta"]?["tool_calls"]?.arrayValue {
                            for toolCallDelta in toolCallDeltas {
                                let update = toolCalls.apply(delta: toolCallDelta)
                                continuation.yield(.toolCallDelta(
                                    id: update.id,
                                    name: update.name,
                                    argumentsDelta: update.argumentsDelta,
                                    index: update.index
                                ))
                            }
                        }
                        if let reason = raw["choices"]?[0]?["finish_reason"]?.stringValue {
                            finishReason = deepSeekFinishReason(reason)
                        }
                    }
                    for toolCall in toolCalls.finishedCalls() {
                        continuation.yield(.toolCall(toolCall))
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

private struct DeepSeekToolCallBuffer {
    var id: String?
    var name: String?
    var arguments: String = ""
    var rawValue: JSONValue?
}

private struct DeepSeekStreamingToolCalls {
    private var buffers: [Int: DeepSeekToolCallBuffer] = [:]

    mutating func apply(delta: JSONValue) -> (id: String?, name: String?, argumentsDelta: String, index: Int?) {
        let index = delta["index"]?.intValue ?? 0
        var buffer = buffers[index] ?? DeepSeekToolCallBuffer()
        if let id = delta["id"]?.stringValue {
            buffer.id = id
        }
        if let name = delta["function"]?["name"]?.stringValue {
            buffer.name = name
        }
        let argumentsDelta = delta["function"]?["arguments"]?.stringValue ?? ""
        if !argumentsDelta.isEmpty {
            buffer.arguments += argumentsDelta
        }
        buffer.rawValue = delta
        buffers[index] = buffer
        return (buffer.id, buffer.name, argumentsDelta, index)
    }

    func finishedCalls() -> [AIToolCall] {
        buffers.keys.sorted().compactMap { index in
            guard let buffer = buffers[index], let name = buffer.name else { return nil }
            return AIToolCall(
                id: buffer.id ?? "tool-call-\(index)",
                name: name,
                arguments: buffer.arguments,
                rawValue: buffer.rawValue
            )
        }
    }
}

private func deepSeekBody(for request: LanguageModelRequest, modelID: String, stream: Bool) -> [String: JSONValue] {
    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "messages": .array(request.messages.map { deepSeekMessageJSON($0, modelID: modelID) })
    ]
    if stream {
        body["stream"] = true
        body["stream_options"] = .object(["include_usage": true])
    }
    if let temperature = request.temperature { body["temperature"] = .number(temperature) }
    if let topP = request.topP { body["top_p"] = .number(topP) }
    if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
    if !request.stopSequences.isEmpty { body["stop"] = .array(request.stopSequences) }
    if !request.tools.isEmpty { body["tools"] = .object(request.tools) }
    body.merge(deepSeekOptions(from: request.extraBody)) { _, new in new }

    if body["thinking"]?["type"]?.stringValue == "disabled" {
        body.removeValue(forKey: "reasoning_effort")
    }
    return body
}

private func deepSeekMessageJSON(_ message: AIMessage, modelID: String) -> JSONValue {
    var value = OpenAICompatibleChatModel.messageJSON(message)
    guard modelID.contains("deepseek-v4"),
          message.role == .assistant,
          var object = value.objectValue,
          object["reasoning_content"] == nil else {
        return value
    }
    object["reasoning_content"] = .string("")
    value = .object(object)
    return value
}

private func deepSeekOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    deepSeekMoveKey("reasoningEffort", to: "reasoning_effort", in: &output)
    if let effort = output["reasoning_effort"]?.stringValue {
        output["reasoning_effort"] = .string(deepSeekReasoningEffort(effort))
    }
    return output
}

private func deepSeekMoveKey(_ source: String, to destination: String, in values: inout [String: JSONValue]) {
    if let value = values.removeValue(forKey: source) {
        values[destination] = value
    }
}

private func deepSeekReasoningEffort(_ value: String) -> String {
    switch value {
    case "minimal":
        return "low"
    case "xhigh":
        return "max"
    default:
        return value
    }
}

private func deepSeekToolCalls(from value: JSONValue?) -> [AIToolCall] {
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

private func deepSeekFinishReason(_ reason: String?) -> String? {
    switch reason {
    case "stop":
        return "stop"
    case "length":
        return "length"
    case "content_filter":
        return "content-filter"
    case "tool_calls":
        return "tool-calls"
    case "insufficient_system_resource":
        return "error"
    case nil:
        return nil
    default:
        return "other"
    }
}
