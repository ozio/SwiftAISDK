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
        let warnings = openAICompatibleChatWarnings(for: request, providerID: providerID, openAIBackedProviderRoot: config.openAIBackedProviderRoot, usesGenericProviderOptions: config.usesGenericOpenAICompatibleProviderOptions)
        let httpResponse = try await config.transport.send(config.request(
            path: "/chat/completions",
            modelID: modelID,
            body: .object(try body(for: request, stream: false)),
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw openAICompatibleHTTPStatusError(provider: providerID, response: httpResponse)
        }
        let response = (json: try httpResponse.jsonValue(), response: httpResponse)
        let raw = response.json
        let choice = raw["choices"]?[0]
        let toolCalls = openAICompatibleChatToolCalls(from: choice?["message"]?["tool_calls"])
        let text = choice?["message"]?["content"]?.stringValue
            ?? choice?["text"]?.stringValue
            ?? raw["output_text"]?.stringValue
            ?? raw["text"]?.stringValue
        guard let text = text ?? (toolCalls.isEmpty ? nil : "") else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in chat completion response.")
        }
        return TextGenerationResult(
            text: text,
            finishReason: openAICompatibleFinishReason(choice?["finish_reason"]?.stringValue),
            usage: usage(from: raw),
            toolCalls: toolCalls,
            providerMetadata: openAICompatibleChatProviderMetadata(from: raw, choice: choice, providerID: providerID),
            rawValue: raw,
            warnings: warnings,
            responseMetadata: openAICompatibleResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let warnings = openAICompatibleChatWarnings(for: request, providerID: providerID, openAIBackedProviderRoot: config.openAIBackedProviderRoot, usesGenericProviderOptions: config.usesGenericOpenAICompatibleProviderOptions)
                    let body = JSONValue.object(try body(for: request, stream: true))
                    let httpRequest = try config.request(path: "/chat/completions", modelID: modelID, body: body, headers: request.headers, abortSignal: request.abortSignal)
                    let response = try await config.transport.send(httpRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        throw openAICompatibleHTTPStatusError(provider: providerID, response: response)
                    }
                    continuation.yield(.streamStart(warnings: warnings))
                    var toolCalls = OpenAICompatibleStreamingToolCalls()
                    var providerMetadata: [String: JSONValue] = [:]
                    var didEmitResponseMetadata = false
                    var activeReasoningID: String?
                    var activeTextID: String?
                    var finishReason: String? = "other"
                    var finishUsage: TokenUsage?
                    var startedToolCallIndices: Set<Int> = []
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
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
                        if !didEmitResponseMetadata {
                            didEmitResponseMetadata = true
                            continuation.yield(.responseMetadata(openAICompatibleResponseMetadata(from: raw, response: response, modelID: modelID)))
                        }
                        let choice = raw["choices"]?[0]
                        openAICompatibleMergeProviderMetadata(
                            openAICompatibleChatProviderMetadata(from: raw, choice: choice, providerID: providerID),
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
                            continuation.yield(.reasoningDelta(reasoning))
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
                            continuation.yield(.textDelta(delta))
                            continuation.yield(.textDeltaPart(id: id, delta: delta))
                        }
                        if let toolCallDeltas = delta?["tool_calls"]?.arrayValue {
                            if let reasoningID = activeReasoningID {
                                continuation.yield(.reasoningEnd(id: reasoningID))
                                activeReasoningID = nil
                            }
                            for toolCallDelta in toolCallDeltas {
                                let index = toolCallDelta["index"]?.intValue ?? 0
                                if !startedToolCallIndices.contains(index) {
                                    guard toolCallDelta["id"]?.stringValue != nil else {
                                        throw AIError.invalidResponse(provider: providerID, message: "Expected 'id' to be a string.")
                                    }
                                    guard toolCallDelta["function"]?["name"]?.stringValue != nil else {
                                        throw AIError.invalidResponse(provider: providerID, message: "Expected 'function.name' to be a string.")
                                    }
                                    startedToolCallIndices.insert(index)
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
                    if providerMetadata.isEmpty {
                        continuation.yield(.finish(reason: finishReason, usage: finishUsage))
                    } else {
                        continuation.yield(.finishMetadata(reason: finishReason, usage: finishUsage, providerMetadata: providerMetadata))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func body(for request: LanguageModelRequest, stream: Bool) throws -> [String: JSONValue] {
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
            usesGenericOpenAICompatibleProviderOptions: config.usesGenericOpenAICompatibleProviderOptions
        )
        if stream, config.includeUsage {
            body["stream_options"] = .object(["include_usage": .bool(true)])
        }
        if openAICompatibleProviderRoot(providerID) == "fireworks" {
            body = fireworksChatBody(from: body)
        }
        if openAICompatibleProviderRoot(providerID) == "moonshotai" {
            body = try moonshotChatBody(from: body, request: request)
        }
        if providerID == "googleVertex.xai" {
            body.removeValue(forKey: "reasoning_effort")
        }
        if providerID.hasPrefix("xai.") {
            body = try xaiChatBody(from: body, request: request)
        }
        return config.transformRequestBody?(body) ?? body
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
        usesGenericOpenAICompatibleProviderOptions: Bool
    ) throws -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "messages": .array(try request.messages.map { try Self.messageJSON($0, providerID: providerID) })
        ]
        if stream { body["stream"] = true }
        if let temperature = request.temperature { body["temperature"] = .number(temperature) }
        if let topP = request.topP { body["top_p"] = .number(topP) }
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
        body.merge(openAICompatibleChatOptions(from: extraBody, supportsStructuredOutputs: supportsStructuredOutputs)) { _, new in new }
        return body
    }

    static func messageJSON(_ message: AIMessage, providerID: String) throws -> JSONValue {
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
                .object([
                    "id": .string(call.id),
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(call.name),
                        "arguments": .string(call.arguments)
                    ])
                ])
            })
            return .object(output)
        }

        let textOnly = message.content.allSatisfy {
            if case .text = $0 { true } else { false }
        }

        if textOnly {
            return .object([
                "role": .string(message.role.rawValue),
                "content": .string(message.combinedText)
            ])
        }

        let parts: [JSONValue] = try message.content.map { part in
            switch part {
            case let .text(text, _):
                return .object(["type": .string("text"), "text": .string(text)])
            case let .reasoning(text, _):
                return .object(["type": .string("text"), "text": .string(text)])
            case let .imageURL(url, _):
                return .object(["type": .string("image_url"), "image_url": .object(["url": .string(url)])])
            case let .data(mimeType, data, _), let .file(mimeType, data, _, _):
                return .object([
                    "type": .string("image_url"),
                    "image_url": .object(["url": .string("data:\(mimeType);base64,\(data.base64EncodedString())")])
                ])
            case let .providerReference(_, reference, _, _):
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
            "role": .string(message.role.rawValue),
            "content": .array(parts)
        ])
    }
}
