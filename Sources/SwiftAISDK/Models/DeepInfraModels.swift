import Foundation

public final class DeepInfraImageModel: ImageModel, @unchecked Sendable {
    public let providerID = "deepinfra.image"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        if let count = request.count, count > 1 {
            throw AIError.invalidArgument(argument: "count", message: "DeepInfra image models support at most 1 image per call.")
        }
        if !request.files.isEmpty {
            return try await editImage(request)
        }

        let options = deepInfraProviderOptions(from: request)
        var body: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let count = request.count { body["num_images"] = .number(Double(count)) }
        if let size = request.size {
            let dimensions = size.split(separator: "x", omittingEmptySubsequences: false)
            if let width = dimensions.first {
                body["width"] = .string(String(width))
            }
            if dimensions.count > 1 {
                body["height"] = .string(String(dimensions[1]))
            }
        }
        if let aspectRatio = request.aspectRatio { body["aspect_ratio"] = .string(aspectRatio) }
        if let seed = request.seed { body["seed"] = .number(Double(seed)) }
        body.merge(options) { _, new in new }

        let base = "\(deepInfraRootBaseURL(config.baseURL))/inference"
        let response = try await config.transport.send(AIHTTPRequest(
            method: "POST",
            url: try requireURL("\(base)/\(modelID)"),
            headers: config.headers
                .mergingHeaders(request.headers)
                .mergingHeaders(["content-type": "application/json"]),
            body: try encodeJSONBody(.object(body)),
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        let base64Images = raw["images"]?.arrayValue?.compactMap { image in
            image.stringValue?.replacingOccurrences(of: #"^data:image/\w+;base64,"#, with: "", options: .regularExpression)
        } ?? []
        return ImageGenerationResult(
            urls: [],
            base64Images: base64Images,
            rawValue: raw,
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: response, modelID: modelID)
        )
    }

    private func editImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        let options = deepInfraProviderOptions(from: request)
        var form = MultipartFormData()
        form.appendField(name: "model", value: modelID)
        form.appendField(name: "prompt", value: request.prompt)
        for file in request.files {
            let resolved = try await deepInfraResolveImageFile(file, transport: config.transport)
            form.appendFile(name: "image", fileName: resolved.fileName, mimeType: resolved.mediaType, data: resolved.data)
        }
        if let mask = request.mask {
            let resolved = try await deepInfraResolveImageFile(mask, transport: config.transport)
            form.appendFile(name: "mask", fileName: resolved.fileName, mimeType: resolved.mediaType, data: resolved.data)
        }
        if let count = request.count {
            form.appendField(name: "n", value: String(count))
        }
        if let size = request.size {
            form.appendField(name: "size", value: size)
        }
        for (key, value) in options {
            if case let .array(items) = value {
                for item in items {
                    if let scalar = jsonScalarString(item) {
                        form.appendField(name: key, value: scalar)
                    }
                }
            } else if let scalar = jsonScalarString(value) {
                form.appendField(name: key, value: scalar)
            }
        }

        let base = "\(deepInfraRootBaseURL(config.baseURL))/openai"
        let response = try await config.transport.send(AIHTTPRequest(
            method: "POST",
            url: try requireURL("\(base)/images/edits"),
            headers: config.headers
                .mergingHeaders(request.headers)
                .mergingHeaders(["content-type": "multipart/form-data; boundary=\(form.boundary)"]),
            body: form.finalize(),
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        let base64Images = raw["data"]?.arrayValue?.compactMap { $0["b64_json"]?.stringValue } ?? []
        return ImageGenerationResult(
            urls: [],
            base64Images: base64Images,
            rawValue: raw,
            requestMetadata: imageGenerationRequestMetadata(request),
            responseMetadata: aiResponseMetadata(from: raw, response: response, modelID: modelID)
        )
    }
}

private func deepInfraProviderOptions(from request: ImageGenerationRequest) -> [String: JSONValue] {
    var output = deepInfraProviderOptions(from: request.extraBody)
    if let nested = request.providerOptions["deepinfra"]?.objectValue {
        output.merge(nested) { _, providerValue in providerValue }
    }
    return output
}

private func deepInfraProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "deepinfra")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private struct DeepInfraResolvedImageFile {
    var data: Data
    var mediaType: String
    var fileName: String
}

private func deepInfraResolveImageFile(_ file: ImageInputFile, transport: AITransport) async throws -> DeepInfraResolvedImageFile {
    if let data = file.data {
        let mediaType = file.mediaType ?? "application/octet-stream"
        return DeepInfraResolvedImageFile(data: data, mediaType: mediaType, fileName: file.fileName ?? deepInfraDefaultFileName(mediaType: mediaType))
    }

    guard let url = file.url else {
        throw AIError.invalidResponse(provider: "deepinfra.image", message: "Image file must contain data or a URL.")
    }
    let response = try await downloadURL(url, transport: transport)
    guard (200..<300).contains(response.statusCode) else {
        throw httpStatusError(provider: "deepinfra.image", response: response)
    }
    let mediaType = file.mediaType
        ?? response.headers["content-type"]
        ?? response.headers["Content-Type"]
        ?? "application/octet-stream"
    return DeepInfraResolvedImageFile(data: response.body, mediaType: mediaType, fileName: file.fileName ?? deepInfraDefaultFileName(mediaType: mediaType))
}

private func deepInfraDefaultFileName(mediaType: String) -> String {
    switch mediaType {
    case "image/png": "image.png"
    case "image/jpeg", "image/jpg": "image.jpg"
    case "image/webp": "image.webp"
    default: "image"
    }
}
