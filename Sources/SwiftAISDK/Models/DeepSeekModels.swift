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
        let prepared = deepSeekPreparedCall(for: request, modelID: modelID, stream: false)
        let raw = try await config.sendJSON(
            path: "/chat/completions",
            modelID: modelID,
            body: .object(prepared.body),
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
            rawValue: raw,
            warnings: prepared.warnings
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = deepSeekPreparedCall(for: request, modelID: modelID, stream: true)
                    let response = try await config.transport.send(config.request(
                        path: "/chat/completions",
                        modelID: modelID,
                        body: .object(prepared.body),
                        headers: request.headers
                    ))
                    guard (200..<300).contains(response.statusCode) else {
                        throw httpStatusError(provider: providerID, response: response)
                    }

                    if !prepared.warnings.isEmpty {
                        continuation.yield(.streamStart(warnings: prepared.warnings))
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
                                for part in toolCalls.apply(delta: toolCallDelta) {
                                    continuation.yield(part)
                                }
                            }
                        }
                        if let reason = raw["choices"]?[0]?["finish_reason"]?.stringValue {
                            finishReason = deepSeekFinishReason(reason)
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

private typealias DeepSeekStreamingToolCalls = OpenAIStyleStreamingToolCalls

private struct DeepSeekPreparedCall {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
}

private func deepSeekPreparedCall(for request: LanguageModelRequest, modelID: String, stream: Bool) -> DeepSeekPreparedCall {
    var options = deepSeekOptions(from: request.extraBody)
    let responseFormat = deepSeekResolvedResponseFormat(request: request, options: &options)
    let toolChoice = options.removeValue(forKey: "toolChoice")
    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "messages": .array(deepSeekMessages(request.messages, responseFormat: responseFormat).map { deepSeekMessageJSON($0, modelID: modelID) })
    ]
    if stream {
        body["stream"] = true
        body["stream_options"] = .object(["include_usage": true])
    }
    if let temperature = request.temperature { body["temperature"] = .number(temperature) }
    if let topP = request.topP { body["top_p"] = .number(topP) }
    if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
    if !request.stopSequences.isEmpty { body["stop"] = .array(request.stopSequences) }
    let tools = deepSeekTools(from: request.tools)
    if !tools.isEmpty {
        body["tools"] = .array(tools)
        if let toolChoice = deepSeekToolChoice(from: toolChoice) {
            body["tool_choice"] = toolChoice
        }
    }
    body.merge(options) { _, new in new }
    if let responseFormat, responseFormat["type"]?.stringValue == "json" {
        body["response_format"] = .object(["type": .string("json_object")])
    }

    if body["thinking"]?["type"]?.stringValue == "disabled" {
        body.removeValue(forKey: "reasoning_effort")
    }
    return DeepSeekPreparedCall(
        body: body,
        warnings: deepSeekWarnings(responseFormat: responseFormat)
    )
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

private func deepSeekMessages(_ messages: [AIMessage], responseFormat: JSONValue?) -> [AIMessage] {
    guard responseFormat?["type"]?.stringValue == "json" else {
        return messages
    }
    if let schema = responseFormat?["schema"] {
        let schemaText = deepSeekJSONString(schema) ?? schema.stringValue ?? ""
        return [AIMessage.system("Return JSON that conforms to the following schema: \(schemaText)")] + messages
    }
    return [AIMessage.system("Return JSON.")] + messages
}

private func deepSeekOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "deepseek")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    deepSeekMoveKey("reasoningEffort", to: "reasoning_effort", in: &output)
    if let effort = output["reasoning_effort"]?.stringValue {
        output["reasoning_effort"] = .string(deepSeekReasoningEffort(effort))
    }
    return output
}

private func deepSeekResolvedResponseFormat(request: LanguageModelRequest, options: inout [String: JSONValue]) -> JSONValue? {
    if let responseFormat = request.responseFormat {
        options.removeValue(forKey: "responseFormat")
        return deepSeekResponseFormatJSON(responseFormat)
    }
    return options.removeValue(forKey: "responseFormat")
}

private func deepSeekResponseFormatJSON(_ responseFormat: AIResponseFormat) -> JSONValue? {
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

private func deepSeekWarnings(responseFormat: JSONValue?) -> [AIWarning] {
    guard responseFormat?["type"]?.stringValue == "json",
          responseFormat?["schema"] != nil else {
        return []
    }
    return [
        AIWarning(
            type: "compatibility",
            feature: "responseFormat JSON schema",
            message: "JSON response schema is injected into the system message."
        )
    ]
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

private func deepSeekTools(from tools: [String: JSONValue]) -> [JSONValue] {
    tools.compactMap { name, schema in
        let object = schema.objectValue
        if object?["type"]?.stringValue == "provider" || object?["id"]?.stringValue != nil {
            return nil
        }
        var parameters = schema
        var function: [String: JSONValue] = [
            "name": .string(name),
            "parameters": parameters
        ]
        if var parameterObject = parameters.objectValue {
            if let description = parameterObject["description"]?.stringValue {
                function["description"] = .string(description)
            }
            if let strict = parameterObject.removeValue(forKey: "strict") {
                function["strict"] = strict
                parameters = .object(parameterObject)
                function["parameters"] = parameters
            }
        }
        return .object([
            "type": .string("function"),
            "function": .object(function)
        ])
    }
}

private func deepSeekToolChoice(from value: JSONValue?) -> JSONValue? {
    if let string = value?.stringValue {
        switch string {
        case "auto", "none", "required":
            return .string(string)
        default:
            return nil
        }
    }
    guard let object = value?.objectValue else { return nil }
    switch object["type"]?.stringValue {
    case "auto", "none", "required":
        return object["type"]
    case "tool":
        guard let toolName = object["toolName"]?.stringValue ?? object["tool_name"]?.stringValue else {
            return nil
        }
        return .object([
            "type": .string("function"),
            "function": .object(["name": .string(toolName)])
        ])
    default:
        return nil
    }
}

private func deepSeekJSONString(_ value: JSONValue) -> String? {
    guard let data = try? encodeJSONBody(value) else { return nil }
    return String(data: data, encoding: .utf8)
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
