import Foundation

public final class OpenAICompatibleCompletionModel: LanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try body(for: request, stream: false)
        let body = prepared.body
        let response = try await config.sendJSONResponse(path: "/completions", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        guard let text = raw["choices"]?[0]?["text"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "No text found in completion response.")
        }
        return TextGenerationResult(
            text: text,
            finishReason: raw["choices"]?[0]?["finish_reason"]?.stringValue,
            usage: tokenUsage(from: raw),
            providerMetadata: openAICompatibleCompletionProviderMetadata(from: raw["choices"]?[0], providerID: providerID),
            rawValue: raw,
            warnings: prepared.warnings,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: openAICompatibleResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = try body(for: request, stream: true)
                    let body = JSONValue.object(prepared.body)
                    let httpRequest = try config.request(path: "/completions", modelID: modelID, body: body, headers: request.headers, abortSignal: request.abortSignal)
                    let response = try await config.transport.send(httpRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        throw apiCallError(provider: providerID, response: response)
                    }
                    continuation.yield(.streamStart(warnings: prepared.warnings))
                    continuation.yield(.responseMetadata(openAICompatibleResponseMetadata(response: response, modelID: modelID)))
                    var providerMetadata: [String: JSONValue] = [:]
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        let choice = raw["choices"]?[0]
                        openAICompatibleMergeProviderMetadata(
                            openAICompatibleCompletionProviderMetadata(from: choice, providerID: providerID),
                            into: &providerMetadata
                        )
                        if let delta = choice?["text"]?.stringValue {
                            continuation.yield(.textDelta(delta))
                        }
                        if let reason = choice?["finish_reason"]?.stringValue {
                            let finishReason = openAICompatibleFinishReason(reason)
                            let finishUsage = tokenUsage(from: raw)
                            if providerMetadata.isEmpty {
                                continuation.yield(.finish(reason: finishReason, usage: finishUsage))
                            } else {
                                continuation.yield(.finishMetadata(reason: finishReason, usage: finishUsage, providerMetadata: providerMetadata))
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func body(for request: LanguageModelRequest, stream: Bool) throws -> (body: [String: JSONValue], warnings: [AIWarning]) {
        let prompt = try openAICompatibleCompletionPrompt(from: request.messages)
        var stopSequences = prompt.stopSequences
        stopSequences.append(contentsOf: request.stopSequences)
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "prompt": .string(prompt.text)
        ]
        if stream { body["stream"] = .bool(true) }
        if stream, config.includeUsage { body["stream_options"] = .object(["include_usage": .bool(true)]) }
        if let temperature = request.temperature { body["temperature"] = .number(temperature) }
        if let topP = request.topP { body["top_p"] = .number(topP) }
        if let frequencyPenalty = request.frequencyPenalty { body["frequency_penalty"] = .number(frequencyPenalty) }
        if let presencePenalty = request.presencePenalty { body["presence_penalty"] = .number(presencePenalty) }
        if let seed = request.seed { body["seed"] = .number(Double(seed)) }
        if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
        if !stopSequences.isEmpty { body["stop"] = .array(stopSequences) }
        let extraBody: [String: JSONValue]
        if isOpenAIBackedProvider(providerID, config: config) {
            extraBody = openAICompletionProviderOptions(providerOptions: request.providerOptions, extraBody: request.extraBody, providerID: providerID, providerRoot: config.openAIBackedProviderRoot)
        } else if config.usesGenericOpenAICompatibleProviderOptions {
            extraBody = openAICompatibleProviderOptions(providerOptions: request.providerOptions, extraBody: request.extraBody, providerID: providerID, includeCompatibilityNamespace: false)
        } else {
            extraBody = openAICompatibleProviderOptions(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: false)
        }
        body.merge(openAICompletionOptions(from: extraBody)) { _, new in new }
        return (body, openAICompletionWarnings(for: request, providerID: providerID, openAIBackedProviderRoot: config.openAIBackedProviderRoot, usesGenericProviderOptions: config.usesGenericOpenAICompatibleProviderOptions))
    }
}

func openAICompatibleCompletionPrompt(from messages: [AIMessage]) throws -> (text: String, stopSequences: [String]) {
    var remaining = messages
    var text = ""

    if remaining.first?.role == .system {
        text += remaining.removeFirst().combinedText + "\n\n"
    }

    for message in remaining {
        switch message.role {
        case .system:
            throw AIError.invalidArgument(argument: "messages", message: "Completion prompts only support a system message as the first message.")
        case .user:
            text += "user:\n\(message.combinedText)\n\n"
        case .assistant:
            let hasUnsupportedParts = message.content.contains { part in
                if case .text = part { return false }
                return true
            }
            if hasUnsupportedParts {
                throw AIError.invalidArgument(argument: "messages", message: "Completion prompts only support text assistant messages.")
            }
            text += "assistant:\n\(message.combinedText)\n\n"
        case .tool:
            throw AIError.invalidArgument(argument: "messages", message: "Completion prompts do not support tool messages.")
        }
    }

    text += "assistant:\n"
    return (text, ["\nuser:"])
}

