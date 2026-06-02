import Foundation

public enum AnthropicTools {
    public static func advisor_20260301(model: String, maxUses: Int? = nil, caching: JSONValue? = nil) -> JSONValue {
        providerTool(id: "anthropic.advisor_20260301", name: "advisor", args: JSONValue.object([
            "model": .string(model),
            "maxUses": maxUses.map { .number(Double($0)) },
            "caching": caching
        ]).objectValue ?? [:])
    }

    public static func bash_20241022() -> JSONValue {
        providerTool(id: "anthropic.bash_20241022", name: "bash")
    }

    public static func bash_20250124() -> JSONValue {
        providerTool(id: "anthropic.bash_20250124", name: "bash")
    }

    public static func codeExecution_20250522() -> JSONValue {
        providerTool(id: "anthropic.code_execution_20250522", name: "code_execution")
    }

    public static func codeExecution_20250825() -> JSONValue {
        providerTool(id: "anthropic.code_execution_20250825", name: "code_execution")
    }

    public static func codeExecution_20260120() -> JSONValue {
        providerTool(id: "anthropic.code_execution_20260120", name: "code_execution")
    }

    public static func computer_20241022(displayWidthPx: Int, displayHeightPx: Int, displayNumber: Int? = nil) -> JSONValue {
        computerTool(id: "anthropic.computer_20241022", displayWidthPx: displayWidthPx, displayHeightPx: displayHeightPx, displayNumber: displayNumber)
    }

    public static func computer_20250124(displayWidthPx: Int, displayHeightPx: Int, displayNumber: Int? = nil) -> JSONValue {
        computerTool(id: "anthropic.computer_20250124", displayWidthPx: displayWidthPx, displayHeightPx: displayHeightPx, displayNumber: displayNumber)
    }

    public static func computer_20251124(displayWidthPx: Int, displayHeightPx: Int, displayNumber: Int? = nil, enableZoom: Bool? = nil) -> JSONValue {
        providerTool(id: "anthropic.computer_20251124", name: "computer", args: JSONValue.object([
            "displayWidthPx": .number(Double(displayWidthPx)),
            "displayHeightPx": .number(Double(displayHeightPx)),
            "displayNumber": displayNumber.map { .number(Double($0)) },
            "enableZoom": enableZoom.map(JSONValue.bool)
        ]).objectValue ?? [:])
    }

    public static func memory_20250818() -> JSONValue {
        providerTool(id: "anthropic.memory_20250818", name: "memory")
    }

    public static func textEditor_20241022() -> JSONValue {
        providerTool(id: "anthropic.text_editor_20241022", name: "str_replace_editor")
    }

    public static func textEditor_20250124() -> JSONValue {
        providerTool(id: "anthropic.text_editor_20250124", name: "str_replace_editor")
    }

    public static func textEditor_20250429() -> JSONValue {
        providerTool(id: "anthropic.text_editor_20250429", name: "str_replace_based_edit_tool")
    }

    public static func textEditor_20250728(maxCharacters: Int? = nil) -> JSONValue {
        providerTool(id: "anthropic.text_editor_20250728", name: "str_replace_based_edit_tool", args: JSONValue.object([
            "maxCharacters": maxCharacters.map { .number(Double($0)) }
        ]).objectValue ?? [:])
    }

    public static func webFetch_20250910(maxUses: Int? = nil, allowedDomains: [String]? = nil, blockedDomains: [String]? = nil, citations: JSONValue? = nil, maxContentTokens: Int? = nil) -> JSONValue {
        webTool(id: "anthropic.web_fetch_20250910", name: "web_fetch", maxUses: maxUses, allowedDomains: allowedDomains, blockedDomains: blockedDomains, citations: citations, maxContentTokens: maxContentTokens)
    }

    public static func webFetch_20260209(maxUses: Int? = nil, allowedDomains: [String]? = nil, blockedDomains: [String]? = nil, citations: JSONValue? = nil, maxContentTokens: Int? = nil) -> JSONValue {
        webTool(id: "anthropic.web_fetch_20260209", name: "web_fetch", maxUses: maxUses, allowedDomains: allowedDomains, blockedDomains: blockedDomains, citations: citations, maxContentTokens: maxContentTokens)
    }

    public static func webSearch_20250305(maxUses: Int? = nil, allowedDomains: [String]? = nil, blockedDomains: [String]? = nil, userLocation: JSONValue? = nil) -> JSONValue {
        webTool(id: "anthropic.web_search_20250305", name: "web_search", maxUses: maxUses, allowedDomains: allowedDomains, blockedDomains: blockedDomains, userLocation: userLocation)
    }

    public static func webSearch_20260209(maxUses: Int? = nil, allowedDomains: [String]? = nil, blockedDomains: [String]? = nil, userLocation: JSONValue? = nil) -> JSONValue {
        webTool(id: "anthropic.web_search_20260209", name: "web_search", maxUses: maxUses, allowedDomains: allowedDomains, blockedDomains: blockedDomains, userLocation: userLocation)
    }

    public static func toolSearchRegex_20251119() -> JSONValue {
        providerTool(id: "anthropic.tool_search_regex_20251119", name: "tool_search_tool_regex")
    }

    public static func toolSearchBm25_20251119() -> JSONValue {
        providerTool(id: "anthropic.tool_search_bm25_20251119", name: "tool_search_tool_bm25")
    }

    static func providerTool(id: String, name: String, args: [String: JSONValue] = [:]) -> JSONValue {
        .object([
            "type": .string("provider"),
            "id": .string(id),
            "name": .string(name),
            "args": .object(args)
        ])
    }

    private static func computerTool(id: String, displayWidthPx: Int, displayHeightPx: Int, displayNumber: Int?) -> JSONValue {
        providerTool(id: id, name: "computer", args: JSONValue.object([
            "displayWidthPx": .number(Double(displayWidthPx)),
            "displayHeightPx": .number(Double(displayHeightPx)),
            "displayNumber": displayNumber.map { .number(Double($0)) }
        ]).objectValue ?? [:])
    }

    private static func webTool(
        id: String,
        name: String,
        maxUses: Int?,
        allowedDomains: [String]?,
        blockedDomains: [String]?,
        citations: JSONValue? = nil,
        maxContentTokens: Int? = nil,
        userLocation: JSONValue? = nil
    ) -> JSONValue {
        providerTool(id: id, name: name, args: JSONValue.object([
            "maxUses": maxUses.map { .number(Double($0)) },
            "allowedDomains": allowedDomains.map { .array($0.map(JSONValue.string)) },
            "blockedDomains": blockedDomains.map { .array($0.map(JSONValue.string)) },
            "citations": citations,
            "maxContentTokens": maxContentTokens.map { .number(Double($0)) },
            "userLocation": userLocation
        ]).objectValue ?? [:])
    }
}

public enum GoogleVertexAnthropicTools {
    public static func bash_20241022() -> JSONValue { AnthropicTools.bash_20241022() }
    public static func bash_20250124() -> JSONValue { AnthropicTools.bash_20250124() }
    public static func computer_20241022(displayWidthPx: Int, displayHeightPx: Int, displayNumber: Int? = nil) -> JSONValue {
        AnthropicTools.computer_20241022(displayWidthPx: displayWidthPx, displayHeightPx: displayHeightPx, displayNumber: displayNumber)
    }
    public static func textEditor_20241022() -> JSONValue { AnthropicTools.textEditor_20241022() }
    public static func textEditor_20250124() -> JSONValue { AnthropicTools.textEditor_20250124() }
    public static func textEditor_20250429() -> JSONValue { AnthropicTools.textEditor_20250429() }
    public static func textEditor_20250728(maxCharacters: Int? = nil) -> JSONValue { AnthropicTools.textEditor_20250728(maxCharacters: maxCharacters) }
    public static func webSearch_20250305(maxUses: Int? = nil, allowedDomains: [String]? = nil, blockedDomains: [String]? = nil, userLocation: JSONValue? = nil) -> JSONValue {
        AnthropicTools.webSearch_20250305(maxUses: maxUses, allowedDomains: allowedDomains, blockedDomains: blockedDomains, userLocation: userLocation)
    }
    public static func toolSearchRegex_20251119() -> JSONValue { AnthropicTools.toolSearchRegex_20251119() }
    public static func toolSearchBm25_20251119() -> JSONValue { AnthropicTools.toolSearchBm25_20251119() }
}

public final class AnthropicLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let preparedRequest = try Self.body(for: request, modelID: modelID, providerID: providerID)
        var body = preparedRequest.body
        body["stream"] = nil
        let path: String
        if providerID == "googleVertex.anthropic.messages" {
            body.removeValue(forKey: "model")
            body["anthropic_version"] = .string("vertex-2023-10-16")
            path = "/\(modelID):rawPredict"
        } else {
            path = "/messages"
        }
        let response = try await config.sendJSONResponse(
            path: path,
            modelID: modelID,
            body: .object(body),
            headers: anthropicHeaders(request.headers, configHeaders: config.headers, betas: preparedRequest.betas)
        )
        let raw = response.json
        let toolCalls = anthropicToolCalls(from: raw["content"])
        let toolResults = anthropicToolResults(from: raw["content"], providerID: providerID)
        let sources = anthropicSources(from: raw["content"], citationDocuments: anthropicCitationDocuments(from: request.messages))
        let text = raw["content"]?.arrayValue?.compactMap { part in
            part["text"]?.stringValue
        }.joined()
        guard let text else {
            throw AIError.invalidResponse(provider: providerID, message: "No text block found in Anthropic response.")
        }
        return TextGenerationResult(
            text: text,
            finishReason: anthropicFinishReason(raw["stop_reason"]?.stringValue),
            usage: TokenUsage(
                inputTokens: raw["usage"]?["input_tokens"]?.intValue,
                outputTokens: raw["usage"]?["output_tokens"]?.intValue
            ),
            toolCalls: toolCalls,
            toolResults: toolResults,
            sources: sources,
            providerMetadata: anthropicProviderMetadata(from: raw, providerID: providerID),
            rawValue: raw,
            warnings: preparedRequest.warnings,
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let preparedRequest = try Self.body(for: request, modelID: modelID, providerID: providerID, stream: true)
                    var body = preparedRequest.body
                    let path: String
                    if providerID == "googleVertex.anthropic.messages" {
                        body.removeValue(forKey: "model")
                        body["anthropic_version"] = .string("vertex-2023-10-16")
                        path = "/\(modelID):streamRawPredict"
                    } else {
                        path = "/messages"
                    }
                    let response = try await config.transport.send(config.request(
                        path: path,
                        modelID: modelID,
                        body: .object(body),
                        headers: anthropicHeaders(request.headers, configHeaders: config.headers, betas: preparedRequest.betas)
                    ))
                    guard (200..<300).contains(response.statusCode) else {
                        throw httpStatusError(provider: providerID, response: response)
                    }
                    continuation.yield(.responseMetadata(aiResponseMetadata(response: response, modelID: modelID)))
                    continuation.yield(.streamStart(warnings: preparedRequest.warnings))
                    var contentBlocks = AnthropicStreamingContentBlocks(providerID: providerID)
                    var providerToolResults = AnthropicStreamingProviderToolResults(providerID: providerID)
                    var toolCalls = AnthropicStreamingToolCalls()
                    let citationDocuments = anthropicCitationDocuments(from: request.messages)
                    var sourceCounter = 0
                    var finishReason: String?
                    var finishUsage: TokenUsage?
                    var rawUsage: JSONValue?
                    var stopSequence: JSONValue = .null
                    var container: JSONValue = .null
                    var contextManagement: JSONValue = .null
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        switch raw["type"]?.stringValue {
                        case "message_start":
                            if let usage = raw["message"]?["usage"] {
                                rawUsage = usage
                            }
                            if let value = anthropicContainerMetadata(from: raw["message"]?["container"]) {
                                container = value
                            }
                            if let reason = raw["message"]?["stop_reason"]?.stringValue {
                                finishReason = anthropicFinishReason(reason)
                            }
                        case "message_delta":
                            finishReason = anthropicFinishReason(raw["delta"]?["stop_reason"]?.stringValue)
                            stopSequence = raw["delta"]?["stop_sequence"] ?? stopSequence
                            finishUsage = TokenUsage(
                                inputTokens: raw["usage"]?["input_tokens"]?.intValue,
                                outputTokens: raw["usage"]?["output_tokens"]?.intValue
                            )
                            if let usage = raw["usage"] {
                                rawUsage = rawUsage.map { anthropicMergedUsage($0, usage) } ?? usage
                            }
                            if let value = anthropicContainerMetadata(from: raw["delta"]?["container"]) {
                                container = value
                            }
                            if let value = anthropicContextManagementMetadata(from: raw["context_management"]) {
                                contextManagement = value
                            }
                        default:
                            break
                        }
                        for part in contentBlocks.apply(event: raw) {
                            continuation.yield(part)
                        }
                        for part in providerToolResults.apply(event: raw) {
                            continuation.yield(part)
                        }
                        for source in anthropicSources(from: raw, citationDocuments: citationDocuments, sourceCounter: &sourceCounter) {
                            continuation.yield(.source(source))
                        }
                        for part in toolCalls.apply(event: raw) {
                            continuation.yield(part)
                        }
                        if raw["type"]?.stringValue == "message_stop" {
                            continuation.yield(.finishMetadata(
                                reason: finishReason,
                                usage: finishUsage,
                                providerMetadata: anthropicProviderMetadata(
                                    usage: rawUsage,
                                    stopSequence: stopSequence,
                                    container: container,
                                    contextManagement: contextManagement,
                                    providerID: providerID
                                )
                            ))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    fileprivate static func body(for request: LanguageModelRequest, modelID: String, providerID: String, stream: Bool = false) throws -> AnthropicPreparedCall {
        let systemText = request.messages
            .filter { $0.role == .system }
            .map(\.combinedText)
            .joined(separator: "\n")
        var betas: [String] = []
        var warnings = anthropicStandardWarnings(for: request)
        let messages = try request.messages
            .filter { $0.role != .system }
            .map { try Self.messageJSON($0, providerID: providerID, betas: &betas) }

        let temperature = anthropicClampedTemperature(request.temperature, warnings: &warnings)
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "messages": .array(messages),
            "max_tokens": .number(Double(request.maxOutputTokens ?? 1024))
        ]
        if stream { body["stream"] = true }
        if !systemText.isEmpty { body["system"] = .string(systemText) }
        if let temperature { body["temperature"] = .number(temperature) }
        if let topK = request.topK { body["top_k"] = .number(Double(topK)) }
        if let topP = request.topP { body["top_p"] = .number(topP) }
        if !request.stopSequences.isEmpty { body["stop_sequences"] = .array(request.stopSequences) }
        let preparedTools = anthropicPrepareTools(from: request.tools)
        if !preparedTools.tools.isEmpty {
            body["tools"] = .array(preparedTools.tools)
        }
        let providerOptions = try anthropicOptions(from: request)
        body.merge(providerOptions.body) { _, new in new }
        anthropicApplyResponseFormat(request.responseFormat, to: &body, warnings: &warnings)
        applyAnthropicThinkingRules(
            to: &body,
            requestedMaxTokens: request.maxOutputTokens,
            requestTemperature: temperature,
            requestTopP: request.topP,
            warnings: &warnings
        )
        if anthropicContainerHasSkills(body), !preparedTools.hasCodeExecution {
            warnings.append(AIWarning(
                type: "other",
                message: "code execution tool is required when using skills"
            ))
        }
        for beta in providerOptions.betas where !betas.contains(beta) {
            betas.append(beta)
        }
        for beta in preparedTools.betas where !betas.contains(beta) {
            betas.append(beta)
        }
        return AnthropicPreparedCall(body: body, betas: betas, warnings: warnings)
    }

    private static func messageJSON(_ message: AIMessage, providerID: String, betas: inout [String]) throws -> JSONValue {
        let role = message.role == .assistant ? "assistant" : "user"
        let parts = try message.content.map { part -> JSONValue in
            switch part {
            case let .text(text):
                return .object(["type": .string("text"), "text": .string(text)])
            case let .imageURL(url):
                if url.lowercased().contains(".pdf") {
                    return .object([
                        "type": .string("document"),
                        "source": .object([
                            "type": .string("url"),
                            "url": .string(url)
                        ])
                    ])
                }
                return .object([
                    "type": .string("image"),
                    "source": .object([
                        "type": .string("url"),
                        "url": .string(url)
                    ])
                ])
            case let .data(mimeType, data), let .file(mimeType, data, _):
                let lowercasedMimeType = mimeType.lowercased()
                if lowercasedMimeType == "application/pdf" {
                    return .object([
                        "type": .string("document"),
                        "source": .object([
                            "type": .string("base64"),
                            "media_type": .string("application/pdf"),
                            "data": .string(data.base64EncodedString())
                        ])
                    ])
                }
                if lowercasedMimeType == "text/plain" {
                    return .object([
                        "type": .string("document"),
                        "source": .object([
                            "type": .string("text"),
                            "media_type": .string("text/plain"),
                            "data": .string(String(data: data, encoding: .utf8) ?? data.base64EncodedString())
                        ])
                    ])
                }
                return .object([
                    "type": .string("image"),
                    "source": .object([
                        "type": .string("base64"),
                        "media_type": .string(mimeType),
                        "data": .string(data.base64EncodedString())
                    ])
                ])
            case let .providerReference(mimeType, reference):
                let provider = anthropicProviderReferenceKey(from: providerID)
                let fileID = try resolveProviderReference(reference, provider: provider)
                if !betas.contains("files-api-2025-04-14") {
                    betas.append("files-api-2025-04-14")
                }
                let type = mimeType.lowercased().hasPrefix("image/") ? "image" : "document"
                return .object([
                    "type": .string(type),
                    "source": .object([
                        "type": .string("file"),
                        "file_id": .string(fileID)
                    ])
                ])
            case let .toolCall(call):
                return .object([
                    "type": .string("tool_use"),
                    "id": .string(call.id),
                    "name": .string(call.name),
                    "input": anthropicToolArguments(call.arguments)
                ])
            case let .toolResult(result):
                return .object([
                    "type": .string("tool_result"),
                    "tool_use_id": .string(result.toolCallID),
                    "content": .string(anthropicJSONString(result.modelOutput ?? result.result) ?? result.modelOutput?.stringValue ?? result.result.stringValue ?? "")
                ])
            case .toolApprovalRequest, .toolApprovalResponse:
                return .object(["type": .string("text"), "text": .string("")])
            }
        }
        return .object(["role": .string(role), "content": .array(parts)])
    }
}

fileprivate struct AnthropicPreparedCall {
    var body: [String: JSONValue]
    var betas: [String]
    var warnings: [AIWarning]
}

public final class AmazonBedrockAnthropicLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "bedrock.anthropic.messages"
    public let modelID: String
    private let config: BedrockRuntimeConfig

    init(modelID: String, config: BedrockRuntimeConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try await preparedCall(for: request)
        let body = amazonBedrockAnthropicBody(prepared.body, betas: prepared.betas)
        let response = try await config.sendJSONResponse(path: "/model/\(bedrockEncodeModelID(modelID))/invoke", body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let toolCalls = anthropicToolCalls(from: raw["content"])
        let toolResults = anthropicToolResults(from: raw["content"], providerID: providerID)
        let sources = anthropicSources(from: raw["content"], citationDocuments: anthropicCitationDocuments(from: request.messages))
        let text = raw["content"]?.arrayValue?.compactMap { part in
            part["text"]?.stringValue
        }.joined()
        guard let text = text ?? (toolCalls.isEmpty ? nil : "") else {
            throw AIError.invalidResponse(provider: providerID, message: "No text block found in Bedrock Anthropic response.")
        }
        return TextGenerationResult(
            text: text,
            finishReason: anthropicFinishReason(raw["stop_reason"]?.stringValue),
            usage: TokenUsage(
                inputTokens: raw["usage"]?["input_tokens"]?.intValue,
                outputTokens: raw["usage"]?["output_tokens"]?.intValue
            ),
            toolCalls: toolCalls,
            toolResults: toolResults,
            sources: sources,
            providerMetadata: anthropicProviderMetadata(from: raw, providerID: providerID),
            rawValue: raw,
            warnings: prepared.warnings,
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = try await preparedCall(for: request, stream: true)
                    let body = amazonBedrockAnthropicBody(prepared.body, betas: prepared.betas)
                    let response = try await config.transport.send(try config.request(
                        path: "/model/\(bedrockEncodeModelID(modelID))/invoke-with-response-stream",
                        body: .object(body),
                        headers: request.headers.mergingHeaders(["accept": "application/vnd.amazon.eventstream"]),
                        abortSignal: request.abortSignal
                    ))
                    guard (200..<300).contains(response.statusCode) else {
                        throw httpStatusError(provider: providerID, response: response)
                    }
                    continuation.yield(.responseMetadata(aiResponseMetadata(response: response, modelID: modelID)))
                    continuation.yield(.streamStart(warnings: prepared.warnings))

                    var contentBlocks = AnthropicStreamingContentBlocks(providerID: providerID)
                    var providerToolResults = AnthropicStreamingProviderToolResults(providerID: providerID)
                    var toolCalls = AnthropicStreamingToolCalls()
                    let citationDocuments = anthropicCitationDocuments(from: request.messages)
                    var sourceCounter = 0
                    for raw in try amazonBedrockAnthropicStreamEvents(from: response) {
                        if raw["type"]?.stringValue == "error" {
                            let message = raw["error"]?["message"]?.stringValue ?? raw["message"]?.stringValue ?? "Bedrock Anthropic stream returned an error event."
                            throw AIError.invalidResponse(provider: providerID, message: message)
                        }
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        for part in contentBlocks.apply(event: raw) {
                            continuation.yield(part)
                        }
                        for part in providerToolResults.apply(event: raw) {
                            continuation.yield(part)
                        }
                        for source in anthropicSources(from: raw, citationDocuments: citationDocuments, sourceCounter: &sourceCounter) {
                            continuation.yield(.source(source))
                        }
                        for part in toolCalls.apply(event: raw) {
                            continuation.yield(part)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func preparedCall(for request: LanguageModelRequest, stream: Bool = false) async throws -> AnthropicPreparedCall {
        var resolvedRequest = request
        resolvedRequest.messages = try await amazonBedrockAnthropicResolveURLContent(
            in: request.messages,
            transport: config.transport,
            abortSignal: request.abortSignal,
            providerID: providerID
        )
        var prepared = try AnthropicLanguageModel.body(for: resolvedRequest, modelID: modelID, providerID: providerID, stream: stream)
        amazonBedrockAnthropicApplyStructuredOutputSupport(modelID: modelID, prepared: &prepared)
        return prepared
    }
}

private struct AnthropicToolCallBuffer {
    var id: String
    var name: String
    var arguments: String
    var providerExecuted: Bool
    var rawValue: JSONValue
}

private enum AnthropicStreamingContentBlock {
    case text(providerMetadata: [String: JSONValue] = [:])
    case reasoning(providerMetadata: [String: JSONValue] = [:])
}

private struct AnthropicStreamingContentBlocks {
    private var blocks: [Int: AnthropicStreamingContentBlock] = [:]
    private let providerID: String

    init(providerID: String) {
        self.providerID = providerID
    }

    mutating func apply(event raw: JSONValue) -> [LanguageStreamPart] {
        switch raw["type"]?.stringValue {
        case "content_block_start":
            guard let index = raw["index"]?.intValue,
                  let block = raw["content_block"],
                  let type = block["type"]?.stringValue else {
                return []
            }
            let id = String(index)
            switch type {
            case "text":
                blocks[index] = .text()
                return [.textStart(id: id)]
            case "thinking":
                blocks[index] = .reasoning()
                return [.reasoningStart(id: id)]
            case "redacted_thinking":
                let metadata = anthropicContentBlockProviderMetadata([
                    "redactedData": block["data"] ?? .null
                ], providerID: providerID)
                blocks[index] = .reasoning(providerMetadata: metadata)
                return [.reasoningStart(id: id, providerMetadata: metadata)]
            case "compaction":
                let metadata = anthropicContentBlockProviderMetadata([
                    "type": .string("compaction")
                ], providerID: providerID)
                blocks[index] = .text(providerMetadata: metadata)
                return [.textStart(id: id, providerMetadata: metadata)]
            default:
                return []
            }
        case "content_block_delta":
            let index = raw["index"]?.intValue ?? 0
            let id = String(index)
            let delta = raw["delta"]
            switch delta?["type"]?.stringValue {
            case "text_delta":
                guard let text = delta?["text"]?.stringValue else { return [] }
                return [.textDelta(text), .textDeltaPart(id: id, delta: text)]
            case "thinking_delta":
                guard let thinking = delta?["thinking"]?.stringValue else { return [] }
                return [.reasoningDelta(thinking), .reasoningDeltaPart(id: id, delta: thinking)]
            case "signature_delta":
                guard case .reasoning = blocks[index],
                      let signature = delta?["signature"] else {
                    return []
                }
                return [.reasoningDeltaPart(
                    id: id,
                    delta: "",
                    providerMetadata: anthropicContentBlockProviderMetadata(["signature": signature], providerID: providerID)
                )]
            case "compaction_delta":
                guard let content = delta?["content"]?.stringValue else { return [] }
                return [.textDelta(content), .textDeltaPart(id: id, delta: content)]
            default:
                return []
            }
        case "content_block_stop":
            guard let index = raw["index"]?.intValue,
                  let block = blocks.removeValue(forKey: index) else {
                return []
            }
            let id = String(index)
            switch block {
            case let .text(metadata):
                return [.textEnd(id: id, providerMetadata: metadata)]
            case let .reasoning(metadata):
                return [.reasoningEnd(id: id, providerMetadata: metadata)]
            }
        case "message_delta":
            return [.finish(
                reason: anthropicFinishReason(raw["delta"]?["stop_reason"]?.stringValue),
                usage: TokenUsage(
                    inputTokens: raw["usage"]?["input_tokens"]?.intValue,
                    outputTokens: raw["usage"]?["output_tokens"]?.intValue
                )
            )]
        default:
            return []
        }
    }
}

private func anthropicContentBlockProviderMetadata(_ metadata: [String: JSONValue?], providerID: String) -> [String: JSONValue] {
    [anthropicProviderMetadataKey(from: providerID): .object(metadata)]
}

private struct AnthropicStreamingProviderToolResults {
    private var serverToolNames: [String: String] = [:]
    private var mcpToolNames: [String: String] = [:]
    private var mcpToolMetadata: [String: [String: JSONValue]] = [:]
    private let providerID: String

    init(providerID: String) {
        self.providerID = providerID
    }

    mutating func apply(event raw: JSONValue) -> [LanguageStreamPart] {
        guard raw["type"]?.stringValue == "content_block_start",
              let block = raw["content_block"] else {
            return []
        }
        recordToolUse(block)
        return anthropicToolResult(
            from: block,
            providerID: providerID,
            serverToolNames: serverToolNames,
            mcpToolNames: mcpToolNames,
            mcpToolMetadata: mcpToolMetadata
        ).map { [.toolResult($0)] } ?? []
    }

    private mutating func recordToolUse(_ block: JSONValue) {
        guard let type = block["type"]?.stringValue,
              let id = block["id"]?.stringValue else {
            return
        }
        switch type {
        case "server_tool_use":
            if let name = block["name"]?.stringValue {
                serverToolNames[id] = name
            }
        case "mcp_tool_use":
            if let name = block["name"]?.stringValue {
                mcpToolNames[id] = name
            }
            mcpToolMetadata[id] = anthropicContentBlockProviderMetadata([
                "type": .string("mcp-tool-use"),
                "serverName": block["server_name"] ?? .null
            ], providerID: providerID)
        default:
            break
        }
    }
}

private struct AnthropicStreamingToolCalls {
    private var buffers: [Int: AnthropicToolCallBuffer] = [:]

    mutating func apply(event raw: JSONValue) -> [LanguageStreamPart] {
        switch raw["type"]?.stringValue {
        case "content_block_start":
            guard let index = raw["index"]?.intValue,
                  let block = raw["content_block"],
                  let toolCall = anthropicToolCall(from: block) else {
                return []
            }
            let initialArguments = toolCall.arguments == "{}" ? "" : toolCall.arguments
            buffers[index] = AnthropicToolCallBuffer(
                id: toolCall.id,
                name: toolCall.name,
                arguments: initialArguments,
                providerExecuted: toolCall.providerExecuted,
                rawValue: block
            )
            var parts: [LanguageStreamPart] = [
                .toolInputStart(id: toolCall.id, name: toolCall.name, providerExecuted: toolCall.providerExecuted)
            ]
            parts.append(.toolCallDelta(id: toolCall.id, name: toolCall.name, argumentsDelta: initialArguments, index: index))
            if !initialArguments.isEmpty {
                parts.append(.toolInputDelta(id: toolCall.id, delta: initialArguments))
            }
            return parts
        case "content_block_delta":
            guard raw["delta"]?["type"]?.stringValue == "input_json_delta",
                  let index = raw["index"]?.intValue,
                  var buffer = buffers[index] else {
                return []
            }
            let delta = raw["delta"]?["partial_json"]?.stringValue ?? ""
            buffer.arguments += delta
            buffers[index] = buffer
            var parts: [LanguageStreamPart] = [.toolCallDelta(id: buffer.id, name: buffer.name, argumentsDelta: delta, index: index)]
            if !delta.isEmpty {
                parts.append(.toolInputDelta(id: buffer.id, delta: delta))
            }
            return parts
        case "content_block_stop":
            guard let index = raw["index"]?.intValue, let buffer = buffers.removeValue(forKey: index) else {
                return []
            }
            return [
                .toolInputEnd(id: buffer.id),
                .toolCall(AIToolCall(
                    id: buffer.id,
                    name: buffer.name,
                    arguments: buffer.arguments.isEmpty ? "{}" : buffer.arguments,
                    providerExecuted: buffer.providerExecuted,
                    rawValue: buffer.rawValue
                ))
            ]
        default:
            return []
        }
    }
}

private struct AnthropicPreparedTools {
    var tools: [JSONValue] = []
    var betas: [String] = []
    var hasCodeExecution = false
}

private func anthropicPrepareTools(from tools: [String: JSONValue]) -> AnthropicPreparedTools {
    var prepared = AnthropicPreparedTools()

    func addBeta(_ beta: String) {
        if !prepared.betas.contains(beta) {
            prepared.betas.append(beta)
        }
    }

    for (name, schema) in tools {
        let object = schema.objectValue
        let isProviderTool = object?["type"]?.stringValue == "provider" || object?["id"]?.stringValue?.hasPrefix("anthropic.") == true
        guard isProviderTool else {
            prepared.tools.append(.object(["name": .string(name), "input_schema": schema]))
            continue
        }

        let id = object?["id"]?.stringValue ?? name
        let args = object?["args"]?.objectValue ?? [:]
        switch id {
        case "anthropic.code_execution_20250522":
            addBeta("code-execution-2025-05-22")
            prepared.hasCodeExecution = true
            prepared.tools.append(.object(["type": "code_execution_20250522", "name": "code_execution"]))
        case "anthropic.code_execution_20250825":
            addBeta("code-execution-2025-08-25")
            prepared.hasCodeExecution = true
            prepared.tools.append(.object(["type": "code_execution_20250825", "name": "code_execution"]))
        case "anthropic.code_execution_20260120":
            prepared.hasCodeExecution = true
            prepared.tools.append(.object(["type": "code_execution_20260120", "name": "code_execution"]))
        case "anthropic.computer_20241022":
            addBeta("computer-use-2024-10-22")
            prepared.tools.append(anthropicComputerTool(type: "computer_20241022", args: args))
        case "anthropic.computer_20250124":
            addBeta("computer-use-2025-01-24")
            prepared.tools.append(anthropicComputerTool(type: "computer_20250124", args: args))
        case "anthropic.computer_20251124":
            addBeta("computer-use-2025-11-24")
            prepared.tools.append(anthropicComputerTool(type: "computer_20251124", args: args, includeZoom: true))
        case "anthropic.text_editor_20241022":
            addBeta("computer-use-2024-10-22")
            prepared.tools.append(.object(["type": "text_editor_20241022", "name": "str_replace_editor"]))
        case "anthropic.text_editor_20250124":
            addBeta("computer-use-2025-01-24")
            prepared.tools.append(.object(["type": "text_editor_20250124", "name": "str_replace_editor"]))
        case "anthropic.text_editor_20250429":
            addBeta("computer-use-2025-01-24")
            prepared.tools.append(.object(["type": "text_editor_20250429", "name": "str_replace_based_edit_tool"]))
        case "anthropic.text_editor_20250728":
            var tool: [String: JSONValue] = ["type": "text_editor_20250728", "name": "str_replace_based_edit_tool"]
            if let maxCharacters = args["maxCharacters"] {
                tool["max_characters"] = maxCharacters
            }
            prepared.tools.append(.object(tool))
        case "anthropic.bash_20241022":
            addBeta("computer-use-2024-10-22")
            prepared.tools.append(.object(["type": "bash_20241022", "name": "bash"]))
        case "anthropic.bash_20250124":
            addBeta("computer-use-2025-01-24")
            prepared.tools.append(.object(["type": "bash_20250124", "name": "bash"]))
        case "anthropic.memory_20250818":
            addBeta("context-management-2025-06-27")
            prepared.tools.append(.object(["type": "memory_20250818", "name": "memory"]))
        case "anthropic.web_fetch_20250910":
            addBeta("web-fetch-2025-09-10")
            prepared.tools.append(anthropicWebTool(type: "web_fetch_20250910", name: "web_fetch", args: args, includeFetchFields: true))
        case "anthropic.web_fetch_20260209":
            addBeta("code-execution-web-tools-2026-02-09")
            prepared.tools.append(anthropicWebTool(type: "web_fetch_20260209", name: "web_fetch", args: args, includeFetchFields: true))
        case "anthropic.web_search_20250305":
            prepared.tools.append(anthropicWebTool(type: "web_search_20250305", name: "web_search", args: args, includeFetchFields: false))
        case "anthropic.web_search_20260209":
            addBeta("code-execution-web-tools-2026-02-09")
            prepared.tools.append(anthropicWebTool(type: "web_search_20260209", name: "web_search", args: args, includeFetchFields: false))
        case "anthropic.tool_search_regex_20251119":
            prepared.tools.append(.object(["type": "tool_search_tool_regex_20251119", "name": "tool_search_tool_regex"]))
        case "anthropic.tool_search_bm25_20251119":
            prepared.tools.append(.object(["type": "tool_search_tool_bm25_20251119", "name": "tool_search_tool_bm25"]))
        case "anthropic.advisor_20260301":
            addBeta("advisor-tool-2026-03-01")
            var tool: [String: JSONValue] = ["type": "advisor_20260301", "name": "advisor"]
            tool["model"] = args["model"]
            tool["max_uses"] = args["maxUses"]
            tool["caching"] = args["caching"]
            prepared.tools.append(.object(tool.compactMapValues { $0 }))
        default:
            break
        }
    }
    return prepared
}

private func anthropicComputerTool(type: String, args: [String: JSONValue], includeZoom: Bool = false) -> JSONValue {
    var tool: [String: JSONValue] = [
        "type": .string(type),
        "name": .string("computer")
    ]
    tool["display_width_px"] = args["displayWidthPx"]
    tool["display_height_px"] = args["displayHeightPx"]
    tool["display_number"] = args["displayNumber"]
    if includeZoom {
        tool["enable_zoom"] = args["enableZoom"]
    }
    return .object(tool.compactMapValues { $0 })
}

private func anthropicWebTool(type: String, name: String, args: [String: JSONValue], includeFetchFields: Bool) -> JSONValue {
    var tool: [String: JSONValue] = [
        "type": .string(type),
        "name": .string(name)
    ]
    tool["max_uses"] = args["maxUses"]
    tool["allowed_domains"] = args["allowedDomains"]
    tool["blocked_domains"] = args["blockedDomains"]
    if includeFetchFields {
        tool["citations"] = args["citations"]
        tool["max_content_tokens"] = args["maxContentTokens"]
    } else {
        tool["user_location"] = args["userLocation"]
    }
    return .object(tool.compactMapValues { $0 })
}

private func anthropicHeaders(_ requestHeaders: [String: String], configHeaders: [String: String], betas: [String]) -> [String: String] {
    guard !betas.isEmpty else { return requestHeaders }
    var betaValues: [String] = []
    for source in [configHeaders["anthropic-beta"], requestHeaders["anthropic-beta"]] {
        for beta in source?.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) ?? [] where !beta.isEmpty && !betaValues.contains(beta) {
            betaValues.append(beta)
        }
    }
    for beta in betas where !betaValues.contains(beta) {
        betaValues.append(beta)
    }
    var headers = requestHeaders
    headers["anthropic-beta"] = betaValues.joined(separator: ",")
    return headers
}

private func anthropicProviderReferenceKey(from providerID: String) -> String {
    if providerID.hasPrefix("anthropic-aws") {
        return "anthropic-aws"
    }
    return "anthropic"
}

private func amazonBedrockAnthropicBody(_ body: [String: JSONValue], betas: [String]) -> [String: JSONValue] {
    var output = body
    output.removeValue(forKey: "model")
    output.removeValue(forKey: "stream")
    var requiredBetas = betas

    if let toolChoice = output["tool_choice"]?.objectValue {
        output["tool_choice"] = .object([
            "type": toolChoice["type"],
            "name": toolChoice["name"]
        ].compactMapValues { $0 })
    }

    if let tools = output["tools"]?.arrayValue {
        output["tools"] = .array(tools.map { tool in
            amazonBedrockAnthropicTool(tool, betas: &requiredBetas)
        })
    }

    output["anthropic_version"] = .string("bedrock-2023-05-31")
    if !requiredBetas.isEmpty {
        output["anthropic_beta"] = .array(requiredBetas.map(JSONValue.string))
    }
    return output
}

private func amazonBedrockAnthropicResolveURLContent(
    in messages: [AIMessage],
    transport: AITransport,
    abortSignal: AIAbortSignal?,
    providerID: String
) async throws -> [AIMessage] {
    var resolvedMessages: [AIMessage] = []
    resolvedMessages.reserveCapacity(messages.count)

    for message in messages {
        var resolvedParts: [AIContentPart] = []
        resolvedParts.reserveCapacity(message.content.count)
        for part in message.content {
            switch part {
            case let .imageURL(url):
                let downloaded = try await amazonBedrockAnthropicDownloadContent(url, transport: transport, abortSignal: abortSignal, providerID: providerID)
                resolvedParts.append(.data(mimeType: downloaded.mimeType, data: downloaded.data))
            case .text, .data, .file, .providerReference, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
                resolvedParts.append(part)
            }
        }
        resolvedMessages.append(AIMessage(role: message.role, content: resolvedParts))
    }

    return resolvedMessages
}

private func amazonBedrockAnthropicDownloadContent(
    _ url: String,
    transport: AITransport,
    abortSignal: AIAbortSignal?,
    providerID: String
) async throws -> (mimeType: String, data: Data) {
    if let dataURL = amazonBedrockAnthropicDataURL(url) {
        return dataURL
    }

    let response = try await downloadURL(url, transport: transport, abortSignal: abortSignal)
    guard (200..<300).contains(response.statusCode) else {
        throw httpStatusError(provider: providerID, response: response)
    }
    let mediaType = amazonBedrockAnthropicMediaType(
        contentType: response.headerValue("content-type"),
        data: response.body,
        url: url
    )
    return (mediaType, response.body)
}

private func amazonBedrockAnthropicDataURL(_ url: String) -> (mimeType: String, data: Data)? {
    guard url.lowercased().hasPrefix("data:"),
          let commaIndex = url.firstIndex(of: ",") else {
        return nil
    }
    let metadata = String(url[url.index(url.startIndex, offsetBy: 5)..<commaIndex])
    let payload = String(url[url.index(after: commaIndex)...])
    let parts = metadata.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
    let mimeType = parts.first?.isEmpty == false ? parts[0] : "text/plain"
    let data: Data?
    if parts.dropFirst().contains(where: { $0.caseInsensitiveCompare("base64") == .orderedSame }) {
        data = Data(base64Encoded: payload)
    } else {
        data = payload.removingPercentEncoding.map { Data($0.utf8) }
    }
    guard let data else { return nil }
    return (mimeType, data)
}

private func amazonBedrockAnthropicMediaType(contentType: String?, data: Data, url: String) -> String {
    if let contentType {
        let mediaType = contentType.split(separator: ";", maxSplits: 1).first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        if isFullMediaType(mediaType) {
            return mediaType
        }
    }
    if let detected = detectMediaType(data: data) {
        return detected
    }
    if url.lowercased().contains(".pdf") {
        return "application/pdf"
    }
    return "application/octet-stream"
}

private func amazonBedrockAnthropicApplyStructuredOutputSupport(modelID: String, prepared: inout AnthropicPreparedCall) {
    guard modelID.contains("claude-opus-4-7") || modelID.contains("claude-opus-4-8") else {
        return
    }
    guard var outputConfig = prepared.body["output_config"]?.objectValue,
          outputConfig.removeValue(forKey: "format") != nil else {
        return
    }
    if outputConfig.isEmpty {
        prepared.body.removeValue(forKey: "output_config")
    } else {
        prepared.body["output_config"] = .object(outputConfig)
    }
    prepared.warnings.append(AIWarning(
        type: "unsupported",
        feature: "responseFormat",
        message: "Bedrock Anthropic does not support native structured output for \(modelID). The response format is ignored."
    ))
}

private func amazonBedrockAnthropicTool(_ tool: JSONValue, betas: inout [String]) -> JSONValue {
    guard var object = tool.objectValue, let originalType = object["type"]?.stringValue else {
        return tool
    }
    let mappedType: String
    switch originalType {
    case "bash_20241022":
        mappedType = "bash_20250124"
    case "text_editor_20241022":
        mappedType = "text_editor_20250728"
    case "computer_20241022":
        mappedType = "computer_20250124"
    default:
        mappedType = originalType
    }
    object["type"] = .string(mappedType)
    if mappedType == "text_editor_20250728" {
        object["name"] = .string("str_replace_based_edit_tool")
    }
    if let beta = amazonBedrockAnthropicBeta(for: mappedType), !betas.contains(beta) {
        betas.append(beta)
    }
    return .object(object)
}

private func amazonBedrockAnthropicBeta(for toolType: String) -> String? {
    switch toolType {
    case "bash_20250124", "text_editor_20250124", "text_editor_20250429", "text_editor_20250728", "computer_20250124":
        return "computer-use-2025-01-24"
    case "bash_20241022", "text_editor_20241022", "computer_20241022":
        return "computer-use-2024-10-22"
    case "tool_search_tool_regex_20251119", "tool_search_tool_bm25_20251119":
        return "tool-search-tool-2025-10-19"
    default:
        return nil
    }
}

private func amazonBedrockAnthropicStreamEvents(from response: AIHTTPResponse) throws -> [JSONValue] {
    let contentType = response.headers.first { $0.key.caseInsensitiveCompare("content-type") == .orderedSame }?.value
    if contentType?.localizedCaseInsensitiveContains("application/vnd.amazon.eventstream") == true {
        return try parseAmazonBedrockEventStream(response.body).compactMap { raw in
            if let encoded = raw["chunk"]?["bytes"]?.stringValue,
               let data = Data(base64Encoded: encoded) {
                return try decodeJSONBody(data)
            }
            if raw["messageStop"] != nil {
                return nil
            }
            return raw
        }
    }
    return try parseServerSentEvents(response.body)
        .filter { $0.data != "[DONE]" }
        .map { try decodeJSONBody(Data($0.data.utf8)) }
}

private func anthropicToolCalls(from value: JSONValue?) -> [AIToolCall] {
    value?.arrayValue?.compactMap(anthropicToolCall) ?? []
}

private func anthropicToolResults(from value: JSONValue?, providerID: String) -> [AIToolResult] {
    var serverToolNames: [String: String] = [:]
    var mcpToolNames: [String: String] = [:]
    var mcpToolMetadata: [String: [String: JSONValue]] = [:]
    var results: [AIToolResult] = []

    for part in value?.arrayValue ?? [] {
        switch part["type"]?.stringValue {
        case "server_tool_use":
            if let id = part["id"]?.stringValue, let name = part["name"]?.stringValue {
                serverToolNames[id] = name
            }
        case "mcp_tool_use":
            if let id = part["id"]?.stringValue {
                if let name = part["name"]?.stringValue {
                    mcpToolNames[id] = name
                }
                mcpToolMetadata[id] = anthropicContentBlockProviderMetadata([
                    "type": .string("mcp-tool-use"),
                    "serverName": part["server_name"] ?? .null
                ], providerID: providerID)
            }
        default:
            break
        }

        if let result = anthropicToolResult(
            from: part,
            providerID: providerID,
            serverToolNames: serverToolNames,
            mcpToolNames: mcpToolNames,
            mcpToolMetadata: mcpToolMetadata
        ) {
            results.append(result)
        }
    }
    return results
}

private func anthropicToolResult(
    from part: JSONValue,
    providerID: String,
    serverToolNames: [String: String],
    mcpToolNames: [String: String],
    mcpToolMetadata: [String: [String: JSONValue]]
) -> AIToolResult? {
    guard let type = part["type"]?.stringValue else { return nil }
    switch type {
    case "web_fetch_tool_result":
        guard let toolCallID = part["tool_use_id"]?.stringValue,
              let content = part["content"],
              let contentType = content["type"]?.stringValue else { return nil }
        if contentType == "web_fetch_result" {
            let source = content["content"]?["source"]
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: "web_fetch",
                result: .object([
                    "type": .string("web_fetch_result"),
                    "url": content["url"],
                    "retrievedAt": content["retrieved_at"],
                    "content": .object([
                        "type": content["content"]?["type"],
                        "title": content["content"]?["title"],
                        "citations": content["content"]?["citations"],
                        "source": .object([
                            "type": source?["type"],
                            "mediaType": source?["media_type"],
                            "data": source?["data"]
                        ])
                    ])
                ])
            )
        }
        if contentType == "web_fetch_tool_result_error" {
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: "web_fetch",
                result: .object([
                    "type": .string("web_fetch_tool_result_error"),
                    "errorCode": content["error_code"]
                ]),
                isError: true
            )
        }
        return nil
    case "web_search_tool_result":
        guard let toolCallID = part["tool_use_id"]?.stringValue,
              let content = part["content"] else { return nil }
        if let results = content.arrayValue {
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: "web_search",
                result: .array(results.map { result in
                    .object([
                        "url": result["url"],
                        "title": result["title"],
                        "pageAge": result["page_age"] ?? .null,
                        "encryptedContent": result["encrypted_content"],
                        "type": result["type"]
                    ])
                })
            )
        }
        return AIToolResult(
            toolCallID: toolCallID,
            toolName: "web_search",
            result: .object([
                "type": .string("web_search_tool_result_error"),
                "errorCode": content["error_code"]
            ]),
            isError: true
        )
    case "code_execution_tool_result":
        guard let toolCallID = part["tool_use_id"]?.stringValue,
              let content = part["content"],
              let contentType = content["type"]?.stringValue else { return nil }
        switch contentType {
        case "code_execution_result":
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: "code_execution",
                result: .object([
                    "type": .string(contentType),
                    "stdout": content["stdout"],
                    "stderr": content["stderr"],
                    "return_code": content["return_code"],
                    "content": content["content"] ?? .array([JSONValue]())
                ])
            )
        case "encrypted_code_execution_result":
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: "code_execution",
                result: .object([
                    "type": .string(contentType),
                    "encrypted_stdout": content["encrypted_stdout"],
                    "stderr": content["stderr"],
                    "return_code": content["return_code"],
                    "content": content["content"] ?? .array([JSONValue]())
                ])
            )
        case "code_execution_tool_result_error":
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: "code_execution",
                result: .object([
                    "type": .string("code_execution_tool_result_error"),
                    "errorCode": content["error_code"]
                ]),
                isError: true
            )
        default:
            return nil
        }
    case "bash_code_execution_tool_result", "text_editor_code_execution_tool_result":
        guard let toolCallID = part["tool_use_id"]?.stringValue else { return nil }
        return AIToolResult(
            toolCallID: toolCallID,
            toolName: "code_execution",
            result: part["content"] ?? .null
        )
    case "tool_search_tool_result":
        guard let toolCallID = part["tool_use_id"]?.stringValue,
              let content = part["content"],
              let contentType = content["type"]?.stringValue else { return nil }
        let toolName = anthropicToolSearchToolName(serverToolNames[toolCallID])
        if contentType == "tool_search_tool_search_result" {
            let references = content["tool_references"]?.arrayValue ?? []
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: toolName,
                result: .array(references.map { reference in
                    .object([
                        "type": reference["type"],
                        "toolName": reference["tool_name"]
                    ])
                })
            )
        }
        return AIToolResult(
            toolCallID: toolCallID,
            toolName: toolName,
            result: .object([
                "type": .string("tool_search_tool_result_error"),
                "errorCode": content["error_code"]
            ]),
            isError: true
        )
    case "advisor_tool_result":
        guard let toolCallID = part["tool_use_id"]?.stringValue,
              let content = part["content"],
              let contentType = content["type"]?.stringValue else { return nil }
        switch contentType {
        case "advisor_result":
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: "advisor",
                result: .object([
                    "type": .string("advisor_result"),
                    "text": content["text"]
                ])
            )
        case "advisor_redacted_result":
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: "advisor",
                result: .object([
                    "type": .string("advisor_redacted_result"),
                    "encryptedContent": content["encrypted_content"]
                ])
            )
        default:
            return AIToolResult(
                toolCallID: toolCallID,
                toolName: "advisor",
                result: .object([
                    "type": .string("advisor_tool_result_error"),
                    "errorCode": content["error_code"]
                ]),
                isError: true
            )
        }
    case "mcp_tool_result":
        guard let toolCallID = part["tool_use_id"]?.stringValue else { return nil }
        return AIToolResult(
            toolCallID: toolCallID,
            toolName: mcpToolNames[toolCallID] ?? "mcp_tool",
            result: part["content"] ?? .null,
            isError: part["is_error"]?.boolValue ?? false,
            dynamic: true,
            providerMetadata: mcpToolMetadata[toolCallID] ?? anthropicContentBlockProviderMetadata([
                "type": .string("mcp-tool-use"),
                "serverName": .null
            ], providerID: providerID)
        )
    default:
        return nil
    }
}

private func anthropicToolSearchToolName(_ providerToolName: String?) -> String {
    switch providerToolName {
    case "tool_search_tool_bm25", "tool_search_tool_regex":
        return "tool_search"
    default:
        return "tool_search"
    }
}

private func anthropicProviderMetadata(from raw: JSONValue, providerID: String) -> [String: JSONValue] {
    anthropicProviderMetadata(
        usage: raw["usage"],
        stopSequence: raw["stop_sequence"] ?? .null,
        container: anthropicContainerMetadata(from: raw["container"]) ?? .null,
        contextManagement: anthropicContextManagementMetadata(from: raw["context_management"]) ?? .null,
        providerID: providerID
    )
}

private func anthropicProviderMetadata(
    usage: JSONValue?,
    stopSequence: JSONValue,
    container: JSONValue,
    contextManagement: JSONValue,
    providerID: String
) -> [String: JSONValue] {
    let metadata: JSONValue = .object([
        "usage": usage ?? .null,
        "stopSequence": stopSequence,
        "iterations": anthropicUsageIterations(from: usage?["iterations"]) ?? .null,
        "container": container,
        "contextManagement": contextManagement
    ])
    return [anthropicProviderMetadataKey(from: providerID): metadata]
}

private func anthropicProviderMetadataKey(from providerID: String) -> String {
    if providerID.hasPrefix("anthropic-aws") {
        return "anthropic-aws"
    }
    if providerID.hasPrefix("bedrock.anthropic") {
        return "bedrock.anthropic"
    }
    if providerID.hasPrefix("googleVertex.anthropic") {
        return "googleVertex.anthropic"
    }
    return "anthropic"
}

private func anthropicMergedUsage(_ existing: JSONValue, _ update: JSONValue) -> JSONValue {
    var output = existing.objectValue ?? [:]
    for (key, value) in update.objectValue ?? [:] {
        output[key] = value
    }
    return .object(output)
}

private func anthropicUsageIterations(from value: JSONValue?) -> JSONValue? {
    guard let iterations = value?.arrayValue else { return nil }
    return .array(iterations.map { iteration in
        var output: [String: JSONValue] = [:]
        output["type"] = iteration["type"]
        output["model"] = iteration["model"]
        output["inputTokens"] = iteration["input_tokens"]
        output["outputTokens"] = iteration["output_tokens"]
        output["cacheCreationInputTokens"] = iteration["cache_creation_input_tokens"]
        output["cacheReadInputTokens"] = iteration["cache_read_input_tokens"]
        return .object(output.compactMapValues { $0 })
    })
}

private func anthropicContainerMetadata(from value: JSONValue?) -> JSONValue? {
    guard var object = value?.objectValue else { return nil }
    anthropicMoveKey("expires_at", to: "expiresAt", in: &object)
    if let skills = object["skills"]?.arrayValue {
        object["skills"] = .array(skills.map { skill in
            guard var skillObject = skill.objectValue else { return skill }
            anthropicMoveKey("skill_id", to: "skillId", in: &skillObject)
            return .object(skillObject)
        })
    } else if object["skills"] == nil {
        object["skills"] = .null
    }
    return .object(object)
}

private func anthropicContextManagementMetadata(from value: JSONValue?) -> JSONValue? {
    guard var object = value?.objectValue else { return nil }
    if let edits = object.removeValue(forKey: "applied_edits")?.arrayValue {
        object["appliedEdits"] = .array(edits.map { edit in
            guard var editObject = edit.objectValue else { return edit }
            anthropicMoveKey("cleared_tool_uses", to: "clearedToolUses", in: &editObject)
            anthropicMoveKey("cleared_input_tokens", to: "clearedInputTokens", in: &editObject)
            return .object(editObject)
        })
    }
    return .object(object)
}

private struct AnthropicCitationDocument {
    var title: String
    var filename: String?
    var mediaType: String
}

private func anthropicCitationDocuments(from messages: [AIMessage]) -> [AnthropicCitationDocument] {
    messages.flatMap(\.content).compactMap { part in
        switch part {
        case let .data(mimeType, _), let .file(mimeType, _, _):
            guard mimeType.lowercased().hasPrefix("text/") || mimeType.lowercased() == "application/pdf" else {
                return nil
            }
            return AnthropicCitationDocument(title: "Document", filename: nil, mediaType: mimeType)
        case let .imageURL(url):
            guard url.lowercased().contains(".pdf") else { return nil }
            let filename = url.split(separator: "/").last.map(String.init)
            return AnthropicCitationDocument(title: filename ?? "Document", filename: filename, mediaType: "application/pdf")
        case .text, .providerReference, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
            return nil
        }
    }
}

private func anthropicToolArguments(_ arguments: String) -> JSONValue {
    (try? decodeJSONBody(Data(arguments.utf8))) ?? .object([:])
}

private func anthropicSources(from content: JSONValue?, citationDocuments: [AnthropicCitationDocument]) -> [AISource] {
    var sourceCounter = 0
    return content?.arrayValue?.flatMap { part in
        anthropicSources(from: part, citationDocuments: citationDocuments, sourceCounter: &sourceCounter)
    } ?? []
}

private func anthropicSources(from eventOrPart: JSONValue, citationDocuments: [AnthropicCitationDocument], sourceCounter: inout Int) -> [AISource] {
    let part: JSONValue
    if eventOrPart["type"]?.stringValue == "content_block_start", let contentBlock = eventOrPart["content_block"] {
        part = contentBlock
    } else {
        part = eventOrPart
    }

    if part["type"]?.stringValue == "web_search_tool_result", let results = part["content"]?.arrayValue {
        return results.compactMap { result in
            guard result["type"]?.stringValue == "web_search_result",
                  let url = result["url"]?.stringValue else {
                return nil
            }
            let source = AISource(
                id: "anthropic-source-\(sourceCounter)",
                sourceType: "url",
                url: url,
                title: result["title"]?.stringValue,
                providerMetadata: ["anthropic": .object(["pageAge": result["page_age"] ?? .null])],
                rawValue: result
            )
            sourceCounter += 1
            return source
        }
    }

    if eventOrPart["type"]?.stringValue == "content_block_delta",
       eventOrPart["delta"]?["type"]?.stringValue == "citations_delta",
       let citation = eventOrPart["delta"]?["citation"],
       let source = anthropicCitationSource(from: citation, citationDocuments: citationDocuments, id: "anthropic-source-\(sourceCounter)") {
        sourceCounter += 1
        return [source]
    }

    guard let citations = part["citations"]?.arrayValue else {
        return []
    }

    return citations.compactMap { citation in
        guard let source = anthropicCitationSource(from: citation, citationDocuments: citationDocuments, id: "anthropic-source-\(sourceCounter)") else {
            return nil
        }
        sourceCounter += 1
        return source
    }
}

private func anthropicCitationSource(from citation: JSONValue, citationDocuments: [AnthropicCitationDocument], id: String) -> AISource? {
    switch citation["type"]?.stringValue {
    case "web_search_result_location":
        guard let url = citation["url"]?.stringValue else { return nil }
        return AISource(
            id: id,
            sourceType: "url",
            url: url,
            title: citation["title"]?.stringValue,
            providerMetadata: ["anthropic": .object([
                "citedText": citation["cited_text"],
                "encryptedIndex": citation["encrypted_index"]
            ])],
            rawValue: citation
        )
    case "page_location", "char_location":
        guard let documentIndex = citation["document_index"]?.intValue,
              citationDocuments.indices.contains(documentIndex) else {
            return nil
        }
        let document = citationDocuments[documentIndex]
        let metadata: [String: JSONValue?]
        if citation["type"]?.stringValue == "page_location" {
            metadata = [
                "citedText": citation["cited_text"],
                "startPageNumber": citation["start_page_number"],
                "endPageNumber": citation["end_page_number"]
            ]
        } else {
            metadata = [
                "citedText": citation["cited_text"],
                "startCharIndex": citation["start_char_index"],
                "endCharIndex": citation["end_char_index"]
            ]
        }
        return AISource(
            id: id,
            sourceType: "document",
            title: citation["document_title"]?.stringValue ?? document.title,
            mediaType: document.mediaType,
            filename: document.filename,
            providerMetadata: ["anthropic": .object(metadata)],
            rawValue: citation
        )
    default:
        return nil
    }
}

private func anthropicToolCall(from part: JSONValue) -> AIToolCall? {
    guard let type = part["type"]?.stringValue else { return nil }
    switch type {
    case "tool_use":
        guard let id = part["id"]?.stringValue, let name = part["name"]?.stringValue else { return nil }
        return AIToolCall(
            id: id,
            name: name,
            arguments: anthropicJSONString(part["input"] ?? .object([:])) ?? "{}",
            rawValue: part
        )
    case "server_tool_use":
        guard let id = part["id"]?.stringValue, let name = part["name"]?.stringValue else { return nil }
        return AIToolCall(
            id: id,
            name: name,
            arguments: anthropicJSONString(part["input"] ?? .object([:])) ?? "{}",
            providerExecuted: true,
            rawValue: part
        )
    case "mcp_tool_use":
        guard let id = part["id"]?.stringValue, let name = part["name"]?.stringValue else { return nil }
        return AIToolCall(
            id: id,
            name: name,
            arguments: anthropicJSONString(part["input"] ?? .object([:])) ?? "{}",
            providerExecuted: true,
            rawValue: part
        )
    default:
        return nil
    }
}

private func anthropicJSONString(_ value: JSONValue) -> String? {
    guard let data = try? encodeJSONBody(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

func anthropicFinishReason(_ reason: String?) -> String? {
    switch reason {
    case nil:
        return nil
    case "pause_turn", "end_turn", "stop_sequence":
        return "stop"
    case "refusal":
        return "content-filter"
    case "tool_use":
        return "tool-calls"
    case "max_tokens", "model_context_window_exceeded":
        return "length"
    case "compaction":
        return "other"
    default:
        return "other"
    }
}

private struct AnthropicMappedOptions {
    var body: [String: JSONValue]
    var betas: [String]
}

private let anthropicLanguageProviderOptionKeys: Set<String> = [
    "sendReasoning",
    "structuredOutputMode",
    "thinking",
    "disableParallelToolUse",
    "cacheControl",
    "metadata",
    "mcpServers",
    "container",
    "toolStreaming",
    "effort",
    "taskBudget",
    "speed",
    "inferenceGeo",
    "anthropicBeta",
    "contextManagement"
]

private func anthropicOptions(from request: LanguageModelRequest) throws -> AnthropicMappedOptions {
    var output = anthropicOptions(from: request.extraBody)
    var betas: [String] = []

    if let value = request.providerOptions["anthropic"] {
        guard value != .null else {
            return AnthropicMappedOptions(body: output, betas: betas)
        }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.anthropic", message: "Anthropic provider options must be an object.")
        }
        let typed = try anthropicTypedOptions(from: nested)
        output.merge(typed.body) { _, typed in typed }
        betas.append(contentsOf: typed.betas)
    }

    if let betaValue = request.extraBody["anthropicBeta"] {
        betas.append(contentsOf: try anthropicBetaValues(betaValue, argument: "extraBody.anthropicBeta"))
    }
    betas.append(contentsOf: anthropicAutomaticBetas(from: output))

    return AnthropicMappedOptions(body: output, betas: betas)
}

private func anthropicTypedOptions(from options: [String: JSONValue]) throws -> AnthropicMappedOptions {
    let knownOptions = options.filter { anthropicLanguageProviderOptionKeys.contains($0.key) }
    var body = anthropicOptions(from: knownOptions)
    body.removeValue(forKey: "anthropicBeta")
    let betas = try anthropicBetaValues(options["anthropicBeta"], argument: "providerOptions.anthropic.anthropicBeta")
    return AnthropicMappedOptions(body: body, betas: betas)
}

private func anthropicBetaValues(_ value: JSONValue?, argument: String) throws -> [String] {
    guard let value, value != .null else { return [] }
    guard let values = value.arrayValue else {
        throw AIError.invalidArgument(argument: argument, message: "Anthropic anthropicBeta must be an array of strings.")
    }
    return try values.enumerated().map { index, value in
        guard let string = value.stringValue else {
            throw AIError.invalidArgument(argument: "\(argument)[\(index)]", message: "Anthropic anthropicBeta values must be strings.")
        }
        return string
    }
}

private func anthropicAutomaticBetas(from body: [String: JSONValue]) -> [String] {
    var betas: [String] = []

    func add(_ beta: String) {
        if !betas.contains(beta) {
            betas.append(beta)
        }
    }

    if body["mcp_servers"]?.arrayValue?.isEmpty == false {
        add("mcp-client-2025-04-04")
    }

    if let contextManagement = body["context_management"]?.objectValue {
        add("context-management-2025-06-27")
        if contextManagement["edits"]?.arrayValue?.contains(where: { edit in
            edit["type"]?.stringValue == "compact_20260112"
        }) == true {
            add("compact-2026-01-12")
        }
    }

    if body["container"]?["skills"]?.arrayValue?.isEmpty == false {
        add("code-execution-2025-08-25")
        add("skills-2025-10-02")
        add("files-api-2025-04-14")
    }

    if body["output_config"]?["task_budget"] != nil {
        add("task-budgets-2026-03-13")
    }

    if body["speed"]?.stringValue == "fast" {
        add("fast-mode-2026-02-01")
    }

    return betas
}

private func anthropicOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    anthropicMoveKey("topK", to: "top_k", in: &output)
    anthropicMoveKey("cacheControl", to: "cache_control", in: &output)
    anthropicMoveKey("inferenceGeo", to: "inference_geo", in: &output)
    anthropicMoveKey("toolChoice", to: "tool_choice", in: &output)

    if let thinking = output.removeValue(forKey: "thinking") {
        output["thinking"] = anthropicThinking(thinking)
    }
    if let metadata = output.removeValue(forKey: "metadata") {
        output["metadata"] = anthropicMetadata(metadata)
    }
    if let contextManagement = output.removeValue(forKey: "contextManagement") {
        output["context_management"] = anthropicContextManagement(contextManagement)
    }
    if let mcpServers = output.removeValue(forKey: "mcpServers") {
        output["mcp_servers"] = anthropicMCPServers(mcpServers)
    }
    if let container = output.removeValue(forKey: "container") {
        output["container"] = anthropicContainer(container)
    }

    var outputConfig: [String: JSONValue] = output.removeValue(forKey: "output_config")?.objectValue ?? [:]
    if let effort = output.removeValue(forKey: "effort") {
        outputConfig["effort"] = effort
    }
    if let taskBudget = output.removeValue(forKey: "taskBudget") {
        outputConfig["task_budget"] = anthropicTaskBudget(taskBudget)
    }
    if !outputConfig.isEmpty {
        output["output_config"] = .object(outputConfig)
    }

    output.removeValue(forKey: "sendReasoning")
    output.removeValue(forKey: "structuredOutputMode")
    output.removeValue(forKey: "responseFormat")
    output.removeValue(forKey: "disableParallelToolUse")
    output.removeValue(forKey: "toolStreaming")
    output.removeValue(forKey: "anthropicBeta")
    return output
}

private func anthropicThinking(_ value: JSONValue) -> JSONValue {
    guard var object = value.objectValue else { return value }
    anthropicMoveKey("budgetTokens", to: "budget_tokens", in: &object)
    return .object(object)
}

private func anthropicMetadata(_ value: JSONValue) -> JSONValue {
    guard var object = value.objectValue else { return value }
    anthropicMoveKey("userId", to: "user_id", in: &object)
    return .object(object)
}

private func anthropicTaskBudget(_ value: JSONValue) -> JSONValue {
    guard var object = value.objectValue else { return value }
    anthropicMoveKey("remainingTokens", to: "remaining", in: &object)
    return .object(object)
}

private func anthropicContextManagement(_ value: JSONValue) -> JSONValue {
    guard var object = value.objectValue else { return value }
    if let edits = object["edits"]?.arrayValue {
        object["edits"] = .array(edits.map { edit in
            guard var editObject = edit.objectValue else { return edit }
            anthropicMoveKey("clearAtLeast", to: "clear_at_least", in: &editObject)
            anthropicMoveKey("clearToolInputs", to: "clear_tool_inputs", in: &editObject)
            anthropicMoveKey("excludeTools", to: "exclude_tools", in: &editObject)
            anthropicMoveKey("pauseAfterCompaction", to: "pause_after_compaction", in: &editObject)
            return .object(editObject)
        })
    }
    return .object(object)
}

private func anthropicMCPServers(_ value: JSONValue) -> JSONValue {
    guard let servers = value.arrayValue else { return value }
    return .array(servers.map { server in
        guard var object = server.objectValue else { return server }
        anthropicMoveKey("authorizationToken", to: "authorization_token", in: &object)
        if let configuration = object.removeValue(forKey: "toolConfiguration") {
            var mapped = configuration.objectValue ?? [:]
            anthropicMoveKey("allowedTools", to: "allowed_tools", in: &mapped)
            object["tool_configuration"] = .object(mapped)
        }
        return .object(object)
    })
}

private func anthropicContainer(_ value: JSONValue) -> JSONValue {
    guard var object = value.objectValue else { return value }
    if let skills = object["skills"]?.arrayValue, !skills.isEmpty {
        object["skills"] = .array(skills.map { skill in
            guard var skillObject = skill.objectValue else { return skill }
            anthropicMoveKey("skillId", to: "skill_id", in: &skillObject)
            return .object(skillObject)
        })
        return .object(object)
    }
    if let id = object["id"] {
        return id
    }
    return .object(object)
}

private func anthropicStandardWarnings(for request: LanguageModelRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.frequencyPenalty != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "frequencyPenalty"))
    }
    if request.presencePenalty != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "presencePenalty"))
    }
    if request.seed != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "seed"))
    }
    return warnings
}

private func anthropicClampedTemperature(_ temperature: Double?, warnings: inout [AIWarning]) -> Double? {
    guard let temperature else { return nil }
    if temperature > 1 {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "temperature",
            message: "\(temperature) exceeds anthropic maximum of 1.0. clamped to 1.0"
        ))
        return 1
    }
    if temperature < 0 {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "temperature",
            message: "\(temperature) is below anthropic minimum of 0. clamped to 0"
        ))
        return 0
    }
    return temperature
}

private func anthropicApplyResponseFormat(_ responseFormat: AIResponseFormat?, to body: inout [String: JSONValue], warnings: inout [AIWarning]) {
    guard let responseFormat else { return }
    switch responseFormat {
    case .text:
        return
    case let .json(schema, _, _):
        guard let schema else {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "responseFormat",
                message: "JSON response format requires a schema. The response format is ignored."
            ))
            return
        }
        var outputConfig = body["output_config"]?.objectValue ?? [:]
        outputConfig["format"] = .object([
            "type": .string("json_schema"),
            "schema": schema
        ])
        body["output_config"] = .object(outputConfig)
    }
}

private func applyAnthropicThinkingRules(
    to body: inout [String: JSONValue],
    requestedMaxTokens: Int?,
    requestTemperature: Double?,
    requestTopP: Double?,
    warnings: inout [AIWarning]
) {
    guard var thinking = body["thinking"]?.objectValue,
          let type = thinking["type"]?.stringValue,
          type == "enabled" || type == "adaptive" else {
        if requestTemperature != nil, requestTopP != nil {
            body["top_p"] = nil
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "topP",
                message: "topP is not supported when temperature is set. topP is ignored."
            ))
        }
        return
    }

    if type == "enabled", thinking["budget_tokens"] == nil {
        thinking["budget_tokens"] = 1024
        body["thinking"] = .object(thinking)
        warnings.append(AIWarning(
            type: "compatibility",
            feature: "extended thinking",
            message: "thinking budget is required when thinking is enabled. using default budget of 1024 tokens."
        ))
    }

    if body["temperature"] != nil {
        body["temperature"] = nil
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "temperature",
            message: "temperature is not supported when thinking is enabled"
        ))
    }
    if body["top_k"] != nil {
        body["top_k"] = nil
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "topK",
            message: "topK is not supported when thinking is enabled"
        ))
    }
    if body["top_p"] != nil {
        body["top_p"] = nil
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "topP",
            message: "topP is not supported when thinking is enabled"
        ))
    }

    if type == "enabled" {
        let budget = thinking["budget_tokens"]?.intValue ?? 1024
        body["max_tokens"] = .number(Double((requestedMaxTokens ?? 1024) + budget))
    }
}

private func anthropicContainerHasSkills(_ body: [String: JSONValue]) -> Bool {
    body["container"]?["skills"]?.arrayValue?.isEmpty == false
}

private func anthropicMoveKey(_ source: String, to destination: String, in values: inout [String: JSONValue]) {
    if let value = values.removeValue(forKey: source) {
        values[destination] = value
    }
}

extension JSONValue {
    var arrayValue: [JSONValue]? {
        if case let .array(value) = self { value } else { nil }
    }
}
