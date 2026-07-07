import Foundation

func xaiResponsesPreparedRequest(
    modelID: String,
    providerID: String,
    request: LanguageModelRequest,
    stream: Bool,
    transformRequestBody: (@Sendable ([String: JSONValue]) -> [String: JSONValue])?
) throws -> OpenAICompatibleResponsesPreparedRequest {
    let options = try xaiResponsesMergedOptions(providerOptions: request.providerOptions, extraBody: request.extraBody)
    var warnings = xaiResponsesWarnings(for: request)
    let input = try request.messages.flatMap { message in
        try xaiResponsesInputMessageJSON(message, warnings: &warnings)
    }
    let preparedTools = xaiResponsesTools(from: request.tools, toolChoice: request.toolChoice ?? request.extraBody["toolChoice"])
    warnings.append(contentsOf: preparedTools.warnings)

    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "input": .array(input)
    ]
    if stream { body["stream"] = .bool(true) }
    if let maxOutputTokens = request.maxOutputTokens { body["max_output_tokens"] = .number(Double(maxOutputTokens)) }
    if let temperature = request.temperature { body["temperature"] = .number(temperature) }
    if let topP = request.topP { body["top_p"] = .number(topP) }
    if let seed = request.seed { body["seed"] = .number(Double(seed)) }
    if let responseFormat = xaiResponsesTextFormat(from: request.responseFormat) {
        body["text"] = .object(["format": responseFormat])
    }
    if options["logprobs"]?.boolValue == true || options["topLogprobs"] != nil {
        body["logprobs"] = .bool(true)
    }
    if let topLogprobs = options["topLogprobs"] { body["top_logprobs"] = topLogprobs }
    if let reasoningEffort = options["reasoningEffort"] {
        body["reasoning"] = .object(["effort": reasoningEffort])
    }
    if options["store"]?.boolValue == false {
        body["store"] = .bool(false)
    }
    if let previousResponseID = options["previousResponseId"] {
        body["previous_response_id"] = previousResponseID
    }
    if var include = options["include"]?.arrayValue {
        if options["store"]?.boolValue == false, !include.contains(.string("reasoning.encrypted_content")) {
            include.append(.string("reasoning.encrypted_content"))
        }
        body["include"] = .array(include)
    } else if options["store"]?.boolValue == false {
        body["include"] = .array([.string("reasoning.encrypted_content")])
    }
    if !preparedTools.tools.isEmpty {
        body["tools"] = .array(preparedTools.tools)
    }
    if let toolChoice = preparedTools.toolChoice {
        body["tool_choice"] = toolChoice
    }
    body.merge(options.raw) { _, new in new }
    return OpenAICompatibleResponsesPreparedRequest(body: transformRequestBody?(body) ?? body, warnings: warnings)
}

private struct XAIResponsesOptions {
    var values: [String: JSONValue]
    var raw: [String: JSONValue]

    subscript(key: String) -> JSONValue? {
        values[key]
    }
}

private func xaiResponsesMergedOptions(providerOptions: [String: JSONValue], extraBody: [String: JSONValue]) throws -> XAIResponsesOptions {
    var raw = extraBody
    if let extraNamespace = raw.removeValue(forKey: "xai"), extraNamespace != .null {
        guard let extraObject = extraNamespace.objectValue else {
            throw AIError.invalidArgument(argument: "extraBody.xai", message: "xAI responses extra body options must be an object.")
        }
        raw.merge(extraObject) { _, nested in nested }
    }

    var values = try xaiValidateResponsesProviderOptions(raw, argumentPrefix: "extraBody.xai", allowUnknown: true).values
    if let providerNamespace = providerOptions["xai"] {
        if providerNamespace != .null {
            guard let providerObject = providerNamespace.objectValue else {
                throw AIError.invalidArgument(argument: "providerOptions.xai", message: "xAI responses provider options must be an object.")
            }
            let providerValues = try xaiValidateResponsesProviderOptions(providerObject, argumentPrefix: "providerOptions.xai", allowUnknown: false).values
            values.merge(providerValues) { _, nested in nested }
        }
    }
    raw.removeValue(forKey: "reasoningEffort")
    raw.removeValue(forKey: "logprobs")
    raw.removeValue(forKey: "topLogprobs")
    raw.removeValue(forKey: "store")
    raw.removeValue(forKey: "previousResponseId")
    raw.removeValue(forKey: "include")
    return XAIResponsesOptions(values: values, raw: raw)
}

private func xaiValidateResponsesProviderOptions(_ options: [String: JSONValue], argumentPrefix: String, allowUnknown: Bool) throws -> XAIResponsesOptions {
    let allowedKeys: Set<String> = ["reasoningEffort", "logprobs", "topLogprobs", "store", "previousResponseId", "include"]
    var values: [String: JSONValue] = [:]
    var raw: [String: JSONValue] = [:]
    for (key, value) in options {
        guard allowedKeys.contains(key) else {
            if allowUnknown { raw[key] = value }
            continue
        }
        switch key {
        case "reasoningEffort":
            guard let effort = value.stringValue, ["low", "medium", "high"].contains(effort) else {
                throw AIError.invalidArgument(argument: "\(argumentPrefix).reasoningEffort", message: "xAI reasoningEffort must be none, low, medium, or high.")
            }
        case "logprobs", "store":
            guard value.boolValue != nil else {
                throw AIError.invalidArgument(argument: "\(argumentPrefix).\(key)", message: "xAI \(key) must be a boolean.")
            }
        case "topLogprobs":
            guard let topLogprobs = value.intValue,
                  value.doubleValue == Double(topLogprobs),
                  (0...8).contains(topLogprobs) else {
                throw AIError.invalidArgument(argument: "\(argumentPrefix).topLogprobs", message: "xAI topLogprobs must be an integer from 0 to 8.")
            }
        case "previousResponseId":
            guard value.stringValue != nil else {
                throw AIError.invalidArgument(argument: "\(argumentPrefix).previousResponseId", message: "xAI previousResponseId must be a string.")
            }
        case "include":
            if value == .null { continue }
            guard let values = value.arrayValue,
                  values.allSatisfy({ $0.stringValue == "file_search_call.results" }) else {
                throw AIError.invalidArgument(argument: "\(argumentPrefix).include", message: "xAI include must contain only file_search_call.results or be null.")
            }
        default:
            break
        }
        values[key] = value
    }
    return XAIResponsesOptions(values: values, raw: raw)
}

private func xaiResponsesWarnings(for request: LanguageModelRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if !request.stopSequences.isEmpty {
        warnings.append(AIWarning(type: "unsupported", feature: "stopSequences"))
    }
    return warnings
}

private func xaiResponsesInputMessageJSON(_ message: AIMessage, warnings: inout [AIWarning]) throws -> [JSONValue] {
    switch message.role {
    case .system:
        return [.object(["role": .string("system"), "content": .string(message.combinedText)])]
    case .user:
        return [.object([
            "role": .string("user"),
            "content": .array(try message.content.compactMap { try xaiResponsesUserContentPart($0) })
        ])]
    case .assistant:
        var items: [JSONValue] = []
        for part in message.content {
            switch part {
            case let .text(text, _):
                let item: [String: JSONValue] = [
                    "role": .string("assistant"),
                    "content": .string(text)
                ]
                items.append(.object(item))
            case let .toolCall(call):
                guard !call.providerExecuted else { break }
                var item: [String: JSONValue] = [
                    "type": .string("function_call"),
                    "id": call.providerMetadata["xai"]?["itemId"] ?? .string(call.id),
                    "call_id": .string(call.id),
                    "name": .string(call.name),
                    "arguments": .string(call.arguments),
                    "status": .string("completed")
                ]
                if let itemID = call.providerMetadata["xai"]?["itemId"] {
                    item["id"] = itemID
                }
                items.append(.object(item))
            case .toolResult:
                break
            case .data, .file, .reasoningFile, .custom, .imageURL, .providerReference, .toolApprovalRequest, .toolApprovalResponse:
                warnings.append(AIWarning(type: "other", message: "xAI Responses API does not support this assistant content type."))
            case .reasoning:
                warnings.append(AIWarning(type: "other", message: "Reasoning parts without xAI itemId or encrypted content cannot be sent back to xAI. Skipping."))
            }
        }
        if let reasoning = message.reasoning, !reasoning.isEmpty {
            warnings.append(AIWarning(type: "other", message: "Reasoning parts without xAI itemId or encrypted content cannot be sent back to xAI. Skipping."))
        }
        return items
    case .tool:
        return message.content.compactMap { part in
            guard case let .toolResult(result) = part else { return nil }
            return .object([
                "type": .string("function_call_output"),
                "call_id": .string(result.toolCallID),
                "output": .string(xaiResponsesToolResultOutput(result))
            ])
        }
    }
}

private func xaiResponsesUserContentPart(_ part: AIContentPart) throws -> JSONValue? {
    switch part {
    case let .text(text, _):
        return .object(["type": .string("input_text"), "text": .string(text)])
    case let .imageURL(url, _):
        return .object(["type": .string("input_image"), "image_url": .string(url)])
    case let .data(mimeType, data, _), let .file(mimeType, data, _, _):
        if mimeType.lowercased().hasPrefix("image/") {
            let resolvedMimeType = mimeType == "image/*" ? "image/jpeg" : mimeType
            return .object([
                "type": .string("input_image"),
                "image_url": .string("data:\(resolvedMimeType);base64,\(data.base64EncodedString())")
            ])
        }
        throw AIError.invalidArgument(
            argument: "messages",
            message: "xAI Responses requires a URL or Files API provider reference for non-image file parts."
        )
    case let .providerReference(_, reference, _, _):
        return .object([
            "type": .string("input_file"),
            "file_id": .string(try resolveProviderReference(reference: reference, provider: "xai"))
        ])
    case .reasoning, .reasoningFile, .custom, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
        return nil
    }
}

private func xaiResponsesToolResultOutput(_ result: AIToolResult) -> String {
    let output = result.modelOutput ?? result.result
    if let text = output.stringValue {
        return text
    }
    if let object = output.objectValue, let type = object["type"]?.stringValue {
        switch type {
        case "text", "error-text":
            return object["value"]?.stringValue ?? ""
        case "execution-denied":
            return object["reason"]?.stringValue ?? "tool execution denied"
        case "json", "error-json":
            return xaiResponsesJSONString(object["value"] ?? .object([:])) ?? ""
        case "content":
            return object["value"]?.arrayValue?.map { item in
                item["type"]?.stringValue == "text" ? (item["text"]?.stringValue ?? "") : ""
            }.joined() ?? ""
        default:
            break
        }
    }
    return xaiResponsesJSONString(output) ?? ""
}

private struct XAIResponsesPreparedTools {
    var tools: [JSONValue]
    var toolChoice: JSONValue?
    var warnings: [AIWarning]
}

private func xaiResponsesTools(from tools: [String: JSONValue], toolChoice: JSONValue?) -> XAIResponsesPreparedTools {
    guard !tools.isEmpty else { return XAIResponsesPreparedTools(tools: [], toolChoice: nil, warnings: []) }
    var warnings: [AIWarning] = []
    var output: [JSONValue] = []
    var providerToolNames: Set<String> = []

    for (name, schema) in tools {
        let object = schema.objectValue ?? [:]
        if object["type"]?.stringValue == "provider", let id = object["id"]?.stringValue {
            let toolName = object["name"]?.stringValue ?? name
            switch id {
            case "xai.web_search":
                output.append(.object(xaiResponsesSnakeCasedTool(type: "web_search", args: object["args"]?.objectValue ?? [:], keys: ["allowedDomains", "excludedDomains", "enableImageSearch", "enableImageUnderstanding"])))
                providerToolNames.insert(name)
                providerToolNames.insert(toolName)
            case "xai.x_search":
                output.append(.object(xaiResponsesSnakeCasedTool(type: "x_search", args: object["args"]?.objectValue ?? [:], keys: ["allowedXHandles", "excludedXHandles", "fromDate", "toDate", "enableImageUnderstanding", "enableVideoUnderstanding"])))
                providerToolNames.insert(name)
                providerToolNames.insert(toolName)
            case "xai.code_execution":
                output.append(.object(["type": .string("code_interpreter")]))
                providerToolNames.insert(name)
                providerToolNames.insert(toolName)
            case "xai.view_image":
                output.append(.object(["type": .string("view_image")]))
                providerToolNames.insert(name)
                providerToolNames.insert(toolName)
            case "xai.view_x_video":
                output.append(.object(["type": .string("view_x_video")]))
                providerToolNames.insert(name)
                providerToolNames.insert(toolName)
            case "xai.file_search":
                output.append(.object(xaiResponsesSnakeCasedTool(type: "file_search", args: object["args"]?.objectValue ?? [:], keys: ["vectorStoreIds", "maxNumResults"])))
                providerToolNames.insert(name)
                providerToolNames.insert(toolName)
            case "xai.mcp":
                output.append(.object(xaiResponsesSnakeCasedTool(type: "mcp", args: object["args"]?.objectValue ?? [:], keys: ["serverUrl", "serverLabel", "serverDescription", "allowedTools", "headers", "authorization"])))
                providerToolNames.insert(name)
                providerToolNames.insert(toolName)
            default:
                warnings.append(AIWarning(type: "unsupported", feature: "provider-defined tool \(toolName)"))
            }
            continue
        }

        var parameters = xaiRemoveAdditionalPropertiesFalse(schema)
        var function: [String: JSONValue] = [
            "type": .string("function"),
            "name": .string(name),
            "parameters": parameters
        ]
        if var parameterObject = parameters.objectValue {
            if let description = parameterObject["description"] {
                function["description"] = description
            }
            if let strict = parameterObject.removeValue(forKey: "strict") {
                function["strict"] = strict
                parameters = .object(parameterObject)
                function["parameters"] = parameters
            }
        }
        output.append(.object(function))
    }

    return XAIResponsesPreparedTools(
        tools: output,
        toolChoice: xaiResponsesToolChoice(from: toolChoice, tools: tools, providerToolNames: providerToolNames, warnings: &warnings),
        warnings: warnings
    )
}

private func xaiResponsesSnakeCasedTool(type: String, args: [String: JSONValue], keys: [String]) -> [String: JSONValue] {
    var output: [String: JSONValue] = ["type": .string(type)]
    for key in keys {
        if let value = args[key] ?? args[xaiResponsesSnakeCasedKey(key)] {
            output[xaiResponsesSnakeCasedKey(key)] = value
        }
    }
    return output
}

private func xaiResponsesToolChoice(from value: JSONValue?, tools: [String: JSONValue], providerToolNames: Set<String>, warnings: inout [AIWarning]) -> JSONValue? {
    if let string = value?.stringValue {
        switch string {
        case "auto", "none", "required":
            return .string(string)
        default:
            warnings.append(AIWarning(type: "unsupported", feature: "tool choice type: \(string)"))
            return nil
        }
    }
    guard let object = value?.objectValue else { return nil }
    switch object["type"]?.stringValue {
    case "auto", "none", "required":
        return object["type"]
    case "tool":
        guard let name = object["toolName"]?.stringValue ?? object["tool_name"]?.stringValue else { return nil }
        if providerToolNames.contains(name) {
            warnings.append(AIWarning(type: "unsupported", feature: "toolChoice for server-side tool \"\(name)\""))
            return nil
        }
        guard tools[name] != nil else { return nil }
        return .object(["type": .string("function"), "name": .string(name)])
    case let type?:
        warnings.append(AIWarning(type: "unsupported", feature: "tool choice type: \(type)"))
        return nil
    case nil:
        warnings.append(AIWarning(type: "unsupported", feature: "tool choice type: undefined"))
        return nil
    }
}

private func xaiResponsesTextFormat(from responseFormat: AIResponseFormat?) -> JSONValue? {
    guard let responseFormat, case let .json(schema, name, description) = responseFormat else { return nil }
    guard let schema else {
        return .object(["type": .string("json_object")])
    }
    var format: [String: JSONValue] = [
        "type": .string("json_schema"),
        "strict": .bool(true),
        "name": .string(name ?? "response"),
        "schema": schema
    ]
    if let description {
        format["description"] = .string(description)
    }
    return .object(format)
}

private func xaiRemoveAdditionalPropertiesFalse(_ value: JSONValue) -> JSONValue {
    switch value {
    case let .object(object):
        var mapped: [String: JSONValue] = [:]
        for (key, nested) in object {
            if key == "additionalProperties", nested.boolValue == false {
                continue
            }
            mapped[key] = xaiRemoveAdditionalPropertiesFalse(nested)
        }
        return .object(mapped)
    case let .array(array):
        return .array(array.map(xaiRemoveAdditionalPropertiesFalse))
    default:
        return value
    }
}

private func xaiResponsesSnakeCasedKey(_ key: String) -> String {
    var output = ""
    for character in key {
        if character.isUppercase {
            output.append("_")
            output.append(character.lowercased())
        } else {
            output.append(character)
        }
    }
    return output
}

private func xaiResponsesJSONString(_ value: JSONValue) -> String? {
    guard let data = try? encodeJSONBody(value) else { return nil }
    return String(data: data, encoding: .utf8)
}
