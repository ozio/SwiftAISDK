import Foundation

func xaiChatWarnings(for request: LanguageModelRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.topK != nil { warnings.append(AIWarning(type: "unsupported", feature: "topK")) }
    if request.frequencyPenalty != nil { warnings.append(AIWarning(type: "unsupported", feature: "frequencyPenalty")) }
    if request.presencePenalty != nil { warnings.append(AIWarning(type: "unsupported", feature: "presencePenalty")) }
    if !request.stopSequences.isEmpty { warnings.append(AIWarning(type: "unsupported", feature: "stopSequences")) }
    return warnings
}

func xaiChatBody(from input: [String: JSONValue], request: LanguageModelRequest) throws -> [String: JSONValue] {
    var body = input
    if let maxTokens = body.removeValue(forKey: "max_tokens") {
        body["max_completion_tokens"] = maxTokens
    }
    body.removeValue(forKey: "stop")
    if let seed = request.seed {
        body["seed"] = .number(Double(seed))
    }
    if let responseFormat = xaiChatResponseFormat(from: request.responseFormat) {
        body["response_format"] = responseFormat
    }
    if let value = request.providerOptions["xai"] {
        guard value != .null else { return xaiChatWireOptions(from: body, reasoning: request.reasoning) }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.xai", message: "xAI chat provider options must be an object.")
        }
        body.merge(try xaiValidateChatProviderOptions(nested)) { _, nested in nested }
    }
    return xaiChatWireOptions(from: body, reasoning: request.reasoning)
}

func xaiChatWireOptions(from input: [String: JSONValue], reasoning: String?) -> [String: JSONValue] {
    var body = input
    if let effort = body.removeValue(forKey: "reasoningEffort") {
        body["reasoning_effort"] = effort
    }
    if body["reasoning_effort"] == nil, let reasoningEffort = xaiReasoningEffort(reasoning) {
        body["reasoning_effort"] = .string(reasoningEffort)
    }
    if let topLogprobs = body.removeValue(forKey: "topLogprobs") {
        body["top_logprobs"] = topLogprobs
        body["logprobs"] = .bool(true)
    } else if body["logprobs"]?.boolValue != true {
        body.removeValue(forKey: "logprobs")
    }
    if let searchParameters = body.removeValue(forKey: "searchParameters") {
        body["search_parameters"] = xaiChatSearchParametersWireValue(searchParameters)
    }
    return body
}

func xaiReasoningEffort(_ reasoning: String?) -> String? {
    switch reasoning {
    case "minimal", "low":
        return "low"
    case "medium":
        return "medium"
    case "high", "xhigh":
        return "high"
    default:
        return nil
    }
}

func xaiChatResponseFormat(from responseFormat: AIResponseFormat?) -> JSONValue? {
    guard let responseFormat else { return nil }
    switch responseFormat {
    case .text:
        return nil
    case let .json(schema, name, _):
        guard let schema else {
            return .object(["type": .string("json_object")])
        }
        return .object([
            "type": .string("json_schema"),
            "json_schema": .object([
                "name": .string(name ?? "response"),
                "schema": schema,
                "strict": .bool(true)
            ])
        ])
    }
}

func xaiValidateChatProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    let allowedKeys: Set<String> = [
        "reasoningEffort",
        "logprobs",
        "topLogprobs",
        "parallel_function_calling",
        "searchParameters"
    ]
    var output: [String: JSONValue] = [:]
    for (key, value) in options where allowedKeys.contains(key) {
        switch key {
        case "reasoningEffort":
            guard let effort = value.stringValue, ["none", "low", "medium", "high"].contains(effort) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.reasoningEffort", message: "xAI reasoningEffort must be none, low, medium, or high.")
            }
        case "logprobs", "parallel_function_calling":
            guard value.boolValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.\(key)", message: "xAI \(key) must be a boolean.")
            }
        case "topLogprobs":
            guard let topLogprobs = value.intValue,
                  value.doubleValue == Double(topLogprobs),
                  (0...8).contains(topLogprobs) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.topLogprobs", message: "xAI topLogprobs must be an integer from 0 to 8.")
            }
        case "searchParameters":
            output[key] = .object(try xaiValidateChatSearchParameters(value))
            continue
        default:
            break
        }
        output[key] = value
    }
    return output
}

func xaiValidateChatSearchParameters(_ value: JSONValue) throws -> [String: JSONValue] {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.xai.searchParameters", message: "xAI searchParameters must be an object.")
    }
    guard let mode = object["mode"]?.stringValue, ["off", "auto", "on"].contains(mode) else {
        throw AIError.invalidArgument(argument: "providerOptions.xai.searchParameters.mode", message: "xAI searchParameters.mode must be off, auto, or on.")
    }
    var output: [String: JSONValue] = ["mode": .string(mode)]
    if let returnCitations = object["returnCitations"] {
        guard returnCitations.boolValue != nil else {
            throw AIError.invalidArgument(argument: "providerOptions.xai.searchParameters.returnCitations", message: "xAI returnCitations must be a boolean.")
        }
        output["returnCitations"] = returnCitations
    }
    for key in ["fromDate", "toDate"] {
        if let value = object[key] {
            guard value.stringValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.searchParameters.\(key)", message: "xAI \(key) must be a string.")
            }
            output[key] = value
        }
    }
    if let maxSearchResults = object["maxSearchResults"] {
        guard let count = maxSearchResults.intValue,
              maxSearchResults.doubleValue == Double(count),
              (1...50).contains(count) else {
            throw AIError.invalidArgument(argument: "providerOptions.xai.searchParameters.maxSearchResults", message: "xAI maxSearchResults must be a number from 1 to 50.")
        }
        output["maxSearchResults"] = maxSearchResults
    }
    if let sources = object["sources"] {
        guard let array = sources.arrayValue else {
            throw AIError.invalidArgument(argument: "providerOptions.xai.searchParameters.sources", message: "xAI sources must be an array.")
        }
        output["sources"] = .array(try array.map(xaiValidateChatSearchSource))
    }
    return output
}

func xaiValidateChatSearchSource(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue, let type = object["type"]?.stringValue else {
        throw AIError.invalidArgument(argument: "providerOptions.xai.searchParameters.sources", message: "xAI search source must have a type.")
    }
    var output: [String: JSONValue] = ["type": .string(type)]
    switch type {
    case "web":
        try xaiCopyOptionalCountry(from: object, to: &output)
        try xaiCopyOptionalStringArray(from: object, key: "excludedWebsites", to: &output, maxCount: 5)
        try xaiCopyOptionalStringArray(from: object, key: "allowedWebsites", to: &output, maxCount: 5)
        try xaiCopyOptionalBool(from: object, key: "safeSearch", to: &output)
    case "x":
        try xaiCopyOptionalStringArray(from: object, key: "excludedXHandles", to: &output)
        try xaiCopyOptionalStringArray(from: object, key: "includedXHandles", to: &output)
        try xaiCopyOptionalStringArray(from: object, key: "xHandles", to: &output)
        try xaiCopyOptionalInt(from: object, key: "postFavoriteCount", to: &output)
        try xaiCopyOptionalInt(from: object, key: "postViewCount", to: &output)
    case "news":
        try xaiCopyOptionalCountry(from: object, to: &output)
        try xaiCopyOptionalStringArray(from: object, key: "excludedWebsites", to: &output, maxCount: 5)
        try xaiCopyOptionalBool(from: object, key: "safeSearch", to: &output)
    case "rss":
        guard let links = object["links"]?.arrayValue,
              !links.isEmpty,
              links.count <= 1,
              links.allSatisfy({ $0.stringValue.flatMap(URL.init(string:)) != nil }) else {
            throw AIError.invalidArgument(argument: "providerOptions.xai.searchParameters.sources.links", message: "xAI rss source links must contain one URL string.")
        }
        output["links"] = .array(links)
    default:
        throw AIError.invalidArgument(argument: "providerOptions.xai.searchParameters.sources.type", message: "xAI search source type must be web, x, news, or rss.")
    }
    return .object(output)
}

func xaiCopyOptionalCountry(from object: [String: JSONValue], to output: inout [String: JSONValue]) throws {
    if let country = object["country"] {
        guard country.stringValue?.count == 2 else {
            throw AIError.invalidArgument(argument: "providerOptions.xai.searchParameters.sources.country", message: "xAI source country must be a two-letter string.")
        }
        output["country"] = country
    }
}

func xaiCopyOptionalBool(from object: [String: JSONValue], key: String, to output: inout [String: JSONValue]) throws {
    guard let value = object[key] else { return }
    guard value.boolValue != nil else {
        throw AIError.invalidArgument(argument: "providerOptions.xai.searchParameters.sources.\(key)", message: "xAI source \(key) must be a boolean.")
    }
    output[key] = value
}

func xaiCopyOptionalInt(from object: [String: JSONValue], key: String, to output: inout [String: JSONValue]) throws {
    guard let value = object[key] else { return }
    guard let intValue = value.intValue, value.doubleValue == Double(intValue) else {
        throw AIError.invalidArgument(argument: "providerOptions.xai.searchParameters.sources.\(key)", message: "xAI source \(key) must be an integer.")
    }
    output[key] = value
}

func xaiCopyOptionalStringArray(from object: [String: JSONValue], key: String, to output: inout [String: JSONValue], maxCount: Int? = nil) throws {
    guard let value = object[key] else { return }
    guard let array = value.arrayValue,
          maxCount.map({ array.count <= $0 }) ?? true,
          array.allSatisfy({ $0.stringValue != nil }) else {
        let suffix = maxCount.map { " with at most \($0) strings" } ?? " of strings"
        throw AIError.invalidArgument(argument: "providerOptions.xai.searchParameters.sources.\(key)", message: "xAI source \(key) must be an array\(suffix).")
    }
    output[key] = value
}

func xaiChatSearchParametersWireValue(_ value: JSONValue) -> JSONValue {
    guard let object = value.objectValue else { return value }
    var output: [String: JSONValue] = [:]
    if let mode = object["mode"] { output["mode"] = mode }
    if let returnCitations = object["returnCitations"] { output["return_citations"] = returnCitations }
    if let fromDate = object["fromDate"] { output["from_date"] = fromDate }
    if let toDate = object["toDate"] { output["to_date"] = toDate }
    if let maxSearchResults = object["maxSearchResults"] { output["max_search_results"] = maxSearchResults }
    if let sources = object["sources"]?.arrayValue {
        output["sources"] = .array(sources.map(xaiChatSearchSourceWireValue))
    }
    return .object(output)
}

func xaiChatSearchSourceWireValue(_ value: JSONValue) -> JSONValue {
    guard let object = value.objectValue else { return value }
    var output: [String: JSONValue] = [:]
    if let type = object["type"] { output["type"] = type }
    if let country = object["country"] { output["country"] = country }
    if let excludedWebsites = object["excludedWebsites"] { output["excluded_websites"] = excludedWebsites }
    if let allowedWebsites = object["allowedWebsites"] { output["allowed_websites"] = allowedWebsites }
    if let safeSearch = object["safeSearch"] { output["safe_search"] = safeSearch }
    if let excludedXHandles = object["excludedXHandles"] { output["excluded_x_handles"] = excludedXHandles }
    if let includedXHandles = object["includedXHandles"] ?? object["xHandles"] { output["included_x_handles"] = includedXHandles }
    if let postFavoriteCount = object["postFavoriteCount"] { output["post_favorite_count"] = postFavoriteCount }
    if let postViewCount = object["postViewCount"] { output["post_view_count"] = postViewCount }
    if let links = object["links"] { output["links"] = links }
    return .object(output)
}
