import Foundation

public final class CerebrasLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "cerebras.chat"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let body = cerebrasBody(for: request, modelID: modelID, stream: false)
        let raw = try await config.sendJSON(
            path: "/chat/completions",
            modelID: modelID,
            body: .object(body),
            headers: request.headers
        )
        let choice = raw["choices"]?[0]
        let toolCalls = cerebrasToolCalls(from: choice?["message"]?["tool_calls"])
        guard let text = choice?["message"]?["content"]?.stringValue ?? (toolCalls.isEmpty ? nil : "") else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in Cerebras response.")
        }
        let rawFinishReason = choice?["finish_reason"]?.stringValue
        let finishReason = cerebrasFinishReason(rawFinishReason, hasText: !text.isEmpty, body: body)
        return TextGenerationResult(
            text: text,
            finishReason: finishReason,
            usage: tokenUsage(from: raw),
            toolCalls: cerebrasShouldDropStructuredToolCalls(hasText: !text.isEmpty, body: body) ? [] : toolCalls,
            rawValue: raw
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let body = cerebrasBody(for: request, modelID: modelID, stream: true)
                    let response = try await config.transport.send(config.request(
                        path: "/chat/completions",
                        modelID: modelID,
                        body: .object(body),
                        headers: request.headers
                    ))
                    guard (200..<300).contains(response.statusCode) else {
                        throw httpStatusError(provider: providerID, response: response)
                    }

                    var latestUsage: TokenUsage?
                    var hasText = false
                    var finishReason: String?
                    var toolCalls = CerebrasStreamingToolCalls()
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        latestUsage = tokenUsage(from: raw) ?? latestUsage
                        if let reasoning = raw["choices"]?[0]?["delta"]?["reasoning"]?.stringValue, !reasoning.isEmpty {
                            continuation.yield(.reasoningDelta(reasoning))
                        }
                        if let delta = raw["choices"]?[0]?["delta"]?["content"]?.stringValue, !delta.isEmpty {
                            hasText = true
                            continuation.yield(.textDelta(delta))
                        }
                        if let toolCallDeltas = raw["choices"]?[0]?["delta"]?["tool_calls"]?.arrayValue,
                           !cerebrasShouldDropStructuredToolCalls(hasText: hasText, body: body) {
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
                            finishReason = cerebrasFinishReason(reason, hasText: hasText, body: body)
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

private struct CerebrasToolCallBuffer {
    var id: String?
    var name: String?
    var arguments: String = ""
    var rawValue: JSONValue?
}

private struct CerebrasStreamingToolCalls {
    private var buffers: [Int: CerebrasToolCallBuffer] = [:]

    mutating func apply(delta: JSONValue) -> (id: String?, name: String?, argumentsDelta: String, index: Int?) {
        let index = delta["index"]?.intValue ?? 0
        var buffer = buffers[index] ?? CerebrasToolCallBuffer()
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

private func cerebrasBody(for request: LanguageModelRequest, modelID: String, stream: Bool) -> [String: JSONValue] {
    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "messages": .array(request.messages.map(OpenAICompatibleChatModel.messageJSON))
    ]
    if stream { body["stream"] = true }
    if let temperature = request.temperature { body["temperature"] = .number(temperature) }
    if let topP = request.topP { body["top_p"] = .number(topP) }
    if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
    if !request.stopSequences.isEmpty { body["stop"] = .array(request.stopSequences) }
    if !request.tools.isEmpty { body["tools"] = .object(request.tools) }
    body.merge(cerebrasOptions(from: request.extraBody)) { _, new in new }

    if let messages = body["messages"]?.arrayValue {
        body["messages"] = .array(messages.map(cerebrasMessageTransform))
    }
    return body
}

private func cerebrasOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if output["response_format"] == nil, let responseFormat = output.removeValue(forKey: "responseFormat") {
        output["response_format"] = cerebrasResponseFormat(from: responseFormat, strictJsonSchema: output.removeValue(forKey: "strictJsonSchema"))
    } else {
        output.removeValue(forKey: "responseFormat")
        output.removeValue(forKey: "strictJsonSchema")
    }
    return output
}

private func cerebrasResponseFormat(from value: JSONValue, strictJsonSchema: JSONValue?) -> JSONValue {
    guard let object = value.objectValue, object["type"]?.stringValue == "json" else {
        return value
    }
    guard let schema = object["schema"] else {
        return .object(["type": .string("json_object")])
    }
    let strict = strictJsonSchema ?? .bool(true)
    let normalizedSchema = strict.boolValue == false ? schema : addAdditionalPropertiesToJSONSchema(schema)
    var jsonSchema: [String: JSONValue] = [
        "schema": normalizedSchema,
        "strict": strict,
        "name": object["name"] ?? .string("response")
    ]
    if let description = object["description"] {
        jsonSchema["description"] = description
    }
    return .object([
        "type": .string("json_schema"),
        "json_schema": .object(jsonSchema)
    ])
}

private func cerebrasMessageTransform(_ message: JSONValue) -> JSONValue {
    guard var object = message.objectValue,
          object["role"]?.stringValue == "assistant",
          let reasoningContent = object.removeValue(forKey: "reasoning_content") else {
        return message
    }
    if object["reasoning"] == nil, reasoningContent != .null {
        object["reasoning"] = reasoningContent
    }
    return .object(object)
}

private func cerebrasFinishReason(_ raw: String?, hasText: Bool, body: [String: JSONValue]) -> String? {
    if raw == "tool_calls", cerebrasShouldDropStructuredToolCalls(hasText: hasText, body: body) {
        return "stop"
    }
    switch raw {
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

private func cerebrasShouldDropStructuredToolCalls(hasText: Bool, body: [String: JSONValue]) -> Bool {
    let responseFormatType = body["response_format"]?["type"]?.stringValue
    return hasText && (responseFormatType == "json_schema" || responseFormatType == "json_object" || responseFormatType == "json")
}

private func cerebrasToolCalls(from value: JSONValue?) -> [AIToolCall] {
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
