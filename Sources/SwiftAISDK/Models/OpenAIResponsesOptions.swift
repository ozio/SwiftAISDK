import Foundation

func openResponsesProviderOptions(providerOptions: [String: JSONValue], providerOptionsName: String) throws -> [String: JSONValue] {
    guard let value = providerOptions[providerOptionsName] else { return [:] }
    guard value != .null else { return [:] }
    guard let options = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.\(providerOptionsName)", message: "Open Responses provider options must be an object.")
    }
    let allowedKeys: Set<String> = ["reasoningEffort", "reasoningSummary"]
    var output: [String: JSONValue] = [:]
    for (key, value) in options where allowedKeys.contains(key) {
        guard value != .null else { continue }
        switch key {
        case "reasoningEffort":
            guard let effort = value.stringValue, ["none", "low", "medium", "high", "xhigh"].contains(effort) else {
                throw AIError.invalidArgument(argument: "providerOptions.\(providerOptionsName).reasoningEffort", message: "Open Responses reasoningEffort must be none, low, medium, high, or xhigh.")
            }
        case "reasoningSummary":
            guard let summary = value.stringValue, ["concise", "detailed", "auto"].contains(summary) else {
                throw AIError.invalidArgument(argument: "providerOptions.\(providerOptionsName).reasoningSummary", message: "Open Responses reasoningSummary must be concise, detailed, or auto.")
            }
        default:
            break
        }
        output[key] = value
    }
    return output
}


func openResponsesFunctionTools(from tools: [String: JSONValue]) -> [JSONValue] {
    tools.compactMap { name, schema in
        var parameters = schema
        guard parameters["type"]?.stringValue != "provider" else {
            return nil
        }
        var tool: [String: JSONValue] = [
            "type": .string("function"),
            "name": .string(name),
            "parameters": parameters
        ]
        if var parameterObject = parameters.objectValue {
            if let description = parameterObject["description"] {
                tool["description"] = description
            }
            if let strict = parameterObject.removeValue(forKey: "strict") {
                tool["strict"] = strict
                parameters = .object(parameterObject)
                tool["parameters"] = parameters
            }
        }
        return .object(tool)
    }
}

func openResponsesToolChoice(from value: JSONValue?) -> JSONValue? {
    if let string = value?.stringValue {
        switch string {
        case "auto", "none", "required":
            return .string(string)
        default:
            return nil
        }
    }
    guard let object = value?.objectValue else { return nil }
    switch object["type"]?.stringValue {
    case "auto", "none", "required":
        return object["type"]
    case "tool":
        guard let name = object["toolName"]?.stringValue ?? object["tool_name"]?.stringValue else { return nil }
        return .object(["type": .string("function"), "name": .string(name)])
    default:
        return nil
    }
}

func openResponsesTextFormat(from responseFormat: AIResponseFormat?) -> JSONValue? {
    guard let responseFormat, case let .json(schema, name, description) = responseFormat else { return nil }
    var format: [String: JSONValue] = ["type": .string("json_schema")]
    if let schema {
        format["name"] = .string(name ?? "response")
        if let description { format["description"] = .string(description) }
        format["schema"] = schema
        format["strict"] = .bool(true)
    }
    return .object(format)
}

func openAIResponsesTextFormat(from responseFormat: AIResponseFormat?, strictJsonSchema: JSONValue?) -> JSONValue? {
    guard let responseFormat, case let .json(schema, name, description) = responseFormat else { return nil }
    guard let schema else {
        return .object(["type": .string("json_object")])
    }
    var format: [String: JSONValue] = [
        "type": .string("json_schema"),
        "name": .string(name ?? "response"),
        "schema": schema,
        "strict": strictJsonSchema ?? .bool(true)
    ]
    if let description { format["description"] = .string(description) }
    return .object(format)
}

func openResponsesWarnings(for request: LanguageModelRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.topK != nil { warnings.append(AIWarning(type: "unsupported", feature: "topK")) }
    if request.seed != nil { warnings.append(AIWarning(type: "unsupported", feature: "seed")) }
    if request.presencePenalty != nil { warnings.append(AIWarning(type: "unsupported", feature: "presencePenalty")) }
    if request.frequencyPenalty != nil { warnings.append(AIWarning(type: "unsupported", feature: "frequencyPenalty")) }
    if !request.stopSequences.isEmpty { warnings.append(AIWarning(type: "unsupported", feature: "stopSequences")) }
    return warnings
}

func openAIResponsesOutputText(from raw: JSONValue) -> String? {
    if let text = raw["output_text"]?.stringValue {
        return text
    }
    let parts = raw["output"]?.arrayValue?.flatMap { item -> [String] in
        guard item["type"]?.stringValue == "message" else { return [] }
        return item["content"]?.arrayValue?.compactMap { $0["text"]?.stringValue } ?? []
    } ?? []
    return parts.isEmpty ? nil : parts.joined()
}

func openAIResponsesInputMessageJSON(
    _ message: AIMessage,
    store: Bool,
    hasConversation: Bool = false,
    hasPreviousResponseID: Bool = false,
    processedApprovalIDs: inout Set<String>,
    toolNamespaces: [String: JSONValue] = [:],
    customToolNames: Set<String> = [],
    providerID: String = "openai",
    useDeveloperRoleForSystem: Bool = false,
    warnings: inout [AIWarning]
) throws -> [JSONValue] {
    if message.role == .tool {
        return message.content.flatMap { part -> [JSONValue] in
            switch part {
            case let .toolApprovalResponse(response):
                guard response.providerExecuted, processedApprovalIDs.insert(response.id).inserted else {
                    return []
                }
                var items: [JSONValue] = []
                if store {
                    items.append(.object([
                        "type": .string("item_reference"),
                        "id": .string(response.id)
                    ]))
                }
                items.append(.object([
                    "type": .string("mcp_approval_response"),
                    "approval_request_id": .string(response.id),
                    "approve": .bool(response.approved)
                ]))
                return items
            case let .toolResult(result):
                guard !openAIResponsesShouldSkipToolResult(result) else { return [] }
                if result.toolName == "tool_search" {
                    return [.object(openAIResponsesToolSearchOutput(result, store: store, providerID: providerID))]
                }
                if result.toolName == "local_shell" {
                    return [.object(openAIResponsesLocalShellOutput(result))]
                }
                if result.toolName == "shell" {
                    return [.object(openAIResponsesShellOutput(result))]
                }
                if result.toolName == "apply_patch" {
                    return [.object(openAIResponsesApplyPatchOutput(result))]
                }
                if customToolNames.contains(result.toolName) {
                    var warnings: [AIWarning] = []
                    return [.object([
                        "type": .string("custom_tool_call_output"),
                        "call_id": .string(result.toolCallID),
                        "output": openResponsesToolResultOutput(result, providerID: providerID, warnings: &warnings)
                    ])]
                }
                var warnings: [AIWarning] = []
                return [.object([
                    "type": .string("function_call_output"),
                    "call_id": .string(result.toolCallID),
                    "output": openResponsesToolResultOutput(result, providerID: providerID, warnings: &warnings)
                ])]
            default:
                return []
            }
        }
    }

    if message.role == .user {
        return [.object([
            "role": .string("user"),
            "content": .array(try message.content.enumerated().compactMap {
                try openAIResponsesInputContentPart($0, providerID: providerID)
            })
        ])]
    }

    if message.role == .assistant {
        var output: [JSONValue] = []
        var reasoningIndexes: [String: Int] = [:]
        for part in message.content {
            switch part {
            case let .text(text, providerMetadata):
                if hasConversation, openAIResponsesItemID(from: providerMetadata) != nil {
                    break
                }
                output.append(openAIResponsesAssistantTextItem(text: text, providerMetadata: providerMetadata, store: store))
            case let .reasoning(text, providerMetadata):
                if (hasConversation || hasPreviousResponseID), openAIResponsesItemID(from: providerMetadata) != nil {
                    break
                }
                openAIResponsesAppendReasoningItem(
                    text: text,
                    providerMetadata: providerMetadata,
                    store: store,
                    output: &output,
                    reasoningIndexes: &reasoningIndexes,
                    warnings: &warnings
                )
            case let .toolCall(call):
                if hasConversation, (openAIResponsesItemID(from: call.providerMetadata) ?? call.rawValue?["id"]?.stringValue) != nil {
                    break
                }
                if call.name == "tool_search" {
                    output.append(openAIResponsesToolSearchCallItem(call, store: store))
                    break
                }
                if call.providerExecuted {
                    if store, let itemID = openAIResponsesItemID(from: call.providerMetadata) ?? call.rawValue?["id"]?.stringValue {
                        output.append(.object(["type": .string("item_reference"), "id": .string(itemID)]))
                    }
                    break
                }
                if hasPreviousResponseID, store, (openAIResponsesItemID(from: call.providerMetadata) ?? call.rawValue?["id"]?.stringValue) != nil {
                    break
                }
                if call.name == "shell", store, let itemID = openAIResponsesItemID(from: call.providerMetadata) ?? call.rawValue?["id"]?.stringValue {
                    output.append(.object(["type": .string("item_reference"), "id": .string(itemID)]))
                    break
                }
                if call.name == "local_shell" {
                    output.append(openAIResponsesLocalShellCallItem(call, store: store))
                    break
                }
                if call.name == "apply_patch" {
                    output.append(openAIResponsesApplyPatchCallItem(call, store: store))
                    break
                }
                if customToolNames.contains(call.name) {
                    if store, let itemID = openAIResponsesItemID(from: call.providerMetadata) ?? call.rawValue?["id"]?.stringValue {
                        output.append(.object(["type": .string("item_reference"), "id": .string(itemID)]))
                        break
                    }
                    output.append(openAIResponsesCustomToolCallItem(call))
                    break
                }
                output.append(.object(openAIResponsesFunctionCallItem(call, toolNamespaces: toolNamespaces)))
            case let .toolResult(result):
                if openAIResponsesShouldSkipAssistantToolResult(result) {
                    break
                }
                if result.toolName == "tool_search" {
                    output.append(.object(openAIResponsesToolSearchOutput(result, store: store, providerID: providerID)))
                    break
                }
                if result.toolName == "shell" {
                    output.append(.object(openAIResponsesShellOutput(result)))
                    break
                }
                if !store {
                    warnings.append(AIWarning(
                        type: "other",
                        message: "Results for OpenAI tool \(result.toolName) are not sent to the API when store is false"
                    ))
                }
            case let .custom(value, providerMetadata):
                guard value["kind"]?.stringValue == "openai.compaction" else {
                    break
                }
                guard let itemID = openAIResponsesItemID(from: providerMetadata) else {
                    break
                }
                if hasConversation {
                    break
                }
                if store {
                    output.append(.object(["type": .string("item_reference"), "id": .string(itemID)]))
                    break
                }
                let openAIOptions = openAIResponsesOpenAIOptions(from: providerMetadata)
                var item: [String: JSONValue] = [
                    "type": .string("compaction"),
                    "id": .string(itemID)
                ]
                if let encryptedContent = openAIOptions["encryptedContent"] ?? openAIOptions["encrypted_content"] {
                    item["encrypted_content"] = encryptedContent
                }
                output.append(.object(item))
            default:
                break
            }
        }
        if !store {
            var droppedReasoningWithoutEncryptedContent = false
            output = output.filter { item in
                guard item["type"]?.stringValue == "reasoning",
                      item["encrypted_content"] == nil else {
                    return true
                }
                droppedReasoningWithoutEncryptedContent = true
                return false
            }
            if droppedReasoningWithoutEncryptedContent {
                warnings.append(AIWarning(
                    type: "other",
                    message: "Reasoning parts without encrypted content are not supported when store is false. Skipping reasoning parts."
                ))
            }
        }
        return output
    }

    let role = message.role == .system && useDeveloperRoleForSystem ? "developer" : message.role.rawValue
    return [.object([
        "role": .string(role),
        "content": .string(message.combinedText)
    ])]
}

func openAIResponsesSerializedToolCallArguments(_ arguments: String) -> String {
    arguments.isEmpty ? "{}" : arguments
}

func openAIResponsesOpenAIOptions(from providerMetadata: [String: JSONValue]) -> [String: JSONValue] {
    providerMetadata["openai"]?.objectValue ?? providerMetadata
}

func openAIResponsesItemID(from providerMetadata: [String: JSONValue]) -> String? {
    let openAIOptions = openAIResponsesOpenAIOptions(from: providerMetadata)
    return (openAIOptions["itemId"] ?? openAIOptions["item_id"])?.stringValue
}

func openAIResponsesAssistantTextItem(text: String, providerMetadata: [String: JSONValue], store: Bool) -> JSONValue {
    let openAIOptions = openAIResponsesOpenAIOptions(from: providerMetadata)
    let itemID = openAIOptions["itemId"] ?? openAIOptions["item_id"]
    if store, let itemID {
        return .object([
            "type": .string("item_reference"),
            "id": itemID
        ])
    }

    var item: [String: JSONValue] = [
        "role": .string("assistant"),
        "content": .array([.object(["type": .string("output_text"), "text": .string(text)])])
    ]
    if let itemID {
        item["id"] = itemID
    }
    if let phase = openAIOptions["phase"] {
        item["phase"] = phase
    }
    return .object(item)
}

func openAIResponsesAppendReasoningItem(
    text: String,
    providerMetadata: [String: JSONValue],
    store: Bool,
    output: inout [JSONValue],
    reasoningIndexes: inout [String: Int],
    warnings: inout [AIWarning]
) {
    let openAIOptions = openAIResponsesOpenAIOptions(from: providerMetadata)
    let reasoningID = (openAIOptions["itemId"] ?? openAIOptions["item_id"])?.stringValue
    let encryptedContent = (openAIOptions["reasoningEncryptedContent"] ?? openAIOptions["reasoning_encrypted_content"])?.stringValue

    guard let reasoningID else {
        guard let encryptedContent else {
            warnings.append(AIWarning(
                type: "other",
                message: "Non-OpenAI reasoning parts are not supported. Skipping reasoning part: \(openAIResponsesReasoningPartDescription(text: text, providerMetadata: providerMetadata))."
            ))
            return
        }

        let item: [String: JSONValue] = [
            "type": .string("reasoning"),
            "encrypted_content": .string(encryptedContent),
            "summary": .array(text.isEmpty ? [] : [.object(["type": .string("summary_text"), "text": .string(text)])])
        ]
        output.append(.object(item))
        return
    }

    if store {
        if reasoningIndexes[reasoningID] == nil {
            output.append(.object(["type": .string("item_reference"), "id": .string(reasoningID)]))
            reasoningIndexes[reasoningID] = output.count - 1
        }
        return
    }

    let existingIndex = reasoningIndexes[reasoningID]
    let summaryParts: [JSONValue]
    if text.isEmpty {
        summaryParts = []
        if existingIndex != nil {
            warnings.append(AIWarning(
                type: "other",
                message: "Cannot append empty reasoning part to existing reasoning sequence. Skipping reasoning part: \(openAIResponsesReasoningPartDescription(text: text, providerMetadata: providerMetadata))."
            ))
        }
    } else {
        summaryParts = [.object(["type": .string("summary_text"), "text": .string(text)])]
    }

    guard let existingIndex else {
        var item: [String: JSONValue] = [
            "type": .string("reasoning"),
            "id": .string(reasoningID),
            "summary": .array(summaryParts)
        ]
        if let encryptedContent {
            item["encrypted_content"] = .string(encryptedContent)
        }
        output.append(.object(item))
        reasoningIndexes[reasoningID] = output.count - 1
        return
    }

    guard var item = output[existingIndex].objectValue else { return }
    var summary = item["summary"]?.arrayValue ?? []
    summary.append(contentsOf: summaryParts)
    item["summary"] = .array(summary)
    if let encryptedContent {
        item["encrypted_content"] = .string(encryptedContent)
    }
    output[existingIndex] = .object(item)
}

func openAIResponsesReasoningPartDescription(text: String, providerMetadata: [String: JSONValue]) -> String {
    var part: [String: JSONValue] = [
        "type": .string("reasoning"),
        "text": .string(text)
    ]
    if !providerMetadata.isEmpty {
        part["providerOptions"] = .object(providerMetadata)
    }
    return openAIResponsesJSONString(.object(part)) ?? String(describing: part)
}

func openAIResponsesFunctionCallItem(_ call: AIToolCall, toolNamespaces: [String: JSONValue]) -> [String: JSONValue] {
    var callObject: [String: JSONValue] = [
        "type": .string("function_call"),
        "call_id": .string(call.id),
        "name": .string(call.name),
        "arguments": .string(openAIResponsesSerializedToolCallArguments(call.arguments))
    ]
    if let namespace = openAIResponsesNamespace(for: call, toolNamespaces: toolNamespaces) {
        callObject["namespace"] = namespace
    }
    return callObject
}

func openAIResponsesToolSearchCallItem(_ call: AIToolCall, store: Bool) -> JSONValue {
    let itemID = openAIResponsesItemID(from: call.providerMetadata) ?? call.rawValue?["id"]?.stringValue
    if store, let itemID {
        return .object(["type": .string("item_reference"), "id": .string(itemID)])
    }

    let input = openAIResponsesParsedToolArguments(call.arguments)
    let callID = input["call_id"]?.stringValue
    return .object([
        "type": .string("tool_search_call"),
        "id": .string(itemID ?? call.id),
        "execution": .string(callID == nil ? "server" : "client"),
        "call_id": callID.map(JSONValue.string) ?? .null,
        "status": .string("completed"),
        "arguments": input["arguments"] ?? .object([:])
    ])
}

func openAIResponsesToolSearchOutput(_ result: AIToolResult, store: Bool, providerID: String) -> [String: JSONValue] {
    let itemID = openAIResponsesItemID(from: result.providerMetadata)
    if store, let itemID {
        return ["type": .string("item_reference"), "id": .string(itemID)]
    }

    let output = result.modelOutput ?? result.result
    let tools = output["value"]?["tools"] ?? output["tools"] ?? .array([JSONValue]())
    let clientCallID = result.toolCallID.hasPrefix("call_") ? result.toolCallID : nil
    var object: [String: JSONValue] = [
        "type": .string("tool_search_output"),
        "execution": .string(clientCallID == nil ? "server" : "client"),
        "call_id": clientCallID.map(JSONValue.string) ?? .null,
        "status": .string("completed"),
        "tools": tools
    ]
    if let itemID {
        object["id"] = .string(itemID)
    } else if clientCallID == nil {
        object["id"] = .string(result.toolCallID)
    }
    return object
}

func openAIResponsesLocalShellCallItem(_ call: AIToolCall, store: Bool) -> JSONValue {
    let itemID = openAIResponsesItemID(from: call.providerMetadata) ?? call.rawValue?["id"]?.stringValue
    if store, let itemID {
        return .object(["type": .string("item_reference"), "id": .string(itemID)])
    }

    let input = openAIResponsesParsedToolArguments(call.arguments)
    let action = input["action"] ?? .object([:])
    var mappedAction: [String: JSONValue] = [
        "type": action["type"] ?? .string("exec"),
        "command": action["command"] ?? .array([JSONValue]())
    ]
    if let timeout = action["timeoutMs"] ?? action["timeout_ms"] { mappedAction["timeout_ms"] = timeout }
    if let user = action["user"] { mappedAction["user"] = user }
    if let workingDirectory = action["workingDirectory"] ?? action["working_directory"] { mappedAction["working_directory"] = workingDirectory }
    if let env = action["env"] { mappedAction["env"] = env }

    var item: [String: JSONValue] = [
        "type": .string("local_shell_call"),
        "call_id": .string(call.id),
        "action": .object(mappedAction)
    ]
    if let itemID {
        item["id"] = .string(itemID)
    }
    return .object(item)
}

func openAIResponsesLocalShellOutput(_ result: AIToolResult) -> [String: JSONValue] {
    let output = result.modelOutput ?? result.result
    return [
        "type": .string("local_shell_call_output"),
        "call_id": .string(result.toolCallID),
        "output": output["value"]?["output"] ?? output["output"] ?? .string("")
    ]
}

func openAIResponsesShellOutput(_ result: AIToolResult) -> [String: JSONValue] {
    let output = result.modelOutput ?? result.result
    let values = output["value"]?["output"]?.arrayValue ?? output["output"]?.arrayValue ?? []
    return [
        "type": .string("shell_call_output"),
        "call_id": .string(result.toolCallID),
        "output": .array(values.map(openAIResponsesShellOutputItem))
    ]
}

func openAIResponsesShellOutputItem(_ value: JSONValue) -> JSONValue {
    var item: [String: JSONValue] = [
        "stdout": value["stdout"] ?? .string(""),
        "stderr": value["stderr"] ?? .string("")
    ]
    if value["outcome"]?["type"]?.stringValue == "timeout" {
        item["outcome"] = .object(["type": .string("timeout")])
    } else {
        item["outcome"] = .object([
            "type": .string("exit"),
            "exit_code": value["outcome"]?["exitCode"] ?? value["outcome"]?["exit_code"] ?? .number(0)
        ])
    }
    return .object(item)
}

func openAIResponsesApplyPatchCallItem(_ call: AIToolCall, store: Bool) -> JSONValue {
    let itemID = openAIResponsesItemID(from: call.providerMetadata) ?? call.rawValue?["id"]?.stringValue
    if store, let itemID {
        return .object(["type": .string("item_reference"), "id": .string(itemID)])
    }

    let input = openAIResponsesParsedToolArguments(call.arguments)
    let callID = input["callId"]?.stringValue ?? input["call_id"]?.stringValue ?? call.id
    var item: [String: JSONValue] = [
        "type": .string("apply_patch_call"),
        "call_id": .string(callID),
        "status": .string("completed"),
        "operation": input["operation"] ?? .object([:])
    ]
    if let itemID {
        item["id"] = .string(itemID)
    }
    return .object(item)
}

func openAIResponsesApplyPatchOutput(_ result: AIToolResult) -> [String: JSONValue] {
    let output = result.modelOutput ?? result.result
    return [
        "type": .string("apply_patch_call_output"),
        "call_id": .string(result.toolCallID),
        "status": output["value"]?["status"] ?? output["status"] ?? .string("completed"),
        "output": output["value"]?["output"] ?? output["output"] ?? .string("")
    ]
}

func openAIResponsesCustomToolCallItem(_ call: AIToolCall) -> JSONValue {
    let itemID = openAIResponsesItemID(from: call.providerMetadata) ?? call.rawValue?["id"]?.stringValue
    var item: [String: JSONValue] = [
        "type": .string("custom_tool_call"),
        "call_id": .string(call.id),
        "name": .string(call.name),
        "input": openAIResponsesCustomToolInput(call.arguments)
    ]
    if let itemID {
        item["id"] = .string(itemID)
    }
    return .object(item)
}

func openAIResponsesCustomToolInput(_ arguments: String) -> JSONValue {
    let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let parsed = try? decodeJSONBody(Data(trimmed.utf8)) else {
        return .string(arguments)
    }
    if let string = parsed.stringValue {
        return .string(string)
    }
    return .string(openAIResponsesJSONString(parsed) ?? arguments)
}

func openAIResponsesParsedToolArguments(_ arguments: String) -> JSONValue {
    let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let parsed = try? decodeJSONBody(Data(trimmed.utf8)) else {
        return .object([:])
    }
    return parsed
}

func openAIResponsesToolNamespaces(from tools: [String: JSONValue]) -> [String: JSONValue] {
    tools.reduce(into: [:]) { output, entry in
        let object = entry.value.objectValue
        let openAIOptions = object?["providerOptions"]?["openai"]?.objectValue ?? object?["openai"]?.objectValue
        if let namespaceName = openAIOptions?["namespace"]?["name"]?.stringValue {
            output[entry.key] = .string(namespaceName)
        }
    }
}

func openAIResponsesNamespace(for call: AIToolCall, toolNamespaces: [String: JSONValue]) -> JSONValue? {
    call.providerMetadata["openai"]?["namespace"]
        ?? call.providerMetadata["openai"]?["item"]?["namespace"]
        ?? call.providerMetadata["namespace"]
        ?? call.rawValue?["namespace"]
        ?? toolNamespaces[call.name]
}

func openAIResponsesShouldSkipToolResult(_ result: AIToolResult) -> Bool {
    guard result.result["type"]?.stringValue == "execution-denied" else { return false }
    return result.providerMetadata["openai"]?["approvalId"]?.stringValue != nil
}

func openAIResponsesShouldSkipAssistantToolResult(_ result: AIToolResult) -> Bool {
    if result.result["type"]?.stringValue == "execution-denied" {
        return true
    }
    if result.result["type"]?.stringValue == "json",
       result.result["value"]?["type"]?.stringValue == "execution-denied" {
        return true
    }
    return false
}

func openAIResponsesInputContentPart(
    _ indexAndPart: EnumeratedSequence<[AIContentPart]>.Element,
    providerID: String = "openai"
) throws -> JSONValue? {
    let (index, part) = indexAndPart
    switch part {
    case let .text(text, _):
        return .object(["type": .string("input_text"), "text": .string(text)])
    case let .reasoning(text, _):
        return .object(["type": .string("input_text"), "text": .string(text)])
    case let .imageURL(url, _):
        return .object(["type": .string("input_image"), "image_url": .string(url)])
    case let .data(mimeType, data, _), let .file(mimeType, data, _, _):
        let resolvedMimeType = try openAIResponsesResolvedMimeType(mimeType, data: data)
        let dataURL = "data:\(resolvedMimeType);base64,\(data.base64EncodedString())"
        if resolvedMimeType.lowercased().hasPrefix("image/") {
            return .object(["type": .string("input_image"), "image_url": .string(dataURL)])
        }
        return .object([
            "type": .string("input_file"),
            "filename": .string(openAIResponsesFileName(for: resolvedMimeType, index: index)),
            "file_data": .string(dataURL)
        ])
    case let .providerReference(mimeType, reference, _, _):
        let fileID = try resolveProviderReference(reference, provider: openAICompatibleProviderRoot(providerID))
        if mimeType.lowercased() == "image" || mimeType.lowercased().hasPrefix("image/") {
            return .object([
                "type": .string("input_image"),
                "file_id": .string(fileID)
            ])
        }
        return .object([
            "type": .string("input_file"),
            "file_id": .string(fileID)
        ])
    case .reasoningFile, .custom, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
        return nil
    }
}

func openAIResponsesResolvedMimeType(_ mimeType: String, data: Data) throws -> String {
    guard mimeType.lowercased() == "image/*" else { return mimeType }
    if let detected = detectMediaType(data: data, topLevelType: "image") {
        return detected
    }
    throw AIError.invalidArgument(
        argument: "messages",
        message: #"Could not determine media type for file data with media type "image/*"."#
    )
}

func openAIResponsesFileName(for mimeType: String, index: Int) -> String {
    mimeType.lowercased() == "application/pdf" ? "part-\(index).pdf" : "part-\(index)"
}

func openAIResponsesOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    openAIResponsesMoveKey("conversation", to: "conversation", in: &output)
    openAIResponsesMoveKey("previousResponseId", to: "previous_response_id", in: &output)
    openAIResponsesMoveKey("parallelToolCalls", to: "parallel_tool_calls", in: &output)
    openAIResponsesMoveKey("serviceTier", to: "service_tier", in: &output)
    openAIResponsesMoveKey("maxToolCalls", to: "max_tool_calls", in: &output)
    openAIResponsesMoveKey("maxCompletionTokens", to: "max_output_tokens", in: &output)
    openAIResponsesMoveKey("promptCacheKey", to: "prompt_cache_key", in: &output)
    openAIResponsesMoveKey("promptCacheRetention", to: "prompt_cache_retention", in: &output)
    openAIResponsesMoveKey("safetyIdentifier", to: "safety_identifier", in: &output)
    openAIResponsesMoveKey("textVerbosity", to: "textVerbosity", in: &output)
    if let contextManagement = output.removeValue(forKey: "contextManagement") ?? output.removeValue(forKey: "context_management") {
        output["context_management"] = openAIResponsesContextManagement(contextManagement)
    }
    output.removeValue(forKey: "toolChoice")

    var reasoning = output["reasoning"]?.objectValue ?? [:]
    if let effort = output.removeValue(forKey: "reasoningEffort") {
        reasoning["effort"] = effort
    }
    if let summary = output.removeValue(forKey: "reasoningSummary") {
        reasoning["summary"] = summary
    }
    if !reasoning.isEmpty {
        output["reasoning"] = .object(reasoning)
    }

    return output
}

func openAIResponsesEffectiveReasoningModel(modelID: String, options: [String: JSONValue]) -> Bool {
    options["forceReasoning"]?.boolValue ?? openAIIsReasoningModel(modelID)
}

func openAIResponsesApplyTopLevelReasoning(_ reasoning: String?, isReasoningModel: Bool, to options: inout [String: JSONValue]) {
    guard let reasoning, reasoning != "provider-default", isReasoningModel else { return }
    var object = options["reasoning"]?.objectValue ?? [:]
    if object["effort"] == nil {
        object["effort"] = .string(reasoning)
    }
    if reasoning != "none", object["summary"] == nil {
        object["summary"] = .string("detailed")
    }
    if !object.isEmpty {
        options["reasoning"] = .object(object)
    }
}

func openAIResponsesFinalizeReasoningOptions(isReasoningModel: Bool, options: inout [String: JSONValue], warnings: inout [AIWarning]) {
    options.removeValue(forKey: "forceReasoning")
    var reasoning = options["reasoning"]?.objectValue ?? [:]
    let hasExplicitNullSummary = reasoning["summary"] == .null
    if hasExplicitNullSummary {
        reasoning.removeValue(forKey: "summary")
    }
    if isReasoningModel {
        if let effort = reasoning["effort"]?.stringValue, effort != "none", reasoning["summary"] == nil, !hasExplicitNullSummary {
            reasoning["summary"] = .string("detailed")
        }
        if !reasoning.isEmpty {
            options["reasoning"] = .object(reasoning)
        }
        return
    }
    if reasoning["effort"] != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "reasoningEffort",
            message: "reasoningEffort is not supported for non-reasoning models"
        ))
    }
    if reasoning["summary"] != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "reasoningSummary",
            message: "reasoningSummary is not supported for non-reasoning models"
        ))
    }
    options.removeValue(forKey: "reasoning")
}

func openAIResponsesStripsSamplingSettings(isReasoningModel: Bool, options: [String: JSONValue]) -> Bool {
    guard isReasoningModel else { return false }
    return options["reasoning"]?["effort"]?.stringValue != "none"
}

func openAIResponsesOpenAIBackedWarnings(options: [String: JSONValue]) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if options["conversation"] != nil, options["previous_response_id"] != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "conversation",
            message: "conversation and previousResponseId cannot be used together"
        ))
    }
    return warnings
}

func openAIResponsesApplyAutomaticOptions(to options: inout [String: JSONValue], tools: [String: JSONValue], isReasoningModel: Bool) {
    if let logprobs = options.removeValue(forKey: "logprobs") {
        if let count = logprobs.intValue, logprobs.doubleValue == Double(count), count > 0 {
            options["top_logprobs"] = .number(Double(count))
            openAIResponsesAppendInclude("message.output_text.logprobs", to: &options)
        } else if logprobs.boolValue == true {
            options["top_logprobs"] = .number(20)
            openAIResponsesAppendInclude("message.output_text.logprobs", to: &options)
        }
    }

    if tools.contains(where: { _, schema in
        let id = schema["id"]?.stringValue
        return id == "openai.web_search" || id == "openai.web_search_preview"
    }) {
        openAIResponsesAppendInclude("web_search_call.action.sources", to: &options)
    }

    if tools.contains(where: { _, schema in schema["id"]?.stringValue == "openai.code_interpreter" }) {
        openAIResponsesAppendInclude("code_interpreter_call.outputs", to: &options)
    }

    if options["store"]?.boolValue == false, isReasoningModel {
        openAIResponsesAppendInclude("reasoning.encrypted_content", to: &options)
    }
}

func openAIResponsesAppendInclude(_ value: String, to options: inout [String: JSONValue]) {
    var include = options["include"]?.arrayValue ?? []
    let item = JSONValue.string(value)
    if !include.contains(item) {
        include.append(item)
    }
    options["include"] = .array(include)
}

func openAIIsReasoningModel(_ modelID: String) -> Bool {
    modelID.hasPrefix("o1")
        || modelID.hasPrefix("o3")
        || modelID.hasPrefix("o4-mini")
        || (modelID.hasPrefix("gpt-5") && !modelID.hasPrefix("gpt-5-chat"))
}

func openAIResponsesAllowedToolsChoice(from value: JSONValue) -> JSONValue {
    let object = value.objectValue ?? [:]
    let toolNames = object["toolNames"]?.arrayValue ?? object["tool_names"]?.arrayValue ?? []
    return .object([
        "type": .string("allowed_tools"),
        "mode": object["mode"] ?? .string("auto"),
        "tools": .array(toolNames.compactMap { name in
            guard let name = name.stringValue else { return nil }
            return .object(["type": .string("function"), "name": .string(name)])
        })
    ])
}

func openAIResponsesContextManagement(_ value: JSONValue) -> JSONValue {
    guard let items = value.arrayValue else { return value }
    return .array(items.map { item in
        guard var object = item.objectValue else { return item }
        openAIResponsesMoveKey("compactThreshold", to: "compact_threshold", in: &object)
        return .object(object)
    })
}

func xaiResponsesOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let topLogprobs = output.removeValue(forKey: "topLogprobs") {
        output["top_logprobs"] = topLogprobs
        output["logprobs"] = output["logprobs"] ?? .bool(true)
    }
    if output["store"]?.boolValue == true {
        output.removeValue(forKey: "store")
    } else if output["store"]?.boolValue == false {
        var include = output["include"]?.arrayValue ?? []
        if !include.contains(.string("reasoning.encrypted_content")) {
            include.append(.string("reasoning.encrypted_content"))
        }
        output["include"] = .array(include)
    } else if output["include"] == .null {
        output.removeValue(forKey: "include")
    }
    return output
}

func xaiResponsesProviderOptions(providerOptions: [String: JSONValue], extraBody: [String: JSONValue], providerID: String) throws -> [String: JSONValue] {
    var output = openAICompatibleProviderOptions(from: extraBody, providerID: providerID, includeCompatibilityNamespace: false)
    if let value = providerOptions["xai"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.xai", message: "xAI responses provider options must be an object.")
        }
        output.merge(try xaiValidateResponsesProviderOptions(nested)) { _, nested in nested }
    }
    return output
}

func xaiValidateResponsesProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    let allowedKeys: Set<String> = [
        "reasoningEffort",
        "reasoningSummary",
        "logprobs",
        "topLogprobs",
        "store",
        "previousResponseId",
        "include"
    ]
    var output: [String: JSONValue] = [:]
    for (key, value) in options where allowedKeys.contains(key) {
        switch key {
        case "reasoningEffort":
            guard let effort = value.stringValue, ["none", "low", "medium", "high"].contains(effort) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.reasoningEffort", message: "xAI reasoningEffort must be none, low, medium, or high.")
            }
        case "reasoningSummary":
            guard let summary = value.stringValue, ["auto", "concise", "detailed"].contains(summary) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.reasoningSummary", message: "xAI reasoningSummary must be auto, concise, or detailed.")
            }
        case "logprobs", "store":
            guard value.boolValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.\(key)", message: "xAI \(key) must be a boolean.")
            }
        case "topLogprobs":
            guard let topLogprobs = value.intValue,
                  value.doubleValue == Double(topLogprobs),
                  (0...8).contains(topLogprobs) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.topLogprobs", message: "xAI topLogprobs must be an integer from 0 to 8.")
            }
        case "previousResponseId":
            guard value.stringValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.previousResponseId", message: "xAI previousResponseId must be a string.")
            }
        case "include":
            if value == .null {
                break
            }
            guard let values = value.arrayValue,
                  values.allSatisfy({ $0.stringValue == "file_search_call.results" }) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.include", message: "xAI include must contain only file_search_call.results or be null.")
            }
        default:
            break
        }
        output[key] = value
    }
    return output
}
