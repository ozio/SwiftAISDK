import Foundation

public final class TogetherAIImageModel: ImageModel, @unchecked Sendable {
    public let providerID = "togetherai.image"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        let options = try togetherAIProviderOptions(from: request)
        var warnings: [AIWarning] = []
        if request.mask != nil {
            throw AIError.invalidResponse(
                provider: providerID,
                message: "Together AI does not support mask-based image editing. Use FLUX Kontext models (e.g., black-forest-labs/FLUX.1-kontext-pro) with a reference image and descriptive prompt instead."
            )
        }
        if request.size != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "aspectRatio",
                message: "This model does not support the `aspectRatio` option. Use `size` instead."
            ))
        }
        if request.files.count > 1 {
            warnings.append(AIWarning(
                type: "other",
                message: "Together AI only supports a single input image. Additional images are ignored."
            ))
        }
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "prompt": .string(request.prompt),
            "response_format": .string("base64")
        ]
        if let count = request.count, count > 1 {
            body["n"] = .number(Double(count))
        }
        if let seed = request.seed {
            body["seed"] = .number(Double(seed))
        }
        if let size = request.size {
            let dimensions = size.split(separator: "x", omittingEmptySubsequences: false)
            body["width"] = togetherAIParseInt(dimensions.first.map(String.init))
            body["height"] = dimensions.count > 1 ? togetherAIParseInt(String(dimensions[1])) : .null
        }
        if let imageURL = togetherAIImageURL(from: request.files.first) {
            body["image_url"] = .string(imageURL)
        }
        body.merge(togetherAIImageOptions(from: options)) { _, new in new }

        let response = try await config.sendJSONResponse(path: "/images/generations", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        guard let data = raw["data"]?.arrayValue else {
            throw AIError.invalidResponse(provider: providerID, message: "TogetherAI image response did not contain data.")
        }
        let base64Images = data.compactMap { $0["b64_json"]?.stringValue }
        guard base64Images.count == data.count else {
            throw AIError.invalidResponse(provider: providerID, message: "TogetherAI image response contained invalid b64_json data.")
        }
        return ImageGenerationResult(
            urls: [],
            base64Images: base64Images,
            rawValue: raw,
            warnings: warnings,
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

private func togetherAIProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    if let nested = extraBody["togetherai"]?.objectValue {
        return nested
    }
    if let nested = extraBody["togetherAI"]?.objectValue {
        return nested
    }
    var output = extraBody
    output.removeValue(forKey: "togetherai")
    output.removeValue(forKey: "togetherAI")
    return output
}

private func togetherAIProviderOptions(from request: ImageGenerationRequest) throws -> [String: JSONValue] {
    try togetherAIProviderOptions(
        extraBody: request.extraBody,
        providerOptions: request.providerOptions,
        validateProviderOptions: togetherAIValidateImageProviderOptions
    )
}

private func togetherAIProviderOptions(from request: RerankingRequest) throws -> [String: JSONValue] {
    try togetherAIProviderOptions(
        extraBody: request.extraBody,
        providerOptions: request.providerOptions,
        supportedProviderOptionKeys: togetherAIRerankingProviderOptionKeys,
        validateProviderOptions: togetherAIValidateRerankingProviderOptions
    )
}

private func togetherAIProviderOptions(
    extraBody: [String: JSONValue],
    providerOptions: [String: JSONValue],
    supportedProviderOptionKeys: Set<String>? = nil,
    validateProviderOptions: ([String: JSONValue], String) throws -> [String: JSONValue]
) throws -> [String: JSONValue] {
    var output = togetherAIProviderOptions(from: extraBody)
    var scopedProviderOptions = try togetherAIProviderOptions(fromProviderOptions: providerOptions, validate: validateProviderOptions)
    if let supportedProviderOptionKeys {
        scopedProviderOptions = scopedProviderOptions.filter { supportedProviderOptionKeys.contains($0.key) }
    }
    output.merge(scopedProviderOptions) { _, providerValue in providerValue }
    return output
}

private func togetherAIProviderOptions(
    fromProviderOptions providerOptions: [String: JSONValue],
    validate: ([String: JSONValue], String) throws -> [String: JSONValue]
) throws -> [String: JSONValue] {
    if let value = providerOptions["togetherai"] {
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.togetherai", message: "TogetherAI provider options must be an object.")
        }
        return try validate(nested, "providerOptions.togetherai")
    }
    if let value = providerOptions["togetherAI"] {
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.togetherAI", message: "TogetherAI provider options must be an object.")
        }
        return try validate(nested, "providerOptions.togetherAI")
    }
    return [:]
}

private let togetherAIRerankingProviderOptionKeys: Set<String> = ["rankFields"]

private func togetherAIValidateImageProviderOptions(_ options: [String: JSONValue], argumentPrefix: String) throws -> [String: JSONValue] {
    for (key, value) in options {
        switch key {
        case "steps", "guidance":
            guard value == .null || value.doubleValue != nil else {
                throw AIError.invalidArgument(argument: "\(argumentPrefix).\(key)", message: "TogetherAI \(key) must be a number or null.")
            }
        case "negative_prompt":
            guard value == .null || value.stringValue != nil else {
                throw AIError.invalidArgument(argument: "\(argumentPrefix).negative_prompt", message: "TogetherAI negative_prompt must be a string or null.")
            }
        case "disable_safety_checker":
            guard value == .null || value.boolValue != nil else {
                throw AIError.invalidArgument(argument: "\(argumentPrefix).disable_safety_checker", message: "TogetherAI disable_safety_checker must be a boolean or null.")
            }
        default:
            break
        }
    }
    return options
}

private func togetherAIValidateRerankingProviderOptions(_ options: [String: JSONValue], argumentPrefix: String) throws -> [String: JSONValue] {
    if let rankFields = options["rankFields"] {
        guard let fields = rankFields.arrayValue else {
            throw AIError.invalidArgument(argument: "\(argumentPrefix).rankFields", message: "TogetherAI rankFields must be an array of strings.")
        }
        guard fields.allSatisfy({ $0.stringValue != nil }) else {
            throw AIError.invalidArgument(argument: "\(argumentPrefix).rankFields", message: "TogetherAI rankFields must be an array of strings.")
        }
    }
    return options
}

private func togetherAIImageOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var options: [String: JSONValue] = [:]
    for (key, value) in extraBody {
        switch key {
        case "negativePrompt":
            options["negative_prompt"] = value
        case "disableSafetyChecker":
            options["disable_safety_checker"] = value
        case "imageUrl", "imageURL":
            options["image_url"] = value
        default:
            options[key] = value
        }
    }
    return options
}

private func togetherAIImageURL(from file: ImageInputFile?) -> String? {
    guard let file else { return nil }
    return try? convertImageModelFileToDataURI(file)
}

private func togetherAIParseInt(_ value: String?) -> JSONValue {
    guard let value else { return .null }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    var output = ""
    for (index, character) in trimmed.enumerated() {
        if index == 0 && (character == "-" || character == "+") {
            output.append(character)
        } else if character.isNumber {
            output.append(character)
        } else {
            break
        }
    }
    guard output != "-" && output != "+", let number = Int(output) else { return .null }
    return .number(Double(number))
}

public final class TogetherAIRerankingModel: RerankingModel, @unchecked Sendable {
    public let providerID = "togetherai.reranking"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func rerank(_ request: RerankingRequest) async throws -> RerankingResult {
        let options = try togetherAIProviderOptions(from: request)
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "query": .string(request.query),
            "documents": .array(request.documentsJSON),
            "return_documents": .bool(false)
        ]
        if let topK = request.topK {
            body["top_n"] = .number(Double(topK))
        }
        for (key, value) in options {
            switch key {
            case "rankFields":
                body["rank_fields"] = value
            default:
                body[key] = value
            }
        }

        let response = try await config.sendJSONResponse(path: "/rerank", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        guard togetherAIRerankingUsageIsValid(raw["usage"]) else {
            throw AIError.invalidResponse(provider: providerID, message: "TogetherAI reranking response did not contain valid usage.")
        }
        guard let rawResults = raw["results"]?.arrayValue else {
            throw AIError.invalidResponse(provider: providerID, message: "TogetherAI reranking response did not contain results.")
        }
        let results = rawResults.compactMap { item -> RerankedDocument? in
            guard let index = item["index"]?.intValue,
                  let score = item["relevance_score"]?.doubleValue ?? item["score"]?.doubleValue else {
                return nil
            }
            return RerankedDocument(index: index, score: score, document: item["document"]?.stringValue)
        }
        guard results.count == rawResults.count else {
            throw AIError.invalidResponse(provider: providerID, message: "TogetherAI reranking response contained invalid results.")
        }
        return RerankingResult(
            results: results,
            rawValue: raw,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

private func togetherAIRerankingUsageIsValid(_ usage: JSONValue?) -> Bool {
    usage?["prompt_tokens"]?.doubleValue != nil &&
        usage?["completion_tokens"]?.doubleValue != nil &&
        usage?["total_tokens"]?.doubleValue != nil
}
