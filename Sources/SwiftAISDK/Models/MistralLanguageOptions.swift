import Foundation

func mistralResolvedResponseFormat(request: LanguageModelRequest, options: inout [String: JSONValue]) -> JSONValue? {
    if let responseFormat = request.responseFormat {
        options.removeValue(forKey: "responseFormat")
        return mistralResponseFormatJSON(responseFormat)
    }
    return options.removeValue(forKey: "responseFormat")
}

func mistralResponseFormatJSON(_ responseFormat: AIResponseFormat) -> JSONValue? {
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

func mistralWarnings(for request: LanguageModelRequest, modelID: String) -> [AIWarning] {
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
    if isCustomReasoning(request.reasoning), !mistralSupportsReasoningEffort(modelID) {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "reasoning",
            message: "This model does not support reasoning configuration."
        ))
    }
    return warnings
}

func mistralSupportsReasoningEffort(_ modelID: String) -> Bool {
    switch modelID {
    case "mistral-small-latest", "mistral-small-2603", "mistral-medium-3", "mistral-medium-3.5":
        return true
    default:
        return false
    }
}

func mistralReasoningEffort(_ reasoning: String?, warnings: inout [AIWarning]) -> JSONValue? {
    guard isCustomReasoning(reasoning), let reasoning else { return nil }
    if reasoning == "none" {
        return .string("none")
    }
    return mapReasoningToProviderEffort(
        reasoning: reasoning,
        effortMap: [
            "minimal": "high",
            "low": "high",
            "medium": "high",
            "high": "high",
            "xhigh": "high"
        ],
        warnings: &warnings
    ).map(JSONValue.string)
}

func mistralMessages(_ messages: [AIMessage], responseFormat: JSONValue?) -> [AIMessage] {
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

func mistralResponseFormat(from value: JSONValue, options: [String: JSONValue]) -> JSONValue {
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

func mistralProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "mistral")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

func mistralProviderOptions(from request: LanguageModelRequest) throws -> [String: JSONValue] {
    var output = mistralProviderOptions(from: request.extraBody)
    if let value = request.providerOptions["mistral"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.mistral", message: "Mistral provider options must be an object.")
        }
        for key in mistralLanguageProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try mistralValidateLanguageProviderOptions(nested)) { _, nested in nested }
    }
    return output
}

let mistralLanguageProviderOptionKeys: Set<String> = [
    "safePrompt",
    "documentImageLimit",
    "documentPageLimit",
    "structuredOutputs",
    "strictJsonSchema",
    "parallelToolCalls",
    "reasoningEffort"
]

func mistralValidateLanguageProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where mistralLanguageProviderOptionKeys.contains(key) {
        guard value != .null else {
            throw AIError.invalidArgument(argument: "providerOptions.mistral.\(key)", message: "Mistral \(key) cannot be null.")
        }
        switch key {
        case "safePrompt", "structuredOutputs", "strictJsonSchema", "parallelToolCalls":
            try mistralRequireBoolean(value, argument: "providerOptions.mistral.\(key)", message: "Mistral \(key) must be a boolean.")
            output[key] = value
        case "documentImageLimit", "documentPageLimit":
            try mistralRequireNumber(value, argument: "providerOptions.mistral.\(key)", message: "Mistral \(key) must be a number.")
            output[key] = value
        case "reasoningEffort":
            guard let string = value.stringValue, ["high", "none"].contains(string) else {
                throw AIError.invalidArgument(argument: "providerOptions.mistral.reasoningEffort", message: "Mistral reasoningEffort must be high or none.")
            }
            output[key] = value
        default:
            break
        }
    }
    return output
}

func mistralRequireBoolean(_ value: JSONValue, argument: String, message: String) throws {
    guard value.boolValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

func mistralRequireNumber(_ value: JSONValue, argument: String, message: String) throws {
    guard value.doubleValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}
