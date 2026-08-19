import Foundation

public final class BlackForestLabsVideoModel: AsyncVideoModel, @unchecked Sendable {
    public let providerID = "black-forest-labs.video"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func startVideoGeneration(
        _ operationRequest: VideoGenerationOperationStartRequest
    ) async throws -> VideoGenerationOperationStartResult {
        let request = operationRequest.request
        let prepared = try blackForestLabsVideoRequest(request)
        let submitResponse = try await config.transport.send(config.request(
            path: "/\(modelID)",
            modelID: modelID,
            body: .object(prepared.body),
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(submitResponse.statusCode) else {
            throw blackForestLabsHTTPStatusError(provider: providerID, response: submitResponse)
        }

        let submit = try submitResponse.jsonValue()
        guard let requestID = submit["id"]?.stringValue,
              let pollingURL = submit["polling_url"]?.stringValue,
              blackForestLabsVideoIsURL(pollingURL) else {
            throw AIError.invalidResponse(
                provider: providerID,
                message: "Black Forest Labs video submit response did not contain a valid id and polling_url."
            )
        }

        let operation = BlackForestLabsVideoOperation(
            requestID: requestID,
            pollingURL: pollingURL,
            cost: blackForestLabsNonNull(submit["cost"]),
            inputMegapixels: blackForestLabsNonNull(submit["input_mp"]),
            outputMegapixels: blackForestLabsNonNull(submit["output_mp"])
        )
        return VideoGenerationOperationStartResult(
            operation: blackForestLabsVideoOperationJSON(operation),
            warnings: prepared.warnings,
            responseMetadata: AIResponseMetadata(
                timestamp: Date(),
                modelID: modelID,
                headers: submitResponse.headers
            )
        )
    }

    public func videoGenerationStatus(
        _ statusRequest: VideoGenerationOperationStatusRequest
    ) async throws -> VideoGenerationOperationStatusResult {
        let operation = try blackForestLabsVideoOperation(statusRequest.operation, providerID: providerID)
        let pollURL = appendQueryItemIfMissing(
            url: operation.pollingURL,
            name: "id",
            value: operation.requestID
        )
        let pollHeaders = blackForestLabsTrustedHeaders(
            for: pollURL,
            baseURL: config.baseURL,
            headers: config.headers.mergingHeaders(statusRequest.headers)
        )
        let response = try await downloadURL(
            pollURL,
            transport: config.transport,
            headers: pollHeaders,
            abortSignal: statusRequest.abortSignal,
            trustedOrigin: config.baseURL
        )
        guard (200..<300).contains(response.statusCode) else {
            throw blackForestLabsHTTPStatusError(provider: providerID, response: response)
        }

        let raw = try response.jsonValue()
        guard let status = raw["status"]?.stringValue ?? raw["state"]?.stringValue else {
            throw AIError.invalidResponse(
                provider: providerID,
                message: "Missing status in Black Forest Labs poll response"
            )
        }
        let responseMetadata = AIResponseMetadata(
            timestamp: Date(),
            modelID: modelID,
            headers: response.headers,
            body: raw
        )

        if status == "Ready" {
            guard let sample = raw["result"]?["sample"]?.stringValue,
                  blackForestLabsVideoIsURL(sample) else {
                throw AIError.invalidResponse(
                    provider: providerID,
                    message: "Black Forest Labs reported the video as Ready but returned no result.sample URL. Request id: \(operation.requestID)"
                )
            }
            return .completed(VideoGenerationResult(
                urls: [sample],
                operationID: operation.requestID,
                mediaType: "video/mp4",
                rawValue: raw,
                providerMetadata: blackForestLabsVideoProviderMetadata(
                    operation: operation,
                    poll: raw,
                    videoURL: sample
                ),
                responseMetadata: responseMetadata
            ))
        }

        if blackForestLabsVideoTerminalFailureStatuses.contains(status) {
            let details = blackForestLabsVideoPollDetails(raw["details"])
            return .failed(
                message: "Black Forest Labs video generation failed with status \"\(status)\"\(details.map { ": \($0)" } ?? ""). Request id: \(operation.requestID)",
                responseMetadata: responseMetadata
            )
        }

        return .pending(responseMetadata: responseMetadata)
    }

    public func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        let prepared = try blackForestLabsVideoRequest(request)
        let submitResponse = try await config.transport.send(config.request(
            path: "/\(modelID)",
            modelID: modelID,
            body: .object(prepared.body),
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(submitResponse.statusCode) else {
            throw blackForestLabsHTTPStatusError(provider: providerID, response: submitResponse)
        }

        let submit = try submitResponse.jsonValue()
        guard let requestID = submit["id"]?.stringValue,
              let pollingURL = submit["polling_url"]?.stringValue,
              blackForestLabsVideoIsURL(pollingURL) else {
            throw AIError.invalidResponse(
                provider: providerID,
                message: "Black Forest Labs video submit response did not contain a valid id and polling_url."
            )
        }

        let completed = try await pollBlackForestLabsVideo(
            operation: BlackForestLabsVideoOperation(
                requestID: requestID,
                pollingURL: pollingURL,
                cost: blackForestLabsNonNull(submit["cost"]),
                inputMegapixels: blackForestLabsNonNull(submit["input_mp"]),
                outputMegapixels: blackForestLabsNonNull(submit["output_mp"])
            ),
            requestHeaders: request.headers,
            pollIntervalMillis: prepared.pollIntervalMillis,
            pollTimeoutMillis: prepared.pollTimeoutMillis,
            abortSignal: request.abortSignal
        )

        return VideoGenerationResult(
            urls: [completed.videoURL],
            operationID: requestID,
            mediaType: "video/mp4",
            rawValue: completed.raw,
            warnings: prepared.warnings,
            providerMetadata: completed.providerMetadata,
            requestMetadata: videoGenerationRequestMetadata(request, body: .object(prepared.body)),
            responseMetadata: AIResponseMetadata(
                timestamp: Date(),
                modelID: modelID,
                headers: completed.response.headers
            )
        )
    }

    private func pollBlackForestLabsVideo(
        operation: BlackForestLabsVideoOperation,
        requestHeaders: [String: String],
        pollIntervalMillis: Int,
        pollTimeoutMillis: Int,
        abortSignal: AIAbortSignal?
    ) async throws -> BlackForestLabsVideoCompletion {
        let pollURL = appendQueryItemIfMissing(url: operation.pollingURL, name: "id", value: operation.requestID)
        let intervalNanoseconds = UInt64(pollIntervalMillis) * 1_000_000
        let timeoutNanoseconds = UInt64(pollTimeoutMillis) * 1_000_000
        let started = DispatchTime.now().uptimeNanoseconds

        while true {
            try await sleepWithAbortSignal(nanoseconds: intervalNanoseconds, abortSignal: abortSignal)
            if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                throw AIError.invalidResponse(
                    provider: providerID,
                    message: "Black Forest Labs video generation timed out after \(pollTimeoutMillis)ms. Request id: \(operation.requestID)"
                )
            }

            let pollHeaders = blackForestLabsTrustedHeaders(
                for: pollURL,
                baseURL: config.baseURL,
                headers: config.headers.mergingHeaders(requestHeaders)
            )
            let response = try await downloadURL(
                pollURL,
                transport: config.transport,
                headers: pollHeaders,
                abortSignal: abortSignal,
                trustedOrigin: config.baseURL
            )
            guard (200..<300).contains(response.statusCode) else {
                throw blackForestLabsHTTPStatusError(provider: providerID, response: response)
            }

            let raw = try response.jsonValue()
            guard let status = raw["status"]?.stringValue ?? raw["state"]?.stringValue else {
                throw AIError.invalidResponse(
                    provider: providerID,
                    message: "Missing status in Black Forest Labs poll response"
                )
            }

            if status == "Ready" {
                guard let sample = raw["result"]?["sample"]?.stringValue,
                      blackForestLabsVideoIsURL(sample) else {
                    throw AIError.invalidResponse(
                        provider: providerID,
                        message: "Black Forest Labs reported the video as Ready but returned no result.sample URL. Request id: \(operation.requestID)"
                    )
                }
                return BlackForestLabsVideoCompletion(
                    videoURL: sample,
                    raw: raw,
                    response: response,
                    providerMetadata: blackForestLabsVideoProviderMetadata(
                        operation: operation,
                        poll: raw,
                        videoURL: sample
                    )
                )
            }

            if blackForestLabsVideoTerminalFailureStatuses.contains(status) {
                let details = blackForestLabsVideoPollDetails(raw["details"])
                throw AIError.invalidResponse(
                    provider: providerID,
                    message: "Black Forest Labs video generation failed with status \"\(status)\"\(details.map { ": \($0)" } ?? ""). Request id: \(operation.requestID)"
                )
            }
        }
    }
}

private struct BlackForestLabsVideoOperation {
    var requestID: String
    var pollingURL: String
    var cost: JSONValue?
    var inputMegapixels: JSONValue?
    var outputMegapixels: JSONValue?
}

private func blackForestLabsVideoOperationJSON(_ operation: BlackForestLabsVideoOperation) -> JSONValue {
    .object([
        "requestId": .string(operation.requestID),
        "pollingUrl": .string(operation.pollingURL),
        "cost": operation.cost,
        "inputMegapixels": operation.inputMegapixels,
        "outputMegapixels": operation.outputMegapixels
    ])
}

private func blackForestLabsVideoOperation(
    _ value: JSONValue,
    providerID: String
) throws -> BlackForestLabsVideoOperation {
    guard let requestID = value["requestId"]?.stringValue,
          let pollingURL = value["pollingUrl"]?.stringValue,
          blackForestLabsVideoIsURL(pollingURL) else {
        throw AIError.invalidResponse(
            provider: providerID,
            message: "Black Forest Labs video operation did not contain a valid requestId and pollingUrl."
        )
    }
    return BlackForestLabsVideoOperation(
        requestID: requestID,
        pollingURL: pollingURL,
        cost: blackForestLabsNonNull(value["cost"]),
        inputMegapixels: blackForestLabsNonNull(value["inputMegapixels"]),
        outputMegapixels: blackForestLabsNonNull(value["outputMegapixels"])
    )
}

private struct BlackForestLabsVideoCompletion {
    var videoURL: String
    var raw: JSONValue
    var response: AIHTTPResponse
    var providerMetadata: [String: JSONValue]
}

private struct BlackForestLabsVideoPreparedRequest {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
    var pollIntervalMillis: Int
    var pollTimeoutMillis: Int
}

private struct BlackForestLabsVideoOptions {
    var resolution: String?
    var aspectRatio: String?
    var keyframes: JSONValue?
    var safetyTolerance: Int?
    var draft: Bool?
    var draftCache: String?
    var version: String?
    var pollIntervalMillis: Int?
    var pollTimeoutMillis: Int?
}

private let blackForestLabsVideoAspectRatios: Set<String> = [
    "21:9", "2:1", "16:9", "4:3", "1:1", "3:4", "9:16", "auto"
]
private let blackForestLabsVideoResolutions: Set<String> = ["hd", "fhd"]
private let blackForestLabsVideoTerminalFailureStatuses: Set<String> = [
    "Error", "Failed", "Request Moderated", "Content Moderated", "Task not found"
]

private func blackForestLabsVideoRequest(_ request: VideoGenerationRequest) throws -> BlackForestLabsVideoPreparedRequest {
    let options = try blackForestLabsVideoOptions(request)
    if options.draftCache != nil {
        return blackForestLabsDraftEnhanceRequest(request, options: options)
    }

    var warnings: [AIWarning] = []
    if request.fps != nil {
        warnings.append(bflVideoWarning(
            type: "unsupported",
            feature: "fps",
            message: "FLUX 3 video does not support a custom frame rate."
        ))
    }
    if request.seed != nil {
        warnings.append(bflVideoWarning(
            type: "unsupported",
            feature: "seed",
            message: "FLUX 3 video does not accept a seed."
        ))
    }
    if let count = request.count, count > 1 {
        warnings.append(bflSingleVideoWarning())
    }

    var resolution = options.resolution
    if let requestedResolution = request.resolution {
        let resolved = bflVideoResolution(requestedResolution)
        if let resolution {
            if resolved == nil {
                warnings.append(bflVideoWarning(
                    type: "unsupported",
                    feature: "resolution",
                    message: "Unrecognized resolution \"\(requestedResolution)\". FLUX 3 video supports \"hd\" and \"fhd\", so providerOptions.blackForestLabs.resolution (\"\(resolution)\") was used instead."
                ))
            }
        } else if let resolved {
            resolution = resolved.tier
            if resolved.derived {
                warnings.append(bflVideoWarning(
                    type: "compatibility",
                    feature: "resolution",
                    message: "FLUX 3 video renders at \"hd\" or \"fhd\"; the requested resolution \"\(requestedResolution)\" was mapped to \"\(resolved.tier)\"."
                ))
            }
        } else {
            warnings.append(bflVideoWarning(
                type: "unsupported",
                feature: "resolution",
                message: "Unrecognized resolution \"\(requestedResolution)\". FLUX 3 video supports \"hd\" and \"fhd\", or a {width}x{height} value to map onto one."
            ))
        }
    }

    var aspectRatio = options.aspectRatio
    if aspectRatio == nil, let requestedAspectRatio = request.aspectRatio {
        if blackForestLabsVideoAspectRatios.contains(requestedAspectRatio) {
            aspectRatio = requestedAspectRatio
        } else {
            warnings.append(bflVideoWarning(
                type: "unsupported",
                feature: "aspectRatio",
                message: "FLUX 3 video does not support the aspect ratio \"\(requestedAspectRatio)\". Using the provider default (auto)."
            ))
        }
    }

    let firstFrameImage = request.frameImages.first { $0.frameType == .firstFrame }?.image
    var firstFrame = firstFrameImage ?? request.image
    var lastFrame = request.frameImages.first { $0.frameType == .lastFrame }?.image

    if let file = firstFrame, let mediaType = bflVideoNonImageMediaType(file) {
        warnings.append(bflVideoWarning(
            type: "unsupported",
            feature: firstFrameImage == nil ? "image" : "frameImages",
            message: mediaType == "video"
                ? "FLUX 3 video does not accept a video as a keyframe. Pass it as an inputReference to continue from it instead."
                : "FLUX 3 video only accepts an image as a keyframe; the \"\(file.mediaType ?? mediaType)\" file was ignored."
        ))
        firstFrame = nil
    }

    if let file = lastFrame {
        if firstFrame == nil {
            warnings.append(bflVideoWarning(
                type: "unsupported",
                feature: "frameImages",
                message: "FLUX 3 video requires a first_frame when a last_frame is provided. The last_frame was ignored."
            ))
            lastFrame = nil
        } else if let mediaType = bflVideoNonImageMediaType(file) {
            warnings.append(bflVideoWarning(
                type: "unsupported",
                feature: "frameImages",
                message: mediaType == "video"
                    ? "FLUX 3 video does not accept a video as a keyframe. The last_frame video was ignored."
                    : "FLUX 3 video only accepts an image as a keyframe; the \"\(file.mediaType ?? mediaType)\" last_frame was ignored."
            ))
            lastFrame = nil
        }
    }

    var keyframes = options.keyframes
    if keyframes != nil {
        if firstFrame != nil || lastFrame != nil {
            warnings.append(bflVideoWarning(
                type: "unsupported",
                feature: request.frameImages.isEmpty ? "image" : "frameImages",
                message: "FLUX 3 video takes a single keyframe list. providerOptions.blackForestLabs.keyframes was used and the top-level frame images were ignored."
            ))
        }
    } else if let firstFrame {
        var values: [JSONValue] = [.string(bflVideoFileString(firstFrame))]
        if let lastFrame {
            values.append(.string(bflVideoFileString(lastFrame)))
        }
        keyframes = .array(values)
    }

    var referenceVideos: [ImageInputFile] = []
    for file in request.inputReferences {
        guard let mediaType = file.mediaType else {
            warnings.append(bflVideoWarning(
                type: "compatibility",
                feature: "inputReferences",
                message: "FLUX 3 video only accepts a video reference, so the reference with no mediaType was treated as the video to continue from. Pass { url, mediaType: \"video/mp4\" } to be explicit."
            ))
            referenceVideos.append(file)
            continue
        }

        switch topLevelMediaType(mediaType.lowercased()) {
        case "video":
            referenceVideos.append(file)
        case "image":
            warnings.append(bflVideoWarning(
                type: "unsupported",
                feature: "inputReferences",
                message: "FLUX 3 video has no reference-image input. Pass images as `image`, `frameImages`, or providerOptions.blackForestLabs.keyframes instead. The reference was ignored."
            ))
        default:
            warnings.append(bflVideoWarning(
                type: "unsupported",
                feature: "inputReferences",
                message: "FLUX 3 video only accepts a video reference; the \"\(mediaType)\" reference was ignored."
            ))
        }
    }

    var startVideo: String?
    if !referenceVideos.isEmpty {
        if keyframes != nil {
            warnings.append(bflVideoWarning(
                type: "unsupported",
                feature: "inputReferences",
                message: "FLUX 3 video cannot combine keyframes with a video to continue from. The video reference was ignored."
            ))
        } else {
            startVideo = bflVideoFileString(referenceVideos[0])
            if referenceVideos.count > 1 {
                warnings.append(bflVideoWarning(
                    type: "unsupported",
                    feature: "inputReferences",
                    message: "FLUX 3 video continues from a single video. Only the first video reference was used."
                ))
            }
        }
    }

    var duration = request.durationSeconds
    if let requestedDuration = request.durationSeconds {
        if requestedDuration.rounded(.towardZero) != requestedDuration {
            duration = floor(requestedDuration + 0.5)
            warnings.append(bflVideoWarning(
                type: "unsupported",
                feature: "duration",
                message: "FLUX 3 video requires a whole number of seconds. The requested duration of \(formatDuration(requestedDuration)) was rounded to \(formatDuration(duration!))."
            ))
        }
        if duration! > 20 {
            duration = 20
            warnings.append(bflVideoWarning(
                type: "unsupported",
                feature: "duration",
                message: "FLUX 3 video supports at most 20 seconds. The requested duration of \(formatDuration(requestedDuration)) was clamped to 20."
            ))
        } else if duration! < 5 {
            duration = 5
            warnings.append(bflVideoWarning(
                type: "unsupported",
                feature: "duration",
                message: "FLUX 3 video requires at least 5 seconds. The requested duration of \(formatDuration(requestedDuration)) was clamped to 5."
            ))
        }
    }

    if duration == nil,
       let keyframeValues = keyframes?.arrayValue,
       keyframeValues.count >= 3,
       keyframeValues.allSatisfy({ $0.stringValue != nil }) {
        throw AIError.invalidArgument(
            argument: "duration",
            message: "FLUX 3 video requires an explicit duration when 3 or more keyframes are sent without a timestamp."
        )
    }

    let mode = keyframes != nil ? "i2v" : startVideo != nil ? "v2v" : "t2v"
    var body: [String: JSONValue] = [
        "mode": .string(mode),
        "prompt": .string(request.prompt)
    ]
    if let aspectRatio { body["aspect_ratio"] = .string(aspectRatio) }
    if let duration { body["duration"] = .number(duration) }
    if let resolution { body["resolution"] = .string(resolution) }
    if let version = options.version { body["version"] = .string(version) }
    if let generateAudio = request.generateAudio { body["generate_audio"] = .bool(generateAudio) }
    if let safetyTolerance = options.safetyTolerance { body["safety_tolerance"] = .number(Double(safetyTolerance)) }
    if let draft = options.draft { body["draft"] = .bool(draft) }
    if mode == "i2v", let keyframes { body["keyframes"] = keyframes }
    if mode == "v2v", let startVideo { body["start_video"] = .string(startVideo) }

    return BlackForestLabsVideoPreparedRequest(
        body: body,
        warnings: warnings,
        pollIntervalMillis: options.pollIntervalMillis ?? 2_000,
        pollTimeoutMillis: options.pollTimeoutMillis ?? 600_000
    )
}

private func blackForestLabsDraftEnhanceRequest(
    _ request: VideoGenerationRequest,
    options: BlackForestLabsVideoOptions
) -> BlackForestLabsVideoPreparedRequest {
    var warnings: [AIWarning] = []
    let pinnedFeatures: [(String, Bool)] = [
        ("prompt", !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
        ("aspectRatio", request.aspectRatio != nil || options.aspectRatio != nil),
        ("resolution", request.resolution != nil || options.resolution != nil),
        ("duration", request.durationSeconds != nil),
        ("fps", request.fps != nil),
        ("seed", request.seed != nil),
        ("generateAudio", request.generateAudio != nil),
        ("image", request.image != nil),
        ("frameImages", !request.frameImages.isEmpty),
        ("inputReferences", !request.inputReferences.isEmpty),
        ("keyframes", options.keyframes != nil),
        ("version", options.version != nil)
    ]
    for (feature, isSet) in pinnedFeatures where isSet {
        warnings.append(bflVideoWarning(
            type: "unsupported",
            feature: feature,
            message: "FLUX 3 draft enhance replays the draft bundle as it was generated, so \"\(feature)\" was ignored. Set it on the original draft request instead."
        ))
    }
    if options.draft != nil {
        warnings.append(bflVideoWarning(
            type: "unsupported",
            feature: "draft",
            message: "FLUX 3 draft enhance always renders at full quality. The draft option was ignored."
        ))
    }
    if let count = request.count, count > 1 {
        warnings.append(bflSingleVideoWarning())
    }

    var body: [String: JSONValue] = [
        "mode": .string("draft_enhance"),
        "draft_cache": .string(options.draftCache ?? "")
    ]
    if let safetyTolerance = options.safetyTolerance {
        body["safety_tolerance"] = .number(Double(safetyTolerance))
    }
    return BlackForestLabsVideoPreparedRequest(
        body: body,
        warnings: warnings,
        pollIntervalMillis: options.pollIntervalMillis ?? 2_000,
        pollTimeoutMillis: options.pollTimeoutMillis ?? 600_000
    )
}

private func blackForestLabsVideoOptions(_ request: VideoGenerationRequest) throws -> BlackForestLabsVideoOptions {
    var values = request.extraBody["blackForestLabs"]?.objectValue ?? request.extraBody
    values.removeValue(forKey: "blackForestLabs")
    if let providerValue = request.providerOptions["blackForestLabs"] {
        if providerValue != .null {
            guard let providerValues = providerValue.objectValue else {
                throw AIError.invalidArgument(
                    argument: "providerOptions.blackForestLabs",
                    message: "Black Forest Labs video provider options must be an object."
                )
            }
            values.merge(providerValues) { _, providerValue in providerValue }
        }
    }

    let resolution = try bflVideoOptionalString(
        values["resolution"],
        key: "resolution",
        allowed: blackForestLabsVideoResolutions
    )
    let aspectRatio = try bflVideoOptionalString(
        values["aspectRatio"],
        key: "aspectRatio",
        allowed: blackForestLabsVideoAspectRatios
    )
    let keyframes = try bflVideoKeyframes(values["keyframes"])
    let safetyTolerance = try bflVideoOptionalInteger(
        values["safetyTolerance"],
        key: "safetyTolerance",
        range: 0...4
    )
    let draft = try bflVideoOptionalBool(values["draft"], key: "draft")
    let draftCache = try bflVideoOptionalString(values["draftCache"], key: "draftCache")
    let version = try bflVideoOptionalString(values["version"], key: "version", allowed: ["latest"])
    let pollIntervalMillis = try bflVideoOptionalPositiveInteger(values["pollIntervalMillis"], key: "pollIntervalMillis")
    let pollTimeoutMillis = try bflVideoOptionalPositiveInteger(values["pollTimeoutMillis"], key: "pollTimeoutMillis")

    return BlackForestLabsVideoOptions(
        resolution: resolution,
        aspectRatio: aspectRatio,
        keyframes: keyframes,
        safetyTolerance: safetyTolerance,
        draft: draft,
        draftCache: draftCache,
        version: version,
        pollIntervalMillis: pollIntervalMillis,
        pollTimeoutMillis: pollTimeoutMillis
    )
}

private func bflVideoKeyframes(_ value: JSONValue?) throws -> JSONValue? {
    guard let value else { return nil }
    guard value != .null,
          let keyframes = value.arrayValue,
          (1...10).contains(keyframes.count) else {
        throw bflVideoInvalidOption("keyframes", "must contain between 1 and 10 entries")
    }
    if keyframes.allSatisfy({ $0.stringValue != nil }) {
        return value
    }

    var previousTimestamp: Double?
    for keyframe in keyframes {
        guard let pair = keyframe.arrayValue,
              pair.count == 2,
              let timestamp = pair[0].doubleValue,
              timestamp >= 0,
              timestamp <= 20,
              pair[1].stringValue != nil else {
            throw bflVideoInvalidOption("keyframes", "must be all URLs/base64 strings or all [timestamp, data] pairs")
        }
        if let previousTimestamp, timestamp <= previousTimestamp {
            throw bflVideoInvalidOption("keyframes", "timed keyframes must be in chronological order")
        }
        previousTimestamp = timestamp
    }
    return value
}

private func bflVideoOptionalString(_ value: JSONValue?, key: String, allowed: Set<String>? = nil) throws -> String? {
    guard let value else { return nil }
    guard value != .null, let string = value.stringValue, allowed?.contains(string) ?? true else {
        throw bflVideoInvalidOption(key, allowed.map { "must be one of \($0.sorted().joined(separator: ", "))" } ?? "must be a string")
    }
    return string
}

private func bflVideoOptionalBool(_ value: JSONValue?, key: String) throws -> Bool? {
    guard let value else { return nil }
    guard value != .null, let bool = value.boolValue else {
        throw bflVideoInvalidOption(key, "must be a boolean")
    }
    return bool
}

private func bflVideoOptionalInteger(_ value: JSONValue?, key: String, range: ClosedRange<Int>) throws -> Int? {
    guard let value else { return nil }
    guard value != .null,
          let number = value.doubleValue,
          number.isFinite,
          number.rounded(.towardZero) == number,
          range.contains(Int(number)) else {
        throw bflVideoInvalidOption(key, "must be an integer between \(range.lowerBound) and \(range.upperBound)")
    }
    return Int(number)
}

private func bflVideoOptionalPositiveInteger(_ value: JSONValue?, key: String) throws -> Int? {
    guard let value else { return nil }
    guard value != .null,
          let number = value.doubleValue,
          number.isFinite,
          number.rounded(.towardZero) == number,
          number > 0,
          number <= Double(Int.max) else {
        throw bflVideoInvalidOption(key, "must be a positive integer")
    }
    return Int(number)
}

private func bflVideoInvalidOption(_ key: String, _ message: String) -> AIError {
    .invalidArgument(
        argument: "providerOptions.blackForestLabs.\(key)",
        message: "Black Forest Labs video \(key) \(message)."
    )
}

private func bflVideoResolution(_ value: String) -> (tier: String, derived: Bool)? {
    let named = value.lowercased()
    if blackForestLabsVideoResolutions.contains(named) {
        return (named, false)
    }
    let parts = value.split(separator: "x", omittingEmptySubsequences: false)
    guard parts.count == 2,
          parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
          let width = Int(parts[0]),
          let height = Int(parts[1]) else {
        return nil
    }
    let shorterSide = min(width, height)
    return (shorterSide <= 720 ? "hd" : "fhd", shorterSide != 720 && shorterSide != 1080)
}

private func bflVideoNonImageMediaType(_ file: ImageInputFile) -> String? {
    guard let mediaType = file.mediaType else { return nil }
    let topLevel = topLevelMediaType(mediaType.lowercased())
    return topLevel == "image" ? nil : topLevel
}

private func bflVideoFileString(_ file: ImageInputFile) -> String {
    if let url = file.url { return url }
    return file.data?.base64EncodedString() ?? ""
}

private func blackForestLabsVideoProviderMetadata(
    operation: BlackForestLabsVideoOperation,
    poll: JSONValue,
    videoURL: String
) -> [String: JSONValue] {
    let settledCost = blackForestLabsNonNull(poll["cost"]) ?? operation.cost
    let metadata: JSONValue = .object([
        "id": .string(operation.requestID),
        "videoUrl": .string(videoURL),
        "seed": blackForestLabsNonNull(poll["result"]?["seed"]),
        "start_time": blackForestLabsNonNull(poll["result"]?["start_time"]),
        "end_time": blackForestLabsNonNull(poll["result"]?["end_time"]),
        "duration": blackForestLabsNonNull(poll["result"]?["duration"]),
        "draftCache": blackForestLabsNonNull(poll["result"]?["draft_cache"]),
        "cost": settledCost,
        "inputMegapixels": operation.inputMegapixels,
        "outputMegapixels": operation.outputMegapixels
    ])
    return [
        "blackForestLabs": .object([
            "videos": .array([metadata])
        ])
    ]
}

private func blackForestLabsVideoPollDetails(_ value: JSONValue?) -> String? {
    guard let value, value != .null else { return nil }
    if let string = value.stringValue { return string }
    guard let data = try? encodeJSONBody(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

private func blackForestLabsVideoIsURL(_ value: String) -> Bool {
    guard let components = URLComponents(string: value),
          let scheme = components.scheme?.lowercased(),
          ["http", "https"].contains(scheme),
          components.host != nil else {
        return false
    }
    return true
}

private func bflVideoWarning(type: String, feature: String, message: String) -> AIWarning {
    AIWarning(type: type, feature: feature, message: message)
}

private func bflSingleVideoWarning() -> AIWarning {
    bflVideoWarning(
        type: "unsupported",
        feature: "n",
        message: "FLUX 3 video generates a single video per call. Only 1 video will be generated."
    )
}
