import Foundation

func openAICompatibleHTTPStatusError(provider: String, response: AIHTTPResponse) -> AIError {
    let body = openAICompatibleErrorMessage(from: response.body) ?? response.bodyText
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

func openAICompatibleErrorMessage(from data: Data) -> String? {
    guard let json = try? decodeJSONBody(data) else { return nil }
    return json["error"]?["message"]?.stringValue ?? json["message"]?.stringValue
}

func openAICompatibleStreamError(from raw: JSONValue) -> (message: String, rawValue: JSONValue)? {
    if let error = raw["error"] {
        return (
            error["message"]?.stringValue ?? openAICompatibleJSONString(error) ?? "OpenAI-compatible stream error.",
            error
        )
    }
    if let message = raw["message"]?.stringValue,
       raw["type"] != nil || raw["code"] != nil || raw["param"] != nil {
        return (message, raw)
    }
    return nil
}

func openAICompatibleJSONString(_ value: JSONValue) -> String? {
    guard let data = try? encodeJSONBody(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

func openAICompatibleChatTools(from tools: [String: JSONValue]) -> [JSONValue] {
    tools.compactMap { name, schema in
        let object = schema.objectValue
        if object?["type"]?.stringValue == "provider" || object?["id"]?.stringValue != nil {
            return nil
        }
        var parameters = schema
        var function: [String: JSONValue] = [
            "name": .string(name),
            "parameters": parameters
        ]
        if var parameterObject = parameters.objectValue {
            if let description = parameterObject["description"]?.stringValue {
                function["description"] = .string(description)
            }
            if let strict = parameterObject.removeValue(forKey: "strict") {
                function["strict"] = strict
                parameters = .object(parameterObject)
                function["parameters"] = parameters
            }
        }
        return .object([
            "type": .string("function"),
            "function": .object(function)
        ])
    }
}

func openAICompatibleChatToolChoice(from value: JSONValue?) -> JSONValue? {
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
        guard let toolName = object["toolName"]?.stringValue ?? object["tool_name"]?.stringValue else {
            return nil
        }
        return .object([
            "type": .string("function"),
            "function": .object(["name": .string(toolName)])
        ])
    default:
        return nil
    }
}

func openAICompatibleChatOptions(from extraBody: [String: JSONValue], supportsStructuredOutputs: Bool) -> [String: JSONValue] {
    var output = extraBody
    output.removeValue(forKey: "toolChoice")
    openAIResponsesMoveKey("parallelToolCalls", to: "parallel_tool_calls", in: &output)
    openAIResponsesMoveKey("maxCompletionTokens", to: "max_completion_tokens", in: &output)
    openAIResponsesMoveKey("serviceTier", to: "service_tier", in: &output)
    openAIResponsesMoveKey("promptCacheKey", to: "prompt_cache_key", in: &output)
    openAIResponsesMoveKey("promptCacheRetention", to: "prompt_cache_retention", in: &output)
    openAIResponsesMoveKey("safetyIdentifier", to: "safety_identifier", in: &output)
    if let logprobs = output["logprobs"] {
        if let count = logprobs.intValue, logprobs.doubleValue == Double(count) {
            output["logprobs"] = count > 0 ? .bool(true) : .bool(false)
            if count > 0 { output["top_logprobs"] = .number(Double(count)) }
        } else if logprobs.boolValue == true {
            output["top_logprobs"] = output["top_logprobs"] ?? .number(0)
        }
    }
    if let reasoningEffort = output.removeValue(forKey: "reasoningEffort") {
        output["reasoning_effort"] = reasoningEffort
    }
    if let textVerbosity = output.removeValue(forKey: "textVerbosity") {
        output["verbosity"] = textVerbosity
    }
    if let responseFormat = output.removeValue(forKey: "responseFormat") {
        if let mapped = openAICompatibleResponseFormat(from: responseFormat, supportsStructuredOutputs: supportsStructuredOutputs, strictJsonSchema: output.removeValue(forKey: "strictJsonSchema")) {
            output["response_format"] = mapped
        }
    } else {
        output.removeValue(forKey: "strictJsonSchema")
    }
    return output
}

func openAICompatibleChatWarnings(for request: LanguageModelRequest, providerID: String, openAIBackedProviderRoot: String? = nil, usesGenericProviderOptions: Bool = false) -> [AIWarning] {
    guard openAIBackedProviderRoot == nil, !isOpenAIBackedProvider(providerID) else { return [] }
    let providerOptionWarnings: [AIWarning]
    if usesGenericProviderOptions {
        providerOptionWarnings = openAICompatibleProviderOptionWarnings(providerOptions: request.providerOptions, extraBody: request.extraBody, providerID: providerID, includeCompatibilityNamespace: true)
    } else {
        providerOptionWarnings = openAICompatibleProviderOptionWarnings(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: true)
    }
    var warnings = providerOptionWarnings
    warnings.append(contentsOf: openAICompatibleChatToolWarnings(for: request))
    if providerID.hasPrefix("xai.") {
        warnings.append(contentsOf: xaiChatWarnings(for: request))
    }
    return warnings
}

func openAICompatibleChatToolWarnings(for request: LanguageModelRequest) -> [AIWarning] {
    guard !request.tools.isEmpty else { return [] }
    var warnings = request.tools.compactMap { name, schema -> AIWarning? in
        let object = schema.objectValue
        guard object?["type"]?.stringValue == "provider" || object?["id"]?.stringValue != nil else {
            return nil
        }
        return AIWarning(
            type: "unsupported",
            feature: "provider-defined tool \(object?["id"]?.stringValue ?? name)"
        )
    }
    let toolChoiceInput = request.toolChoice ?? request.extraBody["toolChoice"]
    if let string = toolChoiceInput?.stringValue {
        switch string {
        case "auto", "none", "required":
            break
        default:
            warnings.append(AIWarning(type: "unsupported", feature: "tool choice type: \(string)"))
        }
    } else if let object = toolChoiceInput?.objectValue {
        switch object["type"]?.stringValue {
        case "auto", "none", "required", "tool":
            break
        case let type?:
            warnings.append(AIWarning(type: "unsupported", feature: "tool choice type: \(type)"))
        case nil:
            warnings.append(AIWarning(type: "unsupported", feature: "tool choice type: undefined"))
        }
    }
    return warnings
}

func openAICompatibleResponseFormat(from value: JSONValue, supportsStructuredOutputs: Bool, strictJsonSchema: JSONValue?) -> JSONValue? {
    guard let object = value.objectValue else {
        return value
    }
    guard object["type"]?.stringValue == "json" else {
        return value
    }
    guard supportsStructuredOutputs, let schema = object["schema"] else {
        return .object(["type": .string("json_object")])
    }
    let strict = strictJsonSchema ?? .bool(true)
    let normalizedSchema = strict.boolValue == false ? schema : addAdditionalPropertiesToJSONSchema(schema)
    var jsonSchema: [String: JSONValue] = [
        "schema": normalizedSchema,
        "strict": strict,
        "name": object["name"] ?? .string("response")
    ]
    if let description = object["description"] {
        jsonSchema["description"] = description
    }
    return .object([
        "type": .string("json_schema"),
        "json_schema": .object(jsonSchema)
    ])
}

struct OpenAICompatibleToolCallBuffer {
    var id: String?
    var name: String?
    var arguments: String = ""
    var inputStarted = false
    var codeInterpreterContainerID: String?
    var applyPatchHasDiff = false
    var applyPatchEndEmitted = false
    var rawValue: JSONValue?
}

struct OpenAICompatibleStreamingToolCalls {
    private var buffers: [Int: OpenAICompatibleToolCallBuffer] = [:]

    mutating func apply(delta: JSONValue) -> [LanguageStreamPart] {
        let index = delta["index"]?.intValue ?? 0
        var buffer = buffers[index] ?? OpenAICompatibleToolCallBuffer()
        if let id = delta["id"]?.stringValue {
            buffer.id = id
        }
        if let name = delta["function"]?["name"]?.stringValue {
            buffer.name = name
        }
        let argumentsDelta = delta["function"]?["arguments"]?.stringValue ?? ""
        if !argumentsDelta.isEmpty {
            buffer.arguments += argumentsDelta
        }
        buffer.rawValue = delta
        let id = buffer.id ?? "tool-call-\(index)"
        var parts: [LanguageStreamPart] = []
        if !buffer.inputStarted, let name = buffer.name {
            parts.append(.toolInputStart(id: id, name: name))
            buffer.inputStarted = true
        }
        parts.append(.toolCallDelta(
            id: buffer.id,
            name: buffer.name,
            argumentsDelta: argumentsDelta,
            index: index
        ))
        if !argumentsDelta.isEmpty, buffer.inputStarted {
            parts.append(.toolInputDelta(id: id, delta: argumentsDelta))
        }
        buffers[index] = buffer
        return parts
    }

    mutating func finishedParts() -> [LanguageStreamPart] {
        buffers.keys.sorted().flatMap { index -> [LanguageStreamPart] in
            guard var buffer = buffers[index], let name = buffer.name else { return [] }
            let id = buffer.id ?? "tool-call-\(index)"
            var parts: [LanguageStreamPart] = []
            if !buffer.inputStarted {
                parts.append(.toolInputStart(id: id, name: name))
                buffer.inputStarted = true
                buffers[index] = buffer
            }
            parts.append(.toolInputEnd(id: id))
            parts.append(.toolCall(AIToolCall(
                id: buffer.id ?? "tool-call-\(index)",
                name: name,
                arguments: buffer.arguments,
                rawValue: buffer.rawValue
            )))
            return parts
        }
    }
}

func openAICompatibleChatToolCalls(from value: JSONValue?) -> [AIToolCall] {
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

func openAICompatibleFinishReason(_ reason: String?) -> String? {
    switch reason {
    case "stop":
        return "stop"
    case "length":
        return "length"
    case "content_filter":
        return "content-filter"
    case "tool_calls", "function_call":
        return "tool-calls"
    default:
        return "other"
    }
}
