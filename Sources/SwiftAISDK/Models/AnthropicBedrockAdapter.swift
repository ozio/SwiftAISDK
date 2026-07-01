import Foundation

func amazonBedrockAnthropicBody(_ body: [String: JSONValue], betas: [String]) -> [String: JSONValue] {
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

func amazonBedrockAnthropicResolveURLContent(
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
            case let .imageURL(url, _):
                let downloaded = try await amazonBedrockAnthropicDownloadContent(url, transport: transport, abortSignal: abortSignal, providerID: providerID)
                resolvedParts.append(.data(mimeType: downloaded.mimeType, data: downloaded.data))
            case .text, .reasoning, .data, .file, .reasoningFile, .custom, .providerReference, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
                resolvedParts.append(part)
            }
        }
        resolvedMessages.append(AIMessage(
            role: message.role,
            content: resolvedParts,
            reasoning: message.reasoning,
            providerMetadata: message.providerMetadata
        ))
    }

    return resolvedMessages
}

func amazonBedrockAnthropicDownloadContent(
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
        throw apiCallError(provider: providerID, response: response)
    }
    let mediaType = amazonBedrockAnthropicMediaType(
        contentType: response.headerValue("content-type"),
        data: response.body,
        url: url
    )
    return (mediaType, response.body)
}

func amazonBedrockAnthropicDataURL(_ url: String) -> (mimeType: String, data: Data)? {
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

func amazonBedrockAnthropicMediaType(contentType: String?, data: Data, url: String) -> String {
    if let contentType {
        let mediaType = contentType.split(separator: ";", maxSplits: 1).first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        if isFullMediaType(mediaType), mediaType.lowercased() != "application/octet-stream" {
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

func amazonBedrockAnthropicApplyStructuredOutputSupport(modelID: String, prepared: inout AnthropicPreparedCall) {
    guard modelID.contains("claude-opus-4-7") || modelID.contains("claude-opus-4-8") || modelID.contains("claude-fable-5") else {
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

func amazonBedrockAnthropicTool(_ tool: JSONValue, betas: inout [String]) -> JSONValue {
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

func amazonBedrockAnthropicBeta(for toolType: String) -> String? {
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

func amazonBedrockAnthropicStreamEvents(from response: AIHTTPResponse) throws -> [JSONValue] {
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
