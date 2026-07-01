import Foundation

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
        let options = try klingAIProviderOptions(from: request)
        let referenceImages = klingAIReferenceImages(from: request)
        let effectiveMode = mode == "i2v" && referenceImages != nil ? "mi2v" : mode
        let endpoint = klingEndpoint(effectiveMode)
        let warnings = klingAIWarnings(for: request, mode: mode, effectiveMode: effectiveMode, options: options, referenceImages: referenceImages)
        var body: [String: JSONValue] = [
            "model_name": .string(klingAPIModelName(modelID, mode: effectiveMode))
        ]
        if !request.prompt.isEmpty { body["prompt"] = .string(request.prompt) }
        if let aspectRatio = request.aspectRatio, effectiveMode == "t2v" || effectiveMode == "mi2v" {
            body["aspect_ratio"] = .string(aspectRatio)
        }
        if let duration = request.durationSeconds, effectiveMode != "motion-control" {
            body["duration"] = .string(formatDuration(duration))
        }
        body.merge(try klingAIOptions(from: options, mode: effectiveMode, request: request, referenceImages: referenceImages)) { _, new in new }

        let createResponse = try await config.transport.send(config.request(path: endpoint, modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal))
        guard (200..<300).contains(createResponse.statusCode) else {
            throw klingAIHTTPStatusError(provider: providerID, response: createResponse)
        }
        let created = (json: try createResponse.jsonValue(), response: createResponse)
        guard let taskID = created.json["data"]?["task_id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "No task_id returned from KlingAI API. Response: \(created.json)")
        }
        let finalResponse = try await pollKling(
            endpoint: endpoint,
            taskID: taskID,
            headers: request.headers,
            intervalNanoseconds: klingAIPollInterval(options.known["pollIntervalMs"]),
            timeoutNanoseconds: klingAIPollTimeout(options.known["pollTimeoutMs"]),
            timeoutMilliseconds: klingAIPollTimeoutMilliseconds(options.known["pollTimeoutMs"]),
            abortSignal: request.abortSignal
        )
        let raw = finalResponse.raw
        let videos = raw["data"]?["task_result"]?["videos"]?.arrayValue ?? []
        guard !videos.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No videos in response. Response: \(raw)")
        }
        let urls = videos.compactMap { $0["url"]?.stringValue }
        guard !urls.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No valid video URLs in response")
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

    private func pollKling(endpoint: String, taskID: String, headers: [String: String], intervalNanoseconds: UInt64, timeoutNanoseconds: UInt64, timeoutMilliseconds: Double, abortSignal: AIAbortSignal?) async throws -> (raw: JSONValue, response: AIHTTPResponse) {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            try await sleepWithAbortSignal(nanoseconds: intervalNanoseconds, abortSignal: abortSignal)
            if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                throw AIError.invalidResponse(provider: providerID, message: "Video generation timed out after \(formatKlingAIMilliseconds(timeoutMilliseconds))ms")
            }
            let response = try await config.transport.send(AIHTTPRequest(
                method: "GET",
                url: try requireURL("\(withoutTrailingSlash(config.baseURL))\(endpoint)/\(taskID)"),
                headers: config.headers.mergingHeaders(headers),
                abortSignal: abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw klingAIHTTPStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            switch raw["data"]?["task_status"]?.stringValue {
            case "succeed":
                return (raw, response)
            case "failed":
                throw AIError.invalidResponse(provider: providerID, message: "Video generation failed: \(raw["data"]?["task_status_msg"]?.stringValue ?? "Unknown error")")
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

private func klingAIOptions(from options: KlingAIResolvedOptions, mode: String, request: VideoGenerationRequest, referenceImages: [ImageInputFile]?) throws -> [String: JSONValue] {
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
        if let image = try klingAIStartImageInput(from: request) ?? klingAIImageInput(from: known) {
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
    } else if mode == "mi2v" {
        output["image_list"] = .array(try (referenceImages ?? []).map { reference in
            .object(["image": try klingAIImageInput(from: reference) ?? .null])
        })
        if let negativePrompt = known["negativePrompt"] { output["negative_prompt"] = negativePrompt }
        if let cfgScale = known["cfgScale"] { output["cfg_scale"] = cfgScale }
        if let mode = known["mode"] { output["mode"] = mode }
        if let watermarkEnabled = known["watermarkEnabled"] {
            output["watermark_info"] = .object(["enabled": watermarkEnabled])
        }
    } else {
        if mode == "i2v", let image = try klingAIStartImageInput(from: request) ?? klingAIImageInput(from: known) {
            output["image"] = image
        }
        klingAIMoveSharedOptions(known, to: &output)
        if mode == "i2v" {
            if let imageTail = try klingAIImageTailInput(from: request, options: known) { output["image_tail"] = imageTail }
            if let staticMask = known["staticMask"] { output["static_mask"] = staticMask }
            if let dynamicMasks = known["dynamicMasks"] { output["dynamic_masks"] = dynamicMasks }
            if let elementList = known["elementList"] { output["element_list"] = elementList }
        }
    }

    output.merge(options.passthrough) { _, new in new }
    return output
}

private func klingAIWarnings(for request: VideoGenerationRequest, mode: String, effectiveMode: String, options: KlingAIResolvedOptions, referenceImages: [ImageInputFile]?) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if mode == "t2v", klingAIHasStartImage(request) {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "image",
            message: "KlingAI text-to-video does not support image input. Use an image-to-video model instead."
        ))
    }
    if request.aspectRatio != nil, effectiveMode == "i2v" {
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
    if referenceImages != nil, effectiveMode != "mi2v" {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "inputReferences",
            message: "KlingAI only supports inputReferences (reference-to-video) on image-to-video models. The reference images were ignored."
        ))
    }
    if effectiveMode == "mi2v", klingAIHasStartImage(request) {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "frameImages",
            message: "KlingAI reference-to-video does not support a separate start frame. Provide all guidance images via inputReferences instead."
        ))
    }
    if effectiveMode == "mi2v", klingAIHasImageTail(request, options: options.known) {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "frameImages",
            message: "KlingAI reference-to-video does not support a last frame (image_tail). Provide all guidance images via inputReferences instead."
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

private func klingAIReferenceImages(from request: VideoGenerationRequest) -> [ImageInputFile]? {
    if !request.frameImages.isEmpty {
        return nil
    }
    return request.inputReferences.isEmpty ? nil : request.inputReferences
}

private func klingAIHasStartImage(_ request: VideoGenerationRequest) -> Bool {
    request.image != nil || request.frameImages.contains(where: { $0.frameType == .firstFrame })
}

private func klingAIHasImageTail(_ request: VideoGenerationRequest, options: [String: JSONValue]) -> Bool {
    request.frameImages.contains(where: { $0.frameType == .lastFrame }) || options["imageTail"] != nil
}

private func klingAIImageInput(from options: [String: JSONValue]) -> JSONValue? {
    let value = options["image"] ?? options["imageUrl"] ?? options["image_url"]
    if let object = value?.objectValue {
        return object["url"] ?? object["data"]
    }
    return value
}

private func klingAIStartImageInput(from request: VideoGenerationRequest) throws -> JSONValue? {
    if let firstFrame = request.frameImages.first(where: { $0.frameType == .firstFrame }) {
        return try klingAIImageInput(from: firstFrame.image)
    }
    return try klingAIImageInput(from: request.image)
}

private func klingAIImageTailInput(from request: VideoGenerationRequest, options: [String: JSONValue]) throws -> JSONValue? {
    if let lastFrame = request.frameImages.first(where: { $0.frameType == .lastFrame }) {
        return try klingAIImageInput(from: lastFrame.image)
    }
    return options["imageTail"]
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
    UInt64(klingAIPollTimeoutMilliseconds(value) * 1_000_000)
}

private func klingAIPollTimeoutMilliseconds(_ value: JSONValue?) -> Double {
    let milliseconds = value?.doubleValue ?? 600_000
    return max(milliseconds, 1)
}

private func formatKlingAIMilliseconds(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(value)
}

private func klingAIHTTPStatusError(provider: String, response: AIHTTPResponse) -> AIError {
    let body = klingAIErrorMessage(from: response.body) ?? response.bodyText
    guard !response.headers.isEmpty else {
        return .apiCall(provider: provider, statusCode: response.statusCode, body: body)
    }
    return .apiCall(provider: provider, statusCode: response.statusCode, body: body, headers: response.headers)
}

private func klingAIErrorMessage(from data: Data) -> String? {
    guard let json = try? decodeJSONBody(data) else { return nil }
    return json["message"]?.stringValue
}

private func klingMode(_ modelID: String) throws -> String {
    if modelID.hasSuffix("-motion-control") { return "motion-control" }
    if modelID.hasSuffix("-i2v") { return "i2v" }
    if modelID.hasSuffix("-t2v") { return "t2v" }
    throw AIError.unsupportedModel(provider: "klingai", capability: .video, modelID: modelID)
}

private func klingEndpoint(_ mode: String) -> String {
    switch mode {
    case "mi2v":
        return "/v1/videos/multi-image2video"
    case "i2v":
        return "/v1/videos/image2video"
    case "motion-control":
        return "/v1/videos/motion-control"
    default:
        return "/v1/videos/text2video"
    }
}

private func klingAPIModelName(_ modelID: String, mode: String) -> String {
    let suffix: String
    if mode == "motion-control" {
        suffix = "-motion-control"
    } else if mode == "mi2v" {
        suffix = "-i2v"
    } else {
        suffix = "-\(mode)"
    }
    let base = modelID.hasSuffix(suffix) ? String(modelID.dropLast(suffix.count)) : modelID
    let normalized = base.hasSuffix(".0") ? String(base.dropLast(2)) : base
    return normalized.replacingOccurrences(of: ".", with: "-")
}
