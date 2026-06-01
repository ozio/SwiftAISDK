import Foundation

func streamFromSSE(providerID: String, response: AIHTTPResponse, includeRawChunks: Bool = false, mapChunk: (JSONValue) -> [LanguageStreamPart]) throws -> [LanguageStreamPart] {
    guard (200..<300).contains(response.statusCode) else {
        throw httpStatusError(provider: providerID, response: response)
    }
    var parts: [LanguageStreamPart] = []
    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
        let raw = try decodeJSONBody(Data(event.data.utf8))
        if includeRawChunks {
            parts.append(.raw(raw))
        }
        parts.append(contentsOf: mapChunk(raw))
    }
    return parts
}

func anthropicStreamParts(from raw: JSONValue) -> [LanguageStreamPart] {
    switch raw["type"]?.stringValue {
    case "content_block_delta":
        let delta = raw["delta"]
        switch delta?["type"]?.stringValue {
        case "text_delta":
            return delta?["text"]?.stringValue.map { [.textDelta($0)] } ?? []
        case "thinking_delta":
            return delta?["thinking"]?.stringValue.map { [.reasoningDelta($0)] } ?? []
        case "compaction_delta":
            return delta?["content"]?.stringValue.map { [.textDelta($0)] } ?? []
        default:
            return []
        }
    case "message_delta":
        return [.finish(
            reason: anthropicFinishReason(raw["delta"]?["stop_reason"]?.stringValue),
            usage: TokenUsage(
                inputTokens: raw["usage"]?["input_tokens"]?.intValue,
                outputTokens: raw["usage"]?["output_tokens"]?.intValue
            )
        )]
    case "message_stop":
        return []
    default:
        return []
    }
}

func googleStreamParts(from raw: JSONValue) -> [LanguageStreamPart] {
    var parts: [LanguageStreamPart] = []
    let contentParts = raw["candidates"]?[0]?["content"]?["parts"]?.arrayValue ?? []
    for contentPart in contentParts {
        guard let text = contentPart["text"]?.stringValue else { continue }
        if contentPart["thought"]?.boolValue == true {
            parts.append(.reasoningDelta(text))
        } else {
            parts.append(.textDelta(text))
        }
    }
    if raw["candidates"]?[0]?["finishReason"]?.stringValue != nil || raw["usageMetadata"] != nil {
        parts.append(.finish(
            reason: raw["candidates"]?[0]?["finishReason"]?.stringValue,
            usage: TokenUsage(
                inputTokens: raw["usageMetadata"]?["promptTokenCount"]?.intValue,
                outputTokens: raw["usageMetadata"]?["candidatesTokenCount"]?.intValue,
                totalTokens: raw["usageMetadata"]?["totalTokenCount"]?.intValue
            )
        ))
    }
    return parts
}

func streamFromGoogleGenerateContent(providerID: String, response: AIHTTPResponse, includeRawChunks: Bool = false, modelID: String? = nil) throws -> [LanguageStreamPart] {
    guard (200..<300).contains(response.statusCode) else {
        throw httpStatusError(provider: providerID, response: response)
    }

    var parts: [LanguageStreamPart] = [.responseMetadata(aiResponseMetadata(response: response, modelID: modelID))]
    var toolCalls = GoogleGenerateContentStreamingToolCalls()
    var latestFinishReason: String?
    var latestUsage: TokenUsage?
    var emittedSourceKeys: Set<String> = []

    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
        let raw = try decodeJSONBody(Data(event.data.utf8))
        if includeRawChunks {
            parts.append(.raw(raw))
        }
        latestUsage = googleGenerateContentUsage(from: raw) ?? latestUsage

        for source in googleGenerateContentSources(from: raw) {
            let key = googleSourceDeduplicationKey(source)
            guard !emittedSourceKeys.contains(key) else { continue }
            emittedSourceKeys.insert(key)
            parts.append(.source(source))
        }

        let contentParts = raw["candidates"]?[0]?["content"]?["parts"]?.arrayValue ?? []
        for contentPart in contentParts {
            if let text = contentPart["text"]?.stringValue {
                if contentPart["thought"]?.boolValue == true {
                    parts.append(.reasoningDelta(text))
                } else if !text.isEmpty {
                    parts.append(.textDelta(text))
                }
            }
            if let functionCall = contentPart["functionCall"] {
                let updates = toolCalls.apply(functionCall: functionCall, rawValue: contentPart)
                parts.append(contentsOf: updates.map {
                    .toolCallDelta(id: $0.id, name: $0.name, argumentsDelta: $0.argumentsDelta, index: $0.index)
                })
            }
        }

        if let reason = raw["candidates"]?[0]?["finishReason"]?.stringValue {
            latestFinishReason = reason
        }
    }

    let finalToolCalls = toolCalls.finishedCalls()
    parts.append(contentsOf: finalToolCalls.map(LanguageStreamPart.toolCall))
    if latestFinishReason != nil || latestUsage != nil {
        parts.append(.finish(
            reason: googleGenerateContentFinishReason(latestFinishReason, hasToolCalls: !finalToolCalls.isEmpty),
            usage: latestUsage
        ))
    }
    return parts
}

func googleGenerateContentText(from raw: JSONValue) -> String? {
    let text = raw["candidates"]?[0]?["content"]?["parts"]?.arrayValue?.compactMap { part in
        part["text"]?.stringValue
    }.joined()
    return text
}

func googleGenerateContentToolCalls(from raw: JSONValue) -> [AIToolCall] {
    raw["candidates"]?[0]?["content"]?["parts"]?.arrayValue?.enumerated().compactMap { index, part in
        guard let functionCall = part["functionCall"],
              let name = functionCall["name"]?.stringValue else {
            return nil
        }
        return AIToolCall(
            id: functionCall["id"]?.stringValue ?? "tool-call-\(index)",
            name: name,
            arguments: googleGenerateContentArguments(functionCall["args"]),
            rawValue: part
        )
    } ?? []
}

func googleGenerateContentSources(from raw: JSONValue) -> [AISource] {
    let chunks = raw["candidates"]?[0]?["groundingMetadata"]?["groundingChunks"]?.arrayValue ?? []
    return chunks.enumerated().compactMap { index, chunk in
        googleGroundingChunkSource(from: chunk, index: index)
    }
}

func googleGenerateContentUsage(from raw: JSONValue) -> TokenUsage? {
    guard raw["usageMetadata"] != nil else { return nil }
    return TokenUsage(
        inputTokens: raw["usageMetadata"]?["promptTokenCount"]?.intValue,
        outputTokens: raw["usageMetadata"]?["candidatesTokenCount"]?.intValue,
        totalTokens: raw["usageMetadata"]?["totalTokenCount"]?.intValue
    )
}

func googleGenerateContentFinishReason(_ reason: String?, hasToolCalls: Bool) -> String? {
    switch reason {
    case "STOP":
        return hasToolCalls ? "tool-calls" : "stop"
    case "MAX_TOKENS":
        return "length"
    case "IMAGE_SAFETY", "RECITATION", "SAFETY", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII":
        return "content-filter"
    case "MALFORMED_FUNCTION_CALL":
        return "error"
    case nil:
        return nil
    default:
        return "other"
    }
}

private func googleGroundingChunkSource(from chunk: JSONValue, index: Int) -> AISource? {
    if let web = chunk["web"], let uri = web["uri"]?.stringValue {
        return AISource(
            id: "grounding-\(index)",
            sourceType: "url",
            url: uri,
            title: web["title"]?.stringValue,
            rawValue: chunk
        )
    }

    if let image = chunk["image"], let sourceURI = image["sourceUri"]?.stringValue {
        return AISource(
            id: "grounding-\(index)",
            sourceType: "url",
            url: sourceURI,
            title: image["title"]?.stringValue,
            rawValue: chunk
        )
    }

    if let retrievedContext = chunk["retrievedContext"] {
        if let uri = retrievedContext["uri"]?.stringValue {
            if uri.hasPrefix("http://") || uri.hasPrefix("https://") {
                return AISource(
                    id: "grounding-\(index)",
                    sourceType: "url",
                    url: uri,
                    title: retrievedContext["title"]?.stringValue,
                    rawValue: chunk
                )
            }

            let filename = googleFilename(from: uri)
            return AISource(
                id: "grounding-\(index)",
                sourceType: "document",
                title: retrievedContext["title"]?.stringValue ?? "Unknown Document",
                mediaType: googleMediaType(for: filename),
                filename: filename,
                rawValue: chunk
            )
        }

        if let fileSearchStore = retrievedContext["fileSearchStore"]?.stringValue {
            return AISource(
                id: "grounding-\(index)",
                sourceType: "document",
                title: retrievedContext["title"]?.stringValue ?? "Unknown Document",
                mediaType: "application/octet-stream",
                filename: googleFilename(from: fileSearchStore),
                rawValue: chunk
            )
        }
    }

    if let maps = chunk["maps"], let uri = maps["uri"]?.stringValue {
        return AISource(
            id: "grounding-\(index)",
            sourceType: "url",
            url: uri,
            title: maps["title"]?.stringValue,
            rawValue: chunk
        )
    }

    return nil
}

private func googleFilename(from uri: String) -> String? {
    uri.split(separator: "/").last.map(String.init)
}

private func googleMediaType(for filename: String?) -> String {
    guard let filename = filename?.lowercased() else {
        return "application/octet-stream"
    }
    if filename.hasSuffix(".pdf") {
        return "application/pdf"
    }
    if filename.hasSuffix(".txt") {
        return "text/plain"
    }
    if filename.hasSuffix(".docx") {
        return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    }
    if filename.hasSuffix(".doc") {
        return "application/msword"
    }
    if filename.hasSuffix(".md") || filename.hasSuffix(".markdown") {
        return "text/markdown"
    }
    return "application/octet-stream"
}

private func googleSourceDeduplicationKey(_ source: AISource) -> String {
    if source.sourceType == "url", let url = source.url {
        return "url:\(url)"
    }
    return "document:\(source.filename ?? source.title ?? source.id)"
}

private struct GoogleGenerateContentToolCallBuffer {
    var id: String?
    var name: String?
    var arguments: [String: JSONValue] = [:]
    var rawValue: JSONValue?
}

private struct GoogleGenerateContentStreamingToolCalls {
    private var buffers: [Int: GoogleGenerateContentToolCallBuffer] = [:]
    private var activeIndex: Int = 0

    mutating func apply(functionCall: JSONValue, rawValue: JSONValue) -> [(id: String?, name: String?, argumentsDelta: String, index: Int?)] {
        if functionCall.objectValue?.isEmpty == true {
            return []
        }

        let index: Int
        if functionCall["name"]?.stringValue != nil {
            index = buffers.isEmpty ? 0 : activeIndex + (buffers[activeIndex]?.name == nil ? 0 : 1)
            activeIndex = index
        } else {
            index = activeIndex
        }

        var buffer = buffers[index] ?? GoogleGenerateContentToolCallBuffer()
        if let id = functionCall["id"]?.stringValue {
            buffer.id = id
        }
        if let name = functionCall["name"]?.stringValue {
            buffer.name = name
        }
        buffer.rawValue = rawValue

        var emitted: [(id: String?, name: String?, argumentsDelta: String, index: Int?)] = []
        if let args = functionCall["args"] {
            let arguments = googleGenerateContentArguments(args)
            buffer.arguments = args.objectValue ?? [:]
            emitted.append((buffer.id, buffer.name, arguments, index))
        }
        if let partialArgs = functionCall["partialArgs"]?.arrayValue {
            for partialArg in partialArgs {
                guard let path = partialArg["jsonPath"]?.stringValue else { continue }
                let value = googlePartialArgValue(partialArg)
                googleSetPartialArgument(path: path, value: value, in: &buffer.arguments)
                let argumentsDelta = googleGenerateContentArguments(.object(buffer.arguments))
                emitted.append((buffer.id, buffer.name, argumentsDelta, index))
            }
        }

        buffers[index] = buffer
        return emitted
    }

    func finishedCalls() -> [AIToolCall] {
        buffers.keys.sorted().compactMap { index in
            guard let buffer = buffers[index], let name = buffer.name else { return nil }
            return AIToolCall(
                id: buffer.id ?? "tool-call-\(index)",
                name: name,
                arguments: googleGenerateContentArguments(.object(buffer.arguments)),
                rawValue: buffer.rawValue
            )
        }
    }
}

private func googleGenerateContentArguments(_ value: JSONValue?) -> String {
    let argumentValue = value ?? .object([:])
    guard let data = try? encodeJSONBody(argumentValue),
          let text = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return text
}

private func googlePartialArgValue(_ partialArg: JSONValue) -> JSONValue {
    if let value = partialArg["stringValue"]?.stringValue {
        return .string(value)
    }
    if let value = partialArg["numberValue"]?.doubleValue {
        return .number(value)
    }
    if let value = partialArg["boolValue"]?.boolValue {
        return .bool(value)
    }
    if let value = partialArg["value"] {
        return value
    }
    return .null
}

private func googleSetPartialArgument(path: String, value: JSONValue, in arguments: inout [String: JSONValue]) {
    guard path.hasPrefix("$.") else { return }
    let key = String(path.dropFirst(2))
    guard !key.isEmpty, !key.contains(".") && !key.contains("[") else { return }

    if case let .string(newValue) = value,
       case let .string(existingValue) = arguments[key] {
        arguments[key] = .string(existingValue + newValue)
    } else {
        arguments[key] = value
    }
}

func bedrockStreamParts(from raw: JSONValue) -> [LanguageStreamPart] {
    var parts: [LanguageStreamPart] = []
    if let text = raw["contentBlockDelta"]?["delta"]?["text"]?.stringValue {
        parts.append(.textDelta(text))
    }
    if let reasoning = raw["contentBlockDelta"]?["delta"]?["reasoningContent"]?["text"]?.stringValue {
        parts.append(.reasoningDelta(reasoning))
    }
    if raw["messageStop"] != nil || raw["metadata"]?["usage"] != nil {
        parts.append(.finish(
            reason: raw["messageStop"]?["stopReason"]?.stringValue,
            usage: TokenUsage(
                inputTokens: raw["metadata"]?["usage"]?["inputTokens"]?.intValue,
                outputTokens: raw["metadata"]?["usage"]?["outputTokens"]?.intValue,
                totalTokens: raw["metadata"]?["usage"]?["totalTokens"]?.intValue
            )
        ))
    }
    return parts
}

private struct BedrockStreamingToolCall {
    var id: String
    var name: String
    var arguments: String = ""
    var rawValue: JSONValue?
}

private struct BedrockStreamState {
    var toolCalls: [Int: BedrockStreamingToolCall] = [:]
    var latestFinishReason: String?
    var latestUsage: TokenUsage?

    mutating func parts(from raw: JSONValue) -> [LanguageStreamPart] {
        var parts: [LanguageStreamPart] = []
        if let text = raw["contentBlockDelta"]?["delta"]?["text"]?.stringValue {
            parts.append(.textDelta(text))
        }
        if let reasoning = raw["contentBlockDelta"]?["delta"]?["reasoningContent"]?["text"]?.stringValue {
            parts.append(.reasoningDelta(reasoning))
        }
        if let signature = raw["contentBlockDelta"]?["delta"]?["reasoningContent"]?["signature"] {
            let payload: [String: JSONValue] = ["signature": signature]
            parts.append(.metadata(["amazonBedrock": .object(payload), "bedrock": .object(payload)]))
        }
        if let redactedData = raw["contentBlockDelta"]?["delta"]?["reasoningContent"]?["data"] {
            let payload: [String: JSONValue] = ["redactedData": redactedData]
            parts.append(.metadata(["amazonBedrock": .object(payload), "bedrock": .object(payload)]))
        }
        if let start = raw["contentBlockStart"],
           let toolUse = start["start"]?["toolUse"] {
            let index = start["contentBlockIndex"]?.intValue ?? 0
            let id = toolUse["toolUseId"]?.stringValue ?? "tool-call-\(index)"
            let name = toolUse["name"]?.stringValue ?? "tool-\(index)"
            toolCalls[index] = BedrockStreamingToolCall(id: id, name: name, rawValue: toolUse)
        }
        if let delta = raw["contentBlockDelta"],
           let toolUse = delta["delta"]?["toolUse"] {
            let index = delta["contentBlockIndex"]?.intValue ?? 0
            var toolCall = toolCalls[index] ?? BedrockStreamingToolCall(id: "tool-call-\(index)", name: "tool-\(index)")
            let argumentsDelta = toolUse["input"]?.stringValue ?? ""
            toolCall.arguments += argumentsDelta
            toolCall.rawValue = toolUse
            toolCalls[index] = toolCall
            parts.append(.toolCallDelta(id: toolCall.id, name: toolCall.name, argumentsDelta: argumentsDelta, index: index))
        }
        if let stop = raw["contentBlockStop"],
           let index = stop["contentBlockIndex"]?.intValue,
           let toolCall = toolCalls[index] {
            parts.append(.toolCall(AIToolCall(
                id: toolCall.id,
                name: toolCall.name,
                arguments: toolCall.arguments.isEmpty ? "{}" : toolCall.arguments,
                rawValue: toolCall.rawValue
            )))
        }
        if let stopReason = raw["messageStop"]?["stopReason"]?.stringValue {
            latestFinishReason = bedrockFinishReason(stopReason)
        }
        if let usage = bedrockUsage(from: raw["metadata"]?["usage"]) {
            latestUsage = usage
        }
        let metadata = bedrockProviderMetadata(fromStreamMetadata: raw["metadata"])
        if !metadata.isEmpty {
            parts.append(.metadata(metadata))
        }
        if raw["messageStop"] != nil || raw["metadata"]?["usage"] != nil {
            parts.append(.finish(reason: latestFinishReason, usage: latestUsage))
        }
        return parts
    }
}

func streamFromBedrockResponse(providerID: String, response: AIHTTPResponse, includeRawChunks: Bool = false) throws -> [LanguageStreamPart] {
    guard (200..<300).contains(response.statusCode) else {
        throw httpStatusError(provider: providerID, response: response)
    }

    let contentType = response.headers.first { $0.key.caseInsensitiveCompare("content-type") == .orderedSame }?.value
    let rawChunks: [JSONValue]
    if contentType?.localizedCaseInsensitiveContains("application/vnd.amazon.eventstream") == true {
        rawChunks = try parseAmazonBedrockEventStream(response.body)
    } else {
        rawChunks = try parseServerSentEvents(response.body)
            .filter { $0.data != "[DONE]" }
            .map { try decodeJSONBody(Data($0.data.utf8)) }
    }

    var parts: [LanguageStreamPart] = []
    var state = BedrockStreamState()
    for raw in rawChunks {
        if includeRawChunks {
            parts.append(.raw(raw))
        }
        parts.append(contentsOf: state.parts(from: raw))
    }
    return parts
}

func parseAmazonBedrockEventStream(_ data: Data) throws -> [JSONValue] {
    var offset = 0
    var chunks: [JSONValue] = []

    while offset + 16 <= data.count {
        let totalLength = Int(readUInt32(data, at: offset))
        let headersLength = Int(readUInt32(data, at: offset + 4))
        guard totalLength >= 16, offset + totalLength <= data.count else { break }

        let headersStart = offset + 12
        let payloadStart = headersStart + headersLength
        let payloadEnd = offset + totalLength - 4
        guard payloadStart <= payloadEnd else { break }

        let headers = parseAmazonEventStreamHeaders(data, start: headersStart, length: headersLength)
        if headers[":message-type"] == "event",
           let eventType = headers[":event-type"] {
            let payload = data.subdata(in: payloadStart..<payloadEnd)
            let rawPayload = try decodeJSONBody(payload)
            chunks.append(.object([eventType: rawPayload]))
        }

        offset += totalLength
    }

    return chunks
}

private func parseAmazonEventStreamHeaders(_ data: Data, start: Int, length: Int) -> [String: String] {
    var headers: [String: String] = [:]
    var offset = start
    let end = start + length

    while offset < end {
        guard offset < data.count else { break }
        let nameLength = Int(data[offset])
        offset += 1
        guard offset + nameLength + 1 <= data.count else { break }
        let name = String(data: data.subdata(in: offset..<(offset + nameLength)), encoding: .utf8) ?? ""
        offset += nameLength
        let type = data[offset]
        offset += 1

        switch type {
        case 7:
            guard offset + 2 <= data.count else { return headers }
            let valueLength = Int(readUInt16(data, at: offset))
            offset += 2
            guard offset + valueLength <= data.count else { return headers }
            headers[name] = String(data: data.subdata(in: offset..<(offset + valueLength)), encoding: .utf8)
            offset += valueLength
        case 0, 1:
            headers[name] = type == 0 ? "true" : "false"
        case 2:
            offset += 1
        case 3:
            offset += 2
        case 4:
            offset += 4
        case 5, 8:
            offset += 8
        case 6:
            guard offset + 2 <= data.count else { return headers }
            let valueLength = Int(readUInt16(data, at: offset))
            offset += 2 + valueLength
        case 9:
            offset += 16
        default:
            return headers
        }
    }

    return headers
}

private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
    (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
}

private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
    (UInt32(data[offset]) << 24)
        | (UInt32(data[offset + 1]) << 16)
        | (UInt32(data[offset + 2]) << 8)
        | UInt32(data[offset + 3])
}
