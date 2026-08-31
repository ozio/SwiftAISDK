import Foundation

func openAICompatibleHTTPStatusError(provider: String, response: AIHTTPResponse) -> AIError {
    let body: String
    if provider == "gmicloud.chat" {
        body = gmiCloudErrorMessage(from: response.body) ?? response.bodyText
    } else {
        body = openAICompatibleErrorMessage(from: response.body) ?? response.bodyText
    }
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
    return json["error"]?["message"]?.stringValue ?? json["error"]?.stringValue ?? json["message"]?.stringValue
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

/// Normalizes OpenAI-owned stream error frames using the provider's published
/// code semantics. Chat and Completion pass the nested `error` object here;
/// Responses passes the complete event so `response.failed` can retain its
/// provider event type and raw payload.
func openAIProviderStreamError(from frame: JSONValue) -> AIStreamProviderError? {
    let isResponseFailed = frame["type"]?.stringValue == "response.failed"
    let error = isResponseFailed
        ? frame["response"]?["error"]
        : frame["error"] ?? frame
    guard let error,
          let message = error["message"]?.stringValue else {
        return nil
    }

    let code: JSONValue?
    if error["code"]?.stringValue != nil || error["code"]?.doubleValue != nil {
        code = error["code"]
    } else {
        code = nil
    }
    let type = isResponseFailed ? "response.failed" : error["type"]?.stringValue
    guard isResponseFailed
            || frame["error"] != nil
            || type != nil
            || error["code"] != nil
            || error["param"] != nil else {
        return nil
    }

    let statusCode = openAIProviderStreamErrorStatusCode(code: code, type: type)
    let isInsufficientQuota = code?.stringValue == "insufficient_quota"
        || type == "insufficient_quota"
    return AIStreamProviderError(
        message: message,
        type: type,
        code: code,
        statusCode: statusCode,
        isRetryable: isInsufficientQuota
            ? false
            : statusCode == 408 || statusCode == 409 || statusCode == 429 || statusCode >= 500,
        data: frame
    )
}

func openAIProviderStreamAPICallError(
    _ error: AIStreamProviderError,
    providerID: String
) -> AIError {
    .apiCall(AIAPICallError(
        provider: providerID,
        statusCode: error.statusCode ?? 500,
        responseBody: error.message,
        isRetryable: error.isRetryable
    ))
}

private func openAIProviderStreamErrorStatusCode(code: JSONValue?, type: String?) -> Int {
    if let explicitStatusCode = openAIProviderHTTPStatusCode(code) {
        return explicitStatusCode
    }

    let discriminator = [code?.stringValue, type]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    if discriminator.contains("insufficient_quota") || discriminator.contains("rate_limit") {
        return 429
    }
    if discriminator.contains("authentication") { return 401 }
    if discriminator.contains("permission") { return 403 }
    if discriminator.contains("not_found") { return 404 }
    if discriminator.contains("invalid")
        || discriminator.contains("bad_request")
        || discriminator.contains("context_length") {
        return 400
    }
    if discriminator.contains("overload") { return 503 }
    if discriminator.contains("timeout") { return 504 }
    return 500
}

private func openAIProviderHTTPStatusCode(_ value: JSONValue?) -> Int? {
    if case let .number(number)? = value,
       number.isFinite,
       number.rounded(.towardZero) == number,
       (400.0...599.0).contains(number) {
        return Int(number)
    }
    if let string = value?.stringValue,
              string.count == 3,
              string.allSatisfy(\.isNumber),
       let statusCode = Int(string),
       400...599 ~= statusCode {
        return statusCode
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
    openAIResponsesMoveKey("logitBias", to: "logit_bias", in: &output)
    openAIResponsesMoveKey("parallelToolCalls", to: "parallel_tool_calls", in: &output)
    openAIResponsesMoveKey("maxCompletionTokens", to: "max_completion_tokens", in: &output)
    openAIResponsesMoveKey("serviceTier", to: "service_tier", in: &output)
    openAIResponsesMoveKey("promptCacheKey", to: "prompt_cache_key", in: &output)
    openAIResponsesMoveKey("promptCacheOptions", to: "prompt_cache_options", in: &output)
    openAIResponsesMoveKey("promptCacheRetention", to: "prompt_cache_retention", in: &output)
    openAIResponsesMoveKey("safetyIdentifier", to: "safety_identifier", in: &output)
    if let logprobs = output["logprobs"] {
        if let count = logprobs.intValue, logprobs.doubleValue == Double(count) {
            output["logprobs"] = .bool(true)
            output["top_logprobs"] = .number(Double(count))
        } else if logprobs.boolValue == true {
            output["top_logprobs"] = output["top_logprobs"] ?? .number(0)
        } else if logprobs.boolValue == false {
            output.removeValue(forKey: "logprobs")
            output.removeValue(forKey: "top_logprobs")
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
    let isOpenAIBacked = openAIBackedProviderRoot != nil || isOpenAIBackedProvider(providerID)
    var warnings: [AIWarning] = []
    if !isOpenAIBacked {
        if usesGenericProviderOptions {
            warnings.append(contentsOf: openAICompatibleProviderOptionWarnings(providerOptions: request.providerOptions, extraBody: request.extraBody, providerID: providerID, includeCompatibilityNamespace: true))
        } else {
            warnings.append(contentsOf: openAICompatibleProviderOptionWarnings(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: true))
        }
    }
    if isOpenAIBacked, request.topK != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "topK"))
    }
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

func openAICompatibleResponseFormatJSON(_ responseFormat: AIResponseFormat?) -> JSONValue? {
    guard let responseFormat else { return nil }
    switch responseFormat {
    case .text:
        return nil
    case let .json(schema, name, description):
        var output: [String: JSONValue] = ["type": .string("json")]
        if let schema {
            output["schema"] = schema
        }
        if let name {
            output["name"] = .string(name)
        }
        if let description {
            output["description"] = .string(description)
        }
        return .object(output)
    }
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

typealias OpenAICompatibleStreamingToolCalls = OpenAIStyleStreamingToolCalls

func openAICompatibleChatToolCalls(
    from value: JSONValue?,
    providerMetadataNamespace: String? = nil
) -> [AIToolCall] {
    value?.arrayValue?.enumerated().compactMap { index, item in
        guard let name = item["function"]?["name"]?.stringValue else { return nil }
        var providerMetadata: [String: JSONValue] = [:]
        if let providerMetadataNamespace,
           let thoughtSignature = item["extra_content"]?["google"]?["thought_signature"]?.stringValue,
           !thoughtSignature.isEmpty {
            providerMetadata[providerMetadataNamespace] = .object([
                "thoughtSignature": .string(thoughtSignature)
            ])
        }
        return AIToolCall(
            id: resolvedToolCallID(item["id"]?.stringValue, whenMissing: "tool-call-\(index)"),
            name: name,
            arguments: item["function"]?["arguments"]?.stringValue ?? "",
            providerMetadata: providerMetadata,
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
