import Foundation

struct AnthropicMappedOptions {
    var body: [String: JSONValue]
    var betas: [String]
    var toolChoice: JSONValue?
    var disableParallelToolUse: Bool?
    var toolStreaming: Bool?
    var sendReasoning: Bool?
    var structuredOutputMode: String?
}

struct AnthropicModelCapabilities {
    var maxOutputTokens: Int
    var supportsStructuredOutput: Bool
    var supportsAdaptiveThinking: Bool
    var rejectsSamplingParameters: Bool
    var supportsXhighEffort: Bool
    var isKnownModel: Bool
}

let anthropicLanguageProviderOptionKeys: Set<String> = [
    "sendReasoning",
    "structuredOutputMode",
    "thinking",
    "disableParallelToolUse",
    "cacheControl",
    "metadata",
    "mcpServers",
    "container",
    "toolStreaming",
    "effort",
    "taskBudget",
    "speed",
    "inferenceGeo",
    "fallbacks",
    "anthropicBeta",
    "contextManagement"
]

func anthropicOptions(from request: LanguageModelRequest, providerID: String) throws -> AnthropicMappedOptions {
    var output = anthropicOptions(from: request.extraBody)
    var betas: [String] = []
    var toolChoice = output.removeValue(forKey: "tool_choice")
    var disableParallelToolUse = request.extraBody["disableParallelToolUse"]?.boolValue
    var toolStreaming = request.extraBody["toolStreaming"]?.boolValue
    var sendReasoning = request.extraBody["sendReasoning"]?.boolValue ?? true
    var structuredOutputMode = request.extraBody["structuredOutputMode"]?.stringValue

    if let value = request.providerOptions["anthropic"] {
        guard value != .null else {
            return AnthropicMappedOptions(body: output, betas: betas, toolChoice: toolChoice, disableParallelToolUse: disableParallelToolUse, toolStreaming: toolStreaming, sendReasoning: sendReasoning, structuredOutputMode: structuredOutputMode)
        }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.anthropic", message: "Anthropic provider options must be an object.")
        }
        let typed = try anthropicTypedOptions(from: nested, argumentPrefix: "providerOptions.anthropic")
        output.merge(typed.body) { _, typed in typed }
        betas.append(contentsOf: typed.betas)
        toolChoice = typed.toolChoice ?? toolChoice
        disableParallelToolUse = typed.disableParallelToolUse ?? disableParallelToolUse
        toolStreaming = typed.toolStreaming ?? toolStreaming
        sendReasoning = typed.sendReasoning ?? sendReasoning
        structuredOutputMode = typed.structuredOutputMode ?? structuredOutputMode
    }

    let providerOptionsName = anthropicProviderOptionsName(from: providerID)
    if providerOptionsName != "anthropic", let value = request.providerOptions[providerOptionsName] {
        guard value != .null else {
            return AnthropicMappedOptions(body: output, betas: betas, toolChoice: toolChoice, disableParallelToolUse: disableParallelToolUse, toolStreaming: toolStreaming, sendReasoning: sendReasoning, structuredOutputMode: structuredOutputMode)
        }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.\(providerOptionsName)", message: "Anthropic provider options must be an object.")
        }
        let typed = try anthropicTypedOptions(from: nested, argumentPrefix: "providerOptions.\(providerOptionsName)")
        output.merge(typed.body) { _, typed in typed }
        betas.append(contentsOf: typed.betas)
        toolChoice = typed.toolChoice ?? toolChoice
        disableParallelToolUse = typed.disableParallelToolUse ?? disableParallelToolUse
        toolStreaming = typed.toolStreaming ?? toolStreaming
        sendReasoning = typed.sendReasoning ?? sendReasoning
        structuredOutputMode = typed.structuredOutputMode ?? structuredOutputMode
    }

    if let betaValue = request.extraBody["anthropicBeta"] {
        betas.append(contentsOf: try anthropicBetaValues(betaValue, argument: "extraBody.anthropicBeta"))
    }
    betas.append(contentsOf: anthropicAutomaticBetas(from: output))

    return AnthropicMappedOptions(body: output, betas: betas, toolChoice: toolChoice, disableParallelToolUse: disableParallelToolUse, toolStreaming: toolStreaming, sendReasoning: sendReasoning, structuredOutputMode: structuredOutputMode)
}

func anthropicTypedOptions(from options: [String: JSONValue], argumentPrefix: String) throws -> AnthropicMappedOptions {
    let knownOptions = options.filter { anthropicLanguageProviderOptionKeys.contains($0.key) }
    var body = anthropicOptions(from: knownOptions)
    body.removeValue(forKey: "anthropicBeta")
    let toolChoice = body.removeValue(forKey: "tool_choice")
    let disableParallelToolUse = options["disableParallelToolUse"]?.boolValue
    let toolStreaming = options["toolStreaming"]?.boolValue
    let sendReasoning = options["sendReasoning"]?.boolValue
    let structuredOutputMode = options["structuredOutputMode"]?.stringValue
    let betas = try anthropicBetaValues(options["anthropicBeta"], argument: "\(argumentPrefix).anthropicBeta")
    return AnthropicMappedOptions(body: body, betas: betas, toolChoice: toolChoice, disableParallelToolUse: disableParallelToolUse, toolStreaming: toolStreaming, sendReasoning: sendReasoning, structuredOutputMode: structuredOutputMode)
}

func anthropicProviderOptionsName(from providerID: String) -> String {
    String(providerID.split(separator: ".", maxSplits: 1).first.map(String.init) ?? providerID)
}

func anthropicBetaValues(_ value: JSONValue?, argument: String) throws -> [String] {
    guard let value, value != .null else { return [] }
    guard let values = value.arrayValue else {
        throw AIError.invalidArgument(argument: argument, message: "Anthropic anthropicBeta must be an array of strings.")
    }
    return try values.enumerated().map { index, value in
        guard let string = value.stringValue else {
            throw AIError.invalidArgument(argument: "\(argument)[\(index)]", message: "Anthropic anthropicBeta values must be strings.")
        }
        return string
    }
}

func anthropicAutomaticBetas(from body: [String: JSONValue]) -> [String] {
    var betas: [String] = []

    func add(_ beta: String) {
        if !betas.contains(beta) {
            betas.append(beta)
        }
    }

    if body["mcp_servers"]?.arrayValue?.isEmpty == false {
        add("mcp-client-2025-04-04")
    }

    if let contextManagement = body["context_management"]?.objectValue {
        add("context-management-2025-06-27")
        if contextManagement["edits"]?.arrayValue?.contains(where: { edit in
            edit["type"]?.stringValue == "compact_20260112"
        }) == true {
            add("compact-2026-01-12")
        }
    }

    if body["container"]?["skills"]?.arrayValue?.isEmpty == false {
        add("code-execution-2025-08-25")
        add("skills-2025-10-02")
        add("files-api-2025-04-14")
    }

    if body["output_config"]?["task_budget"] != nil {
        add("task-budgets-2026-03-13")
    }

    if body["speed"]?.stringValue == "fast" {
        add("fast-mode-2026-02-01")
    }
    if body["fallbacks"]?.arrayValue?.isEmpty == false {
        add("server-side-fallback-2026-06-01")
    }

    return betas
}

func anthropicOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    anthropicMoveKey("topK", to: "top_k", in: &output)
    anthropicMoveKey("cacheControl", to: "cache_control", in: &output)
    anthropicMoveKey("inferenceGeo", to: "inference_geo", in: &output)
    anthropicMoveKey("toolChoice", to: "tool_choice", in: &output)

    if let thinking = output.removeValue(forKey: "thinking") {
        output["thinking"] = anthropicThinking(thinking)
    }
    if let metadata = output.removeValue(forKey: "metadata") {
        output["metadata"] = anthropicMetadata(metadata)
    }
    if let contextManagement = output.removeValue(forKey: "contextManagement") {
        output["context_management"] = anthropicContextManagement(contextManagement)
    }
    if let mcpServers = output.removeValue(forKey: "mcpServers") {
        output["mcp_servers"] = anthropicMCPServers(mcpServers)
    }
    if let container = output.removeValue(forKey: "container") {
        output["container"] = anthropicContainer(container)
    }

    var outputConfig: [String: JSONValue] = output.removeValue(forKey: "output_config")?.objectValue ?? [:]
    if let effort = output.removeValue(forKey: "effort") {
        outputConfig["effort"] = effort
    }
    if let taskBudget = output.removeValue(forKey: "taskBudget") {
        outputConfig["task_budget"] = anthropicTaskBudget(taskBudget)
    }
    if !outputConfig.isEmpty {
        output["output_config"] = .object(outputConfig)
    }

    output.removeValue(forKey: "sendReasoning")
    output.removeValue(forKey: "structuredOutputMode")
    output.removeValue(forKey: "responseFormat")
    output.removeValue(forKey: "disableParallelToolUse")
    output.removeValue(forKey: "toolStreaming")
    output.removeValue(forKey: "anthropicBeta")
    return output
}

func anthropicThinking(_ value: JSONValue) -> JSONValue {
    guard var object = value.objectValue else { return value }
    anthropicMoveKey("budgetTokens", to: "budget_tokens", in: &object)
    return .object(object)
}

func anthropicMetadata(_ value: JSONValue) -> JSONValue {
    guard var object = value.objectValue else { return value }
    anthropicMoveKey("userId", to: "user_id", in: &object)
    return .object(object)
}

func anthropicTaskBudget(_ value: JSONValue) -> JSONValue {
    guard var object = value.objectValue else { return value }
    anthropicMoveKey("remainingTokens", to: "remaining", in: &object)
    return .object(object)
}

func anthropicContextManagement(_ value: JSONValue) -> JSONValue {
    guard var object = value.objectValue else { return value }
    if let edits = object["edits"]?.arrayValue {
        object["edits"] = .array(edits.map { edit in
            guard var editObject = edit.objectValue else { return edit }
            anthropicMoveKey("clearAtLeast", to: "clear_at_least", in: &editObject)
            anthropicMoveKey("clearToolInputs", to: "clear_tool_inputs", in: &editObject)
            anthropicMoveKey("excludeTools", to: "exclude_tools", in: &editObject)
            anthropicMoveKey("pauseAfterCompaction", to: "pause_after_compaction", in: &editObject)
            return .object(editObject)
        })
    }
    return .object(object)
}

func anthropicMCPServers(_ value: JSONValue) -> JSONValue {
    guard let servers = value.arrayValue else { return value }
    return .array(servers.map { server in
        guard var object = server.objectValue else { return server }
        anthropicMoveKey("authorizationToken", to: "authorization_token", in: &object)
        if let configuration = object.removeValue(forKey: "toolConfiguration") {
            var mapped = configuration.objectValue ?? [:]
            anthropicMoveKey("allowedTools", to: "allowed_tools", in: &mapped)
            object["tool_configuration"] = .object(mapped)
        }
        return .object(object)
    })
}

func anthropicContainer(_ value: JSONValue) -> JSONValue {
    guard var object = value.objectValue else { return value }
    if let skills = object["skills"]?.arrayValue, !skills.isEmpty {
        object["skills"] = .array(skills.map { skill in
            guard var skillObject = skill.objectValue else { return skill }
            anthropicMoveKey("skillId", to: "skill_id", in: &skillObject)
            return .object(skillObject)
        })
        return .object(object)
    }
    if let id = object["id"] {
        return id
    }
    return .object(object)
}

func anthropicStandardWarnings(for request: LanguageModelRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.frequencyPenalty != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "frequencyPenalty"))
    }
    if request.presencePenalty != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "presencePenalty"))
    }
    if request.seed != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "seed"))
    }
    return warnings
}

func anthropicModelCapabilities(_ modelID: String) -> AnthropicModelCapabilities {
    if modelID.contains("claude-opus-4-8") ||
        modelID.contains("claude-opus-4-7") ||
        modelID.contains("claude-fable-5") ||
        modelID.contains("claude-sonnet-5") {
        return AnthropicModelCapabilities(
            maxOutputTokens: 128_000,
            supportsStructuredOutput: true,
            supportsAdaptiveThinking: true,
            rejectsSamplingParameters: true,
            supportsXhighEffort: true,
            isKnownModel: true
        )
    }
    if modelID.contains("claude-sonnet-4-6") ||
        modelID.contains("claude-opus-4-6") {
        return AnthropicModelCapabilities(
            maxOutputTokens: 128_000,
            supportsStructuredOutput: true,
            supportsAdaptiveThinking: true,
            rejectsSamplingParameters: false,
            supportsXhighEffort: false,
            isKnownModel: true
        )
    }
    if modelID.contains("claude-sonnet-4-5") ||
        modelID.contains("claude-opus-4-5") ||
        modelID.contains("claude-haiku-4-5") {
        return AnthropicModelCapabilities(
            maxOutputTokens: 64_000,
            supportsStructuredOutput: true,
            supportsAdaptiveThinking: false,
            rejectsSamplingParameters: false,
            supportsXhighEffort: false,
            isKnownModel: true
        )
    }
    if modelID.contains("claude-opus-4-1") {
        return AnthropicModelCapabilities(
            maxOutputTokens: 32_000,
            supportsStructuredOutput: true,
            supportsAdaptiveThinking: false,
            rejectsSamplingParameters: false,
            supportsXhighEffort: false,
            isKnownModel: true
        )
    }
    if modelID.contains("claude-sonnet-4-") {
        return AnthropicModelCapabilities(
            maxOutputTokens: 64_000,
            supportsStructuredOutput: false,
            supportsAdaptiveThinking: false,
            rejectsSamplingParameters: false,
            supportsXhighEffort: false,
            isKnownModel: true
        )
    }
    if modelID.contains("claude-opus-4-") {
        return AnthropicModelCapabilities(
            maxOutputTokens: 32_000,
            supportsStructuredOutput: false,
            supportsAdaptiveThinking: false,
            rejectsSamplingParameters: false,
            supportsXhighEffort: false,
            isKnownModel: true
        )
    }
    if modelID.contains("claude-3-haiku") {
        return AnthropicModelCapabilities(
            maxOutputTokens: 4_096,
            supportsStructuredOutput: false,
            supportsAdaptiveThinking: false,
            rejectsSamplingParameters: false,
            supportsXhighEffort: false,
            isKnownModel: true
        )
    }
    return AnthropicModelCapabilities(
        maxOutputTokens: 4_096,
        supportsStructuredOutput: false,
        supportsAdaptiveThinking: false,
        rejectsSamplingParameters: false,
        supportsXhighEffort: false,
        isKnownModel: false
    )
}

func anthropicSamplingParameters(
    for request: LanguageModelRequest,
    modelID: String,
    capabilities: AnthropicModelCapabilities,
    warnings: inout [AIWarning]
) -> (temperature: Double?, topK: Int?, topP: Double?) {
    if capabilities.rejectsSamplingParameters {
        if request.temperature != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "temperature",
                message: "temperature is not supported by \(modelID) and will be ignored"
            ))
        }
        if request.topK != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "topK",
                message: "topK is not supported by \(modelID) and will be ignored"
            ))
        }
        if request.topP != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "topP",
                message: "topP is not supported by \(modelID) and will be ignored"
            ))
        }
        return (nil, nil, nil)
    }

    return (
        anthropicClampedTemperature(request.temperature, warnings: &warnings),
        request.topK,
        request.topP
    )
}

func anthropicClampedTemperature(_ temperature: Double?, warnings: inout [AIWarning]) -> Double? {
    guard let temperature else { return nil }
    if temperature > 1 {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "temperature",
            message: "\(temperature) exceeds anthropic maximum of 1.0. clamped to 1.0"
        ))
        return 1
    }
    if temperature < 0 {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "temperature",
            message: "\(temperature) is below anthropic minimum of 0. clamped to 0"
        ))
        return 0
    }
    return temperature
}

func anthropicApplyTopLevelReasoning(
    _ reasoning: String?,
    to body: inout [String: JSONValue],
    capabilities: AnthropicModelCapabilities,
    warnings: inout [AIWarning]
) {
    guard let reasoning, reasoning != "provider-default" else { return }
    guard body["output_config"]?["effort"] == nil else { return }

    let config = anthropicReasoningConfig(
        reasoning,
        capabilities: capabilities,
        warnings: &warnings
    )
    guard let config else { return }

    if body["thinking"] == nil {
        body["thinking"] = config.thinking
    }
    if let effort = config.effort,
       body["thinking"]?["type"]?.stringValue != "disabled" {
        var outputConfig = body["output_config"]?.objectValue ?? [:]
        outputConfig["effort"] = .string(effort)
        body["output_config"] = .object(outputConfig)
    }
}

func anthropicReasoningConfig(
    _ reasoning: String,
    capabilities: AnthropicModelCapabilities,
    warnings: inout [AIWarning]
) -> (thinking: JSONValue, effort: String?)? {
    if reasoning == "none" {
        return (["type": "disabled"], nil)
    }

    if capabilities.supportsAdaptiveThinking {
        let effortMap: [String: String] = [
            "minimal": "low",
            "low": "low",
            "medium": "medium",
            "high": "high",
            "xhigh": capabilities.supportsXhighEffort ? "xhigh" : "max"
        ]
        guard let effort = effortMap[reasoning] else {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "reasoning",
                message: "reasoning \"\(reasoning)\" is not supported by this model."
            ))
            return nil
        }
        if effort != reasoning {
            warnings.append(AIWarning(
                type: "compatibility",
                feature: "reasoning",
                message: "reasoning \"\(reasoning)\" is not directly supported by this model. mapped to effort \"\(effort)\"."
            ))
        }
        return (["type": "adaptive"], effort)
    }

    let percentages: [String: Double] = [
        "minimal": 0.02,
        "low": 0.1,
        "medium": 0.3,
        "high": 0.6,
        "xhigh": 0.9
    ]
    guard let percentage = percentages[reasoning] else {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "reasoning",
            message: "reasoning \"\(reasoning)\" is not supported by this model."
        ))
        return nil
    }
    let budget = min(
        capabilities.maxOutputTokens,
        max(1_024, Int((Double(capabilities.maxOutputTokens) * percentage).rounded()))
    )
    return (["type": "enabled", "budget_tokens": .number(Double(budget))], nil)
}

func anthropicApplyMaxTokenLimit(
    to body: inout [String: JSONValue],
    modelID: String,
    requestedMaxTokens: Int?,
    capabilities: AnthropicModelCapabilities,
    warnings: inout [AIWarning]
) {
    guard capabilities.isKnownModel,
          let maxTokens = body["max_tokens"]?.intValue,
          maxTokens > capabilities.maxOutputTokens else {
        return
    }

    if requestedMaxTokens != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "maxOutputTokens",
            message: "\(maxTokens) (maxOutputTokens + thinkingBudget) is greater than \(modelID) \(capabilities.maxOutputTokens) max output tokens. The max output tokens have been limited to \(capabilities.maxOutputTokens)."
        ))
    }
    body["max_tokens"] = .number(Double(capabilities.maxOutputTokens))
}

func anthropicApplyResponseFormat(
    _ responseFormat: AIResponseFormat?,
    to body: inout [String: JSONValue],
    supportsStructuredOutput: Bool,
    structuredOutputMode: String?,
    eagerInputStreaming: Bool,
    warnings: inout [AIWarning]
) -> Bool {
    guard let responseFormat else { return false }
    switch responseFormat {
    case .text:
        return false
    case let .json(schema, _, _):
        guard let schema else {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "responseFormat",
                message: "JSON response format requires a schema. The response format is ignored."
            ))
            return false
        }
        let useNativeOutputFormat = structuredOutputMode == "outputFormat"
            || (structuredOutputMode != "jsonTool" && supportsStructuredOutput)
        guard useNativeOutputFormat else {
            var tools = body["tools"]?.arrayValue ?? []
            tools.append(.object([
                "name": .string("json"),
                "description": .string("Respond with a JSON object."),
                "eager_input_streaming": .bool(eagerInputStreaming),
                "input_schema": schema
            ].filter { key, _ in key != "eager_input_streaming" || eagerInputStreaming }))
            body["tools"] = .array(tools)
            body["tool_choice"] = .object([
                "type": .string("any"),
                "disable_parallel_tool_use": true
            ])
            return true
        }
        var outputConfig = body["output_config"]?.objectValue ?? [:]
        outputConfig["format"] = .object([
            "type": .string("json_schema"),
            "schema": anthropicSanitizeJSONSchema(schema)
        ])
        body["output_config"] = .object(outputConfig)
        return false
    }
}

func anthropicSanitizeJSONSchema(_ schema: JSONValue) -> JSONValue {
    guard let object = schema.objectValue else {
        return schema
    }
    if let ref = object["$ref"] {
        return .object(["$ref": ref])
    }

    var result: [String: JSONValue] = [:]
    for key in ["$schema", "$id", "title", "description", "default", "const", "enum", "type"] {
        if let value = object[key] {
            result[key] = value
        }
    }

    if let anyOf = object["anyOf"]?.arrayValue {
        result["anyOf"] = .array(anyOf.map(anthropicSanitizeJSONSchemaDefinition))
    } else if let oneOf = object["oneOf"]?.arrayValue {
        result["anyOf"] = .array(oneOf.map(anthropicSanitizeJSONSchemaDefinition))
    }
    if let allOf = object["allOf"]?.arrayValue {
        result["allOf"] = .array(allOf.map(anthropicSanitizeJSONSchemaDefinition))
    }
    if let definitions = object["definitions"]?.objectValue {
        result["definitions"] = .object(definitions.mapValues(anthropicSanitizeJSONSchemaDefinition))
    }
    if let definitions = object["$defs"]?.objectValue {
        result["$defs"] = .object(definitions.mapValues(anthropicSanitizeJSONSchemaDefinition))
    }

    if object["type"]?.stringValue == "object" || object["properties"] != nil {
        if let properties = object["properties"]?.objectValue {
            result["properties"] = .object(properties.mapValues(anthropicSanitizeJSONSchemaDefinition))
        }
        result["additionalProperties"] = .bool(false)
        if let required = object["required"] {
            result["required"] = required
        }
    }

    if let items = object["items"] {
        if let tupleItems = items.arrayValue {
            result["items"] = .array(tupleItems.map(anthropicSanitizeJSONSchemaDefinition))
        } else {
            result["items"] = anthropicSanitizeJSONSchemaDefinition(items)
        }
    }

    if let format = object["format"]?.stringValue, anthropicSupportedStringFormats.contains(format) {
        result["format"] = .string(format)
    }

    if let constraintDescription = anthropicConstraintDescription(from: object) {
        if let description = result["description"]?.stringValue {
            result["description"] = .string("\(description)\n\(constraintDescription)")
        } else {
            result["description"] = .string(constraintDescription)
        }
    }

    return .object(result)
}

private func anthropicSanitizeJSONSchemaDefinition(_ definition: JSONValue) -> JSONValue {
    switch definition {
    case .object:
        return anthropicSanitizeJSONSchema(definition)
    case .bool:
        return definition
    default:
        return definition
    }
}

private let anthropicSupportedStringFormats: Set<String> = [
    "date-time",
    "time",
    "date",
    "duration",
    "email",
    "hostname",
    "uri",
    "ipv4",
    "ipv6",
    "uuid"
]

private let anthropicDescriptionConstraintKeys = [
    "minimum",
    "maximum",
    "exclusiveMinimum",
    "exclusiveMaximum",
    "multipleOf",
    "minLength",
    "maxLength",
    "pattern",
    "minItems",
    "maxItems",
    "uniqueItems",
    "minProperties",
    "maxProperties",
    "not"
]

private func anthropicConstraintDescription(from object: [String: JSONValue]) -> String? {
    var descriptions: [String] = []
    for key in anthropicDescriptionConstraintKeys {
        guard let value = object[key], value != .null, value != .bool(false) else { continue }
        descriptions.append("\(anthropicConstraintName(key)): \(anthropicConstraintValue(value))")
    }
    if let format = object["format"]?.stringValue, !anthropicSupportedStringFormats.contains(format) {
        descriptions.append("format: \(format)")
    }
    guard !descriptions.isEmpty else { return nil }
    return "\(descriptions.joined(separator: "; "))."
}

private func anthropicConstraintName(_ key: String) -> String {
    var output = ""
    for character in key {
        if character.isUppercase {
            output.append(" ")
            output.append(character.lowercased())
        } else {
            output.append(character)
        }
    }
    return output
}

private func anthropicConstraintValue(_ value: JSONValue) -> String {
    if let string = value.stringValue {
        return string
    }
    return String(data: (try? JSONEncoder().encode(value)) ?? Data("null".utf8), encoding: .utf8) ?? "null"
}

func applyAnthropicThinkingRules(
    to body: inout [String: JSONValue],
    requestedMaxTokens: Int?,
    requestTemperature: Double?,
    requestTopP: Double?,
    isAnthropicModel: Bool,
    warnings: inout [AIWarning]
) {
    guard var thinking = body["thinking"]?.objectValue,
          let type = thinking["type"]?.stringValue,
          type == "enabled" || type == "adaptive" else {
        if isAnthropicModel, requestTemperature != nil, requestTopP != nil {
            body["top_p"] = nil
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "topP",
                message: "topP is not supported when temperature is set. topP is ignored."
            ))
        }
        return
    }

    if type == "enabled", thinking["budget_tokens"] == nil {
        thinking["budget_tokens"] = 1024
        body["thinking"] = .object(thinking)
        warnings.append(AIWarning(
            type: "compatibility",
            feature: "extended thinking",
            message: "thinking budget is required when thinking is enabled. using default budget of 1024 tokens."
        ))
    }

    if body["temperature"] != nil {
        body["temperature"] = nil
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "temperature",
            message: "temperature is not supported when thinking is enabled"
        ))
    }
    if body["top_k"] != nil {
        body["top_k"] = nil
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "topK",
            message: "topK is not supported when thinking is enabled"
        ))
    }
    if body["top_p"] != nil {
        body["top_p"] = nil
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "topP",
            message: "topP is not supported when thinking is enabled"
        ))
    }

    if type == "enabled" {
        let budget = thinking["budget_tokens"]?.intValue ?? 1024
        body["max_tokens"] = .number(Double((requestedMaxTokens ?? 1024) + budget))
    }
}

func anthropicContainerHasSkills(_ body: [String: JSONValue]) -> Bool {
    body["container"]?["skills"]?.arrayValue?.isEmpty == false
}

func anthropicMoveKey(_ source: String, to destination: String, in values: inout [String: JSONValue]) {
    if let value = values.removeValue(forKey: source) {
        values[destination] = value
    }
}

extension JSONValue {
    var arrayValue: [JSONValue]? {
        if case let .array(value) = self { value } else { nil }
    }
}
