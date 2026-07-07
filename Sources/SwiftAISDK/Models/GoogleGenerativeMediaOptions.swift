import Foundation

func googleImagenParameters(for request: ImageGenerationRequest, options: [String: JSONValue]) -> [String: JSONValue] {
    var parameters: [String: JSONValue] = ["sampleCount": .number(Double(request.count ?? 1))]
    if let aspectRatio = request.aspectRatio ?? options["aspectRatio"]?.stringValue ?? request.extraBody["aspectRatio"]?.stringValue {
        parameters["aspectRatio"] = .string(aspectRatio)
    } else {
        parameters["aspectRatio"] = .string("1:1")
    }
    parameters.merge(googleOptionsWithoutPoll(options, excluding: ["googleSearch", "edit", "aspectRatio"])) { _, new in new }
    return parameters
}

func googleImagenEditParameters(for request: ImageGenerationRequest, options: [String: JSONValue], edit: [String: JSONValue]) -> [String: JSONValue] {
    var parameters = googleImagenParameters(for: request, options: options)
    parameters["editMode"] = edit["mode"] ?? .string("EDIT_MODE_INPAINT_INSERTION")
    if let baseSteps = edit["baseSteps"] {
        parameters["editConfig"] = .object(["baseSteps": baseSteps])
    }
    return parameters
}

func googleImageProviderOptions(from request: ImageGenerationRequest) -> [String: JSONValue] {
    var options = googleImageProviderOptions(from: request.extraBody)
    if let google = request.providerOptions["google"]?.objectValue {
        options.merge(google) { _, new in new }
    }
    return options
}

func googleImageProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    if let google = extraBody["google"]?.objectValue {
        return google
    }
    return extraBody.filter { $0.key != "google" && $0.key != "googleVertex" && $0.key != "vertex" }
}

func googleImageEditBase64(_ file: ImageInputFile) throws -> String {
    if file.url != nil {
        throw AIError.invalidArgument(argument: "files", message: "URL-based images are not supported for Google Vertex image editing. Provide image data directly.")
    }
    guard let data = file.data else {
        throw AIError.invalidArgument(argument: "files", message: "Image file must contain data for Google Vertex image editing.")
    }
    return data.base64EncodedString()
}

func googleEmbeddingProviderOptions(from request: EmbeddingRequest) -> [String: JSONValue] {
    request.providerOptions["google"]?.objectValue ?? [:]
}

func googleEmbeddingParts(text: String, content: JSONValue?) -> [JSONValue] {
    let textPart: [JSONValue] = text.isEmpty ? [] : [.object(["text": .string(text)])]
    guard let content else {
        return textPart.isEmpty ? [.object(["text": .string(text)])] : textPart
    }
    if content == .null {
        return textPart.isEmpty ? [.object(["text": .string(text)])] : textPart
    }
    if let parts = content.arrayValue {
        return textPart + parts
    }
    return textPart.isEmpty ? [.object(["text": .string(text)])] : textPart
}

func googleVideoProviderOptions(from request: VideoGenerationRequest) -> [String: JSONValue] {
    var options = request.extraBody
    if let google = request.providerOptions["google"]?.objectValue {
        options.merge(google) { _, new in new }
    }
    return options
}

func googleSpeechProviderOptions(from request: SpeechRequest) -> [String: JSONValue] {
    var options = request.extraBody
    if let google = request.extraBody["google"]?.objectValue {
        options = google
    }
    if let google = request.providerOptions["google"]?.objectValue {
        options.merge(google) { _, new in new }
    }
    return options.filter { $0.key != "google" && $0.key != "googleVertex" && $0.key != "vertex" }
}

func googleVideoInstance(for request: VideoGenerationRequest, options: [String: JSONValue]) -> (instance: [String: JSONValue], warnings: [AIWarning]) {
    var instance: [String: JSONValue] = ["prompt": .string(request.prompt)]
    var warnings: [AIWarning] = []
    if let firstFrame = request.frameImages.first(where: { $0.frameType == .firstFrame }) {
        if let image = googleVideoInlineImage(firstFrame.image) {
            instance["image"] = image
        } else if firstFrame.image.url != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "URL-based image input",
                message: "Google Generative AI video models require base64-encoded images. URL will be ignored."
            ))
        }
    } else if let image = request.image {
        if image.url != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "URL-based image input",
                message: "Google Generative AI video models require base64-encoded images. URL will be ignored."
            ))
        } else if let image = googleVideoInlineImage(image) {
            instance["image"] = image
        }
    } else if let image = options["image"]?.objectValue {
        if let data = image["data"]?.stringValue {
            instance["image"] = .object([
                "inlineData": .object([
                    "mimeType": image["mimeType"] ?? .string("image/png"),
                    "data": .string(data)
                ])
            ])
        }
    }
    if let lastFrame = request.frameImages.first(where: { $0.frameType == .lastFrame }), let image = googleVideoInlineImage(lastFrame.image) {
        instance["lastFrame"] = image
    }
    if !request.inputReferences.isEmpty {
        let referenceImages = request.inputReferences.compactMap(googleVideoReferenceImage)
        if !referenceImages.isEmpty {
            instance["referenceImages"] = .array(referenceImages)
        }
    } else if let referenceImages = options["referenceImages"]?.arrayValue {
        instance["referenceImages"] = .array(referenceImages.map { reference in
            guard let object = reference.objectValue else { return reference }
            if let bytesBase64Encoded = object["bytesBase64Encoded"]?.stringValue {
                return .object([
                    "inlineData": .object([
                        "mimeType": .string("image/png"),
                        "data": .string(bytesBase64Encoded)
                    ])
                ])
            }
            if let gcsUri = object["gcsUri"] {
                return .object(["gcsUri": gcsUri])
            }
            return reference
        })
    }
    return (instance, warnings)
}

func googleVideoInlineImage(_ image: ImageInputFile) -> JSONValue? {
    guard let data = image.data else { return nil }
    return .object([
        "inlineData": .object([
            "mimeType": .string(image.mediaType ?? "image/png"),
            "data": .string(data.base64EncodedString())
        ])
    ])
}

func googleVideoReferenceImage(_ image: ImageInputFile) -> JSONValue? {
    guard let prepared = googleVideoInlineImage(image) else { return nil }
    return .object([
        "image": prepared,
        "referenceType": .string("asset")
    ])
}

func googleVideoParameters(for request: VideoGenerationRequest, options: [String: JSONValue]) -> [String: JSONValue] {
    var parameters: [String: JSONValue] = [:]
    if let count = request.count {
        parameters["sampleCount"] = .number(Double(count))
    } else if let sampleCount = options["sampleCount"] ?? options["n"] {
        parameters["sampleCount"] = sampleCount
    }
    if let aspectRatio = request.aspectRatio {
        parameters["aspectRatio"] = .string(aspectRatio)
    }
    if let resolution = request.resolution ?? options["resolution"]?.stringValue {
        parameters["resolution"] = .string(googleVideoResolution(resolution))
    }
    if let duration = request.durationSeconds {
        parameters["durationSeconds"] = .number(duration)
    }
    if let seed = request.seed {
        parameters["seed"] = .number(Double(seed))
    } else if let seed = options["seed"] {
        parameters["seed"] = seed
    }
    parameters.merge(googleOptionsWithoutPoll(options, excluding: ["sampleCount", "n", "resolution", "seed", "pollIntervalMs", "pollTimeoutMs", "image", "referenceImages"])) { _, new in new }
    return parameters
}

func googleOptionsWithoutPoll(_ options: [String: JSONValue], excluding keys: Set<String>) -> [String: JSONValue] {
    options.filter { !keys.contains($0.key) }
}

func googleAspectRatio(from request: ImageGenerationRequest) -> String? {
    if let aspectRatio = request.extraBody["aspectRatio"]?.stringValue {
        return aspectRatio
    }
    if let size = request.size, size.contains(":") {
        return size
    }
    return nil
}

func googleVideoResolution(_ resolution: String) -> String {
    switch resolution {
    case "1280x720":
        return "720p"
    case "1920x1080":
        return "1080p"
    case "3840x2160":
        return "4k"
    default:
        return resolution
    }
}

func googlePollTimeout(_ extraBody: [String: JSONValue]) -> UInt64 {
    let milliseconds = extraBody["pollTimeoutMs"]?.intValue ?? 600_000
    return UInt64(milliseconds) * 1_000_000
}

func googlePollInterval(_ extraBody: [String: JSONValue]) -> UInt64 {
    let milliseconds = extraBody["pollIntervalMs"]?.intValue ?? 10_000
    return UInt64(milliseconds) * 1_000_000
}
