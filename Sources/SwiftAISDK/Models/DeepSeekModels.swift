import Foundation

public final class DeepSeekLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "deepseek.chat"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try deepSeekPreparedCall(for: request, modelID: modelID, stream: false)
        let response = try await config.sendJSONResponse(
            path: "/chat/completions",
            modelID: modelID,
            body: .object(prepared.body),
            headers: request.headers,
            abortSignal: request.abortSignal
        )
        let raw = response.json
        let choice = raw["choices"]?[0]
        let reasoning = choice?["message"]?["reasoning_content"]?.stringValue ?? ""
        let toolCalls = deepSeekToolCalls(from: choice?["message"]?["tool_calls"])
        guard let text = choice?["message"]?["content"]?.stringValue ?? (toolCalls.isEmpty ? nil : "") else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in DeepSeek response.")
        }
        return TextGenerationResult(
            text: text,
            reasoning: reasoning,
            finishReason: deepSeekFinishReason(choice?["finish_reason"]?.stringValue),
            usage: deepSeekUsage(from: raw),
            toolCalls: toolCalls,
            providerMetadata: deepSeekProviderMetadata(from: raw),
            rawValue: raw,
            warnings: prepared.warnings,
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = try deepSeekPreparedCall(for: request, modelID: modelID, stream: true)
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
                    var finishReason: String?
                    var providerMetadata: [String: JSONValue] = [:]
                    var toolCalls = DeepSeekStreamingToolCalls()
                    var didEmitResponseMetadata = false
                    var activeReasoningID: String?
                    var activeTextID: String?
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        if !didEmitResponseMetadata {
                            didEmitResponseMetadata = true
                            continuation.yield(.responseMetadata(aiResponseMetadata(from: raw, response: response, modelID: modelID)))
                        }
                        latestUsage = deepSeekUsage(from: raw) ?? latestUsage
                        deepSeekMergeProviderMetadata(deepSeekProviderMetadata(from: raw), into: &providerMetadata)
                        if let reasoning = raw["choices"]?[0]?["delta"]?["reasoning_content"]?.stringValue, !reasoning.isEmpty {
                            let id = activeReasoningID ?? "reasoning-0"
                            if activeReasoningID == nil {
                                activeReasoningID = id
                                continuation.yield(.reasoningStart(id: id))
                            }
                            continuation.yield(.reasoningDeltaPart(id: id, delta: reasoning))
                        }
                        if let delta = raw["choices"]?[0]?["delta"]?["content"]?.stringValue, !delta.isEmpty {
                            let id = activeTextID ?? "txt-0"
                            if activeTextID == nil {
                                activeTextID = id
                                continuation.yield(.textStart(id: id))
                            }
                            if let reasoningID = activeReasoningID {
                                continuation.yield(.reasoningEnd(id: reasoningID))
                                activeReasoningID = nil
                            }
                            continuation.yield(.textDeltaPart(id: id, delta: delta))
                        }
                        if let toolCallDeltas = raw["choices"]?[0]?["delta"]?["tool_calls"]?.arrayValue {
                            if let reasoningID = activeReasoningID {
                                continuation.yield(.reasoningEnd(id: reasoningID))
                                activeReasoningID = nil
                            }
                            for toolCallDelta in toolCallDeltas {
                                for part in toolCalls.apply(delta: toolCallDelta) {
                                    continuation.yield(part)
                                }
                            }
                        }
                        if let reason = raw["choices"]?[0]?["finish_reason"]?.stringValue {
                            finishReason = deepSeekFinishReason(reason)
                        }
                    }
                    if let reasoningID = activeReasoningID {
                        continuation.yield(.reasoningEnd(id: reasoningID))
                    }
                    if let textID = activeTextID {
                        continuation.yield(.textEnd(id: textID))
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

private typealias DeepSeekStreamingToolCalls = OpenAIStyleStreamingToolCalls

private struct DeepSeekPreparedCall {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
}

private struct DeepSeekPreparedMessages {
    var messages: [JSONValue]
    var warnings: [AIWarning]
}

private struct DeepSeekPreparedTools {
    var tools: [JSONValue]
    var warnings: [AIWarning]
}

private func deepSeekPreparedCall(for request: LanguageModelRequest, modelID: String, stream: Bool) throws -> DeepSeekPreparedCall {
    var options = try deepSeekOptions(from: request)
    let responseFormat = deepSeekResolvedResponseFormat(request: request, options: &options)
    let optionToolChoice = options.removeValue(forKey: "toolChoice")
    let toolChoice = request.toolChoice ?? optionToolChoice
    let preparedMessages = deepSeekMessages(request.messages, responseFormat: responseFormat, modelID: modelID)
    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "messages": .array(preparedMessages.messages)
    ]
    if stream {
        body["stream"] = true
        body["stream_options"] = .object(["include_usage": true])
    }
    if let temperature = request.temperature { body["temperature"] = .number(temperature) }
    if let topP = request.topP { body["top_p"] = .number(topP) }
    if let frequencyPenalty = request.frequencyPenalty { body["frequency_penalty"] = .number(frequencyPenalty) }
    if let presencePenalty = request.presencePenalty { body["presence_penalty"] = .number(presencePenalty) }
    if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
    if !request.stopSequences.isEmpty { body["stop"] = .array(request.stopSequences) }
    let preparedTools = deepSeekTools(from: request.tools)
    if !preparedTools.tools.isEmpty {
        body["tools"] = .array(preparedTools.tools)
        if let toolChoice = deepSeekToolChoice(from: toolChoice) {
            body["tool_choice"] = toolChoice
        }
    }
    body.merge(options) { _, new in new }
    let reasoningWarnings = deepSeekApplyReasoning(request.reasoning, to: &body)
    if let responseFormat, responseFormat["type"]?.stringValue == "json" {
        body["response_format"] = .object(["type": .string("json_object")])
    }

    if body["thinking"]?["type"]?.stringValue == "disabled" {
        body.removeValue(forKey: "reasoning_effort")
    }
    return DeepSeekPreparedCall(
        body: body,
        warnings: preparedMessages.warnings
            + deepSeekWarnings(request: request, responseFormat: responseFormat)
            + reasoningWarnings
            + preparedTools.warnings
            + (request.tools.isEmpty ? [] : deepSeekToolChoiceWarnings(from: toolChoice))
    )
}

private func deepSeekMessages(_ messages: [AIMessage], responseFormat: JSONValue?, modelID: String) -> DeepSeekPreparedMessages {
    var output: [JSONValue] = []
    var warnings: [AIWarning] = []
    let isDeepSeekV4 = modelID.contains("deepseek-v4")

    if responseFormat?["type"]?.stringValue == "json" {
        if let schema = responseFormat?["schema"] {
            let schemaText = deepSeekJSONString(schema) ?? schema.stringValue ?? ""
            output.append(.object([
                "role": .string("system"),
                "content": .string("Return JSON that conforms to the following schema: \(schemaText)")
            ]))
        } else {
            output.append(.object([
                "role": .string("system"),
                "content": .string("Return JSON.")
            ]))
        }
    }

    for message in messages {
        switch message.role {
        case .system:
            output.append(.object([
                "role": .string("system"),
                "content": .string(message.combinedText)
            ]))
        case .user:
            var text = ""
            for part in message.content {
                if case let .text(value) = part {
                    text += value
                } else {
                    warnings.append(AIWarning(type: "unsupported", feature: deepSeekUserPartFeature(part)))
                }
            }
            output.append(.object([
                "role": .string("user"),
                "content": .string(text)
            ]))
        case .assistant:
            let toolCalls = message.content.compactMap { part -> AIToolCall? in
                if case let .toolCall(call) = part { call } else { nil }
            }
            var object: [String: JSONValue] = [
                "role": .string("assistant"),
                "content": .string(message.combinedText)
            ]
            if isDeepSeekV4 {
                object["reasoning_content"] = .string("")
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
            output.append(.object(object))
        case .tool:
            for part in message.content {
                guard case let .toolResult(result) = part else { continue }
                let value = result.modelOutput ?? result.result
                output.append(.object([
                    "role": .string("tool"),
                    "tool_call_id": .string(result.toolCallID),
                    "content": .string(deepSeekJSONString(value) ?? value.stringValue ?? "")
                ]))
            }
        }
    }

    return DeepSeekPreparedMessages(messages: output, warnings: warnings)
}

private func deepSeekUserPartFeature(_ part: AIContentPart) -> String {
    switch part {
    case .data, .file, .imageURL:
        return "user message part type: file"
    case .toolCall:
        return "user message part type: tool-call"
    case .toolResult:
        return "user message part type: tool-result"
    case .toolApprovalRequest:
        return "user message part type: tool-approval-request"
    case .toolApprovalResponse:
        return "user message part type: tool-approval-response"
    case .text:
        return "user message part type: text"
    }
}

private func deepSeekOptions(from request: LanguageModelRequest) throws -> [String: JSONValue] {
    var output = request.extraBody
    if let nested = output.removeValue(forKey: "deepseek")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    if let value = request.providerOptions["deepseek"] {
        guard value != .null else {
            deepSeekMoveKey("reasoningEffort", to: "reasoning_effort", in: &output)
            return output
        }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.deepseek", message: "DeepSeek provider options must be an object.")
        }
        for key in deepSeekProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try deepSeekValidateProviderOptions(nested)) { _, nested in nested }
    }
    deepSeekMoveKey("reasoningEffort", to: "reasoning_effort", in: &output)
    return output
}

private let deepSeekProviderOptionKeys: Set<String> = ["thinking", "reasoningEffort"]

private func deepSeekValidateProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where deepSeekProviderOptionKeys.contains(key) {
        guard value != .null else {
            throw AIError.invalidArgument(argument: "providerOptions.deepseek.\(key)", message: "DeepSeek \(key) cannot be null.")
        }
        switch key {
        case "thinking":
            guard let object = value.objectValue else {
                throw AIError.invalidArgument(argument: "providerOptions.deepseek.thinking", message: "DeepSeek thinking must be an object.")
            }
            var thinking: [String: JSONValue] = [:]
            if let type = object["type"] {
                guard type != .null else {
                    throw AIError.invalidArgument(argument: "providerOptions.deepseek.thinking.type", message: "DeepSeek thinking.type cannot be null.")
                }
                guard let typeValue = type.stringValue, ["adaptive", "enabled", "disabled"].contains(typeValue) else {
                    throw AIError.invalidArgument(argument: "providerOptions.deepseek.thinking.type", message: "DeepSeek thinking.type must be adaptive, enabled, or disabled.")
                }
                thinking["type"] = type
            }
            output[key] = .object(thinking)
        case "reasoningEffort":
            guard let effort = value.stringValue, ["low", "medium", "high", "xhigh", "max"].contains(effort) else {
                throw AIError.invalidArgument(argument: "providerOptions.deepseek.reasoningEffort", message: "DeepSeek reasoningEffort must be low, medium, high, xhigh, or max.")
            }
            output[key] = value
        default:
            break
        }
    }
    return output
}

private func deepSeekResolvedResponseFormat(request: LanguageModelRequest, options: inout [String: JSONValue]) -> JSONValue? {
    if let responseFormat = request.responseFormat {
        options.removeValue(forKey: "responseFormat")
        return deepSeekResponseFormatJSON(responseFormat)
    }
    return options.removeValue(forKey: "responseFormat")
}

private func deepSeekResponseFormatJSON(_ responseFormat: AIResponseFormat) -> JSONValue? {
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

private func deepSeekWarnings(request: LanguageModelRequest, responseFormat: JSONValue?) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.topK != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "topK"))
    }
    if request.seed != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "seed"))
    }
    if responseFormat?["type"]?.stringValue == "json",
       responseFormat?["schema"] != nil {
        warnings.append(AIWarning(
            type: "compatibility",
            feature: "responseFormat JSON schema",
            message: "JSON response schema is injected into the system message."
        ))
    }
    return warnings
}

private func deepSeekMoveKey(_ source: String, to destination: String, in values: inout [String: JSONValue]) {
    if let value = values.removeValue(forKey: source) {
        values[destination] = value
    }
}

private func deepSeekReasoningEffort(_ value: String) -> String {
    switch value {
    case "minimal":
        return "low"
    case "xhigh":
        return "max"
    default:
        return value
    }
}

private func deepSeekApplyReasoning(_ reasoning: String?, to body: inout [String: JSONValue]) -> [AIWarning] {
    guard let reasoning, body["thinking"] == nil else { return [] }
    if reasoning == "none" {
        body["thinking"] = .object(["type": .string("disabled")])
        body.removeValue(forKey: "reasoning_effort")
        return []
    }
    body["thinking"] = .object(["type": .string("enabled")])
    var warnings: [AIWarning] = []
    if body["reasoning_effort"] == nil,
       let effort = deepSeekReasoningEffort(from: reasoning) {
        body["reasoning_effort"] = .string(effort)
        if effort != reasoning {
            warnings.append(AIWarning(
                type: "compatibility",
                feature: "reasoning",
                message: "reasoning \"\(reasoning)\" is not directly supported by this model. mapped to effort \"\(effort)\"."
            ))
        }
    }
    return warnings
}

private func deepSeekReasoningEffort(from reasoning: String) -> String? {
    switch reasoning {
    case "minimal", "low":
        return "low"
    case "medium":
        return "medium"
    case "high":
        return "high"
    case "xhigh":
        return "max"
    default:
        return nil
    }
}

private func deepSeekTools(from tools: [String: JSONValue]) -> DeepSeekPreparedTools {
    var warnings: [AIWarning] = []
    let values: [JSONValue] = tools.compactMap { name, schema in
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
    return DeepSeekPreparedTools(tools: values, warnings: warnings)
}

private func deepSeekToolChoice(from value: JSONValue?) -> JSONValue? {
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

private func deepSeekToolChoiceWarnings(from value: JSONValue?) -> [AIWarning] {
    guard let value else { return [] }
    if let string = value.stringValue {
        switch string {
        case "auto", "none", "required":
            return []
        default:
            return [AIWarning(type: "unsupported", feature: "tool choice type: \(string)")]
        }
    }
    guard let object = value.objectValue else { return [] }
    let type = object["type"]?.stringValue
    switch type {
    case "auto", "none", "required":
        return []
    case "tool":
        return (object["toolName"]?.stringValue ?? object["tool_name"]?.stringValue) == nil
            ? [AIWarning(type: "unsupported", feature: "tool choice type: tool")]
            : []
    case let type?:
        return [AIWarning(type: "unsupported", feature: "tool choice type: \(type)")]
    case nil:
        return [AIWarning(type: "unsupported", feature: "tool choice type: undefined")]
    }
}

private func deepSeekJSONString(_ value: JSONValue) -> String? {
    guard let data = try? encodeJSONBody(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

private func deepSeekUsage(from raw: JSONValue) -> TokenUsage? {
    guard let usage = raw["usage"] else { return nil }
    let inputTokens = usage["prompt_tokens"]?.intValue ?? usage["input_tokens"]?.intValue ?? 0
    let outputTokens = usage["completion_tokens"]?.intValue ?? usage["output_tokens"]?.intValue ?? 0
    let cacheReadTokens = usage["prompt_cache_hit_tokens"]?.intValue ?? 0
    let reasoningTokens = usage["completion_tokens_details"]?["reasoning_tokens"]?.intValue ?? 0
    let totalTokens = usage["total_tokens"]?.intValue ?? inputTokens + outputTokens
    return TokenUsage(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: totalTokens,
        inputTokensNoCache: inputTokens - cacheReadTokens,
        inputTokensCacheRead: cacheReadTokens,
        inputTokensCacheWrite: nil,
        outputTextTokens: outputTokens - reasoningTokens,
        outputReasoningTokens: reasoningTokens,
        rawValue: usage
    )
}

private func deepSeekToolCalls(from value: JSONValue?) -> [AIToolCall] {
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

private func deepSeekFinishReason(_ reason: String?) -> String? {
    switch reason {
    case "stop":
        return "stop"
    case "length":
        return "length"
    case "content_filter":
        return "content-filter"
    case "tool_calls":
        return "tool-calls"
    case "insufficient_system_resource":
        return "error"
    case nil:
        return nil
    default:
        return "other"
    }
}

private func deepSeekProviderMetadata(from raw: JSONValue) -> [String: JSONValue] {
    var metadata: [String: JSONValue] = [:]
    if let hit = raw["usage"]?["prompt_cache_hit_tokens"] {
        metadata["promptCacheHitTokens"] = hit
    }
    if let miss = raw["usage"]?["prompt_cache_miss_tokens"] {
        metadata["promptCacheMissTokens"] = miss
    }
    guard !metadata.isEmpty else { return [:] }
    return ["deepseek": .object(metadata)]
}

private func deepSeekMergeProviderMetadata(_ source: [String: JSONValue], into target: inout [String: JSONValue]) {
    for (key, value) in source {
        if case let .object(existing) = target[key],
           case let .object(incoming) = value {
            target[key] = .object(existing.merging(incoming) { _, new in new })
        } else {
            target[key] = value
        }
    }
}
