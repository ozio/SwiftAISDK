import Foundation

typealias AlibabaStreamingToolCalls = OpenAIStyleStreamingToolCalls

struct AlibabaPreparedCall {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
}

struct AlibabaPreparedMessages {
    var messages: [JSONValue]
    var warnings: [AIWarning]
}

struct AlibabaPreparedTools {
    var tools: [JSONValue]
    var warnings: [AIWarning]
}

func alibabaPreparedCall(
    for request: LanguageModelRequest,
    modelID: String,
    stream: Bool,
    transformRequestBody: (@Sendable ([String: JSONValue]) -> [String: JSONValue])?
) throws -> AlibabaPreparedCall {
    var warnings = alibabaWarnings(for: request)
    var options = try alibabaOptions(from: request)
    let responseFormat = alibabaResolvedResponseFormat(request: request, options: &options)
    let toolChoiceInput = request.toolChoice ?? options.removeValue(forKey: "toolChoice")
    let explicitPreserveThinking = options.removeValue(forKey: "preserve_thinking")?.boolValue
    let preserveThinking = explicitPreserveThinking ?? alibabaSupportsPreservedThinking(modelID)
    let preparedMessages = alibabaMessages(request.messages, preserveThinking: preserveThinking)
    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "messages": .array(preparedMessages.messages)
    ]
    if explicitPreserveThinking != nil || alibabaSupportsPreservedThinking(modelID) {
        body["preserve_thinking"] = .bool(preserveThinking)
    }
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

func alibabaMessages(_ messages: [AIMessage], preserveThinking: Bool = false) -> AlibabaPreparedMessages {
    var output: [JSONValue] = []
    var warnings: [AIWarning] = []
    let lastUserMessageIndex = messages.lastIndex { $0.role == .user } ?? -1
    for (index, message) in messages.enumerated() {
        let prepared = alibabaMessageJSONs(
            message,
            includeReasoning: preserveThinking || index > lastUserMessageIndex
        )
        output += prepared.messages
        warnings += prepared.warnings
    }
    return AlibabaPreparedMessages(messages: output, warnings: warnings)
}

private func alibabaSupportsPreservedThinking(_ modelID: String) -> Bool {
    let models: Set<String> = [
        "kimi-k2.7-code",
        "qwen3.6-max-preview",
        "qwen3.6-plus",
        "qwen3.6-plus-2026-04-02",
        "qwen3.7-flash",
        "qwen3.7-flash-2026-07-15",
        "qwen3.7-max",
        "qwen3.7-max-2026-05-17",
        "qwen3.7-max-2026-05-20",
        "qwen3.7-max-2026-06-08",
        "qwen3.7-max-preview",
        "qwen3.7-plus",
        "qwen3.7-plus-2026-05-26",
        "qwen3.8-flash",
        "qwen3.8-max",
        "qwen3.8-max-0902"
    ]
    return models.contains(modelID)
}

struct AlibabaPreparedMessageParts {
    var parts: [JSONValue]
    var warnings: [AIWarning]
}

func alibabaMessageJSONs(_ message: AIMessage, includeReasoning: Bool = false) -> AlibabaPreparedMessages {
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
        let toolCalls = message.content.compactMap(alibabaAssistantToolCallJSON)
        let text = message.combinedText
        let reasoning = includeReasoning
            ? message.content.compactMap { part -> String? in
                if case let .reasoning(value, _) = part { return value }
                return nil
            }.joined()
            : ""
        guard !text.isEmpty || !toolCalls.isEmpty || !reasoning.isEmpty else {
            return AlibabaPreparedMessages(messages: [], warnings: [])
        }
        var output: [String: JSONValue] = [
            "role": .string("assistant"),
            "content": text.isEmpty ? .null : .string(text)
        ]
        if !toolCalls.isEmpty {
            output["tool_calls"] = .array(toolCalls)
        }
        if !reasoning.isEmpty {
            output["reasoning_content"] = .string(reasoning)
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

func alibabaUserContentParts(_ content: [AIContentPart]) -> AlibabaPreparedMessageParts {
    var warnings: [AIWarning] = []
    let parts = content.compactMap { part -> JSONValue? in
        switch part {
        case let .text(text, _):
            return .object(["type": .string("text"), "text": .string(text)])
        case let .imageURL(url, _):
            return .object(["type": .string("image_url"), "image_url": .object(["url": .string(url)])])
        case let .data(mimeType, data, _), let .file(mimeType, data, _, _):
            guard mimeType.lowercased().hasPrefix("image/") else {
                warnings.append(AIWarning(type: "unsupported", feature: "user message part type: file"))
                return nil
            }
            return .object([
                "type": .string("image_url"),
                "image_url": .object(["url": .string("data:\(mimeType);base64,\(data.base64EncodedString())")])
            ])
        case .reasoning, .reasoningFile, .custom, .providerReference, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
            warnings.append(AIWarning(type: "unsupported", feature: alibabaUserPartFeature(part)))
            return nil
        }
    }
    return AlibabaPreparedMessageParts(parts: parts, warnings: warnings)
}

func alibabaUserPartFeature(_ part: AIContentPart) -> String {
    switch part {
    case .data, .file, .providerReference:
        return "user message part type: file"
    case .toolCall:
        return "user message part type: tool-call"
    case .toolResult:
        return "user message part type: tool-result"
    case .toolApprovalRequest:
        return "user message part type: tool-approval-request"
    case .toolApprovalResponse:
        return "user message part type: tool-approval-response"
    case .reasoning:
        return "user message part type: reasoning"
    case .reasoningFile:
        return "user message part type: reasoning-file"
    case .custom:
        return "user message part type: custom"
    case .imageURL:
        return "user message part type: image"
    case .text:
        return "user message part type: text"
    }
}
