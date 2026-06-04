import Foundation

func googleInteractionsHasFunctionCall(_ raw: JSONValue) -> Bool {
    (raw["steps"]?.arrayValue ?? []).contains { step in
        step["type"]?.stringValue == "function_call" || step["type"]?.stringValue == "google_search_call" || step["type"]?.stringValue == "code_execution_call"
    }
}

func googleInteractionsToolCalls(from raw: JSONValue) -> [AIToolCall] {
    (raw["steps"]?.arrayValue ?? []).compactMap { step in
        guard step["type"]?.stringValue == "function_call",
              let name = step["name"]?.stringValue else {
            return nil
        }
        return AIToolCall(
            id: step["id"]?.stringValue ?? "tool-call-\(name)",
            name: name,
            arguments: googleInteractionsArguments(step["arguments"]),
            rawValue: step
        )
    }
}

struct GoogleInteractionsToolCallBuffer {
    var id: String
    var name: String
    var arguments: String
    var inputStarted: Bool
    var rawValue: JSONValue?
}

struct GoogleInteractionsStreamingToolCalls {
    private var buffers: [Int: GoogleInteractionsToolCallBuffer] = [:]

    mutating func start(step: JSONValue?, index: Int?) -> [LanguageStreamPart] {
        let key = index ?? 0
        guard let step,
              let name = step["name"]?.stringValue else {
            return []
        }
        let id = step["id"]?.stringValue ?? "tool-call-\(key)"
        let arguments = googleInteractionsArguments(step["arguments"])
        buffers[key] = GoogleInteractionsToolCallBuffer(
            id: id,
            name: name,
            arguments: arguments == "{}" ? "" : arguments,
            inputStarted: true,
            rawValue: step
        )
        var parts: [LanguageStreamPart] = [.toolInputStart(id: id, name: name)]
        if arguments != "{}" {
            parts.append(.toolCallDelta(id: id, name: name, argumentsDelta: arguments, index: key))
            parts.append(.toolInputDelta(id: id, delta: arguments))
        }
        return parts
    }

    mutating func delta(_ delta: JSONValue, index: Int?) -> [LanguageStreamPart] {
        let key = index ?? 0
        guard var buffer = buffers[key] else {
            return []
        }
        let argumentsDelta = delta["arguments"]?.stringValue ?? ""
        buffer.arguments += argumentsDelta
        buffer.rawValue = delta
        buffers[key] = buffer
        var parts: [LanguageStreamPart] = [.toolCallDelta(id: buffer.id, name: buffer.name, argumentsDelta: argumentsDelta, index: key)]
        if !argumentsDelta.isEmpty {
            parts.append(.toolInputDelta(id: buffer.id, delta: argumentsDelta))
        }
        return parts
    }

    mutating func stop(index: Int?) -> [LanguageStreamPart] {
        let key = index ?? 0
        guard let buffer = buffers[key] else {
            return []
        }
        return [
            .toolInputEnd(id: buffer.id),
            .toolCall(AIToolCall(
            id: buffer.id,
            name: buffer.name,
            arguments: buffer.arguments.isEmpty ? "{}" : buffer.arguments,
            rawValue: buffer.rawValue
            ))
        ]
    }
}

func googleInteractionsArguments(_ value: JSONValue?) -> String {
    guard let value else { return "{}" }
    guard let data = try? encodeJSONBody(value),
          let text = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return text
}

func googleInteractionsFinishReason(status: String?, hasFunctionCall: Bool) -> String? {
    switch status {
    case "completed":
        return hasFunctionCall ? "tool-calls" : "stop"
    case "requires_action":
        return "tool-calls"
    case "failed":
        return "error"
    case "incomplete":
        return "length"
    case "cancelled":
        return "other"
    default:
        return status
    }
}

func googleInteractionsUsage(from raw: JSONValue) -> TokenUsage? {
    guard let usage = raw["usage"] else { return nil }
    let output = (usage["total_output_tokens"]?.intValue ?? 0) + (usage["total_thought_tokens"]?.intValue ?? 0)
    return TokenUsage(
        inputTokens: usage["total_input_tokens"]?.intValue,
        outputTokens: output == 0 && usage["total_output_tokens"] == nil && usage["total_thought_tokens"] == nil ? nil : output,
        totalTokens: usage["total_tokens"]?.intValue
    )
}

func googleInteractionsIsTerminal(_ status: String?) -> Bool {
    switch status {
    case "completed", "failed", "incomplete", "cancelled":
        return true
    default:
        return false
    }
}

func googleInteractionsPollTimeout(raw: JSONValue) -> UInt64 {
    let milliseconds = raw["pollingTimeoutMs"]?.intValue ?? 600_000
    return UInt64(milliseconds) * 1_000_000
}
