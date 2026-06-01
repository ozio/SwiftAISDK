import Foundation

public final class QuiverAIImageModel: ImageModel, @unchecked Sendable {
    public let providerID = "quiverai.image"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        let options = quiverAIImageOptions(from: request)
        let operation = options.operation ?? "generate"
        let body = try quiverAIRequestBody(modelID: modelID, request: request, options: options, operation: operation)
        let path = operation == "vectorize" ? "/svgs/vectorizations" : "/svgs/generations"
        let warnings = quiverAIWarnings(for: request)

        let response = try await config.sendJSONResponse(path: path, modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let base64Images = raw["data"]?.arrayValue?.compactMap { item -> String? in
            guard let svg = item["svg"]?.stringValue else { return nil }
            return Data(svg.utf8).base64EncodedString()
        } ?? []
        return ImageGenerationResult(
            urls: [],
            base64Images: base64Images,
            rawValue: raw,
            warnings: warnings,
            usage: tokenUsage(from: raw),
            providerMetadata: quiverAIProviderMetadata(from: raw),
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

private struct QuiverAIImageOptions {
    var operation: String?
    var instructions: JSONValue?
    var temperature: JSONValue?
    var topP: JSONValue?
    var presencePenalty: JSONValue?
    var maxOutputTokens: JSONValue?
    var autoCrop: JSONValue?
    var targetSize: JSONValue?
}

private func quiverAIImageOptions(from request: ImageGenerationRequest) -> QuiverAIImageOptions {
    quiverAIImageOptions(extraBody: request.extraBody, providerOptions: request.providerOptions)
}

private func quiverAIImageOptions(extraBody: [String: JSONValue], providerOptions: [String: JSONValue]) -> QuiverAIImageOptions {
    var output = quiverAIOptionsDictionary(from: extraBody)
    output.merge(quiverAIOptionsDictionary(from: providerOptions)) { _, providerValue in providerValue }
    return quiverAIImageOptions(from: output)
}

private func quiverAIOptionsDictionary(from options: [String: JSONValue]) -> [String: JSONValue] {
    if let nested = options["quiverai"]?.objectValue {
        return nested
    }
    var output = options
    output.removeValue(forKey: "quiverai")
    return output
}

private func quiverAIImageOptions(from extraBody: [String: JSONValue]) -> QuiverAIImageOptions {
    QuiverAIImageOptions(
        operation: extraBody["operation"]?.stringValue,
        instructions: extraBody["instructions"],
        temperature: extraBody["temperature"],
        topP: extraBody["topP"] ?? extraBody["top_p"],
        presencePenalty: extraBody["presencePenalty"] ?? extraBody["presence_penalty"],
        maxOutputTokens: extraBody["maxOutputTokens"] ?? extraBody["max_output_tokens"],
        autoCrop: extraBody["autoCrop"] ?? extraBody["auto_crop"],
        targetSize: extraBody["targetSize"] ?? extraBody["target_size"]
    )
}

private func quiverAIRequestBody(modelID: String, request: ImageGenerationRequest, options: QuiverAIImageOptions, operation: String) throws -> [String: JSONValue] {
    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "n": .number(Double(request.count ?? 1)),
        "stream": .bool(false)
    ]
    body["temperature"] = options.temperature
    body["top_p"] = options.topP
    body["presence_penalty"] = options.presencePenalty
    body["max_output_tokens"] = options.maxOutputTokens

    switch operation {
    case "generate":
        guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.invalidArgument(argument: "prompt", message: "QuiverAI image generation requires a non-empty prompt for generateImage.")
        }
        let maxReferences = modelID == "arrow-1.1-max" ? 16 : 4
        guard request.files.count <= maxReferences else {
            throw AIError.invalidArgument(argument: "files", message: "QuiverAI generate supports up to \(maxReferences) reference images for model \"\(modelID)\".")
        }
        body["prompt"] = .string(request.prompt)
        body["instructions"] = options.instructions
        if !request.files.isEmpty {
            body["references"] = .array(request.files.map(quiverAIImageReference))
        }
        return body

    case "vectorize":
        guard let file = request.files.first else {
            throw AIError.invalidArgument(argument: "files", message: "QuiverAI vectorize requires an input image. Pass an image in the generateImage prompt and set providerOptions.quiverai.operation to \"vectorize\".")
        }
        guard request.files.count == 1 else {
            throw AIError.invalidArgument(argument: "files", message: "QuiverAI vectorize accepts a single input image.")
        }
        body["image"] = quiverAIImageReference(file)
        body["auto_crop"] = options.autoCrop
        body["target_size"] = options.targetSize
        return body

    default:
        throw AIError.invalidArgument(argument: "operation", message: "QuiverAI operation must be \"generate\" or \"vectorize\".")
    }
}

private func quiverAIImageReference(_ file: ImageInputFile) -> JSONValue {
    if let url = file.url {
        return .object(["url": .string(url)])
    }
    return .object(["base64": .string(file.data?.base64EncodedString() ?? "")])
}

private func quiverAIWarnings(for request: ImageGenerationRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.size != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "size",
            message: "QuiverAI SVG generation does not support the `size` option. The setting was ignored."
        ))
    }
    if request.aspectRatio != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "aspectRatio",
            message: "QuiverAI SVG generation does not support the `aspectRatio` option. The setting was ignored."
        ))
    }
    if request.seed != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "seed",
            message: "QuiverAI SVG generation does not support the `seed` option. The setting was ignored."
        ))
    }
    if request.mask != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "mask",
            message: "QuiverAI SVG generation does not support masks. The mask was ignored."
        ))
    }
    return warnings
}

private func quiverAIProviderMetadata(from raw: JSONValue) -> [String: JSONValue] {
    let images = raw["data"]?.arrayValue?.enumerated().map { index, image in
        JSONValue.object([
            "index": .number(Double(index)),
            "mimeType": image["mime_type"] ?? .string("image/svg+xml")
        ])
    } ?? []
    return ["quiverai": .object(["images": .array(images)])]
}
