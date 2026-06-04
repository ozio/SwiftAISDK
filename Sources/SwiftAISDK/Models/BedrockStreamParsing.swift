import Foundation

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

struct BedrockStreamingToolCall {
    var id: String
    var name: String
    var arguments: String = ""
    var rawValue: JSONValue?
}

struct BedrockStreamState {
    var toolCalls: [Int: BedrockStreamingToolCall] = [:]
    var latestFinishReason: String?
    var latestUsage: TokenUsage?
    var jsonResponseToolName: String?
    var isJsonResponseFromTool = false

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
            if name == jsonResponseToolName {
                isJsonResponseFromTool = true
                return parts
            }
            parts.append(.toolInputStart(id: id, name: name))
        }
        if let delta = raw["contentBlockDelta"],
           let toolUse = delta["delta"]?["toolUse"] {
            let index = delta["contentBlockIndex"]?.intValue ?? 0
            var toolCall = toolCalls[index] ?? BedrockStreamingToolCall(id: "tool-call-\(index)", name: "tool-\(index)")
            let argumentsDelta = toolUse["input"]?.stringValue ?? ""
            toolCall.arguments += argumentsDelta
            toolCall.rawValue = toolUse
            toolCalls[index] = toolCall
            if toolCall.name == jsonResponseToolName {
                parts.append(.textDelta(argumentsDelta))
                return parts
            }
            parts.append(.toolCallDelta(id: toolCall.id, name: toolCall.name, argumentsDelta: argumentsDelta, index: index))
            if !argumentsDelta.isEmpty {
                parts.append(.toolInputDelta(id: toolCall.id, delta: argumentsDelta))
            }
        }
        if let stop = raw["contentBlockStop"],
           let index = stop["contentBlockIndex"]?.intValue,
           let toolCall = toolCalls[index] {
            if toolCall.name == jsonResponseToolName {
                return parts
            }
            parts.append(.toolInputEnd(id: toolCall.id))
            parts.append(.toolCall(AIToolCall(
                id: toolCall.id,
                name: toolCall.name,
                arguments: toolCall.arguments.isEmpty ? "{}" : toolCall.arguments,
                rawValue: toolCall.rawValue
            )))
        }
        if let stopReason = raw["messageStop"]?["stopReason"]?.stringValue {
            latestFinishReason = bedrockFinishReason(stopReason, isJsonResponseFromTool: isJsonResponseFromTool)
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

func streamFromBedrockResponse(providerID: String, response: AIHTTPResponse, includeRawChunks: Bool = false, warnings: [AIWarning] = [], jsonResponseToolName: String? = nil) throws -> [LanguageStreamPart] {
    guard (200..<300).contains(response.statusCode) else {
        throw apiCallError(provider: providerID, response: response)
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

    var parts: [LanguageStreamPart] = [.streamStart(warnings: warnings)]
    var state = BedrockStreamState(jsonResponseToolName: jsonResponseToolName)
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

func parseAmazonEventStreamHeaders(_ data: Data, start: Int, length: Int) -> [String: String] {
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

func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
    (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
}

func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
    (UInt32(data[offset]) << 24)
        | (UInt32(data[offset + 1]) << 16)
        | (UInt32(data[offset + 2]) << 8)
        | UInt32(data[offset + 3])
}
