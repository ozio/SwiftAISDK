import Foundation

public final class OpenAICompatibleChatModel: LanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try preparedBody(for: request, stream: false)
        let metadataNamespace = metadataNamespace(for: request)
        let httpResponse = try await config.transport.send(config.request(
            path: "/chat/completions",
            modelID: modelID,
            body: .object(prepared.body),
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw openAICompatibleHTTPStatusError(provider: providerID, response: httpResponse)
        }
        let response = (json: try httpResponse.jsonValue(), response: httpResponse)
        let raw = response.json
        let choice = raw["choices"]?[0]
        let toolCalls = openAICompatibleChatToolCalls(
            from: choice?["message"]?["tool_calls"],
            providerMetadataNamespace: metadataNamespace
        )
        let text = choice?["message"]?["content"]?.stringValue
            ?? choice?["text"]?.stringValue
            ?? raw["output_text"]?.stringValue
            ?? raw["text"]?.stringValue
        guard let text = text ?? (toolCalls.isEmpty ? nil : "") else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in chat completion response.")
        }
        return TextGenerationResult(
            text: text,
            reasoning: choice?["message"]?["reasoning_content"]?.stringValue
                ?? choice?["message"]?["reasoning"]?.stringValue
                ?? "",
            finishReason: openAICompatibleFinishReason(choice?["finish_reason"]?.stringValue),
            usage: usage(from: raw),
            toolCalls: toolCalls,
            providerMetadata: openAICompatibleChatProviderMetadata(from: raw, choice: choice, providerID: providerID, namespace: metadataNamespace),
            rawValue: raw,
            warnings: prepared.warnings,
            responseMetadata: openAICompatibleResponseMetadata(
                from: raw,
                response: response.response,
                modelID: modelID,
                suppressZeroCreatedTimestamp: isOpenAIBackedProvider(providerID, config: config)
            )
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let prepared = try preparedBody(for: request, stream: true)
                    let metadataNamespace = metadataNamespace(for: request)
                    let body = JSONValue.object(prepared.body)
                    let httpRequest = try config.request(path: "/chat/completions", modelID: modelID, body: body, headers: request.headers, abortSignal: request.abortSignal)
                    let response = try await config.streamRequest(httpRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        throw openAICompatibleHTTPStatusError(provider: providerID, response: try await bufferedHTTPResponse(from: response, request: httpRequest))
                    }
                    let responseHead = httpResponseHead(from: response, request: httpRequest)
                    continuation.yield(.streamStart(warnings: prepared.warnings))
                    var toolCalls = OpenAICompatibleStreamingToolCalls(
                        thoughtSignatureNamespace: metadataNamespace
                    )
                    var providerMetadata: [String: JSONValue] = [:]
                    var didEmitResponseMetadata = false
                    var activeReasoningID: String?
                    var activeTextID: String?
                    var finishReason: String?
                    var finishUsage: TokenUsage?
                    for try await event in serverSentEvents(from: response.body) {
                        if event.data == "[DONE]" { break }
                        let raw: JSONValue
                        do {
                            raw = try decodeJSONBody(Data(event.data.utf8))
                        } catch {
                            finishReason = "error"
                            continuation.yield(.error(message: error.localizedDescription))
                            continue
                        }
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        if let streamError = openAICompatibleStreamError(from: raw) {
                            finishReason = "error"
                            continuation.yield(.error(message: streamError.message, rawValue: streamError.rawValue))
                            continue
                        }
                        let suppressZeroCreatedTimestamp = isOpenAIBackedProvider(providerID, config: config)
                        if !didEmitResponseMetadata,
                           openAICompatibleChatResponseHasMetadata(raw, suppressZeroCreatedTimestamp: suppressZeroCreatedTimestamp) {
                            didEmitResponseMetadata = true
                            continuation.yield(.responseMetadata(openAICompatibleResponseMetadata(
                                from: raw,
                                response: responseHead,
                                modelID: modelID,
                                suppressZeroCreatedTimestamp: suppressZeroCreatedTimestamp
                            )))
                        }
                        let choice = raw["choices"]?[0]
                        openAICompatibleMergeProviderMetadata(
                            openAICompatibleChatProviderMetadata(from: raw, choice: choice, providerID: providerID, namespace: metadataNamespace),
                            into: &providerMetadata
                        )
                        finishUsage = usage(from: raw) ?? finishUsage
                        let delta = choice?["delta"]
                        if let reasoning = delta?["reasoning_content"]?.stringValue ?? delta?["reasoning"]?.stringValue {
                            let id = activeReasoningID ?? "reasoning-0"
                            if activeReasoningID == nil {
                                activeReasoningID = id
                                continuation.yield(.reasoningStart(id: id))
                            }
                            continuation.yield(.reasoningDeltaPart(id: id, delta: reasoning))
                        }
                        if let delta = delta?["content"]?.stringValue {
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
                        if let toolCallDeltas = delta?["tool_calls"]?.arrayValue {
                            if let reasoningID = activeReasoningID {
                                continuation.yield(.reasoningEnd(id: reasoningID))
                                activeReasoningID = nil
                            }
                            for toolCallDelta in toolCallDeltas {
                                if !toolCalls.hasMatchingBuffer(for: toolCallDelta) {
                                    guard toolCallDelta["id"]?.stringValue != nil else {
                                        throw AIError.invalidResponse(provider: providerID, message: "Expected 'id' to be a string.")
                                    }
                                    guard toolCallDelta["function"]?["name"]?.stringValue != nil else {
                                        throw AIError.invalidResponse(provider: providerID, message: "Expected 'function.name' to be a string.")
                                    }
                                }
                                for part in toolCalls.apply(delta: toolCallDelta) {
                                    continuation.yield(part)
                                }
                            }
                        }
                        if let reason = choice?["finish_reason"]?.stringValue {
                            finishReason = openAICompatibleFinishReason(reason)
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
                    if finishReason == nil {
                        if config.usesGenericOpenAICompatibleProviderOptions {
                            finishReason = "error"
                            continuation.yield(.error(message: "Response stream ended without a finish reason."))
                        } else {
                            finishReason = "other"
                        }
                    }
                    continuation.yield(.finishMetadata(
                        reason: finishReason,
                        usage: finishUsage,
                        providerMetadata: providerMetadata
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func preparedBody(
        for request: LanguageModelRequest,
        stream: Bool
    ) throws -> (body: [String: JSONValue], warnings: [AIWarning]) {
        var warnings = openAICompatibleChatWarnings(
            for: request,
            providerID: providerID,
            openAIBackedProviderRoot: config.openAIBackedProviderRoot,
            usesGenericProviderOptions: config.usesGenericOpenAICompatibleProviderOptions
        )
        var body = try Self.body(
            for: request,
            modelID: modelID,
            providerID: providerID,
            stream: stream,
            unwrapOpenAIProviderOptions: isOpenAIBackedProvider(providerID, config: config),
            openAIProviderOptionsRoot: config.openAIBackedProviderRoot,
            supportsStructuredOutputs: config.supportsStructuredOutputs ||
                (openAICompatibleProviderRoot(providerID) == "moonshotai" &&
                    moonshotSupportsStructuredOutputs(modelID: modelID)),
            usesGenericOpenAICompatibleProviderOptions: config.usesGenericOpenAICompatibleProviderOptions,
            warnings: &warnings
        )
        if stream, config.includeUsage {
            body["stream_options"] = .object(["include_usage": .bool(true)])
        }
        if openAICompatibleProviderRoot(providerID) == "fireworks" {
            body = fireworksChatBody(from: body)
        }
        if openAICompatibleProviderRoot(providerID) == "moonshotai" {
            body = try moonshotChatBody(
                from: body,
                request: request,
                modelID: modelID,
                warnings: &warnings
            )
        }
        if providerID == "googleVertex.xai" {
            body.removeValue(forKey: "reasoning_effort")
        }
        if providerID.hasPrefix("xai.") {
            body = try xaiChatBody(from: body, request: request, warnings: &warnings)
        }
        return (config.transformRequestBody?(body) ?? body, warnings)
    }

    private func metadataNamespace(for request: LanguageModelRequest) -> String? {
        guard config.usesGenericOpenAICompatibleProviderOptions else { return nil }
        return openAICompatibleProviderMetadataNamespace(providerID, providerOptions: request.providerOptions)
    }

    private func usage(from raw: JSONValue) -> TokenUsage? {
        switch openAICompatibleProviderRoot(providerID) {
        case "xai":
            return xaiChatUsage(from: raw)
        case "moonshotai":
            return moonshotChatUsage(from: raw)
        case "deepinfra":
            return deepInfraChatUsage(from: raw)
        default:
            return tokenUsage(from: raw)
        }
    }

    private static func body(
        for request: LanguageModelRequest,
        modelID: String,
        providerID: String,
        stream: Bool,
        unwrapOpenAIProviderOptions: Bool,
        openAIProviderOptionsRoot: String?,
        supportsStructuredOutputs: Bool,
        usesGenericOpenAICompatibleProviderOptions: Bool,
        warnings: inout [AIWarning]
    ) throws -> [String: JSONValue] {
        var extraBody: [String: JSONValue]
        if unwrapOpenAIProviderOptions {
            extraBody = openAIProviderOptions(providerOptions: request.providerOptions, extraBody: request.extraBody, providerID: providerID, providerRoot: openAIProviderOptionsRoot)
        } else if usesGenericOpenAICompatibleProviderOptions {
            extraBody = openAICompatibleProviderOptions(providerOptions: request.providerOptions, extraBody: request.extraBody, providerID: providerID, includeCompatibilityNamespace: true)
        } else {
            extraBody = openAICompatibleProviderOptions(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: true)
        }
        if extraBody["responseFormat"] == nil,
           let responseFormat = openAICompatibleResponseFormatJSON(request.responseFormat) {
            extraBody["responseFormat"] = responseFormat
        }

        var options = openAICompatibleChatOptions(from: extraBody, supportsStructuredOutputs: supportsStructuredOutputs)
        let capabilities = openAILanguageModelCapabilities(modelID)
        let isReasoningModel = unwrapOpenAIProviderOptions
            && (options.removeValue(forKey: "forceReasoning")?.boolValue ?? capabilities.isReasoningModel)
        let systemMessageMode = options.removeValue(forKey: "systemMessageMode")?.stringValue
            ?? options.removeValue(forKey: "system_message_mode")?.stringValue
            ?? (isReasoningModel ? "developer" : "system")
        if openAICompatibleProviderRoot(providerID) == "openai",
           options["reasoning_effort"] == nil,
           let reasoning = request.reasoning,
           reasoning != "provider-default" {
            options["reasoning_effort"] = .string(reasoning)
        }

        let messages: [JSONValue]
        if openAICompatibleProviderRoot(providerID) == "moonshotai" {
            messages = try moonshotChatMessages(from: request.messages)
        } else {
            var converted: [JSONValue] = []
            for message in request.messages {
                if message.role == .system, systemMessageMode == "remove" {
                    continue
                }
                converted.append(try Self.messageJSON(
                    message,
                    providerID: providerID,
                    providerOptionsKey: openAICompatibleProviderMetadataNamespace(
                        providerID,
                        providerOptions: request.providerOptions
                    ),
                    systemRole: message.role == .system ? systemMessageMode : nil
                ))
            }
            messages = converted
        }
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "messages": .array(messages)
        ]
        if stream { body["stream"] = true }
        if let temperature = request.temperature { body["temperature"] = .number(temperature) }
        if let topP = request.topP { body["top_p"] = .number(topP) }
        if let presencePenalty = request.presencePenalty { body["presence_penalty"] = .number(presencePenalty) }
        if let frequencyPenalty = request.frequencyPenalty { body["frequency_penalty"] = .number(frequencyPenalty) }
        if let seed = request.seed { body["seed"] = .number(Double(seed)) }
        if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
        if !request.stopSequences.isEmpty { body["stop"] = .array(request.stopSequences) }
        let toolChoiceInput = request.toolChoice ?? request.extraBody["toolChoice"]
        let tools = openAICompatibleChatTools(from: request.tools)
        if !tools.isEmpty {
            body["tools"] = .array(tools)
            if let toolChoice = openAICompatibleChatToolChoice(from: toolChoiceInput) {
                body["tool_choice"] = toolChoice
            }
        }
        body.merge(options) { _, new in new }
        if isReasoningModel {
            let permitsSampling = body["reasoning_effort"]?.stringValue == "none"
                && capabilities.supportsNonReasoningParameters
            if !permitsSampling {
                if body.removeValue(forKey: "temperature") != nil {
                    warnings.append(AIWarning(
                        type: "unsupported",
                        feature: "temperature",
                        message: "temperature is not supported for reasoning models"
                    ))
                }
                if body.removeValue(forKey: "top_p") != nil {
                    warnings.append(AIWarning(
                        type: "unsupported",
                        feature: "topP",
                        message: "topP is not supported for reasoning models"
                    ))
                }
                if body.removeValue(forKey: "logprobs") != nil {
                    warnings.append(AIWarning(
                        type: "other",
                        message: "logprobs is not supported for reasoning models"
                    ))
                }
            }
            if body.removeValue(forKey: "frequency_penalty") != nil {
                warnings.append(AIWarning(
                    type: "unsupported",
                    feature: "frequencyPenalty",
                    message: "frequencyPenalty is not supported for reasoning models"
                ))
            }
            if body.removeValue(forKey: "presence_penalty") != nil {
                warnings.append(AIWarning(
                    type: "unsupported",
                    feature: "presencePenalty",
                    message: "presencePenalty is not supported for reasoning models"
                ))
            }
            if body.removeValue(forKey: "logit_bias") != nil {
                warnings.append(AIWarning(
                    type: "other",
                    message: "logitBias is not supported for reasoning models"
                ))
            }
            if body.removeValue(forKey: "top_logprobs") != nil {
                warnings.append(AIWarning(
                    type: "other",
                    message: "topLogprobs is not supported for reasoning models"
                ))
            }
            if let maxTokens = body.removeValue(forKey: "max_tokens"),
               body["max_completion_tokens"] == nil {
                body["max_completion_tokens"] = maxTokens
            }
        }
        return body
    }

    static func messageJSON(
        _ message: AIMessage,
        providerID: String,
        providerOptionsKey: String? = nil,
        systemRole: String? = nil
    ) throws -> JSONValue {
        if message.role == .tool,
           let result = message.content.compactMap({ part -> AIToolResult? in
               if case let .toolResult(result) = part { result } else { nil }
           }).first {
            return .object([
                "role": .string("tool"),
                "tool_call_id": .string(result.toolCallID),
                "content": .string(openAIResponsesJSONString(result.modelOutput ?? result.result) ?? result.modelOutput?.stringValue ?? result.result.stringValue ?? "")
            ])
        }

        let toolCalls = message.content.compactMap { part -> AIToolCall? in
            if case let .toolCall(call) = part { call } else { nil }
        }
        if message.role == .assistant, !toolCalls.isEmpty {
            var output: [String: JSONValue] = [
                "role": .string("assistant"),
                "content": .string(message.combinedText)
            ]
            output["tool_calls"] = .array(toolCalls.map { call in
                var toolCall: [String: JSONValue] = [
                    "id": .string(call.id),
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(call.name),
                        "arguments": .string(call.arguments)
                    ])
                ]
                let thoughtSignature = providerOptionsKey.flatMap { call.providerMetadata[$0]?["thoughtSignature"]?.stringValue }
                    ?? call.providerMetadata["google"]?["thoughtSignature"]?.stringValue
                if let thoughtSignature, !thoughtSignature.isEmpty {
                    toolCall["extra_content"] = .object([
                        "google": .object(["thought_signature": .string(thoughtSignature)])
                    ])
                }
                return .object(toolCall)
            })
            return .object(output)
        }

        let textOnly = message.content.allSatisfy {
            if case .text = $0 { true } else { false }
        }

        if textOnly {
            return .object([
                "role": .string(systemRole ?? message.role.rawValue),
                "content": .string(message.combinedText)
            ])
        }

        let parts: [JSONValue] = try message.content.enumerated().map { index, part in
            switch part {
            case let .text(text, _):
                return .object(["type": .string("text"), "text": .string(text)])
            case let .reasoning(text, _):
                return .object(["type": .string("text"), "text": .string(text)])
            case let .imageURL(url, providerMetadata):
                var imageURL: [String: JSONValue] = ["url": .string(url)]
                if let imageDetail = openAIChatImageDetail(from: providerMetadata, providerID: providerID) {
                    imageURL["detail"] = imageDetail
                }
                return .object(["type": .string("image_url"), "image_url": .object(imageURL)])
            case let .data(mimeType, data, providerMetadata):
                return try chatFilePart(
                    mimeType: mimeType,
                    data: data,
                    filename: nil,
                    providerMetadata: providerMetadata,
                    index: index,
                    providerID: providerID,
                    providerOptionsKey: providerOptionsKey
                )
            case let .file(mimeType, data, filename, providerMetadata):
                return try chatFilePart(
                    mimeType: mimeType,
                    data: data,
                    filename: filename,
                    providerMetadata: providerMetadata,
                    index: index,
                    providerID: providerID,
                    providerOptionsKey: providerOptionsKey
                )
            case let .providerReference(mimeType, reference, _, providerMetadata):
                if mimeType.hasPrefix("video/"),
                   let url = reference["openaiCompatible"]
                    ?? reference[providerOptionsKey ?? ""]
                    ?? reference[openAICompatibleProviderRoot(providerID)] {
                    var output: [String: JSONValue] = [
                        "type": .string("video_url"),
                        "video_url": .object(["url": .string(url)])
                    ]
                    let namespace = providerOptionsKey ?? openAICompatibleProviderMetadataNamespace(providerID)
                    if let metadata = providerMetadata[namespace]?.objectValue
                        ?? providerMetadata["openaiCompatible"]?.objectValue {
                        output.merge(metadata) { _, value in value }
                    }
                    return .object(output)
                }
                return .object([
                    "type": .string("file"),
                    "file": .object([
                        "file_id": .string(try resolveProviderReference(reference, provider: openAICompatibleProviderRoot(providerID)))
                    ])
                ])
            case .reasoningFile, .custom, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
                return .object(["type": .string("text"), "text": .string("")])
            }
        }

        return .object([
            "role": .string(systemRole ?? message.role.rawValue),
            "content": .array(parts)
        ])
    }
}

private func chatFilePart(
    mimeType: String,
    data: Data,
    filename: String?,
    providerMetadata: [String: JSONValue],
    index: Int,
    providerID: String,
    providerOptionsKey: String?
) throws -> JSONValue {
    let base64 = data.base64EncodedString()
    if mimeType.hasPrefix("image/") {
        var imageURL: [String: JSONValue] = ["url": .string("data:\(mimeType);base64,\(base64)")]
        if let imageDetail = openAIChatImageDetail(from: providerMetadata, providerID: providerID) {
            imageURL["detail"] = imageDetail
        }
        return .object(["type": .string("image_url"), "image_url": .object(imageURL)])
    }
    if mimeType.hasPrefix("video/") {
        var output: [String: JSONValue] = [
            "type": .string("video_url"),
            "video_url": .object(["url": .string("data:\(mimeType);base64,\(base64)")])
        ]
        let namespace = providerOptionsKey ?? openAICompatibleProviderMetadataNamespace(providerID)
        if let metadata = providerMetadata[namespace]?.objectValue
            ?? providerMetadata["openaiCompatible"]?.objectValue {
            output.merge(metadata) { _, value in value }
        }
        return .object(output)
    }
    switch mimeType {
    case "audio/wav":
        return .object([
            "type": .string("input_audio"),
            "input_audio": .object(["data": .string(base64), "format": .string("wav")])
        ])
    case "audio/mp3", "audio/mpeg":
        return .object([
            "type": .string("input_audio"),
            "input_audio": .object(["data": .string(base64), "format": .string("mp3")])
        ])
    case "application/pdf":
        return .object([
            "type": .string("file"),
            "file": .object([
                "filename": .string(filename ?? "part-\(index).pdf"),
                "file_data": .string("data:application/pdf;base64,\(base64)")
            ])
        ])
    default:
        throw AIError.invalidArgument(
            argument: "messages",
            message: "OpenAI chat file part media type \(mimeType) is not supported."
        )
    }
}

private func openAIChatImageDetail(from providerMetadata: [String: JSONValue], providerID: String) -> JSONValue? {
    let providerRoot = openAICompatibleProviderRoot(providerID)
    return providerMetadata[providerRoot]?["imageDetail"]
        ?? providerMetadata["openai"]?["imageDetail"]
        ?? providerMetadata["imageDetail"]
}
