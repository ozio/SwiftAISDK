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
        let prepared = try groqPreparedCall(for: request, modelID: modelID, stream: false)
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
        let reasoning = choice?["message"]?["reasoning"]?.stringValue ?? ""
        guard let text = choice?["message"]?["content"]?.stringValue ?? (!toolCalls.isEmpty || !reasoning.isEmpty ? "" : nil) else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in Groq response.")
        }
        return TextGenerationResult(
            text: text,
            reasoning: reasoning,
            finishReason: groqFinishReason(choice?["finish_reason"]?.stringValue),
            usage: groqUsage(from: raw["usage"]),
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
                    let prepared = try groqPreparedCall(for: request, modelID: modelID, stream: true)
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
                    var finishReason: String? = "other"
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
                        latestUsage = groqUsage(from: raw["x_groq"]?["usage"]) ?? groqUsage(from: raw["usage"]) ?? latestUsage
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
                        if let finishReasonValue = raw["choices"]?[0]?["finish_reason"], finishReasonValue != .null {
                            finishReason = groqFinishReason(finishReasonValue.stringValue)
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
        let uploadFileName = "audio.\(mediaTypeToExtension(request.mimeType))"
        form.appendFile(name: "file", fileName: uploadFileName, mimeType: request.mimeType, data: request.audio)
        var metadataBody: [String: JSONValue] = [
            "model": .string(modelID),
            "filename": .string(uploadFileName),
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

        let providerOptions = try groqTranscriptionOptions(from: request)
        if let language = providerOptions["language"]?.stringValue, request.language == nil {
            form.appendField(name: "language", value: language)
            metadataBody["language"] = .string(language)
        }
        if let prompt = providerOptions["prompt"]?.stringValue, request.prompt == nil {
            form.appendField(name: "prompt", value: prompt)
            metadataBody["prompt"] = .string(prompt)
        }

        for (key, value) in providerOptions where key != "language" && key != "prompt" {
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
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        guard let text = raw["text"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "No transcription text found.")
        }
        try validateGroqTranscriptionResponse(raw)
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

private func validateGroqTranscriptionResponse(_ raw: JSONValue) throws {
    guard raw["x_groq"]?["id"]?.stringValue != nil else {
        throw AIError.invalidResponse(provider: "groq.transcription", message: "Groq transcription response is invalid.")
    }
    if let task = raw["task"], task != .null, task.stringValue == nil {
        throw AIError.invalidResponse(provider: "groq.transcription", message: "Groq transcription response is invalid.")
    }
    if let language = raw["language"], language != .null, language.stringValue == nil {
        throw AIError.invalidResponse(provider: "groq.transcription", message: "Groq transcription response is invalid.")
    }
    if let duration = raw["duration"], duration != .null, duration.doubleValue == nil {
        throw AIError.invalidResponse(provider: "groq.transcription", message: "Groq transcription response is invalid.")
    }
    guard let segments = raw["segments"] else { return }
    guard segments != .null else { return }
    guard let array = segments.arrayValue else {
        throw AIError.invalidResponse(provider: "groq.transcription", message: "Groq transcription response is invalid.")
    }
    for segment in array {
        guard
            segment["id"]?.doubleValue != nil,
            segment["seek"]?.doubleValue != nil,
            segment["start"]?.doubleValue != nil,
            segment["end"]?.doubleValue != nil,
            segment["text"]?.stringValue != nil,
            let tokens = segment["tokens"]?.arrayValue,
            segment["temperature"]?.doubleValue != nil,
            segment["avg_logprob"]?.doubleValue != nil,
            segment["compression_ratio"]?.doubleValue != nil,
            segment["no_speech_prob"]?.doubleValue != nil
        else {
            throw AIError.invalidResponse(provider: "groq.transcription", message: "Groq transcription response is invalid.")
        }
        guard tokens.allSatisfy({ $0.doubleValue != nil }) else {
            throw AIError.invalidResponse(provider: "groq.transcription", message: "Groq transcription response is invalid.")
        }
    }
}

private func groqPreparedCall(for request: LanguageModelRequest, modelID: String, stream: Bool) throws -> GroqPreparedCall {
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

private func groqTranscriptionOptions(from request: AudioTranscriptionRequest) throws -> [String: JSONValue] {
    var output = groqProviderOptions(from: request.extraBody)
    if let value = request.providerOptions["groq"] {
        guard value != .null else {
            moveKey("responseFormat", to: "response_format", in: &output)
            moveKey("timestampGranularities", to: "timestamp_granularities", in: &output)
            return output
        }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.groq", message: "Groq provider options must be an object.")
        }
        for key in groqTranscriptionProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try groqValidateTranscriptionProviderOptions(nested)) { _, providerValue in providerValue }
    }
    moveKey("responseFormat", to: "response_format", in: &output)
    moveKey("timestampGranularities", to: "timestamp_granularities", in: &output)
    return output
}

private func groqProviderOptions(from request: LanguageModelRequest) throws -> [String: JSONValue] {
    var output = groqProviderOptions(from: request.extraBody)
    if let value = request.providerOptions["groq"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.groq", message: "Groq provider options must be an object.")
        }
        for key in groqChatProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try groqValidateChatProviderOptions(nested)) { _, providerValue in providerValue }
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

private let groqChatProviderOptionKeys: Set<String> = [
    "reasoningFormat",
    "reasoningEffort",
    "parallelToolCalls",
    "user",
    "structuredOutputs",
    "strictJsonSchema",
    "serviceTier"
]

private let groqTranscriptionProviderOptionKeys: Set<String> = [
    "language",
    "prompt",
    "responseFormat",
    "temperature",
    "timestampGranularities"
]

private func groqUsage(from usage: JSONValue?) -> TokenUsage? {
    guard let usage, usage != .null else { return nil }
    let promptTokens = usage["prompt_tokens"]?.intValue ?? 0
    let completionTokens = usage["completion_tokens"]?.intValue ?? 0
    let reasoningTokens = usage["completion_tokens_details"]?["reasoning_tokens"]?.intValue
    return TokenUsage(
        inputTokens: promptTokens,
        outputTokens: completionTokens,
        totalTokens: usage["total_tokens"]?.intValue ?? promptTokens + completionTokens,
        inputTokensNoCache: promptTokens,
        outputTextTokens: reasoningTokens.map { completionTokens - $0 } ?? completionTokens,
        outputReasoningTokens: reasoningTokens,
        rawValue: usage
    )
}

private func groqValidateChatProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where groqChatProviderOptionKeys.contains(key) {
        guard value != .null else {
            throw AIError.invalidArgument(argument: "providerOptions.groq.\(key)", message: "Groq \(key) cannot be null.")
        }
        switch key {
        case "reasoningFormat":
            guard let string = value.stringValue, ["parsed", "raw", "hidden"].contains(string) else {
                throw AIError.invalidArgument(argument: "providerOptions.groq.reasoningFormat", message: "Groq reasoningFormat must be parsed, raw, or hidden.")
            }
            output[key] = value
        case "reasoningEffort":
            guard let string = value.stringValue, ["none", "default", "low", "medium", "high"].contains(string) else {
                throw AIError.invalidArgument(argument: "providerOptions.groq.reasoningEffort", message: "Groq reasoningEffort must be none, default, low, medium, or high.")
            }
            output[key] = value
        case "parallelToolCalls", "structuredOutputs", "strictJsonSchema":
            try groqRequireBoolean(value, argument: "providerOptions.groq.\(key)", message: "Groq \(key) must be a boolean.")
            output[key] = value
        case "user":
            try groqRequireString(value, argument: "providerOptions.groq.user", message: "Groq user must be a string.")
            output[key] = value
        case "serviceTier":
            guard let string = value.stringValue, ["on_demand", "performance", "flex", "auto"].contains(string) else {
                throw AIError.invalidArgument(argument: "providerOptions.groq.serviceTier", message: "Groq serviceTier must be on_demand, performance, flex, or auto.")
            }
            output[key] = value
        default:
            break
        }
    }
    return output
}

private func groqValidateTranscriptionProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where groqTranscriptionProviderOptionKeys.contains(key) {
        guard value != .null else { continue }
        switch key {
        case "language", "prompt", "responseFormat":
            try groqRequireString(value, argument: "providerOptions.groq.\(key)", message: "Groq \(key) must be a string.")
            output[key] = value
        case "temperature":
            guard let number = value.doubleValue, number >= 0, number <= 1 else {
                throw AIError.invalidArgument(argument: "providerOptions.groq.temperature", message: "Groq temperature must be a number between 0 and 1.")
            }
            output[key] = value
        case "timestampGranularities":
            output[key] = try groqStringArray(value, argument: "providerOptions.groq.timestampGranularities")
        default:
            break
        }
    }
    return output
}

private func groqStringArray(_ value: JSONValue, argument: String) throws -> JSONValue {
    guard let array = value.arrayValue else {
        throw AIError.invalidArgument(argument: argument, message: "Groq \(argument) must be an array of strings.")
    }
    for item in array where item.stringValue == nil {
        throw AIError.invalidArgument(argument: argument, message: "Groq \(argument) values must be strings.")
    }
    return value
}

private func groqRequireString(_ value: JSONValue, argument: String, message: String) throws {
    guard value.stringValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func groqRequireBoolean(_ value: JSONValue, argument: String, message: String) throws {
    guard value.boolValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func groqMessageJSON(_ message: AIMessage) throws -> [JSONValue] {
    switch message.role {
    case .system:
        return [.object(["role": .string("system"), "content": .string(message.combinedText)])]
    case .user:
        if message.content.count == 1, case let .text(text) = message.content[0] {
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

private func groqUserContentPart(_ part: AIContentPart) throws -> JSONValue {
    switch part {
    case let .text(text):
        return .object(["type": .string("text"), "text": .string(text)])
    case let .imageURL(url):
        return .object(["type": .string("image_url"), "image_url": .object(["url": .string(url)])])
    case let .data(mimeType, data), let .file(mimeType, data, _):
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
    case .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
        throw AIError.invalidArgument(argument: "messages", message: "Groq user messages only support text and image file parts.")
    }
}

private func groqText(from message: AIMessage) -> String {
    message.content.compactMap(\.text).joined()
}

private func groqJSONString(_ value: JSONValue) -> String? {
    guard let data = try? encodeJSONBody(value) else { return nil }
    return String(data: data, encoding: .utf8)
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
