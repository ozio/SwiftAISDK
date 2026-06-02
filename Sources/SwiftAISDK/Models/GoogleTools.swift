import Foundation

public enum GoogleTools {
    public static func googleSearch(searchTypes: JSONValue? = nil, timeRangeFilter: JSONValue? = nil) -> JSONValue {
        providerTool(id: "google.google_search", name: "google_search", args: JSONValue.object([
            "searchTypes": searchTypes,
            "timeRangeFilter": timeRangeFilter
        ]).objectValue ?? [:])
    }

    public static func enterpriseWebSearch() -> JSONValue {
        providerTool(id: "google.enterprise_web_search", name: "enterprise_web_search")
    }

    public static func googleMaps() -> JSONValue {
        providerTool(id: "google.google_maps", name: "google_maps")
    }

    public static func urlContext() -> JSONValue {
        providerTool(id: "google.url_context", name: "url_context")
    }

    public static func fileSearch(fileSearchStoreNames: [String], metadataFilter: String? = nil, topK: Int? = nil) -> JSONValue {
        providerTool(id: "google.file_search", name: "file_search", args: JSONValue.object([
            "fileSearchStoreNames": .array(fileSearchStoreNames),
            "metadataFilter": metadataFilter.map(JSONValue.string),
            "topK": topK.map { .number(Double($0)) }
        ]).objectValue ?? [:])
    }

    public static func codeExecution() -> JSONValue {
        providerTool(id: "google.code_execution", name: "code_execution")
    }

    public static func vertexRagStore(ragCorpus: String, topK: Int? = nil) -> JSONValue {
        providerTool(id: "google.vertex_rag_store", name: "vertex_rag_store", args: JSONValue.object([
            "ragCorpus": .string(ragCorpus),
            "topK": topK.map { .number(Double($0)) }
        ]).objectValue ?? [:])
    }

    static func providerTool(id: String, name: String, args: [String: JSONValue] = [:]) -> JSONValue {
        .object([
            "type": .string("provider"),
            "id": .string(id),
            "name": .string(name),
            "args": .object(args)
        ])
    }
}

public enum GoogleVertexTools {
    public static func googleSearch(searchTypes: JSONValue? = nil, timeRangeFilter: JSONValue? = nil) -> JSONValue {
        GoogleTools.googleSearch(searchTypes: searchTypes, timeRangeFilter: timeRangeFilter)
    }

    public static func enterpriseWebSearch() -> JSONValue {
        GoogleTools.enterpriseWebSearch()
    }

    public static func googleMaps() -> JSONValue {
        GoogleTools.googleMaps()
    }

    public static func urlContext() -> JSONValue {
        GoogleTools.urlContext()
    }

    public static func fileSearch(fileSearchStoreNames: [String], metadataFilter: String? = nil, topK: Int? = nil) -> JSONValue {
        GoogleTools.fileSearch(fileSearchStoreNames: fileSearchStoreNames, metadataFilter: metadataFilter, topK: topK)
    }

    public static func codeExecution() -> JSONValue {
        GoogleTools.codeExecution()
    }

    public static func vertexRagStore(ragCorpus: String, topK: Int? = nil) -> JSONValue {
        GoogleTools.vertexRagStore(ragCorpus: ragCorpus, topK: topK)
    }
}

struct GooglePreparedTools {
    var tools: [JSONValue]
    var toolConfig: JSONValue?
    var warnings: [AIWarning] = []
}

struct GooglePreparedGenerateContentOptions {
    var options: [String: JSONValue]
    var warnings: [AIWarning]
    var headers: [String: String]
}

private struct GooglePreparedProviderTool {
    var tool: JSONValue?
    var warnings: [AIWarning] = []
}

func googlePrepareTools(
    from tools: [String: JSONValue],
    toolChoice: JSONValue?,
    modelID: String,
    isVertexProvider: Bool
) -> GooglePreparedTools? {
    guard !tools.isEmpty else { return nil }

    var warnings: [AIWarning] = []
    let providerResults = tools.compactMap { name, schema -> GooglePreparedProviderTool? in
        let object = schema.objectValue
        let id = object?["id"]?.stringValue ?? name
        let isProviderTool = object?["type"]?.stringValue == "provider" || id.hasPrefix("google.")
        guard isProviderTool else { return nil }
        return googleProviderTool(name: name, schema: schema, modelID: modelID)
    }
    let providerTools = providerResults.compactMap(\.tool)
    warnings.append(contentsOf: providerResults.flatMap(\.warnings))
    let functionDeclarations = googleFunctionDeclarations(from: tools)
    let hasFunctionTools = !functionDeclarations.isEmpty
    let hasProviderTools = !providerTools.isEmpty || tools.values.contains { schema in
        guard let object = schema.objectValue else { return false }
        return object["type"]?.stringValue == "provider" || object["id"]?.stringValue?.hasPrefix("google.") == true
    }

    if hasFunctionTools, hasProviderTools, !googleIsGemini3OrNewer(modelID) {
        warnings.append(AIWarning(type: "unsupported", feature: "combination of function and provider-defined tools"))
    }
    if !isVertexProvider, tools.values.contains(where: { schema in
        let object = schema.objectValue
        return (object?["id"]?.stringValue ?? "") == "google.vertex_rag_store"
    }) {
        warnings.append(AIWarning(
            type: "other",
            message: "The 'vertex_rag_store' tool is only supported with the Google Vertex provider and might not be supported or could behave unexpectedly with the current Google provider."
        ))
    }

    if hasProviderTools {
        if hasFunctionTools, googleIsGemini3OrNewer(modelID), !providerTools.isEmpty {
            var prepared = providerTools
            prepared.append(.object(["functionDeclarations": .array(functionDeclarations)]))
            var config = googleToolConfig(from: toolChoice, hasStrictTools: googleHasStrictTools(tools), defaultMode: "VALIDATED")
                ?? .object(["functionCallingConfig": .object(["mode": .string("VALIDATED")])])
            if !isVertexProvider, var object = config.objectValue {
                object["includeServerSideToolInvocations"] = true
                config = .object(object)
            }
            return GooglePreparedTools(tools: prepared, toolConfig: config, warnings: warnings)
        }
        return GooglePreparedTools(tools: providerTools, toolConfig: nil, warnings: warnings)
    }

    guard hasFunctionTools else { return nil }
    return GooglePreparedTools(
        tools: [.object(["functionDeclarations": .array(functionDeclarations)])],
        toolConfig: googleToolConfig(from: toolChoice, hasStrictTools: googleHasStrictTools(tools), defaultMode: nil),
        warnings: warnings
    )
}

func googleExtraBodyWithoutToolChoice(_ extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    for key in [
        "toolChoice",
        "responseFormat",
        "structuredOutputs",
        "google",
        "googleVertex",
        "vertex",
        "responseModalities",
        "thinkingConfig",
        "mediaResolution",
        "imageConfig",
        "audioTimestamp",
        "safetySettings",
        "cachedContent",
        "labels",
        "serviceTier",
        "sharedRequestType",
        "requestType",
        "streamFunctionCallArguments",
        "retrievalConfig"
    ] {
        output.removeValue(forKey: key)
    }
    return output
}

func googleGenerateContentOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "google")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

func googlePrepareGenerateContentOptions(
    from request: LanguageModelRequest,
    modelID: String,
    providerID: String,
    isVertexProvider: Bool
) -> GooglePreparedGenerateContentOptions {
    var options = googleGenerateContentOptions(from: request.extraBody)
    let providerOptionsNames = isVertexProvider ? ["googleVertex", "vertex", "google"] : ["google"]
    for name in providerOptionsNames {
        guard let providerOptions = request.providerOptions[name]?.objectValue else { continue }
        options.merge(providerOptions.filter { googleKnownLanguageProviderOptionKeys.contains($0.key) }) { _, providerValue in providerValue }
        break
    }

    var warnings: [AIWarning] = []
    var headers: [String: String] = [:]

    if options["streamFunctionCallArguments"]?.boolValue == true, !isVertexProvider {
        warnings.append(AIWarning(
            type: "other",
            message: "'streamFunctionCallArguments' is only supported on the Vertex AI API and will be ignored with the current Google provider (\(providerID)). See https://docs.cloud.google.com/vertex-ai/generative-ai/docs/multimodal/function-calling#streaming-fc"
        ))
    }
    if options["serviceTier"] != nil, isVertexProvider {
        warnings.append(AIWarning(
            type: "other",
            message: "'serviceTier' is a Gemini API option and is not supported on Vertex AI. Use 'sharedRequestType' (and optionally 'requestType') instead. See https://docs.cloud.google.com/vertex-ai/generative-ai/docs/priority-paygo"
        ))
    }
    if (options["sharedRequestType"] != nil || options["requestType"] != nil), !isVertexProvider {
        warnings.append(AIWarning(
            type: "other",
            message: "'sharedRequestType' and 'requestType' are Vertex AI options and are ignored with the current Google provider (\(providerID))."
        ))
    }

    if isVertexProvider {
        if let sharedRequestType = options["sharedRequestType"]?.stringValue {
            headers["X-Vertex-AI-LLM-Shared-Request-Type"] = sharedRequestType
        }
        if let requestType = options["requestType"]?.stringValue {
            headers["X-Vertex-AI-LLM-Request-Type"] = requestType
        }
    }

    let thinkingConfig = googleThinkingConfig(for: request.reasoning, modelID: modelID, warnings: &warnings)
    if var thinkingConfig {
        if let providerThinkingConfig = options["thinkingConfig"]?.objectValue {
            thinkingConfig.merge(providerThinkingConfig) { _, providerValue in providerValue }
        }
        options["thinkingConfig"] = .object(thinkingConfig)
    }

    if isVertexProvider {
        options.removeValue(forKey: "serviceTier")
    }
    options.removeValue(forKey: "sharedRequestType")
    options.removeValue(forKey: "requestType")

    return GooglePreparedGenerateContentOptions(options: options, warnings: warnings, headers: headers)
}

func googleResolvedResponseFormat(request: LanguageModelRequest, options: inout [String: JSONValue]) -> JSONValue? {
    if let responseFormat = request.responseFormat {
        options.removeValue(forKey: "responseFormat")
        return googleResponseFormatJSON(responseFormat)
    }
    return options.removeValue(forKey: "responseFormat")
}

func googleApplyResponseFormat(_ responseFormat: JSONValue?, options: [String: JSONValue], to generationConfig: inout [String: JSONValue]) {
    guard responseFormat?["type"]?.stringValue == "json" else { return }
    generationConfig["responseMimeType"] = .string("application/json")
    guard options["structuredOutputs"]?.boolValue != false,
          let schema = responseFormat?["schema"],
          let openAPISchema = googleOpenAPISchema(from: schema, isRoot: true) else {
        return
    }
    generationConfig["responseSchema"] = openAPISchema
}

func googleApplyStandardGenerationSettings(_ request: LanguageModelRequest, to generationConfig: inout [String: JSONValue]) {
    if let temperature = request.temperature { generationConfig["temperature"] = .number(temperature) }
    if let topP = request.topP { generationConfig["topP"] = .number(topP) }
    if let topK = request.topK { generationConfig["topK"] = .number(Double(topK)) }
    if let frequencyPenalty = request.frequencyPenalty { generationConfig["frequencyPenalty"] = .number(frequencyPenalty) }
    if let presencePenalty = request.presencePenalty { generationConfig["presencePenalty"] = .number(presencePenalty) }
    if let seed = request.seed { generationConfig["seed"] = .number(Double(seed)) }
    if let maxOutputTokens = request.maxOutputTokens { generationConfig["maxOutputTokens"] = .number(Double(maxOutputTokens)) }
    if !request.stopSequences.isEmpty { generationConfig["stopSequences"] = .array(request.stopSequences) }
}

func googleApplyProviderGenerationOptions(_ options: [String: JSONValue], to generationConfig: inout [String: JSONValue]) {
    for key in ["responseModalities", "thinkingConfig", "mediaResolution", "imageConfig", "audioTimestamp"] {
        if let value = options[key] {
            generationConfig[key] = value
        }
    }
}

func googleTopLevelGenerateContentOptions(_ options: [String: JSONValue]) -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for key in ["safetySettings", "cachedContent", "labels", "serviceTier"] {
        if let value = options[key] {
            output[key] = value
        }
    }
    return output
}

func googleToolConfigWithProviderOptions(_ toolConfig: JSONValue?, options: [String: JSONValue], isStreaming: Bool, isVertexProvider: Bool) -> JSONValue? {
    let shouldStreamFunctionCallArguments = isStreaming && isVertexProvider && options["streamFunctionCallArguments"]?.boolValue == true
    let retrievalConfig = options["retrievalConfig"]
    guard toolConfig != nil || shouldStreamFunctionCallArguments || retrievalConfig != nil else { return nil }

    var output = toolConfig?.objectValue ?? [:]
    if shouldStreamFunctionCallArguments {
        var functionCallingConfig = output["functionCallingConfig"]?.objectValue ?? [:]
        functionCallingConfig["streamFunctionCallArguments"] = true
        output["functionCallingConfig"] = .object(functionCallingConfig)
    }
    if let retrievalConfig {
        output["retrievalConfig"] = retrievalConfig
    }
    return .object(output)
}

private func googleThinkingConfig(for reasoning: String?, modelID: String, warnings: inout [AIWarning]) -> [String: JSONValue]? {
    guard let reasoning, reasoning != "provider-default" else { return nil }
    if googleIsGemini3OrNewer(modelID), !modelID.lowercased().contains("gemini-3-pro-image") {
        if reasoning == "none" {
            return ["thinkingLevel": .string("minimal")]
        }
        let effortMap = [
            "minimal": "minimal",
            "low": "low",
            "medium": "medium",
            "high": "high",
            "xhigh": "high"
        ]
        guard let mapped = effortMap[reasoning] else {
            warnings.append(AIWarning(type: "unsupported", feature: "reasoning", message: "reasoning \"\(reasoning)\" is not supported by this model."))
            return nil
        }
        if mapped != reasoning {
            warnings.append(AIWarning(
                type: "compatibility",
                feature: "reasoning",
                message: "reasoning \"\(reasoning)\" is not directly supported by this model. mapped to effort \"\(mapped)\"."
            ))
        }
        return ["thinkingLevel": .string(mapped)]
    }

    if reasoning == "none" {
        return ["thinkingBudget": .number(0)]
    }
    let budgetPercentages: [String: Double] = [
        "minimal": 0.02,
        "low": 0.1,
        "medium": 0.3,
        "high": 0.6,
        "xhigh": 0.9
    ]
    guard let percentage = budgetPercentages[reasoning] else {
        warnings.append(AIWarning(type: "unsupported", feature: "reasoning", message: "reasoning \"\(reasoning)\" is not supported by this model."))
        return nil
    }
    let maxThinkingTokens = googleMaxThinkingTokensForGemini25Model(modelID)
    let budget = min(maxThinkingTokens, max(0, Int((65536 * percentage).rounded())))
    return ["thinkingBudget": .number(Double(budget))]
}

private func googleMaxThinkingTokensForGemini25Model(_ modelID: String) -> Int {
    let id = modelID.lowercased()
    if id.contains("2.5-pro") || id.contains("gemini-3-pro-image") {
        return 32768
    }
    return 24576
}

private let googleKnownLanguageProviderOptionKeys: Set<String> = [
    "responseModalities",
    "thinkingConfig",
    "cachedContent",
    "structuredOutputs",
    "safetySettings",
    "audioTimestamp",
    "labels",
    "mediaResolution",
    "imageConfig",
    "retrievalConfig",
    "streamFunctionCallArguments",
    "serviceTier",
    "sharedRequestType",
    "requestType"
]

private func googleResponseFormatJSON(_ responseFormat: AIResponseFormat) -> JSONValue? {
    switch responseFormat {
    case .text:
        return nil
    case let .json(schema, name, description):
        return .object([
            "type": .string("json"),
            "schema": schema,
            "name": name.map(JSONValue.string),
            "description": description.map(JSONValue.string)
        ])
    }
}

private func googleFunctionDeclarations(from tools: [String: JSONValue]) -> [JSONValue] {
    tools.compactMap { name, schema in
        let object = schema.objectValue
        if object?["type"]?.stringValue == "provider" || object?["id"]?.stringValue?.hasPrefix("google.") == true {
            return nil
        }

        var declaration: [String: JSONValue] = [
            "name": .string(name),
            "description": .string(object?["description"]?.stringValue ?? "")
        ]
        if let parameters = googleOpenAPISchema(from: schema, isRoot: true) {
            declaration["parameters"] = parameters
        }
        return .object(declaration)
    }
}

private func googleProviderTool(name: String, schema: JSONValue, modelID: String) -> GooglePreparedProviderTool {
    let object = schema.objectValue
    let id = object?["id"]?.stringValue ?? name
    let args = object?["args"]?.objectValue ?? [:]

    switch id {
    case "google.google_search":
        guard googleIsGemini2OrNewer(modelID) else {
            return googleUnsupportedProviderTool(id, details: "Google Search requires Gemini 2.0 or newer.")
        }
        return GooglePreparedProviderTool(tool: .object(["googleSearch": .object(args)]))
    case "google.enterprise_web_search":
        guard googleIsGemini2OrNewer(modelID) else {
            return googleUnsupportedProviderTool(id, details: "Enterprise Web Search requires Gemini 2.0 or newer.")
        }
        return GooglePreparedProviderTool(tool: .object(["enterpriseWebSearch": .object([:])]))
    case "google.url_context":
        guard googleIsGemini2OrNewer(modelID) else {
            return googleUnsupportedProviderTool(id, details: "The URL context tool is not supported with other Gemini models than Gemini 2.")
        }
        return GooglePreparedProviderTool(tool: .object(["urlContext": .object([:])]))
    case "google.code_execution":
        guard googleIsGemini2OrNewer(modelID) else {
            return googleUnsupportedProviderTool(id, details: "The code execution tool is not supported with other Gemini models than Gemini 2.")
        }
        return GooglePreparedProviderTool(tool: .object(["codeExecution": .object([:])]))
    case "google.file_search":
        guard modelID.contains("gemini-2.5") || modelID.contains("gemini-3") else {
            return googleUnsupportedProviderTool(id, details: "The file search tool is only supported with Gemini 2.5 models and Gemini 3 models.")
        }
        return GooglePreparedProviderTool(tool: .object(["fileSearch": .object(args)]))
    case "google.vertex_rag_store":
        guard googleIsGemini2OrNewer(modelID) else {
            return googleUnsupportedProviderTool(id, details: "The RAG store tool is not supported with other Gemini models than Gemini 2.")
        }
        return GooglePreparedProviderTool(tool: .object([
            "retrieval": .object([
                "vertex_rag_store": .object([
                    "rag_resources": .object(["rag_corpus": args["ragCorpus"] ?? args["rag_corpus"]]),
                    "similarity_top_k": args["topK"] ?? args["top_k"]
                ])
            ])
        ]))
    case "google.google_maps":
        guard googleIsGemini2OrNewer(modelID) else {
            return googleUnsupportedProviderTool(id, details: "The Google Maps grounding tool is not supported with Gemini models other than Gemini 2 or newer.")
        }
        return GooglePreparedProviderTool(tool: .object(["googleMaps": .object([:])]))
    default:
        return googleUnsupportedProviderTool(id, details: nil)
    }
}

private func googleUnsupportedProviderTool(_ id: String, details: String?) -> GooglePreparedProviderTool {
    GooglePreparedProviderTool(warnings: [
        AIWarning(
            type: "unsupported",
            feature: "provider-defined tool \(id)",
            message: details
        )
    ])
}

private func googleToolConfig(from value: JSONValue?, hasStrictTools: Bool, defaultMode: String?) -> JSONValue? {
    guard let value else {
        guard hasStrictTools || defaultMode != nil else { return nil }
        return .object(["functionCallingConfig": .object(["mode": .string(defaultMode ?? "VALIDATED")])])
    }

    let type: String?
    let toolName: String?
    if let string = value.stringValue {
        type = string
        toolName = nil
    } else if let object = value.objectValue {
        type = object["type"]?.stringValue
        toolName = object["toolName"]?.stringValue
            ?? object["tool_name"]?.stringValue
            ?? object["function"]?["name"]?.stringValue
    } else {
        return nil
    }

    var config: [String: JSONValue]
    switch type {
    case "auto":
        config = ["mode": .string(hasStrictTools ? "VALIDATED" : "AUTO")]
    case "none":
        config = ["mode": .string("NONE")]
    case "required":
        config = ["mode": .string(hasStrictTools ? "VALIDATED" : "ANY")]
    case "tool":
        guard let toolName else { return nil }
        config = [
            "mode": .string(hasStrictTools ? "VALIDATED" : "ANY"),
            "allowedFunctionNames": .array([.string(toolName)])
        ]
    default:
        return nil
    }
    return .object(["functionCallingConfig": .object(config)])
}

private func googleHasStrictTools(_ tools: [String: JSONValue]) -> Bool {
    tools.values.contains { $0["strict"]?.boolValue == true }
}

private func googleIsGemini2OrNewer(_ modelID: String) -> Bool {
    modelID.contains("gemini-2")
        || modelID.contains("gemini-3")
        || modelID.contains("nano-banana")
        || ["gemini-flash-latest", "gemini-flash-lite-latest", "gemini-pro-latest"].contains(modelID)
}

private func googleIsGemini3OrNewer(_ modelID: String) -> Bool {
    modelID.contains("gemini-3")
}

func googleOpenAPISchema(from schema: JSONValue, isRoot: Bool) -> JSONValue? {
    if case let .bool(value) = schema {
        return value ? .object(["type": .string("boolean"), "properties": .object([:])]) : nil
    }
    guard let object = schema.objectValue else { return schema }

    if isRoot,
       object["type"]?.stringValue == "object",
       (object["properties"]?.objectValue?.isEmpty ?? true),
       object["additionalProperties"]?.boolValue != true {
        return nil
    }

    var result: [String: JSONValue] = [:]
    for key in ["description", "required", "format", "enum", "minLength"] {
        if let value = object[key] {
            result[key] = value
        }
    }
    if let constValue = object["const"] {
        result["enum"] = .array([constValue])
    }

    if let type = object["type"] {
        if let types = type.arrayValue?.compactMap(\.stringValue) {
            let nonNullTypes = types.filter { $0 != "null" }
            if nonNullTypes.isEmpty {
                result["type"] = .string("null")
            } else {
                result["anyOf"] = .array(nonNullTypes.map { .object(["type": .string($0)]) })
                if types.contains("null") {
                    result["nullable"] = true
                }
            }
        } else {
            result["type"] = type
        }
    }

    if let properties = object["properties"]?.objectValue {
        result["properties"] = .object(properties.mapValues { googleOpenAPISchema(from: $0, isRoot: false) ?? .object([:]) })
    }
    if let items = object["items"] {
        if let array = items.arrayValue {
            result["items"] = .array(array.map { googleOpenAPISchema(from: $0, isRoot: false) ?? .object([:]) })
        } else if let converted = googleOpenAPISchema(from: items, isRoot: false) {
            result["items"] = converted
        }
    }
    for key in ["allOf", "oneOf"] {
        if let array = object[key]?.arrayValue {
            result[key] = .array(array.map { googleOpenAPISchema(from: $0, isRoot: false) ?? .object([:]) })
        }
    }
    if let anyOf = object["anyOf"]?.arrayValue {
        let nonNullSchemas = anyOf.filter { $0["type"]?.stringValue != "null" }
        if nonNullSchemas.count != anyOf.count {
            result["nullable"] = true
            if nonNullSchemas.count == 1, let converted = googleOpenAPISchema(from: nonNullSchemas[0], isRoot: false)?.objectValue {
                result.merge(converted) { _, new in new }
            } else {
                result["anyOf"] = .array(nonNullSchemas.map { googleOpenAPISchema(from: $0, isRoot: false) ?? .object([:]) })
            }
        } else {
            result["anyOf"] = .array(anyOf.map { googleOpenAPISchema(from: $0, isRoot: false) ?? .object([:]) })
        }
    }

    return result.isEmpty ? nil : .object(result)
}
