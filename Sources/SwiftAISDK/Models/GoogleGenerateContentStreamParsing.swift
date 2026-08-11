import Foundation

func googleStreamParts(from raw: JSONValue) -> [LanguageStreamPart] {
    var parts: [LanguageStreamPart] = []
    let contentParts = raw["candidates"]?[0]?["content"]?["parts"]?.arrayValue ?? []
    for contentPart in contentParts {
        guard let text = contentPart["text"]?.stringValue else { continue }
        if contentPart["thought"]?.boolValue == true {
            parts.append(.reasoningDelta(text))
        } else {
            parts.append(.textDelta(text))
        }
    }
    if raw["candidates"]?[0]?["finishReason"]?.stringValue != nil || raw["usageMetadata"] != nil {
        parts.append(.finish(
            reason: raw["candidates"]?[0]?["finishReason"]?.stringValue,
            usage: TokenUsage(
                inputTokens: raw["usageMetadata"]?["promptTokenCount"]?.intValue,
                outputTokens: raw["usageMetadata"]?["candidatesTokenCount"]?.intValue,
                totalTokens: raw["usageMetadata"]?["totalTokenCount"]?.intValue
            )
        ))
    }
    return parts
}

struct GoogleGenerateContentStreamState {
    private var responseMetadata: AIResponseMetadata
    private let includeRawChunks: Bool
    private let warnings: [AIWarning]
    private var toolCalls = GoogleGenerateContentStreamingToolCalls()
    private var lastCodeExecutionToolCallID: String?
    private var lastServerToolCallID: String?
    private var latestFinishReason: String?
    private var latestUsage: TokenUsage?
    private var latestProviderMetadata: [String: JSONValue] = [:]
    private var emittedSourceKeys: Set<String> = []
    private var sawToolCalls = false
    private var hasResponseID = false
    private var emittedInitialParts = false

    init(response: AIHTTPResponse, includeRawChunks: Bool, modelID: String?, warnings: [AIWarning]) {
        self.responseMetadata = aiResponseMetadata(response: response, modelID: modelID)
        self.includeRawChunks = includeRawChunks
        self.warnings = warnings
    }

    mutating func apply(_ raw: JSONValue) -> [LanguageStreamPart] {
        var parts: [LanguageStreamPart] = []
        if !hasResponseID, let responseID = raw["responseId"]?.stringValue {
            hasResponseID = true
            responseMetadata.id = responseID
        }
        if !emittedInitialParts {
            emittedInitialParts = true
            parts.append(.responseMetadata(responseMetadata))
            parts.append(.streamStart(warnings: warnings))
        }
        if includeRawChunks {
            parts.append(.raw(raw))
        }
        latestUsage = googleGenerateContentUsage(from: raw) ?? latestUsage
        latestProviderMetadata = googleMergeProviderMetadata(
            latestProviderMetadata,
            googleGenerateContentProviderMetadata(from: raw, includeNullDefaults: false)
        )

        for source in googleGenerateContentSources(from: raw) {
            let key = googleSourceDeduplicationKey(source)
            guard !emittedSourceKeys.contains(key) else { continue }
            emittedSourceKeys.insert(key)
            parts.append(.source(source))
        }

        let contentParts = raw["candidates"]?[0]?["content"]?["parts"]?.arrayValue ?? []
        for (index, contentPart) in contentParts.enumerated() {
            if let executableCode = contentPart["executableCode"],
               executableCode["code"]?.stringValue != nil {
                let id = "google-code-execution-\(index)"
                lastCodeExecutionToolCallID = id
                sawToolCalls = true
                parts.append(.toolInputStart(id: id, name: "code_execution", providerExecuted: true))
                let input = googleGenerateContentArguments(executableCode)
                parts.append(.toolInputDelta(id: id, delta: input))
                parts.append(.toolInputEnd(id: id))
                parts.append(.toolCall(AIToolCall(
                    id: id,
                    name: "code_execution",
                    arguments: input,
                    providerExecuted: true,
                    rawValue: contentPart
                )))
                continue
            }
            if let codeExecutionResult = contentPart["codeExecutionResult"] {
                let id = lastCodeExecutionToolCallID ?? "google-code-execution-result-\(index)"
                parts.append(.toolResult(AIToolResult(
                    toolCallID: id,
                    toolName: "code_execution",
                    result: googleCodeExecutionResultJSON(codeExecutionResult)
                )))
                continue
            }
            if let text = contentPart["text"]?.stringValue {
                if contentPart["thought"]?.boolValue == true {
                    parts.append(.reasoningDelta(text))
                } else if !text.isEmpty {
                    parts.append(.textDelta(text))
                }
            }
            if let inlineData = contentPart["inlineData"],
               let mediaType = inlineData["mimeType"]?.stringValue,
               let base64 = inlineData["data"]?.stringValue {
                let file = AIStreamFile(
                    mediaType: mediaType,
                    data: Data(base64Encoded: base64),
                    providerMetadata: googleInlineDataProviderMetadata(from: contentPart),
                    rawValue: contentPart
                )
                if contentPart["thought"]?.boolValue == true {
                    parts.append(.reasoningFile(file))
                } else {
                    parts.append(.file(file))
                }
            }
            if let functionCall = contentPart["functionCall"] {
                sawToolCalls = true
                parts.append(contentsOf: toolCalls.apply(functionCall: functionCall, rawValue: contentPart))
            }
            if let serverToolCall = contentPart["toolCall"],
               let toolType = serverToolCall["toolType"]?.stringValue {
                let id = serverToolCall["id"]?.stringValue ?? "google-server-tool-\(index)"
                lastServerToolCallID = id
                sawToolCalls = true
                let name = "server:\(toolType)"
                let input = googleGenerateContentArguments(serverToolCall["args"])
                let metadata = googleServerToolProviderMetadata(id: id, type: toolType, part: contentPart)
                parts.append(.toolInputStart(id: id, name: name, providerExecuted: true, dynamic: true, providerMetadata: metadata))
                parts.append(.toolInputDelta(id: id, delta: input, providerMetadata: metadata))
                parts.append(.toolInputEnd(id: id, providerMetadata: metadata))
                parts.append(.toolCall(AIToolCall(
                    id: id,
                    name: name,
                    arguments: input,
                    providerExecuted: true,
                    dynamic: true,
                    providerMetadata: metadata,
                    rawValue: contentPart
                )))
            }
            if let serverToolResponse = contentPart["toolResponse"],
               let toolType = serverToolResponse["toolType"]?.stringValue {
                let id = lastServerToolCallID ?? serverToolResponse["id"]?.stringValue ?? "google-server-tool-response-\(index)"
                let metadata = googleServerToolProviderMetadata(id: id, type: toolType, part: contentPart)
                parts.append(.toolResult(AIToolResult(
                    toolCallID: id,
                    toolName: "server:\(toolType)",
                    result: serverToolResponse["response"] ?? .object([:]),
                    dynamic: true,
                    providerMetadata: metadata
                )))
                lastServerToolCallID = nil
            }
        }

        if let reason = raw["candidates"]?[0]?["finishReason"]?.stringValue {
            latestFinishReason = reason
        }
        return parts
    }

    mutating func finish() -> [LanguageStreamPart] {
        var parts: [LanguageStreamPart] = []
        if !emittedInitialParts {
            emittedInitialParts = true
            parts.append(.responseMetadata(responseMetadata))
            parts.append(.streamStart(warnings: warnings))
        }
        parts.append(contentsOf: toolCalls.finishedParts())
        if latestFinishReason != nil || latestUsage != nil {
            let finishReason = googleGenerateContentFinishReason(latestFinishReason, hasToolCalls: sawToolCalls || !parts.isEmpty)
            let providerMetadata = googleFinalizeGenerateContentProviderMetadata(latestProviderMetadata)
            parts.append(.finish(reason: finishReason, usage: latestUsage))
            parts.append(.finishMetadata(reason: finishReason, usage: latestUsage, providerMetadata: providerMetadata))
        }
        return parts
    }
}
