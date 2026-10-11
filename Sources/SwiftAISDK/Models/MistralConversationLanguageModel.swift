import Foundation

/// Mistral's stateless Conversations API, including provider-executed web search.
public final class MistralConversationLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "mistral.conversation"
    public let modelID: String
    public let supportedURLs: [String: [AISupportedURLPattern]] = ["application/pdf": [AISupportedURLPattern { $0.hasPrefix("https://") }]]
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) { self.modelID = modelID; self.config = config }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try mistralConversationPreparedCall(request, modelID: modelID, stream: false)
        let response = try await config.sendJSONResponse(path: "/conversations", modelID: modelID, body: .object(prepared.body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        guard let conversationID = raw["conversation_id"]?.stringValue, let outputs = raw["outputs"]?.arrayValue,
              outputs.allSatisfy(mistralConversationValidOutput), mistralConversationValidUsage(raw["usage"]) else {
            throw AIError.invalidResponse(provider: providerID, message: "Invalid Mistral Conversations response.")
        }
        var converter = MistralConversationContentConverter(tools: request.tools)
        var content: [AIResultContentPart] = []
        var hasFunctionCalls = false
        var responseModel: String?
        for output in outputs {
            switch output["type"]?.stringValue {
            case "tool.execution": content += converter.tool(output)
            case "function.call":
                hasFunctionCalls = true
                let arguments = output["arguments"]!.stringValue ?? mistralJSONString(output["arguments"]!)!
                content.append(.toolCall(AIToolCall(id: output["tool_call_id"]!.stringValue!, name: output["name"]!.stringValue!, arguments: arguments, rawValue: output)))
            case "message.output":
                responseModel = output["model"]?.stringValue ?? responseModel
                let chunks = output["content"]!.stringValue.map { [JSONValue.object(["type": "text", "text": .string($0)])] } ?? output["content"]!.arrayValue!
                for chunk in chunks { content += converter.chunk(chunk) }
            default: break
            }
        }
        return TextGenerationResult(text: content.compactMap { if case let .text(text, _) = $0 { text } else { nil } }.joined(), content: content,
                                    reasoning: content.compactMap { if case let .reasoning(text, _) = $0 { text } else { nil } }.joined(),
                                    finishReason: hasFunctionCalls ? "tool-calls" : "stop", usage: mistralConversationUsage(raw["usage"]), rawValue: raw, warnings: prepared.warnings,
                                    requestMetadata: AIRequestMetadata(body: .object(prepared.body), headers: request.headers),
                                    responseMetadata: AIResponseMetadata(id: conversationID, modelID: responseModel, headers: response.response.headers, body: raw))
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let prepared = try mistralConversationPreparedCall(request, modelID: modelID, stream: true)
                    let http = try config.request(path: "/conversations", modelID: modelID, body: .object(prepared.body), headers: request.headers, abortSignal: request.abortSignal)
                    let response = try await config.streamRequest(http)
                    guard (200..<300).contains(response.statusCode) else { throw apiCallError(provider: providerID, response: try await bufferedHTTPResponse(from: response, request: http)) }
                    continuation.yield(.streamStart(warnings: prepared.warnings))
                    var converter = MistralConversationContentConverter(tools: request.tools)
                    var state = MistralConversationStreamState()
                    for try await event in serverSentEvents(from: response.body) {
                        if event.data == "[DONE]" { break }
                        let raw: JSONValue
                        do { raw = try decodeJSONBody(Data(event.data.utf8)) }
                        catch { state.hasError = true; continuation.yield(.error(message: "Invalid Mistral Conversations JSON event.")); continue }
                        if request.includeRawChunks { continuation.yield(.raw(raw)) }
                        guard mistralConversationValidChunk(raw) else { state.hasError = true; continuation.yield(.error(message: "Invalid Mistral Conversations event.", rawValue: raw)); continue }
                        switch raw["type"]?.stringValue {
                        case "conversation.response.started":
                            continuation.yield(.responseMetadata(AIResponseMetadata(id: raw["conversation_id"]?.stringValue, timestamp: raw["created_at"]?.stringValue.flatMap(mistralConversationDate), headers: response.headers)))
                        case "conversation.response.done": state.isDone = true; state.usage = mistralConversationUsage(raw["usage"])
                        case "conversation.response.error": state.hasError = true; continuation.yield(.error(message: raw["message"]!.stringValue!, rawValue: raw))
                        case "message.output.delta":
                            if !state.hasModelID, let model = raw["model"]?.stringValue { state.hasModelID = true; continuation.yield(.responseMetadata(AIResponseMetadata(modelID: model))) }
                            let chunk = raw["content"]!.stringValue.map { JSONValue.object(["type": "text", "text": .string($0)]) } ?? raw["content"]!
                            for content in converter.chunk(chunk) {
                                let id = "\(raw["id"]!.stringValue!)-\(raw["content_index"]?.intValue ?? 0)"
                                switch content {
                                case let .text(text, _):
                                    for part in state.open(id: id, reasoning: false) { continuation.yield(part) }
                                    continuation.yield(.textDeltaPart(id: id, delta: text))
                                case let .reasoning(text, _):
                                    for part in state.open(id: id, reasoning: true) { continuation.yield(part) }
                                    continuation.yield(.reasoningDeltaPart(id: id, delta: text))
                                case let .source(source): continuation.yield(.source(source))
                                default: break
                                }
                            }
                        case "function.call.delta":
                            for part in state.closeContent() { continuation.yield(part) }
                            state.hasFunctionCalls = true
                            var delta: [String: JSONValue] = ["id": raw["tool_call_id"]!, "function": .object(["name": raw["name"]!, "arguments": raw["arguments"]!])]
                            if let index = raw["output_index"], index != .null { delta["index"] = index }
                            for part in state.toolCalls.apply(delta: .object(delta)) { continuation.yield(part) }
                        case "tool.execution.started", "tool.execution.delta":
                            for part in state.closeContent() { continuation.yield(part) }
                            let id = raw["id"]!.stringValue!
                            if var existing = state.executions[id] {
                                existing["arguments"] = .string((existing["arguments"]?.stringValue ?? "") + raw["arguments"]!.stringValue!)
                                state.executions[id] = existing
                            } else {
                                state.executions[id] = raw.objectValue!
                                continuation.yield(.toolInputStart(id: id, name: converter.mapping.toCustom(raw["name"]!.stringValue!), providerExecuted: true))
                            }
                        case "tool.execution.done":
                            let id = raw["id"]!.stringValue!
                            guard var execution = state.executions.removeValue(forKey: id) else {
                                state.hasError = true; continuation.yield(.error(message: "Missing tool execution start for \(id)", rawValue: raw)); continue
                            }
                            execution["type"] = "tool.execution"
                            if let function = raw["function"], function != .null { execution["function"] = function }
                            execution["info"] = raw["info"]
                            let arguments = mistralJSONString(.object(["arguments": execution["arguments"]!]))!
                            continuation.yield(.toolInputDelta(id: id, delta: arguments))
                            continuation.yield(.toolInputEnd(id: id))
                            for part in converter.tool(.object(execution)) {
                                switch part { case let .toolCall(call): continuation.yield(.toolCall(call)); case let .toolResult(result): continuation.yield(.toolResult(result)); default: break }
                            }
                        default: break
                        }
                    }
                    for part in state.closeContent() { continuation.yield(part) }
                    for part in state.toolCalls.finishedParts() { continuation.yield(part) }
                    continuation.yield(.finishMetadata(reason: state.hasError || !state.isDone || !state.executions.isEmpty ? "error" : state.hasFunctionCalls ? "tool-calls" : "stop", usage: state.usage))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

private struct MistralConversationContentConverter {
    let mapping: MistralConversationToolMapping
    var sourceURLs: Set<String> = []
    init(tools: [String: JSONValue]) { mapping = MistralConversationToolMapping(tools: tools) }
    mutating func chunk(_ chunk: JSONValue) -> [AIResultContentPart] {
        switch chunk["type"]?.stringValue {
        case "text": return chunk["text"]!.stringValue!.isEmpty ? [] : [.text(chunk["text"]!.stringValue!)]
        case "thinking":
            let text = chunk["thinking"]!.arrayValue!.compactMap { $0["text"]?.stringValue }.joined()
            return text.isEmpty ? [] : [.reasoning(text)]
        case "tool_reference":
            guard let url = chunk["url"]?.stringValue, sourceURLs.insert(url).inserted else { return [] }
            return [.source(AISource(id: UUID().uuidString, sourceType: "url", url: url, title: chunk["title"]?.stringValue ?? url))]
        default: return []
        }
    }
    func tool(_ output: JSONValue) -> [AIResultContentPart] {
        let id = output["id"]!.stringValue!
        let providerName = output["name"]!.stringValue!
        let name = mapping.toCustom(providerName)
        var metadata: [String: JSONValue] = ["type": "tool.execution", "name": .string(providerName)]
        if let function = output["function"], function != .null { metadata["function"] = function }
        let call = AIToolCall(id: id, name: name, arguments: mistralJSONString(.object(["arguments": output["arguments"]!]))!, providerExecuted: true, providerMetadata: ["mistral": .object(metadata)], rawValue: output)
        let info = output["info"].flatMap { $0 == .null ? nil : $0 }
        let result = AIToolResult(toolCallID: id, toolName: name, result: .object(info.map { ["info": $0] } ?? [:]), providerExecuted: true)
        return [.toolCall(call), .toolResult(result)]
    }
}

private struct MistralConversationStreamState {
    var active: (id: String, reasoning: Bool)?
    var executions: [String: [String: JSONValue]] = [:]
    var toolCalls = OpenAIStyleStreamingToolCalls()
    var usage: TokenUsage?
    var hasFunctionCalls = false
    var hasError = false
    var isDone = false
    var hasModelID = false
    mutating func closeContent() -> [LanguageStreamPart] {
        guard let active else { return [] }
        self.active = nil
        return [active.reasoning ? .reasoningEnd(id: active.id) : .textEnd(id: active.id)]
    }
    mutating func open(id: String, reasoning: Bool) -> [LanguageStreamPart] {
        if active?.id == id, active?.reasoning == reasoning { return [] }
        let closed = closeContent()
        active = (id, reasoning)
        return closed + [reasoning ? .reasoningStart(id: id) : .textStart(id: id)]
    }
}

private func mistralConversationValidContent(_ value: JSONValue) -> Bool {
    switch value["type"]?.stringValue {
    case "text": return value["text"]?.stringValue != nil
    case "thinking": return value["thinking"]?.arrayValue?.allSatisfy { $0["type"] == "text" && $0["text"]?.stringValue != nil } == true
    case "tool_reference": return ["tool", "title", "url"].allSatisfy { mistralConversationNullableString(value[$0]) }
    default: return false
    }
}
private func mistralConversationValidOutput(_ value: JSONValue) -> Bool {
    switch value["type"]?.stringValue {
    case "tool.execution": return ["id", "name", "arguments"].allSatisfy { value[$0]?.stringValue != nil } && mistralConversationNullableString(value["function"]) && (value["info"] == nil || value["info"] == .null || value["info"]?.objectValue != nil)
    case "function.call": return ["tool_call_id", "name"].allSatisfy { value[$0]?.stringValue != nil } && (value["arguments"]?.stringValue != nil || value["arguments"]?.objectValue != nil)
    case "message.output": return mistralConversationNullableString(value["model"]) && (value["content"]?.stringValue != nil || value["content"]?.arrayValue?.allSatisfy(mistralConversationValidContent) == true)
    default: return false
    }
}
private func mistralConversationValidChunk(_ value: JSONValue) -> Bool {
    switch value["type"]?.stringValue {
    case "conversation.response.started": return value["conversation_id"]?.stringValue != nil && mistralConversationNullableString(value["created_at"])
    case "conversation.response.done": return mistralConversationValidUsage(value["usage"])
    case "conversation.response.error": return value["message"]?.stringValue != nil && value["code"]?.doubleValue != nil
    case "message.output.delta": return value["id"]?.stringValue != nil && mistralConversationNullableString(value["model"]) && mistralConversationNullableNumber(value["content_index"]) && (value["content"]?.stringValue != nil || value["content"].map(mistralConversationValidContent) == true)
    case "function.call.delta": return ["tool_call_id", "name", "arguments"].allSatisfy { value[$0]?.stringValue != nil } && mistralConversationNullableNumber(value["output_index"])
    case "tool.execution.started", "tool.execution.delta": return ["id", "name", "arguments"].allSatisfy { value[$0]?.stringValue != nil } && mistralConversationNullableString(value["function"])
    case "tool.execution.done": return ["id", "name"].allSatisfy { value[$0]?.stringValue != nil } && mistralConversationNullableString(value["function"]) && (value["info"] == nil || value["info"] == .null || value["info"]?.objectValue != nil)
    default: return false
    }
}
private func mistralConversationValidUsage(_ value: JSONValue?) -> Bool {
    guard let value, value != .null else { return true }
    guard value.objectValue != nil, ["prompt_tokens", "completion_tokens", "total_tokens"].allSatisfy({ value[$0] == nil || value[$0]?.doubleValue != nil }) else { return false }
    for key in ["prompt_audio_seconds", "request_count", "num_cached_tokens"] where !mistralConversationNullableNumber(value[key]) { return false }
    guard mistralConversationNullableString(value["service_tier"]) else { return false }
    for key in ["prompt_tokens_details", "prompt_token_details", "completion_tokens_details"] {
        guard let details = value[key], details != .null else { continue }
        guard details.objectValue != nil else { return false }
        let numberKeys = key == "completion_tokens_details" ? ["reasoning_tokens"] : ["cached_tokens", "audio_tokens"]
        guard numberKeys.allSatisfy({ mistralConversationNullableNumber(details[$0]) }) else { return false }
        if key != "completion_tokens_details", let messages = details["messages"], messages != .null, messages.arrayValue == nil { return false }
    }
    return true
}
private func mistralConversationUsage(_ value: JSONValue?) -> TokenUsage? {
    guard let value, var usage = value.objectValue else { return nil }
    for key in ["prompt_tokens", "completion_tokens", "total_tokens"] where usage[key] == nil { usage[key] = 0 }
    return mistralUsage(from: .object(["usage": .object(usage)]))
}
private func mistralConversationNullableString(_ value: JSONValue?) -> Bool { value == nil || value == .null || value?.stringValue != nil }
private func mistralConversationNullableNumber(_ value: JSONValue?) -> Bool { value == nil || value == .null || value?.doubleValue?.isFinite == true }
private func mistralConversationDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}
