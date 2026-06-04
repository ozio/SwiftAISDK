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

struct OpenAIStyleToolCallBuffer {
    var id: String?
    var name: String?
    var arguments: String = ""
    var inputStarted = false
    var rawValue: JSONValue?
}

struct OpenAIStyleStreamingToolCalls {
    private var buffers: [Int: OpenAIStyleToolCallBuffer] = [:]

    mutating func apply(delta: JSONValue) -> [LanguageStreamPart] {
        let index = delta["index"]?.intValue ?? 0
        var buffer = buffers[index] ?? OpenAIStyleToolCallBuffer()
        if let id = delta["id"]?.stringValue {
            buffer.id = id
        }
        if let name = delta["function"]?["name"]?.stringValue {
            buffer.name = name
        }
        let argumentsDelta = delta["function"]?["arguments"]?.stringValue ?? ""
        if !argumentsDelta.isEmpty {
            buffer.arguments += argumentsDelta
        }
        buffer.rawValue = delta

        let id = buffer.id ?? "tool-call-\(index)"
        var parts: [LanguageStreamPart] = []
        if !buffer.inputStarted, let name = buffer.name {
            parts.append(.toolInputStart(id: id, name: name))
            buffer.inputStarted = true
        }
        parts.append(.toolCallDelta(
            id: buffer.id,
            name: buffer.name,
            argumentsDelta: argumentsDelta,
            index: index
        ))
        if !argumentsDelta.isEmpty, buffer.inputStarted {
            parts.append(.toolInputDelta(id: id, delta: argumentsDelta))
        }
        buffers[index] = buffer
        return parts
    }

    mutating func finishedParts() -> [LanguageStreamPart] {
        var parts: [LanguageStreamPart] = []
        for index in buffers.keys.sorted() {
            guard var buffer = buffers[index], let name = buffer.name else { continue }
            let id = buffer.id ?? "tool-call-\(index)"
            if !buffer.inputStarted {
                parts.append(.toolInputStart(id: id, name: name))
                buffer.inputStarted = true
                buffers[index] = buffer
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
}

