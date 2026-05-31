import Foundation

public final class HuggingFaceResponsesLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "huggingface.responses"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let raw = try await config.sendJSON(path: "/responses", modelID: modelID, body: .object(body(for: request, stream: false)), headers: request.headers)
        if let message = raw["error"]?["message"]?.stringValue {
            throw AIError.invalidResponse(provider: providerID, message: message)
        }

        let parsed = huggingFaceResponseContent(from: raw)
        guard !parsed.text.isEmpty || !parsed.toolCalls.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No Hugging Face response output found.")
        }

        return TextGenerationResult(
            text: parsed.text,
            reasoning: parsed.reasoning,
            finishReason: huggingFaceFinishReason(raw["incomplete_details"]?["reason"]?.stringValue ?? "stop"),
            usage: tokenUsage(from: raw),
            toolCalls: parsed.toolCalls,
            sources: parsed.sources,
            providerMetadata: ["huggingface": .object(["responseId": raw["id"] ?? .null])],
            rawValue: raw
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let httpRequest = try config.request(path: "/responses", modelID: modelID, body: .object(body(for: request, stream: true)), headers: request.headers)
                    let response = try await config.transport.send(httpRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
                    }

                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        continuation.yield(.raw(raw))

                        switch raw["type"]?.stringValue {
                        case "response.output_text.delta":
                            if let delta = raw["delta"]?.stringValue {
                                continuation.yield(.textDelta(delta))
                            }
                        case "response.reasoning_text.delta":
                            if let delta = raw["delta"]?.stringValue {
                                continuation.yield(.reasoningDelta(delta))
                            }
                        case "response.output_item.done":
                            if let toolCall = huggingFaceToolCall(from: raw["item"]) {
                                continuation.yield(.toolCall(toolCall))
                            }
                        case "response.completed", "response.incomplete":
                            let response = raw["response"] ?? raw
                            continuation.yield(.finish(
                                reason: huggingFaceFinishReason(response["incomplete_details"]?["reason"]?.stringValue ?? "stop"),
                                usage: tokenUsage(from: response)
                            ))
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func body(for request: LanguageModelRequest, stream: Bool) -> [String: JSONValue] {
        let options = huggingFaceProviderOptions(from: request.extraBody)
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "input": .array(request.messages.compactMap(huggingFaceInputMessage))
        ]
        if stream { body["stream"] = true }
        if let temperature = request.temperature { body["temperature"] = .number(temperature) }
        if let topP = request.topP { body["top_p"] = .number(topP) }
        if let maxOutputTokens = request.maxOutputTokens { body["max_output_tokens"] = .number(Double(maxOutputTokens)) }
        if let metadata = options["metadata"] { body["metadata"] = metadata }
        if let instructions = options["instructions"] { body["instructions"] = instructions }
        if let reasoningEffort = options["reasoningEffort"] ?? options["reasoning_effort"] {
            body["reasoning"] = .object(["effort": reasoningEffort])
        }
        let tools = huggingFaceTools(from: request.tools)
        if !tools.isEmpty {
            body["tools"] = .array(tools)
            if let toolChoice = huggingFaceToolChoice(from: options["toolChoice"] ?? options["tool_choice"]) {
                body["tool_choice"] = toolChoice
            }
        }
        for (key, value) in options where !["metadata", "instructions", "reasoningEffort", "reasoning_effort", "toolChoice", "tool_choice", "strictJsonSchema"].contains(key) {
            body[key] = value
        }
        return body
    }
}

private func huggingFaceProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "huggingface")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func huggingFaceInputMessage(_ message: AIMessage) -> JSONValue? {
    switch message.role {
    case .system:
        return .object(["role": .string("system"), "content": .string(message.combinedText)])
    case .user:
        return .object([
            "role": .string("user"),
            "content": .array(message.content.compactMap(huggingFaceInputContentPart))
        ])
    case .assistant:
        return .object([
            "role": .string("assistant"),
            "content": .array(message.combinedText.isEmpty ? [] : [.object(["type": .string("output_text"), "text": .string(message.combinedText)])])
        ])
    case .tool:
        return nil
    }
}

private func huggingFaceInputContentPart(_ part: AIContentPart) -> JSONValue? {
    switch part {
    case let .text(text):
        return .object(["type": .string("input_text"), "text": .string(text)])
    case let .imageURL(url):
        return .object(["type": .string("input_image"), "image_url": .string(url)])
    case let .data(mimeType, data), let .file(mimeType, data, _):
        guard mimeType.lowercased().hasPrefix("image/") else { return nil }
        return .object([
            "type": .string("input_image"),
            "image_url": .string("data:\(mimeType);base64,\(data.base64EncodedString())")
        ])
    }
}

private func huggingFaceTools(from tools: [String: JSONValue]) -> [JSONValue] {
    tools.map { name, schema in
        .object([
            "type": .string("function"),
            "name": .string(name),
            "parameters": schema
        ])
    }
}

private func huggingFaceToolChoice(from value: JSONValue?) -> JSONValue? {
    guard let value else { return nil }
    if let string = value.stringValue { return .string(string) }
    if let object = value.objectValue,
       let type = object["type"]?.stringValue,
       type == "tool",
       let toolName = object["toolName"]?.stringValue ?? object["tool_name"]?.stringValue {
        return .object(["type": .string("function"), "name": .string(toolName)])
    }
    return value
}

private func huggingFaceResponseContent(from raw: JSONValue) -> (text: String, reasoning: String, toolCalls: [AIToolCall], sources: [AISource]) {
    var textParts: [String] = []
    var reasoningParts: [String] = []
    var toolCalls: [AIToolCall] = []
    var sources: [AISource] = []

    for item in raw["output"]?.arrayValue ?? [] {
        switch item["type"]?.stringValue {
        case "message":
            for content in item["content"]?.arrayValue ?? [] {
                if let text = content["text"]?.stringValue {
                    textParts.append(text)
                }
                for annotation in content["annotations"]?.arrayValue ?? [] {
                    guard let url = annotation["url"]?.stringValue else { continue }
                    sources.append(AISource(
                        id: "huggingface-source-\(sources.count)",
                        sourceType: "url",
                        url: url,
                        title: annotation["title"]?.stringValue,
                        rawValue: annotation
                    ))
                }
            }
        case "reasoning":
            reasoningParts.append(contentsOf: item["content"]?.arrayValue?.compactMap(\.["text"]?.stringValue) ?? [])
        default:
            if let toolCall = huggingFaceToolCall(from: item) {
                toolCalls.append(toolCall)
            }
        }
    }

    if textParts.isEmpty, let outputText = raw["output_text"]?.stringValue {
        textParts.append(outputText)
    }

    return (textParts.joined(), reasoningParts.joined(), toolCalls, sources)
}

private func huggingFaceToolCall(from item: JSONValue?) -> AIToolCall? {
    guard let item, let type = item["type"]?.stringValue else { return nil }
    switch type {
    case "function_call":
        guard let name = item["name"]?.stringValue else { return nil }
        return AIToolCall(
            id: item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "function-call",
            name: name,
            arguments: item["arguments"]?.stringValue ?? "{}",
            rawValue: item
        )
    case "mcp_call":
        guard let name = item["name"]?.stringValue else { return nil }
        return AIToolCall(
            id: item["id"]?.stringValue ?? "mcp-call",
            name: name,
            arguments: item["arguments"]?.stringValue ?? "{}",
            providerExecuted: true,
            rawValue: item
        )
    case "mcp_list_tools":
        let arguments = huggingFaceJSONString(.object(["server_label": item["server_label"] ?? .null])) ?? "{}"
        return AIToolCall(
            id: item["id"]?.stringValue ?? "mcp-list-tools",
            name: "list_tools",
            arguments: arguments,
            providerExecuted: true,
            rawValue: item
        )
    default:
        return nil
    }
}

private func huggingFaceFinishReason(_ reason: String?) -> String? {
    switch reason {
    case "stop":
        return "stop"
    case "length":
        return "length"
    case "content_filter":
        return "content-filter"
    case "tool_calls":
        return "tool-calls"
    case "error":
        return "error"
    default:
        return "other"
    }
}

private func huggingFaceJSONString(_ value: JSONValue) -> String? {
    guard let data = try? encodeJSONBody(value) else { return nil }
    return String(data: data, encoding: .utf8)
}
