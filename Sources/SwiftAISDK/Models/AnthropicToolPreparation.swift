import Foundation

struct AnthropicPreparedTools {
    var tools: [JSONValue] = []
    var toolChoice: JSONValue?
    var betas: [String] = []
    var warnings: [AIWarning] = []
    var hasCodeExecution = false
}

func anthropicPrepareTools(
    from tools: [String: JSONValue],
    toolChoice: JSONValue? = nil,
    disableParallelToolUse: Bool? = nil,
    defaultEagerInputStreaming: Bool = false
) -> AnthropicPreparedTools {
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
            var tool: [String: JSONValue] = ["name": .string(name), "input_schema": schema]
            if defaultEagerInputStreaming {
                tool["eager_input_streaming"] = true
            }
            prepared.tools.append(.object(tool))
            continue
        }

        let id = object?["id"]?.stringValue ?? name
        let args = object?["args"]?.objectValue ?? [:]
        switch id {
        case "anthropic.code_execution_20250522":
            addBeta("code-execution-2025-05-22")
            prepared.hasCodeExecution = true
            prepared.tools.append(.object(["type": "code_execution_20250522", "name": "code_execution"]))
        case "anthropic.code_execution_20250825":
            addBeta("code-execution-2025-08-25")
            prepared.hasCodeExecution = true
            prepared.tools.append(.object(["type": "code_execution_20250825", "name": "code_execution"]))
        case "anthropic.code_execution_20260120":
            prepared.hasCodeExecution = true
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
            prepared.warnings.append(AIWarning(type: "unsupported", feature: "provider-defined tool \(id)"))
        }
    }
    let choice = anthropicToolChoice(from: toolChoice, disableParallelToolUse: disableParallelToolUse)
    if choice.omitTools {
        prepared.tools = []
        prepared.toolChoice = nil
    } else if !prepared.tools.isEmpty {
        prepared.toolChoice = choice.value
    }
    return prepared
}

func anthropicComputerTool(type: String, args: [String: JSONValue], includeZoom: Bool = false) -> JSONValue {
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

func anthropicWebTool(type: String, name: String, args: [String: JSONValue], includeFetchFields: Bool) -> JSONValue {
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

func anthropicToolChoice(from value: JSONValue?, disableParallelToolUse: Bool?) -> (value: JSONValue?, omitTools: Bool) {
    guard let value else {
        guard let disableParallelToolUse, disableParallelToolUse else {
            return (nil, false)
        }
        return (.object([
            "type": .string("auto"),
            "disable_parallel_tool_use": .bool(disableParallelToolUse)
        ]), false)
    }

    let type = value["type"]?.stringValue ?? value.stringValue
    var object: [String: JSONValue]
    switch type {
    case "auto":
        object = ["type": .string("auto")]
    case "required", "any":
        object = ["type": .string("any")]
    case "none":
        return (nil, true)
    case "tool":
        object = ["type": .string("tool")]
        if let name = value["toolName"]?.stringValue ?? value["name"]?.stringValue {
            object["name"] = .string(name)
        }
    default:
        return (nil, false)
    }
    if let disableParallelToolUse {
        object["disable_parallel_tool_use"] = .bool(disableParallelToolUse)
    }
    return (.object(object), false)
}

func anthropicHeaders(_ requestHeaders: [String: String], configHeaders: [String: String], betas: [String]) -> [String: String] {
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

func anthropicProviderReferenceKey(from providerID: String) -> String {
    if providerID.hasPrefix("anthropic-aws") {
        return "anthropic-aws"
    }
    return "anthropic"
}

