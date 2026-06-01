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
        if !request.files.isEmpty {
            return try await editImage(request)
        }

        let options = deepInfraProviderOptions(from: request.extraBody)
        var body: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let count = request.count { body["num_images"] = .number(Double(count)) }
        if let size = request.size {
            let dimensions = size.split(separator: "x").compactMap { Int($0) }
            if dimensions.count == 2 {
                body["width"] = .string(String(dimensions[0]))
                body["height"] = .string(String(dimensions[1]))
            } else {
                body["aspect_ratio"] = .string(size)
            }
        }
        body.merge(options) { _, new in new }

        let base = withoutTrailingSlash(config.baseURL)
            .replacingOccurrences(of: "/openai", with: "/inference")
        let response = try await config.transport.send(AIHTTPRequest(
            method: "POST",
            url: try requireURL("\(base)/\(modelID)"),
            headers: config.headers
                .mergingHeaders(request.headers)
                .mergingHeaders(["content-type": "application/json"]),
            body: try encodeJSONBody(.object(body))
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        let base64Images = raw["images"]?.arrayValue?.compactMap { image in
            image.stringValue?.replacingOccurrences(of: #"^data:image/\w+;base64,"#, with: "", options: .regularExpression)
        } ?? []
        return ImageGenerationResult(urls: [], base64Images: base64Images, rawValue: raw)
    }

    private func editImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        let options = deepInfraProviderOptions(from: request.extraBody)
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

        let base = withoutTrailingSlash(config.baseURL)
            .replacingOccurrences(of: "/inference", with: "/openai")
        let response = try await config.transport.send(AIHTTPRequest(
            method: "POST",
            url: try requireURL("\(base)/images/edits"),
            headers: config.headers
                .mergingHeaders(request.headers)
                .mergingHeaders(["content-type": "multipart/form-data; boundary=\(form.boundary)"]),
            body: form.finalize()
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        let base64Images = raw["data"]?.arrayValue?.compactMap { $0["b64_json"]?.stringValue } ?? []
        return ImageGenerationResult(urls: [], base64Images: base64Images, rawValue: raw)
    }
}

private func deepInfraProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    if let nested = extraBody["deepinfra"]?.objectValue {
        return nested
    }
    var output = extraBody
    output.removeValue(forKey: "deepinfra")
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
