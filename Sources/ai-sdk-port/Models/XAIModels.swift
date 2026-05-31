import Foundation

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
        let options = xaiProviderOptions(from: request.extraBody)
        let endpoint = request.files.isEmpty ? "/images/generations" : "/images/edits"
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "prompt": .string(request.prompt),
            "response_format": .string("b64_json")
        ]
        if let count = request.count { body["n"] = .number(Double(count)) }
        if let aspectRatio = options["aspectRatio"] ?? options["aspect_ratio"] {
            body["aspect_ratio"] = aspectRatio
        } else if let size = request.size, size.contains(":") {
            body["aspect_ratio"] = .string(size)
        }
        body.merge(xaiImageOptions(from: options)) { _, new in new }
        body.merge(xaiImageEditInputs(from: request.files)) { _, new in new }

        let raw = try await config.sendJSON(path: endpoint, modelID: modelID, body: .object(body), headers: request.headers)
        let data = raw["data"]?.arrayValue ?? []
        let urls = data.compactMap { $0["url"]?.stringValue }
        let base64Images: [String]
        let inlineImages = data.compactMap { $0["b64_json"]?.stringValue }
        if inlineImages.count == data.count {
            base64Images = inlineImages
        } else {
            base64Images = try await downloadXAIImages(urls: urls)
        }
        return ImageGenerationResult(
            urls: urls,
            base64Images: base64Images,
            rawValue: raw
        )
    }

    private func downloadXAIImages(urls: [String]) async throws -> [String] {
        var images: [String] = []
        for url in urls {
            let response = try await config.transport.send(AIHTTPRequest(method: "GET", url: try requireURL(url), headers: [:]))
            guard (200..<300).contains(response.statusCode) else {
                throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
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
        let options = xaiProviderOptions(from: request.extraBody)
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
        if let duration = request.durationSeconds, mode != "edit-video" {
            body["duration"] = .number(duration)
        }
        if let aspectRatio = request.aspectRatio, mode != "edit-video", mode != "extend-video" {
            body["aspect_ratio"] = .string(aspectRatio)
        }
        for (key, value) in options {
            switch key {
            case "mode", "pollIntervalMs", "pollTimeoutMs":
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

        let created = try await config.sendJSON(path: endpoint, modelID: modelID, body: .object(body), headers: request.headers)
        guard let requestID = created["request_id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "xAI video create response did not contain request_id.")
        }
        let raw = try await pollXAI(
            requestID: requestID,
            headers: request.headers,
            intervalNanoseconds: xaiPollInterval(options),
            timeoutNanoseconds: xaiPollTimeout(options)
        )
        guard raw["video"]?["respect_moderation"]?.boolValue != false else {
            throw AIError.invalidResponse(provider: providerID, message: "xAI video generation was blocked by moderation.")
        }
        guard let url = raw["video"]?["url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "xAI video status response did not contain video.url.")
        }
        return VideoGenerationResult(urls: [url], operationID: requestID, rawValue: raw)
    }

    private func pollXAI(requestID: String, headers: [String: String], intervalNanoseconds: UInt64, timeoutNanoseconds: UInt64) async throws -> JSONValue {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            try await Task.sleep(nanoseconds: intervalNanoseconds)
            let response = try await config.transport.send(AIHTTPRequest(
                method: "GET",
                url: try requireURL("\(withoutTrailingSlash(config.baseURL))/videos/\(requestID)"),
                headers: config.headers.mergingHeaders(headers)
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
            }
            let raw = try response.jsonValue()
            if raw["status"]?.stringValue == "done" || raw["video"]?["url"]?.stringValue != nil {
                return raw
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

private func xaiProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    if let nested = extraBody["xai"]?.objectValue {
        return nested
    }
    var output = extraBody
    output.removeValue(forKey: "xai")
    return output
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

private func xaiPollTimeout(_ extraBody: [String: JSONValue]) -> UInt64 {
    guard let milliseconds = extraBody["pollTimeoutMs"]?.doubleValue else { return 600_000_000_000 }
    return UInt64(milliseconds * 1_000_000)
}

private func xaiPollInterval(_ extraBody: [String: JSONValue]) -> UInt64 {
    guard let milliseconds = extraBody["pollIntervalMs"]?.doubleValue else { return 5_000_000_000 }
    return UInt64(max(milliseconds, 1) * 1_000_000.0)
}
