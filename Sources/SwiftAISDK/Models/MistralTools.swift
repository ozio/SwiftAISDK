import Foundation

func mistralTools(from tools: [String: JSONValue], only forcedName: String?) -> MistralPreparedTools {
    var warnings: [AIWarning] = []
    let values: [JSONValue] = tools.compactMap { name, schema in
        let object = schema.objectValue
        if object?["type"]?.stringValue == "provider" || object?["id"]?.stringValue != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "provider-defined tool \(object?["id"]?.stringValue ?? name)"
            ))
            return nil
        }
        if let forcedName, forcedName != name { return nil }
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
    return MistralPreparedTools(tools: values, warnings: warnings)
}

func mistralToolChoice(from value: JSONValue?) -> JSONValue? {
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

func mistralForcedToolName(from value: JSONValue?) -> String? {
    guard let object = value?.objectValue,
          object["type"]?.stringValue == "tool" else {
        return nil
    }
    return object["toolName"]?.stringValue ?? object["tool_name"]?.stringValue
}
