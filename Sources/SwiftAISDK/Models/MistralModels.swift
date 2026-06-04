import Foundation

public final class MistralLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "mistral.chat"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try body(for: request, stream: false)
        let response = try await config.sendJSONResponse(
            path: "/chat/completions",
            modelID: modelID,
            body: .object(prepared.body),
            headers: request.headers,
            abortSignal: request.abortSignal
        )
        let raw = response.json
        let choice = raw["choices"]?[0]
        let text = mistralText(from: choice?["message"]?["content"]) ?? ""
        let reasoning = mistralReasoning(from: choice?["message"]?["content"]) ?? ""
        let toolCalls = mistralToolCalls(from: choice?["message"]?["tool_calls"])
        guard choice != nil else {
            throw AIError.invalidResponse(provider: providerID, message: "No Mistral choice found.")
        }
        return TextGenerationResult(
            text: text,
            reasoning: reasoning,
            finishReason: mapMistralFinishReason(choice?["finish_reason"]?.stringValue),
            usage: mistralUsage(from: raw),
            toolCalls: toolCalls,
            rawValue: raw,
            warnings: prepared.warnings,
            responseMetadata: mistralResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = try body(for: request, stream: true)
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
                    var finishReason: String? = "other"
                    var usage: TokenUsage?
                    var emittedResponseMetadata = false
                    var activeText = false
                    var activeReasoningID: String?
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        if !emittedResponseMetadata {
                            emittedResponseMetadata = true
                            continuation.yield(.responseMetadata(mistralResponseMetadata(from: raw, response: response, modelID: modelID)))
                        }
                        if let delta = mistralText(from: raw["choices"]?[0]?["delta"]?["content"]), !delta.isEmpty {
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
                        if let reasoning = mistralReasoning(from: raw["choices"]?[0]?["delta"]?["content"]), !reasoning.isEmpty {
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
                        for toolCall in mistralToolCalls(from: raw["choices"]?[0]?["delta"]?["tool_calls"]) {
                            continuation.yield(.toolInputStart(id: toolCall.id, name: toolCall.name))
                            continuation.yield(.toolCallDelta(id: toolCall.id, name: toolCall.name, argumentsDelta: toolCall.arguments, index: nil))
                            if !toolCall.arguments.isEmpty {
                                continuation.yield(.toolInputDelta(id: toolCall.id, delta: toolCall.arguments))
                            }
                            continuation.yield(.toolInputEnd(id: toolCall.id))
                            continuation.yield(.toolCall(toolCall))
                        }
                        if let reason = raw["choices"]?[0]?["finish_reason"]?.stringValue {
                            finishReason = mapMistralFinishReason(reason)
                        }
                        if raw["usage"] != nil {
                            usage = mistralUsage(from: raw)
                        }
                    }
                    if let reasoningID = activeReasoningID {
                        continuation.yield(.reasoningEnd(id: reasoningID))
                    }
                    if activeText {
                        continuation.yield(.textEnd(id: "0"))
                    }
                    continuation.yield(.finish(reason: finishReason, usage: usage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func body(for request: LanguageModelRequest, stream: Bool) throws -> MistralPreparedCall {
        var options = try mistralProviderOptions(from: request)
        let responseFormat = mistralResolvedResponseFormat(request: request, options: &options)
        let warnings = mistralWarnings(for: request, modelID: modelID)
        let messages = mistralMessages(request.messages, responseFormat: responseFormat)
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "messages": .array(try mistralMessagesJSON(messages))
        ]
        if stream { body["stream"] = true }
        if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
        if let temperature = request.temperature { body["temperature"] = .number(temperature) }
        if let topP = request.topP { body["top_p"] = .number(topP) }
        if !request.stopSequences.isEmpty { body["stop"] = .array(request.stopSequences) }
        if let seed = request.seed { body["random_seed"] = .number(Double(seed)) }
        if let responseFormat = responseFormat {
            body["response_format"] = mistralResponseFormat(from: responseFormat, options: options)
        }
        let toolChoiceInput = request.toolChoice ?? options["toolChoice"]
        let toolChoice = mistralToolChoice(from: toolChoiceInput)
        let preparedTools = mistralTools(from: request.tools, only: mistralForcedToolName(from: toolChoiceInput))
        if !preparedTools.tools.isEmpty {
            body["tools"] = .array(preparedTools.tools)
            if let toolChoice {
                body["tool_choice"] = toolChoice
            }
        }
        for (key, value) in options {
            switch key {
            case "safePrompt":
                body["safe_prompt"] = value
            case "randomSeed":
                body["random_seed"] = value
            case "reasoningEffort":
                body["reasoning_effort"] = value
            case "documentImageLimit":
                body["document_image_limit"] = value
            case "documentPageLimit":
                body["document_page_limit"] = value
            case "parallelToolCalls":
                if !preparedTools.tools.isEmpty { body["parallel_tool_calls"] = value }
            case "responseFormat", "structuredOutputs", "strictJsonSchema":
                continue
            case "toolChoice":
                continue
            case "mistral":
                continue
            default:
                body[key] = value
            }
        }
        if body["reasoning_effort"] == nil,
           let reasoning = request.reasoning,
           mistralSupportsReasoningEffort(modelID) {
            body["reasoning_effort"] = .string(reasoning == "none" ? "none" : "high")
        }
        return MistralPreparedCall(body: body, warnings: warnings + preparedTools.warnings)
    }
}

struct MistralPreparedCall {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
}

struct MistralPreparedTools {
    var tools: [JSONValue]
    var warnings: [AIWarning]
}

