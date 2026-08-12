import Foundation

public final class DeepSeekLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try deepSeekPreparedCall(
            for: request,
            modelID: modelID,
            stream: false,
            supportsThinking: config.deepSeekSupportsThinking,
            supportsStructuredOutputs: config.supportsStructuredOutputs
        )
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
            let task = Task {
                do {
                    let prepared = try deepSeekPreparedCall(
                        for: request,
                        modelID: modelID,
                        stream: true,
                        supportsThinking: config.deepSeekSupportsThinking,
                        supportsStructuredOutputs: config.supportsStructuredOutputs
                    )
                    let httpRequest = try config.request(
                        path: "/chat/completions",
                        modelID: modelID,
                        body: .object(prepared.body),
                        headers: request.headers,
                        abortSignal: request.abortSignal
                    )
                    let response = try await config.streamRequest(httpRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        throw apiCallError(
                            provider: providerID,
                            response: try await bufferedHTTPResponse(from: response, request: httpRequest)
                        )
                    }
                    let responseHead = httpResponseHead(from: response, request: httpRequest)

                    continuation.yield(.streamStart(warnings: prepared.warnings))
                    var latestUsage: TokenUsage? = TokenUsage()
                    var finishReason: String? = "other"
                    var providerMetadata: [String: JSONValue] = [:]
                    var toolCalls = DeepSeekStreamingToolCalls()
                    var didEmitResponseMetadata = false
                    var activeReasoningID: String?
                    var activeTextID: String?
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
                            continuation.yield(.responseMetadata(aiResponseMetadata(from: raw, response: responseHead, modelID: modelID)))
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
                    continuation.yield(.finishMetadata(
                        reason: finishReason,
                        usage: latestUsage,
                        providerMetadata: providerMetadata
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
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
