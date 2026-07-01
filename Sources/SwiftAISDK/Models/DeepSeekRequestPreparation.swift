import Foundation

func deepSeekPreparedCall(for request: LanguageModelRequest, modelID: String, stream: Bool, supportsThinking: Bool = true) throws -> DeepSeekPreparedCall {
    var options = try deepSeekOptions(from: request)
    let responseFormat = deepSeekResolvedResponseFormat(request: request, options: &options)
    let optionToolChoice = options.removeValue(forKey: "toolChoice")
    let toolChoice = request.toolChoice ?? optionToolChoice
    let preparedMessages = deepSeekMessages(request.messages, responseFormat: responseFormat, modelID: modelID)
    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "messages": .array(preparedMessages.messages)
    ]
    if stream {
        body["stream"] = true
        body["stream_options"] = .object(["include_usage": true])
    }
    if let temperature = request.temperature { body["temperature"] = .number(temperature) }
    if let topP = request.topP { body["top_p"] = .number(topP) }
    if let frequencyPenalty = request.frequencyPenalty { body["frequency_penalty"] = .number(frequencyPenalty) }
    if let presencePenalty = request.presencePenalty { body["presence_penalty"] = .number(presencePenalty) }
    if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
    if !request.stopSequences.isEmpty { body["stop"] = .array(request.stopSequences) }
    let preparedTools = deepSeekTools(from: request.tools)
    if !preparedTools.tools.isEmpty {
        body["tools"] = .array(preparedTools.tools)
        if let toolChoice = deepSeekToolChoice(from: toolChoice) {
            body["tool_choice"] = toolChoice
        }
    }
    body.merge(options) { _, new in new }
    let reasoningWarnings = supportsThinking ? deepSeekApplyReasoning(request.reasoning, to: &body) : []
    if !supportsThinking {
        body.removeValue(forKey: "thinking")
    }
    if let responseFormat, responseFormat["type"]?.stringValue == "json" {
        body["response_format"] = .object(["type": .string("json_object")])
    }

    if body["thinking"]?["type"]?.stringValue == "disabled" {
        body.removeValue(forKey: "reasoning_effort")
    }
    return DeepSeekPreparedCall(
        body: body,
        warnings: preparedMessages.warnings
            + deepSeekWarnings(request: request, responseFormat: responseFormat)
            + reasoningWarnings
            + preparedTools.warnings
            + (request.tools.isEmpty ? [] : deepSeekToolChoiceWarnings(from: toolChoice))
    )
}

func deepSeekMessages(_ messages: [AIMessage], responseFormat: JSONValue?, modelID: String) -> DeepSeekPreparedMessages {
    var output: [JSONValue] = []
    var warnings: [AIWarning] = []
    let isDeepSeekV4 = modelID.contains("deepseek-v4")
    let lastUserMessageIndex = messages.lastIndex { $0.role == .user } ?? -1

    if responseFormat?["type"]?.stringValue == "json" {
        if let schema = responseFormat?["schema"] {
            let schemaText = deepSeekJSONString(schema) ?? schema.stringValue ?? ""
            output.append(.object([
                "role": .string("system"),
                "content": .string("Return JSON that conforms to the following schema: \(schemaText)")
            ]))
        } else {
            output.append(.object([
                "role": .string("system"),
                "content": .string("Return JSON.")
            ]))
        }
    }

    for (index, message) in messages.enumerated() {
        switch message.role {
        case .system:
            output.append(.object([
                "role": .string("system"),
                "content": .string(message.combinedText)
            ]))
        case .user:
            var text = ""
            for part in message.content {
                if case let .text(value, _) = part {
                    text += value
                } else {
                    warnings.append(AIWarning(type: "unsupported", feature: deepSeekUserPartFeature(part)))
                }
            }
            output.append(.object([
                "role": .string("user"),
                "content": .string(text)
            ]))
        case .assistant:
            let toolCalls = message.content.compactMap { part -> AIToolCall? in
                if case let .toolCall(call) = part { call } else { nil }
            }
            let reasoning = (index <= lastUserMessageIndex && !isDeepSeekV4) ? nil : message.reasoning
            var object: [String: JSONValue] = [
                "role": .string("assistant"),
                "content": .string(deepSeekText(from: message))
            ]
            if isDeepSeekV4 {
                object["reasoning_content"] = .string(reasoning ?? "")
            } else if let reasoning {
                object["reasoning_content"] = .string(reasoning)
            }
            if !toolCalls.isEmpty {
                object["tool_calls"] = .array(toolCalls.map { call in
                    .object([
                        "id": .string(call.id),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string(call.name),
                            "arguments": .string(call.arguments)
                        ])
                    ])
                })
            }
            output.append(.object(object))
        case .tool:
            for part in message.content {
                guard case let .toolResult(result) = part else { continue }
                output.append(.object([
                    "role": .string("tool"),
                    "tool_call_id": .string(result.toolCallID),
                    "content": .string(deepSeekToolResultContent(result))
                ]))
            }
        }
    }

    return DeepSeekPreparedMessages(messages: output, warnings: warnings)
}

func deepSeekUserPartFeature(_ part: AIContentPart) -> String {
    switch part {
    case .data, .file, .providerReference, .imageURL:
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
    case .text:
        return "user message part type: text"
    }
}

func deepSeekText(from message: AIMessage) -> String {
    message.content.compactMap(\.text).joined()
}
