import Foundation

func streamFromSSE(providerID: String, response: AIHTTPResponse, includeRawChunks: Bool = false, mapChunk: (JSONValue) -> [LanguageStreamPart]) throws -> [LanguageStreamPart] {
    guard (200..<300).contains(response.statusCode) else {
        throw apiCallError(provider: providerID, response: response)
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

struct OpenAIStyleToolCallBuffer {
    var id: String?
    var name: String?
    var arguments: String = ""
    var inputStarted = false
    var rawValue: JSONValue?
    var fallbackIndex: Int
}

struct OpenAIStyleStreamingToolCalls {
    private var buffers: [OpenAIStyleToolCallBuffer] = []
    private var positionsByID: [String: Int] = [:]
    private var positionsByIndex: [Int: Int] = [:]
    private var latestPosition: Int?

    func hasMatchingBuffer(for delta: JSONValue) -> Bool {
        resolvedPosition(for: delta) != nil
    }

    mutating func apply(delta: JSONValue) -> [LanguageStreamPart] {
        let incomingIndex = delta["index"]?.intValue
        let position = resolvedPosition(for: delta) ?? buffers.endIndex
        if position == buffers.endIndex {
            buffers.append(OpenAIStyleToolCallBuffer(fallbackIndex: incomingIndex ?? position))
        }

        var buffer = buffers[position]
        if let id = delta["id"]?.stringValue, !id.isEmpty {
            buffer.id = id
            positionsByID[id] = position
        }
        if let name = delta["function"]?["name"]?.stringValue {
            buffer.name = name
        }
        let argumentsDelta = delta["function"]?["arguments"]?.stringValue ?? ""
        if !argumentsDelta.isEmpty {
            buffer.arguments += argumentsDelta
        }
        buffer.rawValue = delta

        let id = buffer.id ?? "tool-call-\(buffer.fallbackIndex)"
        var parts: [LanguageStreamPart] = []
        if !buffer.inputStarted, let name = buffer.name {
            parts.append(.toolInputStart(id: id, name: name))
            buffer.inputStarted = true
        }
        parts.append(.toolCallDelta(
            id: buffer.id,
            name: buffer.name,
            argumentsDelta: argumentsDelta,
            index: incomingIndex
        ))
        if !argumentsDelta.isEmpty, buffer.inputStarted {
            parts.append(.toolInputDelta(id: id, delta: argumentsDelta))
        }
        buffers[position] = buffer
        if let incomingIndex {
            positionsByIndex[incomingIndex] = position
        }
        latestPosition = position
        return parts
    }

    mutating func finishedParts() -> [LanguageStreamPart] {
        var parts: [LanguageStreamPart] = []
        for position in buffers.indices {
            var buffer = buffers[position]
            guard let name = buffer.name else { continue }
            let id = buffer.id ?? "tool-call-\(buffer.fallbackIndex)"
            if !buffer.inputStarted {
                parts.append(.toolInputStart(id: id, name: name))
                buffer.inputStarted = true
                buffers[position] = buffer
            }
            parts.append(.toolInputEnd(id: id))
            parts.append(.toolCall(AIToolCall(
                id: id,
                name: name,
                arguments: buffer.arguments,
                rawValue: buffer.rawValue
            )))
        }
        return parts
    }

    private func resolvedPosition(for delta: JSONValue) -> Int? {
        if let id = delta["id"]?.stringValue, !id.isEmpty {
            return positionsByID[id]
        }
        if let index = delta["index"]?.intValue {
            return positionsByIndex[index]
        }
        return latestPosition
    }
}
