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
    public let supportedURLs: [String: [AISupportedURLPattern]] = [
        "image/*": [AISupportedURLPattern(anthropicSupportedHTTPURL)],
        "application/pdf": [AISupportedURLPattern(anthropicSupportedHTTPURL)]
    ]
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
        body = config.transformRequestBody?(body) ?? body
        let response = try await config.transport.send(config.request(
            path: path,
            modelID: modelID,
            body: .object(body),
            headers: anthropicHeaders(request.headers, configHeaders: config.headers, betas: preparedRequest.betas),
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw anthropicHTTPStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        let toolCalls = anthropicToolCalls(from: raw["content"])
        let toolResults = anthropicToolResults(from: raw["content"], providerID: providerID)
        let sources = anthropicSources(from: raw["content"], citationDocuments: anthropicCitationDocuments(from: request.messages))
        let text = anthropicTextContent(from: raw["content"])
        guard let text else {
            throw AIError.invalidResponse(provider: providerID, message: "No text block found in Anthropic response.")
        }
        return TextGenerationResult(
            text: text,
            finishReason: anthropicFinishReason(raw["stop_reason"]?.stringValue, toolCalls: toolCalls),
            usage: anthropicTokenUsage(from: raw["usage"]),
            toolCalls: toolCalls,
            toolResults: toolResults,
            sources: sources,
            providerMetadata: anthropicProviderMetadata(from: raw, providerID: providerID, requestProviderOptions: request.providerOptions),
            rawValue: raw,
            warnings: preparedRequest.warnings,
            responseMetadata: aiResponseMetadata(from: raw, response: response, modelID: modelID)
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
                    body = config.transformRequestBody?(body) ?? body
                    let response = try await config.transport.send(config.request(
                        path: path,
                        modelID: modelID,
                        body: .object(body),
                        headers: anthropicHeaders(request.headers, configHeaders: config.headers, betas: preparedRequest.betas),
                        abortSignal: request.abortSignal
                    ))
                    guard (200..<300).contains(response.statusCode) else {
                        throw anthropicHTTPStatusError(provider: providerID, response: response)
                    }
                    continuation.yield(.responseMetadata(aiResponseMetadata(response: response, modelID: modelID)))
                    continuation.yield(.streamStart(warnings: preparedRequest.warnings))
                    var contentBlocks = AnthropicStreamingContentBlocks(
                        providerID: providerID,
                        ignoresTextBlocks: preparedRequest.usesJSONToolResponseFormat
                    )
                    var jsonToolText = AnthropicStreamingJSONToolText()
                    var providerToolResults = AnthropicStreamingProviderToolResults(providerID: providerID)
                    var toolCalls = AnthropicStreamingToolCalls()
                    var realToolCallCount = 0
                    let citationDocuments = anthropicCitationDocuments(from: request.messages)
                    var sourceCounter = 0
                    var finishReason: String?
                    var finishUsage: TokenUsage?
                    var rawUsage: JSONValue?
                    var stopSequence: JSONValue = .null
                    var stopDetails: JSONValue = .null
                    var container: JSONValue = .null
                    var contextManagement: JSONValue = .null
                    var didReceiveMessageStart = false
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        if let streamError = anthropicStreamError(from: raw, provider: providerID, headers: response.headers) {
                            if didReceiveMessageStart {
                                continuation.yield(.error(message: streamError.apiCallError?.responseBody ?? streamError.description, rawValue: raw))
                                break
                            }
                            throw streamError
                        }
                        switch raw["type"]?.stringValue {
                        case "message_start":
                            didReceiveMessageStart = true
                            if let usage = raw["message"]?["usage"] {
                                rawUsage = usage
                            }
                            if let value = anthropicContainerMetadata(from: raw["message"]?["container"]) {
                                container = value
                            }
                            if let reason = raw["message"]?["stop_reason"]?.stringValue {
                                finishReason = anthropicFinishReason(reason, toolCallCount: realToolCallCount)
                            }
                        case "message_delta":
                            finishReason = anthropicFinishReason(raw["delta"]?["stop_reason"]?.stringValue, toolCallCount: realToolCallCount)
                            stopSequence = raw["delta"]?["stop_sequence"] ?? stopSequence
                            stopDetails = anthropicStopDetailsMetadata(from: raw["delta"]?["stop_details"]) ?? stopDetails
                            if let usage = raw["usage"] {
                                rawUsage = rawUsage.map { anthropicMergedUsage($0, usage) } ?? usage
                                finishUsage = anthropicTokenUsage(from: rawUsage)
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
                        for part in contentBlocks.apply(event: raw, toolCallCount: realToolCallCount, usage: rawUsage) {
                            continuation.yield(part)
                        }
                        for part in jsonToolText.apply(event: raw) {
                            continuation.yield(part)
                        }
                        for part in providerToolResults.apply(event: raw) {
                            continuation.yield(part)
                        }
                        for source in anthropicSources(from: raw, citationDocuments: citationDocuments, sourceCounter: &sourceCounter) {
                            continuation.yield(.source(source))
                        }
                        for part in toolCalls.apply(event: raw) {
                            if case .toolCall = part {
                                realToolCallCount += 1
                            }
                            continuation.yield(part)
                        }
                        if raw["type"]?.stringValue == "message_stop" {
                            continuation.yield(.finishMetadata(
                                reason: finishReason,
                                usage: finishUsage,
                                providerMetadata: anthropicProviderMetadata(
                                    usage: rawUsage,
                                    stopSequence: stopSequence,
                                    stopDetails: stopDetails,
                                    container: container,
                                    contextManagement: contextManagement,
                                    providerID: providerID,
                                    requestProviderOptions: request.providerOptions
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
        var betas: [String] = []
        var warnings = anthropicStandardWarnings(for: request)
        let providerOptions = try anthropicOptions(from: request, providerID: providerID)
        let prompt = try Self.promptMessages(
            from: request.messages,
            providerID: providerID,
            sendReasoning: providerOptions.sendReasoning ?? true,
            betas: &betas,
            warnings: &warnings
        )

        let capabilities = anthropicModelCapabilities(modelID)
        let sampling = anthropicSamplingParameters(
            for: request,
            modelID: modelID,
            capabilities: capabilities,
            warnings: &warnings
        )
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "messages": .array(prompt.messages),
            "max_tokens": .number(Double(request.maxOutputTokens ?? capabilities.maxOutputTokens))
        ]
        if stream { body["stream"] = true }
        if !prompt.system.isEmpty { body["system"] = .array(prompt.system) }
        if let temperature = sampling.temperature { body["temperature"] = .number(temperature) }
        if let topK = sampling.topK { body["top_k"] = .number(Double(topK)) }
        if let topP = sampling.topP { body["top_p"] = .number(topP) }
        if !request.stopSequences.isEmpty { body["stop_sequences"] = .array(request.stopSequences) }
        let supportsStructuredOutput = capabilities.supportsStructuredOutput
        let eagerInputStreaming = stream && (providerOptions.toolStreaming ?? true)
        let preparedTools = anthropicPrepareTools(
            from: request.tools,
            toolChoice: request.toolChoice ?? providerOptions.toolChoice,
            disableParallelToolUse: providerOptions.disableParallelToolUse,
            supportsStructuredOutput: supportsStructuredOutput,
            supportsStrictTools: supportsStructuredOutput,
            defaultEagerInputStreaming: eagerInputStreaming
        )
        if !preparedTools.tools.isEmpty {
            body["tools"] = .array(preparedTools.tools)
        }
        if let toolChoice = preparedTools.toolChoice {
            body["tool_choice"] = toolChoice
        }
        body.merge(providerOptions.body) { _, new in new }
        anthropicApplyTopLevelReasoning(
            request.reasoning,
            to: &body,
            capabilities: capabilities,
            warnings: &warnings
        )
        warnings.append(contentsOf: preparedTools.warnings)
        let usesJSONToolResponseFormat = anthropicApplyResponseFormat(
            request.responseFormat,
            to: &body,
            supportsStructuredOutput: supportsStructuredOutput,
            structuredOutputMode: providerOptions.structuredOutputMode,
            eagerInputStreaming: eagerInputStreaming,
            warnings: &warnings
        )
        applyAnthropicThinkingRules(
            to: &body,
            requestedMaxTokens: request.maxOutputTokens,
            requestTemperature: sampling.temperature,
            requestTopP: sampling.topP,
            isAnthropicModel: capabilities.isKnownModel || modelID.hasPrefix("claude-"),
            warnings: &warnings
        )
        anthropicApplyMaxTokenLimit(
            to: &body,
            modelID: modelID,
            requestedMaxTokens: request.maxOutputTokens,
            capabilities: capabilities,
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
        return AnthropicPreparedCall(
            body: body,
            betas: betas,
            warnings: warnings,
            usesJSONToolResponseFormat: usesJSONToolResponseFormat
        )
    }

    private static func promptMessages(
        from messages: [AIMessage],
        providerID: String,
        sendReasoning: Bool,
        betas: inout [String],
        warnings: inout [AIWarning]
    ) throws -> (system: [JSONValue], messages: [JSONValue]) {
        var sawConversationMessage = false
        var cacheBreakpointCount = 0
        var system: [JSONValue] = []
        var conversation: [JSONValue] = []
        for message in messages {
            if message.role == .system, !sawConversationMessage {
                var block: [String: JSONValue] = ["type": .string("text"), "text": .string(message.combinedText)]
                anthropicApplyCacheControl(
                    anthropicCacheControl(from: message.providerMetadata),
                    to: &block,
                    cacheBreakpointCount: &cacheBreakpointCount,
                    warnings: &warnings
                )
                system.append(.object(block))
                continue
            }
            sawConversationMessage = true
            if message.role == .system, !betas.contains("mid-conversation-system-2026-04-07") {
                betas.append("mid-conversation-system-2026-04-07")
            }
            appendAnthropicMessage(
                try messageJSON(
                    message,
                    providerID: providerID,
                    sendReasoning: sendReasoning,
                    betas: &betas,
                    warnings: &warnings,
                    cacheBreakpointCount: &cacheBreakpointCount
                ),
                to: &conversation
            )
        }
        trimTrailingAssistantWhitespace(in: &conversation)
        return (system, conversation)
    }

    private static func appendAnthropicMessage(_ message: JSONValue, to conversation: inout [JSONValue]) {
        let role = message["role"]?.stringValue
        guard role == "user" || role == "assistant",
              let last = conversation.last,
              last["role"]?.stringValue == role,
              var lastObject = last.objectValue else {
            conversation.append(message)
            return
        }
        let mergedContent = (last["content"]?.arrayValue ?? []) + (message["content"]?.arrayValue ?? [])
        lastObject["content"] = .array(mergedContent)
        conversation[conversation.count - 1] = .object(lastObject)
    }

    private static func trimTrailingAssistantWhitespace(in conversation: inout [JSONValue]) {
        guard let last = conversation.last,
              last["role"]?.stringValue == "assistant",
              var message = last.objectValue,
              var content = message["content"]?.arrayValue,
              var lastPart = content.last?.objectValue,
              lastPart["type"]?.stringValue == "text",
              let text = lastPart["text"]?.stringValue else {
            return
        }
        lastPart["text"] = .string(text.trimmingCharacters(in: .whitespacesAndNewlines))
        content[content.count - 1] = .object(lastPart)
        message["content"] = .array(content)
        conversation[conversation.count - 1] = .object(message)
    }

    private static func messageJSON(
        _ message: AIMessage,
        providerID: String,
        sendReasoning: Bool,
        betas: inout [String],
        warnings: inout [AIWarning],
        cacheBreakpointCount: inout Int
    ) throws -> JSONValue {
        let role: String
        switch message.role {
        case .assistant:
            role = "assistant"
        case .system:
            role = "system"
        default:
            role = "user"
        }
        var parts: [JSONValue] = []
        if message.role == .assistant, let reasoning = message.reasoning, !reasoning.isEmpty {
            if sendReasoning {
                if let redactedData = message.providerMetadata["anthropic"]?["redactedData"]?.stringValue {
                    parts.append(.object([
                        "type": .string("redacted_thinking"),
                        "data": .string(redactedData)
                    ]))
                } else if let signature = message.providerMetadata["anthropic"]?["signature"]?.stringValue {
                    parts.append(.object([
                        "type": .string("thinking"),
                        "thinking": .string(reasoning),
                        "signature": .string(signature)
                    ]))
                } else {
                    warnings.append(AIWarning(type: "other", message: "unsupported reasoning metadata"))
                }
            } else {
                warnings.append(AIWarning(type: "other", message: "sending reasoning content is disabled for this model"))
            }
        }
        var mcpToolCallIDs: Set<String> = []
        parts += try message.content.compactMap { part -> JSONValue? in
            switch part {
            case let .text(text, providerMetadata):
                var block: [String: JSONValue] = ["type": .string("text"), "text": .string(text)]
                anthropicApplyPartProviderOptions(
                    providerMetadata,
                    to: &block,
                    cacheBreakpointCount: &cacheBreakpointCount,
                    warnings: &warnings
                )
                return .object(block)
            case let .reasoning(reasoning, providerMetadata):
                guard message.role == .assistant else {
                    return nil
                }
                if sendReasoning {
                    var block: [String: JSONValue] = ["type": .string("thinking"), "thinking": .string(reasoning)]
                    if let signature = providerMetadata["anthropic"]?["signature"]?.stringValue {
                        block["signature"] = .string(signature)
                    }
                    anthropicApplyCacheControl(
                        anthropicCacheControl(from: providerMetadata),
                        to: &block,
                        cacheBreakpointCount: &cacheBreakpointCount,
                        warnings: &warnings
                    )
                    return .object(block)
                }
                warnings.append(AIWarning(type: "other", message: "sending reasoning content is disabled for this model"))
                return nil
            case let .imageURL(url, providerMetadata):
                let content: JSONValue
                if url.lowercased().contains(".pdf") {
                    if !betas.contains("pdfs-2024-09-25") {
                        betas.append("pdfs-2024-09-25")
                    }
                    content = .object([
                        "type": .string("document"),
                        "source": .object([
                            "type": .string("url"),
                            "url": .string(url)
                        ])
                    ])
                } else {
                    content = .object([
                        "type": .string("image"),
                        "source": .object([
                            "type": .string("url"),
                            "url": .string(url)
                        ])
                    ])
                }
                return anthropicApplyPartProviderOptionsIfNeeded(
                    providerMetadata,
                    to: content,
                    cacheBreakpointCount: &cacheBreakpointCount,
                    warnings: &warnings
                )
            case let .data(mimeType, data, providerMetadata):
                let content = try anthropicInlineFileContent(mimeType: mimeType, data: data, filename: nil, betas: &betas)
                return anthropicApplyPartProviderOptionsIfNeeded(
                    providerMetadata,
                    to: content,
                    cacheBreakpointCount: &cacheBreakpointCount,
                    warnings: &warnings
                )
            case let .file(mimeType, data, filename, providerMetadata):
                let content = try anthropicInlineFileContent(mimeType: mimeType, data: data, filename: filename, betas: &betas)
                return anthropicApplyPartProviderOptionsIfNeeded(
                    providerMetadata,
                    to: content,
                    cacheBreakpointCount: &cacheBreakpointCount,
                    warnings: &warnings
                )
            case let .providerReference(mimeType, reference, _, providerMetadata):
                let provider = anthropicProviderReferenceKey(from: providerID)
                let fileID = try resolveProviderReference(reference, provider: provider)
                if !betas.contains("files-api-2025-04-14") {
                    betas.append("files-api-2025-04-14")
                }
                let type = mimeType.lowercased().hasPrefix("image/") ? "image" : "document"
                let content: JSONValue = .object([
                    "type": .string(type),
                    "source": .object([
                        "type": .string("file"),
                        "file_id": .string(fileID)
                    ])
                ])
                return anthropicApplyPartProviderOptionsIfNeeded(
                    providerMetadata,
                    to: content,
                    cacheBreakpointCount: &cacheBreakpointCount,
                    warnings: &warnings
                )
            case let .toolCall(call):
                if call.providerExecuted {
                    let input = anthropicToolArguments(call.arguments)
                    if let serverName = anthropicMCPToolUseServerName(call) {
                        mcpToolCallIDs.insert(call.id)
                        var block: [String: JSONValue] = [
                            "type": .string("mcp_tool_use"),
                            "id": .string(call.id),
                            "name": .string(call.name),
                            "server_name": .string(serverName),
                            "input": input
                        ]
                        anthropicApplyCacheControl(
                            anthropicCacheControl(from: call.providerMetadata),
                            to: &block,
                            cacheBreakpointCount: &cacheBreakpointCount,
                            warnings: &warnings
                        )
                        return .object(block)
                    }
                    var block: [String: JSONValue] = [
                        "type": .string("server_tool_use"),
                        "id": .string(call.id),
                        "name": .string(anthropicProviderExecutedToolName(call.name, input: input)),
                        "input": input
                    ]
                    anthropicApplyCacheControl(
                        anthropicCacheControl(from: call.providerMetadata),
                        to: &block,
                        cacheBreakpointCount: &cacheBreakpointCount,
                        warnings: &warnings
                    )
                    return .object(block)
                }
                var block: [String: JSONValue] = [
                    "type": .string("tool_use"),
                    "id": .string(call.id),
                    "name": .string(call.name),
                    "input": anthropicToolArguments(call.arguments)
                ]
                anthropicApplyCacheControl(
                    anthropicCacheControl(from: call.providerMetadata),
                    to: &block,
                    cacheBreakpointCount: &cacheBreakpointCount,
                    warnings: &warnings
                )
                return .object(block)
            case let .toolResult(result):
                if mcpToolCallIDs.contains(result.toolCallID) || anthropicIsMCPToolResult(result) {
                    warnings.append(AIWarning(
                        type: "other",
                        message: "provider executed tool result for tool \(result.toolName) is not supported"
                    ))
                    return anthropicMCPToolResultBlock(result)
                }
                if anthropicProviderExecutedToolResultNames.contains(result.toolName) {
                    return anthropicProviderExecutedToolResultBlock(result, warnings: &warnings)
                }
                let converted = try anthropicToolResultContent(result, betas: &betas, warnings: &warnings)
                var block: [String: JSONValue] = [
                    "type": .string("tool_result"),
                    "tool_use_id": .string(result.toolCallID),
                    "content": converted.content
                ]
                if converted.isError {
                    block["is_error"] = true
                }
                anthropicApplyCacheControl(
                    anthropicToolResultCacheControl(result),
                    to: &block,
                    cacheBreakpointCount: &cacheBreakpointCount,
                    warnings: &warnings
                )
                return .object(block)
            case .reasoningFile, .custom, .toolApprovalRequest, .toolApprovalResponse:
                return .object(["type": .string("text"), "text": .string("")])
            }
        }
        if message.role == .assistant {
            parts = moveAnthropicToolUseBlocksToEnd(parts)
        }
        anthropicApplyCacheControlToLastPart(
            anthropicCacheControl(from: message.providerMetadata),
            parts: &parts,
            cacheBreakpointCount: &cacheBreakpointCount,
            warnings: &warnings
        )
        return .object(["role": .string(role), "content": .array(parts)])
    }

    private static func anthropicCacheControl(from providerMetadata: [String: JSONValue]) -> JSONValue? {
        let anthropic = providerMetadata["anthropic"]
        return anthropic?["cacheControl"].flatMap(anthropicNonNullCacheControl)
            ?? anthropic?["cache_control"].flatMap(anthropicNonNullCacheControl)
    }

    private static func anthropicToolResultCacheControl(_ result: AIToolResult) -> JSONValue? {
        if let cacheControl = anthropicCacheControl(from: result.providerMetadata) {
            return cacheControl
        }
        let output = result.modelOutput ?? result.result
        if let cacheControl = anthropicProviderOptionsCacheControl(from: output) {
            return cacheControl
        }
        if output["type"]?.stringValue == "content" {
            return (output["value"]?.arrayValue ?? [])
                .lazy
                .compactMap(anthropicProviderOptionsCacheControl)
                .first
        }
        return nil
    }

    private static func anthropicProviderOptionsCacheControl(from value: JSONValue) -> JSONValue? {
        value["providerOptions"]?["anthropic"]?["cacheControl"].flatMap(anthropicNonNullCacheControl)
            ?? value["providerOptions"]?["anthropic"]?["cache_control"].flatMap(anthropicNonNullCacheControl)
    }

    private static func anthropicApplyPartProviderOptionsIfNeeded(
        _ providerMetadata: [String: JSONValue],
        to content: JSONValue,
        cacheBreakpointCount: inout Int,
        warnings: inout [AIWarning]
    ) -> JSONValue {
        guard var block = content.objectValue else { return content }
        anthropicApplyPartProviderOptions(
            providerMetadata,
            to: &block,
            cacheBreakpointCount: &cacheBreakpointCount,
            warnings: &warnings
        )
        return .object(block)
    }

    private static func anthropicApplyPartProviderOptions(
        _ providerMetadata: [String: JSONValue],
        to block: inout [String: JSONValue],
        cacheBreakpointCount: inout Int,
        warnings: inout [AIWarning]
    ) {
        anthropicApplyCacheControl(
            anthropicCacheControl(from: providerMetadata),
            to: &block,
            cacheBreakpointCount: &cacheBreakpointCount,
            warnings: &warnings
        )
        guard block["type"]?.stringValue == "document",
              let anthropic = providerMetadata["anthropic"] else {
            return
        }
        if let title = anthropic["title"]?.stringValue {
            block["title"] = .string(title)
        }
        if let context = anthropic["context"]?.stringValue {
            block["context"] = .string(context)
        }
        if let citations = anthropic["citations"], citations != .null {
            block["citations"] = citations
        }
    }

    private static func anthropicNonNullCacheControl(_ value: JSONValue) -> JSONValue? {
        value == .null ? nil : value
    }

    private static func anthropicApplyCacheControlToLastPart(
        _ cacheControl: JSONValue?,
        parts: inout [JSONValue],
        cacheBreakpointCount: inout Int,
        warnings: inout [AIWarning]
    ) {
        guard !parts.isEmpty, var block = parts[parts.count - 1].objectValue else { return }
        anthropicApplyCacheControl(
            cacheControl,
            to: &block,
            cacheBreakpointCount: &cacheBreakpointCount,
            warnings: &warnings
        )
        parts[parts.count - 1] = .object(block)
    }

    private static func anthropicApplyCacheControl(
        _ cacheControl: JSONValue?,
        to block: inout [String: JSONValue],
        cacheBreakpointCount: inout Int,
        warnings: inout [AIWarning]
    ) {
        guard let cacheControl else { return }
        if block["type"]?.stringValue == "thinking" {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "cache_control on non-cacheable context",
                message: "cache_control cannot be set on thinking block. It will be ignored."
            ))
            return
        }
        if block["type"]?.stringValue == "redacted_thinking" {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "cache_control on non-cacheable context",
                message: "cache_control cannot be set on redacted thinking block. It will be ignored."
            ))
            return
        }
        cacheBreakpointCount += 1
        if cacheBreakpointCount <= 4 {
            block["cache_control"] = cacheControl
        } else {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "cacheControl breakpoint limit",
                message: "Maximum 4 cache breakpoints exceeded (found \(cacheBreakpointCount)). This breakpoint will be ignored."
            ))
        }
    }

    private static func anthropicMCPToolUseServerName(_ call: AIToolCall) -> String? {
        if call.providerMetadata["anthropic"]?["type"]?.stringValue == "mcp-tool-use" {
            return call.providerMetadata["anthropic"]?["serverName"]?.stringValue ?? call.name
        }
        if call.rawValue?["type"]?.stringValue == "mcp_tool_use" {
            return call.rawValue?["server_name"]?.stringValue ?? call.name
        }
        return nil
    }

    private static func anthropicIsMCPToolResult(_ result: AIToolResult) -> Bool {
        result.providerMetadata["anthropic"]?["type"]?.stringValue == "mcp-tool-use"
    }

    private static func anthropicMCPToolResultBlock(_ result: AIToolResult) -> JSONValue {
        .object([
            "type": .string("mcp_tool_result"),
            "tool_use_id": .string(result.toolCallID),
            "content": anthropicMCPToolResultContent(result),
            "is_error": .bool(result.isError)
        ])
    }

    private static func anthropicMCPToolResultContent(_ result: AIToolResult) -> JSONValue {
        let output = result.modelOutput ?? result.result
        if let object = output.objectValue, object["type"]?.stringValue == "json" {
            return object["value"] ?? .array([JSONValue]())
        }
        return output
    }

    private static func anthropicInlineFileContent(
        mimeType: String,
        data: Data,
        filename: String?,
        betas: inout [String]
    ) throws -> JSONValue {
        let resolvedMimeType = try resolveFullMediaType(mediaType: mimeType, data: data)
        let lowercasedMimeType = resolvedMimeType.lowercased()
        if lowercasedMimeType == "application/pdf" {
            if !betas.contains("pdfs-2024-09-25") {
                betas.append("pdfs-2024-09-25")
            }
            return .object([
                "type": .string("document"),
                "source": .object([
                    "type": .string("base64"),
                    "media_type": .string(resolvedMimeType),
                    "data": .string(data.base64EncodedString())
                ])
            ])
        }
        if lowercasedMimeType == "text/plain" {
            var block: [String: JSONValue] = [
                "type": .string("document"),
                "source": .object([
                    "type": .string("text"),
                    "media_type": .string("text/plain"),
                    "data": .string(String(data: data, encoding: .utf8) ?? data.base64EncodedString())
                ])
            ]
            if let filename {
                block["title"] = .string(filename)
            }
            return .object(block)
        }
        if lowercasedMimeType.hasPrefix("image/") {
            return .object([
                "type": .string("image"),
                "source": .object([
                    "type": .string("base64"),
                    "media_type": .string(resolvedMimeType),
                    "data": .string(data.base64EncodedString())
                ])
            ])
        }
        throw AIError.invalidArgument(
            argument: "mediaType",
            message: "Unsupported media type: \(resolvedMimeType)."
        )
    }

    private static func anthropicToolResultContent(
        _ result: AIToolResult,
        betas: inout [String],
        warnings: inout [AIWarning]
    ) throws -> (content: JSONValue, isError: Bool) {
        let output = result.modelOutput ?? result.result
        if let text = output.stringValue {
            return (.string(text), result.isError)
        }
        guard let object = output.objectValue, let type = object["type"]?.stringValue else {
            return (.string(anthropicJSONString(output) ?? ""), result.isError)
        }
        switch type {
        case "content":
            let content = try (object["value"]?.arrayValue ?? []).compactMap { item in
                try anthropicToolResultContentPart(item, betas: &betas, warnings: &warnings)
            }
            return (.array(content), result.isError)
        case "text", "error-text":
            return (.string(object["value"]?.stringValue ?? ""), result.isError || type == "error-text")
        case "execution-denied":
            return (.string(object["reason"]?.stringValue ?? "Tool call execution denied."), result.isError)
        case "json", "error-json":
            return (.string(anthropicJSONString(object["value"] ?? .object([:])) ?? ""), result.isError || type == "error-json")
        default:
            return (.string(anthropicJSONString(object["value"] ?? output) ?? ""), result.isError)
        }
    }

    private static let anthropicProviderExecutedToolResultNames: Set<String> = [
        "advisor",
        "code_execution",
        "tool_search",
        "tool_search_tool_bm25",
        "tool_search_tool_regex",
        "web_fetch",
        "web_search"
    ]

    private static func anthropicProviderExecutedToolName(_ name: String, input: JSONValue) -> String {
        guard name == "code_execution",
              let inputType = input["type"]?.stringValue,
              inputType == "bash_code_execution" || inputType == "text_editor_code_execution" else {
            return name
        }
        return inputType
    }

    private static func anthropicProviderExecutedToolResultBlock(_ result: AIToolResult, warnings: inout [AIWarning]) -> JSONValue? {
        switch result.toolName {
        case "code_execution":
            return anthropicCodeExecutionToolResultBlock(result)
        case "tool_search", "tool_search_tool_bm25", "tool_search_tool_regex":
            return anthropicToolSearchToolResultBlock(result)
        case "web_search":
            return anthropicWebSearchToolResultBlock(result)
        case "web_fetch":
            return anthropicWebFetchToolResultBlock(result)
        case "advisor":
            return anthropicAdvisorToolResultBlock(result, warnings: &warnings)
        default:
            return nil
        }
    }

    private static func anthropicWebSearchToolResultBlock(_ result: AIToolResult) -> JSONValue? {
        let output = result.modelOutput ?? result.result
        let values: [JSONValue]
        if let object = output.objectValue, object["type"]?.stringValue == "json" {
            values = object["value"]?.arrayValue ?? []
        } else if let array = output.arrayValue {
            values = array
        } else {
            return nil
        }
        return .object([
            "type": .string("web_search_tool_result"),
            "tool_use_id": .string(result.toolCallID),
            "content": .array(values.map(anthropicWebSearchResultBlock))
        ])
    }

    private static func anthropicWebFetchToolResultBlock(_ result: AIToolResult) -> JSONValue? {
        let output = result.modelOutput ?? result.result
        guard let object = output.objectValue, let type = object["type"]?.stringValue else {
            return nil
        }
        let content: JSONValue
        switch type {
        case "json":
            content = anthropicWebFetchResultBlock(object["value"] ?? .object([:]))
        case "error-json":
            content = anthropicProviderExecutedErrorBlock(
                object["value"] ?? .object([:]),
                defaultType: "web_fetch_tool_result_error"
            )
        case "web_fetch_result":
            content = anthropicWebFetchResultBlock(output)
        case "web_fetch_tool_result_error":
            content = anthropicProviderExecutedErrorBlock(output, defaultType: "web_fetch_tool_result_error")
        default:
            return nil
        }
        return .object([
            "type": .string("web_fetch_tool_result"),
            "tool_use_id": .string(result.toolCallID),
            "content": content
        ])
    }

    private static func anthropicWebSearchResultBlock(_ result: JSONValue) -> JSONValue {
        .object([
            "type": result["type"] ?? .string("web_search_result"),
            "url": result["url"] ?? .null,
            "title": result["title"] ?? .null,
            "page_age": result["pageAge"] ?? result["page_age"] ?? .null,
            "encrypted_content": result["encryptedContent"] ?? result["encrypted_content"] ?? .null
        ])
    }

    private static func anthropicCodeExecutionToolResultBlock(_ result: AIToolResult) -> JSONValue? {
        let output = result.modelOutput ?? result.result
        let content = output["type"]?.stringValue == "json" ? (output["value"] ?? .object([:])) : output
        guard let contentType = content["type"]?.stringValue else {
            return nil
        }
        let resultType: String
        switch contentType {
        case "code_execution_result", "code_execution_tool_result_error", "encrypted_code_execution_result":
            resultType = "code_execution_tool_result"
        case let type where type.hasPrefix("bash_code_execution"):
            resultType = "bash_code_execution_tool_result"
        case let type where type.hasPrefix("text_editor_code_execution"):
            resultType = "text_editor_code_execution_tool_result"
        default:
            return nil
        }
        return .object([
            "type": .string(resultType),
            "tool_use_id": .string(result.toolCallID),
            "content": anthropicCodeExecutionResultContent(content)
        ])
    }

    private static func anthropicCodeExecutionResultContent(_ content: JSONValue) -> JSONValue {
        if content["type"]?.stringValue == "code_execution_tool_result_error" {
            return anthropicProviderExecutedErrorBlock(content, defaultType: "code_execution_tool_result_error")
        }
        var object = content.objectValue ?? [:]
        if content["type"]?.stringValue == "code_execution_result" || content["type"]?.stringValue == "encrypted_code_execution_result" {
            object["content"] = object["content"] ?? .array([JSONValue]())
        }
        return .object(object)
    }

    private static func anthropicToolSearchToolResultBlock(_ result: AIToolResult) -> JSONValue? {
        let output = result.modelOutput ?? result.result
        if let object = output.objectValue,
           object["type"]?.stringValue == "json",
           let references = object["value"]?.arrayValue {
            return anthropicToolSearchToolResultBlock(toolCallID: result.toolCallID, references: references)
        }
        if let references = output.arrayValue {
            return anthropicToolSearchToolResultBlock(toolCallID: result.toolCallID, references: references)
        }
        if output["type"]?.stringValue == "tool_search_tool_result_error" {
            return .object([
                "type": .string("tool_search_tool_result"),
                "tool_use_id": .string(result.toolCallID),
                "content": anthropicProviderExecutedErrorBlock(output, defaultType: "tool_search_tool_result_error")
            ])
        }
        return nil
    }

    private static func anthropicToolSearchToolResultBlock(toolCallID: String, references: [JSONValue]) -> JSONValue {
        .object([
            "type": .string("tool_search_tool_result"),
            "tool_use_id": .string(toolCallID),
            "content": .object([
                "type": .string("tool_search_tool_search_result"),
                "tool_references": .array(references.map { reference in
                    .object([
                        "type": reference["type"] ?? .string("tool_reference"),
                        "tool_name": reference["toolName"] ?? reference["tool_name"] ?? .null
                    ])
                })
            ])
        ])
    }

    private static func anthropicAdvisorToolResultBlock(_ result: AIToolResult, warnings: inout [AIWarning]) -> JSONValue? {
        let output = result.modelOutput ?? result.result
        guard let object = output.objectValue, let type = object["type"]?.stringValue else {
            return nil
        }
        let content: JSONValue
        switch type {
        case "json":
            content = anthropicAdvisorResultBlock(object["value"] ?? .object([:]))
        case "advisor_result", "advisor_redacted_result", "advisor_tool_result_error":
            content = anthropicAdvisorResultBlock(output)
        default:
            warnings.append(AIWarning(
                type: "other",
                message: "provider executed tool result output type \(type) for tool advisor is not supported"
            ))
            return nil
        }
        return .object([
            "type": .string("advisor_tool_result"),
            "tool_use_id": .string(result.toolCallID),
            "content": content
        ])
    }

    private static func anthropicAdvisorResultBlock(_ result: JSONValue) -> JSONValue {
        switch result["type"]?.stringValue {
        case "advisor_redacted_result":
            return .object([
                "type": .string("advisor_redacted_result"),
                "encrypted_content": result["encryptedContent"] ?? result["encrypted_content"] ?? .null
            ])
        case "advisor_tool_result_error":
            return anthropicProviderExecutedErrorBlock(result, defaultType: "advisor_tool_result_error")
        default:
            return .object([
                "type": result["type"] ?? .string("advisor_result"),
                "text": result["text"] ?? .null
            ])
        }
    }

    private static func anthropicWebFetchResultBlock(_ result: JSONValue) -> JSONValue {
        .object([
            "type": result["type"] ?? .string("web_fetch_result"),
            "url": result["url"] ?? .null,
            "retrieved_at": result["retrievedAt"] ?? result["retrieved_at"] ?? .null,
            "content": anthropicWebFetchDocumentBlock(result["content"] ?? .object([:]))
        ])
    }

    private static func anthropicWebFetchDocumentBlock(_ document: JSONValue) -> JSONValue {
        let source = document["source"]
        return .object([
            "type": document["type"] ?? .string("document"),
            "title": document["title"],
            "citations": document["citations"],
            "source": .object([
                "type": source?["type"],
                "media_type": source?["mediaType"] ?? source?["media_type"],
                "data": source?["data"]
            ])
        ])
    }

    private static func anthropicProviderExecutedErrorBlock(_ value: JSONValue, defaultType: String) -> JSONValue {
        let object: [String: JSONValue]
        if let string = value.stringValue,
           let decoded = try? decodeJSONBody(Data(string.utf8)),
           let decodedObject = decoded.objectValue {
            object = decodedObject
        } else if let valueObject = value.objectValue {
            object = valueObject
        } else {
            object = [:]
        }
        return .object([
            "type": object["type"] ?? .string(defaultType),
            "error_code": object["errorCode"] ?? object["error_code"] ?? .string("unavailable")
        ])
    }

    private static func anthropicToolResultContentPart(
        _ item: JSONValue,
        betas: inout [String],
        warnings: inout [AIWarning]
    ) throws -> JSONValue? {
        switch item["type"]?.stringValue {
        case "text":
            return .object([
                "type": .string("text"),
                "text": item["text"] ?? .string("")
            ])
        case "file":
            return try anthropicToolResultFileContent(
                mediaType: item["mediaType"]?.stringValue ?? "application/octet-stream",
                data: item["data"],
                betas: &betas,
                warnings: &warnings
            )
        case "image-data":
            return try anthropicToolResultBase64FileContent(
                mediaType: item["mediaType"]?.stringValue ?? "image/jpeg",
                base64: item["data"]?.stringValue ?? "",
                betas: &betas,
                warnings: &warnings
            )
        case "image-url":
            return .object([
                "type": .string("image"),
                "source": .object([
                    "type": .string("url"),
                    "url": item["url"] ?? .string("")
                ])
            ])
        case "file-data":
            return try anthropicToolResultBase64FileContent(
                mediaType: item["mediaType"]?.stringValue ?? "application/octet-stream",
                base64: item["data"]?.stringValue ?? "",
                betas: &betas,
                warnings: &warnings
            )
        case "custom":
            if let anthropicOptions = item["providerOptions"]?["anthropic"],
               anthropicOptions["type"]?.stringValue == "tool-reference",
               let toolName = anthropicOptions["toolName"]?.stringValue {
                return .object([
                    "type": .string("tool_reference"),
                    "tool_name": .string(toolName)
                ])
            }
            warnings.append(AIWarning(type: "other", message: "unsupported custom tool content part"))
            return nil
        default:
            warnings.append(AIWarning(type: "other", message: "unsupported tool content part type: \(item["type"]?.stringValue ?? "unknown")"))
            return nil
        }
    }

    private static func anthropicToolResultFileContent(
        mediaType: String,
        data: JSONValue?,
        betas: inout [String],
        warnings: inout [AIWarning]
    ) throws -> JSONValue? {
        switch data?["type"]?.stringValue {
        case "url":
            if topLevelMediaType(mediaType) == "image" {
                return .object([
                    "type": .string("image"),
                    "source": .object([
                        "type": .string("url"),
                        "url": data?["url"] ?? .string("")
                    ])
                ])
            }
            return .object([
                "type": .string("document"),
                "source": .object([
                    "type": .string("url"),
                    "url": data?["url"] ?? .string("")
                ])
            ])
        case "data":
            return try anthropicToolResultBase64FileContent(
                mediaType: mediaType,
                base64: data?["data"]?.stringValue ?? "",
                betas: &betas,
                warnings: &warnings
            )
        default:
            warnings.append(AIWarning(
                type: "other",
                message: "unsupported tool content part type: file with data type: \(data?["type"]?.stringValue ?? "unknown")"
            ))
            return nil
        }
    }

    private static func anthropicToolResultBase64FileContent(
        mediaType: String,
        base64: String,
        betas: inout [String],
        warnings: inout [AIWarning]
    ) throws -> JSONValue? {
        let resolvedMediaType: String
        if isFullMediaType(mediaType) {
            resolvedMediaType = mediaType
        } else if let data = Data(base64Encoded: base64) {
            resolvedMediaType = try resolveFullMediaType(mediaType: mediaType, data: data)
        } else {
            throw AIError.invalidArgument(
                argument: "mediaType",
                message: "File of media type \"\(mediaType)\" must specify subtype since it could not be auto-detected."
            )
        }

        if resolvedMediaType.lowercased().hasPrefix("image/") {
            return .object([
                "type": .string("image"),
                "source": .object([
                    "type": .string("base64"),
                    "media_type": .string(resolvedMediaType),
                    "data": .string(base64)
                ])
            ])
        }
        if resolvedMediaType.lowercased() == "application/pdf" {
            if !betas.contains("pdfs-2024-09-25") {
                betas.append("pdfs-2024-09-25")
            }
            return .object([
                "type": .string("document"),
                "source": .object([
                    "type": .string("base64"),
                    "media_type": .string("application/pdf"),
                    "data": .string(base64)
                ])
            ])
        }

        warnings.append(AIWarning(
            type: "other",
            message: "unsupported tool content part type: file with media type: \(mediaType)"
        ))
        return nil
    }
}

private func moveAnthropicToolUseBlocksToEnd(_ content: [JSONValue]) -> [JSONValue] {
    var nonToolUseBlocks: [JSONValue] = []
    var toolUseBlocks: [JSONValue] = []
    for block in content {
        if block["type"]?.stringValue == "tool_use" {
            toolUseBlocks.append(block)
        } else {
            nonToolUseBlocks.append(block)
        }
    }
    return nonToolUseBlocks + toolUseBlocks
}

struct AnthropicPreparedCall {
    var body: [String: JSONValue]
    var betas: [String]
    var warnings: [AIWarning]
    var usesJSONToolResponseFormat: Bool = false
}

private func anthropicSupportedHTTPURL(_ value: String) -> Bool {
    guard let url = URL(string: value),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https",
          url.host?.isEmpty == false else {
        return false
    }
    return true
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
        let text = anthropicTextContent(from: raw["content"])
        guard let text = text ?? (toolCalls.isEmpty ? nil : "") else {
            throw AIError.invalidResponse(provider: providerID, message: "No text block found in Bedrock Anthropic response.")
        }
        return TextGenerationResult(
            text: text,
            finishReason: anthropicFinishReason(raw["stop_reason"]?.stringValue, toolCalls: toolCalls),
            usage: anthropicTokenUsage(from: raw["usage"]),
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

                    var contentBlocks = AnthropicStreamingContentBlocks(
                        providerID: providerID,
                        ignoresTextBlocks: prepared.usesJSONToolResponseFormat
                    )
                    var jsonToolText = AnthropicStreamingJSONToolText()
                    var providerToolResults = AnthropicStreamingProviderToolResults(providerID: providerID)
                    var toolCalls = AnthropicStreamingToolCalls()
                    var realToolCallCount = 0
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
                        for part in contentBlocks.apply(event: raw, toolCallCount: realToolCallCount) {
                            continuation.yield(part)
                        }
                        for part in jsonToolText.apply(event: raw) {
                            continuation.yield(part)
                        }
                        for part in providerToolResults.apply(event: raw) {
                            continuation.yield(part)
                        }
                        for source in anthropicSources(from: raw, citationDocuments: citationDocuments, sourceCounter: &sourceCounter) {
                            continuation.yield(.source(source))
                        }
                        for part in toolCalls.apply(event: raw) {
                            if case .toolCall = part {
                                realToolCallCount += 1
                            }
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
