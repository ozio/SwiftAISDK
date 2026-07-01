import Foundation

func groqPreparedCall(for request: LanguageModelRequest, modelID: String, stream: Bool) throws -> GroqPreparedCall {
    var options = try groqProviderOptions(from: request)
    let responseFormat = groqResolvedResponseFormat(request: request, options: &options)
    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "messages": .array(try request.messages.flatMap(groqMessageJSON))
    ]
    if stream { body["stream"] = true }
    if let temperature = request.temperature { body["temperature"] = .number(temperature) }
    if let topP = request.topP { body["top_p"] = .number(topP) }
    if let frequencyPenalty = request.frequencyPenalty { body["frequency_penalty"] = .number(frequencyPenalty) }
    if let presencePenalty = request.presencePenalty { body["presence_penalty"] = .number(presencePenalty) }
    if let seed = request.seed { body["seed"] = .number(Double(seed)) }
    if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
    if !request.stopSequences.isEmpty { body["stop"] = .array(request.stopSequences) }
    let preparedTools = groqTools(from: request.tools, modelID: modelID)
    if !preparedTools.tools.isEmpty {
        body["tools"] = .array(preparedTools.tools)
        if let toolChoice = groqToolChoice(from: request.toolChoice ?? options["toolChoice"]) {
            body["tool_choice"] = toolChoice
        }
    }
    if let responseFormat {
        body["response_format"] = groqResponseFormat(from: responseFormat, options: options)
    }
    body.merge(groqLanguageOptions(from: options)) { _, new in new }
    groqApplyReasoning(request.reasoning, to: &body)
    return GroqPreparedCall(
        body: body,
        warnings: groqWarnings(request: request, responseFormat: responseFormat, options: options) + preparedTools.warnings
    )
}

func groqLanguageOptions(from options: [String: JSONValue]) -> [String: JSONValue] {
    var output = options
    moveKey("reasoningFormat", to: "reasoning_format", in: &output)
    moveKey("reasoningEffort", to: "reasoning_effort", in: &output)
    moveKey("parallelToolCalls", to: "parallel_tool_calls", in: &output)
    moveKey("serviceTier", to: "service_tier", in: &output)
    output.removeValue(forKey: "responseFormat")
    output.removeValue(forKey: "structuredOutputs")
    output.removeValue(forKey: "strictJsonSchema")
    output.removeValue(forKey: "toolChoice")
    if let effort = output["reasoning_effort"]?.stringValue {
        output["reasoning_effort"] = .string(groqReasoningEffort(effort))
    }
    return output
}

func groqResolvedResponseFormat(request: LanguageModelRequest, options: inout [String: JSONValue]) -> JSONValue? {
    if let responseFormat = request.responseFormat {
        options.removeValue(forKey: "responseFormat")
        return groqResponseFormatJSON(responseFormat)
    }
    return options.removeValue(forKey: "responseFormat")
}

func groqResponseFormatJSON(_ responseFormat: AIResponseFormat) -> JSONValue? {
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

func groqResponseFormat(from value: JSONValue, options: [String: JSONValue]) -> JSONValue {
    guard let object = value.objectValue, object["type"]?.stringValue == "json" else {
        return value
    }
    let structuredOutputs = options["structuredOutputs"]?.boolValue ?? true
    guard structuredOutputs, let schema = object["schema"] else {
        return .object(["type": .string("json_object")])
    }
    let strict = options["strictJsonSchema"] ?? .bool(true)
    var jsonSchema: [String: JSONValue] = [
        "schema": schema,
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

func groqWarnings(request: LanguageModelRequest, responseFormat: JSONValue?, options: [String: JSONValue]) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.topK != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "topK"))
    }
    if responseFormat?["type"]?.stringValue == "json",
       responseFormat?["schema"] != nil,
       options["structuredOutputs"]?.boolValue == false {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "responseFormat",
            message: "JSON response format schema is only supported with structuredOutputs"
        ))
    }
    return warnings
}

func groqMessageJSON(_ message: AIMessage) throws -> [JSONValue] {
    switch message.role {
    case .system:
        return [.object(["role": .string("system"), "content": .string(message.combinedText)])]
    case .user:
        if message.content.count == 1, case let .text(text, _) = message.content[0] {
            return [.object(["role": .string("user"), "content": .string(text)])]
        }
        return [.object([
            "role": .string("user"),
            "content": .array(try message.content.map(groqUserContentPart))
        ])]
    case .assistant:
        var object: [String: JSONValue] = [
            "role": .string("assistant"),
            "content": .string(groqText(from: message))
        ]
        if let reasoning = message.reasoning, !reasoning.isEmpty {
            object["reasoning"] = .string(reasoning)
        }
        let toolCalls = message.content.compactMap { part -> AIToolCall? in
            if case let .toolCall(call) = part { call } else { nil }
        }
        if !toolCalls.isEmpty {
            object["tool_calls"] = .array(toolCalls.map { call in
                .object([
                    "id": .string(call.id),
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(call.name),
                        "arguments": .string(call.arguments)
                    ])
                ])
            })
        }
        return [.object(object)]
    case .tool:
        return message.content.compactMap { part in
            guard case let .toolResult(result) = part else { return nil }
            let value = result.modelOutput ?? result.result
            return .object([
                "role": .string("tool"),
                "tool_call_id": .string(result.toolCallID),
                "content": .string(groqJSONString(value) ?? value.stringValue ?? "")
            ])
        }
    }
}

func groqUserContentPart(_ part: AIContentPart) throws -> JSONValue {
    switch part {
    case let .text(text, _):
        return .object(["type": .string("text"), "text": .string(text)])
    case let .reasoning(text, _):
        return .object(["type": .string("text"), "text": .string(text)])
    case let .imageURL(url, _):
        return .object(["type": .string("image_url"), "image_url": .object(["url": .string(url)])])
    case let .data(mimeType, data, _), let .file(mimeType, data, _, _):
        guard mimeType.hasPrefix("image/") else {
            throw AIError.invalidArgument(argument: "files", message: "Groq chat API only supports image file parts; got \(mimeType).")
        }
        let mediaType = mimeType == "image/*" ? "image/jpeg" : mimeType
        return .object([
            "type": .string("image_url"),
            "image_url": .object(["url": .string("data:\(mediaType);base64,\(data.base64EncodedString())")])
        ])
    case .providerReference:
        throw AIError.invalidArgument(argument: "files", message: "Groq chat API only supports image URL and inline image file parts.")
    case .reasoningFile, .custom, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
        throw AIError.invalidArgument(argument: "messages", message: "Groq user messages only support text and image file parts.")
    }
}

func groqText(from message: AIMessage) -> String {
    message.content.compactMap(\.text).joined()
}

func groqJSONString(_ value: JSONValue) -> String? {
    guard let data = try? encodeJSONBody(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

func groqTools(from tools: [String: JSONValue], modelID: String) -> GroqPreparedTools {
    var warnings: [AIWarning] = []
    let values: [JSONValue] = tools.compactMap { name, schema in
        let object = schema.objectValue
        let providerToolID = object?["id"]?.stringValue
        if object?["type"]?.stringValue == "provider" || providerToolID != nil || name == "groq.browser_search" {
            guard (providerToolID ?? name) == "groq.browser_search",
                  groqBrowserSearchSupportedModels.contains(modelID) else {
                warnings.append(AIWarning(
                    type: "unsupported",
                    feature: "provider-defined tool \(providerToolID ?? name)"
                ))
                return nil
            }
            return .object(["type": .string("browser_search")])
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
    return GroqPreparedTools(tools: values, warnings: warnings)
}

func groqToolChoice(from value: JSONValue?) -> JSONValue? {
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

func groqToolCalls(from value: JSONValue?) -> [AIToolCall] {
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

func groqFinishReason(_ reason: String?) -> String? {
    switch reason {
    case "stop":
        return "stop"
    case "length":
        return "length"
    case "content_filter":
        return "content-filter"
    case "function_call", "tool_calls":
        return "tool-calls"
    default:
        return "other"
    }
}

let groqBrowserSearchSupportedModels: Set<String> = [
    "openai/gpt-oss-20b",
    "openai/gpt-oss-120b"
]

func groqReasoningEffort(_ value: String) -> String {
    switch value {
    case "minimal":
        return "low"
    case "xhigh":
        return "high"
    default:
        return value
    }
}

func groqApplyReasoning(_ reasoning: String?, to body: inout [String: JSONValue]) {
    guard let reasoning,
          reasoning != "none",
          body["reasoning_effort"] == nil else {
        return
    }
    body["reasoning_effort"] = .string(groqReasoningEffort(reasoning))
}
