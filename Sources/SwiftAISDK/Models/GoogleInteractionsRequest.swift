import Foundation

func googleInteractionsHeaders(_ requestHeaders: [String: String]) -> [String: String] {
    ["Api-Revision": "2026-05-20"].mergingHeaders(requestHeaders)
}

struct GoogleInteractionsPreparedCall {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
}

func googleInteractionsPreparedCall(for request: LanguageModelRequest, modelID: String, agent: String?, stream: Bool) throws -> GoogleInteractionsPreparedCall {
    var options = googleGenerateContentOptions(from: request.extraBody)
    let callResponseFormat = googleInteractionsResolvedCallResponseFormat(request: request, options: &options)
    let providerResponseFormat = options.removeValue(forKey: "responseFormat")
    let systemInstruction = request.messages
        .filter { $0.role == .system }
        .map(\.combinedText)
        .joined(separator: "\n\n")
    let input = try request.messages
        .filter { $0.role != .system }
        .compactMap { try googleInteractionsStep($0) }

    var body: [String: JSONValue] = [
        agent == nil ? "model" : "agent": .string(agent ?? modelID),
        "input": .array(input)
    ]
    if stream, agent == nil {
        body["stream"] = true
    }
    if !systemInstruction.isEmpty {
        body["system_instruction"] = .string(systemInstruction)
    }
    if agent == nil {
        var generationConfig: [String: JSONValue] = [:]
        if let temperature = request.temperature { generationConfig["temperature"] = .number(temperature) }
        if let topP = request.topP { generationConfig["top_p"] = .number(topP) }
        if let maxOutputTokens = request.maxOutputTokens { generationConfig["max_output_tokens"] = .number(Double(maxOutputTokens)) }
        if !request.stopSequences.isEmpty { generationConfig["stop_sequences"] = .array(request.stopSequences) }
        if let thinkingLevel = request.extraBody["thinkingLevel"] { generationConfig["thinking_level"] = thinkingLevel }
        if let thinkingSummaries = request.extraBody["thinkingSummaries"] { generationConfig["thinking_summaries"] = thinkingSummaries }
        if !generationConfig.isEmpty {
            body["generation_config"] = .object(generationConfig)
        }
    }
    body.merge(googleInteractionsOptions(from: options, callResponseFormat: callResponseFormat, providerResponseFormat: providerResponseFormat, isAgent: agent != nil)) { _, new in new }
    return GoogleInteractionsPreparedCall(
        body: body,
        warnings: googleInteractionsWarnings(callResponseFormat: callResponseFormat, isAgent: agent != nil)
    )
}

func googleInteractionsStep(_ message: AIMessage) throws -> JSONValue? {
    switch message.role {
    case .user:
        let content = try googleInteractionsContent(message.content)
        return content.isEmpty ? nil : .object(["type": .string("user_input"), "content": .array(content)])
    case .assistant:
        let content = try googleInteractionsContent(message.content)
        return content.isEmpty ? nil : .object(["type": .string("model_output"), "content": .array(content)])
    case .tool:
        return message.combinedText.isEmpty ? nil : .object([
            "type": .string("user_input"),
            "content": .array([.object(["type": .string("text"), "text": .string(message.combinedText)])])
        ])
    case .system:
        return nil
    }
}

func googleInteractionsContent(_ content: [AIContentPart]) throws -> [JSONValue] {
    try content.map { part in
        switch part {
        case let .text(text, _):
            return .object(["type": .string("text"), "text": .string(text)])
        case let .reasoning(text, _):
            return .object(["type": .string("text"), "text": .string(text)])
        case let .imageURL(url, _):
            return .object(["type": .string("image"), "uri": .string(url)])
        case let .data(mimeType, data, _), let .file(mimeType, data, _, _):
            let resolvedMimeType = try resolveFullMediaType(mediaType: mimeType, data: data)
            let topLevel = resolvedMimeType.split(separator: "/").first.map(String.init) ?? "document"
            let type = ["image", "audio", "video"].contains(topLevel) ? topLevel : "document"
            return .object([
                "type": .string(type),
                "mime_type": .string(resolvedMimeType),
                "data": .string(data.base64EncodedString())
            ])
        case let .providerReference(mimeType, reference, _, _):
            let topLevel = mimeType.split(separator: "/").first.map(String.init) ?? "document"
            let type = ["image", "audio", "video"].contains(topLevel) ? topLevel : "document"
            return .object([
                "type": .string(type),
                "mime_type": .string(mimeType),
                "uri": .string((try? resolveProviderReference(reference, provider: "google")) ?? reference.values.first ?? "")
            ])
        case let .toolCall(call):
            return .object([
                "type": .string("function_call"),
                "name": .string(call.name),
                "arguments": googleToolArguments(call.arguments)
            ])
        case let .toolResult(result):
            return .object([
                "type": .string("function_response"),
                "name": .string(result.toolName),
                "response": result.modelOutput ?? result.result
            ])
        case .reasoningFile, .custom, .toolApprovalRequest, .toolApprovalResponse:
            return .object(["type": .string("text"), "text": .string("")])
        }
    }
}

func googleInteractionsOptions(from extraBody: [String: JSONValue], callResponseFormat: JSONValue?, providerResponseFormat: JSONValue?, isAgent: Bool) -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    if let previousInteractionId = extraBody["previousInteractionId"] { output["previous_interaction_id"] = previousInteractionId }
    if let serviceTier = extraBody["serviceTier"] { output["service_tier"] = serviceTier }
    if let store = extraBody["store"] { output["store"] = store }
    if let background = extraBody["background"] { output["background"] = background }
    if let responseModalities = extraBody["responseModalities"] { output["response_modalities"] = responseModalities }
    let responseFormat = googleInteractionsResponseFormat(callResponseFormat: callResponseFormat, providerResponseFormat: providerResponseFormat, isAgent: isAgent)
    if !responseFormat.isEmpty {
        output["response_format"] = .array(responseFormat)
    }
    if isAgent, let agentConfig = extraBody["agentConfig"] { output["agent_config"] = googleInteractionsSnakeCaseObject(agentConfig) }
    if isAgent, let environment = extraBody["environment"] { output["environment"] = googleInteractionsSnakeCaseObject(environment) }
    return output
}

func googleInteractionsResolvedCallResponseFormat(request: LanguageModelRequest, options: inout [String: JSONValue]) -> JSONValue? {
    if let responseFormat = request.responseFormat {
        if googleInteractionsIsCallResponseFormat(options["responseFormat"]) {
            options.removeValue(forKey: "responseFormat")
        }
        return googleInteractionsResponseFormatJSON(responseFormat)
    }
    guard googleInteractionsIsCallResponseFormat(options["responseFormat"]) else {
        return nil
    }
    return options.removeValue(forKey: "responseFormat")
}

func googleInteractionsIsCallResponseFormat(_ value: JSONValue?) -> Bool {
    guard let type = value?.objectValue?["type"]?.stringValue else { return false }
    return type == "json" || type == "text"
}

func googleInteractionsResponseFormatJSON(_ responseFormat: AIResponseFormat) -> JSONValue? {
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

func googleInteractionsResponseFormat(callResponseFormat: JSONValue?, providerResponseFormat: JSONValue?, isAgent: Bool) -> [JSONValue] {
    var entries: [JSONValue] = []
    if !isAgent, callResponseFormat?["type"]?.stringValue == "json" {
        var entry: [String: JSONValue] = [
            "type": .string("text"),
            "mime_type": .string("application/json")
        ]
        if let schema = callResponseFormat?["schema"] {
            entry["schema"] = schema
        }
        entries.append(.object(entry))
    }
    if let providerResponseFormat {
        if let providerEntries = providerResponseFormat.arrayValue {
            entries.append(contentsOf: providerEntries.map(googleInteractionsSnakeCaseObject))
        } else {
            entries.append(googleInteractionsSnakeCaseObject(providerResponseFormat))
        }
    }
    return entries
}

func googleInteractionsWarnings(callResponseFormat: JSONValue?, isAgent: Bool) -> [AIWarning] {
    guard isAgent, callResponseFormat?["type"]?.stringValue == "json" else { return [] }
    return [
        AIWarning(
            type: "other",
            message: "google.interactions: structured output (responseFormat) is not supported when an agent is set; responseFormat will be ignored."
        )
    ]
}

func googleInteractionsSnakeCaseObject(_ value: JSONValue) -> JSONValue {
    guard let object = value.objectValue else { return value }
    var converted: [String: JSONValue] = [:]
    for (key, value) in object {
        let mappedKey: String
        switch key {
        case "mimeType": mappedKey = "mime_type"
        case "aspectRatio": mappedKey = "aspect_ratio"
        case "imageSize": mappedKey = "image_size"
        case "thinkingSummaries": mappedKey = "thinking_summaries"
        case "collaborativePlanning": mappedKey = "collaborative_planning"
        default: mappedKey = key
        }
        converted[mappedKey] = googleInteractionsSnakeCaseObject(value)
    }
    return .object(converted)
}
