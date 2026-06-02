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
        let options = togetherAIProviderOptions(from: request)
        var warnings: [AIWarning] = []
        if request.mask != nil {
            throw AIError.invalidResponse(
                provider: providerID,
                message: "Together AI does not support mask-based image editing. Use FLUX Kontext models (e.g., black-forest-labs/FLUX.1-kontext-pro) with a reference image and descriptive prompt instead."
            )
        }
        if request.aspectRatio != nil {
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
        if let seed = request.seed {
            body["seed"] = .number(Double(seed))
        }
        if let count = request.count, count > 1 {
            body["n"] = .number(Double(count))
        }
        if let size = request.size {
            let dimensions = size.split(separator: "x").compactMap { Int($0) }
            if dimensions.count == 2 {
                body["width"] = .number(Double(dimensions[0]))
                body["height"] = .number(Double(dimensions[1]))
            }
        }
        if let imageURL = togetherAIImageURL(from: request.files.first) {
            body["image_url"] = .string(imageURL)
        }
        body.merge(togetherAIImageOptions(from: options)) { _, new in new }

        let response = try await config.sendJSONResponse(path: "/images/generations", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let base64Images = raw["data"]?.arrayValue?.compactMap { $0["b64_json"]?.stringValue } ?? []
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

private func togetherAIProviderOptions(from request: ImageGenerationRequest) -> [String: JSONValue] {
    togetherAIProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions)
}

private func togetherAIProviderOptions(from request: RerankingRequest) -> [String: JSONValue] {
    togetherAIProviderOptions(
        extraBody: request.extraBody,
        providerOptions: request.providerOptions,
        supportedProviderOptionKeys: togetherAIRerankingProviderOptionKeys
    )
}

private func togetherAIProviderOptions(
    extraBody: [String: JSONValue],
    providerOptions: [String: JSONValue],
    supportedProviderOptionKeys: Set<String>? = nil
) -> [String: JSONValue] {
    var output = togetherAIProviderOptions(from: extraBody)
    var scopedProviderOptions = togetherAIProviderOptions(fromProviderOptions: providerOptions)
    if let supportedProviderOptionKeys {
        scopedProviderOptions = scopedProviderOptions.filter { supportedProviderOptionKeys.contains($0.key) }
    }
    output.merge(scopedProviderOptions) { _, providerValue in providerValue }
    return output
}

private func togetherAIProviderOptions(fromProviderOptions providerOptions: [String: JSONValue]) -> [String: JSONValue] {
    if let nested = providerOptions["togetherai"]?.objectValue {
        return nested
    }
    if let nested = providerOptions["togetherAI"]?.objectValue {
        return nested
    }
    return [:]
}

private let togetherAIRerankingProviderOptionKeys: Set<String> = ["rankFields"]

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
    if let url = file.url {
        return url
    }
    guard let data = file.data else { return nil }
    return "data:\(file.mediaType ?? "application/octet-stream");base64,\(data.base64EncodedString())"
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
        let options = togetherAIProviderOptions(from: request)
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
        let results = raw["results"]?.arrayValue?.compactMap { item -> RerankedDocument? in
            guard let index = item["index"]?.intValue,
                  let score = item["relevance_score"]?.doubleValue ?? item["score"]?.doubleValue else {
                return nil
            }
            return RerankedDocument(index: index, score: score, document: item["document"]?.stringValue)
        } ?? []
        return RerankingResult(
            results: results,
            rawValue: raw,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}
