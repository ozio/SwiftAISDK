import Foundation

public final class FalImageModel: ImageModel, @unchecked Sendable {
    public let providerID = "fal.image"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        var body: [String: JSONValue] = ["prompt": .string(request.prompt)]
        let options = try falProviderOptions(from: request)
        if let size = request.size {
            body["image_size"] = falImageSize(size)
        } else if let aspectRatio = request.aspectRatio
            ?? options["aspectRatio"]?.stringValue
            ?? options["aspect_ratio"]?.stringValue {
            body["image_size"] = falImageSize(aspectRatio)
        }
        if let seed = request.seed { body["seed"] = .number(Double(seed)) }
        if let count = request.count { body["num_images"] = .number(Double(count)) }
        let preparedInputs = try falImageInputs(from: request.files, mask: request.mask, useMultipleImages: options["useMultipleImages"]?.boolValue == true)
        body.merge(preparedInputs.input) { _, new in new }
        body.merge(falImageOptions(from: options)) { _, new in new }
        let warnings = preparedInputs.warnings + falDeprecatedImageOptionWarnings(from: options)

        let response = try await config.sendJSONResponse(path: "/\(modelID)", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let urls = falImageURLs(from: raw)
        let base64Images = try await downloadFalImages(urls: urls, abortSignal: request.abortSignal)
        return ImageGenerationResult(
            urls: urls,
            base64Images: base64Images,
            rawValue: raw,
            warnings: warnings,
            providerMetadata: falImageProviderMetadata(from: raw),
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    private func downloadFalImages(urls: [String], abortSignal: AIAbortSignal?) async throws -> [String] {
        var images: [String] = []
        for url in urls {
            let response = try await downloadURL(url, transport: config.transport, abortSignal: abortSignal)
            guard (200..<300).contains(response.statusCode) else {
                throw apiCallError(provider: providerID, response: response)
            }
            images.append(response.body.base64EncodedString())
        }
        return images
    }
}

public final class FalVideoModel: VideoModel, @unchecked Sendable {
    public let providerID = "fal.video"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        let options = try falProviderOptions(from: request)
        var body: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let aspectRatio = request.aspectRatio { body["aspect_ratio"] = .string(aspectRatio) }
        if let durationSeconds = request.durationSeconds { body["duration"] = .string("\(formatDuration(durationSeconds))s") }
        if let seed = request.seed { body["seed"] = .number(Double(seed)) }
        if let imageInput = try falVideoImageInput(from: request, options: options) {
            body["image_url"] = imageInput
        }
        body.merge(falVideoOptions(from: options)) { _, new in new }

        let normalized = modelID.replacingOccurrences(of: #"^(fal-ai/|fal/)"#, with: "", options: .regularExpression)
        let submitURL = "https://queue.fal.run/fal-ai/\(normalized)"
        let queueResponse = try await config.transport.send(config.request(
            path: "/fal-ai/\(normalized)",
            modelID: modelID,
            body: .object(body),
            headers: request.headers,
            abortSignal: request.abortSignal
        ).withURL(try requireURL(submitURL)))
        guard (200..<300).contains(queueResponse.statusCode) else {
            throw apiCallError(provider: providerID, response: queueResponse)
        }
        let queued = try queueResponse.jsonValue()
        guard let responseURL = queued["response_url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Fal queue response did not contain response_url.")
        }
        let finalResponse = try await pollFalResponse(
            url: responseURL,
            submitURL: submitURL,
            headers: request.headers,
            intervalNanoseconds: falPollInterval(options),
            timeoutNanoseconds: falPollTimeout(options),
            abortSignal: request.abortSignal
        )
        let raw = finalResponse.json
        guard let videoURL = raw["video"]?["url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Fal response did not contain video.url.")
        }
        return VideoGenerationResult(
            urls: [videoURL],
            operationID: queued["request_id"]?.stringValue,
            rawValue: raw,
            providerMetadata: falVideoProviderMetadata(from: raw),
            requestMetadata: videoGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: finalResponse.response, modelID: modelID)
        )
    }

    private func pollFalResponse(url: String, submitURL: String, headers: [String: String], intervalNanoseconds: UInt64, timeoutNanoseconds: UInt64, abortSignal: AIAbortSignal?) async throws -> (json: JSONValue, response: AIHTTPResponse) {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            let pollHeaders = isSameOrigin(url, submitURL) ? config.headers.mergingHeaders(headers) : [:]
            let response = try await downloadURL(url, transport: config.transport, headers: pollHeaders, abortSignal: abortSignal)
            if (200..<300).contains(response.statusCode) {
                return (try response.jsonValue(), response)
            }
            if !falIsInProgress(response) {
                throw apiCallError(provider: providerID, response: response)
            }
            if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                throw AIError.invalidResponse(provider: providerID, message: "Fal video generation timed out.")
            }
            try await sleepWithAbortSignal(nanoseconds: intervalNanoseconds, abortSignal: abortSignal)
        }
    }
}

private func falImageURLs(from raw: JSONValue) -> [String] {
    if let images = raw["images"]?.arrayValue {
        return images.compactMap { $0["url"]?.stringValue }
    }
    if let image = raw["image"]?["url"]?.stringValue {
        return [image]
    }
    return []
}

private func falImageProviderMetadata(from raw: JSONValue) -> [String: JSONValue] {
    var fal: [String: JSONValue] = [:]
    let images = falImageMetadataObjects(from: raw)
    if !images.isEmpty {
        fal["images"] = .array(images.map(JSONValue.object))
    }
    for (key, value) in raw.objectValue ?? [:] {
        guard !["image", "images", "prompt", "has_nsfw_concepts", "nsfw_content_detected"].contains(key) else { continue }
        fal[falMetadataKey(key)] = value
    }
    return fal.isEmpty ? [:] : ["fal": .object(fal)]
}

private func falImageMetadataObjects(from raw: JSONValue) -> [[String: JSONValue]] {
    if let images = raw["images"]?.arrayValue {
        return images.enumerated().compactMap { index, image in
            falSingleImageMetadata(from: image, index: index, raw: raw)
        }
    }
    if let image = raw["image"], image.objectValue != nil {
        return [falSingleImageMetadata(from: image, index: 0, raw: raw)].compactMap { $0 }
    }
    return []
}

private func falSingleImageMetadata(from image: JSONValue, index: Int, raw: JSONValue) -> [String: JSONValue]? {
    guard let object = image.objectValue else { return nil }
    var metadata: [String: JSONValue] = [:]
    for (key, value) in object where key != "url" {
        metadata[falMetadataKey(key)] = value
    }
    if let nsfw = raw["has_nsfw_concepts"]?[index]?.boolValue
        ?? raw["nsfw_content_detected"]?[index]?.boolValue {
        metadata["nsfw"] = .bool(nsfw)
    }
    return metadata.isEmpty ? nil : metadata
}

private func falVideoProviderMetadata(from raw: JSONValue) -> [String: JSONValue] {
    var fal: [String: JSONValue] = [:]
    if let video = raw["video"], let object = video.objectValue {
        var metadata: [String: JSONValue] = [:]
        for (key, value) in object {
            metadata[falMetadataKey(key)] = value
        }
        if !metadata.isEmpty {
            fal["videos"] = .array([.object(metadata)])
        }
    }
    for (key, value) in raw.objectValue ?? [:] {
        guard key != "video" else { continue }
        fal[falMetadataKey(key)] = value
    }
    return fal.isEmpty ? [:] : ["fal": .object(fal)]
}

private func falMetadataKey(_ key: String) -> String {
    switch key {
    case "content_type":
        return "contentType"
    case "file_name":
        return "fileName"
    case "file_data":
        return "fileData"
    case "file_size":
        return "fileSize"
    case "has_nsfw_concepts":
        return "hasNsfwConcepts"
    case "num_inference_steps":
        return "numInferenceSteps"
    default:
        return key
    }
}

private func falImageOptions(from options: [String: JSONValue]) -> [String: JSONValue] {
    var output = options
    falMoveKey("imageUrl", to: "image_url", in: &output)
    falMoveKey("maskUrl", to: "mask_url", in: &output)
    falMoveKey("guidanceScale", to: "guidance_scale", in: &output)
    falMoveKey("numInferenceSteps", to: "num_inference_steps", in: &output)
    falMoveKey("enableSafetyChecker", to: "enable_safety_checker", in: &output)
    falMoveKey("outputFormat", to: "output_format", in: &output)
    falMoveKey("syncMode", to: "sync_mode", in: &output)
    falMoveKey("safetyTolerance", to: "safety_tolerance", in: &output)
    output.removeValue(forKey: "aspectRatio")
    output.removeValue(forKey: "aspect_ratio")
    output.removeValue(forKey: "useMultipleImages")
    output.removeValue(forKey: "__deprecatedKeys")
    output.removeValue(forKey: "fal")
    return output
}

private func falVideoOptions(from options: [String: JSONValue]) -> [String: JSONValue] {
    var output = options
    falMoveKey("motionStrength", to: "motion_strength", in: &output)
    falMoveKey("negativePrompt", to: "negative_prompt", in: &output)
    falMoveKey("promptOptimizer", to: "prompt_optimizer", in: &output)
    falMoveKey("imageUrl", to: "image_url", in: &output)
    for key in falVideoNullishProviderOptionKeys where output[key] == .null {
        output.removeValue(forKey: key)
    }
    output.removeValue(forKey: "pollIntervalMs")
    output.removeValue(forKey: "pollTimeoutMs")
    output.removeValue(forKey: "poll_interval_ms")
    output.removeValue(forKey: "poll_timeout_ms")
    output.removeValue(forKey: "image")
    output.removeValue(forKey: "image_url")
    output.removeValue(forKey: "imageUrl")
    return output
}

private func falMoveKey(_ source: String, to destination: String, in values: inout [String: JSONValue]) {
    if let value = values.removeValue(forKey: source) {
        values[destination] = value
    }
}

private func falDeprecatedImageOptionWarnings(from options: [String: JSONValue]) -> [AIWarning] {
    let deprecatedKeys: [(snake: String, camel: String)] = falDeprecatedImageOptionKeys.filter { options[$0.snake] != nil && options[$0.snake] != .null }
    guard !deprecatedKeys.isEmpty else { return [] }
    let replacements = deprecatedKeys
        .map { "'\($0.snake)' (use '\($0.camel)')" }
        .joined(separator: ", ")
    return [
        AIWarning(
            type: "other",
            message: "The following provider options use deprecated snake_case and will be removed in @ai-sdk/fal v2.0. Please use camelCase instead: \(replacements)"
        )
    ]
}

private let falDeprecatedImageOptionKeys: [(snake: String, camel: String)] = [
    ("image_url", "imageUrl"),
    ("mask_url", "maskUrl"),
    ("guidance_scale", "guidanceScale"),
    ("num_inference_steps", "numInferenceSteps"),
    ("enable_safety_checker", "enableSafetyChecker"),
    ("output_format", "outputFormat"),
    ("sync_mode", "syncMode"),
    ("safety_tolerance", "safetyTolerance")
]

private let falVideoNullishProviderOptionKeys: Set<String> = [
    "loop",
    "motionStrength",
    "motion_strength",
    "resolution",
    "negativePrompt",
    "negative_prompt",
    "promptOptimizer",
    "prompt_optimizer"
]

private func falPollInterval(_ options: [String: JSONValue]) -> UInt64 {
    let milliseconds = options["pollIntervalMs"]?.intValue ?? options["poll_interval_ms"]?.intValue ?? 2_000
    return UInt64(max(milliseconds, 1)) * 1_000_000
}

private func falPollTimeout(_ options: [String: JSONValue]) -> UInt64 {
    let milliseconds = options["pollTimeoutMs"]?.intValue ?? options["poll_timeout_ms"]?.intValue ?? 300_000
    return UInt64(max(milliseconds, 1)) * 1_000_000
}

private func falProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    extraBody["fal"]?.objectValue ?? extraBody.filter { key, _ in key != "fal" }
}

private func falProviderOptions(from request: ImageGenerationRequest) throws -> [String: JSONValue] {
    try falProviderOptions(
        extraBody: request.extraBody,
        providerOptions: request.providerOptions,
        validateProviderOptions: falValidateImageProviderOptions
    )
}

private func falProviderOptions(from request: VideoGenerationRequest) throws -> [String: JSONValue] {
    try falProviderOptions(
        extraBody: request.extraBody,
        providerOptions: request.providerOptions,
        validateProviderOptions: falValidateVideoProviderOptions
    )
}

private func falProviderOptions(
    extraBody: [String: JSONValue],
    providerOptions: [String: JSONValue],
    validateProviderOptions: ([String: JSONValue]) throws -> [String: JSONValue]
) throws -> [String: JSONValue] {
    var output = falProviderOptions(from: extraBody)
    if let value = providerOptions["fal"] {
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.fal", message: "fal provider options must be an object.")
        }
        output.merge(try validateProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

private func falValidateImageProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output = options
    for (snake, camel) in falDeprecatedImageOptionKeys {
        let snakeValue = output[snake]
        let camelValue = output[camel]
        if let snakeValue, snakeValue != .null {
            output[camel] = snakeValue
        } else if camelValue == .null {
            output.removeValue(forKey: camel)
        }
    }
    for (snake, _) in falDeprecatedImageOptionKeys where output[snake] == .null {
        output.removeValue(forKey: snake)
    }
    for key in ["strength", "acceleration", "useMultipleImages"] where output[key] == .null {
        output.removeValue(forKey: key)
    }
    for (key, value) in options {
        switch key {
        case "imageUrl", "image_url", "maskUrl", "mask_url":
            try falRequireStringOrNull(value, argument: "providerOptions.fal.\(key)", label: key)
        case "guidanceScale", "guidance_scale":
            try falRequireNumberOrNull(value, argument: "providerOptions.fal.\(key)", label: key, min: 1, max: 20)
        case "numInferenceSteps", "num_inference_steps":
            try falRequireNumberOrNull(value, argument: "providerOptions.fal.\(key)", label: key, min: 1, max: 50)
        case "enableSafetyChecker", "enable_safety_checker", "syncMode", "sync_mode", "useMultipleImages":
            try falRequireBooleanOrNull(value, argument: "providerOptions.fal.\(key)", label: key)
        case "outputFormat", "output_format":
            try falRequireEnumOrNull(value, argument: "providerOptions.fal.\(key)", label: key, allowed: ["jpeg", "png"])
        case "strength":
            try falRequireNumberOrNull(value, argument: "providerOptions.fal.strength", label: "strength")
        case "acceleration":
            try falRequireEnumOrNull(value, argument: "providerOptions.fal.acceleration", label: "acceleration", allowed: ["none", "regular", "high"])
        case "safetyTolerance", "safety_tolerance":
            if value != .null, let string = value.stringValue {
                guard ["1", "2", "3", "4", "5", "6"].contains(string) else {
                    throw AIError.invalidArgument(argument: "providerOptions.fal.\(key)", message: "fal \(key) must be 1, 2, 3, 4, 5, or 6, as a string or number, or null.")
                }
            } else {
                try falRequireNumberOrNull(value, argument: "providerOptions.fal.\(key)", label: key, min: 1, max: 6)
            }
        default:
            break
        }
    }
    return output
}

private func falValidateVideoProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    for (key, value) in options {
        switch key {
        case "loop", "promptOptimizer":
            try falRequireBooleanOrNull(value, argument: "providerOptions.fal.\(key)", label: key)
        case "motionStrength":
            try falRequireNumberOrNull(value, argument: "providerOptions.fal.motionStrength", label: "motionStrength", min: 0, max: 1)
        case "pollIntervalMs", "pollTimeoutMs":
            try falRequirePositiveNumberOrNull(value, argument: "providerOptions.fal.\(key)", label: key)
        case "resolution", "negativePrompt":
            try falRequireStringOrNull(value, argument: "providerOptions.fal.\(key)", label: key)
        default:
            break
        }
    }
    return options
}

private func falRequireStringOrNull(_ value: JSONValue, argument: String, label: String) throws {
    guard value == .null || value.stringValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: "fal \(label) must be a string or null.")
    }
}

private func falRequireBooleanOrNull(_ value: JSONValue, argument: String, label: String) throws {
    guard value == .null || value.boolValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: "fal \(label) must be a boolean or null.")
    }
}

private func falRequirePositiveNumberOrNull(_ value: JSONValue, argument: String, label: String) throws {
    try falRequireNumberOrNull(value, argument: argument, label: label, min: 0, exclusiveMin: true)
}

private func falRequireNumberOrNull(_ value: JSONValue, argument: String, label: String, min: Double? = nil, max: Double? = nil, exclusiveMin: Bool = false) throws {
    guard value != .null else { return }
    guard let number = value.doubleValue else {
        throw AIError.invalidArgument(argument: argument, message: "fal \(label) must be a number or null.")
    }
    if let min, exclusiveMin ? number <= min : number < min {
        throw AIError.invalidArgument(argument: argument, message: "fal \(label) must be \(exclusiveMin ? "greater than" : "at least") \(falFormatNumber(min)) or null.")
    }
    if let max, number > max {
        throw AIError.invalidArgument(argument: argument, message: "fal \(label) must be at most \(falFormatNumber(max)) or null.")
    }
}

private func falRequireEnumOrNull(_ value: JSONValue, argument: String, label: String, allowed: Set<String>) throws {
    guard value != .null else { return }
    guard let string = value.stringValue, allowed.contains(string) else {
        throw AIError.invalidArgument(argument: argument, message: "fal \(label) must be one of \(allowed.sorted().joined(separator: ", ")) or null.")
    }
}

private func falFormatNumber(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(value)
}

private func falImageInputs(from files: [ImageInputFile], mask: ImageInputFile?, useMultipleImages: Bool) throws -> (input: [String: JSONValue], warnings: [AIWarning]) {
    var input: [String: JSONValue] = [:]
    var warnings: [AIWarning] = []
    if !files.isEmpty {
        if useMultipleImages {
            input["image_urls"] = .array(try files.map { .string(try falImageFileInput($0)) })
        } else if let file = files.first {
            input["image_url"] = .string(try falImageFileInput(file))
            if files.count > 1 {
                warnings.append(AIWarning(
                    type: "other",
                    message: "Multiple input images provided but useMultipleImages is not enabled. Only the first image will be used. Set providerOptions.fal.useMultipleImages to true for models that support multiple images (e.g., fal-ai/flux-2/edit)."
                ))
            }
        }
    }
    if let mask {
        input["mask_url"] = .string(try falImageFileInput(mask))
    }
    return (input, warnings)
}

private func falImageFileInput(_ file: ImageInputFile) throws -> String {
    if let url = file.url {
        return url
    }
    guard let data = file.data else {
        throw AIError.invalidArgument(argument: "files", message: "Fal image input must contain either data or URL.")
    }
    let mediaType = file.mediaType ?? "image/png"
    return "data:\(mediaType);base64,\(data.base64EncodedString())"
}

private func falVideoImageInput(from request: VideoGenerationRequest, options: [String: JSONValue]) throws -> JSONValue? {
    if let image = request.image {
        return .string(try falImageFileInput(image))
    }
    if let image = options["image"] {
        return falVideoImageValue(image)
    }
    if let imageURL = options["imageUrl"] ?? options["image_url"] {
        return imageURL
    }
    return nil
}

private func falVideoImageValue(_ value: JSONValue) -> JSONValue {
    if let object = value.objectValue {
        if let url = object["url"] {
            return url
        }
        if let data = object["data"]?.stringValue {
            let mediaType = object["mediaType"]?.stringValue ?? object["media_type"]?.stringValue ?? "image/png"
            if data.hasPrefix("data:") {
                return .string(data)
            }
            return .string("data:\(mediaType);base64,\(data)")
        }
    }
    return value
}

private func falIsInProgress(_ response: AIHTTPResponse) -> Bool {
    guard let raw = try? response.jsonValue() else { return false }
    return raw["detail"]?.stringValue == "Request is still in progress"
}

private func falImageSize(_ size: String) -> JSONValue {
    switch size {
    case "1:1":
        return .string("square_hd")
    case "16:9":
        return .string("landscape_16_9")
    case "9:16":
        return .string("portrait_16_9")
    case "4:3":
        return .string("landscape_4_3")
    case "3:4":
        return .string("portrait_4_3")
    case "16:10":
        return .object(["width": .number(1280), "height": .number(800)])
    case "10:16":
        return .object(["width": .number(800), "height": .number(1280)])
    case "21:9":
        return .object(["width": .number(2560), "height": .number(1080)])
    case "9:21":
        return .object(["width": .number(1080), "height": .number(2560)])
    default:
        break
    }
    let dimensions = size.split(separator: "x").compactMap { Int($0) }
    guard dimensions.count == 2 else { return .string(size) }
    return .object(["width": .number(Double(dimensions[0])), "height": .number(Double(dimensions[1]))])
}

private func sizeToAspectRatio(_ size: String) -> String {
    let dimensions = size.split(separator: "x").compactMap { Int($0) }
    guard dimensions.count == 2 else { return size }
    let divisor = gcd(dimensions[0], dimensions[1])
    return "\(dimensions[0] / divisor):\(dimensions[1] / divisor)"
}
