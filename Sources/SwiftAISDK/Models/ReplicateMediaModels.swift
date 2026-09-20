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
        let pollingOptions = try replicateImagePollingOptions(from: options)
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
        let httpResponse = try await config.transport.send(config.request(
            path: path,
            modelID: modelID,
            body: .object(body),
            headers: request.headers.mergingHeaders(replicatePreferHeaders(from: options)),
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw replicateHTTPStatusError(provider: providerID, response: httpResponse)
        }
        let response = (json: try httpResponse.jsonValue(), response: httpResponse)
        let prediction = try await pollReplicateImagePrediction(
            response.json,
            headers: request.headers,
            intervalMilliseconds: pollingOptions.intervalMilliseconds,
            maxAttempts: pollingOptions.maxAttempts,
            abortSignal: request.abortSignal
        )
        let raw = prediction.json
        guard raw["output"] != nil, raw["output"] != .null else {
            throw AIError.invalidResponse(provider: providerID, message: "Replicate image generation completed without output.")
        }
        let urls = mediaURLs(from: raw["output"])
        let base64Images = try await downloadReplicateImages(urls: urls, abortSignal: request.abortSignal)
        return ImageGenerationResult(
            urls: urls,
            base64Images: base64Images,
            rawValue: raw,
            warnings: preparedInputs.warnings,
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    private func pollReplicateImagePrediction(
        _ initialPrediction: JSONValue,
        headers requestHeaders: [String: String],
        intervalMilliseconds: Int,
        maxAttempts: Int,
        abortSignal: AIAbortSignal?
    ) async throws -> (json: JSONValue, response: AIHTTPResponse?) {
        guard maxAttempts > 0 else {
            throw AIError.invalidArgument(
                argument: "providerOptions.replicate.maxPollAttempts",
                message: "Replicate maxPollAttempts must be a positive integer or null."
            )
        }
        var prediction = try replicateValidatedImagePrediction(initialPrediction, providerID: providerID)
        var pollResponse: AIHTTPResponse?
        let safeIntervalMilliseconds = max(intervalMilliseconds, 1)

        for attempt in 0..<maxAttempts {
            if try replicateCompletedImagePrediction(prediction, providerID: providerID) {
                return (prediction, pollResponse)
            }
            guard let pollURL = prediction["urls"]?["get"]?.stringValue, !pollURL.isEmpty else {
                throw AIError.invalidResponse(provider: providerID, message: "Replicate image prediction is pending but missing urls.get.")
            }
            let response = try await downloadURL(
                pollURL,
                transport: config.transport,
                headers: config.headers.mergingHeaders(requestHeaders),
                abortSignal: abortSignal,
                trustedOrigin: config.baseURL,
                credentialedOrigin: config.baseURL
            )
            guard (200..<300).contains(response.statusCode) else {
                throw replicateHTTPStatusError(provider: providerID, response: response)
            }
            prediction = try replicateValidatedImagePrediction(response.jsonValue(), providerID: providerID)
            pollResponse = response
            if attempt < maxAttempts - 1 {
                try await delay(safeIntervalMilliseconds, abortSignal: abortSignal)
            }
        }

        if try replicateCompletedImagePrediction(prediction, providerID: providerID) {
            return (prediction, pollResponse)
        }
        throw AIError.invalidResponse(
            provider: providerID,
            message: "Replicate image generation did not complete after \(maxAttempts) polling attempts."
        )
    }

    private func downloadReplicateImages(urls: [String], abortSignal: AIAbortSignal?) async throws -> [String] {
        var images: [String] = []
        for url in urls {
            let response = try await downloadURL(url, transport: config.transport, abortSignal: abortSignal)
            guard (200..<300).contains(response.statusCode) else {
                throw replicateHTTPStatusError(provider: providerID, response: response)
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
        let createHTTPResponse = try await config.transport.send(config.request(
            path: path,
            modelID: modelID,
            body: .object(body),
            headers: request.headers.mergingHeaders(replicatePreferHeaders(from: options)),
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(createHTTPResponse.statusCode) else {
            throw replicateHTTPStatusError(provider: providerID, response: createHTTPResponse)
        }
        let createResponse = (json: try createHTTPResponse.jsonValue(), response: createHTTPResponse)
        let finalResponse = try await pollReplicatePredictionResponse(
            createResponse.json,
            initialResponse: createResponse.response,
            intervalNanoseconds: replicatePollInterval(from: options),
            timeoutNanoseconds: replicatePollTimeout(from: options),
            abortSignal: request.abortSignal
        )
        let raw = finalResponse.json
        switch raw["status"]?.stringValue {
        case "failed":
            throw AIError.invalidResponse(provider: providerID, message: "Video generation failed: \(raw["error"]?.stringValue ?? "Unknown error")")
        case "canceled":
            throw AIError.invalidResponse(provider: providerID, message: "Video generation was canceled")
        default:
            break
        }
        if mediaURLs(from: raw["output"]).isEmpty {
            throw AIError.invalidResponse(provider: providerID, message: "No video URL in response")
        }
        return VideoGenerationResult(
            urls: mediaURLs(from: raw["output"]),
            operationID: raw["id"]?.stringValue,
            mediaType: "video/mp4",
            rawValue: raw,
            providerMetadata: replicateVideoProviderMetadata(from: raw),
            requestMetadata: videoGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: finalResponse.response, modelID: modelID)
        )
    }

    private func pollReplicatePredictionResponse(_ initial: JSONValue, initialResponse: AIHTTPResponse, intervalNanoseconds: UInt64, timeoutNanoseconds: UInt64, abortSignal: AIAbortSignal?) async throws -> (json: JSONValue, response: AIHTTPResponse) {
        var prediction = initial
        var metadataResponse = initialResponse
        let started = DispatchTime.now().uptimeNanoseconds
        while ["starting", "processing"].contains(prediction["status"]?.stringValue ?? "") {
            guard let getURL = prediction["urls"]?["get"]?.stringValue else { break }
            if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                throw AIError.invalidResponse(provider: providerID, message: "Replicate video generation timed out.")
            }
            try await sleepWithAbortSignal(nanoseconds: intervalNanoseconds, abortSignal: abortSignal)
            let pollHeaders = isSameOrigin(getURL, config.baseURL) ? config.headers : [:]
            let response = try await downloadURL(getURL, transport: config.transport, headers: pollHeaders, abortSignal: abortSignal)
            guard (200..<300).contains(response.statusCode) else {
                throw replicateHTTPStatusError(provider: providerID, response: response)
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
    output.removeValue(forKey: "pollIntervalMillis")
    output.removeValue(forKey: "poll_interval_millis")
    output.removeValue(forKey: "maxPollAttempts")
    output.removeValue(forKey: "max_poll_attempts")
    return output
}

private struct ReplicateImagePollingOptions {
    var intervalMilliseconds: Int
    var maxAttempts: Int
}

private func replicateImagePollingOptions(from options: [String: JSONValue]) throws -> ReplicateImagePollingOptions {
    let intervalMilliseconds: Int
    if let resolved = replicateResolvedImagePollingOption(
        camelCaseKey: "pollIntervalMillis",
        snakeCaseKey: "poll_interval_millis",
        from: options
    ) {
        guard let number = resolved.value.doubleValue, number.isFinite, number >= 0 else {
            throw AIError.invalidArgument(
                argument: "providerOptions.replicate.\(resolved.key)",
                message: "Replicate \(resolved.key) must be a nonnegative finite number or null."
            )
        }
        let roundedMilliseconds = number.rounded(.up)
        intervalMilliseconds = roundedMilliseconds >= Double(Int.max)
            ? Int.max
            : max(Int(roundedMilliseconds), 1)
    } else {
        intervalMilliseconds = 500
    }

    let maxAttempts: Int
    if let resolved = replicateResolvedImagePollingOption(
        camelCaseKey: "maxPollAttempts",
        snakeCaseKey: "max_poll_attempts",
        from: options
    ) {
        guard let number = resolved.value.doubleValue,
              number.isFinite,
              number > 0,
              number.rounded() == number,
              let integer = Int(exactly: number) else {
            throw AIError.invalidArgument(
                argument: "providerOptions.replicate.\(resolved.key)",
                message: "Replicate \(resolved.key) must be a positive integer or null."
            )
        }
        maxAttempts = integer
    } else {
        maxAttempts = 240
    }

    return ReplicateImagePollingOptions(
        intervalMilliseconds: intervalMilliseconds,
        maxAttempts: maxAttempts
    )
}

private func replicateResolvedImagePollingOption(
    camelCaseKey: String,
    snakeCaseKey: String,
    from options: [String: JSONValue]
) -> (key: String, value: JSONValue)? {
    if let value = options[camelCaseKey], value != .null {
        return (camelCaseKey, value)
    }
    if let value = options[snakeCaseKey], value != .null {
        return (snakeCaseKey, value)
    }
    return nil
}

private func replicateCompletedImagePrediction(_ prediction: JSONValue, providerID: String) throws -> Bool {
    let status = prediction["status"]?.stringValue
    if let status, !["starting", "processing", "succeeded", "failed", "canceled"].contains(status) {
        throw AIError.invalidResponse(provider: providerID, message: "Replicate image prediction has invalid status: \(status)")
    }
    if status == "failed" || status == "canceled" {
        let detail = prediction["error"]?.stringValue ?? "Unknown error"
        throw AIError.invalidResponse(
            provider: providerID,
            message: "Replicate image generation \(status ?? "failed"): \(detail)"
        )
    }
    return prediction["output"] != nil && prediction["output"] != .null || status == "succeeded"
}

private func replicateValidatedImagePrediction(_ prediction: JSONValue, providerID: String) throws -> JSONValue {
    guard prediction.objectValue != nil,
          let status = prediction["status"]?.stringValue,
          ["starting", "processing", "succeeded", "failed", "canceled"].contains(status),
          let pollURL = prediction["urls"]?["get"]?.stringValue,
          !pollURL.isEmpty else {
        throw AIError.invalidResponse(provider: providerID, message: "Replicate image prediction response is invalid.")
    }
    if let output = prediction["output"], output != .null {
        if output.stringValue == nil {
            guard let values = output.arrayValue, values.allSatisfy({ $0.stringValue != nil }) else {
                throw AIError.invalidResponse(provider: providerID, message: "Replicate image prediction response is invalid.")
            }
        }
    }
    if let error = prediction["error"], error != .null, error.stringValue == nil {
        throw AIError.invalidResponse(provider: providerID, message: "Replicate image prediction response is invalid.")
    }
    return prediction
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
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.replicate", message: "Replicate provider options must be an object.")
        }
        output.merge(try validateProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

private func replicateHTTPStatusError(provider: String, response: AIHTTPResponse) -> AIError {
    let body = replicateErrorMessage(from: response.body) ?? response.bodyText
    guard !response.headers.isEmpty else {
        return .apiCall(provider: provider, statusCode: response.statusCode, body: body)
    }
    return .apiCall(
        provider: provider,
        statusCode: response.statusCode,
        body: body,
        headers: response.headers
    )
}

private func replicateErrorMessage(from data: Data) -> String? {
    guard let json = try? decodeJSONBody(data) else { return nil }
    return json["detail"]?.stringValue ?? json["error"]?.stringValue
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
        case "pollIntervalMillis", "maxPollAttempts":
            // Validate after merging extraBody and providerOptions so aliases use
            // the same precedence and cannot bypass the runtime constraints.
            break
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
    try convertImageModelFileToDataURI(file)
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
