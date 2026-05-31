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
        let options = quiverAIImageOptions(from: request.extraBody)
        let operation = options.operation ?? "generate"
        let body = try quiverAIRequestBody(modelID: modelID, request: request, options: options, operation: operation)
        let path = operation == "vectorize" ? "/svgs/vectorizations" : "/svgs/generations"

        let raw = try await config.sendJSON(path: path, modelID: modelID, body: .object(body), headers: request.headers)
        let base64Images = raw["data"]?.arrayValue?.compactMap { item -> String? in
            guard let svg = item["svg"]?.stringValue else { return nil }
            return Data(svg.utf8).base64EncodedString()
        } ?? []
        return ImageGenerationResult(urls: [], base64Images: base64Images, rawValue: raw)
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
            throw AIError.invalidArgument(argument: "files", message: "QuiverAI vectorize requires an input image.")
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
