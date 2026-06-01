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
}

func googlePrepareTools(
    from tools: [String: JSONValue],
    toolChoice: JSONValue?,
    modelID: String,
    isVertexProvider: Bool
) -> GooglePreparedTools? {
    guard !tools.isEmpty else { return nil }

    let providerTools = tools.compactMap { name, schema -> JSONValue? in
        googleProviderTool(name: name, schema: schema, modelID: modelID)
    }
    let functionDeclarations = googleFunctionDeclarations(from: tools)
    let hasFunctionTools = !functionDeclarations.isEmpty
    let hasProviderTools = !providerTools.isEmpty || tools.values.contains { schema in
        guard let object = schema.objectValue else { return false }
        return object["type"]?.stringValue == "provider" || object["id"]?.stringValue?.hasPrefix("google.") == true
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
            return GooglePreparedTools(tools: prepared, toolConfig: config)
        }
        return providerTools.isEmpty ? nil : GooglePreparedTools(tools: providerTools, toolConfig: nil)
    }

    guard hasFunctionTools else { return nil }
    return GooglePreparedTools(
        tools: [.object(["functionDeclarations": .array(functionDeclarations)])],
        toolConfig: googleToolConfig(from: toolChoice, hasStrictTools: googleHasStrictTools(tools), defaultMode: nil)
    )
}

func googleExtraBodyWithoutToolChoice(_ extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    output.removeValue(forKey: "toolChoice")
    output.removeValue(forKey: "responseFormat")
    output.removeValue(forKey: "structuredOutputs")
    output.removeValue(forKey: "google")
    return output
}

func googleGenerateContentOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "google")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
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

private func googleProviderTool(name: String, schema: JSONValue, modelID: String) -> JSONValue? {
    let object = schema.objectValue
    let id = object?["id"]?.stringValue ?? name
    let args = object?["args"]?.objectValue ?? [:]
    let isProviderTool = object?["type"]?.stringValue == "provider" || id.hasPrefix("google.")
    guard isProviderTool else { return nil }

    switch id {
    case "google.google_search":
        guard googleIsGemini2OrNewer(modelID) else { return nil }
        return .object(["googleSearch": .object(args)])
    case "google.enterprise_web_search":
        guard googleIsGemini2OrNewer(modelID) else { return nil }
        return .object(["enterpriseWebSearch": .object([:])])
    case "google.url_context":
        guard googleIsGemini2OrNewer(modelID) else { return nil }
        return .object(["urlContext": .object([:])])
    case "google.code_execution":
        guard googleIsGemini2OrNewer(modelID) else { return nil }
        return .object(["codeExecution": .object([:])])
    case "google.file_search":
        guard modelID.contains("gemini-2.5") || modelID.contains("gemini-3") else { return nil }
        return .object(["fileSearch": .object(args)])
    case "google.vertex_rag_store":
        guard googleIsGemini2OrNewer(modelID) else { return nil }
        return .object([
            "retrieval": .object([
                "vertex_rag_store": .object([
                    "rag_resources": .object(["rag_corpus": args["ragCorpus"] ?? args["rag_corpus"]]),
                    "similarity_top_k": args["topK"] ?? args["top_k"]
                ])
            ])
        ])
    case "google.google_maps":
        guard googleIsGemini2OrNewer(modelID) else { return nil }
        return .object(["googleMaps": .object([:])])
    default:
        return nil
    }
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
