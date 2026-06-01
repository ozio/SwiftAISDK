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
        let prepared = alibabaPreparedCall(
            for: request,
            modelID: modelID,
            stream: false,
            transformRequestBody: config.transformRequestBody
        )
        let response = try await config.sendJSONResponse(
            path: "/chat/completions",
            modelID: modelID,
            body: .object(prepared.body),
            headers: request.headers,
            abortSignal: request.abortSignal
        )
        let raw = response.json
        let choice = raw["choices"]?[0]
        let toolCalls = alibabaToolCalls(from: choice?["message"]?["tool_calls"])
        guard let text = choice?["message"]?["content"]?.stringValue ?? (toolCalls.isEmpty ? nil : "") else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in Alibaba response.")
        }
        return TextGenerationResult(
            text: text,
            reasoning: choice?["message"]?["reasoning_content"]?.stringValue ?? "",
            finishReason: alibabaFinishReason(choice?["finish_reason"]?.stringValue),
            usage: alibabaUsage(from: raw),
            toolCalls: toolCalls,
            rawValue: raw,
            warnings: prepared.warnings,
            responseMetadata: alibabaResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = alibabaPreparedCall(
                        for: request,
                        modelID: modelID,
                        stream: true,
                        transformRequestBody: config.transformRequestBody
                    )
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
                    var latestUsage: TokenUsage?
                    var finishReason: String?
                    var toolCalls = AlibabaStreamingToolCalls()
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
                            continuation.yield(.responseMetadata(alibabaResponseMetadata(from: raw, response: response, modelID: modelID)))
                        }
                        latestUsage = alibabaUsage(from: raw) ?? latestUsage
                        guard let choice = raw["choices"]?[0] else { continue }

                        if let reasoning = choice["delta"]?["reasoning_content"]?.stringValue, !reasoning.isEmpty {
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
                        if let delta = choice["delta"]?["content"]?.stringValue, !delta.isEmpty {
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
                        if let toolCallDeltas = choice["delta"]?["tool_calls"]?.arrayValue {
                            if let reasoningID = activeReasoningID {
                                continuation.yield(.reasoningEnd(id: reasoningID))
                                activeReasoningID = nil
                            }
                            if activeText {
                                continuation.yield(.textEnd(id: "0"))
                                activeText = false
                            }
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
                    if let reasoningID = activeReasoningID {
                        continuation.yield(.reasoningEnd(id: reasoningID))
                    }
                    if activeText {
                        continuation.yield(.textEnd(id: "0"))
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

private struct AlibabaPreparedCall {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
}

private struct AlibabaPreparedMessages {
    var messages: [JSONValue]
    var warnings: [AIWarning]
}

private struct AlibabaPreparedTools {
    var tools: [JSONValue]
    var warnings: [AIWarning]
}

private func alibabaPreparedCall(
    for request: LanguageModelRequest,
    modelID: String,
    stream: Bool,
    transformRequestBody: (@Sendable ([String: JSONValue]) -> [String: JSONValue])?
) -> AlibabaPreparedCall {
    var warnings = alibabaWarnings(for: request)
    var options = alibabaOptions(from: request)
    let responseFormat = alibabaResolvedResponseFormat(request: request, options: &options)
    let toolChoiceInput = request.toolChoice ?? options.removeValue(forKey: "toolChoice")
    let preparedMessages = alibabaMessages(request.messages)
    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "messages": .array(preparedMessages.messages)
    ]
    warnings += preparedMessages.warnings
    if let temperature = request.temperature { body["temperature"] = .number(temperature) }
    if let topP = request.topP { body["top_p"] = .number(topP) }
    if let topK = request.topK { body["top_k"] = .number(Double(topK)) }
    if let presencePenalty = request.presencePenalty { body["presence_penalty"] = .number(presencePenalty) }
    if let seed = request.seed { body["seed"] = .number(Double(seed)) }
    if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
    if !request.stopSequences.isEmpty { body["stop"] = .array(request.stopSequences) }
    let preparedTools = alibabaTools(from: request.tools)
    warnings += preparedTools.warnings
    if !preparedTools.tools.isEmpty {
        body["tools"] = .array(preparedTools.tools)
        if let toolChoice = alibabaToolChoice(from: toolChoiceInput) {
            body["tool_choice"] = toolChoice
        }
        if let parallelToolCalls = options.removeValue(forKey: "parallel_tool_calls") {
            body["parallel_tool_calls"] = parallelToolCalls
        }
    } else {
        options.removeValue(forKey: "parallel_tool_calls")
    }
    if !request.tools.isEmpty {
        warnings += alibabaToolChoiceWarnings(from: toolChoiceInput)
    }
    if let responseFormat {
        body["response_format"] = responseFormat
    }
    alibabaApplyThinking(request: request, options: &options, body: &body, warnings: &warnings)
    body.merge(options) { _, new in new }
    if stream {
        body["stream"] = true
        if body["stream_options"] == nil {
            body["stream_options"] = .object(["include_usage": true])
        }
    }
    return AlibabaPreparedCall(body: transformRequestBody?(body) ?? body, warnings: warnings)
}

private func alibabaMessages(_ messages: [AIMessage]) -> AlibabaPreparedMessages {
    var output: [JSONValue] = []
    var warnings: [AIWarning] = []
    for message in messages {
        let prepared = alibabaMessageJSONs(message)
        output += prepared.messages
        warnings += prepared.warnings
    }
    return AlibabaPreparedMessages(messages: output, warnings: warnings)
}

private struct AlibabaPreparedMessageParts {
    var parts: [JSONValue]
    var warnings: [AIWarning]
}

private func alibabaMessageJSONs(_ message: AIMessage) -> AlibabaPreparedMessages {
    switch message.role {
    case .system:
        return AlibabaPreparedMessages(messages: [.object([
            "role": .string("system"),
            "content": .string(message.combinedText)
        ])], warnings: [])
    case .user:
        let content = alibabaUserContentParts(message.content)
        return AlibabaPreparedMessages(messages: [.object([
            "role": .string("user"),
            "content": .array(content.parts)
        ])], warnings: content.warnings)
    case .assistant:
        var output: [String: JSONValue] = [
            "role": .string("assistant"),
            "content": message.combinedText.isEmpty ? .null : .string(message.combinedText)
        ]
        let toolCalls = message.content.compactMap(alibabaAssistantToolCallJSON)
        if !toolCalls.isEmpty {
            output["tool_calls"] = .array(toolCalls)
        }
        return AlibabaPreparedMessages(messages: [.object(output)], warnings: [])
    case .tool:
        let results = message.content.compactMap(alibabaToolMessageJSON)
        if !results.isEmpty {
            return AlibabaPreparedMessages(messages: results, warnings: [])
        }
        return AlibabaPreparedMessages(messages: [.object([
            "role": .string("tool"),
            "content": .string(message.combinedText)
        ])], warnings: [])
    }
}

private func alibabaUserContentParts(_ content: [AIContentPart]) -> AlibabaPreparedMessageParts {
    var warnings: [AIWarning] = []
    let parts = content.compactMap { part -> JSONValue? in
        switch part {
        case let .text(text):
            return .object(["type": .string("text"), "text": .string(text)])
        case let .imageURL(url):
            return .object(["type": .string("image_url"), "image_url": .object(["url": .string(url)])])
        case let .data(mimeType, data), let .file(mimeType, data, _):
            guard mimeType.lowercased().hasPrefix("image/") else {
                warnings.append(AIWarning(type: "unsupported", feature: "user message part type: file"))
                return nil
            }
            return .object([
                "type": .string("image_url"),
                "image_url": .object(["url": .string("data:\(mimeType);base64,\(data.base64EncodedString())")])
            ])
        case .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
            warnings.append(AIWarning(type: "unsupported", feature: alibabaUserPartFeature(part)))
            return nil
        }
    }
    return AlibabaPreparedMessageParts(parts: parts, warnings: warnings)
}

private func alibabaUserPartFeature(_ part: AIContentPart) -> String {
    switch part {
    case .data, .file:
        return "user message part type: file"
    case .toolCall:
        return "user message part type: tool-call"
    case .toolResult:
        return "user message part type: tool-result"
    case .toolApprovalRequest:
        return "user message part type: tool-approval-request"
    case .toolApprovalResponse:
        return "user message part type: tool-approval-response"
    case .imageURL:
        return "user message part type: image"
    case .text:
        return "user message part type: text"
    }
}

private func alibabaOptions(from request: LanguageModelRequest) -> [String: JSONValue] {
    var output = alibabaOptions(from: request.extraBody)
    if let nested = request.providerOptions["alibaba"]?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    alibabaNormalizeOptions(&output)
    return output
}

private func alibabaOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "alibaba")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    alibabaNormalizeOptions(&output)
    return output
}

private func alibabaNormalizeOptions(_ output: inout [String: JSONValue]) {
    alibabaMoveKey("topK", to: "top_k", in: &output)
    alibabaMoveKey("presencePenalty", to: "presence_penalty", in: &output)
    alibabaMoveKey("enableThinking", to: "enable_thinking", in: &output)
    alibabaMoveKey("thinkingBudget", to: "thinking_budget", in: &output)
    alibabaMoveKey("parallelToolCalls", to: "parallel_tool_calls", in: &output)
}

private func alibabaResolvedResponseFormat(request: LanguageModelRequest, options: inout [String: JSONValue]) -> JSONValue? {
    if let responseFormat = request.responseFormat {
        options.removeValue(forKey: "responseFormat")
        options.removeValue(forKey: "response_format")
        return alibabaResponseFormatJSON(responseFormat)
    }
    if let responseFormat = options.removeValue(forKey: "responseFormat") {
        return alibabaResponseFormat(from: responseFormat)
    }
    return options.removeValue(forKey: "response_format")
}

private func alibabaResponseFormatJSON(_ responseFormat: AIResponseFormat) -> JSONValue? {
    switch responseFormat {
    case .text:
        return nil
    case let .json(schema, name, description):
        guard let schema else {
            return .object(["type": .string("json_object")])
        }
        var jsonSchema: [String: JSONValue] = [
            "schema": schema,
            "name": name.map(JSONValue.string) ?? .string("response")
        ]
        if let description {
            jsonSchema["description"] = .string(description)
        }
        return .object([
            "type": .string("json_schema"),
            "json_schema": .object(jsonSchema)
        ])
    }
}

private func alibabaResponseFormat(from value: JSONValue) -> JSONValue {
    guard let object = value.objectValue, object["type"]?.stringValue == "json" else {
        return value
    }
    guard let schema = object["schema"] else {
        return .object(["type": .string("json_object")])
    }
    var jsonSchema: [String: JSONValue] = [
        "schema": schema,
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

private func alibabaApplyThinking(
    request: LanguageModelRequest,
    options: inout [String: JSONValue],
    body: inout [String: JSONValue],
    warnings: inout [AIWarning]
) {
    if let enableThinking = options.removeValue(forKey: "enable_thinking") {
        body["enable_thinking"] = enableThinking
    }
    if let thinkingBudget = options.removeValue(forKey: "thinking_budget") {
        body["thinking_budget"] = thinkingBudget
    }
    if body["enable_thinking"] != nil || body["thinking_budget"] != nil {
        return
    }
    guard let reasoning = request.reasoning, reasoning != "provider-default" else { return }
    if reasoning == "none" {
        body["enable_thinking"] = .bool(false)
        return
    }
    body["enable_thinking"] = .bool(true)
    if let budget = alibabaReasoningBudget(reasoning) {
        body["thinking_budget"] = .number(Double(budget))
    } else {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "reasoning",
            message: "reasoning \"\(reasoning)\" is not supported by this model."
        ))
    }
}

private func alibabaReasoningBudget(_ reasoning: String) -> Int? {
    let maxOutputTokens = 16_384.0
    let maxReasoningBudget = 16_384
    let minReasoningBudget = 1_024
    let percentage: Double
    switch reasoning {
    case "minimal":
        percentage = 0.02
    case "low":
        percentage = 0.1
    case "medium":
        percentage = 0.3
    case "high":
        percentage = 0.6
    case "xhigh":
        percentage = 0.9
    default:
        if let explicit = Int(reasoning) {
            return min(max(explicit, 0), maxReasoningBudget)
        }
        return nil
    }
    return min(maxReasoningBudget, max(minReasoningBudget, Int((maxOutputTokens * percentage).rounded())))
}

private func alibabaTools(from tools: [String: JSONValue]) -> AlibabaPreparedTools {
    var warnings: [AIWarning] = []
    let values = tools.compactMap { name, schema -> JSONValue? in
        let object = schema.objectValue
        if object?["type"]?.stringValue == "provider" || object?["id"]?.stringValue != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "provider-defined tool \(object?["id"]?.stringValue ?? name)"
            ))
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
    return AlibabaPreparedTools(tools: values, warnings: warnings)
}

private func alibabaToolChoice(from value: JSONValue?) -> JSONValue? {
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

private func alibabaToolChoiceWarnings(from value: JSONValue?) -> [AIWarning] {
    if let string = value?.stringValue {
        switch string {
        case "auto", "none", "required":
            return []
        default:
            return [AIWarning(type: "unsupported", feature: "tool choice type: \(string)")]
        }
    }
    guard let object = value?.objectValue else { return [] }
    switch object["type"]?.stringValue {
    case "auto", "none", "required", "tool":
        return []
    case let type?:
        return [AIWarning(type: "unsupported", feature: "tool choice type: \(type)")]
    case nil:
        return [AIWarning(type: "unsupported", feature: "tool choice type: undefined")]
    }
}

private func alibabaAssistantToolCallJSON(_ part: AIContentPart) -> JSONValue? {
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

private func alibabaToolMessageJSON(_ part: AIContentPart) -> JSONValue? {
    guard case let .toolResult(result) = part else { return nil }
    return .object([
        "role": .string("tool"),
        "tool_call_id": .string(result.toolCallID),
        "content": .string(alibabaToolResultContent(result))
    ])
}

private func alibabaToolResultContent(_ result: AIToolResult) -> String {
    let output = result.modelOutput ?? result.result
    switch output["type"]?.stringValue {
    case "text", "error-text":
        return output["value"]?.stringValue ?? ""
    case "execution-denied":
        return output["reason"]?.stringValue ?? "Tool call execution denied."
    case "content", "json", "error-json":
        if let value = output["value"] {
            return alibabaJSONString(value) ?? value.stringValue ?? ""
        }
        return alibabaJSONString(output) ?? output.stringValue ?? ""
    default:
        return alibabaJSONString(output) ?? output.stringValue ?? ""
    }
}

private func alibabaWarnings(for request: LanguageModelRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.frequencyPenalty != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "frequencyPenalty"))
    }
    return warnings
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

private func alibabaUsage(from raw: JSONValue) -> TokenUsage? {
    guard let usage = raw["usage"] else { return nil }
    let inputTokens = usage["prompt_tokens"]?.intValue ?? usage["input_tokens"]?.intValue ?? 0
    let outputTokens = usage["completion_tokens"]?.intValue ?? usage["output_tokens"]?.intValue ?? 0
    let cacheReadTokens = usage["prompt_tokens_details"]?["cached_tokens"]?.intValue ?? 0
    let cacheWriteTokens = usage["prompt_tokens_details"]?["cache_creation_input_tokens"]?.intValue ?? 0
    let reasoningTokens = usage["completion_tokens_details"]?["reasoning_tokens"]?.intValue ?? 0
    let totalTokens = usage["total_tokens"]?.intValue ?? inputTokens + outputTokens
    return TokenUsage(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: totalTokens,
        inputTokensNoCache: max(0, inputTokens - cacheReadTokens - cacheWriteTokens),
        inputTokensCacheRead: cacheReadTokens,
        inputTokensCacheWrite: cacheWriteTokens,
        outputTextTokens: outputTokens - reasoningTokens,
        outputReasoningTokens: reasoningTokens,
        rawValue: usage
    )
}

private func alibabaResponseMetadata(from raw: JSONValue? = nil, response: AIHTTPResponse, modelID: String) -> AIResponseMetadata {
    AIResponseMetadata(
        id: raw?["id"]?.stringValue,
        timestamp: raw?["created"]?.doubleValue.map { Date(timeIntervalSince1970: $0) } ?? Date(),
        modelID: raw?["model"]?.stringValue ?? modelID,
        headers: response.headers,
        body: raw
    )
}

private func alibabaJSONString(_ value: JSONValue) -> String? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
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
