import Foundation

public enum GatewayTools {
    public static func perplexitySearch(
        maxResults: Int? = nil,
        maxTokensPerPage: Int? = nil,
        maxTokens: Int? = nil,
        country: String? = nil,
        searchDomainFilter: [String] = [],
        searchLanguageFilter: [String] = [],
        searchRecencyFilter: String? = nil
    ) -> JSONValue {
        var args: [String: JSONValue] = [:]
        if let maxResults { args["maxResults"] = .number(Double(maxResults)) }
        if let maxTokensPerPage { args["maxTokensPerPage"] = .number(Double(maxTokensPerPage)) }
        if let maxTokens { args["maxTokens"] = .number(Double(maxTokens)) }
        if let country { args["country"] = .string(country) }
        if !searchDomainFilter.isEmpty { args["searchDomainFilter"] = .array(searchDomainFilter) }
        if !searchLanguageFilter.isEmpty { args["searchLanguageFilter"] = .array(searchLanguageFilter) }
        if let searchRecencyFilter { args["searchRecencyFilter"] = .string(searchRecencyFilter) }
        return providerTool(id: "gateway.perplexity_search", name: "perplexity_search", args: args)
    }

    public static func parallelSearch(
        mode: String? = nil,
        maxResults: Int? = nil,
        includeDomains: [String] = [],
        excludeDomains: [String] = [],
        afterDate: String? = nil,
        maxCharsPerResult: Int? = nil,
        maxCharsTotal: Int? = nil,
        maxAgeSeconds: Int? = nil
    ) -> JSONValue {
        var args: [String: JSONValue] = [:]
        if let mode { args["mode"] = .string(mode) }
        if let maxResults { args["maxResults"] = .number(Double(maxResults)) }
        let sourcePolicy = JSONValue.object([
            "includeDomains": includeDomains.isEmpty ? nil : .array(includeDomains),
            "excludeDomains": excludeDomains.isEmpty ? nil : .array(excludeDomains),
            "afterDate": afterDate.map(JSONValue.string)
        ])
        if sourcePolicy.objectValue?.isEmpty == false {
            args["sourcePolicy"] = sourcePolicy
        }
        let excerpts = JSONValue.object([
            "maxCharsPerResult": maxCharsPerResult.map { .number(Double($0)) },
            "maxCharsTotal": maxCharsTotal.map { .number(Double($0)) }
        ])
        if excerpts.objectValue?.isEmpty == false {
            args["excerpts"] = excerpts
        }
        let fetchPolicy = JSONValue.object([
            "maxAgeSeconds": maxAgeSeconds.map { .number(Double($0)) }
        ])
        if fetchPolicy.objectValue?.isEmpty == false {
            args["fetchPolicy"] = fetchPolicy
        }
        return providerTool(id: "gateway.parallel_search", name: "parallel_search", args: args)
    }

    private static func providerTool(id: String, name: String, args: [String: JSONValue]) -> JSONValue {
        .object([
            "type": .string("provider"),
            "id": .string(id),
            "name": .string(name),
            "args": .object(args)
        ])
    }
}

public final class GatewayLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let body = gatewayLanguageBody(for: request)
        let response = try await config.sendJSONResponse(path: "/language-model", modelID: modelID, body: body, headers: request.headers.mergingHeaders(modelHeaders(streaming: false)))
        let raw = response.json
        let text = parseGatewayText(from: raw)
        let toolCalls = gatewayToolCalls(from: raw["content"])
        let sources = gatewaySources(from: raw["content"])
        guard text != nil || !toolCalls.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in Gateway language response.")
        }
        return TextGenerationResult(
            text: text ?? "",
            finishReason: gatewayFinishReason(raw["finishReason"]?.stringValue ?? raw["finish_reason"]?.stringValue, hasToolCalls: !toolCalls.isEmpty),
            usage: tokenUsage(from: raw),
            toolCalls: toolCalls,
            sources: sources,
            rawValue: raw,
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await config.transport.send(
                        config.request(path: "/language-model", modelID: modelID, body: gatewayLanguageBody(for: request), headers: request.headers.mergingHeaders(modelHeaders(streaming: true)))
                    )
                    guard (200..<300).contains(response.statusCode) else {
                        throw apiCallError(provider: providerID, response: response)
                    }
                    continuation.yield(.responseMetadata(aiResponseMetadata(response: response, modelID: modelID)))
                    var toolBuffers: [String: GatewayStreamingToolCall] = [:]
                    var sawToolCalls = false
                    for event in parseServerSentEvents(response.body) {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        let type = raw["type"]?.stringValue
                        if request.includeRawChunks, type == "raw", let rawValue = raw["rawValue"] {
                            continuation.yield(.raw(rawValue))
                        }
                        if let delta = raw["delta"]?.stringValue
                            ?? raw["textDelta"]?.stringValue
                            ?? raw["text"]?.stringValue,
                           type == nil || type == "text-delta" || type == "delta" {
                            continuation.yield(.textDelta(delta))
                        }
                        if type == "reasoning-delta", let delta = raw["delta"]?.stringValue ?? raw["textDelta"]?.stringValue {
                            continuation.yield(.reasoningDelta(delta))
                        }
                        if type == "source", let source = gatewaySource(from: raw, fallbackIndex: 0) {
                            continuation.yield(.source(source))
                        } else if type == "tool-input-start" {
                            let id = raw["id"]?.stringValue ?? raw["toolCallId"]?.stringValue ?? "tool-call-\(toolBuffers.count)"
                            let name = raw["toolName"]?.stringValue ?? raw["tool_name"]?.stringValue ?? raw["name"]?.stringValue ?? ""
                            toolBuffers[id] = GatewayStreamingToolCall(
                                id: id,
                                name: name,
                                arguments: "",
                                providerExecuted: raw["providerExecuted"]?.boolValue ?? false,
                                rawValue: raw
                            )
                            continuation.yield(.toolInputStart(
                                id: id,
                                name: name,
                                providerExecuted: raw["providerExecuted"]?.boolValue ?? false,
                                providerMetadata: gatewayProviderMetadata(raw["providerMetadata"])
                            ))
                        } else if type == "tool-input-delta" {
                            let id = raw["id"]?.stringValue ?? raw["toolCallId"]?.stringValue
                            let delta = raw["delta"]?.stringValue ?? raw["inputDelta"]?.stringValue ?? ""
                            if let id {
                                if var buffer = toolBuffers[id] {
                                    buffer.arguments += delta
                                    toolBuffers[id] = buffer
                                } else {
                                    toolBuffers[id] = GatewayStreamingToolCall(id: id, name: "", arguments: delta, providerExecuted: false, rawValue: raw)
                                }
                            }
                            continuation.yield(.toolCallDelta(id: id, name: toolBuffers[id ?? ""]?.name, argumentsDelta: delta, index: nil))
                            if let id, !delta.isEmpty {
                                continuation.yield(.toolInputDelta(id: id, delta: delta, providerMetadata: gatewayProviderMetadata(raw["providerMetadata"])))
                            }
                        } else if type == "tool-input-end" {
                            let id = raw["id"]?.stringValue ?? raw["toolCallId"]?.stringValue
                            if let id, let buffer = toolBuffers.removeValue(forKey: id), !buffer.name.isEmpty {
                                sawToolCalls = true
                                continuation.yield(.toolInputEnd(id: id, providerMetadata: gatewayProviderMetadata(raw["providerMetadata"])))
                                continuation.yield(.toolCall(buffer.toolCall))
                            }
                        } else if type == "tool-call", let toolCall = gatewayToolCall(from: raw, fallbackIndex: toolBuffers.count) {
                            sawToolCalls = true
                            continuation.yield(.toolInputStart(id: toolCall.id, name: toolCall.name, providerExecuted: toolCall.providerExecuted, providerMetadata: toolCall.providerMetadata))
                            continuation.yield(.toolCallDelta(id: toolCall.id, name: toolCall.name, argumentsDelta: toolCall.arguments, index: nil))
                            if !toolCall.arguments.isEmpty {
                                continuation.yield(.toolInputDelta(id: toolCall.id, delta: toolCall.arguments, providerMetadata: toolCall.providerMetadata))
                            }
                            continuation.yield(.toolInputEnd(id: toolCall.id, providerMetadata: toolCall.providerMetadata))
                            continuation.yield(.toolCall(toolCall))
                        }
                        if type == "finish" || type == "finish-step" {
                            let hasToolCalls = sawToolCalls || !toolBuffers.isEmpty
                            for buffer in toolBuffers.values where !buffer.name.isEmpty {
                                continuation.yield(.toolInputEnd(id: buffer.id))
                                continuation.yield(.toolCall(buffer.toolCall))
                            }
                            toolBuffers.removeAll()
                            continuation.yield(.finish(reason: gatewayFinishReason(raw["finishReason"]?.stringValue ?? raw["finish_reason"]?.stringValue, hasToolCalls: hasToolCalls), usage: tokenUsage(from: raw)))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func gatewayLanguageBody(for request: LanguageModelRequest) -> JSONValue {
        var body: [String: JSONValue] = [
            "prompt": .array(request.messages.map { message in
                .object([
                    "role": .string(message.role.rawValue),
                    "content": .array(message.content.map { part in
                        switch part {
                        case let .text(text, _):
                            return .object(["type": .string("text"), "text": .string(text)])
                        case let .reasoning(text, providerMetadata):
                            return .object(["type": .string("reasoning"), "text": .string(text), "providerMetadata": .object(providerMetadata)])
                        case let .imageURL(url, _):
                            return .object([
                                "type": .string("file"),
                                "data": .object(["type": .string("url"), "url": .string(url)])
                            ])
                        case let .data(mimeType, data, _):
                            return .object([
                                "type": .string("file"),
                                "mediaType": .string(mimeType),
                                "data": .object(["type": .string("data"), "data": .string(data.base64EncodedString())])
                            ])
                        case let .file(mimeType, data, filename, _):
                            var file: [String: JSONValue] = [
                                "type": .string("file"),
                                "mediaType": .string(mimeType),
                                "data": .object(["type": .string("data"), "data": .string(data.base64EncodedString())])
                            ]
                            if let filename { file["filename"] = .string(filename) }
                            return .object(file)
                        case let .reasoningFile(file):
                            var output: [String: JSONValue] = [
                                "type": .string("reasoning-file"),
                                "mediaType": .string(file.mediaType)
                            ]
                            if let id = file.id { output["id"] = .string(id) }
                            if let filename = file.filename { output["filename"] = .string(filename) }
                            if let data = file.data {
                                output["data"] = .object(["type": .string("data"), "data": .string(data.base64EncodedString())])
                            } else if let url = file.url {
                                output["data"] = .object(["type": .string("url"), "url": .string(url)])
                            }
                            return .object(output)
                        case let .custom(value, providerMetadata):
                            return .object(["type": .string("custom"), "value": value, "providerMetadata": .object(providerMetadata)])
                        case let .providerReference(mimeType, reference, _, _):
                            return .object([
                                "type": .string("file"),
                                "mediaType": .string(mimeType),
                                "data": .object(["type": .string("reference"), "reference": .object(reference.mapValues(JSONValue.string))])
                            ])
                        case let .toolCall(call):
                            return .object([
                                "type": .string("tool-call"),
                                "toolCallId": .string(call.id),
                                "toolName": .string(call.name),
                                "args": gatewayToolArguments(call.arguments)
                            ])
                        case let .toolResult(result):
                            return .object([
                                "type": .string("tool-result"),
                                "toolCallId": .string(result.toolCallID),
                                "toolName": .string(result.toolName),
                                "result": result.modelOutput ?? result.result
                            ])
                        case .toolApprovalRequest, .toolApprovalResponse:
                            return .object(["type": .string("text"), "text": .string("")])
                        }
                    })
                ])
            })
        ]
        if let temperature = request.temperature { body["temperature"] = .number(temperature) }
        if let topP = request.topP { body["topP"] = .number(topP) }
        if let topK = request.topK { body["topK"] = .number(Double(topK)) }
        if let presencePenalty = request.presencePenalty { body["presencePenalty"] = .number(presencePenalty) }
        if let frequencyPenalty = request.frequencyPenalty { body["frequencyPenalty"] = .number(frequencyPenalty) }
        if let seed = request.seed { body["seed"] = .number(Double(seed)) }
        if let maxOutputTokens = request.maxOutputTokens { body["maxOutputTokens"] = .number(Double(maxOutputTokens)) }
        if !request.stopSequences.isEmpty { body["stopSequences"] = .array(request.stopSequences) }
        if let reasoning = request.reasoning { body["reasoning"] = .string(reasoning) }
        if !request.providerOptions.isEmpty { body["providerOptions"] = .object(request.providerOptions) }
        let tools = gatewayTools(from: request.tools)
        if !tools.isEmpty {
            body["tools"] = .array(tools)
            if let toolChoice = gatewayToolChoice(from: request.extraBody["toolChoice"]) {
                body["toolChoice"] = toolChoice
            }
        }
        body.merge(request.extraBody) { _, new in new }
        return .object(body)
    }

    private func modelHeaders(streaming: Bool) -> [String: String] {
        [
            "ai-language-model-specification-version": "4",
            "ai-language-model-id": modelID,
            "ai-language-model-streaming": String(streaming)
        ]
    }
}

private func gatewayToolArguments(_ arguments: String) -> JSONValue {
    (try? decodeJSONBody(Data(arguments.utf8))) ?? .object([:])
}
