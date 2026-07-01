import Foundation

func moonshotChatBody(from input: [String: JSONValue], request: LanguageModelRequest) throws -> [String: JSONValue] {
    var body = input
    if let nested = body.removeValue(forKey: "moonshotai")?.objectValue {
        body.merge(nested) { _, nested in nested }
    }
    if let nested = body.removeValue(forKey: "moonshotAI")?.objectValue {
        body.merge(nested) { _, nested in nested }
    }

    let providerOptions = try moonshotProviderOptions(from: request.providerOptions)
    body.merge(providerOptions) { _, providerValue in providerValue }

    if let thinking = body.removeValue(forKey: "thinking")?.objectValue {
        var converted: [String: JSONValue] = [:]
        if let type = thinking["type"] { converted["type"] = type }
        if let budgetTokens = thinking["budgetTokens"] {
            converted["budget_tokens"] = budgetTokens
        } else if let budgetTokens = thinking["budget_tokens"] {
            converted["budget_tokens"] = budgetTokens
        }
        body["thinking"] = .object(converted)
    }

    if let reasoningHistory = body.removeValue(forKey: "reasoningHistory") {
        body["reasoning_history"] = reasoningHistory
    }

    moonshotStripTopLevelDollarSchema(from: &body)

    return body
}

func moonshotSupportsStructuredOutputs(modelID: String) -> Bool {
    modelID.hasPrefix("kimi-k")
}

func moonshotProviderOptions(from providerOptions: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    if let value = providerOptions["moonshotai"] {
        if value != .null {
            guard let nested = value.objectValue else {
                throw AIError.invalidArgument(argument: "providerOptions.moonshotai", message: "MoonshotAI provider options must be an object.")
            }
            output.merge(try moonshotValidateLanguageProviderOptions(nested, argumentPrefix: "providerOptions.moonshotai")) { _, providerValue in providerValue }
        }
    }
    if let value = providerOptions["moonshotAI"] {
        if value != .null {
            guard let nested = value.objectValue else {
                throw AIError.invalidArgument(argument: "providerOptions.moonshotAI", message: "MoonshotAI provider options must be an object.")
            }
            output.merge(try moonshotValidateLanguageProviderOptions(nested, argumentPrefix: "providerOptions.moonshotAI")) { _, providerValue in providerValue }
        }
    }
    return output
}

func moonshotValidateLanguageProviderOptions(_ options: [String: JSONValue], argumentPrefix: String) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    if let thinking = options["thinking"] {
        guard let thinkingObject = thinking.objectValue else {
            throw AIError.invalidArgument(argument: "\(argumentPrefix).thinking", message: "MoonshotAI thinking must be an object.")
        }
        var mappedThinking: [String: JSONValue] = [:]
        if let type = thinkingObject["type"] {
            guard let typeValue = type.stringValue, typeValue == "enabled" || typeValue == "disabled" else {
                throw AIError.invalidArgument(argument: "\(argumentPrefix).thinking.type", message: "MoonshotAI thinking.type must be enabled or disabled.")
            }
            mappedThinking["type"] = .string(typeValue)
        }
        if let budgetTokens = thinkingObject["budgetTokens"] {
            guard let number = budgetTokens.doubleValue, moonshotIsInteger(number), number >= 1024 else {
                throw AIError.invalidArgument(argument: "\(argumentPrefix).thinking.budgetTokens", message: "MoonshotAI thinking.budgetTokens must be an integer greater than or equal to 1024.")
            }
            mappedThinking["budgetTokens"] = .number(number)
        }
        output["thinking"] = .object(mappedThinking)
    }
    if let reasoningHistory = options["reasoningHistory"] {
        guard let value = reasoningHistory.stringValue,
              value == "disabled" || value == "interleaved" || value == "preserved" else {
            throw AIError.invalidArgument(argument: "\(argumentPrefix).reasoningHistory", message: "MoonshotAI reasoningHistory must be disabled, interleaved, or preserved.")
        }
        output["reasoningHistory"] = .string(value)
    }
    return output
}

func moonshotIsInteger(_ value: Double) -> Bool {
    value.rounded(.towardZero) == value
}

private func moonshotStripTopLevelDollarSchema(from body: inout [String: JSONValue]) {
    guard var responseFormat = body["response_format"]?.objectValue,
          var jsonSchema = responseFormat["json_schema"]?.objectValue,
          var schema = jsonSchema["schema"]?.objectValue else {
        return
    }
    schema.removeValue(forKey: "$schema")
    jsonSchema["schema"] = .object(schema)
    responseFormat["json_schema"] = .object(jsonSchema)
    body["response_format"] = .object(responseFormat)
}

func moonshotChatUsage(from raw: JSONValue) -> TokenUsage? {
    guard let usage = raw["usage"] else { return TokenUsage() }
    let inputTokens = usage["prompt_tokens"]?.intValue ?? usage["input_tokens"]?.intValue ?? 0
    let outputTokens = usage["completion_tokens"]?.intValue ?? usage["output_tokens"]?.intValue ?? 0
    let cacheReadTokens = usage["cached_tokens"]?.intValue
        ?? usage["prompt_tokens_details"]?["cached_tokens"]?.intValue
        ?? 0
    let reasoningTokens = usage["completion_tokens_details"]?["reasoning_tokens"]?.intValue ?? 0
    let totalTokens = usage["total_tokens"]?.intValue ?? {
        return inputTokens + outputTokens
    }()
    return TokenUsage(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: totalTokens,
        inputTokensNoCache: inputTokens - cacheReadTokens,
        inputTokensCacheRead: cacheReadTokens,
        outputTextTokens: outputTokens - reasoningTokens,
        outputReasoningTokens: reasoningTokens,
        rawValue: usage
    )
}
