import Foundation

func alibabaTools(from tools: [String: JSONValue]) -> AlibabaPreparedTools {
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

func alibabaToolChoice(from value: JSONValue?) -> JSONValue? {
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

func alibabaToolChoiceWarnings(from value: JSONValue?) -> [AIWarning] {
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

func alibabaAssistantToolCallJSON(_ part: AIContentPart) -> JSONValue? {
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

func alibabaToolMessageJSON(_ part: AIContentPart) -> JSONValue? {
    guard case let .toolResult(result) = part else { return nil }
    return .object([
        "role": .string("tool"),
        "tool_call_id": .string(result.toolCallID),
        "content": .string(alibabaToolResultContent(result))
    ])
}

func alibabaToolResultContent(_ result: AIToolResult) -> String {
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
