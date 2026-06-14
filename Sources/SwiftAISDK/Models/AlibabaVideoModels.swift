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
