import Foundation

func openAIResponsesToolCalls(from raw: JSONValue, providerID: String, toolNameAliases: [String: String] = [:]) -> [AIToolCall] {
    var approvalToolCallIndex = 0
    return raw["output"]?.arrayValue?.compactMap { item in
        let approvalToolCallIDOverride: String?
        if item["type"]?.stringValue == "mcp_approval_request" {
            approvalToolCallIDOverride = openAIResponsesApprovalToolCallID(from: item, generatedIndex: approvalToolCallIndex)
            approvalToolCallIndex += 1
        } else {
            approvalToolCallIDOverride = nil
        }
        return openAIResponsesToolCall(
            from: item,
            providerID: providerID,
            toolNameAliases: toolNameAliases,
            approvalToolCallIDOverride: approvalToolCallIDOverride
        )
    } ?? []
}

func openAIResponsesToolResults(from raw: JSONValue, providerID: String, toolNameAliases: [String: String] = [:]) -> [AIToolResult] {
    var hostedToolSearchCallIDs: [String] = []
    return raw["output"]?.arrayValue?.compactMap { item in
        if item["type"]?.stringValue == "tool_search_call",
           item["execution"]?.stringValue == "server",
           let toolCallID = item["call_id"]?.stringValue ?? item["id"]?.stringValue {
            hostedToolSearchCallIDs.append(toolCallID)
            return nil
        }
        if item["type"]?.stringValue == "tool_search_output" {
            let toolCallID = item["call_id"]?.stringValue ?? (hostedToolSearchCallIDs.isEmpty ? nil : hostedToolSearchCallIDs.removeFirst()) ?? item["id"]?.stringValue
            return openAIResponsesToolResult(from: item, providerID: providerID, toolCallIDOverride: toolCallID, toolNameAliases: toolNameAliases)
        }
        return openAIResponsesToolResult(from: item, providerID: providerID, toolNameAliases: toolNameAliases)
    } ?? []
}

func openAIResponsesToolApprovalRequests(from raw: JSONValue, providerID: String) -> [AIToolApprovalRequest] {
    var approvalToolCallIndex = 0
    return raw["output"]?.arrayValue?.compactMap { item in
        let approvalToolCallIDOverride: String?
        if item["type"]?.stringValue == "mcp_approval_request" {
            approvalToolCallIDOverride = openAIResponsesApprovalToolCallID(from: item, generatedIndex: approvalToolCallIndex)
            approvalToolCallIndex += 1
        } else {
            approvalToolCallIDOverride = nil
        }
        return openAIResponsesToolApprovalRequest(
            from: item,
            providerID: providerID,
            approvalToolCallIDOverride: approvalToolCallIDOverride
        )
    } ?? []
}

func openAIResponsesResultContent(
    from raw: JSONValue,
    toolCalls: [AIToolCall],
    toolResults: [AIToolResult],
    toolApprovalRequests: [AIToolApprovalRequest],
    sources: [AISource],
    providerID: String,
    toolNameAliases: [String: String] = [:]
) -> [AIResultContentPart] {
    var content: [AIResultContentPart] = []
    var hostedToolSearchCallIDs: [String] = []
    var approvalToolCallIndex = 0
    for item in raw["output"]?.arrayValue ?? [] {
        let approvalToolCallIDOverride: String?
        if item["type"]?.stringValue == "mcp_approval_request" {
            approvalToolCallIDOverride = openAIResponsesApprovalToolCallID(from: item, generatedIndex: approvalToolCallIndex)
            approvalToolCallIndex += 1
        } else {
            approvalToolCallIDOverride = nil
        }
        content.append(contentsOf: openAIResponsesOutputContentItem(from: item, providerID: providerID))
        if let toolCall = openAIResponsesToolCall(
            from: item,
            providerID: providerID,
            toolNameAliases: toolNameAliases,
            approvalToolCallIDOverride: approvalToolCallIDOverride
        ) {
            content.append(.toolCall(toolCall))
        }
        if item["type"]?.stringValue == "tool_search_call",
           item["execution"]?.stringValue == "server",
           let toolCallID = item["call_id"]?.stringValue ?? item["id"]?.stringValue {
            hostedToolSearchCallIDs.append(toolCallID)
        }
        if item["type"]?.stringValue == "tool_search_output" {
            let toolCallID = item["call_id"]?.stringValue ?? (hostedToolSearchCallIDs.isEmpty ? nil : hostedToolSearchCallIDs.removeFirst()) ?? item["id"]?.stringValue
            if let toolResult = openAIResponsesToolResult(from: item, providerID: providerID, toolCallIDOverride: toolCallID, toolNameAliases: toolNameAliases) {
                content.append(.toolResult(toolResult))
            }
        } else if let toolResult = openAIResponsesToolResult(from: item, providerID: providerID, toolNameAliases: toolNameAliases) {
            content.append(.toolResult(toolResult))
        }
        if let approvalRequest = openAIResponsesToolApprovalRequest(
            from: item,
            providerID: providerID,
            approvalToolCallIDOverride: approvalToolCallIDOverride
        ) {
            content.append(.toolApprovalRequest(approvalRequest))
        }
    }
    content.append(contentsOf: sources.map(AIResultContentPart.source))
    return content
}

func openAIResponsesOutputContent(from raw: JSONValue, providerID: String) -> [AIResultContentPart] {
    raw["output"]?.arrayValue?.flatMap { item -> [AIResultContentPart] in
        openAIResponsesOutputContentItem(from: item, providerID: providerID)
    } ?? []
}

func openAIResponsesOutputContentItem(from item: JSONValue, providerID: String) -> [AIResultContentPart] {
        guard let type = item["type"]?.stringValue else { return [] }
        switch type {
        case "message":
            guard let itemID = item["id"]?.stringValue else { return [] }
            return item["content"]?.arrayValue?.compactMap { part in
                guard part["type"]?.stringValue == "output_text",
                      let text = part["text"]?.stringValue else { return nil }
                return .text(
                    text,
                    providerMetadata: openAIResponsesTextProviderMetadata(
                        itemID: itemID,
                        phase: item["phase"],
                        annotations: part["annotations"]?.arrayValue ?? [],
                        providerID: providerID
                    )
                )
            } ?? []
        case "reasoning":
            guard let itemID = item["id"]?.stringValue else { return [] }
            guard let summaries = item["summary"]?.arrayValue else { return [] }
            if summaries.isEmpty {
                return [
                    .reasoning(
                        "",
                        providerMetadata: openAIResponsesReasoningProviderMetadata(
                            itemID: itemID,
                            encryptedContent: item["encrypted_content"],
                            includeEncryptedContent: true,
                            providerID: providerID
                        )
                    )
                ]
            }
            return summaries.compactMap { summary in
                guard let text = summary["text"]?.stringValue else { return nil }
                return .reasoning(
                    text,
                    providerMetadata: openAIResponsesReasoningProviderMetadata(
                        itemID: itemID,
                        encryptedContent: item["encrypted_content"],
                        includeEncryptedContent: true,
                        providerID: providerID
                    )
                )
            }
        case "compaction":
            guard let itemID = item["id"]?.stringValue else { return [] }
            return [
                .custom(
                    .object(["kind": .string("openai.compaction")]),
                    providerMetadata: openAIResponsesCompactionProviderMetadata(
                        itemID: itemID,
                        encryptedContent: item["encrypted_content"],
                        providerID: providerID
                    )
                )
            ]
        default:
            return []
        }
}

func openAIResponsesToolCall(
    from item: JSONValue,
    providerID: String,
    toolNameAliases: [String: String] = [:],
    approvalToolCallIDOverride: String? = nil
) -> AIToolCall? {
    guard let type = item["type"]?.stringValue else { return nil }
    switch type {
    case "function_call":
        guard let name = item["name"]?.stringValue else { return nil }
        return AIToolCall(
            id: item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "function-call",
            name: name,
            arguments: item["arguments"]?.stringValue ?? "",
            providerMetadata: openAIResponsesItemProviderMetadata(
                itemID: item["id"]?.stringValue,
                providerID: providerID,
                extra: item["namespace"].map { ["namespace": $0] } ?? [:]
            ),
            rawValue: item
        )
    case "custom_tool_call":
        guard let name = item["name"]?.stringValue else { return nil }
        let input = item["input"].flatMap(openAIResponsesJSONString) ?? item["input"]?.stringValue ?? ""
        return AIToolCall(
            id: item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "custom-tool-call",
            name: name,
            arguments: input,
            providerMetadata: openAIResponsesItemProviderMetadata(itemID: item["id"]?.stringValue, providerID: providerID),
            rawValue: item
        )
    case "web_search_call":
        return openAIResponsesHostedToolCall(item: item, name: toolNameAliases["web_search"] ?? "web_search")
    case "computer_call":
        return openAIResponsesHostedToolCall(item: item, name: toolNameAliases["computer_use"] ?? "computer_use", arguments: "")
    case "file_search_call":
        return openAIResponsesHostedToolCall(item: item, name: toolNameAliases["file_search"] ?? "file_search")
    case "image_generation_call":
        return openAIResponsesHostedToolCall(item: item, name: toolNameAliases["image_generation"] ?? "image_generation")
    case "code_interpreter_call":
        var input: [String: JSONValue] = [:]
        if let code = item["code"] { input["code"] = code }
        if let containerID = item["container_id"] { input["containerId"] = containerID }
        return AIToolCall(
            id: item["id"]?.stringValue ?? "code-interpreter-call",
            name: toolNameAliases["code_interpreter"] ?? "code_interpreter",
            arguments: openAIResponsesJSONString(.object(input)) ?? "{}",
            providerExecuted: true,
            providerMetadata: openAIResponsesItemProviderMetadata(itemID: item["id"]?.stringValue, providerID: providerID),
            rawValue: item
        )
    case "tool_search_call":
        let toolCallID = item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "tool-search-call"
        return openAIResponsesToolSearchCall(
            from: item,
            id: toolCallID,
            providerID: providerID,
            providerExecuted: item["execution"]?.stringValue == "server",
            name: toolNameAliases["tool_search"] ?? "tool_search"
        )
    case "mcp_call":
        guard let name = item["name"]?.stringValue else { return nil }
        return AIToolCall(
            id: item["id"]?.stringValue ?? "mcp-call",
            name: "mcp.\(name)",
            arguments: item["arguments"]?.stringValue ?? "{}",
            providerExecuted: true,
            dynamic: true,
            rawValue: item
        )
    case "local_shell_call":
        return AIToolCall(
            id: item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "local-shell-call",
            name: toolNameAliases["local_shell"] ?? "local_shell",
            arguments: openAIResponsesJSONString(.object(["action": item["action"] ?? .null])) ?? "{}",
            providerMetadata: openAIResponsesItemProviderMetadata(itemID: item["id"]?.stringValue, providerID: providerID),
            rawValue: item
        )
    case "shell_call":
        return AIToolCall(
            id: item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "shell-call",
            name: toolNameAliases["shell"] ?? "shell",
            arguments: openAIResponsesJSONString(.object(["action": openAIResponsesShellCallAction(from: item)])) ?? "{}",
            providerExecuted: item["environment"] != nil,
            providerMetadata: openAIResponsesItemProviderMetadata(itemID: item["id"]?.stringValue, providerID: providerID),
            rawValue: item
        )
    case "apply_patch_call":
        return AIToolCall(
            id: item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "apply-patch-call",
            name: toolNameAliases["apply_patch"] ?? "apply_patch",
            arguments: openAIResponsesJSONString(.object([
                "callId": item["call_id"] ?? .null,
                "operation": item["operation"] ?? .null
            ])) ?? "{}",
            providerMetadata: openAIResponsesItemProviderMetadata(itemID: item["id"]?.stringValue, providerID: providerID),
            rawValue: item
        )
    case "mcp_approval_request":
        let toolName = "mcp.\(item["name"]?.stringValue ?? "tool")"
        return AIToolCall(
            id: approvalToolCallIDOverride ?? openAIResponsesApprovalToolCallID(from: item),
            name: toolName,
            arguments: item["arguments"]?.stringValue ?? "{}",
            providerExecuted: true,
            dynamic: true,
            rawValue: item
        )
    default:
        return nil
    }
}

func openAIResponsesToolSearchCall(from item: JSONValue, id: String, providerID: String, providerExecuted: Bool, name: String = "tool_search") -> AIToolCall {
    var input: [String: JSONValue] = [:]
    if let arguments = item["arguments"] { input["arguments"] = arguments }
    input["call_id"] = providerExecuted ? .null : .string(id)
    return AIToolCall(
        id: id,
        name: name,
        arguments: openAIResponsesJSONString(.object(input)) ?? "{}",
        providerExecuted: providerExecuted,
        providerMetadata: openAIResponsesItemProviderMetadata(itemID: item["id"]?.stringValue, providerID: providerID),
        rawValue: item
    )
}

func openAIResponsesApplyPatchInputPrefix(callID: String, operation: JSONValue) -> String {
    "{\"callId\":\"\(openAIResponsesEscapeJSONStringFragment(callID))\",\"operation\":{\"type\":\"\(openAIResponsesEscapeJSONStringFragment(operation["type"]?.stringValue ?? ""))\",\"path\":\"\(openAIResponsesEscapeJSONStringFragment(operation["path"]?.stringValue ?? ""))\",\"diff\":\""
}

func openAIResponsesToolResult(from item: JSONValue, providerID: String, toolCallIDOverride: String? = nil, toolNameAliases: [String: String] = [:]) -> AIToolResult? {
    guard let type = item["type"]?.stringValue else { return nil }
    switch type {
    case "web_search_call":
        return AIToolResult(
            toolCallID: item["id"]?.stringValue ?? "web-search-call",
            toolName: toolNameAliases["web_search"] ?? "web_search",
            result: openAIResponsesWebSearchResult(from: item["action"])
        )
    case "computer_call":
        return AIToolResult(
            toolCallID: item["id"]?.stringValue ?? "computer-call",
            toolName: toolNameAliases["computer_use"] ?? "computer_use",
            result: .object([
                "type": .string("computer_use_tool_result"),
                "status": .string(item["status"]?.stringValue ?? "completed")
            ])
        )
    case "file_search_call":
        return AIToolResult(
            toolCallID: item["id"]?.stringValue ?? "file-search-call",
            toolName: toolNameAliases["file_search"] ?? "file_search",
            result: .object([
                "queries": item["queries"] ?? .null,
                "results": openAIResponsesFileSearchResults(from: item["results"])
            ])
        )
    case "code_interpreter_call":
        return AIToolResult(
            toolCallID: item["id"]?.stringValue ?? "code-interpreter-call",
            toolName: toolNameAliases["code_interpreter"] ?? "code_interpreter",
            result: .object(["outputs": item["outputs"] ?? .null])
        )
    case "image_generation_call":
        return AIToolResult(
            toolCallID: item["id"]?.stringValue ?? "image-generation-call",
            toolName: toolNameAliases["image_generation"] ?? "image_generation",
            result: .object(["result": item["result"] ?? .null])
        )
    case "tool_search_output":
        return AIToolResult(
            toolCallID: toolCallIDOverride ?? item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "tool-search-output",
            toolName: toolNameAliases["tool_search"] ?? "tool_search",
            result: .object(["tools": item["tools"] ?? .array([JSONValue]())]),
            providerMetadata: openAIResponsesItemProviderMetadata(itemID: item["id"]?.stringValue, providerID: providerID)
        )
    case "shell_call_output":
        return AIToolResult(
            toolCallID: item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "shell-call-output",
            toolName: toolNameAliases["shell"] ?? "shell",
            result: .object(["output": openAIResponsesShellCallOutput(from: item["output"])])
        )
    case "mcp_call":
        guard let name = item["name"]?.stringValue else { return nil }
        var result: [String: JSONValue] = [
            "type": .string("call"),
            "serverLabel": item["server_label"] ?? .null,
            "name": .string(name),
            "arguments": item["arguments"] ?? .string("{}")
        ]
        if let output = item["output"] { result["output"] = output }
        if let error = item["error"] { result["error"] = error }
        return AIToolResult(
            toolCallID: item["id"]?.stringValue ?? "mcp-call",
            toolName: "mcp.\(name)",
            result: .object(result),
            dynamic: true,
            providerMetadata: openAIResponsesItemProviderMetadata(itemID: item["id"]?.stringValue, providerID: providerID)
        )
    default:
        return nil
    }
}

func openAIResponsesWebSearchResult(from action: JSONValue?) -> JSONValue {
    guard let action, let type = action["type"]?.stringValue else { return .object([:]) }
    var mappedAction: [String: JSONValue]
    switch type {
    case "search":
        mappedAction = ["type": .string("search")]
        if let query = action["query"] { mappedAction["query"] = query }
        if let queries = action["queries"] { mappedAction["queries"] = queries }
    case "open_page":
        mappedAction = ["type": .string("openPage")]
        if let url = action["url"] { mappedAction["url"] = url }
    case "find_in_page":
        mappedAction = ["type": .string("findInPage")]
        if let url = action["url"] { mappedAction["url"] = url }
        if let pattern = action["pattern"] { mappedAction["pattern"] = pattern }
    default:
        mappedAction = ["type": .string(type)]
    }
    var result: [String: JSONValue] = ["action": .object(mappedAction)]
    if let sources = action["sources"] {
        result["sources"] = sources
    }
    return .object(result)
}

func openAIResponsesFileSearchResults(from raw: JSONValue?) -> JSONValue {
    guard let results = raw?.arrayValue else { return .null }
    return .array(results.map { result in
        .object([
            "attributes": result["attributes"],
            "fileId": result["file_id"],
            "filename": result["filename"],
            "score": result["score"],
            "text": result["text"]
        ])
    })
}

func openAIResponsesToolApprovalRequest(
    from item: JSONValue,
    providerID: String,
    approvalToolCallIDOverride: String? = nil
) -> AIToolApprovalRequest? {
    guard item["type"]?.stringValue == "mcp_approval_request" else { return nil }
    let approvalRequestID = openAIResponsesApprovalRequestID(from: item)
    return AIToolApprovalRequest(
        id: approvalRequestID,
        toolName: "mcp.\(item["name"]?.stringValue ?? "tool")",
        arguments: item["arguments"]?.stringValue ?? "{}",
        toolCallID: approvalToolCallIDOverride ?? openAIResponsesApprovalToolCallID(from: item)
    )
}

func openAIResponsesApprovalRequestID(from item: JSONValue) -> String {
    item["approval_request_id"]?.stringValue ?? item["id"]?.stringValue ?? "mcp-approval-request"
}

func openAIResponsesApprovalToolCallID(from item: JSONValue, generatedIndex: Int? = nil) -> String {
    item["call_id"]?.stringValue ?? generatedIndex.map { "id-\($0)" } ?? "id-0"
}

func openAIResponsesHostedToolCall(item: JSONValue, name: String, idKey: String = "id", arguments: String = "{}") -> AIToolCall {
    AIToolCall(
        id: item[idKey]?.stringValue ?? item["id"]?.stringValue ?? "\(name)-call",
        name: name,
        arguments: arguments,
        providerExecuted: true,
        rawValue: item
    )
}

func openAIResponsesShellCallAction(from item: JSONValue) -> JSONValue {
    guard let action = item["action"]?.objectValue else { return item["action"] ?? .null }
    var normalized: [String: JSONValue] = [:]
    if let commands = action["commands"] {
        normalized["commands"] = commands
    }
    return .object(normalized)
}

func openAIResponsesShellCallOutput(from output: JSONValue?) -> JSONValue {
    .array(output?.arrayValue?.map { entry in
        var mapped: [String: JSONValue] = [:]
        if let stdout = entry["stdout"] { mapped["stdout"] = stdout }
        if let stderr = entry["stderr"] { mapped["stderr"] = stderr }
        if let outcome = entry["outcome"]?.objectValue {
            var mappedOutcome = outcome
            if let exitCode = mappedOutcome.removeValue(forKey: "exit_code") {
                mappedOutcome["exitCode"] = exitCode
            }
            mapped["outcome"] = .object(mappedOutcome)
        }
        return .object(mapped)
    } ?? [])
}

func openAIResponsesJSONString(_ value: JSONValue) -> String? {
    guard let data = try? encodeJSONBody(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

func openAIResponsesEscapeJSONStringFragment(_ value: String) -> String {
    let encoded = openAIResponsesJSONString(.string(value)) ?? "\"\""
    return String(encoded.dropFirst().dropLast())
}

func openAIResponsesIsTextDelta(_ raw: JSONValue) -> Bool {
    guard let type = raw["type"]?.stringValue else { return true }
    return type == "response.output_text.delta" || type == "response.output_text.done"
}

func openAIResponsesStreamEventStartsOutput(_ raw: JSONValue) -> Bool {
    guard let type = raw["type"]?.stringValue else { return false }
    return type.hasPrefix("response.output_")
}

func openAIResponsesStreamAPIError(_ raw: JSONValue, providerID: String) -> AIError {
    let error = raw["error"] ?? raw
    let code = error["code"]?.stringValue ?? raw["code"]?.stringValue
    let message = error["message"]?.stringValue ?? raw["message"]?.stringValue ?? "OpenAI Responses stream failed."
    return .apiCall(
        provider: providerID,
        statusCode: openAIResponsesStreamErrorStatusCode(code),
        body: message
    )
}

func openAIResponsesStreamFailedError(_ response: JSONValue, providerID: String) -> AIError {
    let error = response["error"] ?? response
    let code = error["code"]?.stringValue
    let message = error["message"]?.stringValue ?? "OpenAI Responses stream failed."
    return .apiCall(
        provider: providerID,
        statusCode: openAIResponsesStreamErrorStatusCode(code),
        body: message
    )
}

private func openAIResponsesStreamErrorStatusCode(_ code: String?) -> Int {
    switch code {
    case "insufficient_quota", "rate_limit_exceeded":
        return 429
    case "server_error":
        return 500
    default:
        return 400
    }
}

func openAIResponsesFinishReason(status: String?, incompleteReason: String?, hasToolCalls: Bool = false) -> String? {
    if let incompleteReason {
        switch incompleteReason {
        case "max_output_tokens", "length":
            return "length"
        case "content_filter":
            return "content-filter"
        case "tool_calls":
            return "tool-calls"
        case "error":
            return "error"
        case "stop":
            return "stop"
        default:
            return "other"
        }
    }

    switch status {
    case "completed":
        return hasToolCalls ? "tool-calls" : "stop"
    case "failed":
        return "error"
    case "incomplete":
        return "other"
    default:
        return status
    }
}

func openResponsesFinishReason(incompleteReason: String?, hasToolCalls: Bool) -> String {
    switch incompleteReason {
    case nil:
        return hasToolCalls ? "tool-calls" : "stop"
    case "max_output_tokens":
        return "length"
    case "content_filter":
        return "content-filter"
    default:
        return hasToolCalls ? "tool-calls" : "other"
    }
}

func openResponsesStreamFinishReason(
    response: JSONValue,
    hasToolCalls: Bool,
    mode: ResponsesRequestMode
) -> String? {
    let incompleteReason = response["incomplete_details"]?["reason"]?.stringValue
    if case .openResponses = mode {
        return openResponsesFinishReason(incompleteReason: incompleteReason, hasToolCalls: hasToolCalls)
    }
    return openAIResponsesFinishReason(
        status: response["status"]?.stringValue,
        incompleteReason: incompleteReason,
        hasToolCalls: hasToolCalls
    )
}
