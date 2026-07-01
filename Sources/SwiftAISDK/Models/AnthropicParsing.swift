import Foundation

func anthropicToolCalls(from value: JSONValue?) -> [AIToolCall] {
    value?.arrayValue?.compactMap(anthropicToolCall) ?? []
}

func anthropicTextContent(from value: JSONValue?) -> String? {
    guard let parts = value?.arrayValue else { return nil }
    return parts.compactMap { part -> String? in
        if part["type"]?.stringValue == "tool_use",
           part["name"]?.stringValue == "json",
           let input = part["input"] {
            return anthropicJSONString(input)
        }
        return part["text"]?.stringValue
    }.joined()
}

func anthropicToolResults(from value: JSONValue?, providerID: String) -> [AIToolResult] {
    var serverToolNames: [String: String] = [:]
    var mcpToolNames: [String: String] = [:]
    var mcpToolMetadata: [String: [String: JSONValue]] = [:]
    var results: [AIToolResult] = []

    for part in value?.arrayValue ?? [] {
        switch part["type"]?.stringValue {
        case "server_tool_use":
            if let id = part["id"]?.stringValue, let name = part["name"]?.stringValue {
                serverToolNames[id] = name
            }
        case "mcp_tool_use":
            if let id = part["id"]?.stringValue {
                if let name = part["name"]?.stringValue {
                    mcpToolNames[id] = name
                }
                mcpToolMetadata[id] = anthropicContentBlockProviderMetadata([
                    "type": .string("mcp-tool-use"),
                    "serverName": part["server_name"] ?? .null
                ], providerID: providerID)
            }
        default:
            break
        }

        if let result = anthropicToolResult(
            from: part,
            providerID: providerID,
            serverToolNames: serverToolNames,
            mcpToolNames: mcpToolNames,
            mcpToolMetadata: mcpToolMetadata
        ) {
            results.append(result)
        }
    }
    return results
}

func anthropicToolResult(
    from part: JSONValue,
    providerID: String,
    serverToolNames: [String: String],
    mcpToolNames: [String: String],
    mcpToolMetadata: [String: [String: JSONValue]]
) -> AIToolResult? {
    guard let type = part["type"]?.stringValue else { return nil }
    switch type {
    case "web_fetch_tool_result":
        guard let toolCallID = part["tool_use_id"]?.stringValue,
              let content = part["content"],
              let contentType = content["type"]?.stringValue else { return nil }
        if contentType == "web_fetch_result" {
            let source = content["content"]?["source"]
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: "web_fetch",
                result: .object([
                    "type": .string("web_fetch_result"),
                    "url": content["url"],
                    "retrievedAt": content["retrieved_at"],
                    "content": .object([
                        "type": content["content"]?["type"],
                        "title": content["content"]?["title"],
                        "citations": content["content"]?["citations"],
                        "source": .object([
                            "type": source?["type"],
                            "mediaType": source?["media_type"],
                            "data": source?["data"]
                        ])
                    ])
                ])
            )
        }
        if contentType == "web_fetch_tool_result_error" {
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: "web_fetch",
                result: .object([
                    "type": .string("web_fetch_tool_result_error"),
                    "errorCode": content["error_code"]
                ]),
                isError: true
            )
        }
        return nil
    case "web_search_tool_result":
        guard let toolCallID = part["tool_use_id"]?.stringValue,
              let content = part["content"] else { return nil }
        if let results = content.arrayValue {
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: "web_search",
                result: .array(results.map { result in
                    .object([
                        "url": result["url"],
                        "title": result["title"],
                        "pageAge": result["page_age"] ?? .null,
                        "encryptedContent": result["encrypted_content"],
                        "type": result["type"]
                    ])
                })
            )
        }
        return AIToolResult(
            toolCallID: toolCallID,
            toolName: "web_search",
            result: .object([
                "type": .string("web_search_tool_result_error"),
                "errorCode": content["error_code"]
            ]),
            isError: true
        )
    case "code_execution_tool_result":
        guard let toolCallID = part["tool_use_id"]?.stringValue,
              let content = part["content"],
              let contentType = content["type"]?.stringValue else { return nil }
        switch contentType {
        case "code_execution_result":
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: "code_execution",
                result: .object([
                    "type": .string(contentType),
                    "stdout": content["stdout"],
                    "stderr": content["stderr"],
                    "return_code": content["return_code"],
                    "content": content["content"] ?? .array([JSONValue]())
                ])
            )
        case "encrypted_code_execution_result":
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: "code_execution",
                result: .object([
                    "type": .string(contentType),
                    "encrypted_stdout": content["encrypted_stdout"],
                    "stderr": content["stderr"],
                    "return_code": content["return_code"],
                    "content": content["content"] ?? .array([JSONValue]())
                ])
            )
        case "code_execution_tool_result_error":
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: "code_execution",
                result: .object([
                    "type": .string("code_execution_tool_result_error"),
                    "errorCode": content["error_code"]
                ]),
                isError: true
            )
        default:
            return nil
        }
    case "bash_code_execution_tool_result", "text_editor_code_execution_tool_result":
        guard let toolCallID = part["tool_use_id"]?.stringValue else { return nil }
        return AIToolResult(
            toolCallID: toolCallID,
            toolName: "code_execution",
            result: part["content"] ?? .null
        )
    case "tool_search_tool_result":
        guard let toolCallID = part["tool_use_id"]?.stringValue,
              let content = part["content"],
              let contentType = content["type"]?.stringValue else { return nil }
        let toolName = anthropicToolSearchToolName(serverToolNames[toolCallID])
        if contentType == "tool_search_tool_search_result" {
            let references = content["tool_references"]?.arrayValue ?? []
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: toolName,
                result: .array(references.map { reference in
                    .object([
                        "type": reference["type"],
                        "toolName": reference["tool_name"]
                    ])
                })
            )
        }
        return AIToolResult(
            toolCallID: toolCallID,
            toolName: toolName,
            result: .object([
                "type": .string("tool_search_tool_result_error"),
                "errorCode": content["error_code"]
            ]),
            isError: true
        )
    case "advisor_tool_result":
        guard let toolCallID = part["tool_use_id"]?.stringValue,
              let content = part["content"],
              let contentType = content["type"]?.stringValue else { return nil }
        switch contentType {
        case "advisor_result":
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: "advisor",
                result: .object([
                    "type": .string("advisor_result"),
                    "text": content["text"]
                ])
            )
        case "advisor_redacted_result":
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: "advisor",
                result: .object([
                    "type": .string("advisor_redacted_result"),
                    "encryptedContent": content["encrypted_content"]
                ])
            )
        default:
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: "advisor",
                result: .object([
                    "type": .string("advisor_tool_result_error"),
                    "errorCode": content["error_code"]
                ]),
                isError: true
            )
        }
    case "mcp_tool_result":
        guard let toolCallID = part["tool_use_id"]?.stringValue else { return nil }
        return AIToolResult(
            toolCallID: toolCallID,
            toolName: mcpToolNames[toolCallID] ?? "mcp_tool",
            result: part["content"] ?? .null,
            isError: part["is_error"]?.boolValue ?? false,
            dynamic: true,
            providerMetadata: mcpToolMetadata[toolCallID] ?? anthropicContentBlockProviderMetadata([
                "type": .string("mcp-tool-use"),
                "serverName": .null
            ], providerID: providerID)
        )
    default:
        return nil
    }
}

func anthropicToolSearchToolName(_ providerToolName: String?) -> String {
    switch providerToolName {
    case "tool_search_tool_bm25", "tool_search_tool_regex":
        return "tool_search"
    default:
        return "tool_search"
    }
}

func anthropicProviderMetadata(from raw: JSONValue, providerID: String, requestProviderOptions: [String: JSONValue] = [:]) -> [String: JSONValue] {
    anthropicProviderMetadata(
        usage: raw["usage"],
        stopSequence: raw["stop_sequence"] ?? .null,
        stopDetails: anthropicStopDetailsMetadata(from: raw["stop_details"]) ?? .null,
        container: anthropicContainerMetadata(from: raw["container"]) ?? .null,
        contextManagement: anthropicContextManagementMetadata(from: raw["context_management"]) ?? .null,
        providerID: providerID,
        requestProviderOptions: requestProviderOptions
    )
}

func anthropicProviderMetadata(
    usage: JSONValue?,
    stopSequence: JSONValue,
    stopDetails: JSONValue = .null,
    container: JSONValue,
    contextManagement: JSONValue,
    providerID: String,
    requestProviderOptions: [String: JSONValue] = [:]
) -> [String: JSONValue] {
    var metadataObject: [String: JSONValue] = [
        "usage": usage ?? .null,
        "stopSequence": stopSequence,
        "iterations": anthropicUsageIterations(from: usage?["iterations"]) ?? .null,
        "container": container,
        "contextManagement": contextManagement
    ]
    if stopDetails != .null {
        metadataObject["stopDetails"] = stopDetails
    }
    let metadata: JSONValue = .object(metadataObject)
    return Dictionary(uniqueKeysWithValues: anthropicProviderMetadataKeys(from: providerID, requestProviderOptions: requestProviderOptions).map {
        ($0, metadata)
    })
}

func anthropicProviderMetadataKey(from providerID: String) -> String {
    if providerID.hasPrefix("anthropic-aws") {
        return "anthropic-aws"
    }
    if providerID.hasPrefix("bedrock.anthropic") {
        return "bedrock.anthropic"
    }
    if providerID.hasPrefix("googleVertex.anthropic") {
        return "googleVertex.anthropic"
    }
    return "anthropic"
}

func anthropicProviderMetadataKeys(from providerID: String, requestProviderOptions: [String: JSONValue]) -> [String] {
    let canonicalKey = anthropicProviderMetadataKey(from: providerID)
    guard canonicalKey == "anthropic" else { return [canonicalKey] }
    let providerOptionsName = anthropicProviderOptionsName(from: providerID)
    guard providerOptionsName != "anthropic", requestProviderOptions[providerOptionsName] != nil else {
        return ["anthropic"]
    }
    return ["anthropic", providerOptionsName]
}

func anthropicMergedUsage(_ existing: JSONValue, _ update: JSONValue) -> JSONValue {
    var output = existing.objectValue ?? [:]
    for (key, value) in update.objectValue ?? [:] {
        output[key] = value
    }
    return .object(output)
}

func anthropicUsageIterations(from value: JSONValue?) -> JSONValue? {
    guard let iterations = value?.arrayValue else { return nil }
    return .array(iterations.map { iteration in
        var output: [String: JSONValue] = [:]
        output["type"] = iteration["type"]
        output["model"] = iteration["model"]
        output["inputTokens"] = iteration["input_tokens"]
        output["outputTokens"] = iteration["output_tokens"]
        output["cacheReadInputTokens"] = iteration["cache_read_input_tokens"]
        return .object(output.compactMapValues { $0 })
    })
}

func anthropicStopDetailsMetadata(from value: JSONValue?) -> JSONValue? {
    guard var object = value?.objectValue else { return nil }
    anthropicMoveKey("recommended_model", to: "recommendedModel", in: &object)
    return .object(object)
}

func anthropicTokenUsage(from usage: JSONValue?) -> TokenUsage? {
    guard let usage else { return nil }
    let cacheReadTokens = usage["cache_read_input_tokens"]?.intValue ?? 0
    let cacheWriteTokens = usage["cache_creation_input_tokens"]?.intValue ?? 0
    let iterations = usage["iterations"]?.arrayValue ?? []
    let servedByFallback = iterations.contains { $0["type"]?.stringValue == "fallback_message" }
    if !iterations.isEmpty && !servedByFallback {
        let executorIterations = iterations.filter {
            let type = $0["type"]?.stringValue
            return type == "compaction" || type == "message"
        }
        if executorIterations.isEmpty {
            let inputTokens = usage["input_tokens"]?.intValue
            return TokenUsage(
                inputTokens: inputTokens.map { $0 + cacheReadTokens + cacheWriteTokens },
                outputTokens: usage["output_tokens"]?.intValue,
                inputTokensNoCache: inputTokens,
                inputTokensCacheRead: cacheReadTokens,
                inputTokensCacheWrite: cacheWriteTokens,
                rawValue: usage
            )
        }
        let inputTokens = executorIterations.reduce(0) { $0 + ($1["input_tokens"]?.intValue ?? 0) }
        return TokenUsage(
            inputTokens: inputTokens + cacheReadTokens + cacheWriteTokens,
            outputTokens: executorIterations.reduce(0) { $0 + ($1["output_tokens"]?.intValue ?? 0) },
            inputTokensNoCache: inputTokens,
            inputTokensCacheRead: cacheReadTokens,
            inputTokensCacheWrite: cacheWriteTokens,
            rawValue: usage
        )
    }
    let inputTokens = usage["input_tokens"]?.intValue
    return TokenUsage(
        inputTokens: inputTokens.map { $0 + cacheReadTokens + cacheWriteTokens },
        outputTokens: usage["output_tokens"]?.intValue,
        inputTokensNoCache: inputTokens,
        inputTokensCacheRead: cacheReadTokens,
        inputTokensCacheWrite: cacheWriteTokens,
        rawValue: usage
    )
}

func anthropicHTTPStatusError(provider: String, response: AIHTTPResponse) -> AIError {
    let body = anthropicErrorMessage(from: response.body) ?? response.bodyText
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

func anthropicStreamError(from raw: JSONValue, provider: String, headers: [String: String]) -> AIError? {
    guard raw["type"]?.stringValue == "error" else { return nil }
    let error = raw["error"] ?? raw
    let message = error["message"]?.stringValue ?? "Anthropic stream returned an error event."
    let statusCode = error["type"]?.stringValue == "overloaded_error" ? 529 : 500
    return .apiCall(provider: provider, statusCode: statusCode, body: message, headers: headers)
}

func anthropicErrorMessage(from data: Data) -> String? {
    guard let json = try? decodeJSONBody(data) else { return nil }
    return json["error"]?["message"]?.stringValue ?? json["message"]?.stringValue
}

func anthropicContainerMetadata(from value: JSONValue?) -> JSONValue? {
    guard var object = value?.objectValue else { return nil }
    anthropicMoveKey("expires_at", to: "expiresAt", in: &object)
    if let skills = object["skills"]?.arrayValue {
        object["skills"] = .array(skills.map { skill in
            guard var skillObject = skill.objectValue else { return skill }
            anthropicMoveKey("skill_id", to: "skillId", in: &skillObject)
            return .object(skillObject)
        })
    } else if object["skills"] == nil {
        object["skills"] = .null
    }
    return .object(object)
}

func anthropicContextManagementMetadata(from value: JSONValue?) -> JSONValue? {
    guard var object = value?.objectValue else { return nil }
    if let edits = object.removeValue(forKey: "applied_edits")?.arrayValue {
        object["appliedEdits"] = .array(edits.map { edit in
            guard var editObject = edit.objectValue else { return edit }
            anthropicMoveKey("cleared_tool_uses", to: "clearedToolUses", in: &editObject)
            anthropicMoveKey("cleared_input_tokens", to: "clearedInputTokens", in: &editObject)
            return .object(editObject)
        })
    }
    return .object(object)
}

struct AnthropicCitationDocument {
    var title: String
    var filename: String?
    var mediaType: String
}

func anthropicCitationDocuments(from messages: [AIMessage]) -> [AnthropicCitationDocument] {
    messages.flatMap(\.content).compactMap { part in
        switch part {
        case let .data(mimeType, _, _), let .file(mimeType, _, _, _):
            guard mimeType.lowercased().hasPrefix("text/") || mimeType.lowercased() == "application/pdf" else {
                return nil
            }
            return AnthropicCitationDocument(title: "Document", filename: nil, mediaType: mimeType)
        case let .imageURL(url, _):
            guard url.lowercased().contains(".pdf") else { return nil }
            let filename = url.split(separator: "/").last.map(String.init)
            return AnthropicCitationDocument(title: filename ?? "Document", filename: filename, mediaType: "application/pdf")
        case .text, .reasoning, .reasoningFile, .custom, .providerReference, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
            return nil
        }
    }
}

func anthropicToolArguments(_ arguments: String) -> JSONValue {
    (try? decodeJSONBody(Data(arguments.utf8))) ?? .object([:])
}

func anthropicSources(from content: JSONValue?, citationDocuments: [AnthropicCitationDocument]) -> [AISource] {
    var sourceCounter = 0
    return content?.arrayValue?.flatMap { part in
        anthropicSources(from: part, citationDocuments: citationDocuments, sourceCounter: &sourceCounter)
    } ?? []
}

func anthropicSources(from eventOrPart: JSONValue, citationDocuments: [AnthropicCitationDocument], sourceCounter: inout Int) -> [AISource] {
    let part: JSONValue
    if eventOrPart["type"]?.stringValue == "content_block_start", let contentBlock = eventOrPart["content_block"] {
        part = contentBlock
    } else {
        part = eventOrPart
    }

    if part["type"]?.stringValue == "web_search_tool_result", let results = part["content"]?.arrayValue {
        return results.compactMap { result in
            guard result["type"]?.stringValue == "web_search_result",
                  let url = result["url"]?.stringValue else {
                return nil
            }
            let source = AISource(
                id: "anthropic-source-\(sourceCounter)",
                sourceType: "url",
                url: url,
                title: result["title"]?.stringValue,
                providerMetadata: ["anthropic": .object(["pageAge": result["page_age"] ?? .null])],
                rawValue: result
            )
            sourceCounter += 1
            return source
        }
    }

    if eventOrPart["type"]?.stringValue == "content_block_delta",
       eventOrPart["delta"]?["type"]?.stringValue == "citations_delta",
       let citation = eventOrPart["delta"]?["citation"],
       let source = anthropicCitationSource(from: citation, citationDocuments: citationDocuments, id: "anthropic-source-\(sourceCounter)") {
        sourceCounter += 1
        return [source]
    }

    guard let citations = part["citations"]?.arrayValue else {
        return []
    }

    return citations.compactMap { citation in
        guard let source = anthropicCitationSource(from: citation, citationDocuments: citationDocuments, id: "anthropic-source-\(sourceCounter)") else {
            return nil
        }
        sourceCounter += 1
        return source
    }
}

func anthropicCitationSource(from citation: JSONValue, citationDocuments: [AnthropicCitationDocument], id: String) -> AISource? {
    switch citation["type"]?.stringValue {
    case "web_search_result_location":
        guard let url = citation["url"]?.stringValue else { return nil }
        return AISource(
            id: id,
            sourceType: "url",
            url: url,
            title: citation["title"]?.stringValue,
            providerMetadata: ["anthropic": .object([
                "citedText": citation["cited_text"],
                "encryptedIndex": citation["encrypted_index"]
            ])],
            rawValue: citation
        )
    case "page_location", "char_location":
        guard let documentIndex = citation["document_index"]?.intValue,
              citationDocuments.indices.contains(documentIndex) else {
            return nil
        }
        let document = citationDocuments[documentIndex]
        let metadata: [String: JSONValue?]
        if citation["type"]?.stringValue == "page_location" {
            metadata = [
                "citedText": citation["cited_text"],
                "startPageNumber": citation["start_page_number"],
                "endPageNumber": citation["end_page_number"]
            ]
        } else {
            metadata = [
                "citedText": citation["cited_text"],
                "startCharIndex": citation["start_char_index"],
                "endCharIndex": citation["end_char_index"]
            ]
        }
        return AISource(
            id: id,
            sourceType: "document",
            title: citation["document_title"]?.stringValue ?? document.title,
            mediaType: document.mediaType,
            filename: document.filename,
            providerMetadata: ["anthropic": .object(metadata)],
            rawValue: citation
        )
    default:
        return nil
    }
}

func anthropicToolCall(from part: JSONValue) -> AIToolCall? {
    guard let type = part["type"]?.stringValue else { return nil }
    switch type {
    case "tool_use":
        guard let id = part["id"]?.stringValue, let name = part["name"]?.stringValue else { return nil }
        guard name != "json" else { return nil }
        return AIToolCall(
            id: id,
            name: name,
            arguments: anthropicJSONString(part["input"] ?? .object([:])) ?? "{}",
            rawValue: part
        )
    case "server_tool_use":
        guard let id = part["id"]?.stringValue, let name = part["name"]?.stringValue else { return nil }
        return AIToolCall(
            id: id,
            name: anthropicCustomToolName(forProviderToolName: name),
            arguments: anthropicJSONString(part["input"] ?? .object([:])) ?? "{}",
            providerExecuted: true,
            rawValue: part
        )
    case "mcp_tool_use":
        guard let id = part["id"]?.stringValue, let name = part["name"]?.stringValue else { return nil }
        return AIToolCall(
            id: id,
            name: name,
            arguments: anthropicJSONString(part["input"] ?? .object([:])) ?? "{}",
            providerExecuted: true,
            rawValue: part
        )
    default:
        return nil
    }
}

func anthropicCustomToolName(forProviderToolName name: String) -> String {
    switch name {
    case "text_editor_code_execution", "bash_code_execution":
        return "code_execution"
    default:
        return name
    }
}

func anthropicJSONString(_ value: JSONValue) -> String? {
    guard let data = try? encodeJSONBody(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

func anthropicFinishReason(_ reason: String?) -> String? {
    switch reason {
    case nil:
        return nil
    case "pause_turn", "end_turn", "stop_sequence":
        return "stop"
    case "refusal":
        return "content-filter"
    case "tool_use":
        return "tool-calls"
    case "max_tokens", "model_context_window_exceeded":
        return "length"
    case "compaction":
        return "other"
    default:
        return "other"
    }
}

func anthropicFinishReason(_ reason: String?, toolCalls: [AIToolCall]) -> String? {
    anthropicFinishReason(reason, toolCallCount: toolCalls.count)
}

func anthropicFinishReason(_ reason: String?, toolCallCount: Int) -> String? {
    if reason == "tool_use", toolCallCount == 0 {
        return "stop"
    }
    return anthropicFinishReason(reason)
}
