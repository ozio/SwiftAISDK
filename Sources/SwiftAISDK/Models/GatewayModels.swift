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
        let raw = try await config.sendJSON(path: "/language-model", modelID: modelID, body: body, headers: request.headers.mergingHeaders(modelHeaders(streaming: false)))
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
            rawValue: raw
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
                        throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
                    }
                    var toolBuffers: [String: GatewayStreamingToolCall] = [:]
                    var sawToolCalls = false
                    for event in parseServerSentEvents(response.body) {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        continuation.yield(.raw(raw))
                        let type = raw["type"]?.stringValue
                        if type == "raw", let rawValue = raw["rawValue"] {
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
                        } else if type == "tool-input-end" {
                            let id = raw["id"]?.stringValue ?? raw["toolCallId"]?.stringValue
                            if let id, let buffer = toolBuffers.removeValue(forKey: id), !buffer.name.isEmpty {
                                sawToolCalls = true
                                continuation.yield(.toolCall(buffer.toolCall))
                            }
                        } else if type == "tool-call", let toolCall = gatewayToolCall(from: raw, fallbackIndex: toolBuffers.count) {
                            sawToolCalls = true
                            continuation.yield(.toolCallDelta(id: toolCall.id, name: toolCall.name, argumentsDelta: toolCall.arguments, index: nil))
                            continuation.yield(.toolCall(toolCall))
                        }
                        if type == "finish" || type == "finish-step" {
                            let hasToolCalls = sawToolCalls || !toolBuffers.isEmpty
                            for buffer in toolBuffers.values where !buffer.name.isEmpty {
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
                        case let .text(text):
                            return .object(["type": .string("text"), "text": .string(text)])
                        case let .imageURL(url):
                            return .object([
                                "type": .string("file"),
                                "data": .object(["type": .string("url"), "url": .string(url)])
                            ])
                        case let .data(mimeType, data):
                            return .object([
                                "type": .string("file"),
                                "mediaType": .string(mimeType),
                                "data": .object(["type": .string("data"), "data": .string(data.base64EncodedString())])
                            ])
                        case let .file(mimeType, data, filename):
                            var file: [String: JSONValue] = [
                                "type": .string("file"),
                                "mediaType": .string(mimeType),
                                "data": .object(["type": .string("data"), "data": .string(data.base64EncodedString())])
                            ]
                            if let filename { file["filename"] = .string(filename) }
                            return .object(file)
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
                                "result": result.result
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
        if let maxOutputTokens = request.maxOutputTokens { body["maxOutputTokens"] = .number(Double(maxOutputTokens)) }
        if !request.stopSequences.isEmpty { body["stopSequences"] = .array(request.stopSequences) }
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

public final class GatewayEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        var body: [String: JSONValue] = ["values": .array(request.values)]
        body.merge(request.extraBody) { _, new in new }
        let raw = try await config.sendJSON(path: "/embedding-model", modelID: modelID, body: .object(body), headers: request.headers.mergingHeaders([
            "ai-embedding-model-specification-version": "4",
            "ai-model-id": modelID
        ]))
        guard let embeddings = raw["embeddings"]?.arrayValue?.map({ item in item.arrayValue?.compactMap(\.doubleValue) ?? [] }) else {
            throw AIError.invalidResponse(provider: providerID, message: "No embeddings found in Gateway response.")
        }
        return EmbeddingResult(embeddings: embeddings, usage: gatewayEmbeddingUsage(from: raw), rawValue: raw)
    }
}

private func gatewayEmbeddingUsage(from raw: JSONValue) -> TokenUsage? {
    if let tokens = raw["usage"]?["tokens"]?.intValue {
        return TokenUsage(totalTokens: tokens)
    }
    return tokenUsage(from: raw)
}

public final class GatewayImageModel: ImageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        var body: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let count = request.count { body["n"] = .number(Double(count)) }
        if let size = request.size { body["size"] = .string(size) }
        body.merge(request.extraBody) { _, new in new }
        if !request.files.isEmpty {
            body["files"] = .array(request.files.map(gatewayImageFile))
        }
        if let mask = request.mask {
            body["mask"] = gatewayImageFile(mask)
        }
        let raw = try await config.sendJSON(path: "/image-model", modelID: modelID, body: .object(body), headers: request.headers.mergingHeaders([
            "ai-image-model-specification-version": "4",
            "ai-model-id": modelID
        ]))
        let images = raw["images"]?.arrayValue ?? raw["data"]?.arrayValue ?? []
        return ImageGenerationResult(
            urls: images.compactMap { $0["url"]?.stringValue },
            base64Images: images.compactMap { $0["data"]?.stringValue ?? $0.stringValue ?? $0["b64_json"]?.stringValue },
            rawValue: raw
        )
    }
}

private func gatewayImageFile(_ file: ImageInputFile) -> JSONValue {
    if let url = file.url {
        return .object([
            "type": .string("url"),
            "url": .string(url)
        ])
    }
    return .object([
        "type": .string("file"),
        "mediaType": .string(file.mediaType ?? "application/octet-stream"),
        "data": .string((file.data ?? Data()).base64EncodedString())
    ])
}

public final class GatewayVideoModel: VideoModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        var body: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let aspectRatio = request.aspectRatio { body["aspectRatio"] = .string(aspectRatio) }
        if let durationSeconds = request.durationSeconds { body["duration"] = .number(durationSeconds) }
        body.merge(request.extraBody) { _, new in new }
        let httpRequest = try config.request(path: "/video-model", modelID: modelID, body: .object(body), headers: request.headers.mergingHeaders([
            "ai-video-model-specification-version": "4",
            "ai-model-id": modelID,
            "accept": "text/event-stream"
        ]))
        let response = try await config.transport.send(httpRequest)
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
        }
        let raw: JSONValue
        if let event = parseServerSentEvents(response.body).first(where: { $0.data != "[DONE]" }) {
            raw = try decodeJSONBody(Data(event.data.utf8))
        } else {
            raw = try response.jsonValue()
        }
        if raw["type"]?.stringValue == "error" {
            throw AIError.httpStatus(
                provider: providerID,
                statusCode: raw["statusCode"]?.intValue ?? response.statusCode,
                body: raw["message"]?.stringValue ?? String(describing: raw)
            )
        }
        let videos = raw["videos"]?.arrayValue ?? raw["data"]?.arrayValue ?? []
        return VideoGenerationResult(
            urls: videos.compactMap { $0["url"]?.stringValue ?? $0.stringValue },
            operationID: raw["id"]?.stringValue,
            rawValue: raw
        )
    }
}

public final class GatewayRerankingModel: RerankingModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func rerank(_ request: RerankingRequest) async throws -> RerankingResult {
        var body: [String: JSONValue] = [
            "query": .string(request.query),
            "documents": .array(request.documents)
        ]
        if let topK = request.topK { body["topN"] = .number(Double(topK)) }
        body.merge(request.extraBody) { _, new in new }
        let raw = try await config.sendJSON(path: "/reranking-model", modelID: modelID, body: .object(body), headers: request.headers.mergingHeaders([
            "ai-reranking-model-specification-version": "4",
            "ai-model-id": modelID
        ]))
        let ranking = raw["ranking"]?.arrayValue ?? raw["results"]?.arrayValue ?? []
        return RerankingResult(results: ranking.compactMap { item in
            guard let index = item["index"]?.intValue,
                  let score = item["relevanceScore"]?.doubleValue ?? item["relevance_score"]?.doubleValue ?? item["score"]?.doubleValue else {
                return nil
            }
            return RerankedDocument(index: index, score: score)
        }, rawValue: raw)
    }
}

public final class GatewaySpeechModel: SpeechModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        var body: [String: JSONValue] = ["text": .string(request.text)]
        if let voice = request.voice { body["voice"] = .string(voice) }
        if let format = request.format { body["outputFormat"] = .string(format) }
        body.merge(request.extraBody) { _, new in new }
        let raw = try await config.sendJSON(path: "/speech-model", modelID: modelID, body: .object(body), headers: request.headers.mergingHeaders([
            "ai-speech-model-specification-version": "4",
            "ai-model-id": modelID
        ]))
        guard let audio = raw["audio"]?.stringValue, let data = Data(base64Encoded: audio) else {
            throw AIError.invalidResponse(provider: providerID, message: "No base64 audio found in Gateway speech response.")
        }
        return SpeechResult(audio: data)
    }
}

public final class GatewayTranscriptionModel: TranscriptionModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        var body: [String: JSONValue] = [
            "audio": .string(request.audio.base64EncodedString()),
            "mediaType": .string(request.mimeType)
        ]
        body.merge(request.extraBody) { _, new in new }
        let raw = try await config.sendJSON(path: "/transcription-model", modelID: modelID, body: .object(body), headers: request.headers.mergingHeaders([
            "ai-transcription-model-specification-version": "4",
            "ai-model-id": modelID
        ]))
        guard let text = raw["text"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "No text found in Gateway transcription response.")
        }
        return TranscriptionResult(text: text, rawValue: raw)
    }
}

private struct GatewayStreamingToolCall {
    var id: String
    var name: String
    var arguments: String
    var providerExecuted: Bool
    var rawValue: JSONValue

    var toolCall: AIToolCall {
        AIToolCall(
            id: id,
            name: name,
            arguments: arguments.isEmpty ? "{}" : arguments,
            providerExecuted: providerExecuted,
            rawValue: rawValue
        )
    }
}

private func parseGatewayText(from raw: JSONValue) -> String? {
    if let text = raw["text"]?.stringValue ?? raw["output_text"]?.stringValue {
        return text
    }
    let contentText = gatewayContentParts(raw["content"]).compactMap { part in
        part["text"]?.stringValue
    }.joined()
    if !contentText.isEmpty {
        return contentText
    }
    return raw["choices"]?[0]?["message"]?["content"]?.stringValue
}

private func gatewayTools(from tools: [String: JSONValue]) -> [JSONValue] {
    tools.map { name, schema in
        let object = schema.objectValue
        if object?["type"]?.stringValue == "provider" || object?["id"]?.stringValue?.hasPrefix("gateway.") == true {
            return .object([
                "type": .string("provider"),
                "id": .string(object?["id"]?.stringValue ?? name),
                "name": .string(object?["name"]?.stringValue ?? name),
                "args": .object(object?["args"]?.objectValue ?? [:])
            ])
        }
        var tool: [String: JSONValue] = [
            "type": .string("function"),
            "name": .string(name),
            "inputSchema": schema
        ]
        if let description = object?["description"]?.stringValue {
            tool["description"] = .string(description)
        }
        return .object(tool)
    }
}

private func gatewayToolChoice(from value: JSONValue?) -> JSONValue? {
    if let string = value?.stringValue {
        switch string {
        case "auto", "none", "required":
            return .object(["type": .string(string)])
        default:
            return nil
        }
    }
    guard let object = value?.objectValue else { return nil }
    switch object["type"]?.stringValue {
    case "auto", "none", "required":
        return .object(["type": object["type"] ?? .string("auto")])
    case "tool":
        guard let toolName = object["toolName"]?.stringValue ?? object["tool_name"]?.stringValue else { return nil }
        return .object(["type": .string("tool"), "toolName": .string(toolName)])
    default:
        return nil
    }
}

private func gatewayContentParts(_ content: JSONValue?) -> [JSONValue] {
    if let array = content?.arrayValue { return array }
    if let content { return [content] }
    return []
}

private func gatewayToolCalls(from content: JSONValue?) -> [AIToolCall] {
    gatewayContentParts(content).enumerated().compactMap { index, part in
        gatewayToolCall(from: part, fallbackIndex: index)
    }
}

private func gatewaySources(from content: JSONValue?) -> [AISource] {
    gatewayContentParts(content).enumerated().compactMap { index, part in
        gatewaySource(from: part, fallbackIndex: index)
    }
}

private func gatewaySource(from value: JSONValue, fallbackIndex: Int) -> AISource? {
    guard value["type"]?.stringValue == "source" else { return nil }
    let sourceType = value["sourceType"]?.stringValue ?? value["source_type"]?.stringValue ?? "url"
    let id = value["id"]?.stringValue ?? "source-\(fallbackIndex)"
    return AISource(
        id: id,
        sourceType: sourceType,
        url: value["url"]?.stringValue,
        title: value["title"]?.stringValue,
        mediaType: value["mediaType"]?.stringValue ?? value["media_type"]?.stringValue,
        filename: value["filename"]?.stringValue,
        providerMetadata: value["providerMetadata"]?.objectValue ?? value["provider_metadata"]?.objectValue ?? [:],
        rawValue: value
    )
}

private func gatewayToolCall(from value: JSONValue, fallbackIndex: Int) -> AIToolCall? {
    guard value["type"]?.stringValue == "tool-call" else { return nil }
    let name = value["toolName"]?.stringValue ?? value["tool_name"]?.stringValue ?? value["name"]?.stringValue
    guard let name else { return nil }
    let id = value["toolCallId"]?.stringValue ?? value["tool_call_id"]?.stringValue ?? value["id"]?.stringValue ?? "tool-call-\(fallbackIndex)"
    return AIToolCall(
        id: id,
        name: name,
        arguments: gatewayToolArguments(value["input"] ?? value["arguments"]),
        providerExecuted: value["providerExecuted"]?.boolValue ?? false,
        rawValue: value
    )
}

private func gatewayToolArguments(_ value: JSONValue?) -> String {
    guard let value else { return "{}" }
    if let string = value.stringValue { return string }
    guard let data = try? encodeJSONBody(value), let text = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return text
}

private func gatewayFinishReason(_ value: String?, hasToolCalls: Bool) -> String? {
    guard let value else {
        return hasToolCalls ? "tool-calls" : nil
    }
    if value == "tool_calls" {
        return "tool-calls"
    }
    return hasToolCalls && value == "stop" ? "tool-calls" : value
}
