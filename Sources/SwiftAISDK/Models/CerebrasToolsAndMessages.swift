import Foundation

func cerebrasTools(from tools: [String: JSONValue]) -> CerebrasPreparedTools {
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
    return CerebrasPreparedTools(tools: values, warnings: warnings)
}

func cerebrasToolChoice(from value: JSONValue?) -> JSONValue? {
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

func cerebrasWarnings(for request: LanguageModelRequest) -> [AIWarning] {
    (request.extraBody["openai-compatible"] == nil && request.providerOptions["openai-compatible"] == nil) ? [] : [
        AIWarning(
            type: "deprecated",
            setting: "providerOptions key 'openai-compatible'",
            message: "Use 'openaiCompatible' instead."
        )
    ]
}

func cerebrasCallWarnings(for request: LanguageModelRequest) -> [AIWarning] {
    request.topK == nil ? [] : [AIWarning(type: "unsupported", feature: "topK")]
}

func cerebrasToolChoiceWarnings(from value: JSONValue?) -> [AIWarning] {
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

func cerebrasMessageTransform(_ message: JSONValue) -> JSONValue {
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

func cerebrasFinishReason(_ raw: String?, hasText: Bool, normalizeStructuredToolCalls: Bool) -> String? {
    if raw == "tool_calls",
       cerebrasShouldDropStructuredToolCalls(
           hasText: hasText,
           normalizeStructuredToolCalls: normalizeStructuredToolCalls
       ) {
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
    default:
        return "other"
    }
}

func cerebrasShouldDropStructuredToolCalls(hasText: Bool, normalizeStructuredToolCalls: Bool) -> Bool {
    hasText && normalizeStructuredToolCalls
}

func cerebrasUsesStandardJSONResponseFormat(_ responseFormat: AIResponseFormat?) -> Bool {
    guard case .json = responseFormat else { return false }
    return true
}
