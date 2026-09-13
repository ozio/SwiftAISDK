import Foundation

public final class MiniMaxVideoModel: AsyncVideoModel, @unchecked Sendable {
    public let providerID = "minimax.video"
    public let modelID: String
    public let maxVideosPerCall = 1
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        let responseTimestamp = Date()
        let prepared = try prepareVideoRequest(request)
        let submission = try await submitVideoGeneration(
            prepared: prepared,
            request: request,
            webhookURL: nil
        )
        let final = try await poll(
            taskID: submission.taskID,
            requestHeaders: request.headers,
            intervalNanoseconds: prepared.options.pollIntervalNanoseconds,
            timeoutNanoseconds: prepared.options.pollTimeoutNanoseconds,
            timeoutMilliseconds: prepared.options.pollTimeoutMilliseconds,
            abortSignal: request.abortSignal
        )
        let resolvedInputs: JSONValue = .object([
            "imageCount": .number(Double(prepared.resolvedInputs.imageCount)),
            "referenceVideoUrls": .array(prepared.resolvedInputs.referenceVideoIndices.compactMap { index in
                guard request.inputReferences.indices.contains(index),
                      let url = request.inputReferences[index].url else { return nil }
                return .string(url)
            })
        ])
        return try completedVideoResult(
            taskID: submission.taskID,
            raw: final.raw,
            response: final.response,
            resolvedInputs: resolvedInputs,
            warnings: prepared.warnings,
            requestMetadata: videoGenerationRequestMetadata(request, body: .object(prepared.body)),
            responseTimestamp: responseTimestamp
        )
    }

    public func startVideoGeneration(
        _ operationRequest: VideoGenerationOperationStartRequest
    ) async throws -> VideoGenerationOperationStartResult {
        let request = operationRequest.request
        let prepared = try prepareVideoRequest(request)
        let submission = try await submitVideoGeneration(
            prepared: prepared,
            request: request,
            webhookURL: operationRequest.webhookURL
        )
        return VideoGenerationOperationStartResult(
            operation: [
                "taskId": .string(submission.taskID),
                "resolvedInputs": prepared.resolvedInputs.jsonValue
            ],
            warnings: prepared.warnings,
            responseMetadata: AIResponseMetadata(
                timestamp: submission.timestamp,
                modelID: modelID,
                headers: submission.response.headers
            )
        )
    }

    public func videoGenerationStatus(
        _ operationRequest: VideoGenerationOperationStatusRequest
    ) async throws -> VideoGenerationOperationStatusResult {
        let operation = try miniMaxVideoOperation(from: operationRequest.operation)
        let response = try await downloadURL(
            "\(withoutTrailingSlash(config.baseURL))/v2/query/video_generation/\(miniMaxVideoPathSegment(operation.taskID))",
            transport: config.transport,
            headers: config.headers.mergingHeaders(normalizeHeaders(operationRequest.headers)),
            abortSignal: operationRequest.abortSignal,
            trustedOrigin: config.baseURL,
            credentialedOrigin: config.baseURL
        )
        guard (200..<300).contains(response.statusCode) else {
            throw miniMaxVideoHTTPStatusError(response: response)
        }
        let raw = try response.jsonValue()
        let task = try miniMaxValidatedVideoTask(from: raw)
        let responseMetadata = AIResponseMetadata(
            timestamp: Date(),
            modelID: modelID,
            headers: response.headers
        )
        switch task?["status"]?.stringValue {
        case "succeeded":
            return .completed(try completedVideoResult(
                taskID: operation.taskID,
                raw: raw,
                response: response,
                resolvedInputs: operation.resolvedInputs.jsonValue,
                responseTimestamp: responseMetadata.timestamp
            ))
        case "failed":
            let message = task?["error"]?["message"]?.stringValue.map { ": \($0)" } ?? ""
            let code = miniMaxErrorCode(task?["error"]?["code"]).map { " (\($0))" } ?? ""
            return .failed(
                message: "MiniMax video generation failed\(message)\(code). Task ID: \(operation.taskID)",
                responseMetadata: responseMetadata
            )
        case "cancelled":
            return .failed(
                message: "MiniMax video generation was cancelled. Task ID: \(operation.taskID)",
                responseMetadata: responseMetadata
            )
        case "expired":
            return .failed(
                message: "MiniMax video generation request expired. Task ID: \(operation.taskID)",
                responseMetadata: responseMetadata
            )
        default:
            return .pending(responseMetadata: responseMetadata)
        }
    }

    private func submitVideoGeneration(
        prepared: MiniMaxPreparedVideoRequest,
        request: VideoGenerationRequest,
        webhookURL: String?
    ) async throws -> (taskID: String, response: AIHTTPResponse, timestamp: Date) {
        let timestamp = Date()
        var body = prepared.body
        if let webhookURL {
            // Applied after the provider body so the direct V4 argument wins.
            body["callback_url"] = .string(webhookURL)
        }
        let response = try await config.transport.send(config.request(
            path: "/v2/video_generation",
            modelID: modelID,
            body: .object(body),
            headers: normalizeHeaders(request.headers),
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw miniMaxVideoHTTPStatusError(response: response)
        }
        let raw = try response.jsonValue()
        guard let taskID = raw["task_id"]?.stringValue, !taskID.isEmpty else {
            throw AIError.invalidResponse(
                provider: providerID,
                message: "No task_id returned from the MiniMax API. Response: \(miniMaxJSONString(raw))"
            )
        }
        return (taskID, response, timestamp)
    }

    private func completedVideoResult(
        taskID: String,
        raw: JSONValue,
        response: AIHTTPResponse,
        resolvedInputs: JSONValue,
        warnings: [AIWarning] = [],
        requestMetadata: AIRequestMetadata = AIRequestMetadata(),
        responseTimestamp: Date? = nil
    ) throws -> VideoGenerationResult {
        let task = try miniMaxValidatedVideoTask(from: raw)
        guard let url = task?["content"]?["url"]?.stringValue, !url.isEmpty else {
            throw AIError.invalidResponse(
                provider: providerID,
                message: "MiniMax video generation completed but no video URL was returned. Task ID: \(taskID)"
            )
        }
        var metadata: [String: JSONValue] = [
            "taskId": .string(taskID),
            "videoUrl": .string(url),
            "resolvedInputs": resolvedInputs
        ]
        if let duration = task?["duration"] { metadata["duration"] = duration }
        if let ratio = task?["ratio"] { metadata["ratio"] = ratio }
        if let resolution = task?["resolution"] { metadata["resolution"] = resolution }
        if let usage = task?["usage"]?.objectValue {
            metadata["usage"] = .object([
                "totalSeconds": usage["total_seconds"],
                "inputSeconds": usage["input_seconds"],
                "outputSeconds": usage["output_seconds"]
            ])
        }
        return VideoGenerationResult(
            urls: [url],
            operationID: taskID,
            mediaType: "video/mp4",
            rawValue: raw,
            warnings: warnings,
            providerMetadata: ["minimax": .object(metadata)],
            requestMetadata: requestMetadata,
            responseMetadata: AIResponseMetadata(
                timestamp: responseTimestamp ?? Date(),
                modelID: modelID,
                headers: response.headers
            )
        )
    }

    private func prepareVideoRequest(_ request: VideoGenerationRequest) throws -> MiniMaxPreparedVideoRequest {
        let options = try miniMaxVideoOptions(from: request)
        var warnings = miniMaxVideoStandardWarnings(for: request, modelID: modelID)

        let resolutionSettings = miniMaxResolutionSettings(for: modelID)
        let supportedResolutionNames = resolutionSettings.supported.sorted().map { "\"\($0)\"" }.joined(separator: " or ")

        var resolution = options.resolution
        if let providerResolution = resolution,
           !resolutionSettings.supported.contains(providerResolution) {
            warnings.append(miniMaxUnsupported(
                "resolution",
                "\(modelID) supports \(supportedResolutionNames). The provider resolution \"\(providerResolution)\" was ignored."
            ))
            resolution = nil
        }
        if let requestedResolution = request.resolution {
            let mapped = miniMaxResolvedResolution(requestedResolution)
            if let providerResolution = resolution {
                if mapped == nil {
                    warnings.append(miniMaxUnsupported(
                        "resolution",
                        "Unrecognized resolution \"\(requestedResolution)\". \(modelID) supports \(supportedResolutionNames), so providerOptions.minimax.resolution (\"\(providerResolution)\") was used instead."
                    ))
                } else if mapped != providerResolution {
                    warnings.append(miniMaxUnsupported(
                        "resolution",
                        "The resolution \"\(requestedResolution)\" selects \(mapped!), but providerOptions.minimax.resolution (\"\(providerResolution)\") was used instead."
                    ))
                }
            } else if let mapped, resolutionSettings.supported.contains(mapped) {
                resolution = mapped
            } else {
                warnings.append(miniMaxUnsupported(
                    "resolution",
                    mapped == nil
                        ? "Unrecognized resolution \"\(requestedResolution)\". \(modelID) supports \(supportedResolutionNames)."
                        : "\(modelID) does not support the resolution \"\(mapped!)\". It supports \(supportedResolutionNames)."
                ))
            }
        }
        resolution = resolution ?? resolutionSettings.defaultResolution

        var content: [JSONValue] = [
            .object(["type": .string("text"), "text": .string(request.prompt)])
        ]
        var sentImageCount = 0
        var sentReferenceVideoIndices: [Int] = []

        let explicitFirstFrame = request.frameImages.first { $0.frameType == .firstFrame }?.image
        var firstFrame = explicitFirstFrame ?? request.image
        var lastFrame = request.frameImages.first { $0.frameType == .lastFrame }?.image

        if let frame = firstFrame, let mediaType = miniMaxNonImageFrameMediaType(frame) {
            warnings.append(miniMaxUnsupported(
                explicitFirstFrame == nil ? "image" : "frameImages",
                mediaType == "video"
                    ? "\(modelID) does not accept a video as a frame image. The video was ignored."
                    : "\(modelID) only accepts an image as a frame image; the \"\(frame.mediaType ?? mediaType)\" file was ignored."
            ))
            firstFrame = nil
        }

        if let frame = lastFrame {
            if firstFrame == nil {
                warnings.append(miniMaxUnsupported(
                    "frameImages",
                    "\(modelID) requires a first_frame when a last_frame is provided. The last_frame was ignored."
                ))
                lastFrame = nil
            } else if let mediaType = miniMaxNonImageFrameMediaType(frame) {
                warnings.append(miniMaxUnsupported(
                    "frameImages",
                    mediaType == "video"
                        ? "\(modelID) does not accept a video as a frame image. The last_frame video was ignored."
                        : "\(modelID) only accepts an image as a frame image; the \"\(frame.mediaType ?? mediaType)\" last_frame was ignored."
                ))
                lastFrame = nil
            }
        }

        let usesFrameImages = firstFrame != nil || lastFrame != nil
        let supportsReferences = modelID != "MiniMax-H3-Max"
        if !supportsReferences, !request.inputReferences.isEmpty {
            warnings.append(miniMaxUnsupported(
                "inputReferences",
                "MiniMax-H3-Max does not support reference-to-video inputs. The references were ignored."
            ))
        }
        if !supportsReferences, !options.referenceAudioURLs.isEmpty {
            warnings.append(miniMaxUnsupported(
                "referenceAudioUrls",
                "MiniMax-H3-Max does not support reference audio. The audio was ignored."
            ))
        }
        let usesReferences = supportsReferences && (!request.inputReferences.isEmpty || !options.referenceAudioURLs.isEmpty)

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
                    "\(modelID) cannot combine frame images with reference inputs. The references were ignored."
                ))
            }
        } else if usesReferences {
            var referenceImages: [ImageInputFile] = []
            var referenceVideos: [(index: Int, file: ImageInputFile)] = []

            for (index, file) in request.inputReferences.enumerated() {
                if let mediaType = file.mediaType {
                    switch topLevelMediaType(mediaType.lowercased()) {
                    case "image":
                        referenceImages.append(file)
                    case "video":
                        referenceVideos.append((index, file))
                    default:
                        warnings.append(miniMaxUnsupported(
                            "inputReferences",
                            "\(modelID) only accepts image and video references; the \"\(mediaType)\" reference was ignored. Pass reference audio via providerOptions.minimax.referenceAudioUrls."
                        ))
                    }
                } else {
                    warnings.append(miniMaxUnsupported(
                        "inputReferences",
                        "\(modelID) requires an explicit mediaType to route URL references as video or image. Pass { data: url, mediaType: \"video/mp4\" } for video references. The reference was treated as an image."
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
                    "\(modelID) accepts at most 9 reference images. Extra images were ignored."
                ))
            }

            for reference in referenceVideos.prefix(3) {
                let video = reference.file
                let url = try convertImageModelFileToDataURI(video)
                content.append(.object([
                    "type": .string("video_url"),
                    "video_url": .object(["url": .string(url)]),
                    "role": .string("reference_video")
                ]))
                if video.url != nil {
                    sentReferenceVideoIndices.append(reference.index)
                }
            }
            if referenceVideos.count > 3 {
                warnings.append(miniMaxUnsupported(
                    "inputReferences",
                    "\(modelID) accepts at most 3 reference videos. Extra videos were ignored."
                ))
            }

            if !options.referenceAudioURLs.isEmpty {
                if referenceImages.isEmpty && referenceVideos.isEmpty {
                    warnings.append(miniMaxUnsupported(
                        "referenceAudioUrls",
                        "\(modelID) reference audio must be paired with at least one reference image or video. The audio was ignored."
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
                            "\(modelID) accepts at most 3 reference audios. Extra audios were ignored."
                        ))
                    }
                }
            }
        }

        let isTextToVideo = content.count == 1
        var ratio = options.ratio
        if ratio == nil, let aspectRatio = request.aspectRatio {
            if miniMaxVideoRatios.contains(aspectRatio) {
                ratio = aspectRatio
            } else {
                warnings.append(miniMaxUnsupported(
                    "aspectRatio",
                    isTextToVideo
                        ? "\(modelID) does not support the aspect ratio \"\(aspectRatio)\". Using the default (16:9)."
                        : "\(modelID) does not support the aspect ratio \"\(aspectRatio)\". Using the provider default (adaptive)."
                ))
                if isTextToVideo {
                    ratio = "16:9"
                }
            }
        }
        if ratio == "adaptive", isTextToVideo {
            warnings.append(miniMaxUnsupported(
                "aspectRatio",
                "\(modelID) text-to-video does not support the adaptive aspect ratio. Using the default (16:9)."
            ))
            ratio = "16:9"
        }
        if usesFrameImages, ratio != nil {
            warnings.append(miniMaxUnsupported(
                "aspectRatio",
                "\(modelID) derives the aspect ratio from the frame image; the requested ratio was ignored."
            ))
            ratio = nil
        }
        if ratio == nil, isTextToVideo {
            ratio = "16:9"
        }

        let minimumDuration = modelID == "MiniMax-H3" ? 4.0 : 5.0
        var duration = request.durationSeconds ?? 5
        if let requestedDuration = request.durationSeconds {
            if requestedDuration.rounded(.towardZero) != requestedDuration {
                duration = floor(requestedDuration + 0.5)
                warnings.append(miniMaxUnsupported(
                    "duration",
                    "\(modelID) requires a whole number of seconds. The requested duration of \(miniMaxFormatNumber(requestedDuration)) was rounded to \(miniMaxFormatNumber(duration))."
                ))
            }
            if duration > 15 {
                warnings.append(miniMaxUnsupported(
                    "duration",
                    "\(modelID) supports at most 15 seconds. The requested duration of \(miniMaxFormatNumber(requestedDuration)) was clamped to 15."
                ))
                duration = 15
            } else if duration < minimumDuration {
                warnings.append(miniMaxUnsupported(
                    "duration",
                    "\(modelID) requires at least \(miniMaxFormatNumber(minimumDuration)) seconds. The requested duration of \(miniMaxFormatNumber(requestedDuration)) was clamped to \(miniMaxFormatNumber(minimumDuration))."
                ))
                duration = minimumDuration
            }
        }

        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "content": .array(content),
            "resolution": .string(resolution ?? resolutionSettings.defaultResolution),
            "duration": .number(duration)
        ]
        if let ratio { body["ratio"] = .string(ratio) }
        if let aigcWatermark = options.aigcWatermark {
            body["aigc_watermark"] = .bool(aigcWatermark)
        }
        return MiniMaxPreparedVideoRequest(
            body: body,
            warnings: warnings,
            options: options,
            resolvedInputs: MiniMaxResolvedVideoInputs(
                imageCount: sentImageCount,
                referenceVideoIndices: sentReferenceVideoIndices
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

            let response = try await downloadURL(
                "\(withoutTrailingSlash(config.baseURL))/v2/query/video_generation/\(miniMaxVideoPathSegment(taskID))",
                transport: config.transport,
                headers: config.headers.mergingHeaders(normalizeHeaders(requestHeaders)),
                abortSignal: abortSignal,
                trustedOrigin: config.baseURL,
                credentialedOrigin: config.baseURL
            )
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

private struct MiniMaxPreparedVideoRequest {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
    var options: MiniMaxVideoOptions
    var resolvedInputs: MiniMaxResolvedVideoInputs
}

private struct MiniMaxResolvedVideoInputs {
    var imageCount: Int
    var referenceVideoIndices: [Int]

    var jsonValue: JSONValue {
        .object([
            "imageCount": .number(Double(imageCount)),
            "referenceVideoIndices": .array(referenceVideoIndices.map { .number(Double($0)) })
        ])
    }
}

private struct MiniMaxVideoOperation {
    var taskID: String
    var resolvedInputs: MiniMaxResolvedVideoInputs
}

private func miniMaxVideoOperation(from value: JSONValue) throws -> MiniMaxVideoOperation {
    guard let operation = value.objectValue,
          let taskID = operation["taskId"]?.stringValue,
          !taskID.isEmpty,
          let resolved = operation["resolvedInputs"]?.objectValue,
          let imageCountNumber = resolved["imageCount"]?.doubleValue,
          imageCountNumber.isFinite,
          imageCountNumber.rounded(.towardZero) == imageCountNumber,
          imageCountNumber >= 0,
          imageCountNumber <= 9,
          let imageCount = Int(exactly: imageCountNumber),
          let indexValues = resolved["referenceVideoIndices"]?.arrayValue,
          indexValues.count <= 3 else {
        throw AIError.invalidArgument(
            argument: "operation",
            message: "MiniMax video operation must contain taskId and bounded resolved input metadata."
        )
    }
    var indices: [Int] = []
    indices.reserveCapacity(indexValues.count)
    for value in indexValues {
        guard let number = value.doubleValue,
              number.isFinite,
              number.rounded(.towardZero) == number,
              number >= 0,
              let index = Int(exactly: number) else {
            throw AIError.invalidArgument(
                argument: "operation.resolvedInputs.referenceVideoIndices",
                message: "MiniMax reference video indices must be non-negative integers."
            )
        }
        indices.append(index)
    }
    return MiniMaxVideoOperation(
        taskID: taskID,
        resolvedInputs: MiniMaxResolvedVideoInputs(
            imageCount: imageCount,
            referenceVideoIndices: indices
        )
    )
}

private func miniMaxVideoPathSegment(_ value: String) -> String {
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
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

private struct MiniMaxResolutionSettings {
    var supported: Set<String>
    var defaultResolution: String
}

private func miniMaxResolutionSettings(for modelID: String) -> MiniMaxResolutionSettings {
    switch modelID {
    case "MiniMax-H3":
        return MiniMaxResolutionSettings(supported: ["768P", "2K"], defaultResolution: "2K")
    case "MiniMax-H3-Max":
        return MiniMaxResolutionSettings(supported: ["480P", "768P"], defaultResolution: "768P")
    default:
        return MiniMaxResolutionSettings(supported: ["480P", "768P", "2K"], defaultResolution: "2K")
    }
}

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
        allowed: ["480P", "768P", "2K"],
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

private func miniMaxVideoStandardWarnings(for request: VideoGenerationRequest, modelID: String) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.fps != nil {
        warnings.append(miniMaxUnsupported("fps", "\(modelID) does not support a custom frame rate."))
    }
    if request.seed != nil {
        warnings.append(miniMaxUnsupported("seed", "\(modelID) does not support a seed."))
    }
    if let count = request.count, count > 1 {
        warnings.append(miniMaxUnsupported(
            "n",
            "\(modelID) generates a single video per call. Only 1 video will be generated."
        ))
    }
    if request.generateAudio != nil {
        warnings.append(miniMaxUnsupported(
            "generateAudio",
            "The \(modelID) API does not expose an audio parameter. The generateAudio option was ignored."
        ))
    }
    return warnings
}

private func miniMaxUnsupported(_ feature: String, _ message: String) -> AIWarning {
    AIWarning(type: "unsupported", feature: feature, message: message)
}

private func miniMaxResolvedResolution(_ resolution: String) -> String? {
    let named = resolution.uppercased()
    if ["480P", "768P", "2K"].contains(named) { return named }
    switch resolution {
    case "480x480", "1120x480", "854x480", "640x480", "480x854", "480x640":
        return "480P"
    case "768x768", "1792x768", "1366x768", "1024x768", "768x1366", "768x1024":
        return "768P"
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
