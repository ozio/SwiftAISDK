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
        let httpResponse = try await config.transport.send(config.request(
            path: "/chat/completions",
            modelID: modelID,
            body: .object(prepared.body),
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw cerebrasHTTPStatusError(response: httpResponse)
        }
        let response = (json: try httpResponse.jsonValue(), response: httpResponse)
        let raw = response.json
        let choice = raw["choices"]?[0]
        let toolCalls = cerebrasToolCalls(from: choice?["message"]?["tool_calls"])
        guard let text = choice?["message"]?["content"]?.stringValue ?? (toolCalls.isEmpty ? nil : "") else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in Cerebras response.")
        }
        let rawFinishReason = choice?["finish_reason"]?.stringValue
        let finishReason = cerebrasFinishReason(
            rawFinishReason,
            hasText: !text.isEmpty,
            normalizeStructuredToolCalls: prepared.normalizesStructuredToolCalls
        )
        return TextGenerationResult(
            text: text,
            reasoning: choice?["message"]?["reasoning"]?.stringValue ?? "",
            finishReason: finishReason,
            usage: cerebrasUsage(from: raw) ?? TokenUsage(),
            toolCalls: cerebrasShouldDropStructuredToolCalls(
                hasText: !text.isEmpty,
                normalizeStructuredToolCalls: prepared.normalizesStructuredToolCalls
            ) ? [] : toolCalls,
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
                        throw cerebrasHTTPStatusError(response: response)
                    }

                    continuation.yield(.streamStart(warnings: prepared.warnings))
                    var latestUsage: TokenUsage? = TokenUsage()
                    var hasText = false
                    var finishReason: String? = "other"
                    var toolCalls = CerebrasStreamingToolCalls()
                    var emittedResponseMetadata = false
                    var providerMetadata: [String: JSONValue] = [:]
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
                        if let streamError = cerebrasStreamError(from: raw) {
                            finishReason = "error"
                            continuation.yield(.error(message: streamError.message, rawValue: streamError.rawValue))
                            continue
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
                           !cerebrasShouldDropStructuredToolCalls(
                               hasText: hasText,
                               normalizeStructuredToolCalls: prepared.normalizesStructuredToolCalls
                           ) {
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
                        if let reason = raw["choices"]?[0]?["finish_reason"]?.stringValue {
                            finishReason = cerebrasFinishReason(
                                reason,
                                hasText: hasText,
                                normalizeStructuredToolCalls: prepared.normalizesStructuredToolCalls
                            )
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

typealias CerebrasStreamingToolCalls = OpenAIStyleStreamingToolCalls

struct CerebrasPreparedCall {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
    var normalizesStructuredToolCalls: Bool
}

struct CerebrasPreparedTools {
    var tools: [JSONValue]
    var warnings: [AIWarning]
}

