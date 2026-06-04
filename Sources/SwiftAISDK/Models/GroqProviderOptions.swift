import Foundation

func groqTranscriptionOptions(from request: AudioTranscriptionRequest) throws -> [String: JSONValue] {
    var output = groqProviderOptions(from: request.extraBody)
    if let value = request.providerOptions["groq"] {
        guard value != .null else {
            moveKey("responseFormat", to: "response_format", in: &output)
            moveKey("timestampGranularities", to: "timestamp_granularities", in: &output)
            return output
        }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.groq", message: "Groq provider options must be an object.")
        }
        for key in groqTranscriptionProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try groqValidateTranscriptionProviderOptions(nested)) { _, providerValue in providerValue }
    }
    moveKey("responseFormat", to: "response_format", in: &output)
    moveKey("timestampGranularities", to: "timestamp_granularities", in: &output)
    return output
}

func groqProviderOptions(from request: LanguageModelRequest) throws -> [String: JSONValue] {
    var output = groqProviderOptions(from: request.extraBody)
    if let value = request.providerOptions["groq"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.groq", message: "Groq provider options must be an object.")
        }
        for key in groqChatProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try groqValidateChatProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

func groqProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "groq")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

func moveKey(_ source: String, to destination: String, in values: inout [String: JSONValue]) {
    if let value = values.removeValue(forKey: source) {
        values[destination] = value
    }
}

let groqChatProviderOptionKeys: Set<String> = [
    "reasoningFormat",
    "reasoningEffort",
    "parallelToolCalls",
    "user",
    "structuredOutputs",
    "strictJsonSchema",
    "serviceTier"
]

let groqTranscriptionProviderOptionKeys: Set<String> = [
    "language",
    "prompt",
    "responseFormat",
    "temperature",
    "timestampGranularities"
]

func groqUsage(from usage: JSONValue?) -> TokenUsage? {
    guard let usage, usage != .null else { return nil }
    let promptTokens = usage["prompt_tokens"]?.intValue ?? 0
    let completionTokens = usage["completion_tokens"]?.intValue ?? 0
    let reasoningTokens = usage["completion_tokens_details"]?["reasoning_tokens"]?.intValue
    return TokenUsage(
        inputTokens: promptTokens,
        outputTokens: completionTokens,
        totalTokens: usage["total_tokens"]?.intValue ?? promptTokens + completionTokens,
        inputTokensNoCache: promptTokens,
        outputTextTokens: reasoningTokens.map { completionTokens - $0 } ?? completionTokens,
        outputReasoningTokens: reasoningTokens,
        rawValue: usage
    )
}

func groqValidateChatProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where groqChatProviderOptionKeys.contains(key) {
        guard value != .null else {
            throw AIError.invalidArgument(argument: "providerOptions.groq.\(key)", message: "Groq \(key) cannot be null.")
        }
        switch key {
        case "reasoningFormat":
            guard let string = value.stringValue, ["parsed", "raw", "hidden"].contains(string) else {
                throw AIError.invalidArgument(argument: "providerOptions.groq.reasoningFormat", message: "Groq reasoningFormat must be parsed, raw, or hidden.")
            }
            output[key] = value
        case "reasoningEffort":
            guard let string = value.stringValue, ["none", "default", "low", "medium", "high"].contains(string) else {
                throw AIError.invalidArgument(argument: "providerOptions.groq.reasoningEffort", message: "Groq reasoningEffort must be none, default, low, medium, or high.")
            }
            output[key] = value
        case "parallelToolCalls", "structuredOutputs", "strictJsonSchema":
            try groqRequireBoolean(value, argument: "providerOptions.groq.\(key)", message: "Groq \(key) must be a boolean.")
            output[key] = value
        case "user":
            try groqRequireString(value, argument: "providerOptions.groq.user", message: "Groq user must be a string.")
            output[key] = value
        case "serviceTier":
            guard let string = value.stringValue, ["on_demand", "performance", "flex", "auto"].contains(string) else {
                throw AIError.invalidArgument(argument: "providerOptions.groq.serviceTier", message: "Groq serviceTier must be on_demand, performance, flex, or auto.")
            }
            output[key] = value
        default:
            break
        }
    }
    return output
}

func groqValidateTranscriptionProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where groqTranscriptionProviderOptionKeys.contains(key) {
        guard value != .null else { continue }
        switch key {
        case "language", "prompt", "responseFormat":
            try groqRequireString(value, argument: "providerOptions.groq.\(key)", message: "Groq \(key) must be a string.")
            output[key] = value
        case "temperature":
            guard let number = value.doubleValue, number >= 0, number <= 1 else {
                throw AIError.invalidArgument(argument: "providerOptions.groq.temperature", message: "Groq temperature must be a number between 0 and 1.")
            }
            output[key] = value
        case "timestampGranularities":
            output[key] = try groqStringArray(value, argument: "providerOptions.groq.timestampGranularities")
        default:
            break
        }
    }
    return output
}

func groqStringArray(_ value: JSONValue, argument: String) throws -> JSONValue {
    guard let array = value.arrayValue else {
        throw AIError.invalidArgument(argument: argument, message: "Groq \(argument) must be an array of strings.")
    }
    for item in array where item.stringValue == nil {
        throw AIError.invalidArgument(argument: argument, message: "Groq \(argument) values must be strings.")
    }
    return value
}

func groqRequireString(_ value: JSONValue, argument: String, message: String) throws {
    guard value.stringValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

func groqRequireBoolean(_ value: JSONValue, argument: String, message: String) throws {
    guard value.boolValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}
