import Foundation

func cerebrasHTTPStatusError(response: AIHTTPResponse) -> AIError {
    let body = cerebrasErrorMessage(from: response.body) ?? response.bodyText
    guard !response.headers.isEmpty else {
        return .apiCall(provider: "cerebras.chat", statusCode: response.statusCode, body: body)
    }
    return .apiCall(
        provider: "cerebras.chat",
        statusCode: response.statusCode,
        body: body,
        headers: response.headers
    )
}

func cerebrasErrorMessage(from data: Data) -> String? {
    guard let json = try? decodeJSONBody(data) else { return nil }
    return json["message"]?.stringValue ?? json["error"]?["message"]?.stringValue
}

func cerebrasStreamError(from raw: JSONValue) -> (message: String, rawValue: JSONValue)? {
    if let message = raw["message"]?.stringValue,
       raw["type"] != nil || raw["code"] != nil || raw["param"] != nil {
        return (message, raw)
    }
    if let error = raw["error"] {
        return (
            error["message"]?.stringValue ?? cerebrasJSONString(error) ?? "Cerebras stream error.",
            error
        )
    }
    return nil
}

func cerebrasJSONString(_ value: JSONValue) -> String? {
    guard let data = try? encodeJSONBody(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

func cerebrasPreparedCall(for request: LanguageModelRequest, modelID: String, stream: Bool) throws -> CerebrasPreparedCall {
    var options = try cerebrasOptions(from: request)
    let responseFormat = cerebrasResolvedResponseFormat(request: request, options: &options)
    let toolChoiceInput = request.toolChoice ?? options.removeValue(forKey: "toolChoice")
    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "messages": .array(try request.messages.map { try OpenAICompatibleChatModel.messageJSON($0, providerID: "cerebras") })
    ]
    if stream { body["stream"] = true }
    if let temperature = request.temperature { body["temperature"] = .number(temperature) }
    if let topP = request.topP { body["top_p"] = .number(topP) }
    if let frequencyPenalty = request.frequencyPenalty { body["frequency_penalty"] = .number(frequencyPenalty) }
    if let presencePenalty = request.presencePenalty { body["presence_penalty"] = .number(presencePenalty) }
    if let seed = request.seed { body["seed"] = .number(Double(seed)) }
    if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
    if !request.stopSequences.isEmpty { body["stop"] = .array(request.stopSequences) }
    let preparedTools = cerebrasTools(from: request.tools)
    if !preparedTools.tools.isEmpty {
        body["tools"] = .array(preparedTools.tools)
        if let toolChoice = cerebrasToolChoice(from: toolChoiceInput) {
            body["tool_choice"] = toolChoice
        }
    }
    if let responseFormat {
        body["response_format"] = cerebrasResponseFormat(from: responseFormat, strictJsonSchema: options.removeValue(forKey: "strictJsonSchema"))
    } else {
        options.removeValue(forKey: "strictJsonSchema")
    }
    cerebrasApplyKnownOptions(from: &options, reasoning: request.reasoning, to: &body)
    body.merge(options) { _, new in new }

    if let messages = body["messages"]?.arrayValue {
        body["messages"] = .array(messages.map(cerebrasMessageTransform))
    }
    return CerebrasPreparedCall(
        body: body,
        warnings: cerebrasWarnings(for: request)
            + cerebrasCallWarnings(for: request)
            + preparedTools.warnings
            + (request.tools.isEmpty ? [] : cerebrasToolChoiceWarnings(from: toolChoiceInput)),
        normalizesStructuredToolCalls: cerebrasUsesStandardJSONResponseFormat(request.responseFormat)
    )
}

func cerebrasOptions(from request: LanguageModelRequest) throws -> [String: JSONValue] {
    var output = cerebrasOptions(from: request.extraBody)
    for key in ["openai-compatible", "openaiCompatible", "cerebras"] {
        guard let value = request.providerOptions[key] else { continue }
        guard value != .null else { continue }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.\(key)", message: "Cerebras provider options must be an object.")
        }
        let known = try cerebrasValidateOpenAICompatibleOptions(nested, argumentPrefix: "providerOptions.\(key)")
        let passthrough = nested.filter { !cerebrasOpenAICompatibleOptionKeys.contains($0.key) }
        output.merge(passthrough) { _, nested in nested }
        output.merge(known) { _, nested in nested }
    }
    return output
}

let cerebrasOpenAICompatibleOptionKeys: Set<String> = [
    "user",
    "reasoningEffort",
    "textVerbosity",
    "strictJsonSchema"
]

func cerebrasValidateOpenAICompatibleOptions(_ options: [String: JSONValue], argumentPrefix: String) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for key in cerebrasOpenAICompatibleOptionKeys {
        guard let value = options[key] else { continue }
        guard value != .null else {
            throw AIError.invalidArgument(argument: "\(argumentPrefix).\(key)", message: "Cerebras \(key) cannot be null.")
        }
        switch key {
        case "user", "reasoningEffort", "textVerbosity":
            guard value.stringValue != nil else {
                throw AIError.invalidArgument(argument: "\(argumentPrefix).\(key)", message: "Cerebras \(key) must be a string.")
            }
        case "strictJsonSchema":
            guard value.boolValue != nil else {
                throw AIError.invalidArgument(argument: "\(argumentPrefix).strictJsonSchema", message: "Cerebras strictJsonSchema must be a boolean.")
            }
        default:
            break
        }
        output[key] = value
    }
    return output
}

func cerebrasOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let compatible = output.removeValue(forKey: "openaiCompatible")?.objectValue {
        output.merge(compatible) { _, nested in nested }
    }
    if let deprecated = output.removeValue(forKey: "openai-compatible")?.objectValue {
        output.merge(deprecated) { _, nested in nested }
    }
    if let nested = output.removeValue(forKey: "cerebras")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

func cerebrasApplyKnownOptions(from options: inout [String: JSONValue], reasoning: String?, to body: inout [String: JSONValue]) {
    if let user = options.removeValue(forKey: "user") {
        body["user"] = user
    }
    if let effort = options.removeValue(forKey: "reasoningEffort") {
        body["reasoning_effort"] = effort
    }
    if let verbosity = options.removeValue(forKey: "textVerbosity") {
        body["verbosity"] = verbosity
    }
    if let reasoning, reasoning != "none", body["reasoning_effort"] == nil {
        body["reasoning_effort"] = .string(reasoning)
    }
}

func cerebrasResolvedResponseFormat(request: LanguageModelRequest, options: inout [String: JSONValue]) -> JSONValue? {
    if let responseFormat = request.responseFormat {
        options.removeValue(forKey: "responseFormat")
        options.removeValue(forKey: "response_format")
        return cerebrasResponseFormatJSON(responseFormat)
    }
    if let responseFormat = options.removeValue(forKey: "responseFormat") {
        return responseFormat
    }
    return options.removeValue(forKey: "response_format")
}

func cerebrasResponseFormatJSON(_ responseFormat: AIResponseFormat) -> JSONValue? {
    switch responseFormat {
    case .text:
        return nil
    case let .json(schema, name, description):
        return .object([
            "type": .string("json"),
            "schema": schema,
            "name": name.map(JSONValue.string),
            "description": description.map(JSONValue.string)
        ])
    }
}

func cerebrasResponseFormat(from value: JSONValue, strictJsonSchema: JSONValue?) -> JSONValue {
    guard let object = value.objectValue, object["type"]?.stringValue == "json" else {
        return value
    }
    guard let schema = object["schema"] else {
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
