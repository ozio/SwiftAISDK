import Foundation

public enum XAITools {
    public static func codeExecution() -> JSONValue {
        providerTool(id: "xai.code_execution", name: "code_execution")
    }

    public static func fileSearch(vectorStoreIDs: [String], maxNumResults: Int? = nil) -> JSONValue {
        providerTool(id: "xai.file_search", name: "file_search", args: JSONValue.object([
            "vectorStoreIds": .array(vectorStoreIDs),
            "maxNumResults": maxNumResults.map { .number(Double($0)) }
        ]).objectValue ?? [:])
    }

    public static func mcpServer(
        serverURL: String,
        serverLabel: String? = nil,
        serverDescription: String? = nil,
        allowedTools: [String]? = nil,
        headers: JSONValue? = nil,
        authorization: String? = nil
    ) -> JSONValue {
        providerTool(id: "xai.mcp", name: "mcp", args: JSONValue.object([
            "serverUrl": .string(serverURL),
            "serverLabel": serverLabel.map(JSONValue.string),
            "serverDescription": serverDescription.map(JSONValue.string),
            "allowedTools": allowedTools.map { .array($0.map(JSONValue.string)) },
            "headers": headers,
            "authorization": authorization.map(JSONValue.string)
        ]).objectValue ?? [:])
    }

    public static func viewImage() -> JSONValue {
        providerTool(id: "xai.view_image", name: "view_image")
    }

    public static func viewXVideo() -> JSONValue {
        providerTool(id: "xai.view_x_video", name: "view_x_video")
    }

    public static func webSearch(
        allowedDomains: [String]? = nil,
        excludedDomains: [String]? = nil,
        enableImageSearch: Bool? = nil,
        enableImageUnderstanding: Bool? = nil
    ) -> JSONValue {
        providerTool(id: "xai.web_search", name: "web_search", args: JSONValue.object([
            "allowedDomains": allowedDomains.map { .array($0.map(JSONValue.string)) },
            "excludedDomains": excludedDomains.map { .array($0.map(JSONValue.string)) },
            "enableImageSearch": enableImageSearch.map(JSONValue.bool),
            "enableImageUnderstanding": enableImageUnderstanding.map(JSONValue.bool)
        ]).objectValue ?? [:])
    }

    public static func xSearch(
        allowedXHandles: [String]? = nil,
        excludedXHandles: [String]? = nil,
        fromDate: String? = nil,
        toDate: String? = nil,
        enableImageUnderstanding: Bool? = nil,
        enableVideoUnderstanding: Bool? = nil
    ) -> JSONValue {
        providerTool(id: "xai.x_search", name: "x_search", args: JSONValue.object([
            "allowedXHandles": allowedXHandles.map { .array($0.map(JSONValue.string)) },
            "excludedXHandles": excludedXHandles.map { .array($0.map(JSONValue.string)) },
            "fromDate": fromDate.map(JSONValue.string),
            "toDate": toDate.map(JSONValue.string),
            "enableImageUnderstanding": enableImageUnderstanding.map(JSONValue.bool),
            "enableVideoUnderstanding": enableVideoUnderstanding.map(JSONValue.bool)
        ]).objectValue ?? [:])
    }

    static func providerTool(id: String, name: String, args: [String: JSONValue] = [:]) -> JSONValue {
        .object([
            "type": .string("provider"),
            "id": .string(id),
            "name": .string(name),
            "args": .object(args)
        ])
    }
}

public final class XAIImageModel: ImageModel, @unchecked Sendable {
    public let providerID = "xai.image"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        if let count = request.count, count > 3 {
            throw AIError.invalidResponse(provider: providerID, message: "xAI supports at most 3 images per call.")
        }
        let options = xaiProviderOptions(providerOptions: request.providerOptions, extraBody: request.extraBody)
        let warnings = xaiImageWarnings(for: request)
        let endpoint = request.files.isEmpty ? "/images/generations" : "/images/edits"
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "prompt": .string(request.prompt),
            "response_format": .string("b64_json")
        ]
        if let count = request.count { body["n"] = .number(Double(count)) }
        if let aspectRatio = request.aspectRatio {
            body["aspect_ratio"] = .string(aspectRatio)
        } else if let aspectRatio = options["aspectRatio"] ?? options["aspect_ratio"] {
            body["aspect_ratio"] = aspectRatio
        }
        body.merge(xaiImageOptions(from: options)) { _, new in new }
        body.merge(xaiImageEditInputs(from: request.files)) { _, new in new }

        let response = try await config.sendJSONResponse(path: endpoint, modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let data = raw["data"]?.arrayValue ?? []
        let urls = data.compactMap { $0["url"]?.stringValue }
        let base64Images: [String]
        let inlineImages = data.compactMap { $0["b64_json"]?.stringValue }
        if inlineImages.count == data.count {
            base64Images = inlineImages
        } else {
            base64Images = try await downloadXAIImages(urls: urls, abortSignal: request.abortSignal)
        }
        return ImageGenerationResult(
            urls: urls,
            base64Images: base64Images,
            rawValue: raw,
            warnings: warnings,
            providerMetadata: xaiImageProviderMetadata(from: raw),
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    private func downloadXAIImages(urls: [String], abortSignal: AIAbortSignal?) async throws -> [String] {
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

public final class XAIVideoModel: VideoModel, @unchecked Sendable {
    public let providerID = "xai.video"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        let options = xaiProviderOptions(providerOptions: request.providerOptions, extraBody: request.extraBody)
        let mode = xaiVideoMode(from: options)
        let endpoint: String
        if mode == "edit-video" {
            endpoint = "/videos/edits"
        } else if mode == "extend-video" {
            endpoint = "/videos/extensions"
        } else {
            endpoint = "/videos/generations"
        }

        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "prompt": .string(request.prompt)
        ]
        var warnings = xaiVideoWarnings(for: request, options: options, mode: mode)
        if let duration = request.durationSeconds, mode != "edit-video" {
            body["duration"] = .number(duration)
        }
        if let aspectRatio = request.aspectRatio, mode != "edit-video", mode != "extend-video" {
            body["aspect_ratio"] = .string(aspectRatio)
        }
        if mode != "edit-video", mode != "extend-video" {
            if let resolution = options["resolution"] {
                body["resolution"] = resolution
            } else if let resolution = request.resolution {
                if let mapped = xaiVideoResolutionMap[resolution] {
                    body["resolution"] = .string(mapped)
                } else {
                    warnings.append(AIWarning(
                        type: "unsupported",
                        feature: "resolution",
                        message: "Unrecognized resolution \"\(resolution)\". Use providerOptions.xai.resolution with \"480p\" or \"720p\" instead."
                    ))
                }
            }
        }
        for (key, value) in options {
            switch key {
            case "mode", "pollIntervalMs", "pollTimeoutMs", "resolution":
                continue
            case "videoUrl", "video_url":
                body["video"] = .object(["url": value])
            case "referenceImageUrls", "reference_image_urls":
                body["reference_images"] = .array(value.arrayValue?.compactMap { item in
                    item.stringValue.map { .object(["url": .string($0)]) }
                } ?? [])
            case "image", "imageUrl", "image_url":
                continue
            default:
                body[key] = value
            }
        }
        if let image = xaiVideoImageInput(from: options), body["image"] == nil {
            body["image"] = .object(["url": image])
        }
        if let image = request.image, body["image"] == nil {
            body["image"] = .object(["url": .string(xaiImageFileURL(image))])
        }

        let created = try await config.sendJSON(path: endpoint, modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        guard let requestID = created["request_id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "xAI video create response did not contain request_id.")
        }
        let finalResponse = try await pollXAIResponse(
            requestID: requestID,
            headers: request.headers,
            intervalNanoseconds: xaiPollInterval(options),
            timeoutNanoseconds: xaiPollTimeout(options),
            abortSignal: request.abortSignal
        )
        let raw = finalResponse.json
        guard raw["video"]?["respect_moderation"]?.boolValue != false else {
            throw AIError.invalidResponse(provider: providerID, message: "xAI video generation was blocked by moderation.")
        }
        guard let url = raw["video"]?["url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "xAI video status response did not contain video.url.")
        }
        return VideoGenerationResult(
            urls: [url],
            operationID: requestID,
            rawValue: raw,
            warnings: warnings,
            providerMetadata: xaiVideoProviderMetadata(from: raw, requestID: requestID, url: url),
            requestMetadata: videoGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: finalResponse.response, modelID: modelID)
        )
    }

    private func pollXAIResponse(requestID: String, headers: [String: String], intervalNanoseconds: UInt64, timeoutNanoseconds: UInt64, abortSignal: AIAbortSignal?) async throws -> (json: JSONValue, response: AIHTTPResponse) {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            try await sleepWithAbortSignal(nanoseconds: intervalNanoseconds, abortSignal: abortSignal)
            let response = try await config.transport.send(AIHTTPRequest(
                method: "GET",
                url: try requireURL("\(withoutTrailingSlash(config.baseURL))/videos/\(requestID)"),
                headers: config.headers.mergingHeaders(headers),
                abortSignal: abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            if raw["status"]?.stringValue == "done" || raw["video"]?["url"]?.stringValue != nil {
                return (raw, response)
            }
            if ["expired", "failed"].contains(raw["status"]?.stringValue ?? "") {
                throw AIError.invalidResponse(provider: providerID, message: "xAI video generation \(raw["status"]?.stringValue ?? "failed").")
            }
            if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                throw AIError.invalidResponse(provider: providerID, message: "xAI video generation timed out.")
            }
        }
    }
}

private let xaiVideoResolutionMap = [
    "1280x720": "720p",
    "854x480": "480p",
    "640x480": "480p"
]

private func xaiProviderOptions(providerOptions: [String: JSONValue], extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "xai")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    if let nested = providerOptions["xai"]?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func xaiImageWarnings(for request: ImageGenerationRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.size != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "size",
            message: "This model does not support the `size` option. Use `aspectRatio` instead."
        ))
    }
    if request.seed != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "seed"))
    }
    if request.mask != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "mask"))
    }
    return warnings
}

private func xaiVideoWarnings(for request: VideoGenerationRequest, options: [String: JSONValue], mode: String?) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.fps != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "fps",
            message: "xAI video models do not support custom FPS."
        ))
    }
    if request.seed != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "seed",
            message: "xAI video models do not support seed."
        ))
    }
    if mode == "edit-video", request.durationSeconds != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "duration",
            message: "xAI video editing does not support custom duration."
        ))
    }
    if mode == "edit-video", request.aspectRatio != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "aspectRatio",
            message: "xAI video editing does not support custom aspect ratio."
        ))
    }
    if mode == "edit-video", request.resolution != nil || options["resolution"] != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "resolution",
            message: "xAI video editing does not support custom resolution."
        ))
    }
    if mode == "extend-video", request.aspectRatio != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "aspectRatio",
            message: "xAI video extension does not support custom aspect ratio."
        ))
    }
    if mode == "extend-video", request.resolution != nil || options["resolution"] != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "resolution",
            message: "xAI video extension does not support custom resolution."
        ))
    }
    return warnings
}

private func xaiImageOptions(from options: [String: JSONValue]) -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    if let outputFormat = options["outputFormat"] ?? options["output_format"] { output["output_format"] = outputFormat }
    if let syncMode = options["syncMode"] ?? options["sync_mode"] { output["sync_mode"] = syncMode }
    if let resolution = options["resolution"] { output["resolution"] = resolution }
    if let quality = options["quality"] { output["quality"] = quality }
    if let user = options["user"] { output["user"] = user }
    return output
}

private func xaiImageEditInputs(from files: [ImageInputFile]) -> [String: JSONValue] {
    let images = files.map { file -> JSONValue in
        .object([
            "url": .string(xaiImageFileURL(file)),
            "type": .string("image_url")
        ])
    }
    if images.count == 1 {
        return ["image": images[0]]
    }
    if images.count > 1 {
        return ["images": .array(images)]
    }
    return [:]
}

private func xaiImageFileURL(_ file: ImageInputFile) -> String {
    if let url = file.url {
        return url
    }
    guard let data = file.data else { return "" }
    let mediaType = file.mediaType ?? "image/png"
    return "data:\(mediaType);base64,\(data.base64EncodedString())"
}

private func xaiVideoImageInput(from options: [String: JSONValue]) -> JSONValue? {
    let value = options["image"] ?? options["imageUrl"] ?? options["image_url"]
    if let object = value?.objectValue {
        if let url = object["url"] {
            return url
        }
        if let data = object["data"] {
            let mediaType = object["mediaType"]?.stringValue ?? object["media_type"]?.stringValue ?? "image/png"
            return .string("data:\(mediaType);base64,\(data.stringValue ?? "")")
        }
    }
    return value
}

private func xaiVideoMode(from extraBody: [String: JSONValue]) -> String? {
    if let mode = extraBody["mode"]?.stringValue {
        return mode
    }
    if extraBody["videoUrl"]?.stringValue != nil || extraBody["video_url"]?.stringValue != nil {
        return "edit-video"
    }
    let references = extraBody["referenceImageUrls"]?.arrayValue ?? extraBody["reference_image_urls"]?.arrayValue
    if references?.isEmpty == false {
        return "reference-to-video"
    }
    return nil
}

private func xaiImageProviderMetadata(from raw: JSONValue) -> [String: JSONValue] {
    var metadata: [String: JSONValue] = [
        "images": .array((raw["data"]?.arrayValue ?? []).map { item in
            var image: [String: JSONValue] = [:]
            if let revisedPrompt = item["revised_prompt"]?.stringValue {
                image["revisedPrompt"] = .string(revisedPrompt)
            }
            return .object(image)
        })
    ]
    if let cost = raw["usage"]?["cost_in_usd_ticks"] {
        metadata["costInUsdTicks"] = cost
    }
    return ["xai": .object(metadata)]
}

private func xaiVideoProviderMetadata(from raw: JSONValue, requestID: String, url: String) -> [String: JSONValue] {
    var metadata: [String: JSONValue] = [
        "requestId": .string(requestID),
        "videoUrl": .string(url)
    ]
    if let duration = raw["video"]?["duration"] {
        metadata["duration"] = duration
    }
    if let cost = raw["usage"]?["cost_in_usd_ticks"] {
        metadata["costInUsdTicks"] = cost
    }
    if let progress = raw["progress"] {
        metadata["progress"] = progress
    }
    return ["xai": .object(metadata)]
}

private func xaiPollTimeout(_ extraBody: [String: JSONValue]) -> UInt64 {
    guard let milliseconds = extraBody["pollTimeoutMs"]?.doubleValue else { return 600_000_000_000 }
    return UInt64(milliseconds * 1_000_000)
}

private func xaiPollInterval(_ extraBody: [String: JSONValue]) -> UInt64 {
    guard let milliseconds = extraBody["pollIntervalMs"]?.doubleValue else { return 5_000_000_000 }
    return UInt64(max(milliseconds, 1) * 1_000_000.0)
}
