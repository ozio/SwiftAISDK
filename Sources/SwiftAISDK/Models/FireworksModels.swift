import Foundation

public final class FireworksImageModel: ImageModel, @unchecked Sendable {
    public let providerID = "fireworks.image"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        let options = fireworksProviderOptions(from: request.extraBody)
        var body: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let count = request.count { body["samples"] = .number(Double(count)) }
        if let size = request.size {
            let dimensions = size.split(separator: "x").compactMap { Int($0) }
            if dimensions.count == 2 {
                body["width"] = .string(String(dimensions[0]))
                body["height"] = .string(String(dimensions[1]))
            } else {
                body["aspect_ratio"] = .string(size)
            }
        }
        if let inputImage = fireworksImageURL(from: request.files.first) {
            body["input_image"] = .string(inputImage)
        }
        body.merge(options) { _, new in new }

        switch fireworksURLFormat(modelID) {
        case "workflows_async":
            return try await generateAsync(body: body, headers: request.headers, abortSignal: request.abortSignal)
        default:
            let response = try await config.transport.send(AIHTTPRequest(
                method: "POST",
                url: try requireURL(fireworksURL(modelID: modelID, baseURL: config.baseURL)),
                headers: config.headers
                    .mergingHeaders(request.headers)
                    .mergingHeaders(["content-type": "application/json"]),
                body: try encodeJSONBody(.object(body)),
                abortSignal: request.abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            return ImageGenerationResult(urls: [], base64Images: [response.body.base64EncodedString()], rawValue: .object([
                "contentType": fireworksContentType(response.headers).map(JSONValue.string)
            ]))
        }
    }

    private func generateAsync(body: [String: JSONValue], headers requestHeaders: [String: String], abortSignal: AIAbortSignal?) async throws -> ImageGenerationResult {
        let submit = try await config.transport.send(AIHTTPRequest(
            method: "POST",
            url: try requireURL(fireworksURL(modelID: modelID, baseURL: config.baseURL)),
            headers: config.headers
                .mergingHeaders(requestHeaders)
                .mergingHeaders(["content-type": "application/json"]),
            body: try encodeJSONBody(.object(body)),
            abortSignal: abortSignal
        ))
        guard (200..<300).contains(submit.statusCode) else {
            throw httpStatusError(provider: providerID, response: submit)
        }
        let submitRaw = try submit.jsonValue()
        guard let requestID = submitRaw["request_id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Fireworks async image response did not contain request_id.")
        }
        let imageURL = try await pollAsyncImage(requestID: requestID, headers: requestHeaders, abortSignal: abortSignal)
        let imageResponse = try await downloadURL(imageURL, transport: config.transport, headers: config.headers.mergingHeaders(requestHeaders), abortSignal: abortSignal)
        guard (200..<300).contains(imageResponse.statusCode) else {
            throw httpStatusError(provider: providerID, response: imageResponse)
        }
        return ImageGenerationResult(urls: [imageURL], base64Images: [imageResponse.body.base64EncodedString()], rawValue: submitRaw)
    }

    private func pollAsyncImage(requestID: String, headers requestHeaders: [String: String], abortSignal: AIAbortSignal?) async throws -> String {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            let response = try await config.transport.send(AIHTTPRequest(
                method: "POST",
                url: try requireURL("\(withoutTrailingSlash(config.baseURL))/workflows/\(modelID)/get_result"),
                headers: config.headers
                    .mergingHeaders(requestHeaders)
                    .mergingHeaders(["content-type": "application/json"]),
                body: try encodeJSONBody(.object(["id": .string(requestID)])),
                abortSignal: abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            switch raw["status"]?.stringValue {
            case "Ready":
                guard let sample = raw["result"]?["sample"]?.stringValue else {
                    throw AIError.invalidResponse(provider: providerID, message: "Fireworks poll response was Ready but missing result.sample.")
                }
                return sample
            case "Error", "Failed":
                throw AIError.invalidResponse(provider: providerID, message: "Fireworks image generation failed.")
            default:
                if DispatchTime.now().uptimeNanoseconds - started > 120_000_000_000 {
                    throw AIError.invalidResponse(provider: providerID, message: "Fireworks image generation timed out.")
                }
                try await sleepWithAbortSignal(nanoseconds: 500_000_000, abortSignal: abortSignal)
            }
        }
    }
}

private func fireworksProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    if let nested = extraBody["fireworks"]?.objectValue {
        return nested
    }
    var output = extraBody
    output.removeValue(forKey: "fireworks")
    return output
}

private func fireworksImageURL(from file: ImageInputFile?) -> String? {
    guard let file else { return nil }
    if let url = file.url {
        return url
    }
    guard let data = file.data else { return nil }
    let mediaType = file.mediaType ?? "image/png"
    return "data:\(mediaType);base64,\(data.base64EncodedString())"
}

private func fireworksContentType(_ headers: [String: String]) -> String? {
    headers.first { $0.key.caseInsensitiveCompare("content-type") == .orderedSame }?.value
}

private func fireworksURL(modelID: String, baseURL: String) -> String {
    let base = withoutTrailingSlash(baseURL)
    switch fireworksURLFormat(modelID) {
    case "image_generation":
        return "\(base)/image_generation/\(modelID)"
    case "workflows_async":
        return "\(base)/workflows/\(modelID)"
    default:
        return "\(base)/workflows/\(modelID)/text_to_image"
    }
}

private func fireworksURLFormat(_ modelID: String) -> String {
    switch modelID {
    case "accounts/fireworks/models/playground-v2-5-1024px-aesthetic",
         "accounts/fireworks/models/japanese-stable-diffusion-xl",
         "accounts/fireworks/models/playground-v2-1024px-aesthetic",
         "accounts/fireworks/models/stable-diffusion-xl-1024-v1-0",
         "accounts/fireworks/models/SSD-1B":
        return "image_generation"
    case "accounts/fireworks/models/flux-kontext-pro",
         "accounts/fireworks/models/flux-kontext-max":
        return "workflows_async"
    default:
        return "workflows"
    }
}
