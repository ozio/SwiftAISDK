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

func alibabaMessages(_ messages: [AIMessage]) -> AlibabaPreparedMessages {
    var output: [JSONValue] = []
    var warnings: [AIWarning] = []
    for message in messages {
        let prepared = alibabaMessageJSONs(message)
        output += prepared.messages
        warnings += prepared.warnings
    }
    return AlibabaPreparedMessages(messages: output, warnings: warnings)
}

struct AlibabaPreparedMessageParts {
    var parts: [JSONValue]
    var warnings: [AIWarning]
}

func alibabaMessageJSONs(_ message: AIMessage) -> AlibabaPreparedMessages {
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

func alibabaUserContentParts(_ content: [AIContentPart]) -> AlibabaPreparedMessageParts {
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
        case .providerReference, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
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
    case .imageURL:
        return "user message part type: image"
    case .text:
        return "user message part type: text"
    }
}
