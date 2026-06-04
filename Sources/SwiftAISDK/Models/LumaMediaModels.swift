import Foundation

public final class LumaImageModel: ImageModel, @unchecked Sendable {
    public let providerID = "luma.image"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        let options = try lumaProviderOptions(from: request)
        var warnings: [AIWarning] = []
        var body: [String: JSONValue] = [
            "prompt": .string(request.prompt),
            "model": .string(modelID)
        ]
        if request.seed != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "seed",
                message: "This model does not support the `seed` option."
            ))
        }
        if request.size != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "size",
                message: "This model does not support the `size` option. Use `aspectRatio` instead."
            ))
        }
        if let aspectRatio = request.aspectRatio {
            body["aspect_ratio"] = .string(aspectRatio)
        } else if let aspectRatio = options.extraAspectRatio {
            body["aspect_ratio"] = aspectRatio
        }
        body.merge(try lumaOptions(from: options, files: request.files, mask: request.mask)) { _, new in new }
        let submitResponse = try await config.transport.send(config.request(path: "/dream-machine/v1/generations/image", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal))
        guard (200..<300).contains(submitResponse.statusCode) else {
            throw lumaHTTPStatusError(provider: providerID, response: submitResponse)
        }
        let submitted = (json: try submitResponse.jsonValue(), response: submitResponse)
        guard let id = submitted.json["id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Luma submit response did not contain id.")
        }
        let finalResponse = try await pollLuma(
            id: id,
            headers: request.headers,
            intervalNanoseconds: lumaPollInterval(options.pollIntervalMillis),
            maxAttempts: lumaMaxPollAttempts(options.maxPollAttempts),
            abortSignal: request.abortSignal
        )
        let raw = finalResponse.raw
        guard let url = raw["assets"]?["image"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Image generation completed but no image was found.")
        }
        let image = try await downloadURL(url, transport: config.transport, abortSignal: request.abortSignal)
        guard (200..<300).contains(image.statusCode) else {
            throw httpStatusError(provider: providerID, response: image)
        }
        return ImageGenerationResult(
            urls: [url],
            base64Images: [image.body.base64EncodedString()],
            rawValue: raw,
            warnings: warnings,
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: submitted.response, modelID: modelID)
        )
    }

    private func pollLuma(id: String, headers: [String: String], intervalNanoseconds: UInt64, maxAttempts: Int, abortSignal: AIAbortSignal?) async throws -> (raw: JSONValue, response: AIHTTPResponse) {
        for _ in 0..<maxAttempts {
            let response = try await config.transport.send(AIHTTPRequest(
                method: "GET",
                url: try requireURL("\(withoutTrailingSlash(config.baseURL))/dream-machine/v1/generations/\(id)"),
                headers: config.headers.mergingHeaders(headers),
                abortSignal: abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw lumaHTTPStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            switch raw["state"]?.stringValue {
            case "completed":
                return (raw, response)
            case "failed":
                throw AIError.invalidResponse(provider: providerID, message: "Image generation failed.")
            default:
                try await sleepWithAbortSignal(nanoseconds: intervalNanoseconds, abortSignal: abortSignal)
            }
        }
        throw AIError.invalidResponse(provider: providerID, message: "Image generation timed out after 120 attempts.")
    }
}

private struct LumaResolvedOptions {
    var requestOptions: [String: JSONValue]
    var extraAspectRatio: JSONValue?
    var referenceType: String?
    var imageConfigs: [JSONValue]
    var pollIntervalMillis: JSONValue?
    var maxPollAttempts: JSONValue?
}

private func lumaOptions(from options: LumaResolvedOptions, files: [ImageInputFile], mask: ImageInputFile?) throws -> [String: JSONValue] {
    if mask != nil {
        throw AIError.invalidArgument(argument: "mask", message: "Luma AI does not support mask-based image editing.")
    }
    var output = options.requestOptions
    let referenceType = options.referenceType ?? "image"
    let images = try lumaReferenceImages(from: files, imageConfigs: options.imageConfigs)
    guard !images.isEmpty else { return output }

    switch referenceType {
    case "image":
        guard images.count <= 4 else {
            throw AIError.invalidArgument(argument: "files", message: "Luma AI image supports up to 4 reference images.")
        }
        output["image"] = .array(images.map { lumaWeightedURL($0, defaultWeight: 0.85) })
    case "style":
        output["style"] = .array(images.map { lumaWeightedURL($0, defaultWeight: 0.8) })
    case "character":
        output["character"] = try lumaCharacterReference(images)
    case "modify_image":
        guard images.count == 1 else {
            throw AIError.invalidArgument(argument: "files", message: "Luma AI modify_image only supports a single input image.")
        }
        output["modify_image"] = lumaWeightedURL(images[0], defaultWeight: 1.0)
    default:
        throw AIError.invalidArgument(argument: "referenceType", message: "Luma AI referenceType must be one of image, style, character, modify_image.")
    }

    return output
}

private func lumaProviderOptions(from request: ImageGenerationRequest) throws -> LumaResolvedOptions {
    var extraOptions = lumaProviderOptions(from: request.extraBody)
    let extraAspectRatio = extraOptions["aspectRatio"] ?? extraOptions["aspect_ratio"]
    extraOptions.removeValue(forKey: "aspectRatio")
    extraOptions.removeValue(forKey: "aspect_ratio")

    var resolved = LumaResolvedOptions(
        requestOptions: extraOptions,
        extraAspectRatio: extraAspectRatio,
        referenceType: extraOptions.removeValue(forKey: "referenceType")?.stringValue,
        imageConfigs: extraOptions.removeValue(forKey: "images")?.arrayValue ?? [],
        pollIntervalMillis: extraOptions.removeValue(forKey: "pollIntervalMillis"),
        maxPollAttempts: extraOptions.removeValue(forKey: "maxPollAttempts")
    )
    resolved.requestOptions = extraOptions

    guard let providerValue = request.providerOptions["luma"] else {
        return resolved
    }
    guard providerValue != .null else {
        return resolved
    }
    guard let providerOptions = providerValue.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.luma", message: "Luma provider options must be an object.")
    }

    let parsedProviderOptions = try lumaValidatedProviderOptions(from: providerOptions)
    resolved.requestOptions.merge(parsedProviderOptions.requestOptions) { _, providerValue in providerValue }
    if parsedProviderOptions.hasReferenceType {
        resolved.referenceType = parsedProviderOptions.referenceType
    }
    if parsedProviderOptions.hasImages {
        resolved.imageConfigs = parsedProviderOptions.imageConfigs
    }
    if parsedProviderOptions.hasPollIntervalMillis {
        resolved.pollIntervalMillis = parsedProviderOptions.pollIntervalMillis
    }
    if parsedProviderOptions.hasMaxPollAttempts {
        resolved.maxPollAttempts = parsedProviderOptions.maxPollAttempts
    }
    return resolved
}

private func lumaProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    extraBody["luma"]?.objectValue ?? extraBody.filter { key, _ in key != "luma" }
}

private struct LumaParsedProviderOptions {
    var requestOptions: [String: JSONValue]
    var hasReferenceType = false
    var referenceType: String?
    var hasImages = false
    var imageConfigs: [JSONValue] = []
    var hasPollIntervalMillis = false
    var pollIntervalMillis: JSONValue?
    var hasMaxPollAttempts = false
    var maxPollAttempts: JSONValue?
}

private func lumaValidatedProviderOptions(from providerOptions: [String: JSONValue]) throws -> LumaParsedProviderOptions {
    var output = LumaParsedProviderOptions(requestOptions: providerOptions)
    if let referenceType = providerOptions["referenceType"] {
        output.hasReferenceType = true
        output.requestOptions.removeValue(forKey: "referenceType")
        if referenceType != .null {
            guard let value = referenceType.stringValue,
                  ["image", "style", "character", "modify_image"].contains(value) else {
                throw AIError.invalidArgument(argument: "providerOptions.luma.referenceType", message: "Luma referenceType must be one of image, style, character, modify_image.")
            }
            output.referenceType = value
        }
    }
    if let images = providerOptions["images"] {
        output.hasImages = true
        output.requestOptions.removeValue(forKey: "images")
        if images != .null {
            guard let array = images.arrayValue else {
                throw AIError.invalidArgument(argument: "providerOptions.luma.images", message: "Luma images provider option must be an array.")
            }
            output.imageConfigs = try array.enumerated().map { index, value in
                guard let object = value.objectValue else {
                    throw AIError.invalidArgument(argument: "providerOptions.luma.images", message: "Luma images[\(index)] must be an object.")
                }
                var config: [String: JSONValue] = [:]
                if let weight = object["weight"], weight != .null {
                    guard let number = weight.doubleValue, number >= 0, number <= 1 else {
                        throw AIError.invalidArgument(argument: "providerOptions.luma.images[\(index)].weight", message: "Luma image weight must be a number between 0 and 1.")
                    }
                    config["weight"] = weight
                }
                if let id = object["id"], id != .null {
                    guard id.stringValue != nil else {
                        throw AIError.invalidArgument(argument: "providerOptions.luma.images[\(index)].id", message: "Luma image id must be a string.")
                    }
                    config["id"] = id
                }
                return .object(config)
            }
        }
    }
    if let pollIntervalMillis = providerOptions["pollIntervalMillis"] {
        output.hasPollIntervalMillis = true
        output.requestOptions.removeValue(forKey: "pollIntervalMillis")
        if pollIntervalMillis != .null {
            guard pollIntervalMillis.doubleValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.luma.pollIntervalMillis", message: "Luma pollIntervalMillis must be a number.")
            }
            output.pollIntervalMillis = pollIntervalMillis
        }
    }
    if let maxPollAttempts = providerOptions["maxPollAttempts"] {
        output.hasMaxPollAttempts = true
        output.requestOptions.removeValue(forKey: "maxPollAttempts")
        if maxPollAttempts != .null {
            guard maxPollAttempts.doubleValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.luma.maxPollAttempts", message: "Luma maxPollAttempts must be a number.")
            }
            output.maxPollAttempts = maxPollAttempts
        }
    }
    return output
}

private func lumaReferenceImages(from files: [ImageInputFile], imageConfigs: [JSONValue]) throws -> [JSONValue] {
    guard !files.isEmpty else { return [] }
    return try files.enumerated().map { index, file in
        guard let url = file.url else {
            throw AIError.invalidArgument(argument: "files", message: "Luma AI only supports URL-based images.")
        }
        var object: [String: JSONValue] = ["url": .string(url)]
        if imageConfigs.indices.contains(index), let config = imageConfigs[index].objectValue {
            if let weight = config["weight"], weight != .null { object["weight"] = weight }
            if let id = config["id"], id != .null { object["id"] = id }
        }
        return .object(object)
    }
}

private func lumaWeightedURL(_ value: JSONValue, defaultWeight: Double) -> JSONValue {
    guard var object = value.objectValue else { return value }
    if object["weight"]?.doubleValue == nil {
        object["weight"] = .number(defaultWeight)
    }
    return .object(object.filter { $0.key == "url" || $0.key == "weight" })
}

private func lumaCharacterReference(_ images: [JSONValue]) throws -> JSONValue {
    var identities: [String: [JSONValue]] = [:]
    for image in images {
        guard let object = image.objectValue,
              let url = object["url"] else { continue }
        let id = object["id"]?.stringValue ?? "identity0"
        identities[id, default: []].append(url)
    }
    for (id, urls) in identities where urls.count > 4 {
        throw AIError.invalidArgument(argument: "files", message: "Luma AI character supports up to 4 images per identity. Identity '\(id)' has \(urls.count) images.")
    }
    return .object(identities.mapValues { .object(["images": .array($0)]) })
}

private func lumaPollInterval(_ value: JSONValue?) -> UInt64 {
    let milliseconds = value?.doubleValue ?? 500
    return UInt64(max(milliseconds, 0)) * 1_000_000
}

private func lumaMaxPollAttempts(_ value: JSONValue?) -> Int {
    guard let attempts = value?.doubleValue else { return 120 }
    return max(Int(attempts.rounded(.up)), 0)
}

private func lumaHTTPStatusError(provider: String, response: AIHTTPResponse) -> AIError {
    let body = lumaErrorMessage(from: response.body) ?? response.bodyText
    guard !response.headers.isEmpty else {
        return .httpStatus(provider: provider, statusCode: response.statusCode, body: body)
    }
    return .httpStatusWithHeaders(provider: provider, statusCode: response.statusCode, body: body, headers: response.headers)
}

private func lumaErrorMessage(from data: Data) -> String? {
    guard let json = try? decodeJSONBody(data),
          let details = json["detail"]?.arrayValue,
          let first = details.first?.objectValue else {
        return nil
    }
    return first["msg"]?.stringValue
}

