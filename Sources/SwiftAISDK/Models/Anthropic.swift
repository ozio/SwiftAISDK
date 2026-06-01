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
        let preparedRequest = Self.body(for: request, modelID: modelID)
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
            sources: sources,
            rawValue: raw,
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let preparedRequest = Self.body(for: request, modelID: modelID, stream: true)
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
                    var toolCalls = AnthropicStreamingToolCalls()
                    let citationDocuments = anthropicCitationDocuments(from: request.messages)
                    var sourceCounter = 0
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        for part in anthropicStreamParts(from: raw) {
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

    fileprivate static func body(for request: LanguageModelRequest, modelID: String, stream: Bool = false) -> (body: [String: JSONValue], betas: [String]) {
        let systemText = request.messages
            .filter { $0.role == .system }
            .map(\.combinedText)
            .joined(separator: "\n")
        let messages = request.messages
            .filter { $0.role != .system }
            .map(Self.messageJSON)

        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "messages": .array(messages),
            "max_tokens": .number(Double(request.maxOutputTokens ?? 1024))
        ]
        if stream { body["stream"] = true }
        if !systemText.isEmpty { body["system"] = .string(systemText) }
        if let temperature = request.temperature { body["temperature"] = .number(min(max(temperature, 0), 1)) }
        if let topP = request.topP { body["top_p"] = .number(topP) }
        if !request.stopSequences.isEmpty { body["stop_sequences"] = .array(request.stopSequences) }
        let preparedTools = anthropicPrepareTools(from: request.tools)
        if !preparedTools.tools.isEmpty {
            body["tools"] = .array(preparedTools.tools)
        }
        body.merge(anthropicOptions(from: request.extraBody)) { _, new in new }
        applyAnthropicThinkingRules(to: &body, requestedMaxTokens: request.maxOutputTokens)
        return (body, preparedTools.betas)
    }

    private static func messageJSON(_ message: AIMessage) -> JSONValue {
        let role = message.role == .assistant ? "assistant" : "user"
        let parts = message.content.map { part -> JSONValue in
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

public final class AmazonBedrockAnthropicLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "bedrock.anthropic.messages"
    public let modelID: String
    private let config: BedrockRuntimeConfig

    init(modelID: String, config: BedrockRuntimeConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = AnthropicLanguageModel.body(for: request, modelID: modelID)
        let body = amazonBedrockAnthropicBody(prepared.body, betas: prepared.betas)
        let raw = try await config.sendJSON(path: "/model/\(bedrockEncodeModelID(modelID))/invoke", body: .object(body), headers: request.headers)
        let toolCalls = anthropicToolCalls(from: raw["content"])
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
            sources: sources,
            rawValue: raw
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = AnthropicLanguageModel.body(for: request, modelID: modelID, stream: true)
                    let body = amazonBedrockAnthropicBody(prepared.body, betas: prepared.betas)
                    let response = try await config.transport.send(try config.request(
                        path: "/model/\(bedrockEncodeModelID(modelID))/invoke-with-response-stream",
                        body: .object(body),
                        headers: request.headers.mergingHeaders(["accept": "application/vnd.amazon.eventstream"])
                    ))
                    guard (200..<300).contains(response.statusCode) else {
                        throw httpStatusError(provider: providerID, response: response)
                    }

                    var toolCalls = AnthropicStreamingToolCalls()
                    let citationDocuments = anthropicCitationDocuments(from: request.messages)
                    var sourceCounter = 0
                    for raw in try amazonBedrockAnthropicStreamEvents(from: response) {
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        for part in anthropicStreamParts(from: raw) {
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
}

private struct AnthropicToolCallBuffer {
    var id: String
    var name: String
    var arguments: String
    var providerExecuted: Bool
    var rawValue: JSONValue
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
            return [.toolCallDelta(id: toolCall.id, name: toolCall.name, argumentsDelta: initialArguments, index: index)]
        case "content_block_delta":
            guard raw["delta"]?["type"]?.stringValue == "input_json_delta",
                  let index = raw["index"]?.intValue,
                  var buffer = buffers[index] else {
                return []
            }
            let delta = raw["delta"]?["partial_json"]?.stringValue ?? ""
            buffer.arguments += delta
            buffers[index] = buffer
            return [.toolCallDelta(id: buffer.id, name: buffer.name, argumentsDelta: delta, index: index)]
        case "content_block_stop":
            guard let index = raw["index"]?.intValue, let buffer = buffers.removeValue(forKey: index) else {
                return []
            }
            return [.toolCall(AIToolCall(
                id: buffer.id,
                name: buffer.name,
                arguments: buffer.arguments.isEmpty ? "{}" : buffer.arguments,
                providerExecuted: buffer.providerExecuted,
                rawValue: buffer.rawValue
            ))]
        default:
            return []
        }
    }
}

private struct AnthropicPreparedTools {
    var tools: [JSONValue] = []
    var betas: [String] = []
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
            prepared.tools.append(.object(["type": "code_execution_20250522", "name": "code_execution"]))
        case "anthropic.code_execution_20250825":
            addBeta("code-execution-2025-08-25")
            prepared.tools.append(.object(["type": "code_execution_20250825", "name": "code_execution"]))
        case "anthropic.code_execution_20260120":
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
        case .text, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
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

private func applyAnthropicThinkingRules(to body: inout [String: JSONValue], requestedMaxTokens: Int?) {
    guard var thinking = body["thinking"]?.objectValue,
          let type = thinking["type"]?.stringValue,
          type == "enabled" || type == "adaptive" else {
        return
    }

    if type == "enabled", thinking["budget_tokens"] == nil {
        thinking["budget_tokens"] = 1024
        body["thinking"] = .object(thinking)
    }

    body["temperature"] = nil
    body["top_k"] = nil
    body["top_p"] = nil

    if type == "enabled" {
        let budget = thinking["budget_tokens"]?.intValue ?? 1024
        body["max_tokens"] = .number(Double((requestedMaxTokens ?? 1024) + budget))
    }
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
