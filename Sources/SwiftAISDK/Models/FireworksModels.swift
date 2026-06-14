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
        let warnings = fireworksImageWarnings(for: request, modelID: modelID)
        let options = fireworksProviderOptions(from: request)
        var body: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let count = request.count { body["samples"] = .number(Double(count)) }
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
        if let inputImage = fireworksImageURL(from: request.files.first) {
            body["input_image"] = .string(inputImage)
        }
        body.merge(options) { _, new in new }

        switch fireworksURLFormat(modelID) {
        case "workflows_async":
            return try await generateAsync(request: request, body: body, warnings: warnings)
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
                throw apiCallError(provider: providerID, response: response)
            }
            let raw: JSONValue = .object([
                "contentType": fireworksContentType(response.headers).map(JSONValue.string)
            ])
            return ImageGenerationResult(
                urls: [],
                base64Images: [response.body.base64EncodedString()],
                rawValue: raw,
                warnings: warnings,
                requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
                responseMetadata: aiResponseMetadata(response: response, modelID: modelID)
            )
        }
    }

    private func generateAsync(request: ImageGenerationRequest, body: [String: JSONValue], warnings: [AIWarning]) async throws -> ImageGenerationResult {
        let submit = try await config.transport.send(AIHTTPRequest(
            method: "POST",
            url: try requireURL(fireworksURL(modelID: modelID, baseURL: config.baseURL)),
            headers: config.headers
                .mergingHeaders(request.headers)
                .mergingHeaders(["content-type": "application/json"]),
            body: try encodeJSONBody(.object(body)),
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(submit.statusCode) else {
            throw apiCallError(provider: providerID, response: submit)
        }
        let submitRaw = try submit.jsonValue()
        guard let requestID = submitRaw["request_id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Fireworks async image response did not contain request_id.")
        }
        let imageURL = try await pollAsyncImage(requestID: requestID, headers: request.headers, abortSignal: request.abortSignal)
        let imageHeaders = isSameOrigin(imageURL, config.baseURL) ? config.headers.mergingHeaders(request.headers) : [:]
        let imageResponse = try await downloadURL(imageURL, transport: config.transport, headers: imageHeaders, abortSignal: request.abortSignal)
        guard (200..<300).contains(imageResponse.statusCode) else {
            throw apiCallError(provider: providerID, response: imageResponse)
        }
        return ImageGenerationResult(
            urls: [imageURL],
            base64Images: [imageResponse.body.base64EncodedString()],
            rawValue: submitRaw,
            warnings: warnings,
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(response: imageResponse, modelID: modelID)
        )
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
                throw apiCallError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            switch raw["status"]?.stringValue {
            case "Ready":
                guard let sample = raw["result"]?["sample"]?.stringValue else {
                    throw AIError.invalidResponse(provider: providerID, message: "Fireworks poll response is Ready but missing result.sample.")
                }
                return sample
            case "Error", "Failed":
                let status = raw["status"]?.stringValue ?? "unknown"
                throw AIError.invalidResponse(provider: providerID, message: "Fireworks image generation failed with status: \(status)")
            default:
                if DispatchTime.now().uptimeNanoseconds - started > 120_000_000_000 {
                    throw AIError.invalidResponse(provider: providerID, message: "Fireworks image generation timed out after 120000ms")
                }
                try await sleepWithAbortSignal(nanoseconds: 500_000_000, abortSignal: abortSignal)
            }
        }
    }
}

private func fireworksProviderOptions(from request: ImageGenerationRequest) -> [String: JSONValue] {
    var output = fireworksProviderOptions(from: request.extraBody)
    if let nested = request.providerOptions["fireworks"]?.objectValue {
        output.merge(nested) { _, providerValue in providerValue }
    }
    return output
}

private func fireworksProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "fireworks")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func fireworksImageWarnings(for request: ImageGenerationRequest, modelID: String) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if !fireworksSupportsSize(modelID), request.size != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "size",
            message: "This model does not support the `size` option. Use `aspectRatio` instead."
        ))
    }
    if fireworksSupportsSize(modelID), request.aspectRatio != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "aspectRatio",
            message: "This model does not support the `aspectRatio` option."
        ))
    }
    if request.files.count > 1 {
        warnings.append(AIWarning(
            type: "other",
            message: "Fireworks only supports a single input image. Additional images are ignored."
        ))
    }
    if request.mask != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "mask",
            message: "Fireworks Kontext models do not support explicit masks. Use the prompt to describe the areas to edit."
        ))
    }
    return warnings
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

private func fireworksSupportsSize(_ modelID: String) -> Bool {
    fireworksURLFormat(modelID) == "image_generation"
}
