import Foundation

public final class CerebrasLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "cerebras.chat"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try cerebrasPreparedCall(for: request, modelID: modelID, stream: false)
        let response = try await config.sendJSONResponse(
            path: "/chat/completions",
            modelID: modelID,
            body: .object(prepared.body),
            headers: request.headers,
            abortSignal: request.abortSignal
        )
        let raw = response.json
        let choice = raw["choices"]?[0]
        let toolCalls = cerebrasToolCalls(from: choice?["message"]?["tool_calls"])
        guard let text = choice?["message"]?["content"]?.stringValue ?? (toolCalls.isEmpty ? nil : "") else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in Cerebras response.")
        }
        let rawFinishReason = choice?["finish_reason"]?.stringValue
        let finishReason = cerebrasFinishReason(rawFinishReason, hasText: !text.isEmpty, body: prepared.body)
        return TextGenerationResult(
            text: text,
            reasoning: choice?["message"]?["reasoning"]?.stringValue ?? "",
            finishReason: finishReason,
            usage: cerebrasUsage(from: raw),
            toolCalls: cerebrasShouldDropStructuredToolCalls(hasText: !text.isEmpty, body: prepared.body) ? [] : toolCalls,
            providerMetadata: cerebrasProviderMetadata(from: raw, choice: choice),
            rawValue: raw,
            warnings: prepared.warnings,
            responseMetadata: cerebrasResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = try cerebrasPreparedCall(for: request, modelID: modelID, stream: true)
                    let response = try await config.transport.send(config.request(
                        path: "/chat/completions",
                        modelID: modelID,
                        body: .object(prepared.body),
                        headers: request.headers,
                        abortSignal: request.abortSignal
                    ))
                    guard (200..<300).contains(response.statusCode) else {
                        throw httpStatusError(provider: providerID, response: response)
                    }

                    continuation.yield(.streamStart(warnings: prepared.warnings))
                    var latestUsage: TokenUsage?
                    var hasText = false
                    var finishReason: String?
                    var toolCalls = CerebrasStreamingToolCalls()
                    var emittedResponseMetadata = false
                    var providerMetadata: [String: JSONValue] = [:]
                    var activeText = false
                    var activeReasoningID: String?
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        if !emittedResponseMetadata {
                            emittedResponseMetadata = true
                            continuation.yield(.responseMetadata(cerebrasResponseMetadata(from: raw, response: response, modelID: modelID)))
                        }
                        cerebrasMergeProviderMetadata(cerebrasProviderMetadata(from: raw, choice: raw["choices"]?[0]), into: &providerMetadata)
                        latestUsage = cerebrasUsage(from: raw) ?? latestUsage
                        if let reasoning = raw["choices"]?[0]?["delta"]?["reasoning"]?.stringValue, !reasoning.isEmpty {
                            if activeText {
                                continuation.yield(.textEnd(id: "0"))
                                activeText = false
                            }
                            let id = activeReasoningID ?? "reasoning-0"
                            if activeReasoningID == nil {
                                activeReasoningID = id
                                continuation.yield(.reasoningStart(id: id))
                            }
                            continuation.yield(.reasoningDeltaPart(id: id, delta: reasoning))
                        }
                        if let delta = raw["choices"]?[0]?["delta"]?["content"]?.stringValue, !delta.isEmpty {
                            hasText = true
                            if let reasoningID = activeReasoningID {
                                continuation.yield(.reasoningEnd(id: reasoningID))
                                activeReasoningID = nil
                            }
                            if !activeText {
                                continuation.yield(.textStart(id: "0"))
                                activeText = true
                            }
                            continuation.yield(.textDeltaPart(id: "0", delta: delta))
                        }
                        if let toolCallDeltas = raw["choices"]?[0]?["delta"]?["tool_calls"]?.arrayValue,
                           !cerebrasShouldDropStructuredToolCalls(hasText: hasText, body: prepared.body) {
                            for toolCallDelta in toolCallDeltas {
                                for part in toolCalls.apply(delta: toolCallDelta) {
                                    continuation.yield(part)
                                }
                            }
                        }
                        if let reason = raw["choices"]?[0]?["finish_reason"]?.stringValue {
                            finishReason = cerebrasFinishReason(reason, hasText: hasText, body: prepared.body)
                        }
                    }
                    if let reasoningID = activeReasoningID {
                        continuation.yield(.reasoningEnd(id: reasoningID))
                    }
                    if activeText {
                        continuation.yield(.textEnd(id: "0"))
                    }
                    for part in toolCalls.finishedParts() {
                        continuation.yield(part)
                    }
                    if providerMetadata.isEmpty {
                        continuation.yield(.finish(reason: finishReason, usage: latestUsage))
                    } else {
                        continuation.yield(.finishMetadata(reason: finishReason, usage: latestUsage, providerMetadata: providerMetadata))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private typealias CerebrasStreamingToolCalls = OpenAIStyleStreamingToolCalls

private struct CerebrasPreparedCall {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
}

private struct CerebrasPreparedTools {
    var tools: [JSONValue]
    var warnings: [AIWarning]
}

private func cerebrasPreparedCall(for request: LanguageModelRequest, modelID: String, stream: Bool) throws -> CerebrasPreparedCall {
    var options = try cerebrasOptions(from: request)
    let responseFormat = cerebrasResolvedResponseFormat(request: request, options: &options)
    let toolChoiceInput = request.toolChoice ?? options.removeValue(forKey: "toolChoice")
    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "messages": .array(request.messages.map(OpenAICompatibleChatModel.messageJSON))
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
            + (request.tools.isEmpty ? [] : cerebrasToolChoiceWarnings(from: toolChoiceInput))
    )
}

private func cerebrasOptions(from request: LanguageModelRequest) throws -> [String: JSONValue] {
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

private let cerebrasOpenAICompatibleOptionKeys: Set<String> = [
    "user",
    "reasoningEffort",
    "textVerbosity",
    "strictJsonSchema"
]

private func cerebrasValidateOpenAICompatibleOptions(_ options: [String: JSONValue], argumentPrefix: String) throws -> [String: JSONValue] {
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

private func cerebrasOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
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

private func cerebrasApplyKnownOptions(from options: inout [String: JSONValue], reasoning: String?, to body: inout [String: JSONValue]) {
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

private func cerebrasResolvedResponseFormat(request: LanguageModelRequest, options: inout [String: JSONValue]) -> JSONValue? {
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

private func cerebrasResponseFormatJSON(_ responseFormat: AIResponseFormat) -> JSONValue? {
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

private func cerebrasResponseFormat(from value: JSONValue, strictJsonSchema: JSONValue?) -> JSONValue {
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

private func cerebrasTools(from tools: [String: JSONValue]) -> CerebrasPreparedTools {
    var warnings: [AIWarning] = []
    let values = tools.compactMap { name, schema -> JSONValue? in
        let object = schema.objectValue
        if object?["type"]?.stringValue == "provider" || object?["id"]?.stringValue != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "provider-defined tool \(object?["id"]?.stringValue ?? name)"
            ))
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
    return CerebrasPreparedTools(tools: values, warnings: warnings)
}

private func cerebrasToolChoice(from value: JSONValue?) -> JSONValue? {
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

private func cerebrasWarnings(for request: LanguageModelRequest) -> [AIWarning] {
    (request.extraBody["openai-compatible"] == nil && request.providerOptions["openai-compatible"] == nil) ? [] : [
        AIWarning(
            type: "deprecated",
            setting: "providerOptions key 'openai-compatible'",
            message: "Use 'openaiCompatible' instead."
        )
    ]
}

private func cerebrasCallWarnings(for request: LanguageModelRequest) -> [AIWarning] {
    request.topK == nil ? [] : [AIWarning(type: "unsupported", feature: "topK")]
}

private func cerebrasToolChoiceWarnings(from value: JSONValue?) -> [AIWarning] {
    if let string = value?.stringValue {
        switch string {
        case "auto", "none", "required":
            return []
        default:
            return [AIWarning(type: "unsupported", feature: "tool choice type: \(string)")]
        }
    }
    guard let object = value?.objectValue else { return [] }
    switch object["type"]?.stringValue {
    case "auto", "none", "required", "tool":
        return []
    case let type?:
        return [AIWarning(type: "unsupported", feature: "tool choice type: \(type)")]
    case nil:
        return [AIWarning(type: "unsupported", feature: "tool choice type: undefined")]
    }
}

private func cerebrasMessageTransform(_ message: JSONValue) -> JSONValue {
    guard var object = message.objectValue,
          object["role"]?.stringValue == "assistant",
          let reasoningContent = object.removeValue(forKey: "reasoning_content") else {
        return message
    }
    if object["reasoning"] == nil, reasoningContent != .null {
        object["reasoning"] = reasoningContent
    }
    return .object(object)
}

private func cerebrasFinishReason(_ raw: String?, hasText: Bool, body: [String: JSONValue]) -> String? {
    if raw == "tool_calls", cerebrasShouldDropStructuredToolCalls(hasText: hasText, body: body) {
        return "stop"
    }
    switch raw {
    case "stop":
        return "stop"
    case "length":
        return "length"
    case "content_filter":
        return "content-filter"
    case "function_call", "tool_calls":
        return "tool-calls"
    case nil:
        return nil
    default:
        return "other"
    }
}

private func cerebrasShouldDropStructuredToolCalls(hasText: Bool, body: [String: JSONValue]) -> Bool {
    let responseFormatType = body["response_format"]?["type"]?.stringValue
    return hasText && (responseFormatType == "json_schema" || responseFormatType == "json_object" || responseFormatType == "json")
}

private func cerebrasProviderMetadata(from raw: JSONValue, choice: JSONValue?) -> [String: JSONValue] {
    var metadata: [String: JSONValue] = [:]
    if let accepted = raw["usage"]?["completion_tokens_details"]?["accepted_prediction_tokens"] {
        metadata["acceptedPredictionTokens"] = accepted
    }
    if let rejected = raw["usage"]?["completion_tokens_details"]?["rejected_prediction_tokens"] {
        metadata["rejectedPredictionTokens"] = rejected
    }
    if let logprobs = choice?["logprobs"]?["content"] {
        metadata["logprobs"] = logprobs
    }
    guard !metadata.isEmpty else { return [:] }
    return ["cerebras": .object(metadata)]
}

private func cerebrasUsage(from raw: JSONValue) -> TokenUsage? {
    guard let usage = raw["usage"] else { return nil }
    let inputTokens = usage["prompt_tokens"]?.intValue ?? usage["input_tokens"]?.intValue ?? 0
    let outputTokens = usage["completion_tokens"]?.intValue ?? usage["output_tokens"]?.intValue ?? 0
    let cacheReadTokens = usage["prompt_tokens_details"]?["cached_tokens"]?.intValue
        ?? usage["cached_tokens"]?.intValue
        ?? 0
    let reasoningTokens = usage["completion_tokens_details"]?["reasoning_tokens"]?.intValue ?? 0
    let totalTokens = usage["total_tokens"]?.intValue ?? inputTokens + outputTokens
    return TokenUsage(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: totalTokens,
        inputTokensNoCache: inputTokens - cacheReadTokens,
        inputTokensCacheRead: cacheReadTokens,
        outputTextTokens: outputTokens - reasoningTokens,
        outputReasoningTokens: reasoningTokens,
        rawValue: usage
    )
}

private func cerebrasMergeProviderMetadata(_ source: [String: JSONValue], into target: inout [String: JSONValue]) {
    for (key, value) in source {
        if case let .object(existing) = target[key],
           case let .object(incoming) = value {
            target[key] = .object(existing.merging(incoming) { _, new in new })
        } else {
            target[key] = value
        }
    }
}

private func cerebrasResponseMetadata(from raw: JSONValue? = nil, response: AIHTTPResponse, modelID: String) -> AIResponseMetadata {
    AIResponseMetadata(
        id: raw?["id"]?.stringValue,
        timestamp: raw?["created"]?.doubleValue.map { Date(timeIntervalSince1970: $0) } ?? Date(),
        modelID: raw?["model"]?.stringValue ?? modelID,
        headers: response.headers,
        body: raw
    )
}

private func cerebrasToolCalls(from value: JSONValue?) -> [AIToolCall] {
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
