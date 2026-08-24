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
            let task = Task {
                do {
                    let prepared = try body(for: request, stream: true)
                    let httpRequest = try config.request(
                        path: "/chat/completions",
                        modelID: modelID,
                        body: .object(prepared.body),
                        headers: request.headers,
                        abortSignal: request.abortSignal
                    )
                    let response = try await config.streamRequest(httpRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        throw apiCallError(provider: providerID, response: try await bufferedHTTPResponse(from: response, request: httpRequest))
                    }
                    let responseHead = httpResponseHead(from: response, request: httpRequest)
                    continuation.yield(.streamStart(warnings: prepared.warnings))
                    var finishReason: String? = "other"
                    var usage: TokenUsage?
                    var emittedResponseMetadata = false
                    var activeText = false
                    var activeReasoningID: String?
                    var toolCalls = OpenAIStyleStreamingToolCalls()
                    for try await event in serverSentEvents(from: response.body) {
                        if event.data == "[DONE]" { break }
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        if !emittedResponseMetadata {
                            emittedResponseMetadata = true
                            continuation.yield(.responseMetadata(mistralResponseMetadata(from: raw, response: responseHead, modelID: modelID)))
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
                        for toolCallDelta in raw["choices"]?[0]?["delta"]?["tool_calls"]?.arrayValue ?? [] {
                            for part in toolCalls.apply(delta: toolCallDelta) {
                                continuation.yield(part)
                            }
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
                    for part in toolCalls.finishedParts() {
                        continuation.yield(part)
                    }
                    continuation.yield(.finishMetadata(
                        reason: finishReason,
                        usage: usage,
                        providerMetadata: [:]
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func body(for request: LanguageModelRequest, stream: Bool) throws -> MistralPreparedCall {
        var options = try mistralProviderOptions(from: request)
        let responseFormat = mistralResolvedResponseFormat(request: request, options: &options)
        var warnings = mistralWarnings(for: request, modelID: modelID)
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
        if let frequencyPenalty = request.frequencyPenalty { body["frequency_penalty"] = .number(frequencyPenalty) }
        if let presencePenalty = request.presencePenalty { body["presence_penalty"] = .number(presencePenalty) }
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
           mistralSupportsReasoningEffort(modelID),
           let reasoningEffort = mistralReasoningEffort(request.reasoning, warnings: &warnings) {
            body["reasoning_effort"] = reasoningEffort
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
