import Foundation

public final class MiniMaxVideoModel: VideoModel, @unchecked Sendable {
    public let providerID = "minimax.video"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        let responseTimestamp = Date()
        let options = try miniMaxVideoOptions(from: request)
        var warnings = miniMaxVideoStandardWarnings(for: request)

        var resolution = options.resolution
        if let requestedResolution = request.resolution {
            let mapped = miniMaxResolvedResolution(requestedResolution)
            if let providerResolution = resolution {
                if mapped == nil {
                    warnings.append(miniMaxUnsupported(
                        "resolution",
                        "Unrecognized resolution \"\(requestedResolution)\". MiniMax-H3 only supports \"2K\", so providerOptions.minimax.resolution (\"\(providerResolution)\") was used instead."
                    ))
                }
            } else if let mapped {
                resolution = mapped
            } else {
                warnings.append(miniMaxUnsupported(
                    "resolution",
                    "Unrecognized resolution \"\(requestedResolution)\". MiniMax-H3 only supports \"2K\"."
                ))
            }
        }
        resolution = resolution ?? "2K"

        var content: [JSONValue] = [
            .object(["type": .string("text"), "text": .string(request.prompt)])
        ]
        var sentImageCount = 0
        var sentReferenceVideoURLs: [String] = []

        let explicitFirstFrame = request.frameImages.first { $0.frameType == .firstFrame }?.image
        var firstFrame = explicitFirstFrame ?? request.image
        var lastFrame = request.frameImages.first { $0.frameType == .lastFrame }?.image

        if let frame = firstFrame, let mediaType = miniMaxNonImageFrameMediaType(frame) {
            warnings.append(miniMaxUnsupported(
                explicitFirstFrame == nil ? "image" : "frameImages",
                mediaType == "video"
                    ? "MiniMax-H3 does not accept a video as a frame image. The video was ignored."
                    : "MiniMax-H3 only accepts an image as a frame image; the \"\(frame.mediaType ?? mediaType)\" file was ignored."
            ))
            firstFrame = nil
        }

        if let frame = lastFrame {
            if firstFrame == nil {
                warnings.append(miniMaxUnsupported(
                    "frameImages",
                    "MiniMax-H3 requires a first_frame when a last_frame is provided. The last_frame was ignored."
                ))
                lastFrame = nil
            } else if let mediaType = miniMaxNonImageFrameMediaType(frame) {
                warnings.append(miniMaxUnsupported(
                    "frameImages",
                    mediaType == "video"
                        ? "MiniMax-H3 does not accept a video as a frame image. The last_frame video was ignored."
                        : "MiniMax-H3 only accepts an image as a frame image; the \"\(frame.mediaType ?? mediaType)\" last_frame was ignored."
                ))
                lastFrame = nil
            }
        }

        let usesFrameImages = firstFrame != nil || lastFrame != nil
        let usesReferences = !request.inputReferences.isEmpty || !options.referenceAudioURLs.isEmpty

        if usesFrameImages {
            if let firstFrame {
                content.append(try miniMaxImageContent(firstFrame, role: "first_frame"))
                sentImageCount += 1
            }
            if let lastFrame {
                content.append(try miniMaxImageContent(lastFrame, role: "last_frame"))
                sentImageCount += 1
            }
            if usesReferences {
                warnings.append(miniMaxUnsupported(
                    "inputReferences",
                    "MiniMax-H3 cannot combine frame images with reference inputs. The references were ignored."
                ))
            }
        } else if usesReferences {
            var referenceImages: [ImageInputFile] = []
            var referenceVideos: [ImageInputFile] = []

            for file in request.inputReferences {
                if let mediaType = file.mediaType {
                    switch topLevelMediaType(mediaType.lowercased()) {
                    case "image":
                        referenceImages.append(file)
                    case "video":
                        referenceVideos.append(file)
                    default:
                        warnings.append(miniMaxUnsupported(
                            "inputReferences",
                            "MiniMax-H3 only accepts image and video references; the \"\(mediaType)\" reference was ignored. Pass reference audio via providerOptions.minimax.referenceAudioUrls."
                        ))
                    }
                } else {
                    warnings.append(miniMaxUnsupported(
                        "inputReferences",
                        "MiniMax-H3 requires an explicit mediaType to route URL references as video or image. Pass { data: url, mediaType: \"video/mp4\" } for video references. The reference was treated as an image."
                    ))
                    referenceImages.append(file)
                }
            }

            for image in referenceImages.prefix(9) {
                content.append(try miniMaxImageContent(image, role: "reference_image"))
                sentImageCount += 1
            }
            if referenceImages.count > 9 {
                warnings.append(miniMaxUnsupported(
                    "inputReferences",
                    "MiniMax-H3 accepts at most 9 reference images. Extra images were ignored."
                ))
            }

            for video in referenceVideos.prefix(3) {
                let url = try convertImageModelFileToDataURI(video)
                content.append(.object([
                    "type": .string("video_url"),
                    "video_url": .object(["url": .string(url)]),
                    "role": .string("reference_video")
                ]))
                if video.url != nil {
                    sentReferenceVideoURLs.append(url)
                }
            }
            if referenceVideos.count > 3 {
                warnings.append(miniMaxUnsupported(
                    "inputReferences",
                    "MiniMax-H3 accepts at most 3 reference videos. Extra videos were ignored."
                ))
            }

            if !options.referenceAudioURLs.isEmpty {
                if referenceImages.isEmpty && referenceVideos.isEmpty {
                    warnings.append(miniMaxUnsupported(
                        "referenceAudioUrls",
                        "MiniMax-H3 reference audio must be paired with at least one reference image or video. The audio was ignored."
                    ))
                } else {
                    for url in options.referenceAudioURLs.prefix(3) {
                        content.append(.object([
                            "type": .string("audio_url"),
                            "audio_url": .object(["url": .string(url)]),
                            "role": .string("reference_audio")
                        ]))
                    }
                    if options.referenceAudioURLs.count > 3 {
                        warnings.append(miniMaxUnsupported(
                            "referenceAudioUrls",
                            "MiniMax-H3 accepts at most 3 reference audios. Extra audios were ignored."
                        ))
                    }
                }
            }
        }

        var ratio = options.ratio
        if ratio == nil, let aspectRatio = request.aspectRatio {
            if miniMaxVideoRatios.contains(aspectRatio) {
                ratio = aspectRatio
            } else {
                warnings.append(miniMaxUnsupported(
                    "aspectRatio",
                    "MiniMax-H3 does not support the aspect ratio \"\(aspectRatio)\". Using the provider default (adaptive)."
                ))
            }
        }
        if usesFrameImages, ratio != nil {
            warnings.append(miniMaxUnsupported(
                "aspectRatio",
                "MiniMax-H3 derives the aspect ratio from the frame image; the requested ratio was ignored."
            ))
            ratio = nil
        }

        var duration = request.durationSeconds ?? 5
        if let requestedDuration = request.durationSeconds {
            if requestedDuration.rounded(.towardZero) != requestedDuration {
                duration = floor(requestedDuration + 0.5)
                warnings.append(miniMaxUnsupported(
                    "duration",
                    "MiniMax-H3 requires a whole number of seconds. The requested duration of \(miniMaxFormatNumber(requestedDuration)) was rounded to \(miniMaxFormatNumber(duration))."
                ))
            }
            if duration > 15 {
                warnings.append(miniMaxUnsupported(
                    "duration",
                    "MiniMax-H3 supports at most 15 seconds. The requested duration of \(miniMaxFormatNumber(requestedDuration)) was clamped to 15."
                ))
                duration = 15
            } else if duration < 5 {
                warnings.append(miniMaxUnsupported(
                    "duration",
                    "MiniMax-H3 requires at least 5 seconds. The requested duration of \(miniMaxFormatNumber(requestedDuration)) was clamped to 5."
                ))
                duration = 5
            }
        }

        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "content": .array(content),
            "resolution": .string(resolution ?? "2K"),
            "duration": .number(duration)
        ]
        if let ratio { body["ratio"] = .string(ratio) }
        if let aigcWatermark = options.aigcWatermark {
            body["aigc_watermark"] = .bool(aigcWatermark)
        }

        let createResponse = try await config.transport.send(config.request(
            path: "/v2/video_generation",
            modelID: modelID,
            body: .object(body),
            headers: normalizeHeaders(request.headers),
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(createResponse.statusCode) else {
            throw miniMaxVideoHTTPStatusError(response: createResponse)
        }
        let createJSON = try createResponse.jsonValue()
        guard let taskID = createJSON["task_id"]?.stringValue, !taskID.isEmpty else {
            throw AIError.invalidResponse(
                provider: providerID,
                message: "No task_id returned from the MiniMax API. Response: \(miniMaxJSONString(createJSON))"
            )
        }

        let final = try await poll(
            taskID: taskID,
            requestHeaders: request.headers,
            intervalNanoseconds: options.pollIntervalNanoseconds,
            timeoutNanoseconds: options.pollTimeoutNanoseconds,
            timeoutMilliseconds: options.pollTimeoutMilliseconds,
            abortSignal: request.abortSignal
        )
        let task = final.raw["task"]
        guard let url = task?["content"]?["url"]?.stringValue, !url.isEmpty else {
            throw AIError.invalidResponse(
                provider: providerID,
                message: "MiniMax video generation completed but no video URL was returned. Task ID: \(taskID)"
            )
        }

        var miniMaxMetadata: [String: JSONValue] = [
            "taskId": .string(taskID),
            "videoUrl": .string(url),
            "resolvedInputs": .object([
                "imageCount": .number(Double(sentImageCount)),
                "referenceVideoUrls": .array(sentReferenceVideoURLs)
            ])
        ]
        if let duration = task?["duration"] { miniMaxMetadata["duration"] = duration }
        if let ratio = task?["ratio"] { miniMaxMetadata["ratio"] = ratio }
        if let resolution = task?["resolution"] { miniMaxMetadata["resolution"] = resolution }
        if let usage = task?["usage"]?.objectValue {
            miniMaxMetadata["usage"] = .object([
                "totalSeconds": usage["total_seconds"],
                "inputSeconds": usage["input_seconds"],
                "outputSeconds": usage["output_seconds"]
            ])
        }

        return VideoGenerationResult(
            urls: [url],
            operationID: taskID,
            mediaType: "video/mp4",
            rawValue: final.raw,
            warnings: warnings,
            providerMetadata: ["minimax": .object(miniMaxMetadata)],
            requestMetadata: videoGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: AIResponseMetadata(
                timestamp: responseTimestamp,
                modelID: modelID,
                headers: final.response.headers
            )
        )
    }

    private func poll(
        taskID: String,
        requestHeaders: [String: String],
        intervalNanoseconds: UInt64,
        timeoutNanoseconds: UInt64,
        timeoutMilliseconds: Double,
        abortSignal: AIAbortSignal?
    ) async throws -> (raw: JSONValue, response: AIHTTPResponse) {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            try await sleepWithAbortSignal(nanoseconds: intervalNanoseconds, abortSignal: abortSignal)
            if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                throw AIError.invalidResponse(
                    provider: providerID,
                    message: "MiniMax video generation timed out after \(miniMaxFormatNumber(timeoutMilliseconds))ms. Task ID: \(taskID)"
                )
            }

            let response = try await config.transport.send(AIHTTPRequest(
                method: "GET",
                url: try requireURL("\(withoutTrailingSlash(config.baseURL))/v2/query/video_generation/\(taskID)"),
                headers: config.headers.mergingHeaders(normalizeHeaders(requestHeaders)),
                abortSignal: abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw miniMaxVideoHTTPStatusError(response: response)
            }
            let raw = try response.jsonValue()
            let task = try miniMaxValidatedVideoTask(from: raw)
            switch task?["status"]?.stringValue {
            case "succeeded":
                return (raw, response)
            case "failed":
                let message = task?["error"]?["message"]?.stringValue.map { ": \($0)" } ?? ""
                let code = miniMaxErrorCode(task?["error"]?["code"]).map { " (\($0))" } ?? ""
                throw AIError.invalidResponse(
                    provider: providerID,
                    message: "MiniMax video generation failed\(message)\(code). Task ID: \(taskID)"
                )
            case "cancelled":
                throw AIError.invalidResponse(
                    provider: providerID,
                    message: "MiniMax video generation was cancelled. Task ID: \(taskID)"
                )
            case "expired":
                throw AIError.invalidResponse(
                    provider: providerID,
                    message: "MiniMax video generation request expired. Task ID: \(taskID)"
                )
            default:
                continue
            }
        }
    }
}

private struct MiniMaxVideoOptions {
    var resolution: String?
    var ratio: String?
    var referenceAudioURLs: [String]
    var aigcWatermark: Bool?
    var pollIntervalMilliseconds: Double
    var pollTimeoutMilliseconds: Double

    var pollIntervalNanoseconds: UInt64 {
        UInt64(pollIntervalMilliseconds * 1_000_000)
    }

    var pollTimeoutNanoseconds: UInt64 {
        UInt64(pollTimeoutMilliseconds * 1_000_000)
    }
}

private let miniMaxVideoRatios: Set<String> = [
    "adaptive", "21:9", "16:9", "4:3", "1:1", "3:4", "9:16"
]

private let miniMaxVideoOptionKeys: Set<String> = [
    "resolution", "ratio", "referenceAudioUrls", "aigcWatermark", "pollIntervalMs", "pollTimeoutMs"
]

private func miniMaxVideoOptions(from request: VideoGenerationRequest) throws -> MiniMaxVideoOptions {
    var values: [String: JSONValue] = [:]
    if let extra = request.extraBody["minimax"] {
        guard let extra = extra.objectValue else {
            throw AIError.invalidArgument(argument: "extraBody.minimax", message: "MiniMax video options must be an object.")
        }
        values.merge(extra) { _, new in new }
    } else {
        for key in miniMaxVideoOptionKeys {
            if let value = request.extraBody[key] { values[key] = value }
        }
    }
    if let provider = request.providerOptions["minimax"], provider != .null {
        guard let provider = provider.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.minimax", message: "MiniMax video provider options must be an object.")
        }
        values.merge(provider) { _, new in new }
    }

    let resolution = try miniMaxOptionalEnum(
        values["resolution"],
        allowed: ["2K"],
        argument: "providerOptions.minimax.resolution"
    )
    let ratio = try miniMaxOptionalEnum(
        values["ratio"],
        allowed: miniMaxVideoRatios,
        argument: "providerOptions.minimax.ratio"
    )
    let referenceAudioURLs: [String]
    if let value = values["referenceAudioUrls"] {
        guard let array = value.arrayValue, array.allSatisfy({ $0.stringValue != nil }) else {
            throw AIError.invalidArgument(
                argument: "providerOptions.minimax.referenceAudioUrls",
                message: "referenceAudioUrls must be an array of strings."
            )
        }
        referenceAudioURLs = array.compactMap(\.stringValue)
    } else {
        referenceAudioURLs = []
    }
    let aigcWatermark: Bool?
    if let value = values["aigcWatermark"] {
        guard let bool = value.boolValue else {
            throw AIError.invalidArgument(
                argument: "providerOptions.minimax.aigcWatermark",
                message: "aigcWatermark must be a boolean."
            )
        }
        aigcWatermark = bool
    } else {
        aigcWatermark = nil
    }

    return MiniMaxVideoOptions(
        resolution: resolution,
        ratio: ratio,
        referenceAudioURLs: referenceAudioURLs,
        aigcWatermark: aigcWatermark,
        pollIntervalMilliseconds: try miniMaxPositiveIntegerMilliseconds(
            values["pollIntervalMs"],
            defaultValue: 10_000,
            argument: "providerOptions.minimax.pollIntervalMs"
        ),
        pollTimeoutMilliseconds: try miniMaxPositiveIntegerMilliseconds(
            values["pollTimeoutMs"],
            defaultValue: 600_000,
            argument: "providerOptions.minimax.pollTimeoutMs"
        )
    )
}

private func miniMaxOptionalEnum(_ value: JSONValue?, allowed: Set<String>, argument: String) throws -> String? {
    guard let value else { return nil }
    guard let string = value.stringValue, allowed.contains(string) else {
        throw AIError.invalidArgument(
            argument: argument,
            message: "Expected one of: \(allowed.sorted().joined(separator: ", "))."
        )
    }
    return string
}

private func miniMaxPositiveIntegerMilliseconds(_ value: JSONValue?, defaultValue: Double, argument: String) throws -> Double {
    guard let value else { return defaultValue }
    guard let number = value.doubleValue,
          number.isFinite,
          number > 0,
          number.rounded(.towardZero) == number,
          number <= Double(UInt64.max) / 1_000_000 else {
        throw AIError.invalidArgument(argument: argument, message: "Expected a positive integer.")
    }
    return number
}

private func miniMaxVideoStandardWarnings(for request: VideoGenerationRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.fps != nil {
        warnings.append(miniMaxUnsupported("fps", "MiniMax-H3 does not support a custom frame rate."))
    }
    if request.seed != nil {
        warnings.append(miniMaxUnsupported("seed", "MiniMax-H3 does not support a seed."))
    }
    if let count = request.count, count > 1 {
        warnings.append(miniMaxUnsupported(
            "n",
            "MiniMax-H3 generates a single video per call. Only 1 video will be generated."
        ))
    }
    if request.generateAudio != nil {
        warnings.append(miniMaxUnsupported(
            "generateAudio",
            "The MiniMax-H3 API does not expose an audio parameter. The generateAudio option was ignored."
        ))
    }
    return warnings
}

private func miniMaxUnsupported(_ feature: String, _ message: String) -> AIWarning {
    AIWarning(type: "unsupported", feature: feature, message: message)
}

private func miniMaxResolvedResolution(_ resolution: String) -> String? {
    if resolution.uppercased() == "2K" { return "2K" }
    switch resolution {
    case "2048x2048", "2560x1080", "2560x1440", "2048x1536", "1440x2560", "1536x2048":
        return "2K"
    default:
        return nil
    }
}

private func miniMaxNonImageFrameMediaType(_ file: ImageInputFile) -> String? {
    guard let mediaType = file.mediaType else { return nil }
    let topLevel = topLevelMediaType(mediaType.lowercased())
    return topLevel == "image" ? nil : topLevel
}

private func miniMaxImageContent(_ file: ImageInputFile, role: String) throws -> JSONValue {
    .object([
        "type": .string("image_url"),
        "image_url": .object(["url": .string(try convertImageModelFileToDataURI(file))]),
        "role": .string(role)
    ])
}

private func miniMaxVideoHTTPStatusError(response: AIHTTPResponse) -> AIError {
    let body: String
    if let json = try? response.jsonValue(), let message = json["error"]?["message"]?.stringValue {
        body = message
    } else {
        body = "MiniMax video generation error"
    }
    return .apiCall(
        provider: "minimax.video",
        statusCode: response.statusCode,
        body: body,
        headers: response.headers
    )
}

private func miniMaxValidatedVideoTask(from raw: JSONValue) throws -> JSONValue? {
    guard let task = raw["task"]?.objectValue else {
        throw AIError.invalidResponse(provider: "minimax.video", message: "MiniMax video status response did not contain task.")
    }

    try miniMaxValidateOptionalString(task["id"], path: "task.id")
    try miniMaxValidateOptionalString(task["status"], path: "task.status")
    try miniMaxValidateOptionalString(task["resolution"], path: "task.resolution")
    try miniMaxValidateOptionalNumber(task["duration"], path: "task.duration")
    try miniMaxValidateOptionalString(task["ratio"], path: "task.ratio")

    if let content = try miniMaxValidateOptionalObject(task["content"], path: "task.content") {
        try miniMaxValidateOptionalString(content["url"], path: "task.content.url")
    }
    if let usage = try miniMaxValidateOptionalObject(task["usage"], path: "task.usage") {
        try miniMaxValidateOptionalNumber(usage["total_seconds"], path: "task.usage.total_seconds")
        try miniMaxValidateOptionalNumber(usage["input_seconds"], path: "task.usage.input_seconds")
        try miniMaxValidateOptionalNumber(usage["output_seconds"], path: "task.usage.output_seconds")
    }
    if let error = try miniMaxValidateOptionalObject(task["error"], path: "task.error") {
        try miniMaxValidateOptionalStringOrNumber(error["code"], path: "task.error.code")
        try miniMaxValidateOptionalString(error["message"], path: "task.error.message")
    }

    return .object(task)
}

private func miniMaxValidateOptionalObject(_ value: JSONValue?, path: String) throws -> [String: JSONValue]? {
    guard let value, value != .null else { return nil }
    guard let object = value.objectValue else {
        throw miniMaxVideoSchemaError(path: path, expected: "an object or null")
    }
    return object
}

private func miniMaxValidateOptionalString(_ value: JSONValue?, path: String) throws {
    guard let value, value != .null else { return }
    guard value.stringValue != nil else {
        throw miniMaxVideoSchemaError(path: path, expected: "a string or null")
    }
}

private func miniMaxValidateOptionalNumber(_ value: JSONValue?, path: String) throws {
    guard let value, value != .null else { return }
    guard value.doubleValue != nil else {
        throw miniMaxVideoSchemaError(path: path, expected: "a number or null")
    }
}

private func miniMaxValidateOptionalStringOrNumber(_ value: JSONValue?, path: String) throws {
    guard let value, value != .null else { return }
    guard value.stringValue != nil || value.doubleValue != nil else {
        throw miniMaxVideoSchemaError(path: path, expected: "a string, number, or null")
    }
}

private func miniMaxVideoSchemaError(path: String, expected: String) -> AIError {
    .invalidResponse(
        provider: "minimax.video",
        message: "MiniMax video status response did not match the expected schema: \(path) must be \(expected)."
    )
}

private func miniMaxErrorCode(_ value: JSONValue?) -> String? {
    if let string = value?.stringValue { return string }
    if let number = value?.doubleValue { return miniMaxFormatNumber(number) }
    return nil
}

private func miniMaxFormatNumber(_ value: Double) -> String {
    value.rounded(.towardZero) == value ? String(format: "%.0f", value) : String(value)
}

private func miniMaxJSONString(_ value: JSONValue) -> String {
    guard let data = try? encodeJSONBody(value), let string = String(data: data, encoding: .utf8) else {
        return String(describing: value)
    }
    return string
}
