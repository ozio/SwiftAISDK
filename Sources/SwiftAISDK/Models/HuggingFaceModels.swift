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
        let prepared = try huggingFacePreparedCall(for: request, modelID: modelID, stream: false)
        let response = try await config.sendJSONResponse(
            path: "/responses",
            modelID: modelID,
            body: .object(prepared.body),
            headers: request.headers,
            abortSignal: request.abortSignal
        )
        let raw = response.json
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
            toolResults: parsed.toolResults,
            sources: parsed.sources,
            providerMetadata: ["huggingface": .object(["responseId": raw["id"] ?? .null])],
            rawValue: raw,
            warnings: prepared.warnings,
            responseMetadata: huggingFaceResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = try huggingFacePreparedCall(for: request, modelID: modelID, stream: true)
                    let httpRequest = try config.request(
                        path: "/responses",
                        modelID: modelID,
                        body: .object(prepared.body),
                        headers: request.headers,
                        abortSignal: request.abortSignal
                    )
                    let response = try await config.transport.send(httpRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        throw apiCallError(provider: providerID, response: response)
                    }

                    continuation.yield(.responseMetadata(aiResponseMetadata(response: response, modelID: modelID)))
                    if !prepared.warnings.isEmpty {
                        continuation.yield(.streamStart(warnings: prepared.warnings))
                    }

                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }

                        switch raw["type"]?.stringValue {
                        case "response.created":
                            let metadataRaw = raw["response"] ?? raw
                            continuation.yield(.responseMetadata(huggingFaceResponseMetadata(from: metadataRaw, response: response, modelID: modelID)))
                        case "response.output_item.added":
                            for part in huggingFaceOutputItemAddedParts(from: raw["item"]) {
                                continuation.yield(part)
                            }
                        case "response.output_text.delta":
                            if let delta = raw["delta"]?.stringValue, !delta.isEmpty {
                                continuation.yield(.textDeltaPart(
                                    id: raw["item_id"]?.stringValue ?? "text",
                                    delta: delta,
                                    providerMetadata: huggingFaceItemMetadata(id: raw["item_id"]?.stringValue)
                                ))
                            }
                        case "response.reasoning_text.delta":
                            if let delta = raw["delta"]?.stringValue, !delta.isEmpty {
                                continuation.yield(.reasoningDeltaPart(
                                    id: raw["item_id"]?.stringValue ?? "reasoning",
                                    delta: delta,
                                    providerMetadata: huggingFaceItemMetadata(id: raw["item_id"]?.stringValue)
                                ))
                            }
                        case "response.reasoning_text.done":
                            continuation.yield(.reasoningEnd(
                                id: raw["item_id"]?.stringValue ?? "reasoning",
                                providerMetadata: huggingFaceItemMetadata(id: raw["item_id"]?.stringValue)
                            ))
                        case "response.output_item.done":
                            for part in huggingFaceOutputItemDoneParts(from: raw["item"]) {
                                continuation.yield(part)
                            }
                        case "response.completed", "response.incomplete":
                            let response = raw["response"] ?? raw
                            continuation.yield(.finishMetadata(
                                reason: huggingFaceFinishReason(response["incomplete_details"]?["reason"]?.stringValue ?? "stop"),
                                usage: tokenUsage(from: response),
                                providerMetadata: ["huggingface": .object(["responseId": response["id"] ?? .null])]
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
}

private struct HuggingFacePreparedCall {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
}

private func huggingFacePreparedCall(for request: LanguageModelRequest, modelID: String, stream: Bool) throws -> HuggingFacePreparedCall {
    var options = try huggingFaceProviderOptions(from: request)
    let responseFormat = huggingFaceResolvedResponseFormat(request: request, options: &options)
    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "input": .array(try request.messages.compactMap(huggingFaceInputMessage))
    ]
    if stream { body["stream"] = true }
    if let temperature = request.temperature { body["temperature"] = .number(temperature) }
    if let topP = request.topP { body["top_p"] = .number(topP) }
    if let maxOutputTokens = request.maxOutputTokens { body["max_output_tokens"] = .number(Double(maxOutputTokens)) }
    if let textFormat = huggingFaceTextFormat(from: responseFormat, strictJsonSchema: options["strictJsonSchema"]) {
        body["text"] = .object(["format": textFormat])
    }
    if let metadata = options["metadata"] { body["metadata"] = metadata }
    if let instructions = options["instructions"] { body["instructions"] = instructions }
    if let reasoningEffort = options["reasoningEffort"] ?? options["reasoning_effort"] {
        body["reasoning"] = .object(["effort": reasoningEffort])
    }
    let preparedTools = huggingFaceTools(from: request.tools)
    if !preparedTools.tools.isEmpty {
        body["tools"] = .array(preparedTools.tools)
        if let toolChoice = huggingFaceToolChoice(from: request.toolChoice ?? options["toolChoice"] ?? options["tool_choice"]) {
            body["tool_choice"] = toolChoice
        }
    }
    for (key, value) in options where !["metadata", "instructions", "reasoningEffort", "reasoning_effort", "toolChoice", "tool_choice", "responseFormat", "strictJsonSchema"].contains(key) {
        body[key] = value
    }
    return HuggingFacePreparedCall(body: body, warnings: huggingFaceWarnings(for: request) + preparedTools.warnings)
}

private func huggingFaceProviderOptions(from request: LanguageModelRequest) throws -> [String: JSONValue] {
    var output = request.extraBody
    if let nested = output.removeValue(forKey: "huggingface")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    if let value = request.providerOptions["huggingface"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.huggingface", message: "Hugging Face provider options must be an object.")
        }
        for key in huggingFaceResponsesProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try huggingFaceValidateResponsesProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

private let huggingFaceResponsesProviderOptionKeys: Set<String> = [
    "metadata",
    "instructions",
    "strictJsonSchema",
    "reasoningEffort"
]

private func huggingFaceValidateResponsesProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where huggingFaceResponsesProviderOptionKeys.contains(key) {
        guard value != .null else {
            throw AIError.invalidArgument(argument: "providerOptions.huggingface.\(key)", message: "Hugging Face \(key) cannot be null.")
        }
        switch key {
        case "metadata":
            guard let metadata = value.objectValue else {
                throw AIError.invalidArgument(argument: "providerOptions.huggingface.metadata", message: "Hugging Face metadata must be a string record.")
            }
            for metadataKey in metadata.keys.sorted() where metadata[metadataKey]?.stringValue == nil {
                throw AIError.invalidArgument(argument: "providerOptions.huggingface.metadata.\(metadataKey)", message: "Hugging Face metadata values must be strings.")
            }
            output[key] = value
        case "instructions", "reasoningEffort":
            guard value.stringValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.huggingface.\(key)", message: "Hugging Face \(key) must be a string.")
            }
            output[key] = value
        case "strictJsonSchema":
            guard value.boolValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.huggingface.strictJsonSchema", message: "Hugging Face strictJsonSchema must be a boolean.")
            }
            output[key] = value
        default:
            break
        }
    }
    return output
}

private func huggingFaceResolvedResponseFormat(request: LanguageModelRequest, options: inout [String: JSONValue]) -> JSONValue? {
    if let responseFormat = request.responseFormat {
        options.removeValue(forKey: "responseFormat")
        return huggingFaceResponseFormatJSON(responseFormat)
    }
    return options.removeValue(forKey: "responseFormat")
}

private func huggingFaceResponseFormatJSON(_ responseFormat: AIResponseFormat) -> JSONValue? {
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

private func huggingFaceTextFormat(from responseFormat: JSONValue?, strictJsonSchema: JSONValue?) -> JSONValue? {
    guard responseFormat?["type"]?.stringValue == "json",
          let schema = responseFormat?["schema"] else {
        return nil
    }
    var format: [String: JSONValue] = [
        "type": .string("json_schema"),
        "strict": strictJsonSchema ?? .bool(false),
        "name": responseFormat?["name"] ?? .string("response"),
        "schema": schema
    ]
    if let description = responseFormat?["description"] {
        format["description"] = description
    }
    return .object(format)
}

private func huggingFaceWarnings(for request: LanguageModelRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.topK != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "topK"))
    }
    if request.seed != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "seed"))
    }
    if request.presencePenalty != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "presencePenalty"))
    }
    if request.frequencyPenalty != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "frequencyPenalty"))
    }
    if !request.stopSequences.isEmpty {
        warnings.append(AIWarning(type: "unsupported", feature: "stopSequences"))
    }
    if request.messages.contains(where: { $0.role == .tool }) {
        warnings.append(AIWarning(type: "unsupported", feature: "tool messages"))
    }
    return warnings
}

private func huggingFaceInputMessage(_ message: AIMessage) throws -> JSONValue? {
    switch message.role {
    case .system:
        return .object(["role": .string("system"), "content": .string(message.combinedText)])
    case .user:
        return .object([
            "role": .string("user"),
            "content": .array(try message.content.compactMap(huggingFaceInputContentPart))
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

private func huggingFaceInputContentPart(_ part: AIContentPart) throws -> JSONValue? {
    switch part {
    case let .text(text, _):
        return .object(["type": .string("input_text"), "text": .string(text)])
    case let .reasoning(text, _):
        return .object(["type": .string("input_text"), "text": .string(text)])
    case let .imageURL(url, _):
        return .object(["type": .string("input_image"), "image_url": .string(url)])
    case let .data(mimeType, data, _), let .file(mimeType, data, _, _):
        guard mimeType.lowercased().hasPrefix("image/") else {
            throw AIError.invalidArgument(argument: "files", message: "Hugging Face Responses API only supports image file parts; got \(mimeType).")
        }
        return .object([
            "type": .string("input_image"),
            "image_url": .string("data:\(mimeType);base64,\(data.base64EncodedString())")
        ])
    case let .providerReference(mimeType, _, _, _):
        guard mimeType.lowercased().hasPrefix("image/") else {
            throw AIError.invalidArgument(argument: "files", message: "Hugging Face Responses API only supports image file parts; got \(mimeType).")
        }
        return nil
    case .reasoningFile, .custom, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
        return nil
    }
}

private func huggingFaceTools(from tools: [String: JSONValue]) -> (tools: [JSONValue], warnings: [AIWarning]) {
    var output: [JSONValue] = []
    var warnings: [AIWarning] = []
    for (name, schema) in tools {
        if schema["type"]?.stringValue == "provider" || schema["id"]?.stringValue != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "provider-defined tool \(schema["id"]?.stringValue ?? name)"))
            continue
        }
        var tool: [String: JSONValue] = [
            "type": .string("function"),
            "name": .string(name),
            "parameters": schema
        ]
        if let description = schema["description"]?.stringValue {
            tool["description"] = .string(description)
        }
        output.append(.object(tool))
    }
    return (output, warnings)
}

private func huggingFaceToolChoice(from value: JSONValue?) -> JSONValue? {
    guard let value else { return nil }
    if let string = value.stringValue { return .string(string) }
    guard let object = value.objectValue else { return nil }
    switch object["type"]?.stringValue {
    case "auto", "required":
        return object["type"]
    case "none":
        return nil
    case "tool":
        guard let toolName = object["toolName"]?.stringValue ?? object["tool_name"]?.stringValue else { return nil }
        return .object([
            "type": .string("function"),
            "function": .object(["name": .string(toolName)])
        ])
    default:
        return nil
    }
}

private func huggingFaceResponseContent(from raw: JSONValue) -> (text: String, reasoning: String, toolCalls: [AIToolCall], toolResults: [AIToolResult], sources: [AISource]) {
    var textParts: [String] = []
    var reasoningParts: [String] = []
    var toolCalls: [AIToolCall] = []
    var toolResults: [AIToolResult] = []
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
            if let toolResult = huggingFaceToolResult(from: item) {
                toolResults.append(toolResult)
            }
        }
    }

    if textParts.isEmpty, let outputText = raw["output_text"]?.stringValue {
        textParts.append(outputText)
    }

    return (textParts.joined(), reasoningParts.joined(), toolCalls, toolResults, sources)
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

private func huggingFaceToolResult(from item: JSONValue?) -> AIToolResult? {
    guard let item, let type = item["type"]?.stringValue else { return nil }
    switch type {
    case "function_call":
        guard let output = item["output"], let name = item["name"]?.stringValue else { return nil }
        return AIToolResult(
            toolCallID: item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "function-call",
            toolName: name,
            result: output,
            modelOutput: output,
            providerMetadata: huggingFaceItemMetadata(id: item["id"]?.stringValue)
        )
    case "mcp_call":
        guard let output = item["output"], let name = item["name"]?.stringValue else { return nil }
        return AIToolResult(
            toolCallID: item["id"]?.stringValue ?? "mcp-call",
            toolName: name,
            result: output,
            modelOutput: output,
            providerMetadata: huggingFaceItemMetadata(id: item["id"]?.stringValue)
        )
    case "mcp_list_tools":
        guard let tools = item["tools"] else { return nil }
        let result: JSONValue = .object(["tools": tools])
        return AIToolResult(
            toolCallID: item["id"]?.stringValue ?? "mcp-list-tools",
            toolName: "list_tools",
            result: result,
            modelOutput: result,
            providerMetadata: huggingFaceItemMetadata(id: item["id"]?.stringValue)
        )
    default:
        return nil
    }
}

private func huggingFaceOutputItemAddedParts(from item: JSONValue?) -> [LanguageStreamPart] {
    guard let item, let type = item["type"]?.stringValue else { return [] }
    switch type {
    case "message" where item["role"]?.stringValue == "assistant":
        let id = item["id"]?.stringValue ?? "message"
        return [.textStart(id: id, providerMetadata: huggingFaceItemMetadata(id: id))]
    case "reasoning":
        let id = item["id"]?.stringValue ?? "reasoning"
        return [.reasoningStart(id: id, providerMetadata: huggingFaceItemMetadata(id: id))]
    case "function_call":
        guard let name = item["name"]?.stringValue else { return [] }
        return [.toolInputStart(id: item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "function-call", name: name)]
    case "mcp_call":
        guard let name = item["name"]?.stringValue else { return [] }
        return [.toolInputStart(id: item["id"]?.stringValue ?? "mcp-call", name: name, providerExecuted: true)]
    case "mcp_list_tools":
        return [.toolInputStart(id: item["id"]?.stringValue ?? "mcp-list-tools", name: "list_tools", providerExecuted: true)]
    default:
        return []
    }
}

private func huggingFaceOutputItemDoneParts(from item: JSONValue?) -> [LanguageStreamPart] {
    guard let item, let type = item["type"]?.stringValue else { return [] }
    switch type {
    case "message" where item["role"]?.stringValue == "assistant":
        let id = item["id"]?.stringValue ?? "message"
        return [.textEnd(id: id, providerMetadata: huggingFaceItemMetadata(id: id))]
    case "reasoning":
        let id = item["id"]?.stringValue ?? "reasoning"
        return [.reasoningEnd(id: id, providerMetadata: huggingFaceItemMetadata(id: id))]
    case "function_call", "mcp_call", "mcp_list_tools":
        var parts: [LanguageStreamPart] = []
        if type == "function_call" {
            parts.append(.toolInputEnd(id: item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "function-call"))
        } else {
            parts.append(.toolInputEnd(id: item["id"]?.stringValue ?? type))
        }
        if let toolCall = huggingFaceToolCall(from: item) {
            parts.append(.toolCall(toolCall))
        }
        if let toolResult = huggingFaceToolResult(from: item) {
            parts.append(.toolResult(toolResult))
        }
        return parts
    default:
        if let toolCall = huggingFaceToolCall(from: item) {
            return [.toolCall(toolCall)]
        }
        return []
    }
}

private func huggingFaceItemMetadata(id: String?) -> [String: JSONValue] {
    guard let id else { return [:] }
    return ["huggingface": .object(["itemId": .string(id)])]
}

private func huggingFaceResponseMetadata(from raw: JSONValue? = nil, response: AIHTTPResponse, modelID: String) -> AIResponseMetadata {
    AIResponseMetadata(
        id: raw?["id"]?.stringValue,
        timestamp: raw?["created_at"]?.doubleValue.map { Date(timeIntervalSince1970: $0) } ?? Date(),
        modelID: raw?["model"]?.stringValue ?? modelID,
        headers: response.headers,
        body: raw
    )
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
