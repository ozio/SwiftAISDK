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
    if !request.stopSequences.isEmpty { warnings.append(AIWarning(type: "unsupported", feature: "stopSequences")) }
    if request.topK != nil { warnings.append(AIWarning(type: "unsupported", feature: "topK")) }
    if request.seed != nil { warnings.append(AIWarning(type: "unsupported", feature: "seed")) }
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

func openAIResponsesInputMessageJSON(_ message: AIMessage, store: Bool, processedApprovalIDs: inout Set<String>, toolNamespaces: [String: JSONValue] = [:]) -> [JSONValue] {
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
                return [.object([
                    "type": .string("function_call_output"),
                    "call_id": .string(result.toolCallID),
                    "output": .string(openAIResponsesJSONString(result.modelOutput ?? result.result) ?? result.modelOutput?.stringValue ?? result.result.stringValue ?? "")
                ])]
            default:
                return []
            }
        }
    }

    if let call = message.content.compactMap({ part -> AIToolCall? in
        if case let .toolCall(call) = part { call } else { nil }
    }).first {
        var callObject: [String: JSONValue] = [
            "type": .string("function_call"),
            "call_id": .string(call.id),
            "name": .string(call.name),
            "arguments": .string(call.arguments)
        ]
        if let namespace = openAIResponsesNamespace(for: call, toolNamespaces: toolNamespaces) {
            callObject["namespace"] = namespace
        }
        return [.object(callObject)]
    }

    if message.role == .user {
        return [.object([
            "role": .string("user"),
            "content": .array(message.content.enumerated().compactMap(openAIResponsesInputContentPart))
        ])]
    }

    if message.role == .assistant {
        return [.object([
            "role": .string("assistant"),
            "content": .array(message.combinedText.isEmpty ? [] : [.object(["type": .string("output_text"), "text": .string(message.combinedText)])])
        ])]
    }

    return [.object([
        "role": .string(message.role.rawValue),
        "content": .string(message.combinedText)
    ])]
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

func openAIResponsesInputContentPart(_ indexAndPart: EnumeratedSequence<[AIContentPart]>.Element) -> JSONValue? {
    let (index, part) = indexAndPart
    switch part {
    case let .text(text):
        return .object(["type": .string("input_text"), "text": .string(text)])
    case let .imageURL(url):
        return .object(["type": .string("input_image"), "image_url": .string(url)])
    case let .data(mimeType, data), let .file(mimeType, data, _):
        let dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
        if mimeType.lowercased().hasPrefix("image/") {
            return .object(["type": .string("input_image"), "image_url": .string(dataURL)])
        }
        return .object([
            "type": .string("input_file"),
            "filename": .string(openAIResponsesFileName(for: mimeType, index: index)),
            "file_data": .string(dataURL)
        ])
    case .providerReference, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
        return nil
    }
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

func openAIResponsesApplyAutomaticOptions(to options: inout [String: JSONValue], tools: [String: JSONValue], modelID: String) {
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

    if options["store"]?.boolValue == false, openAIIsReasoningModel(modelID) {
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
