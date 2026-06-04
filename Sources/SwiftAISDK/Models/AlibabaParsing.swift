import Foundation

func alibabaWarnings(for request: LanguageModelRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.frequencyPenalty != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "frequencyPenalty"))
    }
    return warnings
}

func alibabaMoveKey(_ source: String, to destination: String, in values: inout [String: JSONValue]) {
    if let value = values.removeValue(forKey: source) {
        values[destination] = value
    }
}

func alibabaToolCalls(from value: JSONValue?) -> [AIToolCall] {
    value?.arrayValue?.enumerated().compactMap { index, item in
        guard let name = item["function"]?["name"]?.stringValue else { return nil }
        return AIToolCall(
            id: item["id"]?.stringValue ?? "tool-call-\(index)",
            name: name,
            arguments: item["function"]?["arguments"]?.stringValue ?? "",
            rawValue: item
        )
    } ?? []
}

func alibabaUsage(from raw: JSONValue) -> TokenUsage? {
    guard let usage = raw["usage"] else { return nil }
    let inputTokens = usage["prompt_tokens"]?.intValue ?? usage["input_tokens"]?.intValue ?? 0
    let outputTokens = usage["completion_tokens"]?.intValue ?? usage["output_tokens"]?.intValue ?? 0
    let cacheReadTokens = usage["prompt_tokens_details"]?["cached_tokens"]?.intValue ?? 0
    let cacheWriteTokens = usage["prompt_tokens_details"]?["cache_creation_input_tokens"]?.intValue ?? 0
    let reasoningTokens = usage["completion_tokens_details"]?["reasoning_tokens"]?.intValue ?? 0
    let totalTokens = usage["total_tokens"]?.intValue ?? inputTokens + outputTokens
    return TokenUsage(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: totalTokens,
        inputTokensNoCache: max(0, inputTokens - cacheReadTokens - cacheWriteTokens),
        inputTokensCacheRead: cacheReadTokens,
        inputTokensCacheWrite: cacheWriteTokens,
        outputTextTokens: outputTokens - reasoningTokens,
        outputReasoningTokens: reasoningTokens,
        rawValue: usage
    )
}

func alibabaResponseMetadata(from raw: JSONValue? = nil, response: AIHTTPResponse, modelID: String) -> AIResponseMetadata {
    AIResponseMetadata(
        id: raw?["id"]?.stringValue,
        timestamp: raw?["created"]?.doubleValue.map { Date(timeIntervalSince1970: $0) } ?? Date(),
        modelID: raw?["model"]?.stringValue ?? modelID,
        headers: response.headers,
        body: raw
    )
}

func alibabaJSONString(_ value: JSONValue) -> String? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

func alibabaFinishReason(_ reason: String?) -> String? {
    switch reason {
    case "stop":
        return "stop"
    case "length":
        return "length"
    case "content_filter":
        return "content-filter"
    case "function_call", "tool_calls":
        return "tool-calls"
    case nil:
        return nil
    default:
        return "other"
    }
}
