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
                    var latestUsage: TokenUsage? = TokenUsage()
                    var finishReason: String? = "other"
                    var providerMetadata: [String: JSONValue] = [:]
                    var toolCalls = DeepSeekStreamingToolCalls()
                    var didEmitResponseMetadata = false
                    var activeReasoningID: String?
                    var activeTextID: String?
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
                        if let error = raw["error"] {
                            finishReason = "error"
                            continuation.yield(.error(
                                message: error["message"]?.stringValue ?? deepSeekJSONString(error) ?? "DeepSeek stream error.",
                                rawValue: error
                            ))
                            continue
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
                        if let finishReasonValue = raw["choices"]?[0]?["finish_reason"], finishReasonValue != .null {
                            finishReason = deepSeekFinishReason(finishReasonValue.stringValue)
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

typealias DeepSeekStreamingToolCalls = OpenAIStyleStreamingToolCalls

struct DeepSeekPreparedCall {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
}

struct DeepSeekPreparedMessages {
    var messages: [JSONValue]
    var warnings: [AIWarning]
}

struct DeepSeekPreparedTools {
    var tools: [JSONValue]
    var warnings: [AIWarning]
}

