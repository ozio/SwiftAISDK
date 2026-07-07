import Foundation

func prodiaProviderOptions(from request: LanguageModelRequest) throws -> [String: JSONValue] {
    try prodiaProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions, validateProviderOptions: prodiaValidateLanguageProviderOptions)
}

func prodiaProviderOptions(from request: ImageGenerationRequest) throws -> [String: JSONValue] {
    try prodiaProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions, validateProviderOptions: prodiaValidateImageProviderOptions)
}

func prodiaProviderOptions(from request: VideoGenerationRequest) throws -> [String: JSONValue] {
    try prodiaProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions, validateProviderOptions: prodiaValidateVideoProviderOptions)
}

func prodiaProviderOptions(
    extraBody: [String: JSONValue],
    providerOptions: [String: JSONValue],
    validateProviderOptions: ([String: JSONValue]) throws -> [String: JSONValue]
) throws -> [String: JSONValue] {
    var output = prodiaProviderOptions(from: extraBody)
    if let value = providerOptions["prodia"] {
        guard value != .null else {
            return output
        }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.prodia", message: "Prodia provider options must be an object.")
        }
        output.merge(try validateProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

func prodiaProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    if let nested = extraBody["prodia"]?.objectValue {
        return nested
    }
    var output = extraBody
    output.removeValue(forKey: "prodia")
    return output
}

let prodiaLanguageProviderOptionKeys: Set<String> = [
    "aspectRatio"
]

let prodiaImageProviderOptionKeys: Set<String> = [
    "steps",
    "width",
    "height",
    "stylePreset",
    "loras",
    "progressive"
]

let prodiaVideoProviderOptionKeys: Set<String> = [
    "resolution"
]

let prodiaAspectRatios: Set<String> = [
    "1:1",
    "2:3",
    "3:2",
    "4:5",
    "5:4",
    "4:7",
    "7:4",
    "9:16",
    "16:9",
    "9:21",
    "21:9"
]

let prodiaStylePresets: Set<String> = [
    "3d-model",
    "analog-film",
    "anime",
    "cinematic",
    "comic-book",
    "digital-art",
    "enhance",
    "fantasy-art",
    "isometric",
    "line-art",
    "low-poly",
    "neon-punk",
    "origami",
    "photographic",
    "pixel-art",
    "texture",
    "craft-clay"
]

func prodiaValidateLanguageProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where prodiaLanguageProviderOptionKeys.contains(key) {
        switch key {
        case "aspectRatio":
            try prodiaRequireEnum(value, argument: "providerOptions.prodia.aspectRatio", label: "aspectRatio", allowed: prodiaAspectRatios)
            output[key] = value
        default:
            break
        }
    }
    return output
}

func prodiaValidateImageProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where prodiaImageProviderOptionKeys.contains(key) {
        switch key {
        case "steps":
            try prodiaRequireInteger(value, argument: "providerOptions.prodia.steps", label: "steps", min: 1, max: 4)
        case "width", "height":
            try prodiaRequireInteger(value, argument: "providerOptions.prodia.\(key)", label: key, min: 256, max: 1920)
        case "stylePreset":
            try prodiaRequireEnum(value, argument: "providerOptions.prodia.stylePreset", label: "stylePreset", allowed: prodiaStylePresets)
        case "loras":
            try prodiaRequireStringArray(value, argument: "providerOptions.prodia.loras", label: "loras", maxCount: 3)
        case "progressive":
            try prodiaRequireBoolean(value, argument: "providerOptions.prodia.progressive", label: "progressive")
        default:
            break
        }
        output[key] = value
    }
    return output
}

func prodiaValidateVideoProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where prodiaVideoProviderOptionKeys.contains(key) {
        switch key {
        case "resolution":
            try prodiaRequireString(value, argument: "providerOptions.prodia.resolution", label: "resolution")
            output[key] = value
        default:
            break
        }
    }
    return output
}

func prodiaRequireString(_ value: JSONValue, argument: String, label: String) throws {
    guard value.stringValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: "Prodia \(label) must be a string.")
    }
}

func prodiaRequireBoolean(_ value: JSONValue, argument: String, label: String) throws {
    guard value.boolValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: "Prodia \(label) must be a boolean.")
    }
}

func prodiaRequireInteger(_ value: JSONValue, argument: String, label: String, min: Int, max: Int) throws {
    guard let number = value.doubleValue, number.isFinite, number.rounded() == number else {
        throw AIError.invalidArgument(argument: argument, message: "Prodia \(label) must be an integer.")
    }
    if number < Double(min) || number > Double(max) {
        throw AIError.invalidArgument(argument: argument, message: "Prodia \(label) must be an integer between \(min) and \(max).")
    }
}

func prodiaRequireEnum(_ value: JSONValue, argument: String, label: String, allowed: Set<String>) throws {
    guard let string = value.stringValue, allowed.contains(string) else {
        throw AIError.invalidArgument(argument: argument, message: "Prodia \(label) must be one of \(allowed.sorted().joined(separator: ", ")).")
    }
}

func prodiaRequireStringArray(_ value: JSONValue, argument: String, label: String, maxCount: Int) throws {
    guard let array = value.arrayValue, array.allSatisfy({ $0.stringValue != nil }) else {
        throw AIError.invalidArgument(argument: argument, message: "Prodia \(label) must be an array of strings.")
    }
    guard array.count <= maxCount else {
        throw AIError.invalidArgument(argument: argument, message: "Prodia \(label) must contain at most \(maxCount) values.")
    }
}

func prodiaImageOptions(from options: [String: JSONValue]) -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    if let width = options["width"] { output["width"] = width }
    if let height = options["height"] { output["height"] = height }
    if let seed = options["seed"] { output["seed"] = seed }
    if let steps = options["steps"] { output["steps"] = steps }
    if let stylePreset = options["stylePreset"] ?? options["style_preset"] { output["style_preset"] = stylePreset }
    if let loras = options["loras"] { output["loras"] = loras }
    if let progressive = options["progressive"] { output["progressive"] = progressive }
    return output
}

func prodiaLanguageWarnings(for request: LanguageModelRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.temperature != nil { warnings.append(AIWarning(type: "unsupported", feature: "temperature")) }
    if request.topP != nil { warnings.append(AIWarning(type: "unsupported", feature: "topP")) }
    if request.topK != nil { warnings.append(AIWarning(type: "unsupported", feature: "topK")) }
    if request.maxOutputTokens != nil { warnings.append(AIWarning(type: "unsupported", feature: "maxOutputTokens")) }
    if !request.stopSequences.isEmpty { warnings.append(AIWarning(type: "unsupported", feature: "stopSequences")) }
    if request.presencePenalty != nil { warnings.append(AIWarning(type: "unsupported", feature: "presencePenalty")) }
    if request.frequencyPenalty != nil { warnings.append(AIWarning(type: "unsupported", feature: "frequencyPenalty")) }
    if !request.tools.isEmpty { warnings.append(AIWarning(type: "unsupported", feature: "tools")) }
    if request.toolChoice != nil { warnings.append(AIWarning(type: "unsupported", feature: "toolChoice")) }
    if case .json = request.responseFormat {
        warnings.append(AIWarning(type: "unsupported", feature: "responseFormat"))
    }
    if isCustomReasoning(request.reasoning) {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "reasoning",
            message: "This provider does not support reasoning configuration."
        ))
    }
    return warnings
}
