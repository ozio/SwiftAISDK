import Foundation

func fireworksChatBody(from input: [String: JSONValue]) -> [String: JSONValue] {
    var body = input

    if let value = body.removeValue(forKey: "reasoningEffort") {
        body["reasoning_effort"] = value
    }

    if let effort = body["reasoning_effort"]?.stringValue {
        body["reasoning_effort"] = .string(fireworksReasoningEffort(effort))
    }

    if let thinking = body.removeValue(forKey: "thinking")?.objectValue {
        var converted: [String: JSONValue] = [:]
        if let type = thinking["type"] { converted["type"] = type }
        if let budgetTokens = thinking["budgetTokens"] {
            converted["budget_tokens"] = budgetTokens
        } else if let budgetTokens = thinking["budget_tokens"] {
            converted["budget_tokens"] = budgetTokens
        }
        body["thinking"] = .object(converted)
    }

    if let reasoningHistory = body.removeValue(forKey: "reasoningHistory") {
        body["reasoning_history"] = reasoningHistory
    }

    return body
}

func fireworksReasoningEffort(_ value: String) -> String {
    switch value {
    case "minimal":
        return "low"
    case "xhigh":
        return "high"
    default:
        return value
    }
}
