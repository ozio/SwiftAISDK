import Foundation

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
        let wan27 = alibabaIsWan27Model(modelID)
        let supportsRatio = wan27 && mode != "i2v"
        let options = try alibabaVideoProviderOptions(from: request)
        let warnings = alibabaVideoWarnings(for: request, mode: mode, modelID: modelID, options: options)
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
        if mode == "r2v" {
            if wan27 {
                if let media = try alibabaVideoMedia(from: request, options: options) {
                    input["media"] = media
                }
            } else if let referenceURLs = alibabaVideoReferenceURLs(from: request, options: options) {
                input["reference_urls"] = referenceURLs
            }
        }

        var parameters: [String: JSONValue] = [:]
        if let duration = request.durationSeconds { parameters["duration"] = .number(duration) }
        if let seed = request.seed {
            parameters["seed"] = .number(Double(seed))
        } else if let seed = options["seed"] {
            parameters["seed"] = seed
        }
        if let resolution = request.resolution ?? options["resolution"]?.stringValue {
            if mode == "i2v" || wan27 {
                let tier = alibabaResolution(resolution)
                if !wan27 || tier == "720P" || tier == "1080P" {
                    parameters["resolution"] = .string(tier)
                }
            } else {
                parameters["size"] = .string(resolution.replacingOccurrences(of: "x", with: "*"))
            }
        }
        if supportsRatio {
            let ratio = options["ratio"]?.stringValue
                ?? request.aspectRatio
                ?? request.resolution.flatMap(alibabaRatioFromResolution)
            if let ratio {
                parameters["ratio"] = .string(ratio)
            }
        }
        if let promptExtend = options["promptExtend"] ?? options["prompt_extend"] { parameters["prompt_extend"] = promptExtend }
        if let shotType = options["shotType"] ?? options["shot_type"], !wan27 { parameters["shot_type"] = shotType }
        if let watermark = options["watermark"] { parameters["watermark"] = watermark }
        if let audio = request.generateAudio.map(JSONValue.bool) ?? options["audio"], !wan27 { parameters["audio"] = audio }
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
            throw alibabaVideoHTTPStatusError(provider: providerID, response: createResponse)
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
                throw alibabaVideoHTTPStatusError(provider: providerID, response: response)
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

private func alibabaVideoMode(_ modelID: String) -> String {
    if modelID.contains("-i2v") { return "i2v" }
    if modelID.contains("-r2v") { return "r2v" }
    return "t2v"
}

private func alibabaIsWan27Model(_ modelID: String) -> Bool {
    modelID.hasPrefix("wan2.7")
}

func alibabaNativeBaseURL(_ baseURL: String) -> String {
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
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.alibaba", message: "Alibaba provider options must be an object.")
        }
        output.merge(try alibabaValidateVideoProviderOptions(nested)) { _, nested in nested }
    }
    return output
}

private func alibabaVideoHTTPStatusError(provider: String, response: AIHTTPResponse) -> AIError {
    let body = alibabaVideoErrorMessage(from: response.body) ?? response.bodyText
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

private func alibabaVideoErrorMessage(from data: Data) -> String? {
    guard let json = try? decodeJSONBody(data) else { return nil }
    return json["message"]?.stringValue ?? json["error"]?["message"]?.stringValue
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
        case "media":
            try alibabaRequireVideoMediaArrayOrNull(value, argument: "providerOptions.alibaba.media")
            if value != .null { output[key] = value }
        case "ratio":
            try alibabaRequireEnumOrNull(value, argument: "providerOptions.alibaba.ratio", label: "ratio", allowed: ["16:9", "9:16", "1:1", "4:3", "3:4"])
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

func alibabaRequireStringOrNull(_ value: JSONValue, argument: String, label: String) throws {
    guard value == .null || value.stringValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: "Alibaba \(label) must be a string or null.")
    }
}

func alibabaRequireBooleanOrNull(_ value: JSONValue, argument: String, label: String) throws {
    guard value == .null || value.boolValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: "Alibaba \(label) must be a boolean or null.")
    }
}

func alibabaRequirePositiveNumberOrNull(_ value: JSONValue, argument: String, label: String) throws {
    guard value != .null else { return }
    guard let number = value.doubleValue, number > 0 else {
        throw AIError.invalidArgument(argument: argument, message: "Alibaba \(label) must be a positive number or null.")
    }
}

func alibabaRequireEnumOrNull(_ value: JSONValue, argument: String, label: String, allowed: Set<String>) throws {
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

private func alibabaRequireVideoMediaArrayOrNull(_ value: JSONValue, argument: String) throws {
    guard value != .null else { return }
    guard let array = value.arrayValue else {
        throw AIError.invalidArgument(argument: argument, message: "Alibaba media must be an array of media objects or null.")
    }
    for (index, item) in array.enumerated() {
        guard let object = item.objectValue else {
            throw AIError.invalidArgument(argument: "\(argument)[\(index)]", message: "Alibaba media item must be an object.")
        }
        guard let type = object["type"], type != .null else {
            throw AIError.invalidArgument(argument: "\(argument)[\(index)].type", message: "Alibaba media.type must be one of first_frame, reference_image, reference_video.")
        }
        try alibabaRequireEnumOrNull(type, argument: "\(argument)[\(index)].type", label: "media.type", allowed: ["reference_image", "reference_video", "first_frame"])
        guard let url = object["url"], url != .null else {
            throw AIError.invalidArgument(argument: "\(argument)[\(index)].url", message: "Alibaba media.url must be a string.")
        }
        try alibabaRequireStringOrNull(url, argument: "\(argument)[\(index)].url", label: "media.url")
        if let referenceVoice = object["referenceVoice"] ?? object["reference_voice"] {
            try alibabaRequireStringOrNull(referenceVoice, argument: "\(argument)[\(index)].referenceVoice", label: "media.referenceVoice")
        }
    }
}

private func alibabaVideoImageInput(from request: VideoGenerationRequest, options: [String: JSONValue]) -> JSONValue? {
    if let firstFrame = request.frameImages.first(where: { $0.frameType == .firstFrame }) {
        return alibabaVideoImageString(firstFrame.image)
    }
    if let image = request.image {
        return alibabaVideoImageString(image)
    }
    let value = options["image"] ?? options["imageUrl"] ?? options["image_url"] ?? options["imgUrl"] ?? options["img_url"]
    if let object = value?.objectValue {
        return object["url"] ?? object["data"]
    }
    return value
}

private func alibabaVideoImageString(_ image: ImageInputFile) -> JSONValue? {
    if let url = image.url {
        return .string(url)
    }
    if let data = image.data {
        return .string(data.base64EncodedString())
    }
    return nil
}

private func alibabaVideoMedia(from request: VideoGenerationRequest, options: [String: JSONValue]) throws -> JSONValue? {
    if let media = options["media"]?.arrayValue, !media.isEmpty {
        return .array(media.map(alibabaNormalizeVideoMediaItem))
    }
    var media: [JSONValue] = []
    for reference in request.inputReferences {
        if let url = reference.url {
            media.append(.object([
                "type": .string(alibabaIsVideoURL(url) ? "reference_video" : "reference_image"),
                "url": .string(url)
            ]))
        } else if reference.mediaType?.lowercased().hasPrefix("image/") == true {
            media.append(.object([
                "type": .string("reference_image"),
                "url": .string(try convertImageModelFileToDataURI(reference))
            ]))
        }
    }
    if let firstFrame = request.frameImages.first(where: { $0.frameType == .firstFrame }) {
        media.append(.object([
            "type": .string("first_frame"),
            "url": .string(try convertImageModelFileToDataURI(firstFrame.image))
        ]))
    }
    return media.isEmpty ? nil : .array(media)
}

private func alibabaNormalizeVideoMediaItem(_ item: JSONValue) -> JSONValue {
    guard var object = item.objectValue else { return item }
    if let referenceVoice = object.removeValue(forKey: "referenceVoice") {
        object["reference_voice"] = referenceVoice
    }
    return .object(object)
}

private func alibabaIsVideoURL(_ url: String) -> Bool {
    let lower = url.lowercased()
    return lower.contains(".mp4") || lower.contains(".mov")
}

private func alibabaVideoReferenceURLs(from request: VideoGenerationRequest, options: [String: JSONValue]) -> JSONValue? {
    if !request.frameImages.isEmpty {
        return nil
    }
    if !request.inputReferences.isEmpty {
        let urls = request.inputReferences.compactMap(\.url)
        return urls.isEmpty ? nil : .array(urls.map { .string($0) })
    }
    return options["referenceUrls"] ?? options["reference_urls"]
}

private struct AlibabaPollResult {
    var raw: JSONValue
    var response: AIHTTPResponse
}

private func alibabaVideoWarnings(for request: VideoGenerationRequest, mode: String, modelID: String, options: [String: JSONValue]) -> [AIWarning] {
    var warnings: [AIWarning] = []
    let wan27 = alibabaIsWan27Model(modelID)
    let supportsRatio = wan27 && mode != "i2v"
    if request.aspectRatio != nil, !supportsRatio {
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
    if request.frameImages.contains(where: { $0.frameType == .lastFrame }) {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "frameImages",
            message: "Alibaba video models do not support last_frame frameImages. The last_frame image will be ignored."
        ))
    }
    if wan27, let resolution = request.resolution {
        let tier = alibabaResolution(resolution)
        if tier != "720P", tier != "1080P" {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "resolution",
                message: "wan2.7 models only support 720P and 1080P resolutions. The resolution \"\(resolution)\" was ignored."
            ))
        }
    }
    if wan27, request.generateAudio != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "generateAudio",
            message: "wan2.7 models always generate audio. The audio option was ignored."
        ))
    }
    if wan27, let shotType = options["shotType"] ?? options["shot_type"], shotType != .null {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "shotType",
            message: "wan2.7 models do not support the shotType option. Describe the shot structure in the prompt instead."
        ))
    }
    if !request.inputReferences.isEmpty, mode != "r2v" {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "inputReferences",
            message: "Alibaba inputReferences are only supported by R2V video models."
        ))
    } else if mode == "r2v", !wan27, request.inputReferences.contains(where: { $0.url == nil }) {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "inputReferences",
            message: "Alibaba R2V inputReferences only support URL references. Non-URL references will be ignored."
        ))
    } else if mode == "r2v", wan27, request.inputReferences.contains(where: { $0.url == nil && $0.mediaType?.lowercased().hasPrefix("image/") != true }) {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "inputReferences",
            message: "Alibaba reference-to-video requires URL references for videos. Non-URL video reference was skipped."
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

private func alibabaRatioFromResolution(_ resolution: String) -> String? {
    let parts = resolution.split(separator: "x")
    guard parts.count == 2,
          let width = Int(parts[0]),
          let height = Int(parts[1]),
          width > 0,
          height > 0 else {
        return nil
    }
    func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a
        var b = b
        while b != 0 {
            let next = a % b
            a = b
            b = next
        }
        return a
    }
    let divisor = gcd(width, height)
    let ratio = "\(width / divisor):\(height / divisor)"
    return ["16:9", "9:16", "1:1", "4:3", "3:4"].contains(ratio) ? ratio : nil
}

private func alibabaPollInterval(_ extraBody: [String: JSONValue]) -> UInt64 {
    guard let milliseconds = extraBody["pollIntervalMs"]?.doubleValue else { return 5_000_000_000 }
    return UInt64(max(milliseconds, 1) * 1_000_000)
}

private func alibabaPollTimeout(_ extraBody: [String: JSONValue]) -> UInt64 {
    guard let milliseconds = extraBody["pollTimeoutMs"]?.doubleValue else { return 600_000_000_000 }
    return UInt64(max(milliseconds, 1) * 1_000_000)
}
