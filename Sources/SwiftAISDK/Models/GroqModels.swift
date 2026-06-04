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
                        throw apiCallError(provider: providerID, response: response)
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

struct GroqPreparedCall {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
}

struct GroqPreparedTools {
    var tools: [JSONValue]
    var warnings: [AIWarning]
}
