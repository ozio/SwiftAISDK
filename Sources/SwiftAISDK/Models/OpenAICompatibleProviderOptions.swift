import Foundation

func isOpenAIBackedProvider(_ providerID: String) -> Bool {
    providerID == "openai" || providerID.hasPrefix("openai.")
        || providerID == "azure" || providerID.hasPrefix("azure.")
}

func isOpenAIBackedProvider(_ providerID: String, config: ModelHTTPConfig) -> Bool {
    openAIBackedProviderRoot(providerID, config: config) != nil
}

func openAIBackedProviderRoot(_ providerID: String, config: ModelHTTPConfig) -> String? {
    config.openAIBackedProviderRoot ?? openAIBackedProviderRoot(providerID)
}

func openAIProviderOptions(from extraBody: [String: JSONValue], providerID: String = "openai", providerRoot: String? = nil) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "openai")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    if let root = providerRoot ?? openAIBackedProviderRoot(providerID),
       root != "openai",
       let nested = output.removeValue(forKey: root)?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    if providerID != "openai",
       providerID != (providerRoot ?? openAIBackedProviderRoot(providerID)),
       let nested = output.removeValue(forKey: providerID)?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

func openAIProviderOptions(providerOptions: [String: JSONValue], extraBody: [String: JSONValue], providerID: String = "openai", providerRoot: String? = nil) -> [String: JSONValue] {
    var output = openAIProviderOptions(from: extraBody, providerID: providerID, providerRoot: providerRoot)
    let roots = openAIProviderOptionNamespaceKeys(providerID: providerID, providerRoot: providerRoot)
    for root in roots {
        guard let value = providerOptions[root], value != .null else { continue }
        if let nested = value.objectValue {
            output.merge(nested) { _, providerValue in providerValue }
        }
    }
    return output
}

func openAIProviderOptionNamespaceKeys(providerID: String, providerRoot: String?) -> [String] {
    var keys: [String] = []
    func append(_ key: String?) {
        guard let key, !keys.contains(key) else { return }
        keys.append(key)
    }
    append(providerRoot ?? openAIBackedProviderRoot(providerID))
    append(openAIBackedProviderRoot(providerID))
    append(providerID)
    append("openai")
    return keys
}

func openAIBackedProviderRoot(_ providerID: String) -> String? {
    if providerID == "openai" || providerID.hasPrefix("openai.") {
        return "openai"
    }
    if providerID == "azure" || providerID.hasPrefix("azure.") {
        return "azure"
    }
    return nil
}

func openAICompatibleProviderOptions(from extraBody: [String: JSONValue], providerID: String, includeCompatibilityNamespace: Bool) -> [String: JSONValue] {
    var output = extraBody
    var nested: [String: JSONValue] = [:]

    if includeCompatibilityNamespace {
        if let deprecated = output.removeValue(forKey: "openai-compatible")?.objectValue {
            nested.merge(deprecated) { _, value in value }
        }
        if let compatible = output.removeValue(forKey: "openaiCompatible")?.objectValue {
            nested.merge(compatible) { _, value in value }
        }
    }

    let providerRoots = openAICompatibleProviderOptionRoots(providerID)
    for providerRoot in providerRoots {
        if let rootProviderOptions = output.removeValue(forKey: providerRoot)?.objectValue {
            nested.merge(rootProviderOptions) { _, value in value }
        }
        let camelRoot = openAICompatibleCamelCase(providerRoot)
        if camelRoot != providerRoot, let camelRootOptions = output.removeValue(forKey: camelRoot)?.objectValue {
            nested.merge(camelRootOptions) { _, value in value }
        }
    }

    let camelProviderID = openAICompatibleCamelCase(providerID)
    if providerID.hasPrefix("xai."), let rootProviderOptions = output.removeValue(forKey: "xai")?.objectValue {
        nested.merge(rootProviderOptions) { _, value in value }
    }
    if let rawProviderOptions = output.removeValue(forKey: providerID)?.objectValue {
        nested.merge(rawProviderOptions) { _, value in value }
    }
    if camelProviderID != providerID, let camelProviderOptions = output.removeValue(forKey: camelProviderID)?.objectValue {
        nested.merge(camelProviderOptions) { _, value in value }
    }

    output.merge(nested) { _, nested in nested }
    return output
}

func openAICompatibleProviderOptions(providerOptions: [String: JSONValue], extraBody: [String: JSONValue], providerID: String, includeCompatibilityNamespace: Bool) -> [String: JSONValue] {
    var output = openAICompatibleProviderOptions(from: extraBody, providerID: providerID, includeCompatibilityNamespace: includeCompatibilityNamespace)
    var nested: [String: JSONValue] = [:]

    if includeCompatibilityNamespace {
        if let deprecated = providerOptions["openai-compatible"]?.objectValue {
            nested.merge(deprecated) { _, value in value }
        }
        if let compatible = providerOptions["openaiCompatible"]?.objectValue {
            nested.merge(compatible) { _, value in value }
        }
    }

    for key in openAICompatibleProviderOptionNamespaceKeys(providerID) {
        if let options = providerOptions[key]?.objectValue {
            nested.merge(options) { _, value in value }
        }
    }

    output.merge(nested) { _, value in value }
    return output
}

func openAICompatibleProviderOptionWarnings(from extraBody: [String: JSONValue], providerID: String, includeCompatibilityNamespace: Bool) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if includeCompatibilityNamespace, extraBody["openai-compatible"] != nil {
        warnings.append(AIWarning(
            type: "deprecated",
            setting: "providerOptions key 'openai-compatible'",
            message: "Use 'openaiCompatible' instead."
        ))
    }

    let providerOptionsKey = openAICompatibleProviderRoot(providerID)
    let camelProviderOptionsKey = openAICompatibleCamelCase(providerOptionsKey)
    if camelProviderOptionsKey != providerOptionsKey, extraBody[providerOptionsKey] != nil {
        warnings.append(AIWarning(
            type: "deprecated",
            setting: "providerOptions key '\(providerOptionsKey)'",
            message: "Use '\(camelProviderOptionsKey)' instead."
        ))
    }
    return warnings
}

func openAICompatibleProviderOptionWarnings(providerOptions: [String: JSONValue], extraBody: [String: JSONValue], providerID: String, includeCompatibilityNamespace: Bool) -> [AIWarning] {
    var warnings = openAICompatibleProviderOptionWarnings(from: extraBody, providerID: providerID, includeCompatibilityNamespace: includeCompatibilityNamespace)
    if includeCompatibilityNamespace, providerOptions["openai-compatible"] != nil {
        warnings.append(AIWarning(
            type: "deprecated",
            setting: "providerOptions key 'openai-compatible'",
            message: "Use 'openaiCompatible' instead."
        ))
    }

    let providerOptionsKey = openAICompatibleProviderRoot(providerID)
    let camelProviderOptionsKey = openAICompatibleCamelCase(providerOptionsKey)
    if camelProviderOptionsKey != providerOptionsKey, providerOptions[providerOptionsKey] != nil {
        warnings.append(AIWarning(
            type: "deprecated",
            setting: "providerOptions key '\(providerOptionsKey)'",
            message: "Use '\(camelProviderOptionsKey)' instead."
        ))
    }
    return warnings
}

func openAICompatibleProviderRoot(_ providerID: String) -> String {
    String(providerID.split(separator: ".", maxSplits: 1).first.map(String.init) ?? providerID)
}

func openAICompatibleProviderOptionRoots(_ providerID: String) -> [String] {
    let root = openAICompatibleProviderRoot(providerID)
    switch root {
    case "baseten", "deepinfra", "fireworks", "moonshotai", "togetherai":
        return providerID == root ? [] : [root]
    default:
        return openAICompatibleProviderSurface(providerID) == nil ? [] : [root]
    }
}

func openAICompatibleProviderOptionNamespaceKeys(_ providerID: String) -> [String] {
    var keys: [String] = []
    func append(_ key: String) {
        guard !keys.contains(key) else { return }
        keys.append(key)
    }

    for root in openAICompatibleProviderOptionRoots(providerID) {
        append(root)
        let camelRoot = openAICompatibleCamelCase(root)
        if camelRoot != root { append(camelRoot) }
    }
    if providerID.hasPrefix("xai.") {
        append("xai")
    }
    append(providerID)
    let camelProviderID = openAICompatibleCamelCase(providerID)
    if camelProviderID != providerID { append(camelProviderID) }
    return keys
}

func openAICompatibleProviderSurface(_ providerID: String) -> String? {
    let parts = providerID.split(separator: ".", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return nil }
    switch parts[1] {
    case "chat", "completion", "embedding", "image":
        return parts[1]
    default:
        return nil
    }
}

func openAICompatibleCamelCase(_ value: String) -> String {
    let separators = CharacterSet(charactersIn: "-_. ")
    let parts = value
        .components(separatedBy: separators)
        .filter { !$0.isEmpty }
    guard let first = parts.first else { return value }
    return parts.dropFirst().reduce(first) { result, part in
        result + part.prefix(1).uppercased() + part.dropFirst()
    }
}

func openAICompletionProviderOptions(from extraBody: [String: JSONValue], providerID: String, providerRoot: String? = nil) -> [String: JSONValue] {
    openAIProviderOptions(from: extraBody, providerID: providerID, providerRoot: providerRoot)
}

func openAICompletionProviderOptions(providerOptions: [String: JSONValue], extraBody: [String: JSONValue], providerID: String, providerRoot: String? = nil) -> [String: JSONValue] {
    openAIProviderOptions(providerOptions: providerOptions, extraBody: extraBody, providerID: providerID, providerRoot: providerRoot)
}

func openAICompletionOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    openAIResponsesMoveKey("logitBias", to: "logit_bias", in: &output)
    if let logprobs = output["logprobs"] {
        if logprobs.boolValue == true {
            output["logprobs"] = .number(0)
        } else if logprobs.boolValue == false {
            output.removeValue(forKey: "logprobs")
        }
    }
    return output
}

func openAICompletionWarnings(for request: LanguageModelRequest, providerID: String, openAIBackedProviderRoot: String? = nil, usesGenericProviderOptions: Bool = false) -> [AIWarning] {
    var warnings = isOpenAIBackedProvider(providerID) || openAIBackedProviderRoot != nil
        ? []
        : (usesGenericProviderOptions
            ? openAICompatibleProviderOptionWarnings(providerOptions: request.providerOptions, extraBody: request.extraBody, providerID: providerID, includeCompatibilityNamespace: false)
            : openAICompatibleProviderOptionWarnings(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: false))
    if request.topK != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "topK"))
    }
    if !request.tools.isEmpty {
        warnings.append(AIWarning(type: "unsupported", feature: "tools"))
    }
    if request.toolChoice != nil || request.extraBody["toolChoice"] != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "toolChoice"))
    }
    if let responseFormat = request.responseFormat, responseFormat != .text {
        warnings.append(AIWarning(type: "unsupported", feature: "responseFormat", message: "JSON response format is not supported."))
    }
    return warnings
}

func openAIResponsesProviderOptions(from extraBody: [String: JSONValue], providerID: String, providerRoot: String? = nil) -> [String: JSONValue] {
    openAIProviderOptions(from: extraBody, providerID: providerID, providerRoot: providerRoot)
}

func openAIResponsesProviderOptions(providerOptions: [String: JSONValue], extraBody: [String: JSONValue], providerID: String, providerRoot: String? = nil) -> [String: JSONValue] {
    openAIProviderOptions(providerOptions: providerOptions, extraBody: extraBody, providerID: providerID, providerRoot: providerRoot)
}

func openAIImageOptions(from extraBody: [String: JSONValue], providerID: String = "openai", providerRoot: String? = nil) -> [String: JSONValue] {
    var output = openAIProviderOptions(from: extraBody, providerID: providerID, providerRoot: providerRoot)
    openAIResponsesMoveKey("outputFormat", to: "output_format", in: &output)
    openAIResponsesMoveKey("outputCompression", to: "output_compression", in: &output)
    openAIResponsesMoveKey("inputFidelity", to: "input_fidelity", in: &output)
    return output
}

func openAIImageOptions(providerOptions: [String: JSONValue], extraBody: [String: JSONValue], providerID: String = "openai", providerRoot: String? = nil) -> [String: JSONValue] {
    var output = openAIProviderOptions(providerOptions: providerOptions, extraBody: extraBody, providerID: providerID, providerRoot: providerRoot)
    openAIResponsesMoveKey("outputFormat", to: "output_format", in: &output)
    openAIResponsesMoveKey("outputCompression", to: "output_compression", in: &output)
    openAIResponsesMoveKey("inputFidelity", to: "input_fidelity", in: &output)
    return output
}

func openAIImageHasDefaultResponseFormat(_ modelID: String) -> Bool {
    ["chatgpt-image-", "gpt-image-"].contains { modelID.hasPrefix($0) }
}

func openAIImageMaxImagesPerCall(_ modelID: String) -> Int {
    switch modelID {
    case "dall-e-2", "gpt-image-1", "gpt-image-1-mini", "gpt-image-1.5", "gpt-image-2", "chatgpt-image-latest":
        return 10
    default:
        return modelID.hasPrefix("gpt-image-") ? 10 : 1
    }
}

func openAITranscriptionOptions(from extraBody: [String: JSONValue], providerID: String = "openai", providerRoot: String? = nil, modelID: String) -> [String: JSONValue] {
    var output = openAIProviderOptions(from: extraBody, providerID: providerID, providerRoot: providerRoot)
    let hadProviderOptions = !output.isEmpty
    openAIResponsesMoveKey("timestampGranularities", to: "timestamp_granularities", in: &output)
    openAIResponsesMoveKey("responseFormat", to: "response_format", in: &output)

    if modelID != "whisper-1", hadProviderOptions, output["response_format"] == nil {
        output["response_format"] = .string(openAITranscriptionUsesJSONResponseFormat(modelID) ? "json" : "verbose_json")
    }

    return output
}

func openAITranscriptionOptions(providerOptions: [String: JSONValue], extraBody: [String: JSONValue], providerID: String = "openai", providerRoot: String? = nil, modelID: String) throws -> [String: JSONValue] {
    var validatedProviderOptions = providerOptions
    for key in openAIProviderOptionNamespaceKeys(providerID: providerID, providerRoot: providerRoot) {
        guard var options = validatedProviderOptions[key]?.objectValue else { continue }
        for optionName in ["chunking_strategy", "chunkingStrategy"] {
            guard let chunkingStrategy = options[optionName] else { continue }
            options[optionName] = try openAIValidatedTranscriptionChunkingStrategy(
                chunkingStrategy,
                optionName: optionName
            )
        }
        validatedProviderOptions[key] = .object(options)
    }

    var output = openAIProviderOptions(providerOptions: validatedProviderOptions, extraBody: extraBody, providerID: providerID, providerRoot: providerRoot)
    let hadProviderOptions = !output.isEmpty
    openAIResponsesMoveKey("timestampGranularities", to: "timestamp_granularities", in: &output)
    openAIResponsesMoveKey("responseFormat", to: "response_format", in: &output)
    openAIResponsesMoveKey("chunkingStrategy", to: "chunking_strategy", in: &output)

    if hadProviderOptions {
        output["temperature"] = output["temperature"] ?? .number(0)
        output["timestamp_granularities"] = output["timestamp_granularities"] ?? .array([.string("segment")])
    }

    if modelID != "whisper-1", hadProviderOptions, output["response_format"] == nil {
        output["response_format"] = .string(openAITranscriptionDefaultResponseFormat(modelID))
    }
    if modelID == "gpt-4o-transcribe-diarize" {
        output["response_format"] = output["response_format"] ?? .string("diarized_json")
        output["chunking_strategy"] = output["chunking_strategy"] ?? .string("auto")
    }
    if let strategy = output["chunking_strategy"]?.objectValue {
        var mapped: [String: JSONValue] = [:]
        if let value = strategy["type"] { mapped["type"] = value }
        if let value = strategy["threshold"] { mapped["threshold"] = value }
        if let value = strategy["prefixPaddingMs"] ?? strategy["prefix_padding_ms"] { mapped["prefix_padding_ms"] = value }
        if let value = strategy["silenceDurationMs"] ?? strategy["silence_duration_ms"] { mapped["silence_duration_ms"] = value }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(JSONValue.object(mapped)),
           let string = String(data: data, encoding: .utf8) {
            output["chunking_strategy"] = .string(string)
        }
    }

    return output
}

func openAITranscriptionUsesJSONResponseFormat(_ modelID: String) -> Bool {
    modelID == "gpt-4o-transcribe" || modelID == "gpt-4o-mini-transcribe"
}

private func openAITranscriptionDefaultResponseFormat(_ modelID: String) -> String {
    if modelID == "gpt-4o-transcribe-diarize" { return "diarized_json" }
    return openAITranscriptionUsesJSONResponseFormat(modelID) ? "json" : "verbose_json"
}

private func openAIValidatedTranscriptionChunkingStrategy(
    _ value: JSONValue,
    optionName: String
) throws -> JSONValue {
    let argument = "providerOptions.openai.\(optionName)"
    if let string = value.stringValue {
        guard string == "auto" else {
            throw AIError.invalidArgument(
                argument: argument,
                message: "OpenAI chunkingStrategy must be auto or a server_vad object."
            )
        }
        return value
    }

    guard let strategy = value.objectValue else {
        throw AIError.invalidArgument(
            argument: argument,
            message: "OpenAI chunkingStrategy must be auto or a server_vad object."
        )
    }
    guard strategy["type"]?.stringValue == "server_vad" else {
        throw AIError.invalidArgument(
            argument: "\(argument).type",
            message: "OpenAI chunkingStrategy.type must be server_vad."
        )
    }

    var mapped: [String: JSONValue] = ["type": .string("server_vad")]
    if let threshold = strategy["threshold"] {
        guard let number = threshold.doubleValue,
              number.isFinite,
              (0...1).contains(number) else {
            throw AIError.invalidArgument(
                argument: "\(argument).threshold",
                message: "OpenAI chunkingStrategy.threshold must be a number between 0 and 1."
            )
        }
        mapped["threshold"] = .number(number)
    }
    for name in ["prefix_padding_ms", "prefixPaddingMs"] {
        guard let prefixPadding = strategy[name] else { continue }
        mapped["prefix_padding_ms"] = try openAIValidatedTranscriptionPadding(
            prefixPadding,
            argument: "\(argument).\(name)",
            displayName: "prefixPaddingMs"
        )
    }
    for name in ["silence_duration_ms", "silenceDurationMs"] {
        guard let silenceDuration = strategy[name] else { continue }
        mapped["silence_duration_ms"] = try openAIValidatedTranscriptionPadding(
            silenceDuration,
            argument: "\(argument).\(name)",
            displayName: "silenceDurationMs"
        )
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(JSONValue.object(mapped))
    guard let string = String(data: data, encoding: .utf8) else {
        throw AIError.invalidArgument(
            argument: argument,
            message: "OpenAI chunkingStrategy could not be encoded."
        )
    }
    return .string(string)
}

private func openAIValidatedTranscriptionPadding(
    _ value: JSONValue,
    argument: String,
    displayName: String
) throws -> JSONValue {
    guard let number = value.doubleValue,
          number.isFinite,
          number >= 0,
          number.rounded(.towardZero) == number else {
        throw AIError.invalidArgument(
            argument: argument,
            message: "OpenAI chunkingStrategy.\(displayName) must be a nonnegative integer."
        )
    }
    return .number(number)
}
