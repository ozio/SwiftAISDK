import Foundation

public enum MistralTools {
    public static func webSearch(name: String = "web_search") -> JSONValue { providerTool("mistral.web_search", name: name) }
    public static func webSearchPremium(name: String = "web_search_premium") -> JSONValue { providerTool("mistral.web_search_premium", name: name) }

    private static func providerTool(_ id: String, name: String) -> JSONValue {
        .object(["type": "provider", "id": .string(id), "name": .string(name), "args": .object([:]), "isProviderExecuted": true,
                 "inputSchema": .object(["type": "object", "properties": .object(["arguments": .object(["type": "string"])]), "required": ["arguments"]]),
                 "outputSchema": .object(["type": "object", "properties": .object(["info": .object(["type": "object", "additionalProperties": true])])])])
    }
}

struct MistralConversationToolMapping {
    var customToProvider: [String: String] = [:]
    var providerToCustom: [String: String] = [:]
    init(tools: [String: JSONValue]) {
        for (name, tool) in tools {
            if let id = tool["id"]?.stringValue, let provider = mistralConversationProviderTools[id] {
                customToProvider[name] = provider
                providerToCustom[provider] = name
            }
        }
    }
    func toProvider(_ name: String) -> String { customToProvider[name] ?? name }
    func toCustom(_ name: String) -> String { providerToCustom[name] ?? name }
}

let mistralConversationProviderTools = ["mistral.web_search": "web_search", "mistral.web_search_premium": "web_search_premium"]

func mistralConversationPrepareTools(_ tools: [String: JSONValue], choice: JSONValue?) -> (tools: [JSONValue], choice: JSONValue?, warnings: [AIWarning]) {
    guard !tools.isEmpty else { return ([], nil, []) }
    let mapping = MistralConversationToolMapping(tools: tools)
    let forced = mistralForcedToolName(from: choice).map(mapping.toProvider)
    var warnings: [AIWarning] = []
    let converted = tools.sorted { $0.key < $1.key }.compactMap { name, schema -> JSONValue? in
        if schema["type"] == "provider" || schema["id"] != nil {
            let id = schema["id"]?.stringValue ?? name
            guard let providerName = mistralConversationProviderTools[id] else {
                warnings.append(AIWarning(type: "unsupported", feature: "provider-defined tool \(id)"))
                return nil
            }
            if let forced, forced != providerName { return nil }
            return .object(["type": .string(providerName)])
        }
        if let forced, forced != name { return nil }
        var function: [String: JSONValue] = ["name": .string(name), "parameters": schema]
        if var parameters = schema.objectValue {
            if let description = parameters["description"] { function["description"] = description }
            if let strict = parameters.removeValue(forKey: "strict") { function["strict"] = strict; function["parameters"] = .object(parameters) }
        }
        return .object(["type": "function", "function": .object(function)])
    }
    return (converted, mistralToolChoice(from: choice), warnings)
}
