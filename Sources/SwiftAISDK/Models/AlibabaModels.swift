import Foundation

public final class AlibabaLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "alibaba.chat"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try alibabaPreparedCall(
            for: request,
            modelID: modelID,
            stream: false,
            transformRequestBody: config.transformRequestBody
        )
        let httpResponse = try await config.transport.send(config.request(
            path: "/chat/completions",
            modelID: modelID,
            body: .object(prepared.body),
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw alibabaHTTPStatusError(provider: providerID, response: httpResponse)
        }
        let response = (json: try httpResponse.jsonValue(), response: httpResponse)
        let raw = response.json
        let choice = raw["choices"]?[0]
        let toolCalls = alibabaToolCalls(from: choice?["message"]?["tool_calls"])
        guard let text = choice?["message"]?["content"]?.stringValue ?? (toolCalls.isEmpty ? nil : "") else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in Alibaba response.")
        }
        return TextGenerationResult(
            text: text,
            reasoning: choice?["message"]?["reasoning_content"]?.stringValue ?? "",
            finishReason: alibabaFinishReason(choice?["finish_reason"]?.stringValue),
            usage: alibabaUsage(from: raw) ?? TokenUsage(inputTokensNoCache: 0, inputTokensCacheWrite: 0),
            toolCalls: toolCalls,
            rawValue: raw,
            warnings: prepared.warnings,
            responseMetadata: alibabaResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = try alibabaPreparedCall(
                        for: request,
                        modelID: modelID,
                        stream: true,
                        transformRequestBody: config.transformRequestBody
                    )
                    let response = try await config.transport.send(config.request(
                        path: "/chat/completions",
                        modelID: modelID,
                        body: .object(prepared.body),
                        headers: request.headers,
                        abortSignal: request.abortSignal
                    ))
                    guard (200..<300).contains(response.statusCode) else {
                        throw alibabaHTTPStatusError(provider: providerID, response: response)
                    }

                    continuation.yield(.streamStart(warnings: prepared.warnings))
                    var latestUsage: TokenUsage? = TokenUsage(inputTokensNoCache: 0, inputTokensCacheWrite: 0)
                    var finishReason: String? = "other"
                    var toolCalls = AlibabaStreamingToolCalls()
                    var emittedResponseMetadata = false
                    var activeText = false
                    var activeReasoningID: String?
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
                        if let streamError = alibabaStreamError(from: raw) {
                            finishReason = "error"
                            continuation.yield(.error(message: streamError.message, rawValue: streamError.rawValue))
                            continue
                        }
                        if !emittedResponseMetadata {
                            emittedResponseMetadata = true
                            continuation.yield(.responseMetadata(alibabaResponseMetadata(from: raw, response: response, modelID: modelID)))
                        }
                        latestUsage = alibabaUsage(from: raw) ?? latestUsage
                        guard let choice = raw["choices"]?[0] else { continue }

                        if let reasoning = choice["delta"]?["reasoning_content"]?.stringValue, !reasoning.isEmpty {
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
                        if let delta = choice["delta"]?["content"]?.stringValue, !delta.isEmpty {
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
                        if let toolCallDeltas = choice["delta"]?["tool_calls"]?.arrayValue {
                            if let reasoningID = activeReasoningID {
                                continuation.yield(.reasoningEnd(id: reasoningID))
                                activeReasoningID = nil
                            }
                            if activeText {
                                continuation.yield(.textEnd(id: "0"))
                                activeText = false
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
                        if let reason = choice["finish_reason"]?.stringValue {
                            finishReason = alibabaFinishReason(reason)
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
                    continuation.yield(.finish(reason: finishReason, usage: latestUsage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

