import Foundation

public final class MistralLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "mistral.chat"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = body(for: request, stream: false)
        let response = try await config.sendJSONResponse(
            path: "/chat/completions",
            modelID: modelID,
            body: .object(prepared.body),
            headers: request.headers,
            abortSignal: request.abortSignal
        )
        let raw = response.json
        let choice = raw["choices"]?[0]
        let text = mistralText(from: choice?["message"]?["content"]) ?? ""
        let reasoning = mistralReasoning(from: choice?["message"]?["content"]) ?? ""
        let toolCalls = mistralToolCalls(from: choice?["message"]?["tool_calls"])
        guard choice != nil else {
            throw AIError.invalidResponse(provider: providerID, message: "No Mistral choice found.")
        }
        return TextGenerationResult(
            text: text,
            reasoning: reasoning,
            finishReason: mapMistralFinishReason(choice?["finish_reason"]?.stringValue),
            usage: tokenUsage(from: raw),
            toolCalls: toolCalls,
            rawValue: raw,
            warnings: prepared.warnings,
            responseMetadata: mistralResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = body(for: request, stream: true)
                    let response = try await config.transport.send(config.request(
                        path: "/chat/completions",
                        modelID: modelID,
                        body: .object(prepared.body),
                        headers: request.headers,
                        abortSignal: request.abortSignal
                    ))
                    guard (200..<300).contains(response.statusCode) else {
                        throw httpStatusError(provider: providerID, response: response)
                    }
                    continuation.yield(.streamStart(warnings: prepared.warnings))
                    var finishReason: String?
                    var usage: TokenUsage?
                    var emittedResponseMetadata = false
                    var activeText = false
                    var activeReasoningID: String?
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        if !emittedResponseMetadata {
                            emittedResponseMetadata = true
                            continuation.yield(.responseMetadata(mistralResponseMetadata(from: raw, response: response, modelID: modelID)))
                        }
                        if let delta = mistralText(from: raw["choices"]?[0]?["delta"]?["content"]), !delta.isEmpty {
                            if let reasoningID = activeReasoningID {
                                continuation.yield(.reasoningEnd(id: reasoningID))
                                activeReasoningID = nil
                            }
                            if !activeText {
                                continuation.yield(.textStart(id: "0"))
                                activeText = true
                            }
                            continuation.yield(.textDeltaPart(id: "0", delta: delta))
                        }
                        if let reasoning = mistralReasoning(from: raw["choices"]?[0]?["delta"]?["content"]), !reasoning.isEmpty {
                            if activeText {
                                continuation.yield(.textEnd(id: "0"))
                                activeText = false
                            }
                            let id = activeReasoningID ?? "reasoning-0"
                            if activeReasoningID == nil {
                                activeReasoningID = id
                                continuation.yield(.reasoningStart(id: id))
                            }
                            continuation.yield(.reasoningDeltaPart(id: id, delta: reasoning))
                        }
                        for toolCall in mistralToolCalls(from: raw["choices"]?[0]?["delta"]?["tool_calls"]) {
                            continuation.yield(.toolInputStart(id: toolCall.id, name: toolCall.name))
                            continuation.yield(.toolCallDelta(id: toolCall.id, name: toolCall.name, argumentsDelta: toolCall.arguments, index: nil))
                            if !toolCall.arguments.isEmpty {
                                continuation.yield(.toolInputDelta(id: toolCall.id, delta: toolCall.arguments))
                            }
                            continuation.yield(.toolInputEnd(id: toolCall.id))
                            continuation.yield(.toolCall(toolCall))
                        }
                        if let reason = raw["choices"]?[0]?["finish_reason"]?.stringValue {
                            finishReason = mapMistralFinishReason(reason)
                        }
                        if raw["usage"] != nil {
                            usage = tokenUsage(from: raw)
                        }
                    }
                    if let reasoningID = activeReasoningID {
                        continuation.yield(.reasoningEnd(id: reasoningID))
                    }
                    if activeText {
                        continuation.yield(.textEnd(id: "0"))
                    }
                    continuation.yield(.finish(reason: finishReason, usage: usage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func body(for request: LanguageModelRequest, stream: Bool) -> MistralPreparedCall {
        var options = mistralProviderOptions(from: request)
        let responseFormat = mistralResolvedResponseFormat(request: request, options: &options)
        let warnings = mistralWarnings(for: request, modelID: modelID)
        let messages = mistralMessages(request.messages, responseFormat: responseFormat)
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "messages": .array(mistralMessagesJSON(messages))
        ]
        if stream { body["stream"] = true }
        if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
        if let temperature = request.temperature { body["temperature"] = .number(temperature) }
        if let topP = request.topP { body["top_p"] = .number(topP) }
        if !request.stopSequences.isEmpty { body["stop"] = .array(request.stopSequences) }
        if let seed = request.seed { body["random_seed"] = .number(Double(seed)) }
        if let responseFormat = responseFormat {
            body["response_format"] = mistralResponseFormat(from: responseFormat, options: options)
        }
        let toolChoiceInput = request.toolChoice ?? options["toolChoice"]
        let toolChoice = mistralToolChoice(from: toolChoiceInput)
        let tools = mistralTools(from: request.tools, only: mistralForcedToolName(from: toolChoiceInput))
        if !tools.isEmpty {
            body["tools"] = .array(tools)
            if let toolChoice {
                body["tool_choice"] = toolChoice
            }
        }
        for (key, value) in options {
            switch key {
            case "safePrompt":
                body["safe_prompt"] = value
            case "randomSeed":
                body["random_seed"] = value
            case "reasoningEffort":
                body["reasoning_effort"] = value
            case "documentImageLimit":
                body["document_image_limit"] = value
            case "documentPageLimit":
                body["document_page_limit"] = value
            case "parallelToolCalls":
                if !tools.isEmpty { body["parallel_tool_calls"] = value }
            case "responseFormat", "structuredOutputs", "strictJsonSchema":
                continue
            case "toolChoice":
                continue
            case "mistral":
                continue
            default:
                body[key] = value
            }
        }
        if body["reasoning_effort"] == nil,
           let reasoning = request.reasoning,
           mistralSupportsReasoningEffort(modelID) {
            body["reasoning_effort"] = .string(reasoning == "none" ? "none" : "high")
        }
        return MistralPreparedCall(body: body, warnings: warnings)
    }
}

private struct MistralPreparedCall {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
}

private func mistralResolvedResponseFormat(request: LanguageModelRequest, options: inout [String: JSONValue]) -> JSONValue? {
    if let responseFormat = request.responseFormat {
        options.removeValue(forKey: "responseFormat")
        return mistralResponseFormatJSON(responseFormat)
    }
    return options.removeValue(forKey: "responseFormat")
}

private func mistralResponseFormatJSON(_ responseFormat: AIResponseFormat) -> JSONValue? {
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

private func mistralWarnings(for request: LanguageModelRequest, modelID: String) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.topK != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "topK"))
    }
    if request.frequencyPenalty != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "frequencyPenalty"))
    }
    if request.presencePenalty != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "presencePenalty"))
    }
    if request.reasoning != nil, !mistralSupportsReasoningEffort(modelID) {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "reasoning",
            message: "This model does not support reasoning configuration."
        ))
    }
    return warnings
}

private func mistralSupportsReasoningEffort(_ modelID: String) -> Bool {
    switch modelID {
    case "mistral-small-latest", "mistral-small-2603", "mistral-medium-3", "mistral-medium-3.5":
        return true
    default:
        return false
    }
}

private func mistralMessages(_ messages: [AIMessage], responseFormat: JSONValue?) -> [AIMessage] {
    guard responseFormat?["type"]?.stringValue == "json",
          responseFormat?["schema"] == nil else {
        return messages
    }
    if let first = messages.first, first.role == .system {
        let system = [first.combinedText, "", "You MUST answer with JSON."]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return [AIMessage.system(system)] + Array(messages.dropFirst())
    }
    return [AIMessage.system("You MUST answer with JSON.")] + messages
}

private func mistralResponseFormat(from value: JSONValue, options: [String: JSONValue]) -> JSONValue {
    guard let object = value.objectValue, object["type"]?.stringValue == "json" else {
        return value
    }
    let structuredOutputs = options["structuredOutputs"]?.boolValue ?? true
    guard structuredOutputs, let schema = object["schema"] else {
        return .object(["type": .string("json_object")])
    }
    let strict = options["strictJsonSchema"] ?? .bool(false)
    var jsonSchema: [String: JSONValue] = [
        "schema": schema,
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

public final class MistralEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    public let providerID = "mistral.embedding"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        guard request.values.count <= 32 else {
            throw AIError.invalidResponse(provider: providerID, message: "Mistral supports at most 32 embedding inputs per call.")
        }
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "input": .array(request.values),
            "encoding_format": .string("float")
        ]
        body.merge(mistralProviderOptions(from: request.extraBody)) { _, new in new }
        let response = try await config.sendJSONResponse(path: "/embeddings", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let embeddings = raw["data"]?.arrayValue?.compactMap { item in
            item["embedding"]?.arrayValue?.compactMap(\.doubleValue)
        } ?? []
        return EmbeddingResult(
            embeddings: embeddings,
            usage: tokenUsage(from: raw),
            rawValue: raw,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

private func mistralProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "mistral")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func mistralProviderOptions(from request: LanguageModelRequest) -> [String: JSONValue] {
    var output = mistralProviderOptions(from: request.extraBody)
    if let nested = request.providerOptions["mistral"]?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func mistralMessagesJSON(_ messages: [AIMessage]) -> [JSONValue] {
    messages.flatMap(mistralMessageJSONs)
}

private func mistralMessageJSONs(_ message: AIMessage) -> [JSONValue] {
    switch message.role {
    case .system:
        return [.object(["role": .string("system"), "content": .string(message.combinedText)])]
    case .assistant:
        var output: [String: JSONValue] = [
            "role": .string("assistant"),
            "content": .string(message.combinedText)
        ]
        let toolCalls = message.content.compactMap(mistralAssistantToolCallJSON)
        if !toolCalls.isEmpty {
            output["tool_calls"] = .array(toolCalls)
        }
        return [.object(output)]
    case .tool:
        let toolMessages = message.content.compactMap(mistralToolMessageJSON)
        if !toolMessages.isEmpty {
            return toolMessages
        }
        return [.object(["role": .string("tool"), "content": .string(message.combinedText)])]
    case .user:
        return [.object([
            "role": .string("user"),
            "content": .array(message.content.compactMap(mistralContentPartJSON))
        ])]
    }
}

private func mistralAssistantToolCallJSON(_ part: AIContentPart) -> JSONValue? {
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

private func mistralToolMessageJSON(_ part: AIContentPart) -> JSONValue? {
    guard case let .toolResult(result) = part else { return nil }
    return .object([
        "role": .string("tool"),
        "name": .string(result.toolName),
        "tool_call_id": .string(result.toolCallID),
        "content": .string(mistralToolResultContent(result))
    ])
}

private func mistralToolResultContent(_ result: AIToolResult) -> String {
    let output = result.modelOutput ?? result.result
    switch output["type"]?.stringValue {
    case "text", "error-text":
        return output["value"]?.stringValue ?? ""
    case "execution-denied":
        return output["reason"]?.stringValue ?? "Tool call execution denied."
    case "content", "json", "error-json":
        if let value = output["value"] {
            return mistralJSONString(value) ?? value.stringValue ?? ""
        }
        return mistralJSONString(output) ?? output.stringValue ?? ""
    default:
        return mistralJSONString(output) ?? output.stringValue ?? ""
    }
}

private func mistralJSONString(_ value: JSONValue) -> String? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

private func mistralContentPartJSON(_ part: AIContentPart) -> JSONValue? {
    switch part {
    case let .text(text):
        return .object(["type": .string("text"), "text": .string(text)])
    case let .imageURL(url):
        return .object(["type": .string("image_url"), "image_url": .string(url)])
    case let .data(mimeType, data) where mimeType.hasPrefix("image/"),
         let .file(mimeType, data, _) where mimeType.hasPrefix("image/"):
        return .object(["type": .string("image_url"), "image_url": .string("data:\(mimeType);base64,\(data.base64EncodedString())")])
    case let .data(mimeType, data) where mimeType == "application/pdf",
         let .file(mimeType, data, _) where mimeType == "application/pdf":
        return .object(["type": .string("document_url"), "document_url": .string("data:\(mimeType);base64,\(data.base64EncodedString())")])
    case .data, .file, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
        return nil
    }
}

private func mistralText(from content: JSONValue?) -> String? {
    if let string = content?.stringValue { return string }
    let parts = content?.arrayValue?.compactMap { part -> String? in
        guard part["type"]?.stringValue == "text" else { return nil }
        return part["text"]?.stringValue
    } ?? []
    return parts.isEmpty ? nil : parts.joined()
}

private func mistralReasoning(from content: JSONValue?) -> String? {
    content?.arrayValue?.compactMap { part -> String? in
        guard part["type"]?.stringValue == "thinking" else { return nil }
        return part["thinking"]?.arrayValue?.compactMap { $0["text"]?.stringValue }.joined()
    }.joined()
}

private func mistralToolCalls(from value: JSONValue?) -> [AIToolCall] {
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

private func mapMistralFinishReason(_ reason: String?) -> String? {
    switch reason {
    case "stop":
        return "stop"
    case "length", "model_length":
        return "length"
    case "tool_calls":
        return "tool-calls"
    default:
        return reason == nil ? nil : "other"
    }
}

private func mistralResponseMetadata(from raw: JSONValue? = nil, response: AIHTTPResponse, modelID: String) -> AIResponseMetadata {
    AIResponseMetadata(
        id: raw?["id"]?.stringValue,
        timestamp: raw?["created"]?.doubleValue.map { Date(timeIntervalSince1970: $0) } ?? Date(),
        modelID: raw?["model"]?.stringValue ?? modelID,
        headers: response.headers,
        body: raw
    )
}

private func mistralTools(from tools: [String: JSONValue], only forcedName: String?) -> [JSONValue] {
    tools.compactMap { name, schema in
        if let forcedName, forcedName != name { return nil }
        var function: [String: JSONValue] = [
            "name": .string(name),
            "parameters": schema
        ]
        if let description = schema["description"]?.stringValue {
            function["description"] = .string(description)
        }
        return .object([
            "type": .string("function"),
            "function": .object(function)
        ])
    }
}

private func mistralToolChoice(from value: JSONValue?) -> JSONValue? {
    if let string = value?.stringValue {
        return .string(string == "required" ? "any" : string)
    }
    guard let object = value?.objectValue else { return nil }
    switch object["type"]?.stringValue {
    case "auto", "none":
        return object["type"]
    case "required", "tool":
        return .string("any")
    default:
        return nil
    }
}

private func mistralForcedToolName(from value: JSONValue?) -> String? {
    guard let object = value?.objectValue,
          object["type"]?.stringValue == "tool" else {
        return nil
    }
    return object["toolName"]?.stringValue ?? object["tool_name"]?.stringValue
}
