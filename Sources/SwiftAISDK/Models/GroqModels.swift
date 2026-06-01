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
        let raw = try await config.sendJSON(
            path: "/chat/completions",
            modelID: modelID,
            body: .object(groqBody(for: request, modelID: modelID, stream: false)),
            headers: request.headers
        )
        let choice = raw["choices"]?[0]
        let toolCalls = groqToolCalls(from: choice?["message"]?["tool_calls"])
        guard let text = choice?["message"]?["content"]?.stringValue ?? (toolCalls.isEmpty ? nil : "") else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in Groq response.")
        }
        return TextGenerationResult(
            text: text,
            finishReason: groqFinishReason(choice?["finish_reason"]?.stringValue),
            usage: tokenUsage(from: raw),
            toolCalls: toolCalls,
            rawValue: raw
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await config.transport.send(config.request(
                        path: "/chat/completions",
                        modelID: modelID,
                        body: .object(groqBody(for: request, modelID: modelID, stream: true)),
                        headers: request.headers
                    ))
                    guard (200..<300).contains(response.statusCode) else {
                        throw httpStatusError(provider: providerID, response: response)
                    }
                    var latestUsage: TokenUsage?
                    var toolCalls = GroqStreamingToolCalls()
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        latestUsage = tokenUsage(from: raw["x_groq"] ?? raw) ?? tokenUsage(from: raw) ?? latestUsage
                        if let reasoning = raw["choices"]?[0]?["delta"]?["reasoning"]?.stringValue, !reasoning.isEmpty {
                            continuation.yield(.reasoningDelta(reasoning))
                        }
                        if let delta = raw["choices"]?[0]?["delta"]?["content"]?.stringValue, !delta.isEmpty {
                            continuation.yield(.textDelta(delta))
                        }
                        if let toolCallDeltas = raw["choices"]?[0]?["delta"]?["tool_calls"]?.arrayValue {
                            for toolCallDelta in toolCallDeltas {
                                let update = toolCalls.apply(delta: toolCallDelta)
                                continuation.yield(.toolCallDelta(
                                    id: update.id,
                                    name: update.name,
                                    argumentsDelta: update.argumentsDelta,
                                    index: update.index
                                ))
                            }
                        }
                        if let reason = raw["choices"]?[0]?["finish_reason"]?.stringValue {
                            for toolCall in toolCalls.finishedCalls() {
                                continuation.yield(.toolCall(toolCall))
                            }
                            continuation.yield(.finish(reason: groqFinishReason(reason), usage: latestUsage))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private struct GroqToolCallBuffer {
    var id: String?
    var name: String?
    var arguments: String = ""
    var rawValue: JSONValue?
}

private struct GroqStreamingToolCalls {
    private var buffers: [Int: GroqToolCallBuffer] = [:]

    mutating func apply(delta: JSONValue) -> (id: String?, name: String?, argumentsDelta: String, index: Int?) {
        let index = delta["index"]?.intValue ?? 0
        var buffer = buffers[index] ?? GroqToolCallBuffer()
        if let id = delta["id"]?.stringValue {
            buffer.id = id
        }
        if let name = delta["function"]?["name"]?.stringValue {
            buffer.name = name
        }
        let argumentsDelta = delta["function"]?["arguments"]?.stringValue ?? ""
        buffer.arguments += argumentsDelta
        buffer.rawValue = delta
        buffers[index] = buffer
        return (buffer.id, buffer.name, argumentsDelta, index)
    }

    func finishedCalls() -> [AIToolCall] {
        buffers.keys.sorted().compactMap { index in
            guard let buffer = buffers[index], let name = buffer.name else { return nil }
            return AIToolCall(
                id: buffer.id ?? "tool-call-\(index)",
                name: name,
                arguments: buffer.arguments,
                rawValue: buffer.rawValue
            )
        }
    }
}

public final class GroqTranscriptionModel: TranscriptionModel, @unchecked Sendable {
    public let providerID = "groq.transcription"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        var form = MultipartFormData()
        form.appendField(name: "model", value: modelID)
        form.appendFile(name: "file", fileName: request.fileName, mimeType: request.mimeType, data: request.audio)
        if let language = request.language { form.appendField(name: "language", value: language) }
        if let prompt = request.prompt { form.appendField(name: "prompt", value: prompt) }

        for (key, value) in groqTranscriptionOptions(from: request.extraBody) {
            if case let .array(items) = value {
                for item in items {
                    if let scalar = jsonScalarString(item) {
                        form.appendField(name: "\(key)[]", value: scalar)
                    }
                }
            } else if let scalar = jsonScalarString(value) {
                form.appendField(name: key, value: scalar)
            }
        }

        let body = form.finalize()
        let response = try await config.transport.send(config.rawRequest(
            path: "/audio/transcriptions",
            modelID: modelID,
            body: body,
            contentType: "multipart/form-data; boundary=\(form.boundary)",
            headers: request.headers
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        guard let text = raw["text"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "No transcription text found.")
        }
        return TranscriptionResult(
            text: text,
            rawValue: raw,
            responseMetadata: aiResponseMetadata(from: raw, response: response, modelID: modelID)
        )
    }
}

private func groqBody(for request: LanguageModelRequest, modelID: String, stream: Bool) -> [String: JSONValue] {
    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "messages": .array(request.messages.map(OpenAICompatibleChatModel.messageJSON))
    ]
    if stream { body["stream"] = true }
    if let temperature = request.temperature { body["temperature"] = .number(temperature) }
    if let topP = request.topP { body["top_p"] = .number(topP) }
    if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
    if !request.stopSequences.isEmpty { body["stop"] = .array(request.stopSequences) }
    let tools = groqTools(from: request.tools, modelID: modelID)
    if !tools.isEmpty {
        body["tools"] = .array(tools)
        if let toolChoice = groqToolChoice(from: request.extraBody["toolChoice"]) {
            body["tool_choice"] = toolChoice
        }
    }
    body.merge(groqLanguageOptions(from: request.extraBody)) { _, new in new }
    return body
}

private func groqLanguageOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = groqProviderOptions(from: extraBody)
    moveKey("reasoningFormat", to: "reasoning_format", in: &output)
    moveKey("reasoningEffort", to: "reasoning_effort", in: &output)
    moveKey("parallelToolCalls", to: "parallel_tool_calls", in: &output)
    moveKey("serviceTier", to: "service_tier", in: &output)
    moveKey("structuredOutputs", to: "structured_outputs", in: &output)
    moveKey("strictJsonSchema", to: "strict_json_schema", in: &output)
    output.removeValue(forKey: "toolChoice")
    if let effort = output["reasoning_effort"]?.stringValue {
        output["reasoning_effort"] = .string(groqReasoningEffort(effort))
    }
    return output
}

private func groqTranscriptionOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = groqProviderOptions(from: extraBody)
    moveKey("responseFormat", to: "response_format", in: &output)
    moveKey("timestampGranularities", to: "timestamp_granularities", in: &output)
    return output
}

private func groqProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "groq")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func moveKey(_ source: String, to destination: String, in values: inout [String: JSONValue]) {
    if let value = values.removeValue(forKey: source) {
        values[destination] = value
    }
}

private func groqTools(from tools: [String: JSONValue], modelID: String) -> [JSONValue] {
    tools.compactMap { name, schema in
        let object = schema.objectValue
        let providerToolID = object?["id"]?.stringValue
        if object?["type"]?.stringValue == "provider" || providerToolID != nil || name == "groq.browser_search" {
            guard (providerToolID ?? name) == "groq.browser_search",
                  groqBrowserSearchSupportedModels.contains(modelID) else {
                return nil
            }
            return .object(["type": .string("browser_search")])
        }

        var parameters = schema
        var function: [String: JSONValue] = [
            "name": .string(name),
            "parameters": parameters
        ]
        if var parameterObject = parameters.objectValue {
            if let description = parameterObject["description"]?.stringValue {
                function["description"] = .string(description)
            }
            if let strict = parameterObject.removeValue(forKey: "strict") {
                function["strict"] = strict
                parameters = .object(parameterObject)
                function["parameters"] = parameters
            }
        }
        return .object([
            "type": .string("function"),
            "function": .object(function)
        ])
    }
}

private func groqToolChoice(from value: JSONValue?) -> JSONValue? {
    if let string = value?.stringValue {
        switch string {
        case "auto", "none", "required":
            return .string(string)
        default:
            return nil
        }
    }
    guard let object = value?.objectValue else { return nil }
    switch object["type"]?.stringValue {
    case "auto", "none", "required":
        return object["type"]
    case "tool":
        guard let toolName = object["toolName"]?.stringValue ?? object["tool_name"]?.stringValue else {
            return nil
        }
        return .object([
            "type": .string("function"),
            "function": .object(["name": .string(toolName)])
        ])
    default:
        return nil
    }
}

private func groqToolCalls(from value: JSONValue?) -> [AIToolCall] {
    value?.arrayValue?.enumerated().compactMap { index, item in
        guard let name = item["function"]?["name"]?.stringValue else { return nil }
        return AIToolCall(
            id: item["id"]?.stringValue ?? "tool-call-\(index)",
            name: name,
            arguments: item["function"]?["arguments"]?.stringValue ?? "",
            rawValue: item
        )
    } ?? []
}

private func groqFinishReason(_ reason: String?) -> String? {
    switch reason {
    case "stop":
        return "stop"
    case "length":
        return "length"
    case "content_filter":
        return "content-filter"
    case "function_call", "tool_calls":
        return "tool-calls"
    case nil:
        return nil
    default:
        return "other"
    }
}

private let groqBrowserSearchSupportedModels: Set<String> = [
    "openai/gpt-oss-20b",
    "openai/gpt-oss-120b"
]

private func groqReasoningEffort(_ value: String) -> String {
    switch value {
    case "minimal":
        return "low"
    case "xhigh":
        return "high"
    default:
        return value
    }
}
