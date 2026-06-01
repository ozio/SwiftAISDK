import Foundation

public enum GroqTools {
    public static func browserSearch() -> JSONValue {
        .object([
            "type": .string("provider"),
            "id": .string("groq.browser_search"),
            "name": .string("browser_search"),
            "args": .object([:])
        ])
    }
}

public final class GroqLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "groq.chat"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = groqPreparedCall(for: request, modelID: modelID, stream: false)
        let response = try await config.sendJSONResponse(
            path: "/chat/completions",
            modelID: modelID,
            body: .object(prepared.body),
            headers: request.headers,
            abortSignal: request.abortSignal
        )
        let raw = response.json
        let choice = raw["choices"]?[0]
        let toolCalls = groqToolCalls(from: choice?["message"]?["tool_calls"])
        guard let text = choice?["message"]?["content"]?.stringValue ?? (toolCalls.isEmpty ? nil : "") else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in Groq response.")
        }
        return TextGenerationResult(
            text: text,
            reasoning: choice?["message"]?["reasoning"]?.stringValue ?? "",
            finishReason: groqFinishReason(choice?["finish_reason"]?.stringValue),
            usage: tokenUsage(from: raw),
            toolCalls: toolCalls,
            rawValue: raw,
            warnings: prepared.warnings,
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = groqPreparedCall(for: request, modelID: modelID, stream: true)
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
                    var toolCalls = GroqStreamingToolCalls()
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
                        latestUsage = tokenUsage(from: raw["x_groq"] ?? raw) ?? tokenUsage(from: raw) ?? latestUsage
                        if let reasoning = raw["choices"]?[0]?["delta"]?["reasoning"]?.stringValue, !reasoning.isEmpty {
                            let id = activeReasoningID ?? "reasoning-0"
                            if activeReasoningID == nil {
                                activeReasoningID = id
                                continuation.yield(.reasoningStart(id: id))
                            }
                            continuation.yield(.reasoningDeltaPart(id: id, delta: reasoning))
                        }
                        if let delta = raw["choices"]?[0]?["delta"]?["content"]?.stringValue, !delta.isEmpty {
                            if let reasoningID = activeReasoningID {
                                continuation.yield(.reasoningEnd(id: reasoningID))
                                activeReasoningID = nil
                            }
                            let id = activeTextID ?? "txt-0"
                            if activeTextID == nil {
                                activeTextID = id
                                continuation.yield(.textStart(id: id))
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
                            finishReason = groqFinishReason(reason)
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
                    continuation.yield(.finish(reason: finishReason, usage: latestUsage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private typealias GroqStreamingToolCalls = OpenAIStyleStreamingToolCalls

private struct GroqPreparedCall {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
}

private struct GroqPreparedTools {
    var tools: [JSONValue]
    var warnings: [AIWarning]
}

public final class GroqTranscriptionModel: TranscriptionModel, @unchecked Sendable {
    public let providerID = "groq.transcription"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        var form = MultipartFormData()
        form.appendField(name: "model", value: modelID)
        form.appendFile(name: "file", fileName: request.fileName, mimeType: request.mimeType, data: request.audio)
        var metadataBody: [String: JSONValue] = [
            "model": .string(modelID),
            "filename": .string(request.fileName),
            "mime_type": .string(request.mimeType)
        ]
        if let language = request.language {
            form.appendField(name: "language", value: language)
            metadataBody["language"] = .string(language)
        }
        if let prompt = request.prompt {
            form.appendField(name: "prompt", value: prompt)
            metadataBody["prompt"] = .string(prompt)
        }

        for (key, value) in groqTranscriptionOptions(from: request.extraBody) {
            if case let .array(items) = value {
                metadataBody[key] = value
                for item in items {
                    if let scalar = jsonScalarString(item) {
                        form.appendField(name: "\(key)[]", value: scalar)
                    }
                }
            } else if let scalar = jsonScalarString(value) {
                form.appendField(name: key, value: scalar)
                metadataBody[key] = value
            }
        }

        let body = form.finalize()
        let response = try await config.transport.send(config.rawRequest(
            path: "/audio/transcriptions",
            modelID: modelID,
            body: body,
            contentType: "multipart/form-data; boundary=\(form.boundary)",
            headers: request.headers
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        guard let text = raw["text"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "No transcription text found.")
        }
        let segments = standardTranscriptionSegments(from: raw)
        return TranscriptionResult(
            text: text,
            rawValue: raw,
            segments: segments,
            language: raw["language"]?.stringValue,
            durationInSeconds: raw["duration"]?.doubleValue ?? transcriptionDuration(from: segments),
            requestMetadata: AIRequestMetadata(body: .object(metadataBody), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response, modelID: modelID)
        )
    }
}

private func groqPreparedCall(for request: LanguageModelRequest, modelID: String, stream: Bool) -> GroqPreparedCall {
    var options = groqProviderOptions(from: request)
    let responseFormat = groqResolvedResponseFormat(request: request, options: &options)
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

private func groqLanguageOptions(from options: [String: JSONValue]) -> [String: JSONValue] {
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

private func groqResolvedResponseFormat(request: LanguageModelRequest, options: inout [String: JSONValue]) -> JSONValue? {
    if let responseFormat = request.responseFormat {
        options.removeValue(forKey: "responseFormat")
        return groqResponseFormatJSON(responseFormat)
    }
    return options.removeValue(forKey: "responseFormat")
}

private func groqResponseFormatJSON(_ responseFormat: AIResponseFormat) -> JSONValue? {
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

private func groqResponseFormat(from value: JSONValue, options: [String: JSONValue]) -> JSONValue {
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

private func groqWarnings(request: LanguageModelRequest, responseFormat: JSONValue?, options: [String: JSONValue]) -> [AIWarning] {
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

private func groqTranscriptionOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = groqProviderOptions(from: extraBody)
    moveKey("responseFormat", to: "response_format", in: &output)
    moveKey("timestampGranularities", to: "timestamp_granularities", in: &output)
    return output
}

private func groqProviderOptions(from request: LanguageModelRequest) -> [String: JSONValue] {
    var output = groqProviderOptions(from: request.extraBody)
    if let nested = request.providerOptions["groq"]?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func groqProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "groq")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func moveKey(_ source: String, to destination: String, in values: inout [String: JSONValue]) {
    if let value = values.removeValue(forKey: source) {
        values[destination] = value
    }
}

private func groqTools(from tools: [String: JSONValue], modelID: String) -> GroqPreparedTools {
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

private func groqToolChoice(from value: JSONValue?) -> JSONValue? {
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

private func groqToolCalls(from value: JSONValue?) -> [AIToolCall] {
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

private func groqFinishReason(_ reason: String?) -> String? {
    switch reason {
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

private let groqBrowserSearchSupportedModels: Set<String> = [
    "openai/gpt-oss-20b",
    "openai/gpt-oss-120b"
]

private func groqReasoningEffort(_ value: String) -> String {
    switch value {
    case "minimal":
        return "low"
    case "xhigh":
        return "high"
    default:
        return value
    }
}

private func groqApplyReasoning(_ reasoning: String?, to body: inout [String: JSONValue]) {
    guard let reasoning,
          reasoning != "none",
          body["reasoning_effort"] == nil else {
        return
    }
    body["reasoning_effort"] = .string(groqReasoningEffort(reasoning))
}
