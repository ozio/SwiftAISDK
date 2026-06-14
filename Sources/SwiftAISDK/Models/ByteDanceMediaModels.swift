import Foundation

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

        let createResponse = try await config.transport.send(config.request(path: "/contents/generations/tasks", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal))
        guard (200..<300).contains(createResponse.statusCode) else {
            throw byteDanceHTTPStatusError(provider: providerID, response: createResponse)
        }
        let created = (json: try createResponse.jsonValue(), response: createResponse)
        guard let taskID = created.json["id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "No task ID returned from API")
        }
        let finalResponse = try await pollByteDance(
            taskID: taskID,
            headers: request.headers,
            intervalNanoseconds: byteDancePollInterval(options.known["pollIntervalMs"]),
            timeoutNanoseconds: byteDancePollTimeout(options.known["pollTimeoutMs"]),
            timeoutMilliseconds: byteDancePollTimeoutMilliseconds(options.known["pollTimeoutMs"]),
            abortSignal: request.abortSignal
        )
        let raw = finalResponse.raw
        guard let url = raw["content"]?["video_url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "No video URL in response")
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

    private func pollByteDance(taskID: String, headers: [String: String], intervalNanoseconds: UInt64, timeoutNanoseconds: UInt64, timeoutMilliseconds: Double, abortSignal: AIAbortSignal?) async throws -> (raw: JSONValue, response: AIHTTPResponse) {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            let response = try await config.transport.send(AIHTTPRequest(
                method: "GET",
                url: try requireURL("\(withoutTrailingSlash(config.baseURL))/contents/generations/tasks/\(taskID)"),
                headers: config.headers.mergingHeaders(headers),
                abortSignal: abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw byteDanceHTTPStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            switch raw["status"]?.stringValue {
            case "succeeded":
                return (raw, response)
            case "failed":
                throw AIError.invalidResponse(provider: providerID, message: "Video generation failed: \(byteDanceJSONString(raw))")
            default:
                if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                    throw AIError.invalidResponse(provider: providerID, message: "Video generation timed out after \(formatByteDanceMilliseconds(timeoutMilliseconds))ms")
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
        var imageContent: [String: JSONValue] = ["type": .string("image_url"), "image_url": .object(["url": .string(image)])]
        if known["lastFrameImage"] != nil {
            imageContent["role"] = .string("first_frame")
        }
        content.append(.object(imageContent))
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
    UInt64(byteDancePollTimeoutMilliseconds(value) * 1_000_000)
}

private func byteDancePollTimeoutMilliseconds(_ value: JSONValue?) -> Double {
    let milliseconds = value?.doubleValue ?? 300_000
    return max(milliseconds, 1)
}

private func formatByteDanceMilliseconds(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(value)
}

private func byteDanceHTTPStatusError(provider: String, response: AIHTTPResponse) -> AIError {
    let body = byteDanceErrorMessage(from: response.body) ?? response.bodyText
    guard !response.headers.isEmpty else {
        return .apiCall(provider: provider, statusCode: response.statusCode, body: body)
    }
    return .apiCall(provider: provider, statusCode: response.statusCode, body: body, headers: response.headers)
}

private func byteDanceErrorMessage(from data: Data) -> String? {
    guard let json = try? decodeJSONBody(data) else { return nil }
    return json["error"]?["message"]?.stringValue ?? json["message"]?.stringValue ?? "Unknown error"
}

private func byteDanceJSONString(_ value: JSONValue) -> String {
    guard let data = try? encodeJSONBody(value),
          let text = String(data: data, encoding: .utf8) else {
        return "\(value)"
    }
    return text
}
