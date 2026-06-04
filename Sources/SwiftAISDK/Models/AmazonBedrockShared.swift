import Foundation

func bedrockEncodeModelID(_ modelID: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return modelID.addingPercentEncoding(withAllowedCharacters: allowed) ?? modelID
}

let bedrockDocumentMimeTypes: [String: String] = [
    "application/pdf": "pdf",
    "text/csv": "csv",
    "application/msword": "doc",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
    "application/vnd.ms-excel": "xls",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
    "text/html": "html",
    "text/plain": "txt",
    "text/markdown": "md"
]

let bedrockImageMimeTypes: [String: String] = [
    "image/jpeg": "jpeg",
    "image/png": "png",
    "image/gif": "gif",
    "image/webp": "webp"
]

var bedrockSupportedDocumentMimeTypes: [String] {
    bedrockDocumentMimeTypes.keys.sorted()
}

var bedrockSupportedImageMimeTypes: [String] {
    bedrockImageMimeTypes.keys.sorted()
}

func bedrockDocumentFormat(for mimeType: String) -> String? {
    bedrockDocumentMimeTypes[mimeType]
}

func bedrockImageFormat(for mimeType: String) -> String? {
    bedrockImageMimeTypes[mimeType]
}

struct BedrockPreparedTools {
    var toolConfig: JSONValue?
    var warnings: [AIWarning]
}

func bedrockRequestProviderOptions(providerOptions: [String: JSONValue], extraBody: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    if let bedrock = extraBody["bedrock"]?.objectValue {
        output.merge(bedrock) { _, new in new }
    }
    if let amazonBedrock = extraBody["amazonBedrock"]?.objectValue {
        output.merge(amazonBedrock) { _, new in new }
    }
    if let bedrock = providerOptions["bedrock"] {
        guard let object = bedrock.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.bedrock", message: "Bedrock provider options must be an object.")
        }
        output.merge(object) { _, new in new }
    }
    if let amazonBedrock = providerOptions["amazonBedrock"] {
        guard let object = amazonBedrock.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.amazonBedrock", message: "Amazon Bedrock provider options must be an object.")
        }
        output.merge(object) { _, new in new }
    }
    return output
}

func bedrockPassthroughExtraBody(_ extraBody: [String: JSONValue]) -> [String: JSONValue] {
    extraBody.filter { key, _ in key != "amazonBedrock" && key != "bedrock" && key != "toolChoice" }
}

func bedrockDocumentCitationsEnabled(_ providerOptions: [String: JSONValue]) -> Bool {
    providerOptions["citations"]?["enabled"]?.boolValue ?? false
}

func bedrockResponseJSONSchema(from responseFormat: AIResponseFormat?) -> JSONValue? {
    guard case let .json(schema, _, _) = responseFormat else { return nil }
    return schema
}

func bedrockReasoningConfigEnabled(_ value: JSONValue?) -> Bool {
    let type = value?["type"]?.stringValue
    return type == "enabled" || type == "adaptive"
}

func bedrockApplyRequestProviderOptions(_ providerOptions: [String: JSONValue], to body: inout [String: JSONValue]) {
    if let guardrailConfig = providerOptions["guardrailConfig"] {
        body["guardrailConfig"] = guardrailConfig
    }
    if let additionalModelRequestFields = providerOptions["additionalModelRequestFields"] {
        body["additionalModelRequestFields"] = additionalModelRequestFields
    }
    if let serviceTier = providerOptions["serviceTier"] {
        if let serviceTierType = serviceTier.stringValue {
            body["serviceTier"] = .object(["type": .string(serviceTierType)])
        } else {
            body["serviceTier"] = serviceTier
        }
    }
}

func bedrockPrepareTools(from tools: [String: JSONValue], toolChoice: JSONValue?, modelID: String) -> BedrockPreparedTools {
    guard !tools.isEmpty else {
        return BedrockPreparedTools(toolConfig: nil, warnings: [])
    }

    let isAnthropicModel = modelID.contains("anthropic.")
    var warnings: [AIWarning] = []
    var bedrockTools: [JSONValue] = []
    let forcedToolName = bedrockForcedToolName(from: toolChoice)

    for (name, schema) in tools {
        if schema["type"]?.stringValue == "provider" {
            let id = schema["id"]?.stringValue ?? name
            if id == "anthropic.web_search_20250305" {
                warnings.append(AIWarning(
                    type: "unsupported",
                    feature: "web_search_20250305 tool",
                    message: "The web_search_20250305 tool is not supported on Amazon Bedrock."
                ))
                continue
            }
            if isAnthropicModel, let anthropicToolSchema = bedrockAnthropicProviderToolInputSchema(schema) {
                bedrockTools.append(.object([
                    "toolSpec": .object([
                        "name": .string(name),
                        "inputSchema": .object(["json": anthropicToolSchema])
                    ])
                ]))
            } else {
                warnings.append(AIWarning(type: "unsupported", feature: "tool \(id)"))
            }
            continue
        }

        if let forcedToolName, forcedToolName != name {
            continue
        }

        var toolSpec: [String: JSONValue] = [
            "name": .string(name),
            "inputSchema": .object(["json": schema])
        ]
        if let description = schema["description"]?.stringValue,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            toolSpec["description"] = .string(description)
        }
        if let strict = schema["strict"] {
            toolSpec["strict"] = strict
        }
        bedrockTools.append(.object(["toolSpec": .object(toolSpec)]))
    }

    guard !bedrockTools.isEmpty else {
        return BedrockPreparedTools(toolConfig: nil, warnings: warnings)
    }

    var toolConfig: [String: JSONValue] = ["tools": .array(bedrockTools)]
    if let choice = bedrockToolChoice(from: toolChoice), !bedrockUsesAnthropicProviderTools(tools: tools, modelID: modelID) {
        if choice == .null {
            return BedrockPreparedTools(toolConfig: nil, warnings: warnings)
        }
        toolConfig["toolChoice"] = choice
    }
    return BedrockPreparedTools(toolConfig: .object(toolConfig), warnings: warnings)
}

func bedrockUsesAnthropicProviderTools(tools: [String: JSONValue], modelID: String) -> Bool {
    modelID.contains("anthropic.") && tools.values.contains { $0["type"]?.stringValue == "provider" }
}

func bedrockForcedToolName(from toolChoice: JSONValue?) -> String? {
    guard toolChoice?["type"]?.stringValue == "tool" else { return nil }
    return toolChoice?["toolName"]?.stringValue ?? toolChoice?["name"]?.stringValue
}

func bedrockToolChoice(from value: JSONValue?) -> JSONValue? {
    guard let value else { return nil }
    if let string = value.stringValue {
        switch string {
        case "auto":
            return .object(["auto": .object([:])])
        case "required":
            return .object(["any": .object([:])])
        case "none":
            return .null
        default:
            return nil
        }
    }
    switch value["type"]?.stringValue {
    case "auto":
        return .object(["auto": .object([:])])
    case "required":
        return .object(["any": .object([:])])
    case "none":
        return .null
    case "tool":
        guard let toolName = value["toolName"]?.stringValue ?? value["name"]?.stringValue else { return nil }
        return .object(["tool": .object(["name": .string(toolName)])])
    default:
        return nil
    }
}

func bedrockAnthropicProviderToolInputSchema(_ tool: JSONValue) -> JSONValue? {
    if let inputSchema = tool["inputSchema"] {
        return inputSchema
    }
    if let parameters = tool["parameters"] {
        return parameters
    }
    return .object(["type": .string("object"), "properties": .object([:])])
}

func bedrockApplyReasoningConfig(
    _ value: JSONValue?,
    modelID: String,
    inferenceConfig: inout [String: JSONValue],
    providerOptions: inout [String: JSONValue],
    warnings: inout [AIWarning]
) {
    guard let value else { return }
    guard let reasoningConfig = value.objectValue else {
        warnings.append(AIWarning(type: "unsupported", feature: "reasoningConfig", message: "Bedrock reasoningConfig must be an object."))
        return
    }

    let type = reasoningConfig["type"]?.stringValue
    let budgetTokens = reasoningConfig["budgetTokens"]?.intValue
    let maxReasoningEffort = reasoningConfig["maxReasoningEffort"]?.stringValue
    let display = reasoningConfig["display"]?.stringValue
    let isAnthropicModel = modelID.contains("anthropic.")
    let isOpenAIModel = modelID.hasPrefix("openai.")
    let isAnthropicThinkingEnabled = isAnthropicModel && (type == "enabled" || type == "adaptive")

    if isAnthropicThinkingEnabled {
        if let budgetTokens, type == "enabled" {
            let existingMaxTokens = inferenceConfig["maxTokens"]?.intValue
            inferenceConfig["maxTokens"] = .number(Double((existingMaxTokens ?? 4096) + budgetTokens))
            bedrockMergeAdditionalModelRequestFields([
                "thinking": .object([
                    "type": .string("enabled"),
                    "budget_tokens": .number(Double(budgetTokens))
                ])
            ], into: &providerOptions)
        } else if type == "adaptive" {
            var thinking: [String: JSONValue] = ["type": .string("adaptive")]
            if let display {
                thinking["display"] = .string(display)
            }
            bedrockMergeAdditionalModelRequestFields(["thinking": .object(thinking)], into: &providerOptions)
        }
        if inferenceConfig.removeValue(forKey: "temperature") != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "temperature", message: "temperature is not supported when thinking is enabled"))
        }
        if inferenceConfig.removeValue(forKey: "topP") != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "topP", message: "topP is not supported when thinking is enabled"))
        }
        if inferenceConfig.removeValue(forKey: "topK") != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "topK", message: "topK is not supported when thinking is enabled"))
        }
    } else if !isAnthropicModel {
        if budgetTokens != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "budgetTokens", message: "budgetTokens applies only to Anthropic models on Bedrock and will be ignored for this model."))
        }
        if type == "adaptive" {
            warnings.append(AIWarning(type: "unsupported", feature: "adaptive thinking", message: "adaptive thinking type applies only to Anthropic models on Bedrock."))
        }
    }

    guard let maxReasoningEffort else { return }
    if isAnthropicModel {
        let existing = providerOptions["additionalModelRequestFields"]?["output_config"]?.objectValue ?? [:]
        bedrockMergeAdditionalModelRequestFields([
            "output_config": .object(existing.merging(["effort": .string(maxReasoningEffort)]) { _, new in new })
        ], into: &providerOptions)
    } else if isOpenAIModel {
        bedrockMergeAdditionalModelRequestFields(["reasoning_effort": .string(maxReasoningEffort)], into: &providerOptions)
    } else {
        var nested: [String: JSONValue] = [:]
        if let type, type != "adaptive" {
            nested["type"] = .string(type)
        }
        if let budgetTokens {
            nested["budgetTokens"] = .number(Double(budgetTokens))
        }
        nested["maxReasoningEffort"] = .string(maxReasoningEffort)
        bedrockMergeAdditionalModelRequestFields(["reasoningConfig": .object(nested)], into: &providerOptions)
    }
}

func bedrockMergeAdditionalModelRequestFields(_ fields: [String: JSONValue], into providerOptions: inout [String: JSONValue]) {
    var existing = providerOptions["additionalModelRequestFields"]?.objectValue ?? [:]
    existing.merge(fields) { old, new in
        if var oldObject = old.objectValue,
           let newObject = new.objectValue {
            oldObject.merge(newObject) { _, nestedNew in nestedNew }
            return .object(oldObject)
        }
        return new
    }
    providerOptions["additionalModelRequestFields"] = .object(existing)
}

func bedrockDeduplicatedWarnings(_ warnings: [AIWarning]) -> [AIWarning] {
    var seen: Set<String> = []
    var output: [AIWarning] = []
    for warning in warnings {
        let key = "\(warning.type)|\(warning.feature ?? "")|\(warning.setting ?? "")|\(warning.message ?? "")"
        if seen.insert(key).inserted {
            output.append(warning)
        }
    }
    return output
}

func bedrockToolCalls(from value: JSONValue?) -> [AIToolCall] {
    value?.arrayValue?.enumerated().compactMap { index, part in
        guard let toolUse = part["toolUse"] else { return nil }
        let name = toolUse["name"]?.stringValue ?? "tool-\(index)"
        return AIToolCall(
            id: toolUse["toolUseId"]?.stringValue ?? "tool-call-\(index)",
            name: name,
            arguments: bedrockToolArguments(toolUse["input"]),
            rawValue: part
        )
    } ?? []
}

func bedrockToolArguments(_ value: JSONValue?) -> String {
    guard let value else { return "{}" }
    guard let data = try? encodeJSONBody(value),
          let text = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return text
}

func bedrockReasoningText(from value: JSONValue?) -> String {
    value?.arrayValue?.compactMap { part in
        part["reasoningContent"]?["reasoningText"]?["text"]?.stringValue
    }.joined() ?? ""
}

func bedrockProviderMetadata(from raw: JSONValue, isJsonResponseFromTool: Bool = false) -> [String: JSONValue] {
    var payload: [String: JSONValue] = [:]
    if let trace = raw["trace"] {
        payload["trace"] = trace
    }
    if let performanceConfig = raw["performanceConfig"] {
        payload["performanceConfig"] = performanceConfig
    }
    if let serviceTier = raw["serviceTier"] {
        payload["serviceTier"] = serviceTier
    }
    if let stopSequence = raw["additionalModelResponseFields"]?["delta"]?["stop_sequence"] {
        payload["stopSequence"] = stopSequence
    }
    var usage: [String: JSONValue] = [:]
    if let cacheWriteInputTokens = raw["usage"]?["cacheWriteInputTokens"] {
        usage["cacheWriteInputTokens"] = cacheWriteInputTokens
    }
    if let cacheDetails = raw["usage"]?["cacheDetails"] {
        usage["cacheDetails"] = cacheDetails
    }
    if !usage.isEmpty {
        payload["usage"] = .object(usage)
    }
    if isJsonResponseFromTool {
        payload["isJsonResponseFromTool"] = .bool(true)
    }
    guard !payload.isEmpty else { return [:] }
    return [
        "amazonBedrock": .object(payload),
        "bedrock": .object(payload)
    ]
}

func bedrockProviderMetadata(fromStreamMetadata raw: JSONValue?) -> [String: JSONValue] {
    guard let raw else { return [:] }
    var payload: [String: JSONValue] = [:]
    if let trace = raw["trace"] {
        payload["trace"] = trace
    }
    if let performanceConfig = raw["performanceConfig"] {
        payload["performanceConfig"] = performanceConfig
    }
    if let serviceTier = raw["serviceTier"] {
        payload["serviceTier"] = serviceTier
    }
    var usage: [String: JSONValue] = [:]
    if let cacheWriteInputTokens = raw["usage"]?["cacheWriteInputTokens"] {
        usage["cacheWriteInputTokens"] = cacheWriteInputTokens
    }
    if let cacheDetails = raw["usage"]?["cacheDetails"] {
        usage["cacheDetails"] = cacheDetails
    }
    if !usage.isEmpty {
        payload["usage"] = .object(usage)
    }
    guard !payload.isEmpty else { return [:] }
    return [
        "amazonBedrock": .object(payload),
        "bedrock": .object(payload)
    ]
}

func bedrockFinishReason(_ reason: String?, isJsonResponseFromTool: Bool = false) -> String? {
    switch reason {
    case "stop_sequence", "end_turn":
        return "stop"
    case "max_tokens":
        return "length"
    case "content_filtered", "guardrail_intervened":
        return "content-filter"
    case "tool_use":
        return isJsonResponseFromTool ? "stop" : "tool-calls"
    case nil:
        return nil
    default:
        return "other"
    }
}

func bedrockUsage(from raw: JSONValue?) -> TokenUsage? {
    guard let raw else { return nil }
    return TokenUsage(
        inputTokens: raw["inputTokens"]?.intValue,
        outputTokens: raw["outputTokens"]?.intValue,
        totalTokens: raw["totalTokens"]?.intValue
    )
}
