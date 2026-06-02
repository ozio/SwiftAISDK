import Foundation

public final class ReplicateImageModel: ImageModel, @unchecked Sendable {
    public let providerID = "replicate"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        let (model, version) = splitVersionedModelID(modelID)
        let options = try replicateProviderOptions(from: request)
        var input: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let size = request.size { input["size"] = .string(size) }
        if let aspectRatio = request.aspectRatio { input["aspect_ratio"] = .string(aspectRatio) }
        if let seed = request.seed { input["seed"] = .number(Double(seed)) }
        if let count = request.count { input["num_outputs"] = .number(Double(count)) }
        let preparedInputs = try replicateImageInputs(from: request.files, mask: request.mask, modelID: modelID)
        input.merge(preparedInputs.input) { _, new in new }
        input.merge(replicateImageOptions(from: options)) { _, new in new }

        var body: [String: JSONValue] = ["input": .object(input)]
        if let version { body["version"] = .string(version) }
        let path = version == nil ? "/models/\(model)/predictions" : "/predictions"
        let response = try await config.sendJSONResponse(
            path: path,
            modelID: modelID,
            body: .object(body),
            headers: request.headers.mergingHeaders(replicatePreferHeaders(from: options)),
            abortSignal: request.abortSignal
        )
        let raw = response.json
        let urls = mediaURLs(from: raw["output"])
        let base64Images = try await downloadReplicateImages(urls: urls, headers: request.headers, abortSignal: request.abortSignal)
        return ImageGenerationResult(
            urls: urls,
            base64Images: base64Images,
            rawValue: raw,
            warnings: preparedInputs.warnings,
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    private func downloadReplicateImages(urls: [String], headers: [String: String], abortSignal: AIAbortSignal?) async throws -> [String] {
        var images: [String] = []
        for url in urls {
            let response = try await downloadURL(url, transport: config.transport, headers: config.headers.mergingHeaders(headers), abortSignal: abortSignal)
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            images.append(response.body.base64EncodedString())
        }
        return images
    }
}

public final class ReplicateVideoModel: VideoModel, @unchecked Sendable {
    public let providerID = "replicate.video"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        let (model, version) = splitVersionedModelID(modelID)
        let options = try replicateProviderOptions(from: request)
        var input: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let aspectRatio = request.aspectRatio { input["aspect_ratio"] = .string(aspectRatio) }
        if let durationSeconds = request.durationSeconds { input["duration"] = .number(durationSeconds) }
        if let resolution = request.resolution {
            input["size"] = .string(resolution)
        } else if let resolution = options["resolution"] {
            input["size"] = resolution
        }
        if let fps = request.fps {
            input["fps"] = .number(fps)
        } else if let fps = options["fps"] {
            input["fps"] = fps
        }
        if let seed = request.seed {
            input["seed"] = .number(Double(seed))
        } else if let seed = options["seed"] {
            input["seed"] = seed
        }
        if let image = try replicateVideoImageInput(from: request, options: options) {
            input["image"] = image
        }
        input.merge(replicateVideoOptions(from: options)) { _, new in new }

        var body: [String: JSONValue] = ["input": .object(input)]
        if let version { body["version"] = .string(version) }
        let path = version == nil ? "/models/\(model)/predictions" : "/predictions"
        let createResponse = try await config.sendJSONResponse(
            path: path,
            modelID: modelID,
            body: .object(body),
            headers: request.headers.mergingHeaders(replicatePreferHeaders(from: options)),
            abortSignal: request.abortSignal
        )
        let finalResponse = try await pollReplicatePredictionResponse(
            createResponse.json,
            initialResponse: createResponse.response,
            headers: request.headers,
            intervalNanoseconds: replicatePollInterval(from: options),
            timeoutNanoseconds: replicatePollTimeout(from: options),
            abortSignal: request.abortSignal
        )
        let raw = finalResponse.json
        if ["failed", "canceled"].contains(raw["status"]?.stringValue ?? "") {
            throw AIError.invalidResponse(provider: providerID, message: "Replicate video generation \(raw["status"]?.stringValue ?? "failed").")
        }
        return VideoGenerationResult(
            urls: mediaURLs(from: raw["output"]),
            operationID: raw["id"]?.stringValue,
            rawValue: raw,
            providerMetadata: replicateVideoProviderMetadata(from: raw),
            requestMetadata: videoGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: finalResponse.response, modelID: modelID)
        )
    }

    private func pollReplicatePredictionResponse(_ initial: JSONValue, initialResponse: AIHTTPResponse, headers: [String: String], intervalNanoseconds: UInt64, timeoutNanoseconds: UInt64, abortSignal: AIAbortSignal?) async throws -> (json: JSONValue, response: AIHTTPResponse) {
        var prediction = initial
        var metadataResponse = initialResponse
        let started = DispatchTime.now().uptimeNanoseconds
        while ["starting", "processing"].contains(prediction["status"]?.stringValue ?? "") {
            guard let getURL = prediction["urls"]?["get"]?.stringValue else { break }
            if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                throw AIError.invalidResponse(provider: providerID, message: "Replicate video generation timed out.")
            }
            try await sleepWithAbortSignal(nanoseconds: intervalNanoseconds, abortSignal: abortSignal)
            let response = try await downloadURL(getURL, transport: config.transport, headers: config.headers.mergingHeaders(headers), abortSignal: abortSignal)
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            prediction = try response.jsonValue()
            metadataResponse = response
        }
        return (prediction, metadataResponse)
    }
}

private func replicatePreferHeaders(from options: [String: JSONValue]) -> [String: String] {
    if let wait = options["maxWaitTimeInSeconds"]?.intValue ?? options["max_wait_time_in_seconds"]?.intValue {
        return ["prefer": "wait=\(wait)"]
    }
    return ["prefer": "wait"]
}

private func replicateImageOptions(from options: [String: JSONValue]) -> [String: JSONValue] {
    var output = options
    if let aspectRatio = output.removeValue(forKey: "aspectRatio") {
        output["aspect_ratio"] = aspectRatio
    }
    output.removeValue(forKey: "maxWaitTimeInSeconds")
    output.removeValue(forKey: "max_wait_time_in_seconds")
    return output
}

private func replicateVideoOptions(from options: [String: JSONValue]) -> [String: JSONValue] {
    var output = options
    output.removeValue(forKey: "maxWaitTimeInSeconds")
    output.removeValue(forKey: "max_wait_time_in_seconds")
    output.removeValue(forKey: "pollIntervalMs")
    output.removeValue(forKey: "poll_interval_ms")
    output.removeValue(forKey: "pollTimeoutMs")
    output.removeValue(forKey: "poll_timeout_ms")
    output.removeValue(forKey: "resolution")
    output.removeValue(forKey: "fps")
    output.removeValue(forKey: "seed")
    output.removeValue(forKey: "image")
    output.removeValue(forKey: "imageUrl")
    output.removeValue(forKey: "image_url")
    for key in replicateVideoNullishProviderOptionKeys where output[key] == .null {
        output.removeValue(forKey: key)
    }
    return output
}

private func replicatePollInterval(from options: [String: JSONValue]) -> UInt64 {
    let milliseconds = options["pollIntervalMs"]?.intValue ?? options["poll_interval_ms"]?.intValue ?? 2_000
    return UInt64(max(milliseconds, 1)) * 1_000_000
}

private func replicatePollTimeout(from options: [String: JSONValue]) -> UInt64 {
    let milliseconds = options["pollTimeoutMs"]?.intValue ?? options["poll_timeout_ms"]?.intValue ?? 300_000
    return UInt64(max(milliseconds, 1)) * 1_000_000
}

private func replicateProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    extraBody["replicate"]?.objectValue ?? extraBody.filter { key, _ in key != "replicate" }
}

private func replicateProviderOptions(from request: ImageGenerationRequest) throws -> [String: JSONValue] {
    try replicateProviderOptions(
        extraBody: request.extraBody,
        providerOptions: request.providerOptions,
        validateProviderOptions: replicateValidateImageProviderOptions
    )
}

private func replicateProviderOptions(from request: VideoGenerationRequest) throws -> [String: JSONValue] {
    try replicateProviderOptions(
        extraBody: request.extraBody,
        providerOptions: request.providerOptions,
        validateProviderOptions: replicateValidateVideoProviderOptions
    )
}

private func replicateProviderOptions(
    extraBody: [String: JSONValue],
    providerOptions: [String: JSONValue],
    validateProviderOptions: ([String: JSONValue]) throws -> [String: JSONValue]
) throws -> [String: JSONValue] {
    var output = replicateProviderOptions(from: extraBody)
    if let value = providerOptions["replicate"] {
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.replicate", message: "Replicate provider options must be an object.")
        }
        output.merge(try validateProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

private let replicateVideoNullishProviderOptionKeys: Set<String> = [
    "guidance_scale",
    "num_inference_steps",
    "motion_bucket_id",
    "cond_aug",
    "decoding_t",
    "video_length",
    "sizing_strategy",
    "frames_per_second",
    "prompt_optimizer"
]

private func replicateValidateImageProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    for (key, value) in options {
        switch key {
        case "maxWaitTimeInSeconds":
            try replicateValidatePositiveNumberOrNull(value, argument: "providerOptions.replicate.maxWaitTimeInSeconds", label: "maxWaitTimeInSeconds")
        case "guidance_scale", "num_inference_steps":
            try replicateValidateNumberOrNull(value, argument: "providerOptions.replicate.\(key)", label: key)
        case "negative_prompt":
            try replicateValidateStringOrNull(value, argument: "providerOptions.replicate.negative_prompt", label: "negative_prompt")
        case "output_format":
            guard value == .null || ["png", "jpg", "webp"].contains(value.stringValue ?? "") else {
                throw AIError.invalidArgument(argument: "providerOptions.replicate.output_format", message: "Replicate output_format must be png, jpg, webp, or null.")
            }
        case "output_quality":
            try replicateValidateNumberOrNull(value, argument: "providerOptions.replicate.output_quality", label: "output_quality", min: 1, max: 100)
        case "strength":
            try replicateValidateNumberOrNull(value, argument: "providerOptions.replicate.strength", label: "strength", min: 0, max: 1)
        default:
            break
        }
    }
    return options
}

private func replicateValidateVideoProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    for (key, value) in options {
        switch key {
        case "pollIntervalMs", "pollTimeoutMs", "maxWaitTimeInSeconds":
            try replicateValidatePositiveNumberOrNull(value, argument: "providerOptions.replicate.\(key)", label: key)
        case "guidance_scale", "num_inference_steps", "motion_bucket_id", "cond_aug", "decoding_t", "frames_per_second":
            try replicateValidateNumberOrNull(value, argument: "providerOptions.replicate.\(key)", label: key)
        case "video_length", "sizing_strategy":
            try replicateValidateStringOrNull(value, argument: "providerOptions.replicate.\(key)", label: key)
        case "prompt_optimizer":
            guard value == .null || value.boolValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.replicate.prompt_optimizer", message: "Replicate prompt_optimizer must be a boolean or null.")
            }
        default:
            break
        }
    }
    return options
}

private func replicateValidatePositiveNumberOrNull(_ value: JSONValue, argument: String, label: String) throws {
    try replicateValidateNumberOrNull(value, argument: argument, label: label, min: 0, exclusiveMin: true)
}

private func replicateValidateNumberOrNull(_ value: JSONValue, argument: String, label: String, min: Double? = nil, max: Double? = nil, exclusiveMin: Bool = false) throws {
    guard value != .null else { return }
    guard let number = value.doubleValue else {
        throw AIError.invalidArgument(argument: argument, message: "Replicate \(label) must be a number or null.")
    }
    if let min, exclusiveMin ? number <= min : number < min {
        throw AIError.invalidArgument(argument: argument, message: "Replicate \(label) must be \(exclusiveMin ? "greater than" : "at least") \(replicateFormatNumber(min)) or null.")
    }
    if let max, number > max {
        throw AIError.invalidArgument(argument: argument, message: "Replicate \(label) must be at most \(replicateFormatNumber(max)) or null.")
    }
}

private func replicateValidateStringOrNull(_ value: JSONValue, argument: String, label: String) throws {
    guard value == .null || value.stringValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: "Replicate \(label) must be a string or null.")
    }
}

private func replicateFormatNumber(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(value)
}

private func replicateImageInputs(from files: [ImageInputFile], mask: ImageInputFile?, modelID: String) throws -> (input: [String: JSONValue], warnings: [AIWarning]) {
    let isFlux2 = modelID.range(of: #"^black-forest-labs/flux-2-"#, options: .regularExpression) != nil
    var input: [String: JSONValue] = [:]
    var warnings: [AIWarning] = []

    if isFlux2 {
        for (index, file) in files.prefix(8).enumerated() {
            let key = index == 0 ? "input_image" : "input_image_\(index + 1)"
            input[key] = .string(try replicateImageFileInput(file))
        }
        if files.count > 8 {
            warnings.append(AIWarning(type: "other", message: "Flux-2 models support up to 8 input images. Additional images are ignored."))
        }
        if mask != nil {
            warnings.append(AIWarning(type: "other", message: "Flux-2 models do not support mask input. The mask will be ignored."))
        }
    } else if let file = files.first {
        input["image"] = .string(try replicateImageFileInput(file))
        if files.count > 1 {
            warnings.append(AIWarning(type: "other", message: "This Replicate model only supports a single input image. Additional images are ignored."))
        }
        if let mask {
            input["mask"] = .string(try replicateImageFileInput(mask))
        }
    }

    return (input, warnings)
}

private func replicateImageFileInput(_ file: ImageInputFile) throws -> String {
    if let url = file.url {
        return url
    }
    guard let data = file.data else {
        throw AIError.invalidArgument(argument: "files", message: "Replicate image input must contain either data or URL.")
    }
    let mediaType = file.mediaType ?? "image/png"
    return "data:\(mediaType);base64,\(data.base64EncodedString())"
}

private func replicateVideoImageInput(from request: VideoGenerationRequest, options: [String: JSONValue]) throws -> JSONValue? {
    if let image = request.image {
        return .string(try replicateImageFileInput(image))
    }
    if let image = options["image"] {
        return replicateVideoImageValue(image)
    }
    if let imageURL = options["imageUrl"] ?? options["image_url"] {
        return imageURL
    }
    return nil
}

private func replicateVideoImageValue(_ value: JSONValue) -> JSONValue {
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

private func replicateVideoProviderMetadata(from raw: JSONValue) -> [String: JSONValue] {
    var replicate: [String: JSONValue] = [:]
    if let url = raw["output"]?.stringValue {
        replicate["videos"] = .array([.object(["url": .string(url)])])
    }
    if let id = raw["id"] {
        replicate["predictionId"] = id
    }
    if let metrics = raw["metrics"] {
        replicate["metrics"] = metrics
    }
    return replicate.isEmpty ? [:] : ["replicate": .object(replicate)]
}

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
                throw httpStatusError(provider: providerID, response: response)
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
        let queueResponse = try await config.transport.send(config.request(
            path: "/fal-ai/\(normalized)",
            modelID: modelID,
            body: .object(body),
            headers: request.headers,
            abortSignal: request.abortSignal
        ).withURL(try requireURL("https://queue.fal.run/fal-ai/\(normalized)")))
        guard (200..<300).contains(queueResponse.statusCode) else {
            throw httpStatusError(provider: providerID, response: queueResponse)
        }
        let queued = try queueResponse.jsonValue()
        guard let responseURL = queued["response_url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Fal queue response did not contain response_url.")
        }
        let finalResponse = try await pollFalResponse(
            url: responseURL,
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

    private func pollFalResponse(url: String, headers: [String: String], intervalNanoseconds: UInt64, timeoutNanoseconds: UInt64, abortSignal: AIAbortSignal?) async throws -> (json: JSONValue, response: AIHTTPResponse) {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            let response = try await downloadURL(url, transport: config.transport, headers: config.headers.mergingHeaders(headers), abortSignal: abortSignal)
            if (200..<300).contains(response.statusCode) {
                return (try response.jsonValue(), response)
            }
            if !falIsInProgress(response) {
                throw httpStatusError(provider: providerID, response: response)
            }
            if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                throw AIError.invalidResponse(provider: providerID, message: "Fal video generation timed out.")
            }
            try await sleepWithAbortSignal(nanoseconds: intervalNanoseconds, abortSignal: abortSignal)
        }
    }
}

public final class BlackForestLabsImageModel: ImageModel, @unchecked Sendable {
    public let providerID = "black-forest-labs.image"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        let options = try blackForestLabsProviderOptions(from: request)
        let warnings = blackForestLabsWarnings(for: request)
        var body: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let aspectRatio = request.aspectRatio {
            body["aspect_ratio"] = .string(aspectRatio)
        } else if let aspectRatio = options["aspectRatio"] ?? options["aspect_ratio"] {
            body["aspect_ratio"] = aspectRatio
        } else if let size = request.size, let aspectRatio = bflAspectRatio(from: size) {
            body["aspect_ratio"] = .string(aspectRatio)
        }
        if let dimensions = bflDimensions(from: request.size) {
            body["width"] = options["width"] ?? .number(Double(dimensions.width))
            body["height"] = options["height"] ?? .number(Double(dimensions.height))
        }
        body.merge(blackForestLabsOptions(from: options)) { _, new in new }
        if let seed = request.seed {
            body["seed"] = .number(Double(seed))
        }
        body.merge(try blackForestLabsImageInputs(files: request.files, mask: request.mask, modelID: modelID)) { _, new in new }
        let submitted = try await config.sendJSONResponse(path: "/\(modelID)", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        guard let pollURL = submitted.json["polling_url"]?.stringValue,
              let requestID = submitted.json["id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Black Forest Labs submit response did not contain id and polling_url.")
        }
        let raw = try await pollBFL(
            url: pollURL,
            id: requestID,
            headers: request.headers,
            intervalNanoseconds: bflPollInterval(options),
            timeoutNanoseconds: bflPollTimeout(options),
            abortSignal: request.abortSignal
        )
        guard let url = raw["result"]?["sample"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Black Forest Labs poll response did not contain result.sample.")
        }
        let image = try await downloadURL(url, transport: config.transport, headers: config.headers.mergingHeaders(request.headers), abortSignal: request.abortSignal)
        guard (200..<300).contains(image.statusCode) else {
            throw httpStatusError(provider: providerID, response: image)
        }
        return ImageGenerationResult(
            urls: [url],
            base64Images: [image.body.base64EncodedString()],
            rawValue: raw,
            warnings: warnings,
            providerMetadata: blackForestLabsProviderMetadata(submit: submitted.json, poll: raw),
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: AIResponseMetadata(timestamp: Date(), modelID: modelID, headers: image.headers)
        )
    }

    private func pollBFL(url: String, id: String, headers: [String: String], intervalNanoseconds: UInt64, timeoutNanoseconds: UInt64, abortSignal: AIAbortSignal?) async throws -> JSONValue {
        let pollURL = appendQueryItemIfMissing(url: url, name: "id", value: id)
        let maxPollAttempts = bflMaxPollAttempts(intervalNanoseconds: intervalNanoseconds, timeoutNanoseconds: timeoutNanoseconds)
        for attempt in 0..<maxPollAttempts {
            let response = try await downloadURL(pollURL, transport: config.transport, headers: config.headers.mergingHeaders(headers), abortSignal: abortSignal)
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            let status = raw["status"]?.stringValue ?? raw["state"]?.stringValue
            if status == "Ready" { return raw }
            if status == "Error" || status == "Failed" {
                throw AIError.invalidResponse(provider: providerID, message: "Black Forest Labs generation failed.")
            }
            if attempt < maxPollAttempts - 1 {
                try await sleepWithAbortSignal(nanoseconds: intervalNanoseconds, abortSignal: abortSignal)
            }
        }
        throw AIError.invalidResponse(provider: providerID, message: "Black Forest Labs generation timed out.")
    }
}

private func blackForestLabsProviderOptions(from request: ImageGenerationRequest) throws -> [String: JSONValue] {
    var output = blackForestLabsProviderOptions(from: request.extraBody)
    if let providerOptions = request.providerOptions["blackForestLabs"]?.objectValue {
        output.merge(try blackForestLabsValidatedProviderOptions(from: providerOptions)) { _, providerValue in providerValue }
    }
    return output
}

private func blackForestLabsProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    if let nested = extraBody["blackForestLabs"]?.objectValue {
        return nested
    }
    var output = extraBody
    output.removeValue(forKey: "blackForestLabs")
    return output
}

private func blackForestLabsOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    output.removeValue(forKey: "aspectRatio")
    output.removeValue(forKey: "aspect_ratio")
    blackForestLabsMoveKey("imagePrompt", to: "image_prompt", in: &output)
    blackForestLabsMoveKey("imagePromptStrength", to: "image_prompt_strength", in: &output)
    blackForestLabsMoveKey("outputFormat", to: "output_format", in: &output)
    blackForestLabsMoveKey("promptUpsampling", to: "prompt_upsampling", in: &output)
    blackForestLabsMoveKey("safetyTolerance", to: "safety_tolerance", in: &output)
    blackForestLabsMoveKey("webhookSecret", to: "webhook_secret", in: &output)
    blackForestLabsMoveKey("webhookUrl", to: "webhook_url", in: &output)
    blackForestLabsMoveKey("inputImage", to: "input_image", in: &output)
    for index in 2...10 {
        blackForestLabsMoveKey("inputImage\(index)", to: "input_image_\(index)", in: &output)
    }
    output.removeValue(forKey: "pollIntervalMillis")
    output.removeValue(forKey: "pollTimeoutMillis")
    return output
}

private func blackForestLabsValidatedProviderOptions(from options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where blackForestLabsSupportedProviderOptionKeys.contains(key) {
        switch key {
        case "imagePrompt", "inputImage", "inputImage2", "inputImage3", "inputImage4", "inputImage5", "inputImage6", "inputImage7", "inputImage8", "inputImage9", "inputImage10", "webhookSecret":
            guard value.stringValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs.\(key)", message: "Black Forest Labs \(key) must be a string.")
            }
        case "webhookUrl":
            guard let url = value.stringValue, blackForestLabsIsURL(url) else {
                throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs.webhookUrl", message: "Black Forest Labs webhookUrl must be a valid URL.")
            }
        case "imagePromptStrength":
            guard let number = value.doubleValue, number >= 0, number <= 1 else {
                throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs.imagePromptStrength", message: "Black Forest Labs imagePromptStrength must be between 0 and 1.")
            }
        case "steps", "pollIntervalMillis", "pollTimeoutMillis":
            guard let number = value.doubleValue, blackForestLabsIsInteger(number), number > 0 else {
                throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs.\(key)", message: "Black Forest Labs \(key) must be a positive integer.")
            }
        case "guidance":
            guard let number = value.doubleValue, number >= 0 else {
                throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs.guidance", message: "Black Forest Labs guidance must be greater than or equal to 0.")
            }
        case "width", "height":
            guard let number = value.doubleValue, blackForestLabsIsInteger(number), number >= 256, number <= 1920 else {
                throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs.\(key)", message: "Black Forest Labs \(key) must be an integer between 256 and 1920.")
            }
        case "outputFormat":
            guard let format = value.stringValue, ["jpeg", "png"].contains(format) else {
                throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs.outputFormat", message: "Black Forest Labs outputFormat must be one of jpeg, png.")
            }
        case "promptUpsampling", "raw":
            guard value.boolValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs.\(key)", message: "Black Forest Labs \(key) must be a boolean.")
            }
        case "safetyTolerance":
            guard let number = value.doubleValue, blackForestLabsIsInteger(number), number >= 0, number <= 6 else {
                throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs.safetyTolerance", message: "Black Forest Labs safetyTolerance must be an integer between 0 and 6.")
            }
        default:
            break
        }
        output[key] = value
    }
    return output
}

private let blackForestLabsSupportedProviderOptionKeys: Set<String> = [
    "imagePrompt",
    "imagePromptStrength",
    "inputImage",
    "inputImage2",
    "inputImage3",
    "inputImage4",
    "inputImage5",
    "inputImage6",
    "inputImage7",
    "inputImage8",
    "inputImage9",
    "inputImage10",
    "steps",
    "guidance",
    "width",
    "height",
    "outputFormat",
    "promptUpsampling",
    "raw",
    "safetyTolerance",
    "webhookSecret",
    "webhookUrl",
    "pollIntervalMillis",
    "pollTimeoutMillis"
]

private func blackForestLabsWarnings(for request: ImageGenerationRequest) -> [AIWarning] {
    guard request.size != nil else { return [] }
    if request.aspectRatio == nil {
        return [
            AIWarning(
                type: "unsupported",
                feature: "size",
                message: "Deriving aspect_ratio from size. Use the width and height provider options to specify dimensions for models that support them."
            )
        ]
    }
    return [
        AIWarning(
            type: "unsupported",
            feature: "size",
            message: "Black Forest Labs ignores size when aspectRatio is provided. Use the width and height provider options to specify dimensions for models that support them"
        )
    ]
}

private func blackForestLabsProviderMetadata(submit: JSONValue, poll: JSONValue) -> [String: JSONValue] {
    let imageMetadata: JSONValue = .object([
        "seed": poll["result"]?["seed"],
        "start_time": poll["result"]?["start_time"],
        "end_time": poll["result"]?["end_time"],
        "duration": poll["result"]?["duration"],
        "cost": submit["cost"],
        "inputMegapixels": submit["input_mp"],
        "outputMegapixels": submit["output_mp"]
    ])
    return [
        "blackForestLabs": .object([
            "images": .array([imageMetadata])
        ])
    ]
}

private func blackForestLabsImageInputs(files: [ImageInputFile], mask: ImageInputFile?, modelID: String) throws -> [String: JSONValue] {
    guard files.count <= 10 else {
        throw AIError.invalidArgument(argument: "files", message: "Black Forest Labs supports up to 10 input images.")
    }
    let inputImageField = modelID == "flux-pro-1.0-fill" ? "image" : "input_image"
    var output: [String: JSONValue] = [:]
    for (index, file) in files.enumerated() {
        let key = index == 0 ? inputImageField : "\(inputImageField)_\(index + 1)"
        output[key] = .string(blackForestLabsImageString(file))
    }
    if let mask {
        output["mask"] = .string(blackForestLabsImageString(mask))
    }
    return output
}

private func blackForestLabsImageString(_ file: ImageInputFile) -> String {
    if let url = file.url {
        return url
    }
    if let data = file.data {
        return data.base64EncodedString()
    }
    return ""
}

private func blackForestLabsMoveKey(_ source: String, to destination: String, in values: inout [String: JSONValue]) {
    if let value = values.removeValue(forKey: source) {
        values[destination] = value
    }
}

private func blackForestLabsIsInteger(_ value: Double) -> Bool {
    value.isFinite && value.rounded(.towardZero) == value
}

private func blackForestLabsIsURL(_ value: String) -> Bool {
    guard let components = URLComponents(string: value) else { return false }
    return components.scheme != nil && components.host != nil
}

private func bflAspectRatio(from size: String) -> String? {
    let dimensions = size.split(separator: "x").compactMap { Int($0) }
    guard dimensions.count == 2, dimensions[0] > 0, dimensions[1] > 0 else { return nil }
    let divisor = bflGCD(dimensions[0], dimensions[1])
    return "\(dimensions[0] / divisor):\(dimensions[1] / divisor)"
}

private func bflDimensions(from size: String?) -> (width: Int, height: Int)? {
    guard let size else { return nil }
    let dimensions = size.split(separator: "x").compactMap { Int($0) }
    guard dimensions.count == 2, dimensions[0] > 0, dimensions[1] > 0 else { return nil }
    return (dimensions[0], dimensions[1])
}

private func bflGCD(_ lhs: Int, _ rhs: Int) -> Int {
    var a = abs(lhs)
    var b = abs(rhs)
    while b != 0 {
        let next = a % b
        a = b
        b = next
    }
    return max(a, 1)
}

private func bflPollInterval(_ extraBody: [String: JSONValue]) -> UInt64 {
    let milliseconds = extraBody["pollIntervalMillis"]?.intValue ?? 500
    return UInt64(max(milliseconds, 1)) * 1_000_000
}

private func bflPollTimeout(_ extraBody: [String: JSONValue]) -> UInt64 {
    let milliseconds = extraBody["pollTimeoutMillis"]?.intValue ?? 60_000
    return UInt64(max(milliseconds, 1)) * 1_000_000
}

private func bflMaxPollAttempts(intervalNanoseconds: UInt64, timeoutNanoseconds: UInt64) -> Int {
    let interval = max(intervalNanoseconds, 1)
    let attempts = (timeoutNanoseconds + interval - 1) / interval
    return max(Int(attempts), 1)
}

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
        let submitted = try await config.sendJSONResponse(path: "/dream-machine/v1/generations/image", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
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
            throw AIError.invalidResponse(provider: providerID, message: "Luma completed response did not contain assets.image.")
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
                throw httpStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            switch raw["state"]?.stringValue {
            case "completed":
                return (raw, response)
            case "failed":
                throw AIError.invalidResponse(provider: providerID, message: raw["failure_reason"]?.stringValue ?? "Luma image generation failed.")
            default:
                try await sleepWithAbortSignal(nanoseconds: intervalNanoseconds, abortSignal: abortSignal)
            }
        }
        throw AIError.invalidResponse(provider: providerID, message: "Luma image generation timed out.")
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

public final class KlingAIVideoModel: VideoModel, @unchecked Sendable {
    public let providerID = "klingai.video"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        let mode = try klingMode(modelID)
        let endpoint = klingEndpoint(mode)
        let options = try klingAIProviderOptions(from: request)
        let warnings = klingAIWarnings(for: request, mode: mode)
        var body: [String: JSONValue] = [
            "model_name": .string(klingAPIModelName(modelID, mode: mode))
        ]
        if !request.prompt.isEmpty { body["prompt"] = .string(request.prompt) }
        if let aspectRatio = request.aspectRatio, mode == "t2v" {
            body["aspect_ratio"] = .string(aspectRatio)
        }
        if let duration = request.durationSeconds, mode != "motion-control" {
            body["duration"] = .string(formatDuration(duration))
        }
        body.merge(try klingAIOptions(from: options, mode: mode, requestImage: request.image)) { _, new in new }

        let created = try await config.sendJSONResponse(path: endpoint, modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        guard let taskID = created.json["data"]?["task_id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "KlingAI create response did not contain data.task_id.")
        }
        let finalResponse = try await pollKling(
            endpoint: endpoint,
            taskID: taskID,
            headers: request.headers,
            intervalNanoseconds: klingAIPollInterval(options.known["pollIntervalMs"]),
            timeoutNanoseconds: klingAIPollTimeout(options.known["pollTimeoutMs"]),
            abortSignal: request.abortSignal
        )
        let raw = finalResponse.raw
        let videos = raw["data"]?["task_result"]?["videos"]?.arrayValue ?? []
        let urls = videos.compactMap { $0["url"]?.stringValue }
        guard !urls.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "KlingAI task response did not contain video URLs.")
        }
        return VideoGenerationResult(
            urls: urls,
            operationID: taskID,
            rawValue: raw,
            warnings: warnings,
            providerMetadata: [
                "klingai": .object([
                    "taskId": .string(taskID),
                    "videos": .array(klingAIVideoMetadata(from: videos))
                ])
            ],
            requestMetadata: videoGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: finalResponse.response, modelID: modelID)
        )
    }

    private func pollKling(endpoint: String, taskID: String, headers: [String: String], intervalNanoseconds: UInt64, timeoutNanoseconds: UInt64, abortSignal: AIAbortSignal?) async throws -> (raw: JSONValue, response: AIHTTPResponse) {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            try await sleepWithAbortSignal(nanoseconds: intervalNanoseconds, abortSignal: abortSignal)
            if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                throw AIError.invalidResponse(provider: providerID, message: "KlingAI video generation timed out.")
            }
            let response = try await config.transport.send(AIHTTPRequest(
                method: "GET",
                url: try requireURL("\(withoutTrailingSlash(config.baseURL))\(endpoint)/\(taskID)"),
                headers: config.headers.mergingHeaders(headers),
                abortSignal: abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            switch raw["data"]?["task_status"]?.stringValue {
            case "succeed":
                return (raw, response)
            case "failed":
                throw AIError.invalidResponse(provider: providerID, message: raw["data"]?["task_status_msg"]?.stringValue ?? "KlingAI task failed.")
            default:
                continue
            }
        }
    }
}

private struct KlingAIResolvedOptions {
    var known: [String: JSONValue]
    var passthrough: [String: JSONValue]
}

private func klingAIProviderOptions(from request: VideoGenerationRequest) throws -> KlingAIResolvedOptions {
    var output = try klingAIExtraBodyOptions(from: request.extraBody)
    if let providerValue = request.providerOptions["klingai"] {
        guard providerValue != .null else { return output }
        guard let providerOptions = providerValue.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.klingai", message: "KlingAI provider options must be an object.")
        }
        let parsed = try klingAIValidatedProviderOptions(from: providerOptions)
        for (key, value) in parsed.known {
            if value == .null {
                output.known.removeValue(forKey: key)
            } else {
                output.known[key] = value
            }
        }
        output.passthrough.merge(parsed.passthrough) { _, providerValue in providerValue }
    }
    return output
}

private func klingAIExtraBodyOptions(from extraBody: [String: JSONValue]) throws -> KlingAIResolvedOptions {
    var passthrough = extraBody["klingai"]?.objectValue ?? extraBody.filter { key, _ in key != "klingai" }
    var known: [String: JSONValue] = [:]
    for (key, canonicalKey) in klingAIExtraBodyOptionAliases {
        if let value = passthrough.removeValue(forKey: key), value != .null {
            known[canonicalKey] = value
        }
    }
    return KlingAIResolvedOptions(known: try klingAIValidateKnownOptions(known), passthrough: passthrough)
}

private func klingAIOptions(from options: KlingAIResolvedOptions, mode: String, requestImage: ImageInputFile?) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    let known = options.known
    if mode == "motion-control" {
        guard let videoURL = known["videoUrl"],
              let characterOrientation = known["characterOrientation"],
              let generationMode = known["mode"] else {
            throw AIError.invalidArgument(argument: "extraBody.klingai", message: "KlingAI Motion Control requires videoUrl, characterOrientation, and mode.")
        }
        output["video_url"] = videoURL
        output["character_orientation"] = characterOrientation
        output["mode"] = generationMode
        if let image = try klingAIImageInput(from: requestImage) ?? klingAIImageInput(from: known) {
            output["image_url"] = image
        }
        if let keepOriginalSound = known["keepOriginalSound"] {
            output["keep_original_sound"] = keepOriginalSound
        }
        if let watermarkEnabled = known["watermarkEnabled"] {
            output["watermark_info"] = .object(["enabled": watermarkEnabled])
        }
        if let elementList = known["elementList"] {
            output["element_list"] = elementList
        }
    } else {
        if mode == "i2v", let image = try klingAIImageInput(from: requestImage) ?? klingAIImageInput(from: known) {
            output["image"] = image
        }
        klingAIMoveSharedOptions(known, to: &output)
        if mode == "i2v" {
            if let imageTail = known["imageTail"] { output["image_tail"] = imageTail }
            if let staticMask = known["staticMask"] { output["static_mask"] = staticMask }
            if let dynamicMasks = known["dynamicMasks"] { output["dynamic_masks"] = dynamicMasks }
            if let elementList = known["elementList"] { output["element_list"] = elementList }
        }
    }

    output.merge(options.passthrough) { _, new in new }
    return output
}

private func klingAIWarnings(for request: VideoGenerationRequest, mode: String) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if mode == "t2v", request.image != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "image",
            message: "KlingAI text-to-video does not support image input. Use an image-to-video model instead."
        ))
    }
    if request.aspectRatio != nil, mode == "i2v" {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "aspectRatio",
            message: "KlingAI image-to-video does not support aspectRatio. The output dimensions are determined by the input image."
        ))
    }
    if request.aspectRatio != nil, mode == "motion-control" {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "aspectRatio",
            message: "KlingAI Motion Control does not support aspectRatio. The output dimensions are determined by the reference image/video."
        ))
    }
    if request.durationSeconds != nil, mode == "motion-control" {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "duration",
            message: "KlingAI Motion Control does not support custom duration. The output duration matches the reference video duration."
        ))
    }
    if request.resolution != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "resolution",
            message: "KlingAI video models do not support the resolution option."
        ))
    }
    if request.seed != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "seed",
            message: "KlingAI video models do not support seed for deterministic generation."
        ))
    }
    if request.fps != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "fps",
            message: "KlingAI video models do not support custom FPS."
        ))
    }
    if let count = request.count, count > 1 {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "n",
            message: "KlingAI video models do not support generating multiple videos per call. Only 1 video will be generated."
        ))
    }
    return warnings
}

private let klingAIProviderOptionKeys: Set<String> = [
    "mode",
    "pollIntervalMs",
    "pollTimeoutMs",
    "negativePrompt",
    "sound",
    "cfgScale",
    "cameraControl",
    "multiShot",
    "shotType",
    "multiPrompt",
    "elementList",
    "voiceList",
    "imageTail",
    "staticMask",
    "dynamicMasks",
    "videoUrl",
    "characterOrientation",
    "keepOriginalSound",
    "watermarkEnabled"
]

private let klingAIExtraBodyOptionAliases: [String: String] = [
    "mode": "mode",
    "pollIntervalMs": "pollIntervalMs",
    "pollTimeoutMs": "pollTimeoutMs",
    "image": "image",
    "imageUrl": "image",
    "image_url": "image",
    "negativePrompt": "negativePrompt",
    "negative_prompt": "negativePrompt",
    "sound": "sound",
    "cfgScale": "cfgScale",
    "cfg_scale": "cfgScale",
    "cameraControl": "cameraControl",
    "camera_control": "cameraControl",
    "multiShot": "multiShot",
    "multi_shot": "multiShot",
    "shotType": "shotType",
    "shot_type": "shotType",
    "multiPrompt": "multiPrompt",
    "multi_prompt": "multiPrompt",
    "elementList": "elementList",
    "element_list": "elementList",
    "voiceList": "voiceList",
    "voice_list": "voiceList",
    "imageTail": "imageTail",
    "image_tail": "imageTail",
    "staticMask": "staticMask",
    "static_mask": "staticMask",
    "dynamicMasks": "dynamicMasks",
    "dynamic_masks": "dynamicMasks",
    "videoUrl": "videoUrl",
    "video_url": "videoUrl",
    "characterOrientation": "characterOrientation",
    "character_orientation": "characterOrientation",
    "keepOriginalSound": "keepOriginalSound",
    "keep_original_sound": "keepOriginalSound",
    "watermarkEnabled": "watermarkEnabled"
]

private func klingAIValidatedProviderOptions(from providerOptions: [String: JSONValue]) throws -> KlingAIResolvedOptions {
    var known: [String: JSONValue] = [:]
    var valuesToValidate: [String: JSONValue] = [:]
    var passthrough = providerOptions
    for key in klingAIProviderOptionKeys {
        if let value = passthrough.removeValue(forKey: key) {
            if value == .null {
                known[key] = .null
            } else {
                valuesToValidate[key] = value
            }
        }
    }
    known.merge(try klingAIValidateKnownOptions(valuesToValidate)) { _, validated in validated }
    return KlingAIResolvedOptions(known: known, passthrough: passthrough)
}

private func klingAIValidateKnownOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options {
        switch key {
        case "mode":
            output[key] = try klingAIStringEnum(value, key: key, allowed: ["std", "pro"])
        case "pollIntervalMs", "pollTimeoutMs":
            guard let number = value.doubleValue, number > 0 else {
                throw AIError.invalidArgument(argument: "providerOptions.klingai.\(key)", message: "KlingAI \(key) must be a positive number.")
            }
            output[key] = value
        case "negativePrompt", "imageTail", "staticMask", "videoUrl":
            output[key] = try klingAIString(value, key: key)
        case "sound":
            output[key] = try klingAIStringEnum(value, key: key, allowed: ["on", "off"])
        case "cfgScale":
            guard value.doubleValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.klingai.cfgScale", message: "KlingAI cfgScale must be a number.")
            }
            output[key] = value
        case "cameraControl":
            output[key] = try klingAICameraControl(value)
        case "multiShot", "watermarkEnabled":
            guard value.boolValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.klingai.\(key)", message: "KlingAI \(key) must be a boolean.")
            }
            output[key] = value
        case "shotType":
            output[key] = try klingAIStringEnum(value, key: key, allowed: ["customize", "intelligence"])
        case "multiPrompt":
            output[key] = try klingAIMultiPrompt(value)
        case "elementList":
            output[key] = try klingAIElementList(value)
        case "voiceList":
            output[key] = try klingAIVoiceList(value)
        case "dynamicMasks":
            output[key] = try klingAIDynamicMasks(value)
        case "characterOrientation":
            output[key] = try klingAIStringEnum(value, key: key, allowed: ["image", "video"])
        case "keepOriginalSound":
            output[key] = try klingAIStringEnum(value, key: key, allowed: ["yes", "no"])
        case "image":
            output[key] = value
        default:
            output[key] = value
        }
    }
    return output
}

private func klingAIString(_ value: JSONValue, key: String) throws -> JSONValue {
    guard value.stringValue != nil else {
        throw AIError.invalidArgument(argument: "providerOptions.klingai.\(key)", message: "KlingAI \(key) must be a string.")
    }
    return value
}

private func klingAIStringEnum(_ value: JSONValue, key: String, allowed: Set<String>) throws -> JSONValue {
    guard let string = value.stringValue, allowed.contains(string) else {
        throw AIError.invalidArgument(argument: "providerOptions.klingai.\(key)", message: "KlingAI \(key) must be one of \(allowed.sorted().joined(separator: ", ")).")
    }
    return value
}

private func klingAICameraControl(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.klingai.cameraControl", message: "KlingAI cameraControl must be an object.")
    }
    _ = try klingAIStringEnum(object["type"] ?? .null, key: "cameraControl.type", allowed: ["simple", "down_back", "forward_up", "right_turn_forward", "left_turn_forward"])
    if let config = object["config"], config != .null {
        guard let configObject = config.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.klingai.cameraControl.config", message: "KlingAI cameraControl.config must be an object.")
        }
        for key in ["horizontal", "vertical", "pan", "tilt", "roll", "zoom"] {
            if let value = configObject[key], value != .null, value.doubleValue == nil {
                throw AIError.invalidArgument(argument: "providerOptions.klingai.cameraControl.config.\(key)", message: "KlingAI cameraControl.config.\(key) must be a number.")
            }
        }
    }
    return value
}

private func klingAIMultiPrompt(_ value: JSONValue) throws -> JSONValue {
    guard let array = value.arrayValue else {
        throw AIError.invalidArgument(argument: "providerOptions.klingai.multiPrompt", message: "KlingAI multiPrompt must be an array.")
    }
    for (index, item) in array.enumerated() {
        guard let object = item.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.klingai.multiPrompt", message: "KlingAI multiPrompt[\(index)] must be an object.")
        }
        guard object["index"]?.doubleValue != nil else {
            throw AIError.invalidArgument(argument: "providerOptions.klingai.multiPrompt[\(index)].index", message: "KlingAI multiPrompt index must be a number.")
        }
        _ = try klingAIString(object["prompt"] ?? .null, key: "multiPrompt[\(index)].prompt")
        _ = try klingAIString(object["duration"] ?? .null, key: "multiPrompt[\(index)].duration")
    }
    return value
}

private func klingAIElementList(_ value: JSONValue) throws -> JSONValue {
    guard let array = value.arrayValue else {
        throw AIError.invalidArgument(argument: "providerOptions.klingai.elementList", message: "KlingAI elementList must be an array.")
    }
    for (index, item) in array.enumerated() {
        guard let object = item.objectValue, object["element_id"]?.doubleValue != nil else {
            throw AIError.invalidArgument(argument: "providerOptions.klingai.elementList[\(index)].element_id", message: "KlingAI element_id must be a number.")
        }
    }
    return value
}

private func klingAIVoiceList(_ value: JSONValue) throws -> JSONValue {
    guard let array = value.arrayValue else {
        throw AIError.invalidArgument(argument: "providerOptions.klingai.voiceList", message: "KlingAI voiceList must be an array.")
    }
    for (index, item) in array.enumerated() {
        guard let object = item.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.klingai.voiceList", message: "KlingAI voiceList[\(index)] must be an object.")
        }
        _ = try klingAIString(object["voice_id"] ?? .null, key: "voiceList[\(index)].voice_id")
    }
    return value
}

private func klingAIDynamicMasks(_ value: JSONValue) throws -> JSONValue {
    guard let array = value.arrayValue else {
        throw AIError.invalidArgument(argument: "providerOptions.klingai.dynamicMasks", message: "KlingAI dynamicMasks must be an array.")
    }
    for (index, item) in array.enumerated() {
        guard let object = item.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.klingai.dynamicMasks", message: "KlingAI dynamicMasks[\(index)] must be an object.")
        }
        _ = try klingAIString(object["mask"] ?? .null, key: "dynamicMasks[\(index)].mask")
        guard let trajectories = object["trajectories"]?.arrayValue else {
            throw AIError.invalidArgument(argument: "providerOptions.klingai.dynamicMasks[\(index)].trajectories", message: "KlingAI dynamicMasks trajectories must be an array.")
        }
        for (trajectoryIndex, trajectory) in trajectories.enumerated() {
            guard let point = trajectory.objectValue,
                  point["x"]?.doubleValue != nil,
                  point["y"]?.doubleValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.klingai.dynamicMasks[\(index)].trajectories[\(trajectoryIndex)]", message: "KlingAI trajectory x and y must be numbers.")
            }
        }
    }
    return value
}

private func klingAIVideoMetadata(from videos: [JSONValue]) -> [JSONValue] {
    videos.map { video in
        .object([
            "id": video["id"]?.stringValue.map(JSONValue.string),
            "url": video["url"]?.stringValue.map(JSONValue.string),
            "watermarkUrl": video["watermark_url"]?.stringValue.map(JSONValue.string),
            "duration": video["duration"]?.stringValue.map(JSONValue.string)
        ])
    }
}

private func klingAIMoveSharedOptions(_ options: [String: JSONValue], to output: inout [String: JSONValue]) {
    if let negativePrompt = options["negativePrompt"] { output["negative_prompt"] = negativePrompt }
    if let sound = options["sound"] { output["sound"] = sound }
    if let cfgScale = options["cfgScale"] { output["cfg_scale"] = cfgScale }
    if let mode = options["mode"] { output["mode"] = mode }
    if let cameraControl = options["cameraControl"] { output["camera_control"] = cameraControl }
    if let multiShot = options["multiShot"] { output["multi_shot"] = multiShot }
    if let shotType = options["shotType"] { output["shot_type"] = shotType }
    if let multiPrompt = options["multiPrompt"] { output["multi_prompt"] = multiPrompt }
    if let voiceList = options["voiceList"] { output["voice_list"] = voiceList }
    if let watermarkEnabled = options["watermarkEnabled"] {
        output["watermark_info"] = .object(["enabled": watermarkEnabled])
    }
}

private func klingAIImageInput(from options: [String: JSONValue]) -> JSONValue? {
    let value = options["image"] ?? options["imageUrl"] ?? options["image_url"]
    if let object = value?.objectValue {
        return object["url"] ?? object["data"]
    }
    return value
}

private func klingAIImageInput(from image: ImageInputFile?) throws -> JSONValue? {
    guard let image else { return nil }
    if let url = image.url {
        return .string(url)
    }
    if let data = image.data {
        return .string(data.base64EncodedString())
    }
    throw AIError.invalidArgument(argument: "image", message: "KlingAI video image input requires data or URL.")
}

private func klingAIPollInterval(_ value: JSONValue?) -> UInt64 {
    let milliseconds = value?.doubleValue ?? 5_000
    return UInt64(max(milliseconds, 1) * 1_000_000)
}

private func klingAIPollTimeout(_ value: JSONValue?) -> UInt64 {
    let milliseconds = value?.doubleValue ?? 600_000
    return UInt64(max(milliseconds, 1) * 1_000_000)
}

public final class ByteDanceVideoModel: VideoModel, @unchecked Sendable {
    public let providerID = "bytedance.video"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        let options = try byteDanceProviderOptions(from: request)
        let warnings = byteDanceWarnings(for: request)
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "content": .array(try byteDanceContent(prompt: request.prompt, image: request.image, options: options))
        ]
        if let aspectRatio = request.aspectRatio { body["ratio"] = .string(aspectRatio) }
        if let duration = request.durationSeconds { body["duration"] = .number(duration) }
        if let seed = request.seed { body["seed"] = .number(Double(seed)) }
        if let resolution = request.resolution {
            body["resolution"] = .string(byteDanceResolutionMap[resolution] ?? resolution)
        }
        body.merge(byteDanceOptions(from: options)) { _, new in new }

        let created = try await config.sendJSONResponse(path: "/contents/generations/tasks", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        guard let taskID = created.json["id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "ByteDance create response did not contain id.")
        }
        let finalResponse = try await pollByteDance(
            taskID: taskID,
            headers: request.headers,
            intervalNanoseconds: byteDancePollInterval(options.known["pollIntervalMs"]),
            timeoutNanoseconds: byteDancePollTimeout(options.known["pollTimeoutMs"]),
            abortSignal: request.abortSignal
        )
        let raw = finalResponse.raw
        guard let url = raw["content"]?["video_url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "ByteDance status response did not contain content.video_url.")
        }
        return VideoGenerationResult(
            urls: [url],
            operationID: taskID,
            rawValue: raw,
            warnings: warnings,
            providerMetadata: [
                "bytedance": .object([
                    "taskId": .string(taskID),
                    "usage": raw["usage"]
                ])
            ],
            requestMetadata: videoGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: finalResponse.response, modelID: modelID)
        )
    }

    private func pollByteDance(taskID: String, headers: [String: String], intervalNanoseconds: UInt64, timeoutNanoseconds: UInt64, abortSignal: AIAbortSignal?) async throws -> (raw: JSONValue, response: AIHTTPResponse) {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            let response = try await config.transport.send(AIHTTPRequest(
                method: "GET",
                url: try requireURL("\(withoutTrailingSlash(config.baseURL))/contents/generations/tasks/\(taskID)"),
                headers: config.headers.mergingHeaders(headers),
                abortSignal: abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            switch raw["status"]?.stringValue {
            case "succeeded":
                return (raw, response)
            case "failed":
                throw AIError.invalidResponse(provider: providerID, message: "ByteDance video generation failed.")
            default:
                if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                    throw AIError.invalidResponse(provider: providerID, message: "ByteDance video generation timed out.")
                }
                try await sleepWithAbortSignal(nanoseconds: intervalNanoseconds, abortSignal: abortSignal)
            }
        }
    }
}

private struct ByteDanceResolvedOptions {
    var known: [String: JSONValue]
    var passthrough: [String: JSONValue]
}

private func byteDanceProviderOptions(from request: VideoGenerationRequest) throws -> ByteDanceResolvedOptions {
    var output = try byteDanceExtraBodyOptions(from: request.extraBody)
    if let providerValue = request.providerOptions["bytedance"] {
        guard providerValue != .null else { return output }
        guard let providerOptions = providerValue.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.bytedance", message: "ByteDance provider options must be an object.")
        }
        let parsed = try byteDanceValidatedProviderOptions(from: providerOptions)
        for (key, value) in parsed.known {
            if value == .null {
                output.known.removeValue(forKey: key)
            } else {
                output.known[key] = value
            }
        }
        output.passthrough.merge(parsed.passthrough) { _, providerValue in providerValue }
    }
    return output
}

private func byteDanceExtraBodyOptions(from extraBody: [String: JSONValue]) throws -> ByteDanceResolvedOptions {
    var passthrough = extraBody["bytedance"]?.objectValue ?? extraBody.filter { key, _ in key != "bytedance" }
    var known: [String: JSONValue] = [:]
    for (key, canonicalKey) in byteDanceExtraBodyOptionAliases {
        if let value = passthrough.removeValue(forKey: key), value != .null {
            known[canonicalKey] = value
        }
    }
    return ByteDanceResolvedOptions(known: known, passthrough: passthrough)
}

private func byteDanceContent(prompt: String, image: ImageInputFile?, options: ByteDanceResolvedOptions) throws -> [JSONValue] {
    var content: [JSONValue] = []
    let known = options.known
    if !prompt.isEmpty {
        content.append(.object(["type": .string("text"), "text": .string(prompt)]))
    }
    if let image = try byteDanceMediaURL(from: image) ?? byteDanceMediaURL(known["image"]) {
        content.append(.object(["type": .string("image_url"), "image_url": .object(["url": .string(image)])]))
    }
    if let lastFrameImage = byteDanceMediaURL(known["lastFrameImage"]) {
        content.append(.object([
            "type": .string("image_url"),
            "image_url": .object(["url": .string(lastFrameImage)]),
            "role": .string("last_frame")
        ]))
    }
    for imageURL in byteDanceMediaURLs(known["referenceImages"]) {
        content.append(.object([
            "type": .string("image_url"),
            "image_url": .object(["url": .string(imageURL)]),
            "role": .string("reference_image")
        ]))
    }
    for videoURL in byteDanceMediaURLs(known["referenceVideos"]) {
        content.append(.object([
            "type": .string("video_url"),
            "video_url": .object(["url": .string(videoURL)]),
            "role": .string("reference_video")
        ]))
    }
    for audioURL in byteDanceMediaURLs(known["referenceAudio"]) {
        content.append(.object([
            "type": .string("audio_url"),
            "audio_url": .object(["url": .string(audioURL)]),
            "role": .string("reference_audio")
        ]))
    }
    return content
}

private func byteDanceOptions(from options: ByteDanceResolvedOptions) -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    let known = options.known
    if let seed = known["seed"] { output["seed"] = seed }
    if let resolution = known["resolution"]?.stringValue {
        output["resolution"] = .string(byteDanceResolutionMap[resolution] ?? resolution)
    }
    if let watermark = known["watermark"] { output["watermark"] = watermark }
    if let generateAudio = known["generateAudio"] { output["generate_audio"] = generateAudio }
    if let cameraFixed = known["cameraFixed"] { output["camera_fixed"] = cameraFixed }
    if let returnLastFrame = known["returnLastFrame"] { output["return_last_frame"] = returnLastFrame }
    if let serviceTier = known["serviceTier"] { output["service_tier"] = serviceTier }
    if let draft = known["draft"] { output["draft"] = draft }
    output.merge(options.passthrough) { _, new in new }
    return output
}

private func byteDanceWarnings(for request: VideoGenerationRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.fps != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "fps",
            message: "ByteDance video models do not support custom FPS. Frame rate is fixed at 24 fps."
        ))
    }
    if let count = request.count, count > 1 {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "n",
            message: "ByteDance video models do not support generating multiple videos per call. Only 1 video will be generated."
        ))
    }
    return warnings
}

private let byteDanceProviderOptionKeys: Set<String> = [
    "watermark",
    "generateAudio",
    "cameraFixed",
    "returnLastFrame",
    "serviceTier",
    "draft",
    "lastFrameImage",
    "referenceImages",
    "referenceVideos",
    "referenceAudio",
    "pollIntervalMs",
    "pollTimeoutMs"
]

private let byteDanceExtraBodyOptionAliases: [String: String] = [
    "image": "image",
    "imageUrl": "image",
    "image_url": "image",
    "lastFrameImage": "lastFrameImage",
    "last_frame_image": "lastFrameImage",
    "referenceImages": "referenceImages",
    "reference_images": "referenceImages",
    "referenceVideos": "referenceVideos",
    "reference_videos": "referenceVideos",
    "referenceAudio": "referenceAudio",
    "reference_audio": "referenceAudio",
    "watermark": "watermark",
    "generateAudio": "generateAudio",
    "generate_audio": "generateAudio",
    "cameraFixed": "cameraFixed",
    "camera_fixed": "cameraFixed",
    "returnLastFrame": "returnLastFrame",
    "return_last_frame": "returnLastFrame",
    "serviceTier": "serviceTier",
    "service_tier": "serviceTier",
    "draft": "draft",
    "seed": "seed",
    "resolution": "resolution",
    "pollIntervalMs": "pollIntervalMs",
    "pollTimeoutMs": "pollTimeoutMs"
]

private func byteDanceValidatedProviderOptions(from providerOptions: [String: JSONValue]) throws -> ByteDanceResolvedOptions {
    var known: [String: JSONValue] = [:]
    var valuesToValidate: [String: JSONValue] = [:]
    var passthrough = providerOptions
    for key in byteDanceProviderOptionKeys {
        if let value = passthrough.removeValue(forKey: key) {
            if value == .null {
                known[key] = .null
            } else {
                valuesToValidate[key] = value
            }
        }
    }
    known.merge(try byteDanceValidateKnownOptions(valuesToValidate)) { _, validated in validated }
    return ByteDanceResolvedOptions(known: known, passthrough: passthrough)
}

private func byteDanceValidateKnownOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options {
        switch key {
        case "watermark", "generateAudio", "cameraFixed", "returnLastFrame", "draft":
            guard value.boolValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.bytedance.\(key)", message: "ByteDance \(key) must be a boolean.")
            }
            output[key] = value
        case "serviceTier":
            guard let serviceTier = value.stringValue, ["default", "flex"].contains(serviceTier) else {
                throw AIError.invalidArgument(argument: "providerOptions.bytedance.serviceTier", message: "ByteDance serviceTier must be one of default, flex.")
            }
            output[key] = value
        case "lastFrameImage":
            guard value.stringValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.bytedance.lastFrameImage", message: "ByteDance lastFrameImage must be a string.")
            }
            output[key] = value
        case "referenceImages", "referenceVideos", "referenceAudio":
            output[key] = try byteDanceStringArray(value, key: key)
        case "pollIntervalMs", "pollTimeoutMs":
            guard let number = value.doubleValue, number > 0 else {
                throw AIError.invalidArgument(argument: "providerOptions.bytedance.\(key)", message: "ByteDance \(key) must be a positive number.")
            }
            output[key] = value
        case "image", "seed", "resolution":
            output[key] = value
        default:
            output[key] = value
        }
    }
    return output
}

private func byteDanceStringArray(_ value: JSONValue, key: String) throws -> JSONValue {
    guard let array = value.arrayValue else {
        throw AIError.invalidArgument(argument: "providerOptions.bytedance.\(key)", message: "ByteDance \(key) must be an array of strings.")
    }
    for (index, item) in array.enumerated() where item.stringValue == nil {
        throw AIError.invalidArgument(argument: "providerOptions.bytedance.\(key)[\(index)]", message: "ByteDance \(key) values must be strings.")
    }
    return value
}

private let byteDanceResolutionMap: [String: String] = [
    "864x496": "480p", "496x864": "480p", "752x560": "480p", "560x752": "480p",
    "640x640": "480p", "992x432": "480p", "432x992": "480p", "864x480": "480p",
    "480x864": "480p", "736x544": "480p", "544x736": "480p", "960x416": "480p",
    "416x960": "480p", "832x480": "480p", "480x832": "480p", "624x624": "480p",
    "1280x720": "720p", "720x1280": "720p", "1112x834": "720p", "834x1112": "720p",
    "960x960": "720p", "1470x630": "720p", "630x1470": "720p", "1248x704": "720p",
    "704x1248": "720p", "1120x832": "720p", "832x1120": "720p", "1504x640": "720p",
    "640x1504": "720p", "1920x1080": "1080p", "1080x1920": "1080p",
    "1664x1248": "1080p", "1248x1664": "1080p", "1440x1440": "1080p",
    "2206x946": "1080p", "946x2206": "1080p", "1920x1088": "1080p",
    "1088x1920": "1080p", "2176x928": "1080p", "928x2176": "1080p"
]

private func byteDanceMediaURL(_ value: JSONValue?) -> String? {
    if let string = value?.stringValue { return string }
    if let object = value?.objectValue {
        return object["url"]?.stringValue ?? object["data"]?.stringValue
    }
    return nil
}

private func byteDanceMediaURL(from image: ImageInputFile?) throws -> String? {
    guard let image else { return nil }
    if let url = image.url {
        return url
    }
    if let data = image.data {
        let mediaType = image.mediaType ?? "application/octet-stream"
        return "data:\(mediaType);base64,\(data.base64EncodedString())"
    }
    throw AIError.invalidArgument(argument: "image", message: "ByteDance video image input requires data or URL.")
}

private func byteDanceMediaURLs(_ value: JSONValue?) -> [String] {
    if let url = byteDanceMediaURL(value) { return [url] }
    return value?.arrayValue?.compactMap(byteDanceMediaURL) ?? []
}

private func byteDancePollInterval(_ value: JSONValue?) -> UInt64 {
    let milliseconds = value?.doubleValue ?? 3_000
    return UInt64(max(milliseconds, 1) * 1_000_000)
}

private func byteDancePollTimeout(_ value: JSONValue?) -> UInt64 {
    let milliseconds = value?.doubleValue ?? 300_000
    return UInt64(max(milliseconds, 1) * 1_000_000)
}

public final class AlibabaVideoModel: VideoModel, @unchecked Sendable {
    public let providerID = "alibaba.video"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        let mode = alibabaVideoMode(modelID)
        let options = try alibabaVideoProviderOptions(from: request)
        let warnings = alibabaVideoWarnings(for: request)
        var input: [String: JSONValue] = [:]
        if !request.prompt.isEmpty { input["prompt"] = .string(request.prompt) }
        if let negativePrompt = options["negativePrompt"] ?? options["negative_prompt"] {
            input["negative_prompt"] = negativePrompt
        }
        if let audioURL = options["audioUrl"] ?? options["audio_url"] {
            input["audio_url"] = audioURL
        }
        if mode == "i2v", let image = alibabaVideoImageInput(from: request, options: options) {
            input["img_url"] = image
        }
        if mode == "r2v", let referenceURLs = options["referenceUrls"] ?? options["reference_urls"] {
            input["reference_urls"] = referenceURLs
        }

        var parameters: [String: JSONValue] = [:]
        if let duration = request.durationSeconds { parameters["duration"] = .number(duration) }
        if let seed = request.seed {
            parameters["seed"] = .number(Double(seed))
        } else if let seed = options["seed"] {
            parameters["seed"] = seed
        }
        if let resolution = request.resolution ?? options["resolution"]?.stringValue {
            if mode == "i2v" {
                parameters["resolution"] = .string(alibabaResolution(resolution))
            } else {
                parameters["size"] = .string(resolution.replacingOccurrences(of: "x", with: "*"))
            }
        }
        if let promptExtend = options["promptExtend"] ?? options["prompt_extend"] { parameters["prompt_extend"] = promptExtend }
        if let shotType = options["shotType"] ?? options["shot_type"] { parameters["shot_type"] = shotType }
        if let watermark = options["watermark"] { parameters["watermark"] = watermark }
        if let audio = options["audio"] { parameters["audio"] = audio }
        let body: JSONValue = .object([
            "model": .string(modelID),
            "input": .object(input),
            "parameters": .object(parameters)
        ])
        let base = alibabaNativeBaseURL(config.baseURL)
        let createResponse = try await config.transport.send(config.request(
            path: "/api/v1/services/aigc/video-generation/video-synthesis",
            modelID: modelID,
            body: body,
            headers: request.headers.mergingHeaders(["X-DashScope-Async": "enable"]),
            abortSignal: request.abortSignal
        ).withURL(try requireURL("\(base)/api/v1/services/aigc/video-generation/video-synthesis")))
        guard (200..<300).contains(createResponse.statusCode) else {
            throw httpStatusError(provider: providerID, response: createResponse)
        }
        let created = try createResponse.jsonValue()
        guard let taskID = created["output"]?["task_id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Alibaba video create response did not contain output.task_id.")
        }
        let raw = try await pollAlibaba(
            taskID: taskID,
            base: base,
            headers: request.headers,
            intervalNanoseconds: alibabaPollInterval(options),
            timeoutNanoseconds: alibabaPollTimeout(options),
            abortSignal: request.abortSignal
        )
        guard let url = raw.raw["output"]?["video_url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Alibaba video status response did not contain output.video_url.")
        }
        return VideoGenerationResult(
            urls: [url],
            operationID: taskID,
            rawValue: raw.raw,
            warnings: warnings,
            providerMetadata: alibabaVideoProviderMetadata(taskID: taskID, raw: raw.raw, videoURL: url),
            requestMetadata: videoGenerationRequestMetadata(request, body: body),
            responseMetadata: aiResponseMetadata(from: raw.raw, response: raw.response, modelID: modelID)
        )
    }

    private func pollAlibaba(taskID: String, base: String, headers: [String: String], intervalNanoseconds: UInt64, timeoutNanoseconds: UInt64, abortSignal: AIAbortSignal?) async throws -> AlibabaPollResult {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            let response = try await config.transport.send(AIHTTPRequest(
                method: "GET",
                url: try requireURL("\(base)/api/v1/tasks/\(taskID)"),
                headers: config.headers.mergingHeaders(headers),
                abortSignal: abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            switch raw["output"]?["task_status"]?.stringValue {
            case "SUCCEEDED":
                return AlibabaPollResult(raw: raw, response: response)
            case "FAILED", "CANCELED":
                throw AIError.invalidResponse(provider: providerID, message: raw["output"]?["message"]?.stringValue ?? "Alibaba video generation failed.")
            default:
                if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                    throw AIError.invalidResponse(provider: providerID, message: "Alibaba video generation timed out.")
                }
                try await sleepWithAbortSignal(nanoseconds: intervalNanoseconds, abortSignal: abortSignal)
            }
        }
    }
}

public final class ProdiaLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "prodia.language"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        try await prodiaGenerate(request).result
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let generated = try await prodiaGenerate(request)
                    let result = generated.result
                    continuation.yield(.streamStart(warnings: result.warnings))
                    continuation.yield(.responseMetadata(result.responseMetadata))
                    if !result.text.isEmpty {
                        let id = UUID().uuidString
                        continuation.yield(.textStart(id: id))
                        continuation.yield(.textDeltaPart(id: id, delta: result.text))
                        continuation.yield(.textEnd(id: id))
                    }
                    for file in generated.files {
                        continuation.yield(.file(file))
                    }
                    continuation.yield(.finishMetadata(reason: result.finishReason, usage: result.usage, providerMetadata: result.providerMetadata))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func prodiaGenerate(_ request: LanguageModelRequest) async throws -> ProdiaLanguageGeneration {
        let options = try prodiaProviderOptions(from: request)
        let warnings = prodiaLanguageWarnings(for: request)
        var jobConfig: [String: JSONValue] = [
            "prompt": .string(prodiaPrompt(from: request.messages)),
            "include_messages": .bool(true)
        ]
        if let aspectRatio = options["aspectRatio"]?.stringValue ?? options["aspect_ratio"]?.stringValue {
            jobConfig["aspect_ratio"] = .string(aspectRatio)
        }

        let body: JSONValue = .object([
            "type": .string(modelID),
            "config": .object(jobConfig)
        ])
        var form = MultipartFormData()
        form.appendFile(name: "job", fileName: "job.json", mimeType: "application/json", data: try encodeJSONBody(body))
        if let input = try await prodiaInputImage(from: request.messages, transport: config.transport, abortSignal: request.abortSignal) {
            form.appendFile(name: "input", fileName: "input\(mediaExtension(input.mimeType))", mimeType: input.mimeType, data: input.data)
        }
        let payload = form.finalize()
        var headers = request.headers.mergingHeaders([
            "Accept": "multipart/form-data",
            "Content-Type": "multipart/form-data; boundary=\(form.boundary)"
        ])
        headers = config.headers.mergingHeaders(headers)
        let response = try await config.transport.send(AIHTTPRequest(
            method: "POST",
            url: try requireURL("\(withoutTrailingSlash(config.baseURL))/job?price=true"),
            headers: headers,
            body: payload,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        let multipart = try parseMultipartResponse(response)
        guard multipart.contains(where: { $0.name == "job" }) else {
            throw AIError.invalidResponse(provider: providerID, message: "Prodia language response did not contain job part.")
        }
        let text = multipart.first {
            ($0.name == "output" && ($0.contentType?.hasPrefix("text/") == true || $0.fileName?.hasSuffix(".txt") == true))
                || $0.contentType?.hasPrefix("text/") == true
        }.flatMap { String(data: $0.body, encoding: .utf8) } ?? ""
        let job = prodiaJobResult(from: multipart)
        let files = prodiaLanguageFiles(from: multipart)
        let rawValue = multipartRawValue(multipart)
        return ProdiaLanguageGeneration(
            result: TextGenerationResult(
                text: text,
                finishReason: "stop",
                usage: TokenUsage(),
                providerMetadata: ["prodia": prodiaProviderMetadata(from: job)],
                rawValue: rawValue,
                warnings: warnings,
                responseMetadata: aiResponseMetadata(from: job, response: response, modelID: modelID)
            ),
            files: files
        )
    }
}

public final class ProdiaImageModel: ImageModel, @unchecked Sendable {
    public let providerID = "prodia.image"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        let options = try prodiaProviderOptions(from: request)
        var warnings: [AIWarning] = []
        var jobConfig: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let size = request.size {
            let parts = size.split(separator: "x", omittingEmptySubsequences: false).map(String.init)
            if parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) {
                jobConfig["width"] = .number(Double(width))
                jobConfig["height"] = .number(Double(height))
            } else {
                warnings.append(AIWarning(
                    type: "unsupported",
                    feature: "size",
                    message: "Invalid size format: \(size). Expected format: WIDTHxHEIGHT (e.g., 1024x1024)"
                ))
            }
        }
        if let seed = request.seed {
            jobConfig["seed"] = .number(Double(seed))
        }
        jobConfig.merge(prodiaImageOptions(from: options)) { _, new in new }
        let body: JSONValue = .object([
            "type": .string(modelID),
            "config": .object(jobConfig)
        ])
        let response = try await config.transport.send(config.request(
            path: "/job?price=true",
            modelID: modelID,
            body: body,
            headers: request.headers.mergingHeaders(["Accept": "multipart/form-data; image/png"]),
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        let multipart = try parseMultipartResponse(response)
        let output = multipart.first { $0.name == "output" || $0.contentType?.hasPrefix("image/") == true }
        guard let output else {
            throw AIError.invalidResponse(provider: providerID, message: "Prodia image response did not contain output image part.")
        }
        let job = prodiaJobResult(from: multipart)
        return ImageGenerationResult(
            urls: [],
            base64Images: [output.body.base64EncodedString()],
            rawValue: multipartRawValue(multipart),
            warnings: warnings,
            providerMetadata: ["prodia": .object(["images": .array([prodiaProviderMetadata(from: job)])])],
            requestMetadata: imageGenerationRequestMetadata(request, body: body),
            responseMetadata: aiResponseMetadata(from: job, response: response, modelID: modelID)
        )
    }
}

public final class ProdiaVideoModel: VideoModel, @unchecked Sendable {
    public let providerID = "prodia.video"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        let options = try prodiaProviderOptions(from: request)
        var jobConfig: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let seed = request.seed {
            jobConfig["seed"] = .number(Double(seed))
        } else if let seed = options["seed"] {
            jobConfig["seed"] = seed
        }
        if let resolution = options["resolution"] { jobConfig["resolution"] = resolution }
        let body: JSONValue = .object([
            "type": .string(modelID),
            "config": .object(jobConfig)
        ])
        let response: AIHTTPResponse
        if let image = request.image {
            let input = try await prodiaVideoInputImage(from: image, transport: config.transport, abortSignal: request.abortSignal)
            var form = MultipartFormData()
            form.appendFile(name: "job", fileName: "job.json", mimeType: "application/json", data: try encodeJSONBody(body))
            form.appendFile(name: "input", fileName: "input\(mediaExtension(input.mimeType))", mimeType: input.mimeType, data: input.data)
            let payload = form.finalize()
            let headers = config.headers.mergingHeaders(request.headers).mergingHeaders([
                "Accept": "multipart/form-data; video/mp4",
                "Content-Type": "multipart/form-data; boundary=\(form.boundary)"
            ])
            response = try await config.transport.send(AIHTTPRequest(
                method: "POST",
                url: try requireURL("\(withoutTrailingSlash(config.baseURL))/job?price=true"),
                headers: headers,
                body: payload,
                abortSignal: request.abortSignal
            ))
        } else {
            response = try await config.transport.send(config.request(
                path: "/job?price=true",
                modelID: modelID,
                body: body,
                headers: request.headers.mergingHeaders(["Accept": "multipart/form-data; video/mp4"]),
                abortSignal: request.abortSignal
            ))
        }
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        let multipart = try parseMultipartResponse(response)
        let output = multipart.first { $0.name == "output" || $0.contentType?.hasPrefix("video/") == true }
        guard output != nil else {
            throw AIError.invalidResponse(provider: providerID, message: "Prodia video response did not contain output video part.")
        }
        let job = prodiaJobResult(from: multipart)
        return VideoGenerationResult(
            urls: [],
            operationID: job?["id"]?.stringValue,
            rawValue: multipartRawValue(multipart),
            providerMetadata: ["prodia": .object(["videos": .array([prodiaProviderMetadata(from: job)])])],
            requestMetadata: videoGenerationRequestMetadata(request, body: body),
            responseMetadata: aiResponseMetadata(from: job, response: response, modelID: modelID)
        )
    }
}

private struct ProdiaLanguageGeneration {
    var result: TextGenerationResult
    var files: [AIStreamFile]
}

private func prodiaProviderOptions(from request: LanguageModelRequest) throws -> [String: JSONValue] {
    try prodiaProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions, validateProviderOptions: prodiaValidateLanguageProviderOptions)
}

private func prodiaProviderOptions(from request: ImageGenerationRequest) throws -> [String: JSONValue] {
    try prodiaProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions, validateProviderOptions: prodiaValidateImageProviderOptions)
}

private func prodiaProviderOptions(from request: VideoGenerationRequest) throws -> [String: JSONValue] {
    try prodiaProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions, validateProviderOptions: prodiaValidateVideoProviderOptions)
}

private func prodiaProviderOptions(
    extraBody: [String: JSONValue],
    providerOptions: [String: JSONValue],
    validateProviderOptions: ([String: JSONValue]) throws -> [String: JSONValue]
) throws -> [String: JSONValue] {
    var output = prodiaProviderOptions(from: extraBody)
    if let value = providerOptions["prodia"] {
        guard value != .null else {
            return output
        }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.prodia", message: "Prodia provider options must be an object.")
        }
        output.merge(try validateProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

private func prodiaProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    if let nested = extraBody["prodia"]?.objectValue {
        return nested
    }
    var output = extraBody
    output.removeValue(forKey: "prodia")
    return output
}

private let prodiaLanguageProviderOptionKeys: Set<String> = [
    "aspectRatio"
]

private let prodiaImageProviderOptionKeys: Set<String> = [
    "steps",
    "width",
    "height",
    "stylePreset",
    "loras",
    "progressive"
]

private let prodiaVideoProviderOptionKeys: Set<String> = [
    "resolution"
]

private let prodiaAspectRatios: Set<String> = [
    "1:1",
    "2:3",
    "3:2",
    "4:5",
    "5:4",
    "4:7",
    "7:4",
    "9:16",
    "16:9",
    "9:21",
    "21:9"
]

private let prodiaStylePresets: Set<String> = [
    "3d-model",
    "analog-film",
    "anime",
    "cinematic",
    "comic-book",
    "digital-art",
    "enhance",
    "fantasy-art",
    "isometric",
    "line-art",
    "low-poly",
    "neon-punk",
    "origami",
    "photographic",
    "pixel-art",
    "texture",
    "craft-clay"
]

private func prodiaValidateLanguageProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where prodiaLanguageProviderOptionKeys.contains(key) {
        switch key {
        case "aspectRatio":
            try prodiaRequireEnum(value, argument: "providerOptions.prodia.aspectRatio", label: "aspectRatio", allowed: prodiaAspectRatios)
            output[key] = value
        default:
            break
        }
    }
    return output
}

private func prodiaValidateImageProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where prodiaImageProviderOptionKeys.contains(key) {
        switch key {
        case "steps":
            try prodiaRequireInteger(value, argument: "providerOptions.prodia.steps", label: "steps", min: 1, max: 4)
        case "width", "height":
            try prodiaRequireInteger(value, argument: "providerOptions.prodia.\(key)", label: key, min: 256, max: 1920)
        case "stylePreset":
            try prodiaRequireEnum(value, argument: "providerOptions.prodia.stylePreset", label: "stylePreset", allowed: prodiaStylePresets)
        case "loras":
            try prodiaRequireStringArray(value, argument: "providerOptions.prodia.loras", label: "loras", maxCount: 3)
        case "progressive":
            try prodiaRequireBoolean(value, argument: "providerOptions.prodia.progressive", label: "progressive")
        default:
            break
        }
        output[key] = value
    }
    return output
}

private func prodiaValidateVideoProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where prodiaVideoProviderOptionKeys.contains(key) {
        switch key {
        case "resolution":
            try prodiaRequireString(value, argument: "providerOptions.prodia.resolution", label: "resolution")
            output[key] = value
        default:
            break
        }
    }
    return output
}

private func prodiaRequireString(_ value: JSONValue, argument: String, label: String) throws {
    guard value.stringValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: "Prodia \(label) must be a string.")
    }
}

private func prodiaRequireBoolean(_ value: JSONValue, argument: String, label: String) throws {
    guard value.boolValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: "Prodia \(label) must be a boolean.")
    }
}

private func prodiaRequireInteger(_ value: JSONValue, argument: String, label: String, min: Int, max: Int) throws {
    guard let number = value.doubleValue, number.isFinite, number.rounded() == number else {
        throw AIError.invalidArgument(argument: argument, message: "Prodia \(label) must be an integer.")
    }
    if number < Double(min) || number > Double(max) {
        throw AIError.invalidArgument(argument: argument, message: "Prodia \(label) must be an integer between \(min) and \(max).")
    }
}

private func prodiaRequireEnum(_ value: JSONValue, argument: String, label: String, allowed: Set<String>) throws {
    guard let string = value.stringValue, allowed.contains(string) else {
        throw AIError.invalidArgument(argument: argument, message: "Prodia \(label) must be one of \(allowed.sorted().joined(separator: ", ")).")
    }
}

private func prodiaRequireStringArray(_ value: JSONValue, argument: String, label: String, maxCount: Int) throws {
    guard let array = value.arrayValue, array.allSatisfy({ $0.stringValue != nil }) else {
        throw AIError.invalidArgument(argument: argument, message: "Prodia \(label) must be an array of strings.")
    }
    guard array.count <= maxCount else {
        throw AIError.invalidArgument(argument: argument, message: "Prodia \(label) must contain at most \(maxCount) values.")
    }
}

private func prodiaImageOptions(from options: [String: JSONValue]) -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    if let width = options["width"] { output["width"] = width }
    if let height = options["height"] { output["height"] = height }
    if let seed = options["seed"] { output["seed"] = seed }
    if let steps = options["steps"] { output["steps"] = steps }
    if let stylePreset = options["stylePreset"] ?? options["style_preset"] { output["style_preset"] = stylePreset }
    if let loras = options["loras"] { output["loras"] = loras }
    if let progressive = options["progressive"] { output["progressive"] = progressive }
    return output
}

private func prodiaLanguageWarnings(for request: LanguageModelRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.temperature != nil { warnings.append(AIWarning(type: "unsupported", feature: "temperature")) }
    if request.topP != nil { warnings.append(AIWarning(type: "unsupported", feature: "topP")) }
    if request.topK != nil { warnings.append(AIWarning(type: "unsupported", feature: "topK")) }
    if request.maxOutputTokens != nil { warnings.append(AIWarning(type: "unsupported", feature: "maxOutputTokens")) }
    if !request.stopSequences.isEmpty { warnings.append(AIWarning(type: "unsupported", feature: "stopSequences")) }
    if request.presencePenalty != nil { warnings.append(AIWarning(type: "unsupported", feature: "presencePenalty")) }
    if request.frequencyPenalty != nil { warnings.append(AIWarning(type: "unsupported", feature: "frequencyPenalty")) }
    if !request.tools.isEmpty { warnings.append(AIWarning(type: "unsupported", feature: "tools")) }
    if request.toolChoice != nil { warnings.append(AIWarning(type: "unsupported", feature: "toolChoice")) }
    if case .json = request.responseFormat {
        warnings.append(AIWarning(type: "unsupported", feature: "responseFormat"))
    }
    if request.reasoning != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "reasoning",
            message: "This provider does not support reasoning configuration."
        ))
    }
    return warnings
}

private func prodiaJobResult(from parts: [MultipartResponsePart]) -> JSONValue? {
    parts.first { $0.name == "job" }?.json
}

private func prodiaProviderMetadata(from jobResult: JSONValue?) -> JSONValue {
    guard let jobResult else { return .object([:]) }
    var metadata: [String: JSONValue] = [:]
    if let jobID = jobResult["id"]?.stringValue {
        metadata["jobId"] = .string(jobID)
    }
    if let seed = jobResult["config"]?["seed"] {
        metadata["seed"] = seed
    }
    if let elapsed = jobResult["metrics"]?["elapsed"] {
        metadata["elapsed"] = elapsed
    }
    if let ips = jobResult["metrics"]?["ips"] {
        metadata["iterationsPerSecond"] = ips
    }
    if let createdAt = jobResult["created_at"]?.stringValue {
        metadata["createdAt"] = .string(createdAt)
    }
    if let updatedAt = jobResult["updated_at"]?.stringValue {
        metadata["updatedAt"] = .string(updatedAt)
    }
    if let dollars = jobResult["price"]?["dollars"] {
        metadata["dollars"] = dollars
    }
    return .object(metadata)
}

private func prodiaLanguageFiles(from parts: [MultipartResponsePart]) -> [AIStreamFile] {
    parts.compactMap { part in
        guard part.name == "output", let contentType = part.contentType, contentType.hasPrefix("image/") else {
            return nil
        }
        return AIStreamFile(
            mediaType: contentType,
            data: part.body,
            filename: part.fileName,
            rawValue: .object([
                "name": part.name.map(JSONValue.string),
                "fileName": part.fileName.map(JSONValue.string),
                "contentType": .string(contentType),
                "base64": .string(part.body.base64EncodedString())
            ])
        )
    }
}

private func splitVersionedModelID(_ modelID: String) -> (model: String, version: String?) {
    let parts = modelID.split(separator: ":", maxSplits: 1).map(String.init)
    return (parts[0], parts.count > 1 ? parts[1] : nil)
}

private func klingMode(_ modelID: String) throws -> String {
    if modelID.hasSuffix("-motion-control") { return "motion-control" }
    if modelID.hasSuffix("-i2v") { return "i2v" }
    if modelID.hasSuffix("-t2v") { return "t2v" }
    throw AIError.unsupportedModel(provider: "klingai", capability: .video, modelID: modelID)
}

private func klingEndpoint(_ mode: String) -> String {
    switch mode {
    case "i2v":
        return "/v1/videos/image2video"
    case "motion-control":
        return "/v1/videos/motion-control"
    default:
        return "/v1/videos/text2video"
    }
}

private func klingAPIModelName(_ modelID: String, mode: String) -> String {
    let suffix = mode == "motion-control" ? "-motion-control" : "-\(mode)"
    let base = modelID.hasSuffix(suffix) ? String(modelID.dropLast(suffix.count)) : modelID
    let normalized = base.hasSuffix(".0") ? String(base.dropLast(2)) : base
    return normalized.replacingOccurrences(of: ".", with: "-")
}

private func mediaURLs(from value: JSONValue?) -> [String] {
    if let string = value?.stringValue { return [string] }
    return value?.arrayValue?.compactMap(\.stringValue) ?? []
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
        guard key != "image" && key != "images" else { continue }
        fal[falMetadataKey(key)] = value
    }
    return fal.isEmpty ? [:] : ["fal": .object(fal)]
}

private func falImageMetadataObjects(from raw: JSONValue) -> [[String: JSONValue]] {
    if let images = raw["images"]?.arrayValue {
        return images.compactMap { falSingleImageMetadata(from: $0) }
    }
    if let image = raw["image"], image.objectValue != nil {
        return [falSingleImageMetadata(from: image)].compactMap { $0 }
    }
    return []
}

private func falSingleImageMetadata(from image: JSONValue) -> [String: JSONValue]? {
    guard let object = image.objectValue else { return nil }
    var metadata: [String: JSONValue] = [:]
    for (key, value) in object where key != "url" {
        metadata[falMetadataKey(key)] = value
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

private func formatDuration(_ duration: Double) -> String {
    duration.rounded() == duration ? String(Int(duration)) : String(duration)
}

private func sizeToAspectRatio(_ size: String) -> String {
    let dimensions = size.split(separator: "x").compactMap { Int($0) }
    guard dimensions.count == 2 else { return size }
    let divisor = gcd(dimensions[0], dimensions[1])
    return "\(dimensions[0] / divisor):\(dimensions[1] / divisor)"
}

private func alibabaVideoMode(_ modelID: String) -> String {
    if modelID.contains("-i2v") { return "i2v" }
    if modelID.contains("-r2v") { return "r2v" }
    return "t2v"
}

private func alibabaNativeBaseURL(_ baseURL: String) -> String {
    withoutTrailingSlash(baseURL)
        .replacingOccurrences(of: "/compatible-mode/v1", with: "")
}

private func alibabaVideoProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    if let nested = extraBody["alibaba"]?.objectValue {
        return nested
    }
    var output = extraBody
    output.removeValue(forKey: "alibaba")
    return output
}

private func alibabaVideoProviderOptions(from request: VideoGenerationRequest) throws -> [String: JSONValue] {
    var output = alibabaVideoProviderOptions(from: request.extraBody)
    if let value = request.providerOptions["alibaba"] {
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.alibaba", message: "Alibaba provider options must be an object.")
        }
        output.merge(try alibabaValidateVideoProviderOptions(nested)) { _, nested in nested }
    }
    return output
}

private func alibabaValidateVideoProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options {
        switch key {
        case "negativePrompt", "audioUrl":
            try alibabaRequireStringOrNull(value, argument: "providerOptions.alibaba.\(key)", label: key)
            if value != .null { output[key] = value }
        case "promptExtend", "watermark", "audio":
            try alibabaRequireBooleanOrNull(value, argument: "providerOptions.alibaba.\(key)", label: key)
            if value != .null { output[key] = value }
        case "shotType":
            try alibabaRequireEnumOrNull(value, argument: "providerOptions.alibaba.shotType", label: "shotType", allowed: ["single", "multi"])
            if value != .null { output[key] = value }
        case "referenceUrls":
            try alibabaRequireStringArrayOrNull(value, argument: "providerOptions.alibaba.referenceUrls", label: "referenceUrls")
            if value != .null { output[key] = value }
        case "pollIntervalMs", "pollTimeoutMs":
            try alibabaRequirePositiveNumberOrNull(value, argument: "providerOptions.alibaba.\(key)", label: key)
            if value != .null { output[key] = value }
        default:
            output[key] = value
        }
    }
    return output
}

private func alibabaRequireStringOrNull(_ value: JSONValue, argument: String, label: String) throws {
    guard value == .null || value.stringValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: "Alibaba \(label) must be a string or null.")
    }
}

private func alibabaRequireBooleanOrNull(_ value: JSONValue, argument: String, label: String) throws {
    guard value == .null || value.boolValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: "Alibaba \(label) must be a boolean or null.")
    }
}

private func alibabaRequirePositiveNumberOrNull(_ value: JSONValue, argument: String, label: String) throws {
    guard value != .null else { return }
    guard let number = value.doubleValue, number > 0 else {
        throw AIError.invalidArgument(argument: argument, message: "Alibaba \(label) must be a positive number or null.")
    }
}

private func alibabaRequireEnumOrNull(_ value: JSONValue, argument: String, label: String, allowed: Set<String>) throws {
    guard value != .null else { return }
    guard let string = value.stringValue, allowed.contains(string) else {
        throw AIError.invalidArgument(argument: argument, message: "Alibaba \(label) must be one of \(allowed.sorted().joined(separator: ", ")) or null.")
    }
}

private func alibabaRequireStringArrayOrNull(_ value: JSONValue, argument: String, label: String) throws {
    guard value != .null else { return }
    guard let array = value.arrayValue, array.allSatisfy({ $0.stringValue != nil }) else {
        throw AIError.invalidArgument(argument: argument, message: "Alibaba \(label) must be an array of strings or null.")
    }
}

private func alibabaVideoImageInput(from request: VideoGenerationRequest, options: [String: JSONValue]) -> JSONValue? {
    if let image = request.image {
        if let url = image.url {
            return .string(url)
        }
        if let data = image.data {
            return .string(data.base64EncodedString())
        }
    }
    let value = options["image"] ?? options["imageUrl"] ?? options["image_url"] ?? options["imgUrl"] ?? options["img_url"]
    if let object = value?.objectValue {
        return object["url"] ?? object["data"]
    }
    return value
}

private struct AlibabaPollResult {
    var raw: JSONValue
    var response: AIHTTPResponse
}

private func alibabaVideoWarnings(for request: VideoGenerationRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.aspectRatio != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "aspectRatio",
            message: "Alibaba video models use explicit size/resolution dimensions. Use the resolution option or providerOptions.alibaba for size control."
        ))
    }
    if request.fps != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "fps",
            message: "Alibaba video models do not support custom FPS."
        ))
    }
    if let count = request.count, count > 1 {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "n",
            message: "Alibaba video models only support generating 1 video per call."
        ))
    }
    return warnings
}

private func alibabaVideoProviderMetadata(taskID: String, raw: JSONValue, videoURL: String) -> [String: JSONValue] {
    var metadata: [String: JSONValue] = [
        "taskId": .string(taskID),
        "videoUrl": .string(videoURL)
    ]
    if let actualPrompt = raw["output"]?["actual_prompt"] {
        metadata["actualPrompt"] = actualPrompt
    }
    if let usage = raw["usage"] {
        var mappedUsage: [String: JSONValue] = [:]
        if let duration = usage["duration"] { mappedUsage["duration"] = duration }
        if let outputVideoDuration = usage["output_video_duration"] { mappedUsage["outputVideoDuration"] = outputVideoDuration }
        if let resolution = usage["SR"] { mappedUsage["resolution"] = resolution }
        if let size = usage["size"] { mappedUsage["size"] = size }
        if !mappedUsage.isEmpty {
            metadata["usage"] = .object(mappedUsage)
        }
    }
    return ["alibaba": .object(metadata)]
}

private func alibabaResolution(_ resolution: String) -> String {
    switch resolution {
    case "1280x720", "720x1280", "960x960", "1088x832", "832x1088":
        return "720P"
    case "1920x1080", "1080x1920", "1440x1440", "1632x1248", "1248x1632":
        return "1080P"
    case "832x480", "480x832", "624x624":
        return "480P"
    default:
        return resolution
    }
}

private func alibabaPollInterval(_ extraBody: [String: JSONValue]) -> UInt64 {
    guard let milliseconds = extraBody["pollIntervalMs"]?.doubleValue else { return 5_000_000_000 }
    return UInt64(max(milliseconds, 1) * 1_000_000)
}

private func alibabaPollTimeout(_ extraBody: [String: JSONValue]) -> UInt64 {
    guard let milliseconds = extraBody["pollTimeoutMs"]?.doubleValue else { return 600_000_000_000 }
    return UInt64(max(milliseconds, 1) * 1_000_000)
}

private func gcd(_ lhs: Int, _ rhs: Int) -> Int {
    var a = abs(lhs)
    var b = abs(rhs)
    while b != 0 {
        let next = a % b
        a = b
        b = next
    }
    return max(a, 1)
}

private func appendQueryItemIfMissing(url: String, name: String, value: String) -> String {
    guard var components = URLComponents(string: url) else { return url }
    var items = components.queryItems ?? []
    if !items.contains(where: { $0.name == name }) {
        items.append(URLQueryItem(name: name, value: value))
        components.queryItems = items
    }
    return components.url?.absoluteString ?? url
}

private struct MultipartResponsePart {
    var name: String?
    var fileName: String?
    var contentType: String?
    var body: Data
    var json: JSONValue?
}

private func parseMultipartResponse(_ response: AIHTTPResponse) throws -> [MultipartResponsePart] {
    guard let contentType = response.headers.first(where: { $0.key.caseInsensitiveCompare("content-type") == .orderedSame })?.value,
          let boundaryRange = contentType.range(of: "boundary=") else {
        throw AIError.invalidResponse(provider: "multipart", message: "Response missing multipart boundary.")
    }
    let boundary = String(contentType[boundaryRange.upperBound...])
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        .split(separator: ";", maxSplits: 1)
        .first
        .map(String.init) ?? ""
    let marker = Data("--\(boundary)".utf8)
    let delimiter = Data("\r\n\r\n".utf8)
    let lineBreak = Data("\r\n".utf8)
    let ranges = response.body.ranges(of: marker)
    guard ranges.count >= 2 else { return [] }

    return ranges.indices.dropLast().compactMap { index in
        var part = response.body[ranges[index].upperBound..<ranges[index + 1].lowerBound]
        if part.starts(with: lineBreak) {
            part.removeFirst(lineBreak.count)
        }
        if part.starts(with: Data("--".utf8)) {
            return nil
        }
        while part.last == 10 || part.last == 13 {
            part.removeLast()
        }
        guard let separator = part.range(of: delimiter) else { return nil }
        let headerData = part[part.startIndex..<separator.lowerBound]
        var bodyData = Data(part[separator.upperBound..<part.endIndex])
        if bodyData.count >= 2,
           bodyData[bodyData.count - 2] == 13,
           bodyData[bodyData.count - 1] == 10 {
            bodyData.removeLast(2)
        }
        let headerText = String(data: headerData, encoding: .utf8) ?? ""
        let headers = Dictionary(uniqueKeysWithValues: headerText.split(separator: "\r\n").compactMap { line -> (String, String)? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return (String(line[..<colon]).lowercased(), String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        })
        let disposition = headers["content-disposition"] ?? ""
        func dispositionValue(_ key: String) -> String? {
            disposition.components(separatedBy: ";").compactMap { part -> String? in
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("\(key)=") else { return nil }
                return trimmed.dropFirst("\(key)=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }.first
        }
        let name = dispositionValue("name")
        let fileName = dispositionValue("filename")
        let jsonData: Data
        if headers["content-type"]?.localizedCaseInsensitiveContains("json") == true,
           let text = String(data: bodyData, encoding: .utf8) {
            jsonData = Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        } else {
            jsonData = bodyData
        }
        let json = try? decodeJSONBody(jsonData)
        return MultipartResponsePart(name: name, fileName: fileName, contentType: headers["content-type"], body: bodyData, json: json)
    }
}

private func prodiaPrompt(from messages: [AIMessage]) -> String {
    let system = messages.first(where: { $0.role == .system })?.combinedText ?? ""
    let user = messages.reversed().first(where: { $0.role == .user })?.combinedText ?? ""
    if system.isEmpty { return user }
    if user.isEmpty { return system }
    return "\(system)\n\(user)"
}

private func prodiaInputImage(from messages: [AIMessage], transport: AITransport, abortSignal: AIAbortSignal?) async throws -> (data: Data, mimeType: String)? {
    guard let user = messages.reversed().first(where: { $0.role == .user }) else { return nil }
    for part in user.content {
        switch part {
        case let .data(mimeType, data) where topLevelMediaType(mimeType) == "image",
             let .file(mimeType, data, _) where topLevelMediaType(mimeType) == "image":
            return (data, prodiaResolvedImageMediaType(mediaType: mimeType, data: data))
        case let .imageURL(urlString):
            let response = try await downloadURL(urlString, transport: transport, abortSignal: abortSignal)
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: "prodia.language", response: response)
            }
            let mediaType = response.headers.first { $0.key.caseInsensitiveCompare("content-type") == .orderedSame }?.value ?? "image/png"
            return (response.body, prodiaResolvedImageMediaType(mediaType: mediaType, data: response.body))
        case .text, .data, .file, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
            continue
        }
    }
    return nil
}

private func prodiaVideoInputImage(from image: ImageInputFile, transport: AITransport, abortSignal: AIAbortSignal?) async throws -> (data: Data, mimeType: String) {
    if let data = image.data {
        let mediaType = image.mediaType ?? detectMediaType(data: data, topLevelType: "image") ?? "image/png"
        return (data, prodiaResolvedImageMediaType(mediaType: mediaType, data: data))
    }
    guard let url = image.url else {
        throw AIError.invalidArgument(argument: "image", message: "Prodia video image input requires data or URL.")
    }
    let response = try await downloadURL(url, transport: transport, abortSignal: abortSignal)
    guard (200..<300).contains(response.statusCode) else {
        throw httpStatusError(provider: "prodia.video", response: response)
    }
    let mediaType = image.mediaType
        ?? response.headers.first { $0.key.caseInsensitiveCompare("content-type") == .orderedSame }?.value
        ?? detectMediaType(data: response.body, topLevelType: "image")
        ?? "image/png"
    return (response.body, prodiaResolvedImageMediaType(mediaType: mediaType, data: response.body))
}

private func prodiaResolvedImageMediaType(mediaType: String, data: Data) -> String {
    if isFullMediaType(mediaType) {
        return mediaType
    }
    return detectMediaType(data: data, topLevelType: topLevelMediaType(mediaType)) ?? "image/png"
}

private func mediaExtension(_ mimeType: String) -> String {
    switch mimeType.lowercased() {
    case "image/jpeg", "image/jpg":
        return ".jpg"
    case "image/webp":
        return ".webp"
    case "image/png":
        return ".png"
    case "video/mp4":
        return ".mp4"
    default:
        return ""
    }
}

private extension Data {
    func ranges(of needle: Data) -> [Range<Data.Index>] {
        guard !needle.isEmpty else { return [] }
        var ranges: [Range<Data.Index>] = []
        var searchStart = startIndex
        while searchStart < endIndex,
              let range = self[searchStart..<endIndex].range(of: needle) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }
}

private func multipartRawValue(_ parts: [MultipartResponsePart]) -> JSONValue {
    .object([
        "parts": .array(parts.map { part in
            .object([
                "name": part.name.map(JSONValue.string),
                "fileName": part.fileName.map(JSONValue.string),
                "contentType": part.contentType.map(JSONValue.string),
                "base64": part.contentType?.hasPrefix("image/") == true || part.contentType?.hasPrefix("video/") == true ? .string(part.body.base64EncodedString()) : nil,
                "json": part.json
            ])
        })
    ])
}

private extension AIHTTPRequest {
    func withURL(_ url: URL) -> AIHTTPRequest {
        AIHTTPRequest(method: method, url: url, headers: headers, body: body, abortSignal: abortSignal)
    }
}
