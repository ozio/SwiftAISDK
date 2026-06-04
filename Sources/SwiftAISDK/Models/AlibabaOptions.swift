import Foundation

func alibabaOptions(from request: LanguageModelRequest) throws -> [String: JSONValue] {
    var output = alibabaOptions(from: request.extraBody)
    if let value = request.providerOptions["alibaba"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.alibaba", message: "Alibaba provider options must be an object.")
        }
        output.merge(try alibabaValidateLanguageProviderOptions(nested)) { _, nested in nested }
    }
    alibabaNormalizeOptions(&output)
    return output
}

func alibabaHTTPStatusError(provider: String, response: AIHTTPResponse) -> AIError {
    let body = alibabaErrorMessage(from: response.body) ?? response.bodyText
    guard !response.headers.isEmpty else {
        return .apiCall(provider: provider, statusCode: response.statusCode, body: body)
    }
    return .apiCall(
        provider: provider,
        statusCode: response.statusCode,
        body: body,
        headers: response.headers
    )
}

func alibabaErrorMessage(from data: Data) -> String? {
    guard let json = try? decodeJSONBody(data) else { return nil }
    return json["error"]?["message"]?.stringValue ?? json["message"]?.stringValue
}

func alibabaStreamError(from raw: JSONValue) -> (message: String, rawValue: JSONValue)? {
    if let error = raw["error"] {
        return (
            error["message"]?.stringValue ?? alibabaJSONString(error) ?? "Alibaba stream error.",
            error
        )
    }
    if let message = raw["message"]?.stringValue,
       raw["code"] != nil || raw["type"] != nil || raw["request_id"] != nil {
        return (message, raw)
    }
    return nil
}

func alibabaOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "alibaba")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    alibabaNormalizeOptions(&output)
    return output
}

func alibabaNormalizeOptions(_ output: inout [String: JSONValue]) {
    alibabaMoveKey("topK", to: "top_k", in: &output)
    alibabaMoveKey("presencePenalty", to: "presence_penalty", in: &output)
    alibabaMoveKey("enableThinking", to: "enable_thinking", in: &output)
    alibabaMoveKey("thinkingBudget", to: "thinking_budget", in: &output)
    alibabaMoveKey("parallelToolCalls", to: "parallel_tool_calls", in: &output)
}

func alibabaValidateLanguageProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options {
        switch key {
        case "enableThinking":
            guard let bool = value.boolValue else {
                throw AIError.invalidArgument(argument: "providerOptions.alibaba.enableThinking", message: "Alibaba enableThinking must be a boolean.")
            }
            output[key] = .bool(bool)
        case "thinkingBudget":
            guard let number = value.doubleValue, number > 0 else {
                throw AIError.invalidArgument(argument: "providerOptions.alibaba.thinkingBudget", message: "Alibaba thinkingBudget must be a positive number.")
            }
            output[key] = .number(number)
        case "parallelToolCalls":
            guard let bool = value.boolValue else {
                throw AIError.invalidArgument(argument: "providerOptions.alibaba.parallelToolCalls", message: "Alibaba parallelToolCalls must be a boolean.")
            }
            output[key] = .bool(bool)
        default:
            break
        }
    }
    return output
}

func alibabaResolvedResponseFormat(request: LanguageModelRequest, options: inout [String: JSONValue]) -> JSONValue? {
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

func alibabaResponseFormatJSON(_ responseFormat: AIResponseFormat) -> JSONValue? {
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

func alibabaResponseFormat(from value: JSONValue) -> JSONValue {
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

func alibabaApplyThinking(
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

func alibabaReasoningBudget(_ reasoning: String) -> Int? {
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
