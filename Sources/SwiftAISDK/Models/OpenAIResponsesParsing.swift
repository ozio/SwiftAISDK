import Foundation

func openAIResponsesToolCalls(from raw: JSONValue, providerID: String) -> [AIToolCall] {
    raw["output"]?.arrayValue?.compactMap { openAIResponsesToolCall(from: $0, providerID: providerID) } ?? []
}

func openAIResponsesToolResults(from raw: JSONValue, providerID: String) -> [AIToolResult] {
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
            return openAIResponsesToolResult(from: item, providerID: providerID, toolCallIDOverride: toolCallID)
        }
        return openAIResponsesToolResult(from: item, providerID: providerID)
    } ?? []
}

func openAIResponsesToolApprovalRequests(from raw: JSONValue, providerID: String) -> [AIToolApprovalRequest] {
    raw["output"]?.arrayValue?.compactMap { openAIResponsesToolApprovalRequest(from: $0, providerID: providerID) } ?? []
}

func openAIResponsesToolCall(from item: JSONValue, providerID: String) -> AIToolCall? {
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
        return openAIResponsesHostedToolCall(item: item, name: "web_search")
    case "computer_call":
        return openAIResponsesHostedToolCall(item: item, name: "computer_use", arguments: "")
    case "file_search_call":
        return openAIResponsesHostedToolCall(item: item, name: "file_search")
    case "image_generation_call":
        return openAIResponsesHostedToolCall(item: item, name: "image_generation")
    case "code_interpreter_call":
        var input: [String: JSONValue] = [:]
        if let code = item["code"] { input["code"] = code }
        if let containerID = item["container_id"] { input["containerId"] = containerID }
        return AIToolCall(
            id: item["id"]?.stringValue ?? "code-interpreter-call",
            name: "code_interpreter",
            arguments: openAIResponsesJSONString(.object(input)) ?? "{}",
            providerExecuted: true,
            providerMetadata: openAIResponsesItemProviderMetadata(itemID: item["id"]?.stringValue, providerID: providerID),
            rawValue: item
        )
    case "tool_search_call":
        let toolCallID = item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "tool-search-call"
        return openAIResponsesToolSearchCall(from: item, id: toolCallID, providerID: providerID, providerExecuted: item["execution"]?.stringValue == "server")
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
        return openAIResponsesHostedToolCall(item: item, name: "local_shell", idKey: "call_id", arguments: openAIResponsesJSONString(.object(["action": item["action"] ?? .null])) ?? "{}")
    case "shell_call":
        return openAIResponsesHostedToolCall(item: item, name: "shell", idKey: "call_id", arguments: openAIResponsesJSONString(.object(["action": item["action"] ?? .null])) ?? "{}")
    case "apply_patch_call":
        return AIToolCall(
            id: item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "apply-patch-call",
            name: "apply_patch",
            arguments: openAIResponsesJSONString(.object([
                "callId": item["call_id"] ?? .null,
                "operation": item["operation"] ?? .null
            ])) ?? "{}",
            providerMetadata: openAIResponsesItemProviderMetadata(itemID: item["id"]?.stringValue, providerID: providerID),
            rawValue: item
        )
    case "mcp_approval_request":
        let approvalRequestID = openAIResponsesApprovalRequestID(from: item)
        let toolName = "mcp.\(item["name"]?.stringValue ?? "tool")"
        return AIToolCall(
            id: openAIResponsesApprovalToolCallID(from: item),
            name: toolName,
            arguments: item["arguments"]?.stringValue ?? "{}",
            providerExecuted: true,
            dynamic: true,
            providerMetadata: openAIResponsesItemProviderMetadata(
                itemID: item["id"]?.stringValue ?? approvalRequestID,
                providerID: providerID,
                extra: ["approvalId": .string(approvalRequestID)]
            ),
            rawValue: item
        )
    default:
        return nil
    }
}

func openAIResponsesToolSearchCall(from item: JSONValue, id: String, providerID: String, providerExecuted: Bool) -> AIToolCall {
    var input: [String: JSONValue] = [:]
    if let arguments = item["arguments"] { input["arguments"] = arguments }
    input["call_id"] = providerExecuted ? .null : .string(id)
    return AIToolCall(
        id: id,
        name: "tool_search",
        arguments: openAIResponsesJSONString(.object(input)) ?? "{}",
        providerExecuted: providerExecuted,
        providerMetadata: openAIResponsesItemProviderMetadata(itemID: item["id"]?.stringValue, providerID: providerID),
        rawValue: item
    )
}

func openAIResponsesApplyPatchInputPrefix(callID: String, operation: JSONValue) -> String {
    "{\"callId\":\"\(openAIResponsesEscapeJSONStringFragment(callID))\",\"operation\":{\"type\":\"\(openAIResponsesEscapeJSONStringFragment(operation["type"]?.stringValue ?? ""))\",\"path\":\"\(openAIResponsesEscapeJSONStringFragment(operation["path"]?.stringValue ?? ""))\",\"diff\":\""
}

func openAIResponsesToolResult(from item: JSONValue, providerID: String, toolCallIDOverride: String? = nil) -> AIToolResult? {
    guard let type = item["type"]?.stringValue else { return nil }
    switch type {
    case "web_search_call":
        return AIToolResult(
            toolCallID: item["id"]?.stringValue ?? "web-search-call",
            toolName: "web_search",
            result: openAIResponsesWebSearchResult(from: item["action"])
        )
    case "computer_call":
        return AIToolResult(
            toolCallID: item["id"]?.stringValue ?? "computer-call",
            toolName: "computer_use",
            result: .object([
                "type": .string("computer_use_tool_result"),
                "status": .string(item["status"]?.stringValue ?? "completed")
            ])
        )
    case "file_search_call":
        return AIToolResult(
            toolCallID: item["id"]?.stringValue ?? "file-search-call",
            toolName: "file_search",
            result: .object([
                "queries": item["queries"] ?? .null,
                "results": openAIResponsesFileSearchResults(from: item["results"])
            ])
        )
    case "code_interpreter_call":
        return AIToolResult(
            toolCallID: item["id"]?.stringValue ?? "code-interpreter-call",
            toolName: "code_interpreter",
            result: .object(["outputs": item["outputs"] ?? .null])
        )
    case "image_generation_call":
        return AIToolResult(
            toolCallID: item["id"]?.stringValue ?? "image-generation-call",
            toolName: "image_generation",
            result: .object(["result": item["result"] ?? .null])
        )
    case "tool_search_output":
        return AIToolResult(
            toolCallID: toolCallIDOverride ?? item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "tool-search-output",
            toolName: "tool_search",
            result: .object(["tools": item["tools"] ?? .array([JSONValue]())]),
            providerMetadata: openAIResponsesItemProviderMetadata(itemID: item["id"]?.stringValue, providerID: providerID)
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

func openAIResponsesToolApprovalRequest(from item: JSONValue, providerID: String) -> AIToolApprovalRequest? {
    guard item["type"]?.stringValue == "mcp_approval_request" else { return nil }
    let approvalRequestID = openAIResponsesApprovalRequestID(from: item)
    return AIToolApprovalRequest(
        id: approvalRequestID,
        toolName: "mcp.\(item["name"]?.stringValue ?? "tool")",
        arguments: item["arguments"]?.stringValue ?? "{}",
        toolCallID: openAIResponsesApprovalToolCallID(from: item),
        providerMetadata: openAIResponsesItemProviderMetadata(itemID: item["id"]?.stringValue ?? approvalRequestID, providerID: providerID)
    )
}

func openAIResponsesApprovalRequestID(from item: JSONValue) -> String {
    item["approval_request_id"]?.stringValue ?? item["id"]?.stringValue ?? "mcp-approval-request"
}

func openAIResponsesApprovalToolCallID(from item: JSONValue) -> String {
    let approvalRequestID = openAIResponsesApprovalRequestID(from: item)
    return item["call_id"]?.stringValue ?? "tool-call-\(approvalRequestID)"
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

func openAIResponsesFinishReason(status: String?, incompleteReason: String?) -> String? {
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
        return "stop"
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
        incompleteReason: incompleteReason
    )
}

