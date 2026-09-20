import Foundation

func googleGenerateContentText(from raw: JSONValue) -> String? {
    let text = raw["candidates"]?[0]?["content"]?["parts"]?.arrayValue?.compactMap { part in
        part["text"]?.stringValue
    }.joined()
    return text
}

func googleGenerateContentToolCalls(
    from raw: JSONValue,
    toolNameMapping: AIToolNameMapping = AIToolNameMapping()
) -> [AIToolCall] {
    var calls: [AIToolCall] = []
    let parts = raw["candidates"]?[0]?["content"]?["parts"]?.arrayValue ?? []
    for (index, part) in parts.enumerated() {
        if let executableCode = part["executableCode"],
           executableCode["code"]?.stringValue != nil {
            calls.append(AIToolCall(
                id: "google-code-execution-\(index)",
                name: toolNameMapping.toCustomToolName("code_execution"),
                arguments: googleGenerateContentArguments(executableCode),
                providerExecuted: true,
                rawValue: part
            ))
            continue
        }
        if let functionCall = part["functionCall"],
           let name = functionCall["name"]?.stringValue {
            calls.append(AIToolCall(
                id: resolvedToolCallID(functionCall["id"]?.stringValue, whenMissing: "tool-call-\(index)"),
                name: name,
                arguments: googleGenerateContentArguments(functionCall["args"]),
                providerMetadata: googleThoughtSignatureProviderMetadata(from: part),
                rawValue: part
            ))
            continue
        }
        if let serverToolCall = part["toolCall"],
           let toolType = serverToolCall["toolType"]?.stringValue {
            let id = serverToolCall["id"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
                ?? "google-server-tool-\(index)"
            calls.append(AIToolCall(
                id: id,
                name: "server:\(toolType)",
                arguments: googleGenerateContentArguments(serverToolCall["args"]),
                providerExecuted: true,
                dynamic: true,
                providerMetadata: googleServerToolProviderMetadata(id: id, type: toolType, part: part),
                rawValue: part
            ))
        }
    }
    return calls
}

func googleGenerateContentToolResults(
    from raw: JSONValue,
    toolNameMapping: AIToolNameMapping = AIToolNameMapping()
) -> [AIToolResult] {
    var results: [AIToolResult] = []
    var lastCodeExecutionToolCallID: String?
    var lastServerToolCallID: String?
    let parts = raw["candidates"]?[0]?["content"]?["parts"]?.arrayValue ?? []
    for (index, part) in parts.enumerated() {
        if let executableCode = part["executableCode"],
           executableCode["code"]?.stringValue != nil {
            lastCodeExecutionToolCallID = "google-code-execution-\(index)"
            continue
        }
        if let codeExecutionResult = part["codeExecutionResult"] {
            results.append(AIToolResult(
                toolCallID: lastCodeExecutionToolCallID ?? "google-code-execution-result-\(index)",
                toolName: toolNameMapping.toCustomToolName("code_execution"),
                result: googleCodeExecutionResultJSON(codeExecutionResult)
            ))
            continue
        }
        if let serverToolCall = part["toolCall"],
           serverToolCall["toolType"]?.stringValue != nil {
            lastServerToolCallID = serverToolCall["id"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
                ?? "google-server-tool-\(index)"
            continue
        }
        if let serverToolResponse = part["toolResponse"],
            let toolType = serverToolResponse["toolType"]?.stringValue {
            let id = lastServerToolCallID
                ?? serverToolResponse["id"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
                ?? "google-server-tool-response-\(index)"
            results.append(AIToolResult(
                toolCallID: id,
                toolName: "server:\(toolType)",
                result: serverToolResponse["response"] ?? .object([:]),
                dynamic: true,
                providerMetadata: googleServerToolProviderMetadata(id: id, type: toolType, part: part)
            ))
            lastServerToolCallID = nil
        }
    }
    return results
}

func googleGenerateContentSources(from raw: JSONValue) -> [AISource] {
    let chunks = raw["candidates"]?[0]?["groundingMetadata"]?["groundingChunks"]?.arrayValue ?? []
    return chunks.enumerated().compactMap { index, chunk in
        googleGroundingChunkSource(from: chunk, index: index)
    }
}

func googleGenerateContentProviderMetadata(from raw: JSONValue, includeNullDefaults: Bool = true) -> [String: JSONValue] {
    let candidate = raw["candidates"]?[0]
    var google: [String: JSONValue] = [:]
    if let safetyRatings = candidate?["safetyRatings"] {
        google["safetyRatings"] = safetyRatings
    }
    if let promptFeedback = raw["promptFeedback"] {
        google["promptFeedback"] = promptFeedback
    }
    if let groundingMetadata = candidate?["groundingMetadata"] {
        google["groundingMetadata"] = groundingMetadata
    }
    if let urlContextMetadata = candidate?["urlContextMetadata"] {
        google["urlContextMetadata"] = urlContextMetadata
    }
    if let finishMessage = candidate?["finishMessage"] {
        google["finishMessage"] = finishMessage
    } else if includeNullDefaults {
        google["finishMessage"] = .null
    }
    if let usageMetadata = raw["usageMetadata"] {
        google["usageMetadata"] = usageMetadata
    } else if includeNullDefaults {
        google["usageMetadata"] = .null
    }
    if let serviceTier = raw["usageMetadata"]?["serviceTier"] {
        google["serviceTier"] = serviceTier
    } else if includeNullDefaults {
        google["serviceTier"] = .null
    }
    guard !google.isEmpty else { return [:] }
    return ["google": .object(google)]
}

func googleFinalizeGenerateContentProviderMetadata(_ providerMetadata: [String: JSONValue]) -> [String: JSONValue] {
    var google = providerMetadata["google"]?.objectValue ?? [:]
    google["finishMessage"] = google["finishMessage"] ?? .null
    google["usageMetadata"] = google["usageMetadata"] ?? .null
    google["serviceTier"] = google["serviceTier"] ?? .null
    return ["google": .object(google)]
}

func googleMergeProviderMetadata(_ current: [String: JSONValue], _ incoming: [String: JSONValue]) -> [String: JSONValue] {
    var output = current
    for (provider, value) in incoming {
        if var existing = output[provider]?.objectValue,
           let incomingObject = value.objectValue {
            existing.merge(incomingObject) { _, new in new }
            output[provider] = .object(existing)
        } else {
            output[provider] = value
        }
    }
    return output
}


func googleGenerateContentUsage(from raw: JSONValue) -> TokenUsage? {
    guard let usage = raw["usageMetadata"] else { return nil }
    return googleGenerateContentUsage(fromUsageMetadata: usage)
}

func googleGenerateContentUsage(fromUsageMetadata usage: JSONValue) -> TokenUsage {
    let promptTokens = usage["promptTokenCount"]?.intValue ?? 0
    let toolUsePromptTokens = usage["toolUsePromptTokenCount"]?.intValue ?? 0
    let cachedContentTokens = usage["cachedContentTokenCount"]?.intValue ?? 0
    let candidateTokens = usage["candidatesTokenCount"]?.intValue ?? 0
    let thoughtTokens = usage["thoughtsTokenCount"]?.intValue ?? 0
    let inputTokens = promptTokens + toolUsePromptTokens
    return TokenUsage(
        inputTokens: inputTokens,
        outputTokens: candidateTokens + thoughtTokens,
        totalTokens: usage["totalTokenCount"]?.intValue,
        inputTokensNoCache: inputTokens - cachedContentTokens,
        inputTokensCacheRead: cachedContentTokens,
        outputTextTokens: candidateTokens,
        outputReasoningTokens: thoughtTokens,
        rawValue: usage
    )
}

func googleGenerateContentFinishReason(_ reason: String?, hasToolCalls: Bool) -> String? {
    switch reason {
    case "STOP":
        return hasToolCalls ? "tool-calls" : "stop"
    case "MAX_TOKENS":
        return "length"
    case "IMAGE_SAFETY", "RECITATION", "SAFETY", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII":
        return "content-filter"
    case "MALFORMED_FUNCTION_CALL":
        return "error"
    case nil:
        return nil
    default:
        return "other"
    }
}

func googleConfirmedPromptBlockReason(_ reason: String?) -> String? {
    guard let reason,
          !reason.isEmpty,
          reason != "BLOCK_REASON_UNSPECIFIED",
          reason != "BLOCKED_REASON_UNSPECIFIED" else {
        return nil
    }
    return reason
}

func googleGenerateContentFinishReason(from raw: JSONValue, hasToolCalls: Bool) -> String? {
    let candidateFinishReason = raw["candidates"]?[0]?["finishReason"]?.stringValue
    let promptBlockReason = googleConfirmedPromptBlockReason(raw["promptFeedback"]?["blockReason"]?.stringValue)
    if candidateFinishReason == nil, promptBlockReason != nil {
        return "content-filter"
    }
    return googleGenerateContentFinishReason(candidateFinishReason ?? promptBlockReason, hasToolCalls: hasToolCalls)
}
