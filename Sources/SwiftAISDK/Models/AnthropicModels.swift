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
            headers: anthropicHeaders(request.headers, configHeaders: config.headers, betas: preparedRequest.betas),
            abortSignal: request.abortSignal
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
                        headers: anthropicHeaders(request.headers, configHeaders: config.headers, betas: preparedRequest.betas),
                        abortSignal: request.abortSignal
                    ))
                    guard (200..<300).contains(response.statusCode) else {
                        throw apiCallError(provider: providerID, response: response)
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
        let providerOptions = try anthropicOptions(from: request, providerID: providerID)
        let preparedTools = anthropicPrepareTools(
            from: request.tools,
            toolChoice: request.toolChoice ?? providerOptions.toolChoice,
            disableParallelToolUse: providerOptions.disableParallelToolUse,
            defaultEagerInputStreaming: stream && (providerOptions.toolStreaming ?? true)
        )
        if !preparedTools.tools.isEmpty {
            body["tools"] = .array(preparedTools.tools)
        }
        if let toolChoice = preparedTools.toolChoice {
            body["tool_choice"] = toolChoice
        }
        body.merge(providerOptions.body) { _, new in new }
        warnings.append(contentsOf: preparedTools.warnings)
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

struct AnthropicPreparedCall {
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
                        throw apiCallError(provider: providerID, response: response)
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
