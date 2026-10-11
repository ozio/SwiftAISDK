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
        guard let choice = raw["choices"]?.arrayValue?.first else {
            throw AIError.invalidResponse(provider: providerID, message: "Response did not contain any choices.")
        }

        let allToolCalls = groqToolCalls(from: choice["message"]?["tool_calls"])
        let toolCalls = allToolCalls.filter { $0.name != prepared.jsonResponseToolName }
        let reasoning = choice["message"]?["reasoning"]?.stringValue ?? ""
        guard let conversationalText = choice["message"]?["content"]?.stringValue ?? (!allToolCalls.isEmpty || !reasoning.isEmpty ? "" : nil) else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in Groq response.")
        }
        let responseCalls = allToolCalls.filter { $0.name == prepared.jsonResponseToolName }
        let text = prepared.jsonResponseToolName == nil ? conversationalText : responseCalls.map(\.arguments).joined()
        let reason = groqFinishReason(choice["finish_reason"]?.stringValue)
        var content: [AIResultContentPart] = []
        if prepared.jsonResponseToolName != nil {
            if !reasoning.isEmpty { content.append(.reasoning(reasoning)) }
            content += allToolCalls.map { $0.name == prepared.jsonResponseToolName ? .text($0.arguments) : .toolCall($0) }
        }
        return TextGenerationResult(
            text: text,
            content: content,
            reasoning: reasoning,
            finishReason: !responseCalls.isEmpty && toolCalls.isEmpty && reason == "tool-calls" ? "stop" : reason,
            usage: groqUsage(from: raw["usage"]),
            toolCalls: toolCalls,
            rawValue: raw,
            warnings: prepared.warnings,
            requestMetadata: AIRequestMetadata(body: .object(prepared.body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let prepared = try groqPreparedCall(for: request, modelID: modelID, stream: true)
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
                    var latestUsage: TokenUsage?
                    var finishReason: String? = "other"
                    var toolCalls = GroqStreamingToolCalls()
                    var didEmitResponseMetadata = false
                    var activeReasoningID: String?
                    var activeTextID: String?
                    var jsonConverter = GroqJSONResponseToolConverter(name: prepared.jsonResponseToolName)
                    for try await event in serverSentEvents(from: response.body) {
                        if event.data == "[DONE]" { break }
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        if let providerError = groqStreamProviderError(from: raw) {
                            finishReason = "error"
                            continuation.yield(.providerError(providerError))
                            continue
                        }
                        if !didEmitResponseMetadata {
                            didEmitResponseMetadata = true
                            continuation.yield(.responseMetadata(aiResponseMetadata(from: raw, response: responseHead, modelID: modelID)))
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
                        if prepared.jsonResponseToolName != nil, raw["choices"]?[0]?["delta"]?["content"]?.stringValue?.isEmpty == false,
                           let reasoningID = activeReasoningID {
                            continuation.yield(.reasoningEnd(id: reasoningID))
                            activeReasoningID = nil
                        }
                        if prepared.jsonResponseToolName == nil, let delta = raw["choices"]?[0]?["delta"]?["content"]?.stringValue, !delta.isEmpty {
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
                        if let toolCallDeltas = raw["choices"]?[0]?["delta"]?["tool_calls"]?.arrayValue,
                           !toolCallDeltas.isEmpty {
                            if let reasoningID = activeReasoningID {
                                continuation.yield(.reasoningEnd(id: reasoningID))
                                activeReasoningID = nil
                            }
                            for toolCallDelta in toolCallDeltas {
                                for part in toolCalls.apply(delta: toolCallDelta) {
                                    for converted in jsonConverter.convert(part) { continuation.yield(converted) }
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
                        for converted in jsonConverter.convert(part) { continuation.yield(converted) }
                    }
                    continuation.yield(.finishMetadata(
                        reason: jsonConverter.hasResponseTool && !jsonConverter.hasApplicationTool && finishReason == "tool-calls" ? "stop" : finishReason,
                        usage: latestUsage,
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
}

private typealias GroqStreamingToolCalls = OpenAIStyleStreamingToolCalls

struct GroqPreparedCall {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
    var jsonResponseToolName: String? = nil
}

private struct GroqJSONResponseToolConverter {
    var name: String?
    var ids: Set<String> = []
    var idsWithDeltas: Set<String> = []
    var hasResponseTool = false
    var hasApplicationTool = false

    mutating func convert(_ part: LanguageStreamPart) -> [LanguageStreamPart] {
        guard let name else { return [part] }
        switch part {
        case let .toolInputStart(id, toolName, _, _, _, metadata) where toolName == name:
            ids.insert(id)
            return [.textStart(id: id, providerMetadata: metadata)]
        case let .toolInputDelta(id, delta, metadata) where ids.contains(id):
            if !delta.isEmpty { idsWithDeltas.insert(id) }
            return [.textDeltaPart(id: id, delta: delta, providerMetadata: metadata)]
        case let .toolInputEnd(id, _) where ids.contains(id):
            return []
        case let .toolCallDelta(id, toolName, _, _) where toolName == name || id.map(ids.contains) == true:
            return []
        case let .toolCall(call):
            if call.name == name {
                hasResponseTool = true
                var parts: [LanguageStreamPart] = []
                if !ids.contains(call.id) { parts.append(.textStart(id: call.id, providerMetadata: call.providerMetadata)) }
                if !idsWithDeltas.contains(call.id) { parts.append(.textDeltaPart(id: call.id, delta: call.arguments, providerMetadata: call.providerMetadata)) }
                parts.append(.textEnd(id: call.id, providerMetadata: call.providerMetadata))
                return parts
            }
            if !call.providerExecuted { hasApplicationTool = true }
            return [part]
        default:
            return [part]
        }
    }
}

struct GroqPreparedTools {
    var tools: [JSONValue]
    var warnings: [AIWarning]
}
